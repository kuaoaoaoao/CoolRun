import Foundation

// MARK: - 生日模型

struct Birthday: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var lunarMonth: Int  // 农历月 (1-12)
    var lunarDay: Int    // 农历日 (1-30)
    var isLeapMonth: Bool
    var note: String

    init(id: UUID = UUID(), name: String, lunarMonth: Int, lunarDay: Int, isLeapMonth: Bool = false, note: String = "") {
        self.id = id
        self.name = name
        self.lunarMonth = lunarMonth
        self.lunarDay = lunarDay
        self.isLeapMonth = isLeapMonth
        self.note = note
    }

    // 农历日期显示文本
    var lunarDateString: String {
        let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
        let dayNames = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]

        let monthStr = (isLeapMonth ? "闰" : "") + monthNames[lunarMonth - 1] + "月"
        let dayStr = dayNames[lunarDay - 1]
        return monthStr + dayStr
    }

    // 获取某年的公历日期
    func solarDate(for year: Int) -> Date? {
        return LunarCalendar.lunarToSolar(year: year, month: lunarMonth, day: lunarDay, isLeapMonth: isLeapMonth)
    }

    // 检查某日期是否是这个生日
    func isBirthday(on date: Date) -> Bool {
        let lunarDate = LunarCalendar.convertSolarToLunar(date: date)
        return lunarDate.month == lunarMonth &&
               lunarDate.day == lunarDay &&
               lunarDate.isLeapMonth == isLeapMonth
    }
}

// MARK: - 生日管理器

class BirthdayManager {
    static let shared = BirthdayManager()

    private let userDefaults = UserDefaults.standard
    private let storageKey = "saved_birthdays"

    private init() {}

    // 获取所有生日
    func getAllBirthdays() -> [Birthday] {
        guard let data = userDefaults.data(forKey: storageKey),
              let birthdays = try? JSONDecoder().decode([Birthday].self, from: data) else {
            return []
        }
        return birthdays
    }

    // 保存生日
    func saveBirthday(_ birthday: Birthday) {
        var birthdays = getAllBirthdays()
        birthdays.append(birthday)
        saveBirthdays(birthdays)
    }

    // 更新生日
    func updateBirthday(_ birthday: Birthday) {
        var birthdays = getAllBirthdays()
        if let index = birthdays.firstIndex(where: { $0.id == birthday.id }) {
            birthdays[index] = birthday
            saveBirthdays(birthdays)
        }
    }

    // 删除生日
    func deleteBirthday(_ birthday: Birthday) {
        var birthdays = getAllBirthdays()
        birthdays.removeAll { $0.id == birthday.id }
        saveBirthdays(birthdays)
    }

    // 获取某日期的所有生日
    func getBirthdays(for date: Date) -> [Birthday] {
        return getAllBirthdays().filter { $0.isBirthday(on: date) }
    }

    // 获取某日期的生日（农历）
    func getBirthdays(lunarMonth: Int, lunarDay: Int, isLeapMonth: Bool) -> [Birthday] {
        return getAllBirthdays().filter {
            $0.lunarMonth == lunarMonth &&
            $0.lunarDay == lunarDay &&
            $0.isLeapMonth == isLeapMonth
        }
    }

    // 检查某日期是否有生日
    func hasBirthday(on date: Date) -> Bool {
        return !getBirthdays(for: date).isEmpty
    }

    // MARK: - 私有方法

    private func saveBirthdays(_ birthdays: [Birthday]) {
        if let data = try? JSONEncoder().encode(birthdays) {
            userDefaults.set(data, forKey: storageKey)
            // 镜像到 iCloud，供手表/其他端读取（未开 iCloud 能力时会优雅降级）。
            if let json = String(data: data, encoding: .utf8) {
                CloudSyncStore.shared.pushBirthdaysJSON(json)
            }
        }
        Task { @MainActor in
            await LocalReminderCenter.shared.rescheduleAll()
        }
    }
}
