import Combine
import Foundation

/// 跨平台的轻量数据同步层，基于 iCloud 键值存储（`NSUbiquitousKeyValueStore`）。
///
/// 设计目标：让 macOS / iOS 上登录同一 iCloud 账号的 CoolRun 各端，
/// 共享少量“小数据”——目前是黄金持仓（克数、成本价）与英语打卡状态。
///
/// - 金价本身不走同步：各端可直接调用公开 API 拉取实时价，仅需从这里读持仓即可本地算盈亏。
/// - 需要在各 Target 开启 iCloud「Key-value storage」能力后才会真正跨设备同步；
///   未开启能力时本类会降级为“仅本地”行为，不会崩溃。
///
/// 该类默认运行在 MainActor（工程 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`）。
final class CloudSyncStore: ObservableObject {
    static let shared = CloudSyncStore()

    /// 同步的键。`rawValue` 与 macOS 端既有的 `@AppStorage` 键保持一致，
    /// 从而无需迁移历史本地数据。
    enum Key: String, CaseIterable {
        case goldHoldingGrams = "goldHoldingGramsText"
        case goldHoldingAverageCost = "goldHoldingAverageCostText"
        case englishStreakDays = "englishStreakDays"
        case englishTodayWordID = "englishTodayWordID"
        case englishTodayWord = "englishTodayWord"
        case englishTodayTranslation = "englishTodayTranslation"
        case englishLearnedToday = "englishLearnedToday"
        case englishDailyTargetSync = "englishDailyTargetSync"
        case englishAccent = "englishAccentSync"
        // 生日列表以 JSON 字符串镜像到 iCloud；使用独立键，避免与本地 `saved_birthdays`（Data）冲突。
        case birthdaysJSON = "cloudBirthdaysJSON"
    }

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let localDefaults = UserDefaults.standard
    private var observer: NSObjectProtocol?
    private var started = false

    /// 供应用视图直接观察的镜像值（避免各端都去读 UserDefaults）。
    @Published private(set) var values: [String: String] = [:]

    private init() {
        for key in Key.allCases {
            values[key.rawValue] = kvStore.string(forKey: key.rawValue)
                ?? localDefaults.string(forKey: key.rawValue)
        }
    }

    /// 在 App 启动时调用一次：开始监听 iCloud 外部变更，并做一次首屏拉取。
    func start() {
        guard !started else { return }
        started = true

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pullRemoteIntoLocal()
            }
        }

        kvStore.synchronize()
        pullRemoteIntoLocal()
    }

    // MARK: - 写入（在“编辑端”调用，通常是 macOS / iOS）

    /// 写入一个键：本地 UserDefaults 与 iCloud 同时更新。
    func setString(_ value: String, for key: Key) {
        values[key.rawValue] = value
        localDefaults.set(value, forKey: key.rawValue)
        kvStore.set(value, forKey: key.rawValue)
        kvStore.synchronize()
    }

    /// 便捷方法：推送黄金持仓。
    func pushGoldPosition(gramsText: String, averageCostText: String) {
        setString(gramsText, for: .goldHoldingGrams)
        setString(averageCostText, for: .goldHoldingAverageCost)
    }

    /// 推送英语打卡快照：连续天数、今日已学/目标、今日单词与释义，供手表抬手查看。
    func pushEnglish(
        streak: Int,
        learnedToday: Int,
        dailyTarget: Int,
        word: String?,
        translation: String?,
        wordID: String?,
        accent: String? = nil
    ) {
        setString(String(streak), for: .englishStreakDays)
        setString(String(learnedToday), for: .englishLearnedToday)
        setString(String(dailyTarget), for: .englishDailyTargetSync)
        setString(word ?? "", for: .englishTodayWord)
        setString(translation ?? "", for: .englishTodayTranslation)
        setString(wordID ?? "", for: .englishTodayWordID)
        if let accent { setString(accent, for: .englishAccent) }
    }

    /// 直接推送生日 JSON（由 `BirthdayManager` 在保存时调用）。
    func pushBirthdaysJSON(_ json: String) {
        setString(json, for: .birthdaysJSON)
    }

    /// 从本地 `saved_birthdays`（Data）读取并镜像到 iCloud，供 App 启动时补一次。
    func pushBirthdaysFromLocalDefaults() {
        guard let data = localDefaults.data(forKey: "saved_birthdays"),
              let json = String(data: data, encoding: .utf8) else { return }
        setString(json, for: .birthdaysJSON)
    }

    // MARK: - 读取

    func string(for key: Key) -> String? {
        values[key.rawValue]
    }

    func double(for key: Key) -> Double? {
        guard let text = string(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return Double(text)
    }

    // MARK: - 远端 → 本地

    private func pullRemoteIntoLocal() {
        for key in Key.allCases {
            guard let remote = kvStore.string(forKey: key.rawValue) else { continue }
            if values[key.rawValue] != remote {
                values[key.rawValue] = remote
            }
            // 同步回本地 UserDefaults，使 macOS 端的 @AppStorage 绑定也能反映远端变更。
            if localDefaults.string(forKey: key.rawValue) != remote {
                localDefaults.set(remote, forKey: key.rawValue)
            }
        }
    }
}
