import Foundation

// MARK: - 倒数日模型

struct CountdownEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isLunar: Bool
    var month: Int          // 公历或农历月 (1-12)
    var day: Int            // 公历 1-31 / 农历 1-30
    var isLeapMonth: Bool   // 仅农历有效
    var repeatsAnnually: Bool
    var targetYear: Int?    // 不重复时的目标年份（农历事件为农历年）
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        isLunar: Bool = false,
        month: Int,
        day: Int,
        isLeapMonth: Bool = false,
        repeatsAnnually: Bool = true,
        targetYear: Int? = nil,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.isLunar = isLunar
        self.month = month
        self.day = day
        self.isLeapMonth = isLeapMonth
        self.repeatsAnnually = repeatsAnnually
        self.targetYear = targetYear
        self.note = note
    }

    // 下一次发生的公历日期（每年重复取未来最近一次；一次性事件可能已过期）
    func nextOccurrence(after now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        if isLunar {
            if repeatsAnnually {
                let currentLunarYear = LunarCalendar.convertSolarToLunar(date: now).year
                // 闰月不是每年都有，向后多找几年
                for offset in 0...3 {
                    if let date = LunarCalendar.lunarToSolar(year: currentLunarYear + offset, month: month, day: day, isLeapMonth: isLeapMonth),
                       calendar.startOfDay(for: date) >= todayStart {
                        return date
                    }
                }
                return nil
            }
            guard let targetYear else { return nil }
            return LunarCalendar.lunarToSolar(year: targetYear, month: month, day: day, isLeapMonth: isLeapMonth)
        }

        if repeatsAnnually {
            var components = DateComponents()
            components.month = month
            components.day = day
            // 从昨天开始搜索，使"今天"也算作命中（2/29 等无效年份自动顺延）
            let searchStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
            return calendar.nextDate(after: searchStart, matching: components, matchingPolicy: .nextTime)
        }
        guard let targetYear else { return nil }
        var components = DateComponents()
        components.year = targetYear
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    // 剩余天数：0=今天，负数=一次性事件已过期
    func daysRemaining(from now: Date = Date()) -> Int? {
        guard let next = nextOccurrence(after: now) else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: next)
        ).day
    }

    /// 判断事件是否落在指定的公历日期，用于日历格与日期详情联动。
    func occurs(on date: Date) -> Bool {
        let solarCalendar = Calendar.current

        if isLunar {
            let lunarDate = LunarCalendar.convertSolarToLunar(date: date)
            guard lunarDate.month == month,
                  lunarDate.day == day,
                  lunarDate.isLeapMonth == isLeapMonth else {
                return false
            }
            return repeatsAnnually || lunarDate.year == targetYear
        }

        let components = solarCalendar.dateComponents([.year, .month, .day], from: date)
        guard components.month == month, components.day == day else {
            return false
        }
        return repeatsAnnually || components.year == targetYear
    }

    // 日期显示文本，如 "3月8日" / "闰二月初八" / "2027年6月7日"
    var dateString: String {
        if isLunar {
            let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
            let dayNames = [
                "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
            ]
            guard (1...12).contains(month), (1...30).contains(day) else { return "--" }
            let prefix = repeatsAnnually ? "" : targetYear.map { "\($0)年" } ?? ""
            return prefix + (isLeapMonth ? "闰" : "") + monthNames[month - 1] + "月" + dayNames[day - 1]
        }
        let prefix = repeatsAnnually ? "" : targetYear.map { "\($0)年" } ?? ""
        return "\(prefix)\(month)月\(day)日"
    }
}

// MARK: - 倒数日管理器

final class CountdownManager {
    static let shared = CountdownManager()

    private let userDefaults = UserDefaults.standard
    private let storageKey = "saved_countdowns"
    // 菜单栏每秒刷新会频繁读取，用内存缓存避免反复解码
    private var cache: [CountdownEvent]?

    private init() {}

    func getAllEvents() -> [CountdownEvent] {
        if let cache { return cache }
        guard let data = userDefaults.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([CountdownEvent].self, from: data) else {
            cache = []
            return []
        }
        cache = events
        return events
    }

    func saveEvent(_ event: CountdownEvent) {
        var events = getAllEvents()
        events.append(event)
        saveEvents(events)
    }

    func updateEvent(_ event: CountdownEvent) {
        var events = getAllEvents()
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
            saveEvents(events)
        }
    }

    func deleteEvent(_ event: CountdownEvent) {
        var events = getAllEvents()
        events.removeAll { $0.id == event.id }
        saveEvents(events)
    }

    // 按剩余天数升序排列（过期的一次性事件排最后）
    func sortedEvents(from now: Date = Date()) -> [CountdownEvent] {
        getAllEvents().sorted { lhs, rhs in
            let lhsDays = lhs.daysRemaining(from: now)
            let rhsDays = rhs.daysRemaining(from: now)
            switch (lhsDays, rhsDays) {
            case let (.some(l), .some(r)):
                if (l >= 0) != (r >= 0) { return l >= 0 }
                return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.name < rhs.name
            }
        }
    }

    // 最近一个未到期事件，用于菜单栏常驻显示
    func nearestUpcoming(from now: Date = Date()) -> (event: CountdownEvent, days: Int)? {
        var best: (event: CountdownEvent, days: Int)?
        for event in getAllEvents() {
            guard let days = event.daysRemaining(from: now), days >= 0 else { continue }
            if best == nil || days < best!.days {
                best = (event, days)
            }
        }
        return best
    }

    func events(on date: Date) -> [CountdownEvent] {
        getAllEvents()
            .filter { $0.occurs(on: date) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func mergeEvents(_ incoming: [CountdownEvent]) -> Int {
        let existing = getAllEvents()
        let merged = Self.mergedEvents(existing: existing, incoming: incoming)
        guard merged.count != existing.count else { return 0 }
        saveEvents(merged)
        return merged.count - existing.count
    }

    static func mergedEvents(
        existing: [CountdownEvent],
        incoming: [CountdownEvent]
    ) -> [CountdownEvent] {
        var knownIDs = Set(existing.map(\.id))
        var result = existing
        for event in incoming where knownIDs.insert(event.id).inserted {
            result.append(event)
        }
        return result
    }

    private func saveEvents(_ events: [CountdownEvent]) {
        cache = events
        if let data = try? JSONEncoder().encode(events) {
            userDefaults.set(data, forKey: storageKey)
        }
        Task { @MainActor in
            await LocalReminderCenter.shared.rescheduleAll()
        }
    }
}
