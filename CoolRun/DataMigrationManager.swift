import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 数据迁移管理器

/// 负责应用全部用户数据的导出与导入，实现跨设备迁移和本地备份。
/// 导出为单个 `.coolrun` 文件（实际为 JSON 档案），内含所有模块数据。
@MainActor
final class DataMigrationManager {
    static let shared = DataMigrationManager()

    // 最近一次导出/导入的失败原因（取消操作为 nil，供设置页区分失败与取消）
    private(set) var lastErrorMessage: String?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    // MARK: - Export

    /// 导出所有用户数据为单个文件，返回是否成功。
    @discardableResult
    func exportAllData() -> Bool {
        let panel = NSSavePanel()
        panel.title = LocalizedString.migration("export_title")
        panel.nameFieldStringValue = "CoolRun-backup-\(Self.dateStamp()).coolrun"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        lastErrorMessage = nil
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let archive = buildArchive()
            let data = try encoder.encode(archive)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            showAlert(
                title: LocalizedString.migration("export_failed"),
                message: error.localizedDescription,
                style: .critical
            )
            return false
        }
    }

    // MARK: - Import

    /// 从文件导入数据，合并或覆盖现有数据。返回是否成功。
    @discardableResult
    func importData() -> Bool {
        let panel = NSOpenPanel()
        panel.title = LocalizedString.migration("import_title")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        lastErrorMessage = nil
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let data = try Data(contentsOf: url)
            let archive = try decoder.decode(DataArchive.self, from: data)

            let confirmed = showConfirmation(
                title: LocalizedString.migration("import_confirm"),
                message: buildImportSummary(archive)
            )
            guard confirmed else { return false }

            restoreArchive(archive)
            return true
        } catch {
            lastErrorMessage = LocalizedString.migration("import_corrupt") + "：\(error.localizedDescription)"
            showAlert(
                title: LocalizedString.migration("import_failed"),
                message: LocalizedString.migration("import_corrupt") + "：\(error.localizedDescription)",
                style: .critical
            )
            return false
        }
    }

    // MARK: - Archive Structure

    private func buildArchive() -> DataArchive {
        DataArchive(
            version: 3,
            exportedAt: Date(),
            appVersion: AppVersion.current.marketingVersion,
            birthdays: BirthdayManager.shared.getAllBirthdays(),
            countdownEvents: nonEmpty(CountdownManager.shared.getAllEvents()),
            englishProgress: exportEnglishProgress(),
            goldPriceRecords: GoldPriceStore.shared.records,
            goldPredictionLearningRecords: GoldPredictionLearningStore.shared.records,
            goldTrades: GoldTradeStore.shared.records.isEmpty ? nil : GoldTradeStore.shared.records,
            appSettings: exportSettings(),
            goldWeeklyForecastRecords: GoldWeeklyForecastStore.shared.records.isEmpty
                ? nil : GoldWeeklyForecastStore.shared.records
        )
    }

    private func restoreArchive(_ archive: DataArchive) {
        // 1. 恢复生日数据
        if !archive.birthdays.isEmpty {
            let existing = BirthdayManager.shared.getAllBirthdays()
            let existingIDs = Set(existing.map(\.id))
            for birthday in archive.birthdays where !existingIDs.contains(birthday.id) {
                BirthdayManager.shared.saveBirthday(birthday)
            }
        }

        // 1.5 恢复倒数日（按 UUID 去重，不覆盖本地已有记录）
        if let countdownEvents = archive.countdownEvents {
            CountdownManager.shared.mergeEvents(countdownEvents)
        }

        // 2. 恢复英语学习进度
        if let englishData = archive.englishProgress {
            restoreEnglishProgress(englishData)
        }

        // 3. 恢复金价历史
        if !archive.goldPriceRecords.isEmpty {
            for record in archive.goldPriceRecords {
                GoldPriceStore.shared.addPrice(record.price, timestamp: record.timestamp, source: record.source)
            }
            GoldPriceStore.shared.flushToDisk()
        }

        // 3.5 恢复预测学习记录
        if !archive.goldPredictionLearningRecords.isEmpty {
            let existingRecords = GoldPredictionLearningStore.shared.records
            let existingIDs = Set(existingRecords.map(\.id))
            var newRecords = existingRecords
            for record in archive.goldPredictionLearningRecords where !existingIDs.contains(record.id) {
                newRecords.append(record)
            }
            GoldPredictionLearningStore.shared.records = newRecords
            GoldPredictionLearningStore.shared.refreshSummary()
            GoldPredictionLearningStore.shared.saveToDisk()
        }

        // 3.6 恢复交易流水（按 id 去重合并）
        if let trades = archive.goldTrades, !trades.isEmpty {
            GoldTradeStore.shared.merge(trades)
        }

        // 3.7 恢复一周预测记录（按 id 去重合并）
        if let weeklyRecords = archive.goldWeeklyForecastRecords, !weeklyRecords.isEmpty {
            GoldWeeklyForecastStore.shared.merge(weeklyRecords)
        }

        // 4. 恢复应用设置
        if let settingsData = archive.appSettings {
            restoreSettings(settingsData)
        }
    }

    // MARK: - English Progress Export/Import

    private func exportEnglishProgress() -> EnglishProgressData? {
        let store = EnglishProgressStore.shared
        guard !store.records.isEmpty else { return nil }
        return EnglishProgressData(
            records: store.records,
            activityDays: store.activityDays,
            learnedItemIDsByDay: store.learnedItemIDsByDay
        )
    }

    private func restoreEnglishProgress(_ data: EnglishProgressData) {
        let store = EnglishProgressStore.shared
        // 合并逻辑：保留已有中更高的 mastery，累加计数
        for (itemID, importedProgress) in data.records {
            let existing = store.progress(for: itemID)
            if importedProgress.mastery > existing.mastery {
                store.setMastery(importedProgress.mastery, for: itemID)
            }
            // 如果导入的进度有收藏且本地没有，同步收藏
            if importedProgress.isFavorite && !existing.isFavorite {
                store.toggleFavorite(itemID)
            }
        }
    }

    // MARK: - Settings Export/Import

    private func exportSettings() -> SettingsData? {
        let s = AppSettings.shared
        return SettingsData(
            language: s.language.rawValue,
            menuBarDisplayMode: s.menuBarDisplayMode.rawValue,
            systemRefreshRate: s.systemRefreshRate.rawValue,
            goldRefreshRate: s.goldRefreshRate.rawValue,
            menuBarAnimationRate: s.menuBarAnimationRate.rawValue,
            englishAccent: s.englishAccent.rawValue,
            englishStage: s.englishStage.rawValue,
            englishTTSBackend: s.englishTTSBackend.rawValue,
            englishNormalRate: s.englishNormalRate,
            englishSlowRate: s.englishSlowRate,
            englishVolume: s.englishVolume,
            englishRepeatCount: s.englishRepeatCount,
            englishItemInterval: s.englishItemInterval,
            englishDailyTarget: s.englishDailyTarget,
            englishShowTranslation: s.englishShowTranslation,
            englishSpeakTranslation: s.englishSpeakTranslation,
            aiQuotaAlertEnabled: s.aiQuotaAlertEnabled,
            goldHoldingGramsText: UserDefaults.standard.string(forKey: "goldHoldingGramsText"),
            goldHoldingAverageCostText: UserDefaults.standard.string(forKey: "goldHoldingAverageCostText"),
            visibleTabs: s.visibleTabRaws.sorted()
        )
    }

    private func restoreSettings(_ data: SettingsData) {
        let s = AppSettings.shared
        if let lang = AppLanguage(rawValue: data.language) { s.language = lang }
        if let mode = MenuBarDisplayMode(rawValue: data.menuBarDisplayMode) { s.menuBarDisplayMode = mode }
        if let rate = SystemRefreshRate(rawValue: data.systemRefreshRate) { s.systemRefreshRate = rate }
        if let rate = GoldRefreshRate(rawValue: data.goldRefreshRate) { s.goldRefreshRate = rate }
        if let rate = MenuBarAnimationRate(rawValue: data.menuBarAnimationRate) { s.menuBarAnimationRate = rate }
        if let accent = EnglishAccent(rawValue: data.englishAccent) { s.englishAccent = accent }
        if let stage = EnglishStage(rawValue: data.englishStage) { s.englishStage = stage }
        if let backend = EnglishTTSBackend(rawValue: data.englishTTSBackend) { s.englishTTSBackend = backend }
        s.englishNormalRate = data.englishNormalRate
        s.englishSlowRate = data.englishSlowRate
        s.englishVolume = data.englishVolume
        s.englishRepeatCount = data.englishRepeatCount
        s.englishItemInterval = data.englishItemInterval
        s.englishDailyTarget = data.englishDailyTarget
        s.englishShowTranslation = data.englishShowTranslation
        s.englishSpeakTranslation = data.englishSpeakTranslation
        if let enabled = data.aiQuotaAlertEnabled {
            s.aiQuotaAlertEnabled = enabled
        }
        if let grams = data.goldHoldingGramsText {
            UserDefaults.standard.set(grams, forKey: "goldHoldingGramsText")
        }
        if let averageCost = data.goldHoldingAverageCostText {
            UserDefaults.standard.set(averageCost, forKey: "goldHoldingAverageCostText")
        }
        // 恢复面板模块显隐；过滤失效 raw，全部无效时忽略（保留本机现状）
        if let visibleTabs = data.visibleTabs {
            let validRaws = Set(ViewMode.allCases.map(\.rawValue))
            let cleaned = Set(visibleTabs).intersection(validRaws)
            if !cleaned.isEmpty {
                s.visibleTabRaws = cleaned
            }
        }
    }

    // MARK: - Helpers

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func nonEmpty<T>(_ values: [T]) -> [T]? {
        values.isEmpty ? nil : values
    }

    private func buildImportSummary(_ archive: DataArchive) -> String {
        var parts: [String] = []
        parts.append(LocalizedString.migration("export_time") + Self.formatDate(archive.exportedAt))
        parts.append(LocalizedString.migration("source_version") + "v\(archive.appVersion)")
        parts.append("")
        parts.append(LocalizedString.migration("merge_hint"))

        if !archive.birthdays.isEmpty {
            parts.append("• \(LocalizedString.migration("birthday_items")) \(archive.birthdays.count)")
        }
        if let countdownEvents = archive.countdownEvents, !countdownEvents.isEmpty {
            parts.append("• \(LocalizedString.migration("countdown_items")) \(countdownEvents.count)")
        }
        if let english = archive.englishProgress, !english.records.isEmpty {
            parts.append("• \(LocalizedString.migration("english_items")) \(english.records.count)")
        }
        if !archive.goldPriceRecords.isEmpty {
            parts.append("• \(LocalizedString.migration("gold_items")) \(archive.goldPriceRecords.count)")
        }
        if let trades = archive.goldTrades, !trades.isEmpty {
            parts.append("• \(LocalizedString.migration("gold_trade_items")) \(trades.count)")
        }
        if let weeklyRecords = archive.goldWeeklyForecastRecords, !weeklyRecords.isEmpty {
            parts.append("• \(LocalizedString.migration("gold_weekly_forecast_items")) \(weeklyRecords.count)")
        }
        if archive.appSettings != nil {
            parts.append("• \(LocalizedString.migration("app_settings"))")
        }
        return parts.joined(separator: "\n")
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: LocalizedString.common("confirm"))
        alert.runModal()
    }

    private func showConfirmation(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: LocalizedString.common("import"))
        alert.addButton(withTitle: LocalizedString.common("cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Data Models

struct DataArchive: Codable {
    let version: Int
    let exportedAt: Date
    let appVersion: String
    let birthdays: [Birthday]
    // v2 追加：倒数日（可选以兼容 v1 档案）
    let countdownEvents: [CountdownEvent]?
    let englishProgress: EnglishProgressData?
    let goldPriceRecords: [GoldPriceRecord]
    let goldPredictionLearningRecords: [GoldPredictionLearningRecord]
    // v1.1 追加：交易流水（可选，兼容旧档案 decodeIfPresent）
    let goldTrades: [GoldTradeRecord]?
    let appSettings: SettingsData?
    // v3 追加：一周预测记录（可选，兼容旧档案）
    let goldWeeklyForecastRecords: [GoldWeeklyForecastRecord]?
}

// Extension to make GoldPredictionLearningRecord conform to Codable if needed
// It already conforms to Codable, so no changes needed.

struct EnglishProgressData: Codable {
    let records: [String: EnglishItemProgress]
    let activityDays: Set<String>
    let learnedItemIDsByDay: [String: Set<String>]
}

struct SettingsData: Codable {
    let language: String
    let menuBarDisplayMode: String
    let systemRefreshRate: String
    let goldRefreshRate: String
    let menuBarAnimationRate: String
    let englishAccent: String
    let englishStage: String
    let englishTTSBackend: String
    let englishNormalRate: Double
    let englishSlowRate: Double
    let englishVolume: Double
    let englishRepeatCount: Int
    let englishItemInterval: Double
    let englishDailyTarget: Int
    let englishShowTranslation: Bool
    let englishSpeakTranslation: Bool
    // v2 追加字段均为可选，旧备份可继续解码。
    let aiQuotaAlertEnabled: Bool?
    let goldHoldingGramsText: String?
    let goldHoldingAverageCostText: String?
    // v4 追加：面板模块显隐配置（可选，兼容旧档案）
    let visibleTabs: [String]?
}
