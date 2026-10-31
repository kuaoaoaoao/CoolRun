import Foundation

// MARK: - 节假日类型

enum HolidayType {
    case holiday     // 法定节假日（休）
    case workday     // 调休工作日（班）
}

// MARK: - 节假日信息

struct HolidayInfo {
    let name: String
    let type: HolidayType
}

// MARK: - 节假日数据模型（用于JSON解析）

struct HolidayItem: Codable {
    let name: String
    let type: String  // "holiday" or "workday"
}

// MARK: - 节假日服务

class HolidayService {
    static let shared = HolidayService()

    private let userDefaults = UserDefaults.standard
    private let cacheKey = "cached_holiday_data"
    private let lastUpdateKey = "holiday_last_update"
    private let versionKey = "holiday_data_version"

    // 当前内置数据版本
    private let currentVersion = 2

    private init() {
        // 首次启动时设置更新时间
        if userDefaults.object(forKey: lastUpdateKey) == nil {
            userDefaults.set(Date(), forKey: lastUpdateKey)
        }
    }

    // MARK: - 公开方法

    /// 获取节假日信息
    func getHolidayInfo(for date: Date) -> HolidayInfo? {
        let dateString = formatDate(date)

        // 先从缓存中查找
        if let cachedData = loadCachedData(),
           let item = cachedData[dateString] {
            let type: HolidayType = item.type == "holiday" ? .holiday : .workday
            return HolidayInfo(name: item.name, type: type)
        }

        // 使用内置数据
        return builtInHolidays[dateString]
    }

    /// 检查是否需要更新
    func needsUpdate() -> Bool {
        let savedVersion = userDefaults.integer(forKey: versionKey)
        return savedVersion < currentVersion
    }

    /// 将当前应用版本携带的节假日数据合并到本地缓存。
    /// 新年份数据随应用版本发布，不伪装成远程网络更新。
    func updateHolidayData() async throws {
        // 获取现有缓存
        var cachedData = loadCachedData() ?? [:]

        // 合并内置数据
        for (date, info) in builtInHolidays {
            cachedData[date] = HolidayItem(name: info.name, type: info.type == .holiday ? "holiday" : "workday")
        }

        // 保存到缓存
        saveToCache(cachedData)

        // 更新版本号和时间
        userDefaults.set(currentVersion, forKey: versionKey)
        userDefaults.set(Date(), forKey: lastUpdateKey)
    }

    /// 获取最后更新时间
    func getLastUpdateTime() -> Date? {
        return userDefaults.object(forKey: lastUpdateKey) as? Date
    }

    /// 获取当前数据版本
    func getCurrentVersion() -> Int {
        return currentVersion
    }

    /// 获取缓存的数据条数
    func getCachedDataCount() -> Int {
        return loadCachedData()?.count ?? 0
    }

    // MARK: - 缓存管理

    private func saveToCache(_ data: [String: HolidayItem]) {
        if let encoded = try? JSONEncoder().encode(data) {
            userDefaults.set(encoded, forKey: cacheKey)
        }
    }

    func loadCachedData() -> [String: HolidayItem]? {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode([String: HolidayItem].self, from: data)
    }

    // MARK: - 辅助方法

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - 内置节假日数据（2024-2026年）

    private let builtInHolidays: [String: HolidayInfo] = [
        // ==================== 2024年 ====================

        // 元旦
        "2024-01-01": HolidayInfo(name: "元旦", type: .holiday),

        // 春节
        "2024-02-10": HolidayInfo(name: "春节", type: .holiday),
        "2024-02-11": HolidayInfo(name: "春节", type: .holiday),
        "2024-02-12": HolidayInfo(name: "春节", type: .holiday),
        "2024-02-13": HolidayInfo(name: "春节", type: .holiday),
        "2024-02-14": HolidayInfo(name: "春节", type: .holiday),
        "2024-02-15": HolidayInfo(name: "春节", type: .holiday),
        "2024-02-16": HolidayInfo(name: "春节", type: .holiday),
        "2024-02-04": HolidayInfo(name: "春节调休", type: .workday),
        "2024-02-18": HolidayInfo(name: "春节调休", type: .workday),

        // 清明节
        "2024-04-04": HolidayInfo(name: "清明节", type: .holiday),
        "2024-04-05": HolidayInfo(name: "清明节", type: .holiday),
        "2024-04-06": HolidayInfo(name: "清明节", type: .holiday),

        // 劳动节
        "2024-05-01": HolidayInfo(name: "劳动节", type: .holiday),
        "2024-05-02": HolidayInfo(name: "劳动节", type: .holiday),
        "2024-05-03": HolidayInfo(name: "劳动节", type: .holiday),
        "2024-05-04": HolidayInfo(name: "劳动节", type: .holiday),
        "2024-05-05": HolidayInfo(name: "劳动节", type: .holiday),
        "2024-04-28": HolidayInfo(name: "劳动节调休", type: .workday),
        "2024-05-11": HolidayInfo(name: "劳动节调休", type: .workday),

        // 端午节
        "2024-06-08": HolidayInfo(name: "端午节", type: .holiday),
        "2024-06-09": HolidayInfo(name: "端午节", type: .holiday),
        "2024-06-10": HolidayInfo(name: "端午节", type: .holiday),

        // 中秋节
        "2024-09-15": HolidayInfo(name: "中秋节", type: .holiday),
        "2024-09-16": HolidayInfo(name: "中秋节", type: .holiday),
        "2024-09-17": HolidayInfo(name: "中秋节", type: .holiday),
        "2024-09-14": HolidayInfo(name: "中秋节调休", type: .workday),

        // 国庆节
        "2024-10-01": HolidayInfo(name: "国庆节", type: .holiday),
        "2024-10-02": HolidayInfo(name: "国庆节", type: .holiday),
        "2024-10-03": HolidayInfo(name: "国庆节", type: .holiday),
        "2024-10-04": HolidayInfo(name: "国庆节", type: .holiday),
        "2024-10-05": HolidayInfo(name: "国庆节", type: .holiday),
        "2024-10-06": HolidayInfo(name: "国庆节", type: .holiday),
        "2024-10-07": HolidayInfo(name: "国庆节", type: .holiday),
        "2024-09-29": HolidayInfo(name: "国庆节调休", type: .workday),
        "2024-10-12": HolidayInfo(name: "国庆节调休", type: .workday),

        // ==================== 2025年 ====================

        // 元旦
        "2025-01-01": HolidayInfo(name: "元旦", type: .holiday),

        // 春节
        "2025-01-28": HolidayInfo(name: "春节", type: .holiday),
        "2025-01-29": HolidayInfo(name: "春节", type: .holiday),
        "2025-01-30": HolidayInfo(name: "春节", type: .holiday),
        "2025-01-31": HolidayInfo(name: "春节", type: .holiday),
        "2025-02-01": HolidayInfo(name: "春节", type: .holiday),
        "2025-02-02": HolidayInfo(name: "春节", type: .holiday),
        "2025-02-03": HolidayInfo(name: "春节", type: .holiday),
        "2025-02-04": HolidayInfo(name: "春节", type: .holiday),
        "2025-01-26": HolidayInfo(name: "春节调休", type: .workday),
        "2025-02-08": HolidayInfo(name: "春节调休", type: .workday),

        // 清明节
        "2025-04-04": HolidayInfo(name: "清明节", type: .holiday),
        "2025-04-05": HolidayInfo(name: "清明节", type: .holiday),
        "2025-04-06": HolidayInfo(name: "清明节", type: .holiday),

        // 劳动节
        "2025-05-01": HolidayInfo(name: "劳动节", type: .holiday),
        "2025-05-02": HolidayInfo(name: "劳动节", type: .holiday),
        "2025-05-03": HolidayInfo(name: "劳动节", type: .holiday),
        "2025-05-04": HolidayInfo(name: "劳动节", type: .holiday),
        "2025-05-05": HolidayInfo(name: "劳动节", type: .holiday),
        "2025-04-27": HolidayInfo(name: "劳动节调休", type: .workday),

        // 端午节
        "2025-05-31": HolidayInfo(name: "端午节", type: .holiday),
        "2025-06-01": HolidayInfo(name: "端午节", type: .holiday),
        "2025-06-02": HolidayInfo(name: "端午节", type: .holiday),

        // 中秋节+国庆节
        "2025-10-01": HolidayInfo(name: "国庆节", type: .holiday),
        "2025-10-02": HolidayInfo(name: "国庆节", type: .holiday),
        "2025-10-03": HolidayInfo(name: "国庆节", type: .holiday),
        "2025-10-04": HolidayInfo(name: "国庆节", type: .holiday),
        "2025-10-05": HolidayInfo(name: "国庆节", type: .holiday),
        "2025-10-06": HolidayInfo(name: "中秋节", type: .holiday),
        "2025-10-07": HolidayInfo(name: "国庆节", type: .holiday),
        "2025-10-08": HolidayInfo(name: "国庆节", type: .holiday),
        "2025-09-28": HolidayInfo(name: "国庆节调休", type: .workday),
        "2025-10-11": HolidayInfo(name: "国庆节调休", type: .workday),

        // ==================== 2026年 ====================

        // 元旦
        "2026-01-01": HolidayInfo(name: "元旦", type: .holiday),
        "2026-01-02": HolidayInfo(name: "元旦", type: .holiday),
        "2026-01-03": HolidayInfo(name: "元旦", type: .holiday),

        // 春节
        "2026-02-17": HolidayInfo(name: "春节", type: .holiday),
        "2026-02-18": HolidayInfo(name: "春节", type: .holiday),
        "2026-02-19": HolidayInfo(name: "春节", type: .holiday),
        "2026-02-20": HolidayInfo(name: "春节", type: .holiday),
        "2026-02-21": HolidayInfo(name: "春节", type: .holiday),
        "2026-02-22": HolidayInfo(name: "春节", type: .holiday),
        "2026-02-23": HolidayInfo(name: "春节", type: .holiday),
        "2026-02-15": HolidayInfo(name: "春节调休", type: .workday),
        "2026-02-28": HolidayInfo(name: "春节调休", type: .workday),

        // 清明节
        "2026-04-04": HolidayInfo(name: "清明节", type: .holiday),
        "2026-04-05": HolidayInfo(name: "清明节", type: .holiday),
        "2026-04-06": HolidayInfo(name: "清明节", type: .holiday),

        // 劳动节
        "2026-05-01": HolidayInfo(name: "劳动节", type: .holiday),
        "2026-05-02": HolidayInfo(name: "劳动节", type: .holiday),
        "2026-05-03": HolidayInfo(name: "劳动节", type: .holiday),
        "2026-05-04": HolidayInfo(name: "劳动节", type: .holiday),
        "2026-05-05": HolidayInfo(name: "劳动节", type: .holiday),
        "2026-04-26": HolidayInfo(name: "劳动节调休", type: .workday),

        // 端午节
        "2026-06-19": HolidayInfo(name: "端午节", type: .holiday),
        "2026-06-20": HolidayInfo(name: "端午节", type: .holiday),
        "2026-06-21": HolidayInfo(name: "端午节", type: .holiday),

        // 中秋节
        "2026-09-25": HolidayInfo(name: "中秋节", type: .holiday),
        "2026-09-26": HolidayInfo(name: "中秋节", type: .holiday),
        "2026-09-27": HolidayInfo(name: "中秋节", type: .holiday),

        // 国庆节
        "2026-10-01": HolidayInfo(name: "国庆节", type: .holiday),
        "2026-10-02": HolidayInfo(name: "国庆节", type: .holiday),
        "2026-10-03": HolidayInfo(name: "国庆节", type: .holiday),
        "2026-10-04": HolidayInfo(name: "国庆节", type: .holiday),
        "2026-10-05": HolidayInfo(name: "国庆节", type: .holiday),
        "2026-10-06": HolidayInfo(name: "国庆节", type: .holiday),
        "2026-10-07": HolidayInfo(name: "国庆节", type: .holiday),
        "2026-10-10": HolidayInfo(name: "国庆节调休", type: .workday),
    ]
}
