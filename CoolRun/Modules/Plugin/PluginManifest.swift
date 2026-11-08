import Foundation

// MARK: - 插件权限

/// 插件能碰的东西。比工具权限粗一档，因为插件是一整包代码，
/// 声明什么能力就只能在 `coolrun` 命名空间里拿到什么。
enum PluginPermission: String, CaseIterable, Sendable {
    /// 读网络（httpGet / httpPost）
    case network
    /// 发系统通知
    case notify
    /// 写剪贴板
    case clipboard
    /// 读写插件自己的 data.json
    case storage

    var displayName: String {
        switch self {
        case .network: return "联网"
        case .notify: return "通知"
        case .clipboard: return "剪贴板"
        case .storage: return "本地存储"
        }
    }
}

// MARK: - 工具声明

struct PluginToolSpec: Sendable, Identifiable {
    /// 工具名（不含插件前缀）
    var name: String
    var summary: String
    /// 参数 JSON Schema
    var parameters: JSONValue
    /// main.js 里对应的全局函数名
    var handler: String
    var permission: ToolPermission

    nonisolated var id: String { name }
}

// MARK: - manifest

/// 一个插件的 `manifest.json`。
///
/// 不用 Codable：项目开了 `-default-isolation MainActor`，struct 的自动合成
/// Codable 会踩隔离问题，手动从 JSONValue 解析反而干净。
struct PluginManifest: Sendable, Identifiable {
    var id: String
    var name: String
    var version: String
    var summary: String
    var author: String
    var mainScript: String
    var permissions: [PluginPermission]
    var tools: [PluginToolSpec]

    nonisolated init?(_ json: JSONValue) {
        guard let id = json["id"]?.stringValue, !id.isEmpty,
              let name = json["name"]?.stringValue, !name.isEmpty
        else {
            return nil
        }

        self.id = id
        self.name = name
        self.version = json["version"]?.stringValue ?? "0.0.0"
        self.summary = json["description"]?.stringValue ?? ""
        self.author = json["author"]?.stringValue ?? ""
        self.mainScript = json["main"]?.stringValue ?? "main.js"

        let permissionNames = json["permissions"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        self.permissions = permissionNames.compactMap(PluginPermission.init(rawValue:))

        let toolValues = json["tools"]?.arrayValue ?? []
        self.tools = toolValues.compactMap { value in
            guard let toolName = value["name"]?.stringValue, !toolName.isEmpty else { return nil }
            let handler = value["handler"]?.stringValue ?? toolName
            let level = ToolPermission(rawValue: value["permission"]?.intValue ?? 0) ?? .read
            return PluginToolSpec(
                name: toolName,
                summary: value["summary"]?.stringValue ?? value["description"]?.stringValue ?? toolName,
                parameters: value["parameters"] ?? .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ]),
                handler: handler,
                permission: level
            )
        }
    }

    nonisolated static func load(from directory: URL) -> PluginManifest? {
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return nil
        }
        return PluginManifest(json)
    }
}
