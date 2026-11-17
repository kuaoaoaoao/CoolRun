import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 设置卡片组件

struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    let description: String
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        AppTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.11),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                Text(title)
                    .font(.headline)

                Spacer()
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            content
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.elevatedSurface(colorScheme))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
                )
        }
        .padding(14)
        .appCardSurface(cornerRadius: 12, showsShadow: false)
    }
}

// MARK: - 数据备份卡片

struct DataBackupCard: View {
    @State private var exportSuccess = false
    @State private var importSuccess = false
    @State private var statusMessage: String?
    // 当前状态消息是否为失败（红色展示）
    @State private var isErrorMessage = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsCard(
            icon: "externaldrive.fill",
            title: LocalizedString.settings("data_backup"),
            description: LocalizedString.settings("data_backup_desc")
        ) {
            VStack(spacing: 0) {
                // 数据统计
                HStack(spacing: 6) {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text(dataSummaryText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider().padding(.horizontal, 14)

                // 导出/导入按钮
                HStack(spacing: 12) {
                    Button {
                        let success = DataMigrationManager.shared.exportAllData()
                        if success {
                            statusMessage = LocalizedString.settings("export_success")
                            isErrorMessage = false
                            exportSuccess = true
                            clearMessageAfterDelay()
                        } else if let error = DataMigrationManager.shared.lastErrorMessage {
                            // 取消不提示，真失败才显示红色消息
                            statusMessage = error
                            isErrorMessage = true
                            clearMessageAfterDelay()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .medium))
                            Text(LocalizedString.settings("export"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        let success = DataMigrationManager.shared.importData()
                        if success {
                            statusMessage = LocalizedString.settings("import_success")
                            isErrorMessage = false
                            importSuccess = true
                            clearMessageAfterDelay()
                        } else if let error = DataMigrationManager.shared.lastErrorMessage {
                            statusMessage = error
                            isErrorMessage = true
                            clearMessageAfterDelay()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .medium))
                            Text(LocalizedString.settings("import_data"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.accentColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                // 状态消息（成功绿色 / 失败红色）
                if let message = statusMessage {
                    Divider().padding(.horizontal, 14)
                    HStack(spacing: 6) {
                        Image(systemName: isErrorMessage ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(isErrorMessage ? Color.red : Color.green)
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(isErrorMessage ? Color.red : Color.green)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }

                Divider().padding(.horizontal, 14)

                // 说明
                Text(LocalizedString.settings("data_backup_note"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
    }

    private var dataSummaryText: String {
        let birthdayCount = BirthdayManager.shared.getAllBirthdays().count
        let countdownCount = CountdownManager.shared.getAllEvents().count
        let englishCount = EnglishProgressStore.shared.records.count
        let goldCount = GoldPriceStore.shared.records.count

        return LocalizedString.l(
            settings.language,
            en: "\(birthdayCount) birthdays · \(countdownCount) countdowns · \(englishCount) words · \(goldCount) prices",
            zh: "\(birthdayCount) 条生日 · \(countdownCount) 个倒数日 · \(englishCount) 条进度 · \(goldCount) 条金价",
            ja: "\(birthdayCount) 件の誕生日 · \(countdownCount) 件のカウントダウン · \(englishCount) 件の進捗 · \(goldCount) 件の価格",
            ko: "\(birthdayCount) 생일 · \(countdownCount) 카운트다운 · \(englishCount) 학습 기록 · \(goldCount) 가격 기록"
        )
    }

    private func clearMessageAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            statusMessage = nil
        }
    }
}

// MARK: - 更新检查卡片

struct UpdateCheckCard: View {
    @State private var updateChecker = UpdateChecker.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsCard(
            icon: "arrow.triangle.2.circlepath.circle.fill",
            title: LocalizedString.settings("app_updates"),
            description: LocalizedString.settings("app_updates_desc")
        ) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: updateChecker.hasUpdate ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(updateChecker.hasUpdate ? AppTheme.warning : .green)

                            if updateChecker.hasUpdate {
                                Text("v\(updateChecker.latestVersion ?? "") \(LocalizedString.settings("available"))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.warning)
                            } else {
                                Text("v\(AppVersion.current.marketingVersion) \(LocalizedString.settings("up_to_date"))")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }

                        if let lastCheck = updateChecker.lastCheckDate {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text("\(LocalizedString.settings("last_checked")) \(formatDate(lastCheck))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        Task {
                            await updateChecker.checkForUpdates(silent: false)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if updateChecker.isChecking {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Text(updateChecker.isChecking
                                ? LocalizedString.settings("checking")
                                : LocalizedString.settings("check_now"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(updateChecker.isChecking ? Color.gray : Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(updateChecker.isChecking)
                }
                .padding(12)

                if updateChecker.hasUpdate, let url = updateChecker.releaseURL {
                    Divider().padding(.horizontal, 14)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                        Button(LocalizedString.settings("download_page")) {
                            NSWorkspace.shared.open(url)
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.link)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            if updateChecker.lastCheckDate == nil {
                Task {
                    await updateChecker.checkForUpdates(silent: true)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 节假日更新卡片

struct HolidayUpdateCard: View {
    @State private var isUpdating = false
    @State private var updateMessage: String?
    @State private var updateSuccess = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    private let holidayService = HolidayService.shared

    var body: some View {
        SettingsCard(
            icon: "calendar.badge.clock",
            title: LocalizedString.data("holiday_data", lang: settings.language),
            description: LocalizedString.data("holiday_data_desc", lang: settings.language)
        ) {
            VStack(spacing: 12) {
                // 状态信息
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        // 数据状态
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)

                            Text("\(LocalizedString.data("data_version", lang: settings.language)): v\(holidayService.getCurrentVersion())")
                                .font(.system(size: 12, weight: .medium))
                        }

                        // 数据条数
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Text("\(holidayService.getCachedDataCount()) \(LocalizedString.data("record_count", lang: settings.language))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        // 最后更新时间
                        if let lastUpdate = holidayService.getLastUpdateTime() {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

                                Text("\(LocalizedString.data("last_update", lang: settings.language)): \(formatDate(lastUpdate))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // 更新按钮
                    Button(action: { updateData() }) {
                        HStack(spacing: 6) {
                            if isUpdating {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .medium))
                            }

                            Text(isUpdating ? LocalizedString.data("updating", lang: settings.language) : LocalizedString.data("update_data", lang: settings.language))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isUpdating ? Color.gray : Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdating)
                }
                .padding(12)

                // 更新结果消息
                if let message = updateMessage {
                    HStack(spacing: 6) {
                        Image(systemName: updateSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(updateSuccess ? .green : .red)

                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(updateSuccess ? .green : .red)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                // 说明文字
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(LocalizedString.data("data_note", lang: settings.language)):")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(LocalizedString.data("data_note_content", lang: settings.language))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func updateData() {
        isUpdating = true
        updateMessage = nil

        Task {
            do {
                try await holidayService.updateHolidayData()

                await MainActor.run {
                    isUpdating = false
                    updateSuccess = true
                    updateMessage = LocalizedString.data("update_success", lang: settings.language)
                    Analytics.capture(.holidayDataUpdated, properties: [
                        "success": true,
                    ])

                    // 3秒后清除消息
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        updateMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isUpdating = false
                    updateSuccess = false
                    updateMessage = "\(LocalizedString.data("update_failed", lang: settings.language)): \(error.localizedDescription)"
                    Analytics.capture(.holidayDataUpdated, properties: [
                        "success": false,
                        "error_type": String(describing: type(of: error)),
                    ])

                    // 5秒后清除消息
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        updateMessage = nil
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 语言行

struct LanguageRow: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(languageFlag)
                    .font(.system(size: 18))

                Text(language.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var languageFlag: String {
        switch language {
        case .chinese: return "🇨🇳"
        case .english: return "🇺🇸"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        }
    }
}

// MARK: - 监控开关行

struct MonitorToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Color.accentColor)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - 菜单栏显示行

struct MenuBarDisplayRow: View {
    let mode: MenuBarDisplayMode
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName(lang: settings.language))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .truncationMode(.tail)

                    Text(modeDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 18)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var modeDescription: String {
        switch mode {
        case .goldPrice:
            return LocalizedString.menuBar("gold_price", lang: settings.language)
        case .date:
            return LocalizedString.menuBar("date", lang: settings.language)
        case .cpu:
            return LocalizedString.l(settings.language, en: "Live processor utilization", zh: "实时显示处理器占用率", ja: "プロセッサ使用率をリアルタイム表示", ko: "실시간 프로세서 사용률")
        case .memory:
            return LocalizedString.l(settings.language, en: "Live memory utilization", zh: "实时显示内存占用率", ja: "メモリ使用率をリアルタイム表示", ko: "실시간 메모리 사용률")
        case .network:
            return LocalizedString.l(settings.language, en: "Live download and upload speed", zh: "实时显示下载和上传速度", ja: "ダウンロードとアップロード速度をリアルタイム表示", ko: "실시간 다운로드 및 업로드 속도")
        case .english:
            return LocalizedString.l(settings.language, en: "Current word or spoken sentence", zh: "显示当前单词或正在朗读的句子", ja: "現在の単語または読み上げ中の文を表示", ko: "현재 단어나 읽는 문장 표시")
        case .codex:
            return LocalizedString.l(settings.language, en: "Codex quota remaining", zh: "显示 Codex 剩余额度", ja: "Codex の残り使用量を表示", ko: "Codex 잔여 사용량 표시")
        case .claude:
            return LocalizedString.l(settings.language, en: "Claude Code quota remaining", zh: "显示 Claude 剩余额度", ja: "Claude の残り使用量を表示", ko: "Claude 잔여 사용량 표시")
        case .countdown:
            return LocalizedString.l(settings.language, en: "Nearest countdown event", zh: "显示最近的倒数日", ja: "直近のカウントダウンを表示", ko: "가장 가까운 카운트다운 표시")
        }
    }
}

// MARK: - Components

struct SettingsRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct LinkRow: View {
    let icon: String
    let label: String
    let url: URL

    @Environment(\.openURL) private var openURL
    @State private var isHovering = false

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .cursor(.pointingHand)
    }
}

// MARK: - Cursor Modifier

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Data

enum AppLinks {
    static let repository = URL(string: "https://github.com/kuaoaoaoao/CoolRun")!
    static let releases = URL(string: "https://github.com/kuaoaoaoao/CoolRun/releases")!
    static let privacy = URL(string: "https://github.com/kuaoaoaoao/CoolRun/blob/main/PRIVACY.md")!
    static let issues = URL(string: "https://github.com/kuaoaoaoao/CoolRun/issues/new/choose")!
    static let feedbackEmail = "feedback@coolrun.app"
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
