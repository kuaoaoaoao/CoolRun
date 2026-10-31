import Foundation

// MARK: - 农历日期模型

struct LunarDate {
    let year: Int
    let month: Int
    let day: Int
    let isLeapMonth: Bool
    let yearChinese: String  // 天干地支年名
    let monthChinese: String // 农历月名
    let dayChinese: String   // 农历日名
    let zodiac: String       // 生肖
    let solarTerm: String?   // 节气（如果有）
    let festival: String?    // 节日（如果有）
}

// MARK: - 农历转换工具

enum LunarCalendar {
    // 天干
    private static let heavenlyStems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    // 地支
    private static let earthlyBranches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    // 生肖
    private static let zodiacs = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    // 农历月名
    private static let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    // 农历日名
    private static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    // 二十四节气
    private static let solarTerms = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
        "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
        "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]

    // 节气日期表 (2024-2030年，每月两个节气的近似日期)
    private static let solarTermDates: [Int: [Int]] = [
        2024: [6,20, 4,19, 5,20, 4,19, 5,21, 5,21, 7,22, 7,22, 7,22, 5,20, 7,21, 6,21],
        2025: [5,20, 3,18, 5,20, 4,20, 5,21, 5,21, 7,22, 7,22, 7,22, 5,20, 7,21, 6,21],
        2026: [5,20, 4,19, 5,20, 5,21, 5,21, 5,21, 7,22, 7,22, 7,22, 5,20, 7,21, 6,21],
        2027: [5,20, 4,19, 5,20, 5,21, 5,21, 5,21, 7,22, 7,22, 7,22, 5,20, 7,21, 6,21],
        2028: [6,20, 4,19, 5,20, 4,19, 5,21, 5,21, 7,22, 7,22, 7,22, 5,20, 7,21, 6,21],
        2029: [5,20, 3,18, 5,20, 4,20, 5,21, 5,21, 7,22, 7,22, 7,22, 5,20, 7,21, 6,21],
        2030: [5,20, 4,19, 5,20, 5,21, 5,21, 5,21, 7,22, 7,22, 7,22, 5,20, 7,21, 6,21]
    ]

    // MARK: - 公历转农历

    static func convertSolarToLunar(date: Date) -> LunarDate {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        // 使用 Foundation 的农历日历
        let lunarCalendar = Calendar(identifier: .chinese)
        let lunarComponents = lunarCalendar.dateComponents([.year, .month, .day, .isLeapMonth], from: date)

        let lunarYear = lunarComponents.year ?? 0
        let lunarMonth = lunarComponents.month ?? 0
        let lunarDay = lunarComponents.day ?? 0
        let isLeapMonth = lunarComponents.isLeapMonth ?? false

        // 计算天干地支
        let stemIndex = (lunarYear - 1) % 10
        let branchIndex = (lunarYear - 1) % 12
        let yearChinese = heavenlyStems[stemIndex] + earthlyBranches[branchIndex] + "年"

        // 月名
        let monthChinese = (isLeapMonth ? "闰" : "") + monthNames[lunarMonth - 1] + "月"

        // 日名
        let dayChinese = dayNames[lunarDay - 1]

        // 生肖
        let zodiac = zodiacs[branchIndex]

        // 节气
        let solarTerm = getSolarTerm(year: year, month: month, day: day)

        // 节日
        let festival = getFestival(month: month, day: day, lunarMonth: lunarMonth, lunarDay: lunarDay, isLeapMonth: isLeapMonth)

        return LunarDate(
            year: lunarYear,
            month: lunarMonth,
            day: lunarDay,
            isLeapMonth: isLeapMonth,
            yearChinese: yearChinese,
            monthChinese: monthChinese,
            dayChinese: dayChinese,
            zodiac: zodiac,
            solarTerm: solarTerm,
            festival: festival
        )
    }

    // MARK: - 获取节气

    private static func getSolarTerm(year: Int, month: Int, day: Int) -> String? {
        guard let dates = solarTermDates[year] else { return nil }

        let termIndex = (month - 1) * 2
        guard termIndex < dates.count - 1 else { return nil }

        let firstTermDay = dates[termIndex]
        let secondTermDay = dates[termIndex + 1]

        if day == firstTermDay {
            return solarTerms[termIndex]
        } else if day == secondTermDay {
            return solarTerms[termIndex + 1]
        }

        return nil
    }

    // MARK: - 获取节日

    private static func getFestival(month: Int, day: Int, lunarMonth: Int, lunarDay: Int, isLeapMonth: Bool) -> String? {
        // 公历节日
        let solarFestivals: [String: String] = [
            "1-1": "元旦",
            "2-14": "情人节",
            "3-8": "妇女节",
            "3-12": "植树节",
            "4-1": "愚人节",
            "5-1": "劳动节",
            "5-4": "青年节",
            "6-1": "儿童节",
            "7-1": "建党节",
            "8-1": "建军节",
            "9-10": "教师节",
            "10-1": "国庆节",
            "12-25": "圣诞节"
        ]

        let solarKey = "\(month)-\(day)"
        if let festival = solarFestivals[solarKey] {
            return festival
        }

        // 农历节日（非闰月）
        if !isLeapMonth {
            let lunarFestivals: [String: String] = [
                "1-1": "春节",
                "1-15": "元宵节",
                "2-2": "龙抬头",
                "5-5": "端午节",
                "7-7": "七夕",
                "7-15": "中元节",
                "8-15": "中秋节",
                "9-9": "重阳节",
                "12-8": "腊八节",
                "12-30": "除夕"
            ]

            let lunarKey = "\(lunarMonth)-\(lunarDay)"
            return lunarFestivals[lunarKey]
        }

        return nil
    }

    // MARK: - 农历转公历

    static func lunarToSolar(year: Int, month: Int, day: Int, isLeapMonth: Bool) -> Date? {
        let lunarCalendar = Calendar(identifier: .chinese)

        // 创建农历日期组件
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.isLeapMonth = isLeapMonth
        components.calendar = lunarCalendar

        // 尝试直接获取日期
        if let date = lunarCalendar.date(from: components) {
            // 验证转换结果
            let verifyComponents = lunarCalendar.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
            if verifyComponents.year == year &&
               verifyComponents.month == month &&
               verifyComponents.day == day &&
               (verifyComponents.isLeapMonth ?? false) == isLeapMonth {
                return date
            }
        }

        // 如果直接转换失败，尝试在目标年份内搜索
        let solarCalendar = Calendar.current
        var searchComponents = DateComponents()
        searchComponents.year = year
        searchComponents.month = 1
        searchComponents.day = 1

        guard let startDate = solarCalendar.date(from: searchComponents) else { return nil }

        // 搜索范围：农历年通常比公历年晚约一个月
        let searchRange: Range<Int> = -30..<390  // 搜索约13个月的范围

        for dayOffset in searchRange {
            guard let checkDate = solarCalendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let lunarComponents = lunarCalendar.dateComponents([.year, .month, .day, .isLeapMonth], from: checkDate)

            if lunarComponents.year == year &&
               lunarComponents.month == month &&
               lunarComponents.day == day &&
               (lunarComponents.isLeapMonth ?? false) == isLeapMonth {
                return checkDate
            }
        }

        return nil
    }

    // MARK: - 获取某月第一天的农历信息

    static func getFirstDayOfMonth(year: Int, month: Int) -> LunarDate? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let date = Calendar.current.date(from: components) else { return nil }
        return convertSolarToLunar(date: date)
    }

    // MARK: - 获取某月的天数

    static func getDaysInMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month

        guard let date = Calendar.current.date(from: components) else { return 30 }
        return Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    // MARK: - 获取某月第一天是星期几 (1=周日, 7=周六)

    static func getFirstWeekdayOfMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let date = Calendar.current.date(from: components) else { return 1 }
        return Calendar.current.component(.weekday, from: date)
    }
}
