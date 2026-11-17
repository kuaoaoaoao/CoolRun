import Foundation

// MARK: - 已安装插件

struct InstalledPlugin: Identifiable, Sendable {
    var manifest: PluginManifest
    var root: URL
    /// 加载时的错误，nil 表示正常
    var loadError: String?

    nonisolated var id: String { manifest.id }
    nonisolated var isValid: Bool { loadError == nil }
    nonisolated var toolCount: Int { manifest.tools.count }
}

// MARK: - 插件管理

/// 本地插件：一个 `.coolplugin` 目录里放 `manifest.json` 和 `main.js`，
/// 拷进 `~/Library/Application Support/CoolRun/Plugins/` 就算装好。
///
/// 插件声明的工具会注册进 `ToolRegistry`，于是模型能调、工具浏览器里也能点。
/// 工具权限由 manifest 里 `permission` 字段决定，照样过确认闸门。
@MainActor
@Observable
final class PluginManager {
    static let shared = PluginManager()

    private(set) var plugins: [InstalledPlugin] = []
    private(set) var lastError: String?

    private let defaults = UserDefaults.standard

    private init() {}

    /// UI 里装失败时把原因显示出来。
    func reportError(_ message: String?) {
        lastError = message
    }

    // MARK: 目录

    nonisolated static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("CoolRun", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    // MARK: 加载

    /// 扫描插件目录，注册全部启用的工具。可重复调用（工具名固定，覆盖注册）。
    func loadAll() {
        let root = Self.rootDirectory
        let manager = FileManager.default

        if !manager.fileExists(atPath: root.path) {
            try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        }

        let entries = (try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [InstalledPlugin] = []
        for entry in entries where entry.pathExtension == "coolplugin" {
            guard let manifest = PluginManifest.load(from: entry) else {
                lastError = LocalizedString.l(
                    AppSettings.shared.language,
                    en: "\(entry.lastPathComponent): manifest.json is missing or malformed",
                    zh: "\(entry.lastPathComponent) 的 manifest.json 缺失或格式不对",
                    ja: "\(entry.lastPathComponent) の manifest.json が見つからないか形式が正しくありません",
                    ko: "\(entry.lastPathComponent)의 manifest.json이 없거나 형식이 올바르지 않습니다"
                )
                continue
            }

            var error: String?
            let scriptURL = entry.appendingPathComponent(manifest.mainScript)
            if !manager.fileExists(atPath: scriptURL.path) {
                error = LocalizedString.l(
                    AppSettings.shared.language,
                    en: "Missing script \(manifest.mainScript)",
                    zh: "缺少脚本 \(manifest.mainScript)",
                    ja: "スクリプトがありません：\(manifest.mainScript)",
                    ko: "스크립트가 없습니다: \(manifest.mainScript)"
                )
            }

            loaded.append(InstalledPlugin(manifest: manifest, root: entry, loadError: error))
        }

        plugins = loaded.sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
        registerTools()
    }

    private func registerTools() {
        for plugin in plugins where plugin.isValid && Self.isEnabled(plugin.manifest.id) {
            for spec in plugin.manifest.tools {
                let fullName = Self.toolName(pluginID: plugin.manifest.id, tool: spec.name)
                let descriptor = ToolDescriptor(
                    name: fullName,
                    summary: "[\(plugin.manifest.name)] \(spec.summary)",
                    parameters: spec.parameters,
                    permission: spec.permission
                )
                let manifest = plugin.manifest
                let root = plugin.root

                ToolRegistry.shared.register(descriptor) { arguments in
                    await PluginHost.callTool(
                        manifest: manifest,
                        spec: spec,
                        arguments: arguments,
                        root: root,
                        lang: AppSettings.shared.language
                    )
                }
            }
        }
    }

    // MARK: 启停

    nonisolated static func isEnabled(_ pluginID: String) -> Bool {
        UserDefaults.standard.object(forKey: "plugin.disabled.\(pluginID)") as? Bool != true
    }

    func setEnabled(_ enabled: Bool, pluginID: String) {
        defaults.set(!enabled, forKey: "plugin.disabled.\(pluginID)")

        // 关掉时把工具摘掉，重新打开时重扫一遍。
        if let plugin = plugins.first(where: { $0.manifest.id == pluginID }) {
            for spec in plugin.manifest.tools {
                ToolRegistry.shared.unregister(
                    name: Self.toolName(pluginID: pluginID, tool: spec.name)
                )
            }
        }
        if enabled {
            loadAll()
        }
    }

    // MARK: 安装 / 卸载

    func install(from source: URL) throws {
        guard let manifest = PluginManifest.load(from: source) else {
            throw PluginError.invalidManifest(AppSettings.shared.language)
        }

        let destination = Self.rootDirectory.appendingPathComponent("\(manifest.id).coolplugin")
        let manager = FileManager.default

        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: source, to: destination)
        loadAll()
    }

    func remove(_ pluginID: String) throws {
        if let plugin = plugins.first(where: { $0.manifest.id == pluginID }) {
            for spec in plugin.manifest.tools {
                ToolRegistry.shared.unregister(
                    name: Self.toolName(pluginID: pluginID, tool: spec.name)
                )
            }
            try FileManager.default.removeItem(at: plugin.root)
        }
        plugins.removeAll { $0.manifest.id == pluginID }
    }

    // MARK: 工具名

    /// 插件工具统一加前缀，避免和内置工具撞名，也方便在工具列表里归类。
    nonisolated static func toolName(pluginID: String, tool: String) -> String {
        let sanitized = pluginID.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return "plugin_\(String(sanitized))_\(tool)"
    }
}

// MARK: - 错误

enum PluginError: LocalizedError {
    case invalidManifest(AppLanguage)

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidManifest(let lang):
            return LocalizedString.l(
                lang,
                en: "manifest.json is invalid: at least id and name are required",
                zh: "manifest.json 格式不对：至少要写 id 和 name",
                ja: "manifest.json の形式が正しくありません：id と name は必須です",
                ko: "manifest.json 형식이 올바르지 않습니다: id와 name은 필수입니다"
            )
        }
    }
}
