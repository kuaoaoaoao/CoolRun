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

    /// 一次工具调用的执行策略。权限上限、用户确认、超时都收在这里。
    ///
    /// 为什么必须在这里拦：把工具从 schema 里藏起来只是「不告诉模型」，
    /// 不是「不让它做」。模型可以凭上下文里的旧工具名直接点名调用，
    /// DSH 那边也是通过 MCP 回连到同一张表——所有通道都走 `execute`，
    /// 所以闸门必须装在 `execute` 里。
    struct ExecutionPolicy {
        /// 没显式给策略时按最保守处理：只放行只读工具。
        /// 这样将来新增的调用点忘了传策略，也不会意外获得写权限。
        var maxLevel: ToolPermission = .read
        var approval: (@MainActor (ToolDescriptor, JSONValue) async -> Bool)?
        var timeout: Duration? = .seconds(60)
    }

    func execute(
        name: String,
        arguments: JSONValue,
        policy: ExecutionPolicy = ExecutionPolicy()
    ) async -> ToolResult {
        guard let entry = entries[name] else {
            let failure = ToolResult.failure("未知工具：\(name)")
            AgentAuditLog.shared.record(tool: name, arguments: arguments, result: failure, duration: 0)
            return failure
        }
        let descriptor = entry.descriptor
        let started = Date()

        func deny(_ message: String) -> ToolResult {
            let failure = ToolResult.failure(message)
            AgentAuditLog.shared.record(
                tool: name,
                arguments: arguments,
                result: failure,
                duration: Date().timeIntervalSince(started)
            )
            return failure
        }

        // 1. 权限上限：执行期校验，不能只靠「不把工具告诉模型」。
        guard descriptor.permission <= policy.maxLevel else {
            return deny(
                "权限不足：\(name) 属于「\(descriptor.permission.displayName)」，"
                + "当前上限是「\(policy.maxLevel.displayName)」。"
            )
        }

        // 2. 持久写入必须有人点头；没有确认通道时按拒绝处理（安全默认）。
        if descriptor.permission >= .persistent {
            guard let approval = policy.approval else {
                return deny("\(name) 会写入持久数据，需要用户确认，但当前通道没有确认界面。")
            }
            guard await approval(descriptor, arguments) else {
                return deny("用户拒绝了这次操作。请改用不需要写入的方式，或先向用户说明意图。")
            }
        }

        let result = await Self.awaitTool(entry, arguments: arguments, timeout: policy.timeout)
        AgentAuditLog.shared.record(
            tool: name,
            arguments: arguments,
            result: result,
            duration: Date().timeIntervalSince(started)
        )
        return result
    }

    /// 跑工具并给一个上限。工具本身不一定可取消（比如正在等网络响应），
    /// 但至少不能让整个回合被一个卡死的工具挂住。
    private static func awaitTool(
        _ entry: Entry,
        arguments: JSONValue,
        timeout: Duration?
    ) async -> ToolResult {
        guard let timeout else {
            return await entry.handler(arguments)
        }
        let box = CompletionBox()
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let result = await entry.handler(arguments)
                if box.claim() {
                    continuation.resume(returning: result)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if box.claim() {
                    continuation.resume(
                        returning: .failure("工具 \(entry.descriptor.name) 执行超时，已放弃等待。")
                    )
                }
            }
        }
    }

    /// 两个分支（结果、超时）谁先到谁说话，只允许说一次。
    @MainActor
    private final class CompletionBox {
        private var finished = false

        func claim() -> Bool {
            guard !finished else { return false }
            finished = true
            return true
        }
    }

    func openAISchemas(upTo limit: ToolPermission) -> [JSONValue] {
        descriptors(upTo: limit).map { $0.openAISchema }
    }

    func anthropicSchemas(upTo limit: ToolPermission) -> [JSONValue] {
        descriptors(upTo: limit).map { $0.anthropicSchema }
    }
}
