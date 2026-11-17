import Foundation
import os

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

    private static let logger = Logger(subsystem: "com.coolrun.agent", category: "coordinator")

    /// 界面文案用的语言。界面本身订阅了 AppSettings，这里只是取当前值。
    private var lang: AppLanguage { AppSettings.shared.language }

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
            errorMessage = localized(error)
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
            errorMessage = localized(error)
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
        let markers = [
            "API Key", "接口地址", "模型名称", "未配置", "设置",  // i18n-allow: 多语言关键词匹配表 / 日志
            "credential", "401", "403",
            "endpoint", "model name", "not configured", "Settings",
            "エンドポイント", "モデル名", "未設定", "設定",  // i18n-allow: 多语言关键词匹配表 / 日志
            "엔드포인트", "모델 이름", "설정되지 않음", "설정",
        ]
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
            // 这份 patch 决定 DSH 用哪个 provider、连哪个 MCP 端口。写失败的话
            // 引擎会用默认配置起来，表现成「模型不认 key」——所以不能静默。
            do {
                _ = try DSHAgentEngine.writePatch(
                    config: config,
                    endpoint: CoolRunMCPHost.shared.endpoint,
                    token: CoolRunMCPHost.shared.token
                )
            } catch {
                Self.logger.error("DSH patch 写入失败：\(error.localizedDescription, privacy: .public)")  // i18n-allow: 多语言关键词匹配表 / 日志
                self.errorMessage = LocalizedString.l(
                    self.lang,
                    en: "Failed to write the DSH runtime config: \(error.localizedDescription)",
                    zh: "DSH 运行时配置写入失败：\(error.localizedDescription)",
                    ja: "DSH ランタイム設定の書き込みに失敗しました：\(error.localizedDescription)",
                    ko: "DSH 런타임 설정 쓰기 실패: \(error.localizedDescription)"
                )
            }
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
            // 场景命令缺参数时也走这里：说清是「少了一句内容」，别当成不存在的命令。
            let isRecipe = AgentRecipeStore.shared.all.contains { $0.slash == word }
            appendNotice(
                isRecipe
                    ? LocalizedString.l(
                        lang,
                        en: "/\(word) needs some content after it.",
                        zh: "/\(word) 还需要补一句内容。",
                        ja: "/\(word) の後ろに内容を書いてください。",
                        ko: "/\(word) 뒤에 내용을 적어 주세요."
                    )
                    : LocalizedString.l(
                        lang,
                        en: "No such command: /\(word). \(helpText)",
                        zh: "没有 /\(word) 这个命令。\(helpText)",
                        ja: "/\(word) というコマンドはありません。\(helpText)",
                        ko: "/\(word) 명령이 없습니다. \(helpText)"
                    )
            )
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
            errorMessage = LocalizedString.l(
                lang,
                en: "Usage: /tool <tool name> [JSON arguments]",
                zh: "用法：/tool <工具名> [JSON 参数]",
                ja: "使い方：/tool <ツール名> [JSON 引数]",
                ko: "사용법: /tool <도구 이름> [JSON 인수]"
            )
            return
        }
        AgentTools.registerAll()
        AgentActionTools.registerAll()

        guard let descriptor = ToolRegistry.shared.descriptor(named: name) else {
            errorMessage = LocalizedString.l(
                lang,
                en: "No tool named \(name).",
                zh: "没有叫 \(name) 的工具。",
                ja: "\(name) というツールはありません。",
                ko: "\(name) 도구가 없습니다."
            )
            return
        }
        let allowed = AgentSettings.shared.toolLevel
        guard descriptor.permission <= allowed else {
            errorMessage = LocalizedString.l(
                lang,
                en: "\(name) requires \(descriptor.permission.displayName) level, but the current setting only allows \(allowed.displayName).",
                zh: "\(name) 需要 \(descriptor.permission.displayName) 等级，当前设置只允许 \(allowed.displayName)。",
                ja: "\(name) には \(descriptor.permission.displayName) レベルが必要ですが、現在の設定では \(allowed.displayName) までしか許可されていません。",
                ko: "\(name)은(는) \(descriptor.permission.displayName) 레벨이 필요하지만 현재 설정은 \(allowed.displayName)까지만 허용합니다."
            )
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
                switch await self.requestApproval(descriptor, arguments) {
                case .approved:
                    break
                case .denied(let reason):
                    self.isRunning = false
                    self.runTask = nil
                    self.appendNotice(
                        LocalizedString.l(
                            self.lang,
                            en: "Cancelled: \(name) (\(reason))",
                            zh: "已取消：\(name)（\(reason)）",
                            ja: "キャンセルしました：\(name)（\(reason)）",
                            ko: "취소됨: \(name) (\(reason))"
                        )
                    )
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
                policy: .init(maxLevel: allowed, approval: { _, _ in .approved })
            )
            let elapsed = Date().timeIntervalSince(started)

            if let index = self.activities.firstIndex(where: { $0.id == callID }) {
                self.activities[index].output = result.content
                self.activities[index].isError = result.isError
                self.activities[index].duration = elapsed
            }

            let preview = result.content.count > 2400
                ? String(result.content.prefix(2400))
                    + LocalizedString.l(
                        lang,
                        en: "\n… (truncated)",
                        zh: "\n…（已截断）",
                        ja: "\n…（切り詰めました）",
                        ko: "\n… (잘림)"
                    )
                : result.content
            self.history.append(
                role: .assistant,
                content: result.isError
                    ? LocalizedString.l(
                        lang,
                        en: "Running \(name) failed:\n\(preview)",
                        zh: "执行 \(name) 失败：\n\(preview)",
                        ja: "\(name) の実行に失敗しました：\n\(preview)",
                        ko: "\(name) 실행 실패:\n\(preview)"
                    )
                    : preview
            )

            self.isRunning = false
            self.runTask = nil
        }
    }

    private var helpText: String {
        let hints = AgentCommandParser.commandHints
            + AgentRecipeStore.shared.all.compactMap { recipe in
                recipe.slash.map { "/" + $0 }
            }
        return LocalizedString.l(
            lang,
            en: "Available commands:\n\(hints.joined(separator: "　"))\nYou can also just talk, no slash needed.",
            zh: "可用命令：\n\(hints.joined(separator: "　"))\n也可以直接说话，不用斜杠。",
            ja: "使えるコマンド：\n\(hints.joined(separator: "　"))\nスラッシュなしでそのまま話しかけても大丈夫です。",
            ko: "사용 가능한 명령:\n\(hints.joined(separator: "　"))\n슬래시 없이 그냥 말해도 됩니다."
        )
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
    ) async -> ApprovalDecision {
        // 确认条是画在对话界面里的。面板没开着就没人能点，与其让两边一起
        // 干等（我们 90 秒、DSH 60 秒），不如立刻拒绝并说清原因。
        guard AgentApprovalGate.shared.isChatVisible else {
            return .denied(
                LocalizedString.l(
                    lang,
                    en: "There's no visible chat window, so the confirmation can't be shown. "
                        + "Open CoolRun's AI panel first and then ask me to do a write operation, "
                        + "or answer in a read-only way.",
                    zh: "现在没有可见的对话窗口，无法弹出确认。请先打开 CoolRun 的 AI 面板，"
                        + "再让我做需要写入的操作；或者改用只读的方式回答。",
                    ja: "表示中の会話ウィンドウがないため確認を出せません。先に CoolRun の AI パネルを開いてから、"
                        + "書き込みが必要な操作を依頼してください。もしくは読み取り専用の方法で答えます。",
                    ko: "표시 중인 대화 창이 없어 확인을 띄울 수 없습니다. 먼저 CoolRun의 AI 패널을 연 뒤 "
                        + "쓰기 작업을 요청해 주세요. 아니면 읽기 전용 방식으로 답하겠습니다."
                )
            )
        }

        let request = AgentApprovalRequest(
            id: UUID().uuidString,
            toolName: descriptor.name,
            summary: descriptor.summary,
            argumentsText: arguments.prettyJSONString()
        )
        let approved = await withCheckedContinuation { continuation in
            approvalContinuation = continuation
            pendingApproval = request

            // 没人搭理就当作拒绝，避免引擎永远卡住。
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(90))
                guard let self, self.pendingApproval?.id == request.id else { return }
                self.resolveApproval(false)
            }
        }
        return approved ? .approved : .userDeclined
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
                guard let self else { return .userDeclined }
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
                content: LocalizedString.l(
                    lang,
                    en: "The tools ran, but the model didn't give a written conclusion. Try asking again.",
                    zh: "工具执行完毕，但模型没有给出文字结论。可以再问一次。",
                    ja: "ツールは実行されましたが、モデルから文章の結論がありませんでした。もう一度聞いてみてください。",
                    ko: "도구는 실행되었지만 모델이 글로 된 결론을 주지 않았습니다. 다시 물어봐 주세요."
                )
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
        errorMessage = localized(error)
    }

    /// 把错误转成当前语言下的文案：AgentError 有专门的本地化文案，
    /// 其余沿用系统提供的描述。
    private func localized(_ error: Error) -> String {
        if let localized = error as? AgentLocalizedError {
            return localized.localizedMessage(lang)
        }
        return error.localizedDescription
    }
}
