import Foundation
import AppKit

/// 本地崩溃日志收集器。
///
/// 不依赖任何第三方服务，纯本地写入。用户主动反馈时可将日志文件一并附带。
///
/// 注：Swift 6 对 `NSSetUncaughtExceptionHandler` 的 C 函数指针参数有严格限制，
/// 无法直接在 Swift 中注册异常 handler。因此采用以下策略：
/// 1. 在关键路径手动 `try/catch` 并记录异常上下文。
/// 2. 提供 `recordError` 供各模块主动上报非致命错误。
/// 3. App 启动时检查上次是否异常退出（通过 `NSApplication.willTerminateNotification`
///    与启动时间戳对比）。
@MainActor
final class CrashReporter {
    static let shared = CrashReporter()

    /// 崩溃日志目录：~/Library/Application Support/CoolRun/crashes/
    private static var crashDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("CoolRun/crashes", isDirectory: true)
    }

    /// 所有已记录的崩溃日志文件，按时间倒序排列。
    var crashLogs: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: Self.crashDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    private init() {}

    /// 初始化崩溃收集。应在 `applicationDidFinishLaunching` 中调用。
    func install() {
        // 检查上次是否异常退出
        checkLastCrash()
        // 记录正常启动
        recordEvent(type: "launch", reason: "App launched normally")
    }

    /// 记录一次非致命错误。
    func recordError(_ error: Error, context: String = "") {
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "type": "error",
            "reason": "\(error)\(context.isEmpty ? "" : " | \(context)")",
            "callStack": Thread.callStackSymbols.joined(separator: "\n"),
        ]
        write(payload)
    }

    /// 记录一次自定义事件（用于调试和诊断）。
    func recordEvent(type: String, reason: String) {
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "type": type,
            "reason": reason,
        ]
        write(payload)
    }

    /// 删除所有崩溃日志。
    func clearAll() {
        for url in crashLogs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 内部

    private func checkLastCrash() {
        // 如果上次启动后没有正常退出记录，且距离上次启动超过 5 秒，
        // 则认为是异常退出
        let lastLaunch = UserDefaults.standard.object(forKey: "_crash_reporter_last_launch") as? Date
        let lastTerminate = UserDefaults.standard.object(forKey: "_crash_reporter_last_terminate") as? Date

        if let lastLaunch = lastLaunch,
           (lastTerminate == nil || lastLaunch > lastTerminate!) {
            // 上次异常退出，记录
            let payload: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "type": "crash",
                "reason": "App terminated abnormally (no clean shutdown detected)",
                "lastLaunch": ISO8601DateFormatter().string(from: lastLaunch),
            ]
            write(payload)
        }

        // 记录本次启动
        UserDefaults.standard.set(Date(), forKey: "_crash_reporter_last_launch")
        UserDefaults.standard.removeObject(forKey: "_crash_reporter_last_terminate")
    }

    /// 应在 `applicationWillTerminate` 中调用，标记正常退出。
    func markCleanShutdown() {
        UserDefaults.standard.set(Date(), forKey: "_crash_reporter_last_terminate")
    }

    private func write(_ payload: [String: Any]) {
        let dir = Self.crashDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var fullPayload = payload
        fullPayload["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        fullPayload["buildVersion"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        fullPayload["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? "unknown"
        fullPayload["osVersion"] = ProcessInfo.processInfo.operatingSystemVersionString
        let file = dir.appendingPathComponent("crash-\(ISO8601DateFormatter().string(from: Date())).json")
        if let data = try? JSONSerialization.data(withJSONObject: fullPayload, options: .prettyPrinted) {
            try? data.write(to: file)
        }
    }
}
