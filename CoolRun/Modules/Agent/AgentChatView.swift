import AppKit
import SwiftUI

// MARK: - Agent 对话视图

struct AgentChatView: View {
    @State private var coordinator = AgentCoordinator.shared
    @State private var settings = AgentSettings.shared
    @State private var inputText = ""
    @State private var showsSettings = false
    @State private var showsTools = false
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                        Text("未配置模型 · 去设置")
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
            .help("工具")

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Agent 设置")

            Button {
                coordinator.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("清空对话")
            .disabled(coordinator.isRunning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                Text("点一个场景，或者直接说")
                    .font(.system(size: 14, weight: .semibold))
                Text("Agent 会自己挑工具、读数据，再把结论讲给你听。")
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

            Text("输入 / 查看快捷指令　·　对话会保存在本地，可逐条删除")
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
                Text(coordinator.streamingText)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .appCardSurface(cornerRadius: 10, showsShadow: false)
            } else if coordinator.activities.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("思考中…")
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
                        Text("去设置")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }

                if coordinator.hasUserMessage {
                    Button {
                        coordinator.retryLast()
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
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
                Text("Agent 想执行「\(request.toolName)」")
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
                Button("允许") {
                    coordinator.resolveApproval(true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("拒绝") {
                    coordinator.resolveApproval(false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text("90 秒后自动拒绝")
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
                TextField("问点什么，或输入 / 看指令…", text: $inputText, axis: .vertical)
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
                    .help("停止")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(canSend ? AppTheme.accent : AppTheme.textSecondary(colorScheme).opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("发送")
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

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            Text(message.content)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    isUser ? AppTheme.accent.opacity(0.14) : AppTheme.surface(colorScheme),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contextMenu {
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    }
                    if let onDelete {
                        Divider()
                        Button("删除这条", role: .destructive, action: onDelete)
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
                        detailBlock(title: "参数", text: activity.argumentsText)
                    }
                    if let output = activity.output {
                        detailBlock(title: activity.isError ? "错误" : "结果", text: output)
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
        if activity.isError { return "失败" }
        return activity.isFinished ? "完成" : "执行中"
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
                .help("返回对话")

                Text("Agent 设置")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button("完成") { onClose() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field(title: "引擎") {
                        AgentEngineSettingsSection()
                    }

                    field(title: "接入协议") {
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
                        Text(settings.protocolKind.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }

                    field(title: "接口地址") {
                        TextField("https://…", text: $settings.baseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    field(title: "模型") {
                        TextField("模型名称", text: $settings.model)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    if settings.requiresAPIKey {
                        field(title: "API Key") {
                            SecureField("sk-…", text: $settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            Text("保存在系统钥匙串，不会写入偏好文件。")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        }
                    }

                    field(title: "工具调用上限") {
                        Stepper("最多 \(settings.maxRounds) 轮", value: $settings.maxRounds, in: 1...12)
                            .font(.system(size: 11))
                    }

                    Divider().opacity(0.4)

                    Button {
                        settings.adoptFromAssistant()
                    } label: {
                        Label("从 AI 助手同步配置", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)

                    field(title: "工具权限") {
                        Picker("", selection: $settings.toolLevel) {
                            ForEach(ToolPermission.allCases, id: \.self) { permission in
                                Text(permissionLabel(permission)).tag(permission)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Text("L2 及以上的工具在每次执行前都会弹确认条。")
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
        case .read: return "只读（L0）"
        case .reversible: return "可逆写入（L1）"
        case .persistent: return "持久写入（L2，每次确认）"
        case .dangerous: return "危险（L3，默认关闭）"
        }
    }
}
