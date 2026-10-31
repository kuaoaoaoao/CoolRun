import SwiftUI
import AppKit

// MARK: - AI 监控容器（Codex / Claude 切换）

struct AIMonitorView: View {
    @AppStorage("ai_monitor_tab") private var selectedTab = "overview"
    @State private var codexViewModel: CodexMonitorViewModel
    @State private var claudeViewModel: ClaudeMonitorViewModel
    @ObservedObject private var settings = AppSettings.shared

    @MainActor
    init() {
        _codexViewModel = State(initialValue: .shared)
        _claudeViewModel = State(initialValue: .shared)
    }

    @MainActor
    init(
        codexViewModel: CodexMonitorViewModel,
        claudeViewModel: ClaudeMonitorViewModel
    ) {
        _codexViewModel = State(initialValue: codexViewModel)
        _claudeViewModel = State(initialValue: claudeViewModel)
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $selectedTab) {
                Text(overviewTitle).tag("overview")
                Text("Codex").tag("codex")
                Text("Claude").tag("claude")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 2)

            if selectedTab == "overview" {
                AIUsageOverviewView(
                    codexViewModel: codexViewModel,
                    claudeViewModel: claudeViewModel,
                    onSelectProvider: { selectedTab = $0 }
                )
            } else if selectedTab == "claude" {
                ClaudeMonitorView(viewModel: claudeViewModel)
            } else {
                CodexMonitorView(viewModel: codexViewModel)
            }
        }
        .onAppear {
            codexViewModel.start()
            claudeViewModel.start()
        }
        .onDisappear {
            codexViewModel.stop()
            claudeViewModel.stop()
        }
    }

    private var overviewTitle: String {
        LocalizedString.l(
            settings.language,
            en: "Overview",
            zh: "总览",
            ja: "概要",
            ko: "개요"
        )
    }
}

private enum AIProviderAvailability: Equatable {
    case loading
    case ready
    case unavailable(String)
    case notLoggedIn(String)
}

private struct AIProviderOverview: Equatable, Identifiable {
    let id: String
    let name: String
    let account: String?
    let plan: String?
    let remainingPercent: Int?
    let windowTitle: String?
    let resetsAt: Date?
    let pace: CodexQuotaPace.Status?
    let updatedAt: Date?
    let availability: AIProviderAvailability
}

private enum AIProviderOverviewBuilder {
    static func codex(_ state: CodexMonitorState) -> AIProviderOverview {
        switch state {
        case .loading:
            return placeholder(id: "codex", name: "Codex", availability: .loading)
        case let .unavailable(message):
            return placeholder(id: "codex", name: "Codex", availability: .unavailable(message))
        case let .notLoggedIn(message):
            return placeholder(id: "codex", name: "Codex", availability: .notLoggedIn(message))
        case let .ready(snapshot):
            let constrainedWindow = snapshot.limits
                .flatMap { limit in
                    limit.windows.map { (limit.title, $0) }
                }
                .filter { $0.1.remainingPercent != nil }
                .min { ($0.1.remainingPercent ?? 101) < ($1.1.remainingPercent ?? 101) }
            return AIProviderOverview(
                id: "codex",
                name: "Codex",
                account: snapshot.account,
                plan: snapshot.plan,
                remainingPercent: constrainedWindow?.1.remainingPercent,
                windowTitle: constrainedWindow.map { "\($0.0) · \($0.1.title)" },
                resetsAt: constrainedWindow?.1.resetsAt,
                pace: constrainedWindow?.1.pace()?.status,
                updatedAt: snapshot.updatedAt,
                availability: .ready
            )
        }
    }

    static func claude(_ state: ClaudeMonitorState) -> AIProviderOverview {
        switch state {
        case .loading:
            return placeholder(id: "claude", name: "Claude", availability: .loading)
        case let .unavailable(message):
            return placeholder(id: "claude", name: "Claude", availability: .unavailable(message))
        case let .notLoggedIn(message):
            return placeholder(id: "claude", name: "Claude", availability: .notLoggedIn(message))
        case let .ready(snapshot):
            let constrainedWindow = snapshot.windows
                .filter { $0.remainingPercent != nil }
                .min { ($0.remainingPercent ?? 101) < ($1.remainingPercent ?? 101) }
            return AIProviderOverview(
                id: "claude",
                name: "Claude",
                account: snapshot.account,
                plan: snapshot.plan,
                remainingPercent: constrainedWindow?.remainingPercent,
                windowTitle: constrainedWindow?.title,
                resetsAt: constrainedWindow?.resetsAt,
                pace: constrainedWindow?.pace()?.status,
                updatedAt: snapshot.updatedAt,
                availability: .ready
            )
        }
    }

    private static func placeholder(
        id: String,
        name: String,
        availability: AIProviderAvailability
    ) -> AIProviderOverview {
        AIProviderOverview(
            id: id,
            name: name,
            account: nil,
            plan: nil,
            remainingPercent: nil,
            windowTitle: nil,
            resetsAt: nil,
            pace: nil,
            updatedAt: nil,
            availability: availability
        )
    }
}

private struct AIUsageOverviewView: View {
    let codexViewModel: CodexMonitorViewModel
    let claudeViewModel: ClaudeMonitorViewModel
    let onSelectProvider: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        AppTheme.accent.opacity(colorScheme == .dark ? 0.2 : 0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(refreshLabel, systemImage: "arrow.clockwise", action: refreshAll)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .disabled(isRefreshing)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    providerCard(codexSummary, tint: AppTheme.accent, symbol: "sparkles")
                    providerCard(claudeSummary, tint: AppTheme.warning, symbol: "asterisk")

                    HStack {
                        Label(summaryHint, systemImage: "arrow.right.circle")
                        Spacer()
                        if let lastUpdated {
                            Text(lastUpdated.formatted(date: .omitted, time: .shortened))
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appCardSurface(cornerRadius: 12)
    }

    private var codexSummary: AIProviderOverview {
        AIProviderOverviewBuilder.codex(codexViewModel.state)
    }

    private var claudeSummary: AIProviderOverview {
        AIProviderOverviewBuilder.claude(claudeViewModel.state)
    }

    private var isRefreshing: Bool {
        codexViewModel.isRefreshing || claudeViewModel.isRefreshing
    }

    private var lastUpdated: Date? {
        [codexSummary.updatedAt, claudeSummary.updatedAt]
            .compactMap { $0 }
            .max()
    }

    private func providerCard(
        _ summary: AIProviderOverview,
        tint: Color,
        symbol: String
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.18)) {
                onSelectProvider(summary.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.textPrimary(colorScheme))
                        Text(providerSubtitle(summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    availabilityBadge(summary.availability, tint: tint)
                }

                switch summary.availability {
                case .ready:
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(summary.remainingPercent.map(String.init) ?? "--")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(quotaColor(summary.remainingPercent))
                        Text(percentAvailable)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let windowTitle = summary.windowTitle {
                            Text(windowTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    AIQuotaRunway(
                        remainingPercent: summary.remainingPercent,
                        tint: quotaColor(summary.remainingPercent),
                        accessibilityText: runwayAccessibilityText(summary)
                    )

                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .accessibilityHidden(true)
                        Text(resetCountdown(summary.resetsAt))
                        Spacer()
                        if let pace = summary.pace {
                            Text(paceText(pace))
                                .foregroundStyle(paceColor(pace))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .loading:
                    ProgressView(loadingText)
                        .controlSize(.small)
                        .font(.caption)
                case let .unavailable(message), let .notLoggedIn(message):
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.elevatedSurface(colorScheme),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.2 : 0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(openDetailsHint)
    }

    @ViewBuilder
    private func availabilityBadge(
        _ availability: AIProviderAvailability,
        tint: Color
    ) -> some View {
        switch availability {
        case .ready:
            Label(connectedText, systemImage: "checkmark.circle.fill")
                .foregroundStyle(tint)
        case .loading:
            Text(loadingShortText)
                .foregroundStyle(.secondary)
        case .unavailable:
            Label(unavailableText, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)
        case .notLoggedIn:
            Label(loginText, systemImage: "person.crop.circle.badge.xmark")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshAll() {
        Task { await codexViewModel.refresh() }
        Task { await claudeViewModel.refresh() }
    }

    private func providerSubtitle(_ summary: AIProviderOverview) -> String {
        let metadata: [String] = [summary.plan, summary.account]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return metadata.isEmpty ? providerWaitingText : metadata.joined(separator: " · ")
    }

    private func runwayAccessibilityText(_ summary: AIProviderOverview) -> String {
        "\(summary.name) \(summary.remainingPercent ?? 0)% \(percentAvailable)"
    }

    private func quotaColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        return value <= 10 ? AppTheme.critical : value <= 25 ? AppTheme.warning : AppTheme.healthy
    }

    private func paceText(_ status: CodexQuotaPace.Status) -> String {
        switch status {
        case .balanced: return localized(en: "On pace", zh: "节奏正常", ja: "適正ペース", ko: "정상 속도")
        case .comfortable: return localized(en: "Comfortable", zh: "额度充足", ja: "余裕あり", ko: "여유 있음")
        case .fast: return localized(en: "Using fast", zh: "消耗偏快", ja: "消費が速い", ko: "빠른 소모")
        case .critical: return localized(en: "Low quota", zh: "额度紧张", ja: "残量わずか", ko: "할당량 부족")
        }
    }

    private func paceColor(_ status: CodexQuotaPace.Status) -> Color {
        switch status {
        case .balanced: return AppTheme.accent
        case .comfortable: return AppTheme.healthy
        case .fast: return AppTheme.warning
        case .critical: return AppTheme.critical
        }
    }

    private func resetCountdown(_ date: Date?) -> String {
        guard let date else { return resetUnknownText }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds < 60 { return localized(en: "Resets in <1m", zh: "不到 1 分钟后重置", ja: "1分以内にリセット", ko: "1분 내 초기화") }
        if seconds < 3_600 { return localized(en: "Resets in \(seconds / 60)m", zh: "\(seconds / 60) 分钟后重置", ja: "\(seconds / 60)分後にリセット", ko: "\(seconds / 60)분 후 초기화") }
        if seconds < 86_400 {
            let hours = seconds / 3_600
            return localized(en: "Resets in \(hours)h", zh: "\(hours) 小时后重置", ja: "\(hours)時間後にリセット", ko: "\(hours)시간 후 초기화")
        }
        let days = seconds / 86_400
        return localized(en: "Resets in \(days)d", zh: "\(days) 天后重置", ja: "\(days)日後にリセット", ko: "\(days)일 후 초기화")
    }

    private func localized(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }

    private var title: String { localized(en: "AI quota runway", zh: "AI 额度跑道", ja: "AI クォータ状況", ko: "AI 할당량 현황") }
    private var subtitle: String { localized(en: "See the tightest limit first", zh: "优先显示最紧张的额度窗口", ja: "最も厳しい上限を優先表示", ko: "가장 부족한 한도를 먼저 표시") }
    private var refreshLabel: String { localized(en: "Refresh all providers", zh: "刷新全部 AI 额度", ja: "すべて更新", ko: "모두 새로고침") }
    private var summaryHint: String { localized(en: "Select a card for details", zh: "点击卡片查看完整额度", ja: "カードを選択して詳細を表示", ko: "카드를 선택해 상세 보기") }
    private var percentAvailable: String { localized(en: "% available", zh: "% 可用", ja: "% 利用可能", ko: "% 사용 가능") }
    private var loadingText: String { localized(en: "Reading local account…", zh: "正在读取本机账号…", ja: "ローカルアカウントを確認中…", ko: "로컬 계정 확인 중…") }
    private var loadingShortText: String { localized(en: "Loading", zh: "读取中", ja: "読込中", ko: "불러오는 중") }
    private var connectedText: String { localized(en: "Ready", zh: "已连接", ja: "接続済み", ko: "연결됨") }
    private var unavailableText: String { localized(en: "Unavailable", zh: "暂不可用", ja: "利用不可", ko: "사용 불가") }
    private var loginText: String { localized(en: "Sign in", zh: "需登录", ja: "ログイン", ko: "로그인 필요") }
    private var providerWaitingText: String { localized(en: "Waiting for account data", zh: "等待账号数据", ja: "アカウント情報を待機中", ko: "계정 정보 대기 중") }
    private var resetUnknownText: String { localized(en: "Reset time unknown", zh: "重置时间未知", ja: "リセット時刻不明", ko: "초기화 시간 알 수 없음") }
    private var openDetailsHint: String { localized(en: "Open provider details", zh: "打开提供方额度详情", ja: "プロバイダーの詳細を開く", ko: "제공자 상세 열기") }
}

private struct AIQuotaRunway: View {
    let remainingPercent: Int?
    let tint: Color
    let accessibilityText: String

    private let segmentCount = 10

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < filledSegments ? tint : Color.secondary.opacity(0.14))
                    .frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var filledSegments: Int {
        guard let remainingPercent else { return 0 }
        return max(
            0,
            min(
                segmentCount,
                Int((Double(remainingPercent) / 100 * Double(segmentCount)).rounded())
            )
        )
    }
}

// MARK: - Claude 额度监控视图

struct ClaudeMonitorView: View {
    @State private var viewModel: ClaudeMonitorViewModel
    @Environment(\.colorScheme) private var colorScheme

    @MainActor
    init() {
        _viewModel = State(initialValue: .shared)
    }

    @MainActor
    init(viewModel: ClaudeMonitorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "asterisk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .frame(width: 28, height: 28)
                    .background(
                        AppTheme.warning.opacity(colorScheme == .dark ? 0.19 : 0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude 监控")
                        .font(.headline)
                    Text("Claude Code 5 小时与周额度")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .disabled(viewModel.isRefreshing)
                .accessibilityLabel("刷新 Claude 状态")
                .help("刷新 Claude 状态")
            }

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch viewModel.state {
                    case .loading:
                        ProgressView("正在读取 Claude 用量…")
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case let .unavailable(message):
                        statusCard(icon: "exclamationmark.triangle", color: .orange, title: "暂时无法读取", detail: message)
                    case let .notLoggedIn(detail):
                        statusCard(icon: "person.crop.circle.badge.xmark", color: .secondary, title: "Claude 未登录", detail: detail)
                    case let .ready(snapshot):
                        readyView(snapshot)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appCardSurface(cornerRadius: 12)
    }

    private func readyView(_ snapshot: ClaudeMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(AppTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.account).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if let plan = snapshot.plan {
                        Text(planDisplayName(plan)).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 6) {
                quickAction("用量详情", icon: "gauge.with.dots.needle.50percent") {
                    openURL("https://claude.ai/settings/usage")
                }
                quickAction("打开 Claude", icon: "bubble.left.and.bubble.right") {
                    openURL("https://claude.ai")
                }
            }

            if snapshot.windows.isEmpty {
                Text("暂无额度数据")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }

            ForEach(snapshot.windows) { window in
                quotaRow(window)
                    .padding(9)
                    .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let extra = snapshot.extraUsage {
                extraUsageCard(extra)
            }

            HStack {
                Text("每 60 秒刷新")
                Spacer()
                Text(snapshot.updatedAt.formatted(date: .omitted, time: .standard))
                    .monospacedDigit()
            }
            .font(.system(size: 8)).foregroundStyle(.tertiary)
        }
    }

    private func quotaRow(_ window: CodexQuotaWindow) -> some View {
        let pace = window.pace()
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(window.title) · \(window.durationText)")
                    .font(.system(size: 9, weight: .medium))
                Spacer()
                if let pace {
                    Text(paceText(pace.status))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(paceColor(pace.status))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(paceColor(pace.status).opacity(0.12), in: Capsule())
                }
                Text(window.remainingPercent.map { "\($0)%" } ?? "--")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(quotaColor(window.remainingPercent))
            }
            ClaudeQuotaProgressBar(
                remainingPercent: Double(window.remainingPercent ?? 0),
                expectedRemainingPercent: pace?.expectedRemainingPercent,
                tint: quotaColor(window.remainingPercent)
            )
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(resetCountdown(window.resetsAt))
                Spacer()
                if let pace {
                    Text("节奏线 \(Int(pace.expectedRemainingPercent.rounded()))%")
                } else {
                    Text(resetText(window.resetsAt))
                }
            }
            .font(.system(size: 8.5, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    private func extraUsageCard(_ extra: ClaudeExtraUsage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("按量加购", systemImage: "creditcard")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(String(format: "%.2f / %.0f %@", extra.usedCredits, extra.monthlyLimit, extra.currency ?? "USD"))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
            ClaudeQuotaProgressBar(
                remainingPercent: extra.monthlyLimit > 0
                    ? max(0, min(100, 100 - extra.usedCredits / extra.monthlyLimit * 100))
                    : 0,
                expectedRemainingPercent: nil,
                tint: AppTheme.accent
            )
        }
        .padding(9)
        .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func quickAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusCard(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8))
    }

    private func planDisplayName(_ plan: String) -> String {
        switch plan.lowercased() {
        case "max": return "Claude Max"
        case "pro": return "Claude Pro"
        case "team": return "Claude Team"
        case "enterprise": return "Claude Enterprise"
        default: return plan
        }
    }

    private func quotaColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        return value < 10 ? .red : value < 25 ? .orange : .green
    }

    private func paceText(_ status: CodexQuotaPace.Status) -> String {
        switch status {
        case .balanced: "节奏正常"
        case .comfortable: "额度充足"
        case .fast: "消耗偏快"
        case .critical: "额度紧张"
        }
    }

    private func paceColor(_ status: CodexQuotaPace.Status) -> Color {
        switch status {
        case .balanced: AppTheme.accent
        case .comfortable: AppTheme.healthy
        case .fast: AppTheme.warning
        case .critical: AppTheme.critical
        }
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "--" }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
    }

    private func resetCountdown(_ date: Date?) -> String {
        guard let date else { return "重置时间未知" }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds < 60 { return "不到 1 分钟后重置" }
        if seconds < 3600 { return "\(seconds / 60) 分钟后重置" }
        if seconds < 86_400 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分后重置" : "\(hours) 小时后重置"
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        return hours > 0 ? "\(days) 天 \(hours) 小时后重置" : "\(days) 天后重置"
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ClaudeQuotaProgressBar: View {
    let remainingPercent: Double
    let expectedRemainingPercent: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let clampedRemaining = max(0, min(100, remainingPercent))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: width * clampedRemaining / 100)

                if let expectedRemainingPercent {
                    Rectangle()
                        .fill(.primary.opacity(0.68))
                        .frame(width: 1, height: 9)
                        .offset(x: max(0, min(width - 1, width * expectedRemainingPercent / 100)))
                }
            }
        }
        .frame(height: 5)
        .accessibilityLabel("剩余额度")
        .accessibilityValue("\(Int(remainingPercent.rounded()))%")
    }
}
