import Foundation

// MARK: - 工具活动

/// 一次工具调用在 UI 上的展示记录。
struct AgentToolActivity: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    var argumentsText: String
    var output: String?
    var isError: Bool
    var duration: TimeInterval?

    var isFinished: Bool { output != nil }
}

// MARK: - 确认请求

/// 需要用户点头才继续的工具调用。
struct AgentApprovalRequest: Identifiable, Equatable, Sendable {
    let id: String
    let toolName: String
    let summary: String
    let argumentsText: String
}

// MARK: - 会话协调器

/// 会话状态 + 引擎驱动。UI 只跟它打交道，不直接碰引擎。
///
/// 对话记录放在 `AgentHistoryStore` 里，跨启动保留，可以逐条删除。
@MainActor
@Observable
final class AgentCoordinator {
    static let shared = AgentCoordinator()

    private(set) var isRunning = false
    private(set) var streamingText = ""
    private(set) var reasoningText = ""
    private(set) var activities: [AgentToolActivity] = []
    private(set) var engineName: String = AgentEngineKind.native.displayName

    /// 非空时 UI 显示错误条。
    var errorMessage: String?

    /// 非空时 UI 显示确认条，等用户点允许 / 拒绝。
    private(set) var pendingApproval: AgentApprovalRequest?

    private var engine: (any AgentEngine)?
    private var runTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    private var history: AgentHistoryStore { AgentHistoryStore.shared }

    private init() {}

    /// 已落盘的对话，供界面渲染。
    var messages: [AgentHistoryEntry] { history.entries }

    /// 有没有可以重试的提问。
    var hasUserMessage: Bool { history.entries.contains { $0.role == .user } }

    // MARK: - 发送

    func send(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }

        let config: AgentRunConfig
        do {
            config = try AgentSettings.shared.makeConfig()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // 工具注册是幂等的，这里兜底，防止有人绕过 App 启动路径直接进对话。
        AgentTools.registerAll()
        AgentActionTools.registerAll()

        let engineHistory = history.messages()
        history.append(role: .user, content: trimmed)

        start(prompt: trimmed, history: engineHistory, config: config)
    }

    /// 重试上一次提问：失败之后最需要的动作——改完设置、换个模型，不用重新打字。
    /// 不会重复记一条用户消息，只把模型再跑一遍。
    func retryLast() {
        guard !isRunning else { return }
        guard let lastUser = history.entries.last(where: { $0.role == .user }) else { return }

        let config: AgentRunConfig
        do {
            config = try AgentSettings.shared.makeConfig()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        AgentTools.registerAll()
        AgentActionTools.registerAll()

        var priorHistory = history.messages()
        if let last = priorHistory.last, last.role == .user { priorHistory.removeLast() }
        start(prompt: lastUser.content, history: priorHistory, config: config)
    }

    /// 这条错误是配置问题吗？UI 用它决定给「去设置」还是「重试」。
    nonisolated static func looksLikeConfigurationProblem(_ message: String) -> Bool {
        let markers = ["API Key", "接口地址", "模型名称", "未配置", "设置", "credential", "401", "403"]
        return markers.contains { message.localizedCaseInsensitiveContains($0) }
    }

    private func start(prompt: String, history engineHistory: [AgentMessage], config: AgentRunConfig) {
        isRunning = true
        streamingText = ""
        reasoningText = ""
        activities = []
        errorMessage = nil

        let engine = activeEngine()
        engineName = engine.displayName

        runTask = Task { [weak self] in
            var collected = ""
            do {
                for try await event in engine.run(prompt: prompt, history: engineHistory, config: config) {
                    guard let self, !Task.isCancelled else { return }
                    switch event {
                    case .textDelta(let delta):
                        collected += delta
                        self.streamingText = collected

                    case .reasoningDelta(let delta):
                        self.reasoningText += delta

                    case .toolCallStarted(let id, let name, let arguments):
                        self.activities.append(AgentToolActivity(
                            id: id,
                            name: name,
                            argumentsText: arguments.compactJSONString(),
                            output: nil,
                            isError: false,
                            duration: nil
                        ))

                    case .toolCallFinished(let id, _, let output, let isError):
                        if let index = self.activities.firstIndex(where: { $0.id == id }) {
                            self.activities[index].output = output
                            self.activities[index].isError = isError
                        }

                    case .turnFinished, .confirmationRequired:
                        break
                    }
                }
                self?.finish(text: collected)
            } catch {
                self?.fail(error)
            }
        }
    }

    // MARK: - 指令

    /// 执行一条已解析的斜杠指令。返回 false 表示这条指令该由界面自己处理。
    /// DSH 引擎靠本地 MCP 服务器把工具递过去，提前拉起来，省得首次对话干等端口。
    func prewarm() {
        // 这里刻意不碰 AgentSettings：它的初始化要读 Keychain，未签名的 Debug
        // 构建会弹钥匙串授权框，卡住 App 启动。
        let raw = UserDefaults.standard.string(forKey: "agent.engine") ?? AgentEngineKind.native.rawValue
        guard raw == AgentEngineKind.dsh.rawValue else { return }
        CoolRunMCPHost.shared.start()

        // 顺手把运行时配置落盘，排查「引擎起不来」时能直接看文件。
        // 端口是异步就绪的，等一拍再写，否则 MCP 那段会是空的。
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard let config = try? AgentSettings.shared.makeConfig() else { return }
            _ = try? DSHAgentEngine.writePatch(
                config: config,
                endpoint: CoolRunMCPHost.shared.endpoint,
                token: CoolRunMCPHost.shared.token
            )
        }
    }

    @discardableResult
    func runCommand(_ command: AgentCommand) -> Bool {
        switch command {
        case .send(let prompt):
            send(prompt)
            return true
        case .runTool(let name, let arguments):
            runToolDirectly(name: name, arguments: arguments)
            return true
        case .clear:
            reset()
            return true
        case .help:
            appendNotice(helpText)
            return true
        case .unknown(let word):
            appendNotice("没有 /\(word) 这个命令。\(helpText)")
            return true
        case .openSettings:
            return false
        }
    }

    /// 直接执行一个工具，不经过模型。用于 `/tool` 和工具浏览器。
    /// 外部（搜索面板、场景卡）要求把一段话填进输入框，`AgentChatView` 消费后清空。
    var draft: String?

    func runToolDirectly(name: String, arguments: JSONValue) {
        guard !isRunning else { return }
        guard !name.isEmpty else {
            errorMessage = "用法：/tool <工具名> [JSON 参数]"
            return
        }
        AgentTools.registerAll()
        AgentActionTools.registerAll()

        guard let descriptor = ToolRegistry.shared.descriptor(named: name) else {
            errorMessage = "没有叫 \(name) 的工具。"
            return
        }
        let allowed = AgentSettings.shared.toolLevel
        guard descriptor.permission <= allowed else {
            errorMessage = "\(name) 需要 \(descriptor.permission.displayName) 等级，当前设置只允许 \(allowed.displayName)。"
            return
        }

        isRunning = true
        errorMessage = nil
        activities = []
        streamingText = ""
        reasoningText = ""

        let callID = UUID().uuidString
        history.append(role: .user, content: "/tool \(name) \(arguments.compactJSONString())")

        runTask = Task { [weak self] in
            guard let self else { return }

            if descriptor.permission >= .persistent {
                let approved = await self.requestApproval(descriptor, arguments)
                guard approved else {
                    self.isRunning = false
                    self.runTask = nil
                    self.appendNotice("已取消：\(name)")
                    return
                }
            }

            self.activities.append(AgentToolActivity(
                id: callID,
                name: name,
                argumentsText: arguments.compactJSONString(),
                output: nil,
                isError: false,
                duration: nil
            ))

            let started = Date()
            // 上面已经验过等级、也已经问过用户，这里把结论原样交给执行器，
            // 免得同一件事被问两遍、或者被闸门第二次拦下。
            let result = await ToolRegistry.shared.execute(
                name: name,
                arguments: arguments,
                policy: .init(maxLevel: allowed, approval: { _, _ in true })
            )
            let elapsed = Date().timeIntervalSince(started)

            if let index = self.activities.firstIndex(where: { $0.id == callID }) {
                self.activities[index].output = result.content
                self.activities[index].isError = result.isError
                self.activities[index].duration = elapsed
            }

            let preview = result.content.count > 2400
                ? String(result.content.prefix(2400)) + "\n…（已截断）"
                : result.content
            self.history.append(
                role: .assistant,
                content: result.isError ? "执行 \(name) 失败：\n\(preview)" : preview
            )

            self.isRunning = false
            self.runTask = nil
        }
    }

    private var helpText: String {
        """
        可用命令：
        \(AgentCommandParser.commandHints.joined(separator: "　"))
        也可以直接说话，不用斜杠。
        """
    }

    private func appendNotice(_ text: String) {
        history.append(role: .assistant, content: text)
    }

    // MARK: - 历史

    func deleteMessage(id: UUID) {
        history.delete(id: id)
    }

    // MARK: - 控制

    func cancel() {
        runTask?.cancel()
        engine?.cancel()
        runTask = nil
        isRunning = false
        streamingText = ""
        reasoningText = ""
        resolveApproval(false)
    }

    func reset() {
        cancel()
        history.clear()
        activities.removeAll()
        errorMessage = nil
    }

    // MARK: - 确认

    /// 由 UI 调用：允许或拒绝挂起的写入操作。
    func resolveApproval(_ approved: Bool) {
        pendingApproval = nil
        guard let continuation = approvalContinuation else { return }
        approvalContinuation = nil
        continuation.resume(returning: approved)
    }

    /// 由任何需要确认的通道调用（原生引擎、MCP 回连）。
    func requestApproval(
        _ descriptor: ToolDescriptor,
        _ arguments: JSONValue
    ) async -> Bool {
        let request = AgentApprovalRequest(
            id: UUID().uuidString,
            toolName: descriptor.name,
            summary: descriptor.summary,
            argumentsText: arguments.prettyJSONString()
        )
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
            pendingApproval = request

            // 没人搭理就当作拒绝，避免引擎永远卡住。
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(90))
                guard let self, self.pendingApproval?.id == request.id else { return }
                self.resolveApproval(false)
            }
        }
    }

    // MARK: - 私有

    private func activeEngine() -> any AgentEngine {
        let kind = AgentSettings.shared.engineKind
        if let engine, engine.kind == kind { return engine }

        // 换引擎前先把旧的关掉，DSH 是个真实进程，不能泄漏。
        engine?.shutdown()
        engine = nil

        let created: any AgentEngine
        switch kind {
        case .native:
            let native = SwiftAgentEngine()
            native.approvalHandler = { [weak self] descriptor, arguments in
                guard let self else { return false }
                return await self.requestApproval(descriptor, arguments)
            }
            created = native
        case .dsh:
            // DSH 的工具走 MCP 回连，所以先把本地 MCP 服务器拉起来。
            CoolRunMCPHost.shared.start()
            created = DSHAgentEngine()
        }

        engine = created
        return created
    }

    private func finish(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            history.append(role: .assistant, content: trimmed)
        } else if activities.contains(where: { !$0.isFinished }) {
            history.append(
                role: .assistant,
                content: "工具执行完毕，但模型没有给出文字结论。可以再问一次。"
            )
        }
        isRunning = false
        streamingText = ""
        reasoningText = ""
        runTask = nil
    }

    private func fail(_ error: Error) {
        isRunning = false
        streamingText = ""
        reasoningText = ""
        runTask = nil

        if error is CancellationError {
            return
        }
        errorMessage = error.localizedDescription
    }
}
