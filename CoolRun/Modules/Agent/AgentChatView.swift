import AppKit
import SwiftUI

// MARK: - Agent 对话视图

struct AgentChatView: View {
    @State private var showsClearConfirmation = false
    @State private var coordinator = AgentCoordinator.shared
    @State private var settings = AgentSettings.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var inputText = ""
    @State private var showsSettings = false
    @State private var showsTools = false
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var lang: AppLanguage { appSettings.language }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !coordinator.isRunning
    }

    var body: some View {
        Group {
            if showsSettings {
                AgentSettingsPanel(onClose: { showsSettings = false })
            } else if showsTools {
                AgentToolsBrowser(onClose: { showsTools = false })
            } else {
                chatBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            WindowVisibilityReader { visible in
                AgentApprovalGate.shared.setChatVisible(visible)
            }
            .frame(width: 0, height: 0)
        )
        .onChange(of: coordinator.draft) { _, draft in
            // 搜索面板选了「需要补一句话」的场景卡：把提示词放进输入框，光标停在末尾。
            guard let draft else { return }
            inputText = draft
            coordinator.draft = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                inputFocused = true
            }
        }
        .onAppear {
            AgentTools.registerAll()
            AgentActionTools.registerAll()
            // 热键唤出时希望直接能打字，等面板真正显示出来再抢焦点。
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                inputFocused = true
            }
        }
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            statusStrip
            Divider().opacity(0.4)
            transcript
            if let approval = coordinator.pendingApproval {
                approvalBar(approval)
            }
            if let error = coordinator.errorMessage {
                errorBar(error)
            }
            inputBar
        }
    }

    // MARK: - 顶部状态

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(coordinator.isRunning ? AppTheme.warning : AppTheme.healthy)
                .frame(width: 6, height: 6)

            Text(coordinator.engineName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            Text(settings.protocolKind.displayName)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.8))

            Spacer()

            if !settings.isConfigured {
                Button {
                    showsSettings = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 8))
                        Text(LocalizedString.l(lang, en: "No model · Open settings", zh: "未配置模型 · 去设置", ja: "モデル未設定 · 設定へ", ko: "모델 미설정 · 설정으로"))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.warning)
                }
                .buttonStyle(.plain)
            }

            Button {
                showsTools = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help(LocalizedString.l(lang, en: "Tools", zh: "工具", ja: "ツール", ko: "도구"))

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help(LocalizedString.l(lang, en: "Agent settings", zh: "Agent 设置", ja: "Agent 設定", ko: "Agent 설정"))

            Button {
                showsClearConfirmation = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help(LocalizedString.l(lang, en: "Clear chat", zh: "清空对话", ja: "会話をクリア", ko: "대화 지우기"))
            .disabled(coordinator.isRunning || AgentHistoryStore.shared.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // 这个按钮删的是全部历史（磁盘上的也删），不是只清屏。以前一点就没，
        // 手滑点错就找不回来了 —— 所以先问一句。
        .alert(
            LocalizedString.l(
                lang,
                en: "Clear all conversations?",
                zh: "清空全部对话记录？",
                ja: "会話をすべて消しますか？",
                ko: "모든 대화를 지울까요?"
            ),
            isPresented: $showsClearConfirmation
        ) {
            Button(
                LocalizedString.l(lang, en: "Clear", zh: "清空", ja: "消去", ko: "지우기"),
                role: .destructive
            ) {
                coordinator.reset()
            }
            Button(
                LocalizedString.l(lang, en: "Cancel", zh: "取消", ja: "キャンセル", ko: "취소"),
                role: .cancel
            ) {}
        } message: {
            Text(
                LocalizedString.l(
                    lang,
                    en: "Every saved message will be deleted. This cannot be undone.",
                    zh: "会删掉所有已保存的消息，无法恢复。",
                    ja: "保存されたメッセージがすべて削除され、元に戻せません。",
                    ko: "저장된 메시지가 모두 삭제되며 되돌릴 수 없습니다."
                )
            )
        }
    }

    // MARK: - 对话区

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if coordinator.messages.isEmpty && !coordinator.isRunning {
                        emptyState
                    }

                    ForEach(coordinator.messages) { message in
                        AgentMessageBubble(message: message, onDelete: {
                            coordinator.deleteMessage(id: message.id)
                        })
                        .id(message.id)
                    }

                    if coordinator.isRunning {
                        liveSection
                            .id("live")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .onChange(of: coordinator.messages.count) { _, _ in scroll(proxy) }
            .onChange(of: coordinator.streamingText) { _, _ in scroll(proxy) }
            .onChange(of: coordinator.activities.count) { _, _ in scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedString.l(lang, en: "Pick a scenario, or just ask", zh: "点一个场景，或者直接说", ja: "シナリオを選ぶか、そのまま話しかけてください", ko: "시나리오를 고르거나 그냥 말해 보세요"))
                    .font(.system(size: 14, weight: .semibold))
                Text(LocalizedString.l(lang, en: "The agent picks its own tools, reads the data, then tells you what it found.", zh: "Agent 会自己挑工具、读数据，再把结论讲给你听。", ja: "Agent が自分でツールを選び、データを読んで、結論を教えてくれます。", ko: "Agent가 스스로 도구를 고르고 데이터를 읽은 뒤 결론을 알려 줍니다."))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                ForEach(recipes) { recipe in
                    recipeCard(recipe)
                }
            }

            Text(LocalizedString.l(lang, en: "Type / for shortcuts　·　Chats are stored locally and can be deleted one by one", zh: "输入 / 查看快捷指令　·　对话会保存在本地，可逐条删除", ja: "「/」でショートカット一覧　·　会話はローカルに保存され、1 件ずつ削除できます", ko: "/ 를 입력해 단축 명령 보기　·　대화는 로컬에 저장되며 하나씩 삭제할 수 있습니다"))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.75))
        }
        .padding(.top, 4)
    }

    private var recipes: [AgentRecipe] { AgentRecipeStore.shared.all }

    private func recipeCard(_ recipe: AgentRecipe) -> some View {
        Button {
            run(recipe)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: recipe.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.accent)

                Text(recipe.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(1)

                Text(recipe.subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(AppTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(AppTheme.textSecondary(colorScheme).opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(coordinator.isRunning)
        .help(recipe.needsInput ? (recipe.inputHint ?? "") : recipe.prompt)
    }

    private func run(_ recipe: AgentRecipe) {
        guard !coordinator.isRunning else { return }
        if recipe.needsInput {
            inputText = recipe.prompt + "\n"
            inputFocused = true
        } else {
            coordinator.send(recipe.prompt)
        }
    }

    // MARK: - 运行中

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(coordinator.activities) { activity in
                ToolActivityCard(activity: activity)
            }

            if !coordinator.streamingText.isEmpty {
                Text(AgentMarkdown.render(coordinator.streamingText))
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .appCardSurface(cornerRadius: 10, showsShadow: false)
            } else if coordinator.activities.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(LocalizedString.l(lang, en: "Thinking…", zh: "思考中…", ja: "考え中…", ko: "생각 중…"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }
        }
    }

    // MARK: - 错误条

    private func errorBar(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.critical)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.critical)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Button {
                    coordinator.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
            }

            // 报错不该只让人知道"错了"。配置问题给去设置的入口，其他问题给重试——
            // 这两件事覆盖了九成的失败场景。
            HStack(spacing: 6) {
                if AgentCoordinator.looksLikeConfigurationProblem(message) {
                    Button {
                        showsSettings = true
                    } label: {
                        Text(LocalizedString.l(lang, en: "Open settings", zh: "去设置", ja: "設定を開く", ko: "설정 열기"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }

                if coordinator.hasUserMessage {
                    Button {
                        coordinator.retryLast()
                    } label: {
                        Label(LocalizedString.l(lang, en: "Retry", zh: "重试", ja: "再試行", ko: "다시 시도"), systemImage: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(coordinator.isRunning)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.critical.opacity(0.08))
    }

    // MARK: - 确认条

    private func approvalBar(_ request: AgentApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
                Text(LocalizedString.l(lang, en: "Agent wants to run \"\(request.toolName)\"", zh: "Agent 想执行「\(request.toolName)」", ja: "Agent が「\(request.toolName)」を実行しようとしています", ko: "Agent가 \"\(request.toolName)\" 실행을 요청합니다"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }

            Text(request.summary)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if !request.argumentsText.isEmpty, request.argumentsText != "{}" {
                Text(request.argumentsText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button(LocalizedString.l(lang, en: "Allow", zh: "允许", ja: "許可", ko: "허용")) {
                    coordinator.resolveApproval(true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(LocalizedString.l(lang, en: "Deny", zh: "拒绝", ja: "拒否", ko: "거부")) {
                    coordinator.resolveApproval(false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text(LocalizedString.l(lang, en: "Auto-denies in 90 s", zh: "90 秒后自动拒绝", ja: "90 秒後に自動で拒否", ko: "90초 후 자동 거부"))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.warning.opacity(0.12))
    }

    // MARK: - 输入区

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(spacing: 8) {
                TextField(LocalizedString.l(lang, en: "Ask something, or type / for commands…", zh: "问点什么，或输入 / 看指令…", ja: "何か聞くか、「/」でコマンド一覧…", ko: "무엇이든 물어보거나 / 로 명령 보기…"), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 10))

                if coordinator.isRunning {
                    Button {
                        coordinator.cancel()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.critical)
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedString.l(lang, en: "Stop", zh: "停止", ja: "停止", ko: "중지"))
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(canSend ? AppTheme.accent : AppTheme.textSecondary(colorScheme).opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help(LocalizedString.l(lang, en: "Send", zh: "发送", ja: "送信", ko: "보내기"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func send() {
        let text = inputText
        inputText = ""

        if let command = AgentCommandParser.parse(text, recipes: recipes) {
            let handled = coordinator.runCommand(command)
            if !handled { showsSettings = true }
            return
        }

        coordinator.send(text)
    }
}

// MARK: - 消息气泡

struct AgentMessageBubble: View {
    let message: AgentHistoryEntry
    var onDelete: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appSettings = AppSettings.shared

    private var lang: AppLanguage { appSettings.language }

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            Text(AgentMarkdown.render(message.content))
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    isUser ? AppTheme.accent.opacity(0.14) : AppTheme.surface(colorScheme),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contextMenu {
                    Button(LocalizedString.l(lang, en: "Copy", zh: "复制", ja: "コピー", ko: "복사")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    }
                    if let onDelete {
                        Divider()
                        Button(LocalizedString.l(lang, en: "Delete this message", zh: "删除这条", ja: "このメッセージを削除", ko: "이 메시지 삭제"), role: .destructive, action: onDelete)
                    }
                }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - 工具调用卡片

struct ToolActivityCard: View {
    let activity: AgentToolActivity
    @State private var expanded = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appSettings = AppSettings.shared

    private var lang: AppLanguage { appSettings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(iconColor)

                    Text(activity.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))

                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !activity.argumentsText.isEmpty, activity.argumentsText != "{}" {
                        detailBlock(
                            title: LocalizedString.l(lang, en: "Arguments", zh: "参数", ja: "引数", ko: "인수"),
                            text: activity.argumentsText
                        )
                    }
                    if let output = activity.output {
                        detailBlock(
                            title: activity.isError
                                ? LocalizedString.l(lang, en: "Error", zh: "错误", ja: "エラー", ko: "오류")
                                : LocalizedString.l(lang, en: "Result", zh: "结果", ja: "結果", ko: "결과"),
                            text: output
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(AppTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(activity.isError ? AppTheme.critical.opacity(0.4) : AppTheme.stroke(colorScheme), lineWidth: 0.5)
        )
    }

    private var iconName: String {
        if activity.isError { return "exclamationmark.circle.fill" }
        return activity.isFinished ? "checkmark.circle.fill" : "circle.dotted"
    }

    private var iconColor: Color {
        if activity.isError { return AppTheme.critical }
        return activity.isFinished ? AppTheme.healthy : AppTheme.warning
    }

    private var statusText: String {
        if activity.isError {
            return LocalizedString.l(lang, en: "Failed", zh: "失败", ja: "失敗", ko: "실패")
        }
        return activity.isFinished
            ? LocalizedString.l(lang, en: "Done", zh: "完成", ja: "完了", ko: "완료")
            : LocalizedString.l(lang, en: "Running", zh: "执行中", ja: "実行中", ko: "실행 중")
    }

    private func detailBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .textSelection(.enabled)
                .lineLimit(12)
        }
    }
}

// MARK: - 设置面板

struct AgentSettingsPanel: View {
    let onClose: () -> Void
    @State private var settings = AgentSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appSettings = AppSettings.shared

    private var lang: AppLanguage { appSettings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(LocalizedString.l(lang, en: "Back to chat", zh: "返回对话", ja: "会話に戻る", ko: "대화로 돌아가기"))

                Text(LocalizedString.l(lang, en: "Agent settings", zh: "Agent 设置", ja: "Agent 設定", ko: "Agent 설정"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button(LocalizedString.l(lang, en: "Done", zh: "完成", ja: "完了", ko: "완료")) { onClose() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field(title: LocalizedString.l(lang, en: "Engine", zh: "引擎", ja: "エンジン", ko: "엔진")) {
                        AgentEngineSettingsSection()
                    }

                    field(title: LocalizedString.l(lang, en: "Protocol", zh: "接入协议", ja: "接続プロトコル", ko: "연결 프로토콜")) {
                        Picker("", selection: $settings.protocolKind) {
                            ForEach(AgentWireProtocol.allCases) { kind in
                                Text(kind.shortName).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .onChange(of: settings.protocolKind) { _, _ in
                            settings.applyProtocolDefaults()
                        }
                        Text(settings.protocolKind.subtitle(lang))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }

                    field(title: LocalizedString.l(lang, en: "Endpoint", zh: "接口地址", ja: "エンドポイント", ko: "엔드포인트")) {
                        TextField("https://…", text: $settings.baseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    field(title: LocalizedString.l(lang, en: "Model", zh: "模型", ja: "モデル", ko: "모델")) {
                        TextField(LocalizedString.l(lang, en: "Model name", zh: "模型名称", ja: "モデル名", ko: "모델 이름"), text: $settings.model)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    if settings.requiresAPIKey {
                        field(title: "API Key") {
                            SecureField("sk-…", text: $settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            Text(LocalizedString.l(lang, en: "Stored in the system Keychain, never written to preferences.", zh: "保存在系统钥匙串，不会写入偏好文件。", ja: "システムキーチェーンに保存され、設定ファイルには書き込まれません。", ko: "시스템 키체인에 저장되며 환경설정 파일에는 기록되지 않습니다."))
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        }
                    }

                    field(title: LocalizedString.l(lang, en: "Tool call limit", zh: "工具调用上限", ja: "ツール呼び出し上限", ko: "도구 호출 한도")) {
                        Stepper(
                            LocalizedString.l(lang, en: "Up to \(settings.maxRounds) rounds", zh: "最多 \(settings.maxRounds) 轮", ja: "最大 \(settings.maxRounds) ラウンド", ko: "최대 \(settings.maxRounds) 라운드"),
                            value: $settings.maxRounds,
                            in: 1...12
                        )
                            .font(.system(size: 11))
                    }

                    Divider().opacity(0.4)

                    Button {
                        settings.adoptFromAssistant()
                    } label: {
                        Label(LocalizedString.l(lang, en: "Sync from AI Assistant", zh: "从 AI 助手同步配置", ja: "AI アシスタントから同期", ko: "AI 어시스턴트에서 동기화"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)

                    field(title: LocalizedString.l(lang, en: "Tool permissions", zh: "工具权限", ja: "ツール権限", ko: "도구 권한")) {
                        Picker("", selection: $settings.toolLevel) {
                            ForEach(ToolPermission.allCases, id: \.self) { permission in
                                Text(permissionLabel(permission)).tag(permission)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Text(LocalizedString.l(lang, en: "Tools at L2 and above ask for confirmation before every run.", zh: "L2 及以上的工具在每次执行前都会弹确认条。", ja: "L2 以上のツールは実行のたびに確認バーが出ます。", ko: "L2 이상 도구는 실행할 때마다 확인 바가 표시됩니다."))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            content()
        }
    }

    private func permissionLabel(_ permission: ToolPermission) -> String {
        switch permission {
        case .read:
            return LocalizedString.l(lang, en: "Read-only (L0)", zh: "只读（L0）", ja: "読み取り専用（L0）", ko: "읽기 전용(L0)")
        case .reversible:
            return LocalizedString.l(lang, en: "Reversible write (L1)", zh: "可逆写入（L1）", ja: "可逆書き込み（L1）", ko: "되돌릴 수 있는 쓰기(L1)")
        case .persistent:
            return LocalizedString.l(lang, en: "Persistent write (L2, confirm each time)", zh: "持久写入（L2，每次确认）", ja: "永続書き込み（L2、毎回確認）", ko: "영구 쓰기(L2, 매번 확인)")
        case .dangerous:
            return LocalizedString.l(lang, en: "Dangerous (L3, off by default)", zh: "危险（L3，默认关闭）", ja: "危険（L3、既定でオフ）", ko: "위험(L3, 기본 꺼짐)")
        }
    }
}
