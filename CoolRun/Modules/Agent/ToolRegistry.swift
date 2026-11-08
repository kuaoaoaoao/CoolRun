import Foundation

// MARK: - 权限

/// 工具权限分级。数字越大越危险，UI 与执行器都按它做闸门。
enum ToolPermission: Int, Comparable, CaseIterable, Codable, Sendable {
    /// 只读：直接执行
    case read = 0
    /// 可逆写：切面板、发通知、写剪贴板，直接执行
    case reversible = 1
    /// 持久写：笔记、提醒、设置、截图，执行前需确认
    case persistent = 2
    /// 危险：shell、任意文件写，默认不注册
    case dangerous = 3

    nonisolated static func < (lhs: ToolPermission, rhs: ToolPermission) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .read: return "只读"
        case .reversible: return "可撤销"
        case .persistent: return "需确认"
        case .dangerous: return "危险"
        }
    }
}

// MARK: - 工具描述

struct ToolDescriptor: Sendable, Identifiable {
    var name: String
    var summary: String
    /// JSON Schema object，描述参数
    var parameters: JSONValue
    var permission: ToolPermission

    nonisolated var id: String { name }

    nonisolated init(
        name: String,
        summary: String,
        parameters: JSONValue = .object(["type": .string("object"), "properties": .object([:])]),
        permission: ToolPermission = .read
    ) {
        self.name = name
        self.summary = summary
        self.parameters = parameters
        self.permission = permission
    }
}

extension ToolDescriptor {
    /// OpenAI Chat / Responses 通用 schema
    nonisolated var openAISchema: JSONValue {
        .object([
            "type": .string("function"),
            "function": .object([
                "name": .string(name),
                "description": .string(summary),
                "parameters": parameters,
            ]),
        ])
    }

    /// Anthropic Messages schema
    nonisolated var anthropicSchema: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(summary),
            "input_schema": parameters,
        ])
    }
}

// MARK: - 工具结果

struct ToolResult: Sendable {
    var content: String
    var isError: Bool

    nonisolated init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    nonisolated static func text(_ text: String) -> ToolResult {
        ToolResult(content: text)
    }

    nonisolated static func failure(_ message: String) -> ToolResult {
        ToolResult(content: message, isError: true)
    }
}

// MARK: - Schema 构造辅助

/// 手写 JSON Schema 太容易出错，这里提供几个小而明确的构造器。
nonisolated enum ToolSchema {
    static func object(
        properties: [(name: String, schema: JSONValue)],
        required: [String] = []
    ) -> JSONValue {
        var map: [String: JSONValue] = [:]
        for property in properties {
            map[property.name] = property.schema
        }
        var root: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(map),
        ]
        if !required.isEmpty {
            root["required"] = .array(required.map { .string($0) })
        }
        return .object(root)
    }

    static func string(_ description: String, enumValues: [String]? = nil) -> JSONValue {
        var map: [String: JSONValue] = [
            "type": .string("string"),
            "description": .string(description),
        ]
        if let enumValues {
            map["enum"] = .array(enumValues.map { .string($0) })
        }
        return .object(map)
    }

    static func integer(_ description: String, minimum: Int? = nil, maximum: Int? = nil) -> JSONValue {
        var map: [String: JSONValue] = [
            "type": .string("integer"),
            "description": .string(description),
        ]
        if let minimum { map["minimum"] = .number(Double(minimum)) }
        if let maximum { map["maximum"] = .number(Double(maximum)) }
        return .object(map)
    }

    static func boolean(_ description: String) -> JSONValue {
        .object([
            "type": .string("boolean"),
            "description": .string(description),
        ])
    }
}

// MARK: - 注册表

/// 全 app 唯一的工具目录。所有引擎共用同一份工具，保证能力一致。
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private struct Entry {
        let descriptor: ToolDescriptor
        let handler: @MainActor (JSONValue) async -> ToolResult
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []

    private init() {}

    func register(
        _ descriptor: ToolDescriptor,
        handler: @escaping @MainActor (JSONValue) async -> ToolResult
    ) {
        if entries[descriptor.name] == nil {
            order.append(descriptor.name)
        }
        entries[descriptor.name] = Entry(descriptor: descriptor, handler: handler)
    }

    /// 卸载插件时把工具摘掉，避免留下调用即失败的幽灵工具。
    func unregister(name: String) {
        entries.removeValue(forKey: name)
        order.removeAll { $0 == name }
    }

    var allDescriptors: [ToolDescriptor] {
        order.compactMap { entries[$0]?.descriptor }
    }

    /// 按权限上限过滤后的工具，供引擎生成 schema。
    func descriptors(upTo limit: ToolPermission) -> [ToolDescriptor] {
        allDescriptors.filter { $0.permission <= limit }
    }

    func descriptor(named name: String) -> ToolDescriptor? {
        entries[name]?.descriptor
    }

    func execute(name: String, arguments: JSONValue) async -> ToolResult {
        guard let entry = entries[name] else {
            return .failure("未知工具：\(name)")
        }
        let started = Date()
        let result = await entry.handler(arguments)
        AgentAuditLog.shared.record(
            tool: name,
            arguments: arguments,
            result: result,
            duration: Date().timeIntervalSince(started)
        )
        return result
    }

    func openAISchemas(upTo limit: ToolPermission) -> [JSONValue] {
        descriptors(upTo: limit).map { $0.openAISchema }
    }

    func anthropicSchemas(upTo limit: ToolPermission) -> [JSONValue] {
        descriptors(upTo: limit).map { $0.anthropicSchema }
    }
}
