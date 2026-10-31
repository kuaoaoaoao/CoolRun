import SwiftUI
import AppKit

struct CodexMonitorView: View {
    @State private var viewModel: CodexMonitorViewModel
    @Environment(\.colorScheme) private var colorScheme

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
                    Text("Codex 监控")
                        .font(.headline)
                    Text("额度节奏、近期任务与用量")
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
                .accessibilityLabel("刷新 Codex 状态")
                .help("刷新 Codex 状态")
            }

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch viewModel.state {
                    case .loading:
                        ProgressView("正在连接本机 Codex…")
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case let .unavailable(message):
                        statusCard(icon: "exclamationmark.triangle", color: .orange, title: "暂时无法读取", detail: message)
                    case let .notLoggedIn(detail):
                        statusCard(icon: "person.crop.circle.badge.xmark", color: .secondary, title: "Codex 未返回账号", detail: detail)
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
                quickAction("打开 Codex", icon: "sparkles", action: openCodexApplication)
                quickAction("额度详情", icon: "gauge.with.dots.needle.50percent", action: openUsagePage)
                quickAction("任务文件", icon: "folder", action: openSessionsFolder)
            }

            if snapshot.limits.isEmpty && snapshot.usage == nil {
                Text("暂无额度与用量数据")
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
                            Text("可重置 \(count) 次")
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
                        usageMetric("今日", todayTokens(snapshot.dailyUsage))
                        usageMetric("累计", compactNumber(usage.lifetimeTokens))
                        usageMetric("峰值", compactNumber(usage.peakDailyTokens))
                    }
                    HStack(spacing: 4) {
                        usageMetric("连续", dayText(usage.currentStreakDays))
                        usageMetric("最长连续", dayText(usage.longestStreakDays))
                        usageMetric("最长任务", durationText(usage.longestRunningTurnSec))
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
                    Label("部分缓存", systemImage: "clock.arrow.circlepath")
                } else {
                    Text("每 30 秒刷新")
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
                    Text("节奏线 \(Int(pace.expectedRemainingPercent.rounded()))%")
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
                Label("近期任务", systemImage: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                let activeCount = sessions.filter(\.isActive).count
                if activeCount > 0 {
                    Text("\(activeCount) 个活跃")
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
                .help("在访达中显示任务记录")
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

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60) 分前" }
        if seconds < 86_400 { return "\(seconds / 3600) 时前" }
        return "\(seconds / 86_400) 天前"
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

    private func dayText(_ days: Int?) -> String { days.map { "\(max(0, $0))天" } ?? "--" }

    private func durationText(_ seconds: Int?) -> String {
        guard let seconds else { return "--" }
        let value = max(0, seconds)
        if value >= 3600 { return "\(value / 3600)时\((value % 3600) / 60)分" }
        if value >= 60 { return "\(value / 60)分" }
        return "\(value)秒"
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

private struct CodexUsageHeatmap: View {
    let buckets: [CodexDailyUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("近 30 天 Token 用量")
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
