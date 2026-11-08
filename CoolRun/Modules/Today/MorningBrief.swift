import SwiftUI

// MARK: - 晨间简报

/// 简报里的一行。刻意只保留四个字段：图标、一句话、一个数值、跳转目标。
/// 行数控制在 4 条以内，多了就不叫简报。
struct MorningBriefLine: Identifiable, Equatable, Sendable {
    enum Tone: String, Sendable {
        case normal
        case attention
        case warning
        case critical

        var color: Color {
            switch self {
            case .normal: AppTheme.textSecondary(.light)
            case .attention: AppTheme.accent
            case .warning: AppTheme.warning
            case .critical: AppTheme.critical
            }
        }

        var symbol: String {
            switch self {
            case .normal: "circle.fill"
            case .attention: "circle.fill"
            case .warning: "exclamationmark.circle.fill"
            case .critical: "exclamationmark.triangle.fill"
            }
        }
    }

    let id: String
    let icon: String
    let title: String
    let detail: String
    let tone: Tone
    let destination: ViewMode?

    nonisolated init(
        id: String,
        icon: String,
        title: String,
        detail: String,
        tone: Tone = .normal,
        destination: ViewMode? = nil
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.detail = detail
        self.tone = tone
        self.destination = destination
    }
}

struct MorningBrief: Equatable, Sendable {
    /// 当天零点，用来判断缓存是否过期。
    let day: Date
    let greeting: String
    let lines: [MorningBriefLine]
    let generatedAt: Date
    /// 模型润色后的两三句话，没润色时为 nil。
    var summary: String?

    nonisolated init(
        day: Date,
        greeting: String,
        lines: [MorningBriefLine],
        generatedAt: Date = Date(),
        summary: String? = nil
    ) {
        self.day = day
        self.greeting = greeting
        self.lines = lines
        self.generatedAt = generatedAt
        self.summary = summary
    }

    var isEmpty: Bool { lines.isEmpty }
}

// MARK: - 生成

@MainActor
enum MorningBriefBuilder {

    static func build(
        snapshot: SystemSnapshot,
        goldPrice: Double?,
        goldChange: Double?,
        countdown: (name: String, days: Int)?,
        birthday: (name: String, days: Int)?,
        englishDone: Int,
        englishTarget: Int,
        codexRemaining: Int?,
        claudeRemaining: Int?,
        language: AppLanguage,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MorningBrief {
        let day = calendar.startOfDay(for: now)
        var lines: [MorningBriefLine] = []

        // 系统只在真的有问题时才占一行，正常不打扰。
        if let alert = systemAlert(snapshot: snapshot, language: language) {
            lines.append(alert)
        }

        if let goldPrice {
            let flat = abs(goldChange ?? 0) < 0.01
            let tone: MorningBriefLine.Tone = flat ? .normal : .attention
            let changeText: String
            if let goldChange, !flat {
                let percent = goldPrice > 0 ? goldChange / goldPrice * 100 : 0
                changeText = String(format: "%+.2f (%+.2f%%)", goldChange, percent)
            } else {
                changeText = LocalizedString.l(language, en: "flat", zh: "平盘", ja: "変わらず", ko: "보합")
            }
            lines.append(MorningBriefLine(
                id: "gold",
                icon: "circle.hexagongrid.fill",
                title: LocalizedString.l(language, en: "Gold", zh: "金价", ja: "金価格", ko: "금값"),
                detail: "¥\(String(format: "%.2f", goldPrice))/g · \(changeText)",
                tone: tone,
                destination: .gold
            ))
        }

        if let countdown {
            let tone: MorningBriefLine.Tone = countdown.days == 0 ? .critical : countdown.days <= 3 ? .warning : .attention
            lines.append(MorningBriefLine(
                id: "countdown",
                icon: "hourglass",
                title: countdown.name,
                detail: countdown.days == 0
                    ? LocalizedString.l(language, en: "today", zh: "就是今天", ja: "今日", ko: "오늘")
                    : LocalizedString.l(language, en: "in \(countdown.days) days", zh: "还有 \(countdown.days) 天", ja: "あと\(countdown.days)日", ko: "\(countdown.days)일 남음"),
                tone: tone,
                destination: .calendar
            ))
        } else if let birthday {
            lines.append(MorningBriefLine(
                id: "birthday",
                icon: "birthday.cake.fill",
                title: birthday.name,
                detail: birthday.days == 0
                    ? LocalizedString.l(language, en: "birthday today", zh: "今天生日", ja: "今日が誕生日", ko: "오늘 생일")
                    : LocalizedString.l(language, en: "in \(birthday.days) days", zh: "还有 \(birthday.days) 天", ja: "あと\(birthday.days)日", ko: "\(birthday.days)일 남음"),
                tone: birthday.days <= 3 ? .warning : .attention,
                destination: .calendar
            ))
        }

        if englishTarget > 0 {
            let remaining = max(0, englishTarget - englishDone)
            if remaining > 0 {
                lines.append(MorningBriefLine(
                    id: "english",
                    icon: "text.book.closed.fill",
                    title: LocalizedString.l(language, en: "English", zh: "英语", ja: "英語", ko: "영어"),
                    detail: LocalizedString.l(language, en: "\(remaining) to go", zh: "还差 \(remaining) 个", ja: "あと\(remaining)個", ko: "\(remaining)개 남음"),
                    tone: .normal,
                    destination: .english
                ))
            }
        }

        if let lowest = [codexRemaining, claudeRemaining].compactMap({ $0 }).min(), lowest <= 20 {
            lines.append(MorningBriefLine(
                id: "quota",
                icon: "gauge.with.dots.needle.bottom.50percent",
                title: LocalizedString.l(language, en: "AI quota", zh: "AI 额度", ja: "AI 枠", ko: "AI 할당량"),
                detail: LocalizedString.l(language, en: "\(lowest)% left", zh: "只剩 \(lowest)%", ja: "残り\(lowest)%", ko: "\(lowest)% 남음"),
                tone: lowest <= 10 ? .critical : .warning,
                destination: .codex
            ))
        }

        return MorningBrief(
            day: day,
            greeting: greeting(for: now, language: language),
            lines: Array(lines.prefix(4))
        )
    }

    static func greeting(for now: Date, language: AppLanguage, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<11:
            return LocalizedString.l(language, en: "Good morning", zh: "早上好", ja: "おはよう", ko: "좋은 아침")
        case 11..<14:
            return LocalizedString.l(language, en: "Good noon", zh: "中午好", ja: "こんにちは", ko: "좋은 점심")
        case 14..<19:
            return LocalizedString.l(language, en: "Good afternoon", zh: "下午好", ja: "こんにちは", ko: "좋은 오후")
        default:
            return LocalizedString.l(language, en: "Good evening", zh: "晚上好", ja: "こんばんは", ko: "좋은 저녁")
        }
    }

    private static func systemAlert(snapshot: SystemSnapshot, language: AppLanguage) -> MorningBriefLine? {
        if snapshot.storage.usage >= 0.85 {
            return MorningBriefLine(
                id: "system-storage",
                icon: "internaldrive.fill",
                title: LocalizedString.l(language, en: "Disk", zh: "磁盘", ja: "ディスク", ko: "디스크"),
                detail: LocalizedString.l(
                    language,
                    en: "only \(Int((1 - snapshot.storage.usage) * 100))% free",
                    zh: "只剩 \(Int((1 - snapshot.storage.usage) * 100))%",
                    ja: "残り\(Int((1 - snapshot.storage.usage) * 100))%",
                    ko: "\(Int((1 - snapshot.storage.usage) * 100))% 남음"
                ),
                tone: .warning,
                destination: .monitor
            )
        }
        if snapshot.memory.usage >= 0.85 {
            return MorningBriefLine(
                id: "system-memory",
                icon: "memorychip.fill",
                title: LocalizedString.l(language, en: "Memory", zh: "内存", ja: "メモリ", ko: "메모리"),
                detail: "\(Int(snapshot.memory.usage * 100))%",
                tone: .warning,
                destination: .monitor
            )
        }
        if snapshot.cpu.usage >= 0.8 {
            return MorningBriefLine(
                id: "system-cpu",
                icon: "cpu.fill",
                title: LocalizedString.l(language, en: "CPU", zh: "CPU", ja: "CPU", ko: "CPU"),
                detail: "\(Int(snapshot.cpu.usage * 100))%",
                tone: .attention,
                destination: .monitor
            )
        }
        return nil
    }
}
