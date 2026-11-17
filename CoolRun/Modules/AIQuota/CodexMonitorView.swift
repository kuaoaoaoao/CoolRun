import SwiftUI
import AppKit

struct CodexMonitorView: View {
    @State private var viewModel: CodexMonitorViewModel
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    private var lang: AppLanguage { settings.language }

    private func localized(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }

    @MainActor
    init() {
        _viewModel = State(initialValue: .shared)
    }

    @MainActor
    init(viewModel: CodexMonitorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        AppTheme.accent.opacity(colorScheme == .dark ? 0.19 : 0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(localized(
                        en: "Codex Monitor",
                        zh: "Codex 监控",
                        ja: "Codex モニター",
                        ko: "Codex 모니터"
                    ))
                        .font(.headline)
                    Text(localized(
                        en: "Quota pace, recent tasks and usage",
                        zh: "额度节奏、近期任务与用量",
                        ja: "クォータのペース、最近のタスクと使用量",
                        ko: "할당량 흐름, 최근 작업 및 사용량"
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await viewModel.refresh(lang: lang) }
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
                .accessibilityLabel(localized(
                    en: "Refresh Codex status",
                    zh: "刷新 Codex 状态",
                    ja: "Codex の状態を更新",
                    ko: "Codex 상태 새로고침"
                ))
                .help(localized(
                    en: "Refresh Codex status",
                    zh: "刷新 Codex 状态",
                    ja: "Codex の状態を更新",
                    ko: "Codex 상태 새로고침"
                ))
            }

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch viewModel.state {
                    case .loading:
                        ProgressView(localized(
                            en: "Connecting to local Codex…",
                            zh: "正在连接本机 Codex…",
                            ja: "ローカルの Codex に接続中…",
                            ko: "로컬 Codex에 연결하는 중…"
                        ))
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case let .unavailable(message):
                        statusCard(
                            icon: "exclamationmark.triangle",
                            color: .orange,
                            title: localized(
                                en: "Unable to read right now",
                                zh: "暂时无法读取",
                                ja: "現在読み取れません",
                                ko: "지금은 읽을 수 없습니다"
                            ),
                            detail: message
                        )
                    case let .notLoggedIn(detail):
                        statusCard(
                            icon: "person.crop.circle.badge.xmark",
                            color: .secondary,
                            title: localized(
                                en: "Codex returned no account",
                                zh: "Codex 未返回账号",
                                ja: "Codex がアカウントを返しませんでした",
                                ko: "Codex가 계정을 반환하지 않았습니다"
                            ),
                            detail: detail
                        )
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

    private func readyView(_ snapshot: CodexMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.account).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if let plan = snapshot.plan { Text(plan).font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(8)
            .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 6) {
                quickAction(localized(en: "Open Codex", zh: "打开 Codex", ja: "Codex を開く", ko: "Codex 열기"), icon: "sparkles", action: openCodexApplication)
                quickAction(localized(en: "Quota details", zh: "额度详情", ja: "クォータの詳細", ko: "할당량 상세"), icon: "gauge.with.dots.needle.50percent", action: openUsagePage)
                quickAction(localized(en: "Task files", zh: "任务文件", ja: "タスクファイル", ko: "작업 파일"), icon: "folder", action: openSessionsFolder)
            }

            if snapshot.limits.isEmpty && snapshot.usage == nil {
                Text(localized(
                    en: "No quota or usage data yet",
                    zh: "暂无额度与用量数据",
                    ja: "クォータと使用量のデータがありません",
                    ko: "할당량 및 사용량 데이터가 없습니다"
                ))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }

            ForEach(snapshot.limits) { limit in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(limit.title).font(.system(size: 10, weight: .semibold))
                        Spacer()
                        if limit.id == snapshot.limits.first?.id,
                           let count = snapshot.resetCreditsAvailableCount, count > 0 {
                            Text(localized(
                                en: "\(count) resets available",
                                zh: "可重置 \(count) 次",
                                ja: "\(count) 回リセット可能",
                                ko: "\(count)회 재설정 가능"
                            ))
                                .font(.system(size: 8, weight: .medium)).foregroundStyle(.green)
                        }
                    }
                    ForEach(limit.windows) { window in
                        quotaRow(window)
                    }
                }
                .padding(9)
                .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(snapshot.isRateLimitsStale ? 0.55 : 1)
            }

            if !snapshot.sessions.isEmpty {
                sessionsCard(snapshot.sessions)
            }

            if let usage = snapshot.usage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        usageMetric(localized(en: "Today", zh: "今日", ja: "今日", ko: "오늘"), todayTokens(snapshot.dailyUsage))
                        usageMetric(localized(en: "Total", zh: "累计", ja: "累計", ko: "누적"), compactNumber(usage.lifetimeTokens))
                        usageMetric(localized(en: "Peak", zh: "峰值", ja: "ピーク", ko: "최고"), compactNumber(usage.peakDailyTokens))
                    }
                    HStack(spacing: 4) {
                        usageMetric(localized(en: "Streak", zh: "连续", ja: "連続", ko: "연속"), dayText(usage.currentStreakDays))
                        usageMetric(localized(en: "Longest streak", zh: "最长连续", ja: "最長連続", ko: "최장 연속"), dayText(usage.longestStreakDays))
                        usageMetric(localized(en: "Longest task", zh: "最长任务", ja: "最長タスク", ko: "최장 작업"), durationText(usage.longestRunningTurnSec))
                    }
                    if !snapshot.dailyUsage.isEmpty {
                        CodexUsageHeatmap(buckets: snapshot.dailyUsage)
                    }
                }
                .padding(9)
                .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(snapshot.isUsageStale ? 0.55 : 1)
            }
            HStack {
                if snapshot.isRateLimitsStale || snapshot.isUsageStale {
                    Label(localized(en: "Partly cached", zh: "部分缓存", ja: "一部キャッシュ", ko: "일부 캐시됨"), systemImage: "clock.arrow.circlepath")
                } else {
                    Text(localized(en: "Refreshes every 30s", zh: "每 30 秒刷新", ja: "30 秒ごとに更新", ko: "30초마다 새로고침"))
                }
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
                Text("\(window.title) · \(window.durationText(lang: lang))")
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
            CodexQuotaProgressBar(
                remainingPercent: Double(window.remainingPercent ?? 0),
                expectedRemainingPercent: pace?.expectedRemainingPercent,
                tint: quotaColor(window.remainingPercent)
            )
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(resetCountdown(window.resetsAt))
                Spacer()
                if let pace {
                    Text(localized(
                        en: "Pace \(Int(pace.expectedRemainingPercent.rounded()))%",
                        zh: "节奏线 \(Int(pace.expectedRemainingPercent.rounded()))%",
                        ja: "ペースライン \(Int(pace.expectedRemainingPercent.rounded()))%",
                        ko: "페이스 \(Int(pace.expectedRemainingPercent.rounded()))%"
                    ))
                } else {
                    Text(resetText(window.resetsAt))
                }
            }
            .font(.system(size: 8.5, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    private func sessionsCard(_ sessions: [CodexSessionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(localized(en: "Recent tasks", zh: "近期任务", ja: "最近のタスク", ko: "최근 작업"), systemImage: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                let activeCount = sessions.filter(\.isActive).count
                if activeCount > 0 {
                    Text(localized(
                        en: "\(activeCount) active",
                        zh: "\(activeCount) 个活跃",
                        ja: "\(activeCount) 件アクティブ",
                        ko: "\(activeCount)개 활성"
                    ))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(AppTheme.healthy)
                }
            }

            ForEach(Array(sessions.prefix(3).enumerated()), id: \.element.id) { index, session in
                if index > 0 {
                    Divider().opacity(0.45)
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(fileURLWithPath: session.transcriptPath)
                    ])
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(session.isActive ? AppTheme.healthy : AppTheme.textSecondary(colorScheme).opacity(0.35))
                            .frame(width: 6, height: 6)
                            .shadow(
                                color: session.isActive ? AppTheme.healthy.opacity(0.45) : .clear,
                                radius: 3
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                                .lineLimit(1)
                            Text("\(session.projectName) · \(session.source)")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 5)

                        Text(relativeTime(session.updatedAt))
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(localized(
                    en: "Reveal task log in Finder",
                    zh: "在访达中显示任务记录",
                    ja: "Finder でタスク記録を表示",
                    ko: "Finder에서 작업 기록 보기"
                ))
            }
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

    private func usageMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 9, weight: .semibold, design: .monospaced)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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

    private func quotaColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        return value < 10 ? .red : value < 25 ? .orange : .green
    }

    private func paceText(_ status: CodexQuotaPace.Status) -> String {
        switch status {
        case .balanced: localized(en: "On pace", zh: "节奏正常", ja: "ペース正常", ko: "정상 흐름")
        case .comfortable: localized(en: "Plenty left", zh: "额度充足", ja: "余裕あり", ko: "여유 충분")
        case .fast: localized(en: "Burning fast", zh: "消耗偏快", ja: "消費が速い", ko: "소비 빠름")
        case .critical: localized(en: "Tight", zh: "额度紧张", ja: "残りわずか", ko: "부족")
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
        guard let date else { return localized(en: "Reset time unknown", zh: "重置时间未知", ja: "リセット時刻不明", ko: "재설정 시각 알 수 없음") }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds < 60 { return localized(en: "Resets in under a minute", zh: "不到 1 分钟后重置", ja: "1 分以内にリセット", ko: "1분 이내 재설정") }
        if seconds < 3600 {
            return localized(
                en: "Resets in \(seconds / 60) min",
                zh: "\(seconds / 60) 分钟后重置",
                ja: "\(seconds / 60) 分後にリセット",
                ko: "\(seconds / 60)분 후 재설정"
            )
        }
        if seconds < 86_400 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0
                ? localized(
                    en: "Resets in \(hours) h \(minutes) min",
                    zh: "\(hours) 小时 \(minutes) 分后重置",
                    ja: "\(hours) 時間 \(minutes) 分後にリセット",
                    ko: "\(hours)시간 \(minutes)분 후 재설정"
                )
                : localized(
                    en: "Resets in \(hours) h",
                    zh: "\(hours) 小时后重置",
                    ja: "\(hours) 時間後にリセット",
                    ko: "\(hours)시간 후 재설정"
                )
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        return hours > 0
            ? localized(
                en: "Resets in \(days) d \(hours) h",
                zh: "\(days) 天 \(hours) 小时后重置",
                ja: "\(days) 日 \(hours) 時間後にリセット",
                ko: "\(days)일 \(hours)시간 후 재설정"
            )
            : localized(
                en: "Resets in \(days) d",
                zh: "\(days) 天后重置",
                ja: "\(days) 日後にリセット",
                ko: "\(days)일 후 재설정"
            )
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return localized(en: "Just now", zh: "刚刚", ja: "たった今", ko: "방금") }
        if seconds < 3600 {
            return localized(en: "\(seconds / 60) min ago", zh: "\(seconds / 60) 分前", ja: "\(seconds / 60) 分前", ko: "\(seconds / 60)분 전")
        }
        if seconds < 86_400 {
            return localized(en: "\(seconds / 3600) h ago", zh: "\(seconds / 3600) 时前", ja: "\(seconds / 3600) 時間前", ko: "\(seconds / 3600)시간 전")
        }
        return localized(en: "\(seconds / 86_400) d ago", zh: "\(seconds / 86_400) 天前", ja: "\(seconds / 86_400) 日前", ko: "\(seconds / 86_400)일 전")
    }

    private func openCodexApplication() {
        let candidates = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
        guard let path = candidates.first(where: FileManager.default.fileExists(atPath:)) else {
            openUsagePage()
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func openUsagePage() {
        guard let url = URL(string: "https://chatgpt.com/codex/settings/usage") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openSessionsFolder() {
        let root = CodexLocalSessionScanner.sessionsRootURL()
        let target = FileManager.default.fileExists(atPath: root.path)
            ? root
            : root.deletingLastPathComponent()
        NSWorkspace.shared.open(target)
    }

    private func dayText(_ days: Int?) -> String {
        guard let days else { return "--" }
        let value = max(0, days)
        return localized(en: "\(value) d", zh: "\(value)天", ja: "\(value) 日", ko: "\(value)일")
    }

    private func durationText(_ seconds: Int?) -> String {
        guard let seconds else { return "--" }
        let value = max(0, seconds)
        if value >= 3600 {
            return localized(
                en: "\(value / 3600)h \((value % 3600) / 60)m",
                zh: "\(value / 3600)时\((value % 3600) / 60)分",
                ja: "\(value / 3600)時間\((value % 3600) / 60)分",
                ko: "\(value / 3600)시간 \((value % 3600) / 60)분"
            )
        }
        if value >= 60 {
            return localized(en: "\(value / 60) min", zh: "\(value / 60)分", ja: "\(value / 60) 分", ko: "\(value / 60)분")
        }
        return localized(en: "\(value) s", zh: "\(value)秒", ja: "\(value) 秒", ko: "\(value)초")
    }

    private func todayTokens(_ buckets: [CodexDailyUsage]) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: Date())
        return compactNumber(buckets.first(where: { $0.date == key })?.tokens ?? 0)
    }

    private func compactNumber(_ value: Int) -> String {
        value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000) : value >= 1_000 ? String(format: "%.1fK", Double(value) / 1_000) : "\(value)"
    }
}

private struct CodexQuotaProgressBar: View {
    let remainingPercent: Double
    let expectedRemainingPercent: Double?
    let tint: Color

    @ObservedObject private var settings = AppSettings.shared

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
        .accessibilityLabel(LocalizedString.l(
            settings.language,
            en: "Remaining quota",
            zh: "剩余额度",
            ja: "残りクォータ",
            ko: "남은 할당량"
        ))
        .accessibilityValue("\(Int(remainingPercent.rounded()))%")
    }
}

private struct CodexUsageHeatmap: View {
    let buckets: [CodexDailyUsage]

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedString.l(
                settings.language,
                en: "Token usage, last 30 days",
                zh: "近 30 天 Token 用量",
                ja: "直近 30 日の Token 使用量",
                ko: "최근 30일 Token 사용량"
            ))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(recentDays, id: \.self) { date in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: tokens(on: date)))
                        .frame(width: 5, height: 18)
                        .help("\(date): \(tokens(on: date)) tokens")
                }
            }
        }
        .padding(.top, 2)
    }

    private var recentDays: [String] {
        let calendar = Calendar.autoupdatingCurrent
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -29 + offset, to: Date()) else { return nil }
            return formatter.string(from: date)
        }
    }

    private func tokens(on date: String) -> Int {
        buckets.first(where: { $0.date == date })?.tokens ?? 0
    }

    private func color(for tokens: Int) -> Color {
        guard tokens > 0 else { return .secondary.opacity(0.14) }
        let peak = max(buckets.map(\.tokens).max() ?? 1, 1)
        return AppTheme.accent.opacity(0.25 + 0.75 * min(Double(tokens) / Double(peak), 1))
    }
}
