import Foundation
import SwiftUI
import Combine

// MARK: - 应用设置管理器

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    // 语言设置
    @Published var language: AppLanguage {
        didSet {
            userDefaults.set(language.rawValue, forKey: "app_language")
        }
    }

    // 监控模块开关
    @Published var showCPU: Bool {
        didSet { userDefaults.set(showCPU, forKey: "monitor_cpu") }
    }
    @Published var showMemory: Bool {
        didSet { userDefaults.set(showMemory, forKey: "monitor_memory") }
    }
    @Published var showStorage: Bool {
        didSet { userDefaults.set(showStorage, forKey: "monitor_storage") }
    }
    @Published var showBattery: Bool {
        didSet { userDefaults.set(showBattery, forKey: "monitor_battery") }
    }
    @Published var showNetwork: Bool {
        didSet { userDefaults.set(showNetwork, forKey: "monitor_network") }
    }
    @Published var showUptime: Bool {
        didSet { userDefaults.set(showUptime, forKey: "monitor_uptime") }
    }
    @Published var showTemperature: Bool {
        didSet { userDefaults.set(showTemperature, forKey: "monitor_temperature") }
    }
    @Published var showProcesses: Bool {
        didSet { userDefaults.set(showProcesses, forKey: "monitor_processes") }
    }
    @Published var mergeProcesses: Bool {
        didSet { userDefaults.set(mergeProcesses, forKey: "monitor_process_merge") }
    }

    // 常驻刷新策略
    @Published var systemRefreshRate: SystemRefreshRate {
        didSet { userDefaults.set(systemRefreshRate.rawValue, forKey: "system_refresh_rate") }
    }

    @Published var menuBarAnimationRate: MenuBarAnimationRate {
        didSet { userDefaults.set(menuBarAnimationRate.rawValue, forKey: "menubar_animation_rate") }
    }

    @Published var showMenuBarCoinIcon: Bool {
        didSet { userDefaults.set(showMenuBarCoinIcon, forKey: "menubar_show_coin_icon") }
    }

    @Published var menuBarCoinMotion: MenuBarCoinMotion {
        didSet { userDefaults.set(menuBarCoinMotion.rawValue, forKey: "menubar_coin_motion") }
    }

    @Published var menuBarCoinAppearance: MenuBarCoinAppearance {
        didSet { userDefaults.set(menuBarCoinAppearance.rawValue, forKey: "menubar_coin_appearance") }
    }

    @Published var goldRefreshRate: GoldRefreshRate {
        didSet { userDefaults.set(goldRefreshRate.rawValue, forKey: "gold_refresh_rate") }
    }

    // 预测自动校准：关闭后只观察历史表现，不自动调整信心和仓位
    @Published var goldAutoCalibrationEnabled: Bool {
        didSet { userDefaults.set(goldAutoCalibrationEnabled, forKey: "gold_auto_calibration_enabled") }
    }

    // 金价到价提醒：触达上/下限时发系统通知
    @Published var goldAlertEnabled: Bool {
        didSet { userDefaults.set(goldAlertEnabled, forKey: "gold_alert_enabled") }
    }
    @Published var goldAlertUpperText: String {
        didSet { userDefaults.set(goldAlertUpperText, forKey: "gold_alert_upper") }
    }
    @Published var goldAlertLowerText: String {
        didSet { userDefaults.set(goldAlertLowerText, forKey: "gold_alert_lower") }
    }

    // AI 额度提醒：默认关闭，只有用户主动开启后才请求通知权限。
    @Published var aiQuotaAlertEnabled: Bool {
        didSet { userDefaults.set(aiQuotaAlertEnabled, forKey: "ai_quota_alert_enabled") }
    }

    // 隐私设置
    @Published var analyticsEnabled: Bool {
        didSet {
            userDefaults.set(analyticsEnabled, forKey: "analytics_enabled")
            Analytics.setEnabled(analyticsEnabled)
        }
    }

    // 菜单栏显示模式
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: "menubar_display_mode")
            if menuBarSecondaryDisplayMode == menuBarDisplayMode {
                menuBarSecondaryDisplayMode = MenuBarDisplayMode.allCases.first { $0 != menuBarDisplayMode } ?? .date
            }
        }
    }

    @Published var menuBarCompositionStyle: MenuBarCompositionStyle {
        didSet { userDefaults.set(menuBarCompositionStyle.rawValue, forKey: "menubar_composition_style") }
    }
    @Published var menuBarSecondaryDisplayMode: MenuBarDisplayMode {
        didSet {
            if menuBarSecondaryDisplayMode == menuBarDisplayMode {
                menuBarSecondaryDisplayMode = MenuBarDisplayMode.allCases.first { $0 != menuBarDisplayMode } ?? .date
                return
            }
            userDefaults.set(menuBarSecondaryDisplayMode.rawValue, forKey: "menubar_secondary_display_mode")
        }
    }
    @Published var menuBarRotationSeconds: Int {
        didSet { userDefaults.set(menuBarRotationSeconds, forKey: "menubar_rotation_seconds") }
    }

    // 本地提醒设置。全部默认关闭，只有用户主动开启时才申请通知权限。
    @Published var countdownRemindersEnabled: Bool {
        didSet { userDefaults.set(countdownRemindersEnabled, forKey: "reminder_countdown_enabled") }
    }
    @Published var birthdayRemindersEnabled: Bool {
        didSet { userDefaults.set(birthdayRemindersEnabled, forKey: "reminder_birthday_enabled") }
    }
    @Published var englishRemindersEnabled: Bool {
        didSet { userDefaults.set(englishRemindersEnabled, forKey: "reminder_english_enabled") }
    }
    @Published var systemAnomalyRemindersEnabled: Bool {
        didSet { userDefaults.set(systemAnomalyRemindersEnabled, forKey: "reminder_system_enabled") }
    }
    @Published var reminderDaysBefore: Int {
        didSet { userDefaults.set(reminderDaysBefore, forKey: "reminder_days_before") }
    }
    @Published var reminderHour: Int {
        didSet { userDefaults.set(reminderHour, forKey: "reminder_hour") }
    }
    @Published var reminderQuietHoursEnabled: Bool {
        didSet { userDefaults.set(reminderQuietHoursEnabled, forKey: "reminder_quiet_enabled") }
    }
    @Published var reminderQuietStartHour: Int {
        didSet { userDefaults.set(reminderQuietStartHour, forKey: "reminder_quiet_start_hour") }
    }
    @Published var reminderQuietEndHour: Int {
        didSet { userDefaults.set(reminderQuietEndHour, forKey: "reminder_quiet_end_hour") }
    }
    @Published var reminderSnoozeMinutes: Int {
        didSet { userDefaults.set(reminderSnoozeMinutes, forKey: "reminder_snooze_minutes") }
    }

    // 英语学习设置
    @Published var englishAccent: EnglishAccent {
        didSet { userDefaults.set(englishAccent.rawValue, forKey: "english_accent") }
    }
    @Published var englishVoiceIdentifier: String {
        didSet { userDefaults.set(englishVoiceIdentifier, forKey: "english_voice_identifier") }
    }
    @Published var englishTTSBackend: EnglishTTSBackend {
        didSet { userDefaults.set(englishTTSBackend.rawValue, forKey: "english_tts_backend") }
    }
    @Published var englishKokoroCommandPath: String {
        didSet { userDefaults.set(englishKokoroCommandPath, forKey: "english_kokoro_command_path") }
    }
    @Published var englishKokoroVoice: String {
        didSet { userDefaults.set(englishKokoroVoice, forKey: "english_kokoro_voice") }
    }
    @Published var englishNormalRate: Double {
        didSet { userDefaults.set(englishNormalRate, forKey: "english_normal_rate") }
    }
    @Published var englishSlowRate: Double {
        didSet { userDefaults.set(englishSlowRate, forKey: "english_slow_rate") }
    }
    @Published var englishVolume: Double {
        didSet { userDefaults.set(englishVolume, forKey: "english_volume") }
    }
    @Published var englishRepeatCount: Int {
        didSet { userDefaults.set(englishRepeatCount, forKey: "english_repeat_count") }
    }
    @Published var englishItemInterval: Double {
        didSet { userDefaults.set(englishItemInterval, forKey: "english_item_interval") }
    }
    @Published var englishShowTranslation: Bool {
        didSet { userDefaults.set(englishShowTranslation, forKey: "english_show_translation") }
    }
    @Published var englishSpeakTranslation: Bool {
        didSet { userDefaults.set(englishSpeakTranslation, forKey: "english_speak_translation") }
    }
    @Published var englishMenuTextStyle: EnglishMenuTextStyle {
        didSet { userDefaults.set(englishMenuTextStyle.rawValue, forKey: "english_menu_text_style") }
    }
    @Published var englishDailyTarget: Int {
        didSet { userDefaults.set(englishDailyTarget, forKey: "english_daily_target") }
    }
    @Published var englishHasSeenVoiceOnboarding: Bool {
        didSet { userDefaults.set(englishHasSeenVoiceOnboarding, forKey: "english_has_seen_voice_onboarding") }
    }
    // 语音质量横幅关闭后持久记住，不随面板重建反复出现
    @Published var englishVoiceHintDismissed: Bool {
        didSet { userDefaults.set(englishVoiceHintDismissed, forKey: "english_voice_hint_dismissed") }
    }
    @Published var englishStage: EnglishStage {
        didSet { userDefaults.set(englishStage.rawValue, forKey: "english_stage") }
    }

    // 记住上次使用的模块，重启后直接回到该模块
    @Published var lastViewModeRaw: String {
        didSet { userDefaults.set(lastViewModeRaw, forKey: "last_view_mode") }
    }

    // 面板导航栏中可见的模块（ViewMode.rawValue 集合），默认只显示监控/金价/日历/剪切板
    @Published var visibleTabRaws: Set<String> {
        didSet { userDefaults.set(visibleTabRaws.sorted(), forKey: "visible_tabs") }
    }

    private init() {
        // 从 UserDefaults 加载设置
        let langRaw = userDefaults.string(forKey: "app_language") ?? AppLanguage.chinese.rawValue
        self.language = AppLanguage(rawValue: langRaw) ?? .chinese

        self.showCPU = userDefaults.object(forKey: "monitor_cpu") as? Bool ?? true
        self.showMemory = userDefaults.object(forKey: "monitor_memory") as? Bool ?? true
        self.showStorage = userDefaults.object(forKey: "monitor_storage") as? Bool ?? true
        self.showBattery = userDefaults.object(forKey: "monitor_battery") as? Bool ?? true
        self.showNetwork = userDefaults.object(forKey: "monitor_network") as? Bool ?? true
        self.showUptime = userDefaults.object(forKey: "monitor_uptime") as? Bool ?? true
        self.showTemperature = userDefaults.object(forKey: "monitor_temperature") as? Bool ?? true
        self.showProcesses = userDefaults.object(forKey: "monitor_processes") as? Bool ?? true
        self.mergeProcesses = userDefaults.object(forKey: "monitor_process_merge") as? Bool ?? true

        let systemRefreshRaw = userDefaults.string(forKey: "system_refresh_rate") ?? SystemRefreshRate.balanced.rawValue
        self.systemRefreshRate = SystemRefreshRate(rawValue: systemRefreshRaw) ?? .balanced

        let animationRaw = userDefaults.string(forKey: "menubar_animation_rate") ?? MenuBarAnimationRate.energySaving.rawValue
        self.menuBarAnimationRate = MenuBarAnimationRate(rawValue: animationRaw) ?? .energySaving

        self.showMenuBarCoinIcon = userDefaults.object(forKey: "menubar_show_coin_icon") as? Bool ?? true

        let coinMotionRaw = userDefaults.string(forKey: "menubar_coin_motion") ?? MenuBarCoinMotion.classicFlip.rawValue
        self.menuBarCoinMotion = MenuBarCoinMotion(rawValue: coinMotionRaw) ?? .classicFlip

        let coinAppearanceRaw = userDefaults.string(forKey: "menubar_coin_appearance") ?? MenuBarCoinAppearance.yuan.rawValue
        self.menuBarCoinAppearance = MenuBarCoinAppearance(rawValue: coinAppearanceRaw) ?? .yuan

        let goldRefreshRaw = userDefaults.string(forKey: "gold_refresh_rate") ?? GoldRefreshRate.minute.rawValue
        self.goldRefreshRate = GoldRefreshRate(rawValue: goldRefreshRaw) ?? .minute

        self.goldAutoCalibrationEnabled = userDefaults.object(forKey: "gold_auto_calibration_enabled") as? Bool ?? true

        self.goldAlertEnabled = userDefaults.object(forKey: "gold_alert_enabled") as? Bool ?? false
        self.goldAlertUpperText = userDefaults.string(forKey: "gold_alert_upper") ?? ""
        self.goldAlertLowerText = userDefaults.string(forKey: "gold_alert_lower") ?? ""
        self.aiQuotaAlertEnabled = userDefaults.object(forKey: "ai_quota_alert_enabled") as? Bool ?? false

        // 新安装和源码 fork 默认不发送遥测；已有用户的明确选择保持不变。
        self.analyticsEnabled = userDefaults.object(forKey: "analytics_enabled") as? Bool ?? false

        self.lastViewModeRaw = userDefaults.string(forKey: "last_view_mode") ?? ""

        // 首次运行（无持久化值）时采用默认可见模块；已存值则过滤掉失效 raw 后恢复，
        // 全部失效（手改 plist、版本删减模块等）时回退默认，保证导航栏不为空。
        // 另外做一次结构版本迁移：把老版本之后新增的模块并入已保存的集合，
        // 否则升级上来的用户永远看不到新模块。
        let validRaws = Set(ViewMode.allCases.map(\.rawValue))
        let storedSchema = userDefaults.object(forKey: "visible_tabs_schema") as? Int ?? 1
        let resolvedTabs: Set<String>
        if let savedTabs = userDefaults.stringArray(forKey: "visible_tabs"), !savedTabs.isEmpty {
            var cleaned = Set(savedTabs).intersection(validRaws)
            if storedSchema < ViewMode.visibleTabsSchemaVersion {
                cleaned.formUnion(ViewMode.modulesAdded(after: storedSchema).map(\.rawValue))
            }
            resolvedTabs = cleaned.isEmpty
                ? Set(ViewMode.defaultVisible.map(\.rawValue))
                : cleaned
        } else {
            resolvedTabs = Set(ViewMode.defaultVisible.map(\.rawValue))
        }
        self.visibleTabRaws = resolvedTabs
        if storedSchema < ViewMode.visibleTabsSchemaVersion {
            userDefaults.set(resolvedTabs.sorted(), forKey: "visible_tabs")
            userDefaults.set(ViewMode.visibleTabsSchemaVersion, forKey: "visible_tabs_schema")
        }

        let modeRaw = userDefaults.string(forKey: "menubar_display_mode") ?? MenuBarDisplayMode.goldPrice.rawValue
        let primaryMode = MenuBarDisplayMode(rawValue: modeRaw) ?? .goldPrice
        self.menuBarDisplayMode = primaryMode
        let compositionRaw = userDefaults.string(forKey: "menubar_composition_style") ?? MenuBarCompositionStyle.single.rawValue
        self.menuBarCompositionStyle = MenuBarCompositionStyle(rawValue: compositionRaw) ?? .single
        let secondaryRaw = userDefaults.string(forKey: "menubar_secondary_display_mode") ?? MenuBarDisplayMode.date.rawValue
        let savedSecondary = MenuBarDisplayMode(rawValue: secondaryRaw) ?? .date
        self.menuBarSecondaryDisplayMode = savedSecondary == primaryMode
            ? (MenuBarDisplayMode.allCases.first { $0 != primaryMode } ?? .date)
            : savedSecondary
        self.menuBarRotationSeconds = max(userDefaults.object(forKey: "menubar_rotation_seconds") as? Int ?? 10, 5)

        self.countdownRemindersEnabled = userDefaults.object(forKey: "reminder_countdown_enabled") as? Bool ?? false
        self.birthdayRemindersEnabled = userDefaults.object(forKey: "reminder_birthday_enabled") as? Bool ?? false
        self.englishRemindersEnabled = userDefaults.object(forKey: "reminder_english_enabled") as? Bool ?? false
        self.systemAnomalyRemindersEnabled = userDefaults.object(forKey: "reminder_system_enabled") as? Bool ?? false
        self.reminderDaysBefore = userDefaults.object(forKey: "reminder_days_before") as? Int ?? 1
        self.reminderHour = userDefaults.object(forKey: "reminder_hour") as? Int ?? 9
        self.reminderQuietHoursEnabled = userDefaults.object(forKey: "reminder_quiet_enabled") as? Bool ?? true
        self.reminderQuietStartHour = userDefaults.object(forKey: "reminder_quiet_start_hour") as? Int ?? 22
        self.reminderQuietEndHour = userDefaults.object(forKey: "reminder_quiet_end_hour") as? Int ?? 8
        self.reminderSnoozeMinutes = userDefaults.object(forKey: "reminder_snooze_minutes") as? Int ?? 30

        let accentRaw = userDefaults.string(forKey: "english_accent") ?? EnglishAccent.american.rawValue
        self.englishAccent = EnglishAccent(rawValue: accentRaw) ?? .american
        self.englishVoiceIdentifier = userDefaults.string(forKey: "english_voice_identifier") ?? ""
        let ttsBackendRaw = userDefaults.string(forKey: "english_tts_backend") ?? EnglishTTSBackend.system.rawValue
        self.englishTTSBackend = EnglishTTSBackend(rawValue: ttsBackendRaw) ?? .system
        self.englishKokoroCommandPath = userDefaults.string(forKey: "english_kokoro_command_path") ?? ""
        self.englishKokoroVoice = userDefaults.string(forKey: "english_kokoro_voice") ?? KokoroEnglishSpeechProvider.defaultVoice
        self.englishNormalRate = userDefaults.object(forKey: "english_normal_rate") as? Double ?? 0.43
        self.englishSlowRate = userDefaults.object(forKey: "english_slow_rate") as? Double ?? 0.30
        let savedEnglishVolume = userDefaults.object(forKey: "english_volume") as? Double ?? 0.9
        self.englishVolume = min(max(savedEnglishVolume, 0.1), 1)
        self.englishRepeatCount = userDefaults.object(forKey: "english_repeat_count") as? Int ?? 2
        self.englishItemInterval = userDefaults.object(forKey: "english_item_interval") as? Double ?? 7
        self.englishShowTranslation = userDefaults.object(forKey: "english_show_translation") as? Bool ?? true
        self.englishSpeakTranslation = userDefaults.object(forKey: "english_speak_translation") as? Bool ?? false
        let textStyleRaw = userDefaults.string(forKey: "english_menu_text_style") ?? EnglishMenuTextStyle.englishOnly.rawValue
        self.englishMenuTextStyle = EnglishMenuTextStyle(rawValue: textStyleRaw) ?? .englishOnly
        self.englishDailyTarget = userDefaults.object(forKey: "english_daily_target") as? Int ?? 10
        self.englishHasSeenVoiceOnboarding = userDefaults.object(forKey: "english_has_seen_voice_onboarding") as? Bool ?? false
        self.englishVoiceHintDismissed = userDefaults.object(forKey: "english_voice_hint_dismissed") as? Bool ?? false
        let stageRaw = userDefaults.string(forKey: "english_stage") ?? EnglishStage.daily.rawValue
        self.englishStage = EnglishStage(rawValue: stageRaw) ?? .daily
    }

    // MARK: - 面板模块显隐

    /// 按 ViewMode 声明顺序返回当前可见的模块
    var visibleViewModes: [ViewMode] {
        ViewMode.allCases.filter { visibleTabRaws.contains($0.rawValue) }
    }

    func isTabVisible(_ mode: ViewMode) -> Bool {
        visibleTabRaws.contains(mode.rawValue)
    }

    /// 切换模块显隐；保底至少保留一个有效可见模块，避免导航栏为空
    func setTabVisible(_ mode: ViewMode, _ visible: Bool) {
        if visible {
            visibleTabRaws.insert(mode.rawValue)
        } else {
            guard visibleViewModes.count > 1 else { return }
            visibleTabRaws.remove(mode.rawValue)
        }
    }

    /// 启动时的初始模块：优先恢复上次使用且仍可见的模块，否则取第一个可见模块
    var initialViewMode: ViewMode {
        if let saved = ViewMode(rawValue: lastViewModeRaw), isTabVisible(saved) {
            return saved
        }
        return visibleViewModes.first ?? .monitor
    }
}

// MARK: - 语言枚举
