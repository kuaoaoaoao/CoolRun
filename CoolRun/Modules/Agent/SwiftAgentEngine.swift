import Foundation

// MARK: - 原生引擎

/// CoolRun 自带的 Agent 引擎：直接调用模型 HTTP 接口，自己跑「模型 → 工具 → 模型」循环。
/// 体积为零、无子进程，覆盖菜单栏助手的绝大多数场景。
@MainActor
final class SwiftAgentEngine: AgentEngine {
    let kind: AgentEngineKind = .native

    var displayName: String { "CoolRun Native" }
    var isAvailable: Bool { true }

    private var currentTask: Task<Void, Never>?
    private var cancelled = false

    /// 引擎在调用 L2（持久写）及以上工具前会走这个回调，返回 false 表示用户拒绝。
    /// 由 `AgentCoordinator` 注入，UI 负责真正弹出确认。
    var approvalHandler: (@MainActor (ToolDescriptor, JSONValue) async -> Bool)?

    /// 单条工具结果回灌给模型时的最大字符数，避免一次读文件把上下文撑爆。
    private static let toolResultLimit = 12_000

    func run(
        prompt: String,
        history: [AgentMessage],
        config: AgentRunConfig
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        cancelled = false
        currentTask?.cancel()

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.runLoop(
                        prompt: prompt,
                        history: history,
                        config: config,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AgentError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            currentTask = task

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                let owner = self
                Task { @MainActor in owner?.currentTask = nil }
            }
        }
    }

    func cancel() {
        cancelled = true
        currentTask?.cancel()
        currentTask = nil
    }

    func shutdown() {
        cancel()
    }

    // MARK: - 循环

    private struct PendingCall {
        var id: String
        var name: String
        var arguments: String
    }

    private func runLoop(
        prompt: String,
        history: [AgentMessage],
        config: AgentRunConfig,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        var working: [AgentMessage] = [
            AgentMessage(role: .system, content: AgentPrompts.system(for: prompt)),
        ]
        working.append(contentsOf: history)
        working.append(AgentMessage(role: .user, content: prompt))

        let descriptors = ToolRegistry.shared.descriptors(upTo: AgentSettings.shared.toolLevel)
        let wire = AgentWireFactory.make(config.protocolKind)

        for _ in 0..<config.maxRounds {
            try Task.checkCancellation()
            if cancelled { throw AgentError.cancelled }

            var text = ""
            var calls: [Int: PendingCall] = [:]

            let stream = try await wire.stream(messages: working, tools: descriptors, config: config)
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .text(let delta):
                    text += delta
                    continuation.yield(.textDelta(delta))
                case .reasoning(let delta):
                    continuation.yield(.reasoningDelta(delta))
                case .toolCallStart(let index, let id, let name):
                    calls[index] = PendingCall(id: id, name: name, arguments: "")
                case .toolCallArguments(let index, let fragment):
                    if calls[index] == nil {
                        calls[index] = PendingCall(id: "call-\(index)", name: "", arguments: "")
                    }
                    calls[index]?.arguments += fragment
                case .finished:
                    break
                }
            }

            let toolCalls = calls.keys.sorted().compactMap { index -> AgentToolCall? in
                guard let call = calls[index], !call.name.isEmpty else { return nil }
                return AgentToolCall(id: call.id, name: call.name, argumentsText: call.arguments)
            }

            // 模型没走 tool_calls 字段时，正文里可能藏着 <tool_call>{...}</tool_call>。
            // 能还原就继续跑，不能还原才算最终回答。
            var effectiveCalls = toolCalls
            var assistantText = text
            if effectiveCalls.isEmpty {
                let salvaged = AgentToolCallParser.parse(text, known: Set(descriptors.map(\.name)))
                if !salvaged.isEmpty {
                    effectiveCalls = salvaged
                    assistantText = ""
                }
            }

            guard !effectiveCalls.isEmpty else {
                continuation.yield(.turnFinished)
                return
            }

            working.append(AgentMessage(role: .assistant, content: assistantText, toolCalls: effectiveCalls))

            for call in effectiveCalls {
                try Task.checkCancellation()
                let arguments = call.arguments
                continuation.yield(.toolCallStarted(id: call.id, name: call.name, arguments: arguments))

                // 权限上限与持久写入的确认都在 ToolRegistry 里统一执行，
                // 这样 MCP 回连（DSH 引擎）与原生引擎走的是同一道闸门。
                let result = await ToolRegistry.shared.execute(
                    name: call.name,
                    arguments: arguments,
                    policy: ToolRegistry.ExecutionPolicy(
                        maxLevel: AgentSettings.shared.toolLevel,
                        approval: approvalHandler
                    )
                )
                let output = result.content.count > Self.toolResultLimit
                    ? String(result.content.prefix(Self.toolResultLimit)) + "\n…（结果已截断）"
                    : result.content

                working.append(AgentMessage(
                    role: .tool,
                    content: output,
                    toolCallID: call.id,
                    toolName: call.name,
                    isError: result.isError
                ))
                continuation.yield(.toolCallFinished(
                    id: call.id,
                    name: call.name,
                    output: output,
                    isError: result.isError
                ))
            }
        }

        throw AgentError.maxRoundsExceeded(config.maxRounds)
    }
}
