import Foundation
import SwiftUI
import UserNotifications

// MARK: - 简报仓库

@MainActor
@Observable
final class MorningBriefStore {

    static let shared = MorningBriefStore()

    private(set) var brief: MorningBrief?
    private(set) var isRefreshing = false
    private(set) var isRefining = false
    private(set) var refineError: String?

    /// 每天几点提醒。
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            scheduleDaily()
        }
    }

    var hour: Int {
        didSet {
            UserDefaults.standard.set(hour, forKey: Keys.hour)
            scheduleDaily()
        }
    }

    var minute: Int {
        didSet {
            UserDefaults.standard.set(minute, forKey: Keys.minute)
            scheduleDaily()
        }
    }

    private enum Keys {
        static let enabled = "morningBrief.enabled"
        static let hour = "morningBrief.hour"
        static let minute = "morningBrief.minute"
        static let request = "coolrun.morningBrief"
    }

    private let cacheURL: URL

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.hour: 8,
            Keys.minute: 30,
        ])
        isEnabled = defaults.bool(forKey: Keys.enabled)
        hour = defaults.integer(forKey: Keys.hour)
        minute = defaults.integer(forKey: Keys.minute)

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoolRun", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        cacheURL = support.appendingPathComponent("morning-brief.json")
        loadCache()
    }

    // MARK: 生成

    func refreshIfNeeded() async {
        let today = Calendar.current.startOfDay(for: Date())
        if let brief, brief.day == today { return }
        await refresh(force: true)
    }

    func refresh(force: Bool = false) async {
        let today = Calendar.current.startOfDay(for: Date())
        if !force, let brief, brief.day == today { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let snapshot = await sampleSystem()
        let settings = AppSettings.shared
        let language = settings.language
        let quote = GoldPriceStore.shared.latestQuote
        let english = EnglishProgressStore.shared.summary(dailyTarget: settings.englishDailyTarget)

        let built = MorningBriefBuilder.build(
            snapshot: snapshot,
            goldPrice: quote?.cnyPerGram ?? GoldPriceStore.shared.records.last?.price,
            goldChange: quote?.changeAmount,
            countdown: nextCountdown(),
            birthday: nextBirthday(),
            englishDone: english.learnedCount,
            englishTarget: english.dailyTarget,
            language: language
        )

        let merged = Self.mergingPatrol(built)
        brief = merged
        saveCache(merged)
        scheduleDaily()
    }

    /// 后台体检发现了问题，就把它顶到简报第一行——不然得等用户自己点进诊断。
    private static func mergingPatrol(_ brief: MorningBrief) -> MorningBrief {
        guard let finding = DiagnosticsPatrol.shared.findings.first else { return brief }
        let tone: MorningBriefLine.Tone
        switch finding.severity {
        case .critical: tone = .critical
        case .warning: tone = .warning
        case .notice: tone = .attention
        case .healthy, .unavailable: tone = .normal
        }
        // 体检说过的，就别在下面再说一遍。
        var base = brief.lines
        switch finding.id {
        case "storage": base.removeAll { $0.id == "system-storage" }
        case "memory": base.removeAll { $0.id == "system-memory" }
        default: break
        }
        let line = MorningBriefLine(
            id: "patrol",
            icon: "stethoscope",
            title: finding.title,
            detail: LocalizedString.l(
                AppSettings.shared.language,
                en: "Take a look",
                zh: "去看看",
                ja: "見てみる",
                ko: "확인해 보기"
            ),
            tone: tone,
            destination: .diagnostics
        )
        return MorningBrief(
            day: brief.day,
            greeting: brief.greeting,
            lines: Array(([line] + base).prefix(4)),
            generatedAt: brief.generatedAt,
            summary: brief.summary
        )
    }

    // MARK: 模型润色

    /// 把几行要点交给模型，让它说成两三句人话。失败不影响简报本身。
    func refine() async {
        guard var brief, !isRefining else { return }
        isRefining = true
        refineError = nil
        defer { isRefining = false }

        let config: AgentRunConfig
        do {
            config = try AgentSettings.shared.makeConfig()
        } catch {
            refineError = LocalizedString.l(
                AppSettings.shared.language,
                en: "Configure a model in Agent Settings first",
                zh: "先在 Agent 设置里配置模型",
                ja: "先に Agent 設定でモデルを構成してください",
                ko: "먼저 Agent 설정에서 모델을 구성하세요"
            )
            return
        }

        let language = AppSettings.shared.language
        let lines = brief.lines.map { "\($0.title)：\($0.detail)" }.joined(separator: "\n")
        let system = LocalizedString.l(
            language,
            en: "You are a concise assistant. Turn the given daily facts into two short, warm sentences. No bullet points, no greetings, no advice, no invented facts.",
            zh: "你是一个说话利落的助理。把下面的事实改写成两三句自然的中文，不要分点、不要寒暄、不要编造数据、不要给建议。",
            ja: "簡潔なアシスタントです。与えられた事実を2〜3文の自然な日本語にしてください。箇条書きも挨拶も助言も不要です。",
            ko: "간결한 비서입니다. 주어진 사실을 2~3문장의 자연스러운 한국어로 바꿔 주세요. 목록, 인사, 조언은 필요 없습니다."
        )

        do {
            let wire = AgentWireFactory.make(config.protocolKind)
            let stream = try await wire.stream(
                messages: [
                    AgentMessage(role: .system, content: system),
                    AgentMessage(role: .user, content: lines),
                ],
                tools: [],
                config: config
            )
            var text = ""
            for try await event in stream {
                if case let .text(chunk) = event { text += chunk }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                refineError = LocalizedString.l(
                    AppSettings.shared.language,
                    en: "The model returned nothing",
                    zh: "模型没返回内容",
                    ja: "モデルが内容を返しませんでした",
                    ko: "모델이 내용을 반환하지 않았습니다"
                )
                return
            }
            brief.summary = trimmed
            self.brief = brief
            saveCache(brief)
        } catch {
            refineError = error.localizedDescription
        }
    }

    // MARK: 定时提醒

    func scheduleDaily() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Keys.request])
        guard isEnabled else { return }

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let content = UNMutableNotificationContent()
        let language = AppSettings.shared.language
        content.title = LocalizedString.l(language, en: "Your daily brief is ready", zh: "今天的简报准备好了", ja: "今日のまとめができました", ko: "오늘의 브리핑이 준비됐어요")
        content.body = LocalizedString.l(language, en: "Tap to see what's up today.", zh: "点开看看今天要注意什么。", ja: "タップして今日の予定を確認。", ko: "눌러서 오늘 할 일을 확인하세요.")
        content.sound = .default

        center.add(UNNotificationRequest(identifier: Keys.request, content: content, trigger: trigger))
    }

    // MARK: 数据

    private func sampleSystem() async -> SystemSnapshot {
        let sampler = SystemSampler()
        _ = sampler.sample(includeProcesses: false, mergeProcesses: true)
        try? await Task.sleep(for: .milliseconds(320))
        return sampler.sample(includeProcesses: false, mergeProcesses: true)
    }

    private func nextCountdown() -> (name: String, days: Int)? {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        return CountdownManager.shared.getAllEvents().compactMap { event -> (String, Int)? in
            guard let date = event.nextOccurrence(after: now) else { return nil }
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
            guard days >= 0 else { return nil }
            return (event.name, days)
        }.min(by: { $0.1 < $1.1 })
    }

    private func nextBirthday() -> (name: String, days: Int)? {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let lunarYear = LunarCalendar.convertSolarToLunar(date: now).year
        return BirthdayManager.shared.getAllBirthdays().compactMap { birthday -> (String, Int)? in
            for offset in 0...3 {
                guard let date = birthday.solarDate(for: lunarYear + offset) else { continue }
                let day = calendar.startOfDay(for: date)
                guard day >= today else { continue }
                return (birthday.name, calendar.dateComponents([.day], from: today, to: day).day ?? 0)
            }
            return nil
        }.min(by: { $0.1 < $1.1 })
    }

    // MARK: 缓存

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(CachedBrief.self, from: data),
              cached.schema == CachedBrief.version
        else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard cached.day == today else { return }
        brief = cached.brief
    }

    private func saveCache(_ brief: MorningBrief) {
        guard let data = try? JSONEncoder().encode(CachedBrief(brief)) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private struct CachedBrief: Codable {
        static let version = 2
        let schema: Int
        let day: Date
        let greeting: String
        let lines: [Line]
        let generatedAt: Date
        let summary: String?

        struct Line: Codable {
            let id: String
            let icon: String
            let title: String
            let detail: String
            let tone: String
            let destination: String?
        }

        init(_ brief: MorningBrief) {
            schema = Self.version
            day = brief.day
            greeting = brief.greeting
            generatedAt = brief.generatedAt
            summary = brief.summary
            lines = brief.lines.map {
                Line(
                    id: $0.id,
                    icon: $0.icon,
                    title: $0.title,
                    detail: $0.detail,
                    tone: $0.tone.rawValue,
                    destination: $0.destination?.rawValue
                )
            }
        }

        var brief: MorningBrief {
            MorningBrief(
                day: day,
                greeting: greeting,
                lines: lines.map {
                    MorningBriefLine(
                        id: $0.id,
                        icon: $0.icon,
                        title: $0.title,
                        detail: $0.detail,
                        tone: MorningBriefLine.Tone(rawValue: $0.tone) ?? .normal,
                        destination: $0.destination.flatMap(ViewMode.init(rawValue:))
                    )
                },
                generatedAt: generatedAt,
                summary: summary
            )
        }
    }
}
