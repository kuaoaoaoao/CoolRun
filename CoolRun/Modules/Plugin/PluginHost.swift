import AppKit
import Foundation
import JavaScriptCore
import UserNotifications

// MARK: - 插件执行环境

/// 用系统自带的 JavaScriptCore 跑插件，不引入任何第三方依赖，也不增加包体积。
///
/// 每次调用工具都新建一个 `JSContext`，在后台线程里跑完就丢。插件很小，
/// 这点开销可以接受，换来的是不用维护常驻 JS 运行时、也不会因为某个插件
/// 的死循环拖垮主线程。
enum PluginHost {
    nonisolated static func callTool(
        manifest: PluginManifest,
        spec: PluginToolSpec,
        arguments: JSONValue,
        root: URL,
        lang: AppLanguage
    ) async -> ToolResult {
        await Task.detached(priority: .userInitiated) {
            run(manifest: manifest, spec: spec, arguments: arguments, root: root, lang: lang)
        }.value
    }

    // MARK: 同步执行

    private nonisolated static func run(
        manifest: PluginManifest,
        spec: PluginToolSpec,
        arguments: JSONValue,
        root: URL,
        lang: AppLanguage
    ) -> ToolResult {
        let scriptURL = root.appendingPathComponent(manifest.mainScript)
        guard let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            return .failure(
                LocalizedString.l(
                    lang,
                    en: "Cannot read the plugin script: \(manifest.mainScript)",
                    zh: "插件脚本读不到：\(manifest.mainScript)",
                    ja: "プラグインスクリプトを読み込めません：\(manifest.mainScript)",
                    ko: "플러그인 스크립트를 읽을 수 없습니다: \(manifest.mainScript)"
                )
            )
        }

        guard let context = JSContext() else {
            return .failure(
                LocalizedString.l(
                    lang,
                    en: "Cannot create a JavaScript runtime",
                    zh: "无法创建 JavaScript 运行时",
                    ja: "JavaScript ランタイムを作成できません",
                    ko: "JavaScript 런타임을 만들 수 없습니다"
                )
            )
        }

        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString() ?? LocalizedString.l(
                lang,
                en: "Unknown script error",
                zh: "未知脚本错误",
                ja: "不明なスクリプトエラー",
                ko: "알 수 없는 스크립트 오류"
            )
        }

        installAPI(in: context, manifest: manifest, root: root)

        context.evaluateScript(script)
        if let jsError {
            return .failure(
                LocalizedString.l(
                    lang,
                    en: "Plugin script error: \(jsError)",
                    zh: "插件脚本报错：\(jsError)",
                    ja: "プラグインスクリプトのエラー：\(jsError)",
                    ko: "플러그인 스크립트 오류: \(jsError)"
                )
            )
        }

        let argsJSON = arguments.compactJSONString()
        let call = "\(spec.handler)(\(argsJSON))"
        guard let value = context.evaluateScript(call) else {
            return .failure(
                LocalizedString.l(
                    lang,
                    en: "The plugin returned no result",
                    zh: "插件没有返回结果",
                    ja: "プラグインが結果を返しませんでした",
                    ko: "플러그인이 결과를 반환하지 않았습니다"
                )
            )
        }
        if let jsError {
            return .failure(
                LocalizedString.l(
                    lang,
                    en: "Plugin execution failed: \(jsError)",
                    zh: "插件执行失败：\(jsError)",
                    ja: "プラグインの実行に失敗しました：\(jsError)",
                    ko: "플러그인 실행 실패: \(jsError)"
                )
            )
        }
        if value.isUndefined || value.isNull {
            return .text(
                LocalizedString.l(
                    lang,
                    en: "The plugin finished without returning a value",
                    zh: "插件执行完成，没有返回值",
                    ja: "プラグインは値を返さずに完了しました",
                    ko: "플러그인이 값을 반환하지 않고 완료되었습니다"
                )
            )
        }

        return .text(value.toString() ?? "")
    }

    // MARK: 注入 coolrun API

    private nonisolated static func installAPI(in context: JSContext, manifest: PluginManifest, root: URL) {
        guard let coolrun = JSValue(newObjectIn: context) else { return }

        // log(msg)
        let logBlock: @convention(block) (String) -> Void = { message in
            NSLog("[plugin:%@] %@", manifest.id, message)
        }
        coolrun.setObject(unsafeBitCast(logBlock, to: AnyObject.self), forKeyedSubscript: "log")

        // storage.get / storage.set —— 存在插件目录下的 data.json
        let dataURL = root.appendingPathComponent("data.json")
        let storageBlock: @convention(block) (String) -> String = { key in
            guard let data = try? Data(contentsOf: dataURL),
                  let map = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                return ""
            }
            return map[key] ?? ""
        }
        let storeBlock: @convention(block) (String, String) -> Void = { key, value in
            var map: [String: String] = [:]
            if let data = try? Data(contentsOf: dataURL),
               let existing = try? JSONDecoder().decode([String: String].self, from: data) {
                map = existing
            }
            map[key] = value
            if let data = try? JSONEncoder().encode(map) {
                try? data.write(to: dataURL, options: .atomic)
            }
        }
        let storage = JSValue(newObjectIn: context)
        storage?.setObject(unsafeBitCast(storageBlock, to: AnyObject.self), forKeyedSubscript: "get")
        storage?.setObject(unsafeBitCast(storeBlock, to: AnyObject.self), forKeyedSubscript: "set")
        coolrun.setObject(storage, forKeyedSubscript: "storage")

        // 联网：同步阻塞，跑在后台线程，不卡 UI。
        if manifest.permissions.contains(.network) {
            let getBlock: @convention(block) (String) -> String = { urlString in
                httpGetSync(urlString)
            }
            coolrun.setObject(unsafeBitCast(getBlock, to: AnyObject.self), forKeyedSubscript: "httpGet")
        }

        // 通知 / 剪贴板：投递到主线程，不阻塞脚本。
        if manifest.permissions.contains(.notify) {
            let notifyBlock: @convention(block) (String, String) -> Void = { title, body in
                Task { @MainActor in
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    let request = UNNotificationRequest(
                        identifier: "plugin.\(UUID().uuidString)",
                        content: content,
                        trigger: nil
                    )
                    try? await UNUserNotificationCenter.current().add(request)
                }
            }
            coolrun.setObject(unsafeBitCast(notifyBlock, to: AnyObject.self), forKeyedSubscript: "notify")
        }

        if manifest.permissions.contains(.clipboard) {
            let clipboardBlock: @convention(block) (String) -> Void = { text in
                Task { @MainActor in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }
            }
            coolrun.setObject(unsafeBitCast(clipboardBlock, to: AnyObject.self), forKeyedSubscript: "copy")
        }

        context.setObject(coolrun, forKeyedSubscript: "coolrun" as NSString)
    }

    // MARK: 同步 HTTP

    /// 当前 Agent（MCP）服务器监听的端口，由 `CoolRunMCPHost` 在启停时写入。
    ///
    /// 用 `nonisolated(unsafe)` 而不是 MainActor 属性：读它的是插件桥的
    /// 后台线程（`httpGetSync` 会阻塞，不能放主线程）。写入只发生在启停时，
    /// 读的是一个对齐的 UInt16，不会读到半个值。
    nonisolated(unsafe) static var blockedAgentPort: UInt16?

    /// 判断 URL 是否指向本机 Agent（MCP）服务器的端口。
    nonisolated static func targetsLocalAgentPort(
        _ url: URL,
        agentPort: UInt16? = PluginHost.blockedAgentPort
    ) -> Bool {
        guard let agentPort, let host = url.host?.lowercased() else { return false }
        let loopback = ["127.0.0.1", "localhost", "::1", "[::1]"]
        guard loopback.contains(host) else { return false }
        return url.port.map { UInt16(clamping: $0) } == agentPort
    }

    private nonisolated static func httpGetSync(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let scheme = url.scheme,
              scheme == "http" || scheme == "https"
        else {
            return ""
        }

        // 插件是本地第三方 JS，能读 manifest 就能发请求。127.0.0.1 上有我们自己的
        // MCP 服务器（能调工具、能写文件），所以专门把它挡掉——不封整个回环，
        // 因为插件连本地模型（11434）是正当用法。
        if Self.targetsLocalAgentPort(url) {
            FileHandle.standardError.write(
                Data("[Plugin] blocked request to local Agent port: \(url.absoluteString)\n".utf8)
            )
            return ""
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("CoolRun-Plugin", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var text = ""
        }
        let box = Box()

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, let text = String(data: data, encoding: .utf8) {
                box.text = text
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 12)
        return box.text
    }
}
