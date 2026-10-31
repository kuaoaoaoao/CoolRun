import SwiftUI

enum TodaySeverity: Int, Codable, Comparable, Sendable {
    case normal
    case attention
    case warning
    case critical

    static func < (lhs: TodaySeverity, rhs: TodaySeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .normal: AppTheme.healthy
        case .attention: AppTheme.accent
        case .warning: AppTheme.warning
        case .critical: AppTheme.critical
        }
    }
}

struct TodaySummaryItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case system
        case countdown
        case birthday
        case gold
        case english
        case aiQuota
    }

    let id: String
    let kind: Kind
    let severity: TodaySeverity
    let icon: String
    let title: String
    let detail: String
    let destination: ViewMode
    let dueDate: Date?
}

enum TodaySummaryBuilder {
    @MainActor
    static func current(
        snapshot: SystemSnapshot,
        settings: AppSettings,
        progressStore: EnglishProgressStore,
        goldStore: GoldPriceStore,
        tradeStore: GoldTradeStore,
        codexModel: CodexMonitorViewModel,
        claudeModel: ClaudeMonitorViewModel
    ) -> [TodaySummaryItem] {
        build(
            snapshot: snapshot,
            countdowns: CountdownManager.shared.getAllEvents(),
            birthdays: BirthdayManager.shared.getAllBirthdays(),
            english: progressStore.summary(dailyTarget: settings.englishDailyTarget),
            goldPrice: goldStore.latestQuote?.cnyPerGram ?? goldStore.records.last?.price,
            goldHolding: GoldTradeStore.holdingSummary(records: tradeStore.records),
            codexRemaining: minimumCodexRemaining(from: codexModel.state),
            claudeRemaining: minimumClaudeRemaining(from: claudeModel.state),
            language: settings.language
        )
    }

    static func maximumSeverity(in items: [TodaySummaryItem]) -> TodaySeverity? {
        items.map(\.severity).max()
    }

    static func build(
        snapshot: SystemSnapshot,
        countdowns: [CountdownEvent],
        birthdays: [Birthday],
        english: EnglishDailySummary,
        goldPrice: Double?,
        goldHolding: (grams: Double, averageCost: Double),
        codexRemaining: Int?,
        claudeRemaining: Int?,
        language: AppLanguage,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodaySummaryItem] {
        var items = [systemItem(snapshot: snapshot, language: language)]

        if let next = countdowns.compactMap({ event -> (CountdownEvent, Date, Int)? in
            guard let date = event.nextOccurrence(after: now) else { return nil }
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: date)
            ).day ?? 0
            guard days >= 0 else { return nil }
            return (event, date, days)
        }).min(by: { $0.2 < $1.2 }) {
            let severity: TodaySeverity = next.2 == 0 ? .critical : next.2 <= 3 ? .warning : .attention
            let detail = next.2 == 0
                ? LocalizedString.l(language, en: "Today", zh: "就是今天", ja: "今日", ko: "오늘")
                : LocalizedString.l(language, en: "In \(next.2) days", zh: "还有 \(next.2) 天", ja: "あと\(next.2)日", ko: "\(next.2)일 남음")
            items.append(TodaySummaryItem(
                id: "countdown-\(next.0.id.uuidString)",
                kind: .countdown,
                severity: severity,
                icon: "hourglass",
                title: next.0.name,
                detail: detail,
                destination: .calendar,
                dueDate: next.1
            ))
        }

        if let nextBirthday = nextBirthday(in: birthdays, after: now, calendar: calendar) {
            let severity: TodaySeverity = nextBirthday.days == 0 ? .critical : nextBirthday.days <= 7 ? .warning : .attention
            let detail = nextBirthday.days == 0
                ? LocalizedString.l(language, en: "Birthday today", zh: "今天生日", ja: "今日が誕生日", ko: "오늘 생일")
                : LocalizedString.l(language, en: "Birthday in \(nextBirthday.days) days", zh: "生日还有 \(nextBirthday.days) 天", ja: "誕生日まで\(nextBirthday.days)日", ko: "생일까지 \(nextBirthday.days)일")
            items.append(TodaySummaryItem(
                id: "birthday-\(nextBirthday.birthday.id.uuidString)",
                kind: .birthday,
                severity: severity,
                icon: "gift.fill",
                title: nextBirthday.birthday.name,
                detail: detail,
                destination: .calendar,
                dueDate: nextBirthday.date
            ))
        }

        if let goldPrice {
            var detail = LocalizedString.l(
                language,
                en: String(format: "Gold ¥%.2f/g", goldPrice),
                zh: String(format: "金价 ¥%.2f/克", goldPrice),
                ja: String(format: "金価格 ¥%.2f/g", goldPrice),
                ko: String(format: "금 가격 ¥%.2f/g", goldPrice)
            )
            var severity: TodaySeverity = .normal
            if goldHolding.grams > 0, goldHolding.averageCost > 0 {
                let profitPercent = (goldPrice - goldHolding.averageCost) / goldHolding.averageCost
                severity = profitPercent <= -0.05 ? .critical : profitPercent <= -0.02 ? .warning : .normal
                detail += String(format: " · %+.1f%%", profitPercent * 100)
            }
            items.append(TodaySummaryItem(
                id: "gold",
                kind: .gold,
                severity: severity,
                icon: "chart.line.uptrend.xyaxis",
                title: LocalizedString.l(language, en: "Gold position", zh: "黄金持仓", ja: "金ポジション", ko: "금 보유"),
                detail: detail,
                destination: .gold,
                dueDate: nil
            ))
        }

        let hour = calendar.component(.hour, from: now)
        let englishSeverity: TodaySeverity = english.isGoalComplete ? .normal : hour >= 18 ? .warning : .attention
        items.append(TodaySummaryItem(
            id: "english",
            kind: .english,
            severity: englishSeverity,
            icon: "character.book.closed.fill",
            title: english.isGoalComplete
                ? LocalizedString.l(language, en: "English goal complete", zh: "英语目标已完成", ja: "英語目標を達成", ko: "영어 목표 완료")
                : LocalizedString.l(language, en: "Continue English", zh: "继续今日英语", ja: "今日の英語を続ける", ko: "오늘 영어 계속하기"),
            detail: "\(english.learnedCount)/\(english.dailyTarget) · \(english.streak) " + LocalizedString.l(language, en: "day streak", zh: "天连续", ja: "日連続", ko: "일 연속"),
            destination: .english,
            dueDate: calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now)
        ))

        if let remaining = [codexRemaining, claudeRemaining].compactMap({ $0 }).min() {
            let severity: TodaySeverity = remaining <= 10 ? .critical : remaining <= 25 ? .warning : .normal
            items.append(TodaySummaryItem(
                id: "ai-quota",
                kind: .aiQuota,
                severity: severity,
                icon: "sparkles",
                title: LocalizedString.l(language, en: "AI quota", zh: "AI 额度", ja: "AI クォータ", ko: "AI 할당량"),
                detail: LocalizedString.l(language, en: "Tightest window \(remaining)% left", zh: "最紧张窗口剩余 \(remaining)%", ja: "最小残量 \(remaining)%", ko: "최소 잔여량 \(remaining)%"),
                destination: .codex,
                dueDate: nil
            ))
        }

        return sorted(items)
    }

    static func sorted(_ items: [TodaySummaryItem]) -> [TodaySummaryItem] {
        items.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            switch (lhs.dueDate, rhs.dueDate) {
            case let (.some(l), .some(r)): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.id < rhs.id
            }
        }
    }

    static func severity(for snapshot: SystemSnapshot) -> TodaySeverity {
        let hottest = [snapshot.temperature.cpuTemperature, snapshot.temperature.gpuTemperature]
            .compactMap { $0 }
            .max() ?? 0
        if snapshot.cpu.usage >= 0.9 || snapshot.memory.usage >= 0.9 || snapshot.storage.usage >= 0.95 || hottest >= 95 {
            return .critical
        }
        if snapshot.cpu.usage >= 0.75 || snapshot.memory.usage >= 0.75 || snapshot.storage.usage >= 0.85 || hottest >= 80 {
            return .warning
        }
        return .normal
    }

    private static func systemItem(snapshot: SystemSnapshot, language: AppLanguage) -> TodaySummaryItem {
        let severity = severity(for: snapshot)
        let title = severity >= .warning
            ? LocalizedString.l(language, en: "Mac needs attention", zh: "Mac 状态需要关注", ja: "Mac の状態を確認", ko: "Mac 상태 확인 필요")
            : LocalizedString.l(language, en: "Mac is running normally", zh: "Mac 运行正常", ja: "Mac は正常です", ko: "Mac 정상 작동 중")
        let detail = "CPU \(Int(snapshot.cpu.usage * 100))% · MEM \(Int(snapshot.memory.usage * 100))%"
        return TodaySummaryItem(
            id: "system",
            kind: .system,
            severity: severity,
            icon: severity >= .warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            title: title,
            detail: detail,
            destination: .monitor,
            dueDate: nil
        )
    }

    private static func nextBirthday(
        in birthdays: [Birthday],
        after now: Date,
        calendar: Calendar
    ) -> (birthday: Birthday, date: Date, days: Int)? {
        let currentLunarYear = LunarCalendar.convertSolarToLunar(date: now).year
        let today = calendar.startOfDay(for: now)
        return birthdays.compactMap { birthday in
            for offset in 0...3 {
                guard let date = birthday.solarDate(for: currentLunarYear + offset) else { continue }
                let day = calendar.startOfDay(for: date)
                guard day >= today else { continue }
                let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
                return (birthday, date, days)
            }
            return nil
        }.min(by: { $0.days < $1.days })
    }

    private static func minimumCodexRemaining(from state: CodexMonitorState) -> Int? {
        guard case let .ready(snapshot) = state else { return nil }
        return snapshot.limits.flatMap(\.windows).compactMap(\.remainingPercent).min()
    }

    private static func minimumClaudeRemaining(from state: ClaudeMonitorState) -> Int? {
        guard case let .ready(snapshot) = state else { return nil }
        return snapshot.windows.compactMap(\.remainingPercent).min()
    }
}

struct TodayOverviewView: View {
    let snapshot: SystemSnapshot

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var progressStore = EnglishProgressStore.shared
    @ObservedObject private var router = AppNavigationRouter.shared
    @State private var goldStore = GoldPriceStore.shared
    @State private var tradeStore = GoldTradeStore.shared
    @State private var codexModel = CodexMonitorViewModel.shared
    @State private var claudeModel = ClaudeMonitorViewModel.shared
    @Environment(\.colorScheme) private var colorScheme

    private var items: [TodaySummaryItem] {
        TodaySummaryBuilder.current(
            snapshot: snapshot,
            settings: settings,
            progressStore: progressStore,
            goldStore: goldStore,
            tradeStore: tradeStore,
            codexModel: codexModel,
            claudeModel: claudeModel
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                headline

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        router.open(item.destination)
                    } label: {
                        timelineRow(item, isLast: index == items.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
    }

    private var headline: some View {
        let urgentCount = items.filter { $0.severity >= .warning }.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedString.l(settings.language, en: "Today", zh: "今天", ja: "今日", ko: "오늘"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Text(Date.now.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            Text(urgentCount == 0
                ? LocalizedString.l(settings.language, en: "Nothing urgent. Keep your rhythm.", zh: "暂无紧急事项，按自己的节奏继续。", ja: "急ぎの項目はありません。", ko: "긴급한 항목이 없습니다.")
                : LocalizedString.l(settings.language, en: "\(urgentCount) items need attention.", zh: "有 \(urgentCount) 项需要关注。", ja: "\(urgentCount)件の確認事項があります。", ko: "\(urgentCount)개 항목을 확인하세요."))
                .font(.caption)
                .foregroundStyle(urgentCount == 0 ? AppTheme.textSecondary(colorScheme) : AppTheme.warning)
        }
        .padding(12)
        .background(AppTheme.gold.opacity(colorScheme == .dark ? 0.13 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(AppTheme.gold).frame(width: 3).padding(.vertical, 9)
        }
    }

    private func timelineRow(_ item: TodaySummaryItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(item.severity.color.opacity(0.14)).frame(width: 28, height: 28)
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.severity.color)
                }
                if !isLast {
                    Rectangle().fill(AppTheme.stroke(colorScheme)).frame(width: 1, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(2)
            }
            .padding(.top, 2)

            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.6))
                .padding(.top, 9)
        }
        .contentShape(Rectangle())
    }

}
