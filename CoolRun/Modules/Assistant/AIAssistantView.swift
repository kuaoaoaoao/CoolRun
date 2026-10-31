import SwiftUI
import AppKit

// MARK: - AI 助手视图

@MainActor
struct AIAssistantView: View {
    @State private var service = LLMService.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var showConfigSheet = false
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var language: AppLanguage { appSettings.language }

    // 预置快捷问题
    private var quickQuestions: [QuickQuestion] {
        [
            QuickQuestion(icon: "cpu", text: LocalizedString.l(language, en: "How's my CPU usage?", zh: "我的 CPU 占用多少？", ja: "CPU使用率は？", ko: "CPU 사용량은?")),
            QuickQuestion(icon: "chart.line.uptrend.xyaxis", text: LocalizedString.l(language, en: "How is gold doing today?", zh: "今天金价怎么样？", ja: "今日の金価格は？", ko: "오늘 금 시세는?")),
            QuickQuestion(icon: "sparkles", text: LocalizedString.l(language, en: "What's slowing my Mac down?", zh: "我的 Mac 卡在哪里？", ja: "Macが重い原因は？", ko: "Mac이 느린 이유는?")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            moduleHeader

            if !service.isConfigured {
                setupPrompt
            } else {
                chatArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appCardSurface(cornerRadius: 12)
        .sheet(isPresented: $showConfigSheet) {
            LLMConfigSheet()
        }
    }

    // MARK: - 头部

    private var moduleHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(
                    AppTheme.accent.opacity(colorScheme == .dark ? 0.20 : 0.13),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedString.l(
                    language,
                    en: "AI Assistant",
                    zh: "AI 助手",
                    ja: "AI アシスタント",
                    ko: "AI 도우미"
                ))
                .font(.system(size: 12.5, weight: .bold))

                Text(service.isConfigured
                     ? service.providerDisplayName
                     : LocalizedString.l(language, en: "Not configured", zh: "未配置", ja: "未設定", ko: "설정 안 됨"))
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .lineLimit(1)

            Spacer(minLength: 4)

            if service.isConfigured {
                Circle()
                    .fill(AppTheme.healthy)
                    .frame(width: 6, height: 6)
            }

            // 清空对话
            if !messages.isEmpty {
                Button {
                    messages.removeAll()
                    service.clearError()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .frame(width: 26, height: 26)
                        .background(
                            AppTheme.progressBg(colorScheme).opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(LocalizedString.l(language, en: "Clear conversation", zh: "清空对话", ja: "会話をクリア", ko: "대화 지우기"))
            }

            // 配置
            Button {
                showConfigSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .frame(width: 26, height: 26)
                    .background(
                        AppTheme.progressBg(colorScheme).opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(LocalizedString.l(language, en: "Configure provider", zh: "配置服务商", ja: "プロバイダ設定", ko: "제공자 설정"))
        }
        .padding(.horizontal, GoldLayout.contentInset)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - 未配置提示

    private var setupPrompt: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppTheme.accent.opacity(0.5))

            Text(LocalizedString.l(
                language,
                en: "Connect a model to get started",
                zh: "连接一个模型开始使用",
                ja: "モデルを接続して開始",
                ko: "모델을 연결하여 시작하세요"
            ))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Text(LocalizedString.l(
                language,
                en: "Your API key is stored in the macOS Keychain. Requests go directly from this Mac to the provider you choose.",
                zh: "API Key 保存在 macOS 钥匙串中，请求由本机直接发送到你选择的服务商。",
                ja: "APIキーはmacOSキーチェーンに保存されます。リクエストは本機から選択したプロバイダへ直接送信されます。",
                ko: "API 키는 macOS 키체인에 저장됩니다. 요청은 이 Mac에서 선택한 제공자로 직접 전송됩니다."
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)

            VStack(spacing: 6) {
                ForEach(LLMProviderKind.allCases) { kind in
                    providerButton(kind)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, GoldLayout.contentInset)
    }

    private func providerButton(_ kind: LLMProviderKind) -> some View {
        Button {
            showConfigSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    Text(kind.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.progressBg(colorScheme).opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 聊天区域

    private var chatArea: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            welcomeSection
                        }

                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if service.isLoading {
                            typingIndicator
                        }

                        if let error = service.lastError, !service.isLoading {
                            ErrorBubble(error: error)
                        }
                    }
                    .padding(.horizontal, GoldLayout.contentInset)
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: service.isLoading) { _, loading in
                    guard !loading, let last = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            inputBar
        }
    }

    private var welcomeSection: some View {
        VStack(spacing: 12) {
            Text(LocalizedString.l(
                language,
                en: "What can I help you with?",
                zh: "有什么可以帮您的？",
                ja: "何かお手伝いできることは？",
                ko: "무엇을 도와드릴까요?"
            ))
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary(colorScheme))

            FlowLayout(spacing: 6) {
                ForEach(quickQuestions) { question in
                    Button {
                        sendMessage(question.text)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: question.icon)
                                .font(.system(size: 9))
                            Text(question.text)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(AppTheme.accent)
                        .background(AppTheme.accent.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.mini)
            Text(LocalizedString.l(language, en: "Thinking…", zh: "思考中…", ja: "考え中…", ko: "생각 중…"))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(
                LocalizedString.l(language, en: "Ask anything…", zh: "输入问题…", ja: "質問を入力…", ko: "질문을 입력하세요…"),
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))
            .lineLimit(1...4)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onSubmit {
                sendMessage(inputText)
            }

            Button {
                sendMessage(inputText)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isLoading
                            ? AppTheme.textSecondary(colorScheme).opacity(0.3)
                            : AppTheme.accent
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isLoading)
        }
        .padding(.horizontal, GoldLayout.contentInset)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.5))
    }

    // MARK: - 发送消息

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !service.isLoading else { return }

        messages.append(ChatMessage(role: .user, content: trimmed))
        inputText = ""

        Task {
            let context = await buildContext(for: trimmed)
            let systemPrompt = LLMService.defaultSystemPrompt + "\n\n" + context

            if let response = await service.askWithContext(userQuestion: trimmed, systemContext: systemPrompt) {
                messages.append(ChatMessage(role: .assistant, content: response))
            }
        }
    }

    /// 根据用户问题挑选相关数据注入上下文，避免把无关数据全部发给模型。
    private func buildContext(for question: String) async -> String {
        let lowercased = question.lowercased()
        var contexts: [String] = []

        let asksSystem = ["cpu", "memory", "ram", "battery", "disk", "storage", "slow", "hot", "temperature", "system", "mac",
                          "内存", "电池", "磁盘", "卡", "慢", "温度", "系统", "电脑",
                          "メモリ", "バッテリー", "遅い", "温度", "システム",
                          "메모리", "배터리", "느린", "온도", "시스템"]
            .contains { lowercased.contains($0) }

        if asksSystem {
            let snapshot = await sampleSystem()
            contexts.append(LLMContextBuilder.systemContext(snapshot))
        }

        let asksGold = ["gold", "price", "buy", "sell", "invest", "黄金", "金价", "买", "卖", "投资", "金価格", "금", "금값"]
            .contains { lowercased.contains($0) }

        if asksGold {
            contexts.append(LLMContextBuilder.goldContext(GoldPriceStore.shared))
            contexts.append("Reminder: gold analysis is reference only and is not investment advice.")
        }

        let asksQuota = ["codex", "claude", "quota", "limit", "token", "配额", "额度", "用量", "クォータ", "할당량"]
            .contains { lowercased.contains($0) }

        if asksQuota {
            contexts.append(LLMContextBuilder.aiQuotaContext())
        }

        if contexts.isEmpty {
            return "No specific module data was requested. Answer generally and ask a clarifying question if needed."
        }
        return contexts.joined(separator: "\n\n")
    }

    /// CPU 占用需要两次采样求差值，因此先预热一次再取值。
    private func sampleSystem() async -> SystemSnapshot {
        let sampler = SystemSampler()
        _ = sampler.sample(includeProcesses: false)
        try? await Task.sleep(for: .milliseconds(350))
        return sampler.sample(includeProcesses: true, mergeProcesses: true)
    }
}

// MARK: - 聊天消息模型

/// 快捷问题条目
private struct QuickQuestion: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()

    enum MessageRole {
        case user
        case assistant
        case error
    }
}

// MARK: - 消息气泡

struct MessageBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 36) }

            Text(message.content)
                .font(.system(size: 11.5))
                .foregroundStyle(isUser ? Color.white : AppTheme.textPrimary(colorScheme))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    isUser
                        ? AnyShapeStyle(AppTheme.accent)
                        : AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .fixedSize(horizontal: false, vertical: true)

            if !isUser { Spacer(minLength: 36) }
        }
    }
}

// MARK: - 错误气泡

struct ErrorBubble: View {
    let error: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.critical)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(AppTheme.critical.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
        }
    }
}

// MARK: - 流式布局

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let result = FlowResult(in: width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { continue }
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x,
                            y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var maxX: CGFloat = 0

            for subview in subviews {
                let itemSize = subview.sizeThatFits(.unspecified)
                if x > 0, x + itemSize.width > maxWidth {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, itemSize.height)
                x += itemSize.width + spacing
                maxX = max(maxX, x - spacing)
            }

            size = CGSize(width: max(maxX, 0), height: y + rowHeight)
        }
    }
}
