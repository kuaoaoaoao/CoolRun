import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 设置分类

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "general"
    case monitors = "monitors"
    case reminders = "reminders"
    case menubar = "menubar"
    case english = "english"
    case data = "data"
    case about = "about"

    var id: String { rawValue }

    func displayName(lang: AppLanguage) -> String {
        switch self {
        case .general: return LocalizedString.l(lang, en: "General", zh: "通用", ja: "一般", ko: "일반")
        case .monitors: return LocalizedString.l(lang, en: "Monitors", zh: "监控", ja: "監視", ko: "모니터")
        case .reminders: return LocalizedString.l(lang, en: "Reminders", zh: "提醒", ja: "通知", ko: "알림")
        case .menubar: return LocalizedString.l(lang, en: "Menu Bar", zh: "菜单栏", ja: "メニュー", ko: "메뉴 막대")
        case .english: return LocalizedString.l(lang, en: "English", zh: "英语", ja: "英語", ko: "영어")
        case .data: return LocalizedString.l(lang, en: "Data", zh: "数据", ja: "データ", ko: "데이터")
        case .about: return LocalizedString.l(lang, en: "About", zh: "关于", ja: "情報", ko: "정보")
        }
    }

    func subtitle(lang: AppLanguage) -> String {
        switch self {
        case .general:
            return LocalizedString.l(lang, en: "Language, startup and privacy", zh: "语言、启动与隐私", ja: "言語、起動、プライバシー", ko: "언어, 시작 및 개인정보")
        case .monitors:
            return LocalizedString.l(lang, en: "Choose metrics and sampling speed", zh: "选择指标与采样速度", ja: "指標とサンプリング速度", ko: "지표 및 샘플링 속도")
        case .reminders:
            return LocalizedString.l(lang, en: "Dates, study and system attention", zh: "日期、学习与系统异常提醒", ja: "日付、学習、システム通知", ko: "날짜, 학습 및 시스템 알림")
        case .menubar:
            return LocalizedString.l(lang, en: "Control the menu bar at a glance", zh: "控制菜单栏的显示方式", ja: "メニューバーの表示を管理", ko: "메뉴 막대 표시 관리")
        case .english:
            return LocalizedString.l(lang, en: "Voice, content and study goals", zh: "语音、内容与学习目标", ja: "音声、教材、学習目標", ko: "음성, 콘텐츠 및 학습 목표")
        case .data:
            return LocalizedString.l(lang, en: "Backup, restore and updates", zh: "备份、恢复与更新", ja: "バックアップ、復元、更新", ko: "백업, 복원 및 업데이트")
        case .about:
            return LocalizedString.l(lang, en: "Version and project information", zh: "版本与项目信息", ja: "バージョンとプロジェクト情報", ko: "버전 및 프로젝트 정보")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .monitors: return "chart.bar.fill"
        case .reminders: return "bell.badge.fill"
        case .menubar: return "menubar.rectangle"
        case .english: return "character.book.closed"
        case .data: return "icloud.and.arrow.down"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var textbookStore = EnglishTextbookStore.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    @ObservedObject private var reminderCenter = LocalReminderCenter.shared
    @State private var selectedCategory: SettingsCategory = .general
    // 系统通知权限被拒时在到价提醒开关下提示，避免用户以为开了就能收到
    @State private var notificationPermissionDenied = false
    @AppStorage(ClipboardQuickPasteController.enabledDefaultsKey) private var quickPasteEnabled = false
    @State private var quickPasteAccessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            VStack(spacing: 0) {
                contentHeader

                Divider()

                ScrollView {
                    VStack(spacing: 14) {
                        switch selectedCategory {
                        case .general:
                            generalContent
                        case .monitors:
                            monitorsContent
                        case .reminders:
                            remindersContent
                        case .menubar:
                            menubarContent
                        case .english:
                            englishContent
                        case .data:
                            dataContent
                        case .about:
                            aboutContent
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
            }
        }
        .frame(width: 720, height: 560)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                AppTheme.canvas(colorScheme)
            }
        }
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 5, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CoolRun")
                        .font(.headline)
                    Text("v\(AppVersion.current.displayText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(spacing: 4) {
                ForEach(SettingsCategory.allCases) { category in
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: category.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 20)

                            Text(category.displayName(lang: settings.language))
                                .font(.subheadline.weight(selectedCategory == category ? .semibold : .regular))

                            Spacer()
                        }
                        .foregroundStyle(
                            selectedCategory == category
                                ? AppTheme.accent
                                : AppTheme.textSecondary(colorScheme)
                        )
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background {
                            if selectedCategory == category {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.accent.opacity(colorScheme == .dark ? 0.20 : 0.12))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.displayName(lang: settings.language))
                    .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                }
            }

            Spacer()

            Text(LocalizedString.l(
                settings.language,
                en: "Menu bar toolkit",
                zh: "菜单栏效率工具箱",
                ja: "メニューバーツールキット",
                ko: "메뉴 막대 도구 모음"
            ))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 184)
        .background(AppTheme.chromeSurface(colorScheme))
    }

    private var contentHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedCategory.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(colorScheme == .dark ? 0.19 : 0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCategory.displayName(lang: settings.language))
                    .font(.title3.weight(.semibold))
                Text(selectedCategory.subtitle(lang: settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 68)
    }

    // MARK: - 通用设置内容

    private var generalContent: some View {
        VStack(spacing: 16) {
            // 语言选择
            SettingsCard(
                icon: "globe",
                title: LocalizedString.settings("language"),
                description: LocalizedString.settings("language_desc")
            ) {
                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases) { language in
                        LanguageRow(
                            language: language,
                            isSelected: settings.language == language
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.language = language
                            }
                            Analytics.capture(.languageChanged, properties: [
                                "language": language.rawValue,
                            ])
                        }

                        if language != AppLanguage.allCases.last {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }

            SettingsCard(
                icon: "power",
                title: LocalizedString.settings("startup"),
                description: LocalizedString.settings("startup_desc")
            ) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(LocalizedString.settings("launch_at_login"))
                            .font(.system(size: 13))

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    if let statusMessage = launchAtLogin.statusMessage {
                        Divider().padding(.horizontal, 14)
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
            }

            SettingsCard(
                icon: "doc.on.clipboard.fill",
                title: LocalizedString.settings("clipboard_quick_paste"),
                description: LocalizedString.settings("clipboard_quick_paste_desc")
            ) {
                VStack(spacing: 0) {
                    MonitorToggleRow(
                        icon: "keyboard",
                        title: LocalizedString.settings("quick_paste_toggle"),
                        isOn: $quickPasteEnabled
                    )
                    Divider().padding(.horizontal, 14)
                    Text(LocalizedString.settings("quick_paste_note"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                    if quickPasteEnabled {
                        let conflicts = ClipboardQuickPasteController.shared.conflictedSlots
                        if !conflicts.isEmpty {
                            let combos = conflicts
                                .sorted()
                                .map { "⌃⌘\($0 + 1)" }
                                .joined(separator: ", ")
                            Divider().padding(.horizontal, 14)
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppTheme.warning)
                                    .frame(width: 20)
                                Text("\(LocalizedString.settings("quick_paste_conflict")) \(combos)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.warning)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }

                    if !quickPasteAccessibilityGranted {
                        Divider().padding(.horizontal, 14)
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.warning)
                                .frame(width: 20)
                            Text(LocalizedString.settings("quick_paste_accessibility"))
                                .font(.system(size: 12))
                            Spacer()
                            Button(LocalizedString.settings("quick_paste_grant")) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    openURL(url)
                                }
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
            }

            SettingsCard(
                icon: "hand.raised.fill",
                title: LocalizedString.settings("privacy"),
                description: LocalizedString.settings("privacy_desc")
            ) {
                VStack(spacing: 0) {
                    MonitorToggleRow(
                        icon: "chart.bar.xaxis",
                        title: LocalizedString.settings("share_analytics"),
                        isOn: $settings.analyticsEnabled
                    )
                    .disabled(!Analytics.isConfigured)
                    Divider().padding(.horizontal, 14)
                    Text(LocalizedString.settings(
                        Analytics.isConfigured ? "privacy_note" : "analytics_unavailable"
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(Analytics.isConfigured ? Color.secondary : AppTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            launchAtLogin.refresh()
            quickPasteAccessibilityGranted = AXIsProcessTrusted()
        }
        // 从系统设置授权回来后刷新权限状态，否则警告行不会消失
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            quickPasteAccessibilityGranted = AXIsProcessTrusted()
        }
    }

    // MARK: - 监控设置内容

    private var monitorsContent: some View {
        VStack(spacing: 16) {
            SettingsCard(
                icon: "chart.bar.fill",
                title: LocalizedString.settings("monitor_modules"),
                description: LocalizedString.settings("monitor_modules_desc")
            ) {
                VStack(spacing: 0) {
                    MonitorToggleRow(
                        icon: "cpu",
                        title: LocalizedString.monitor("cpu"),
                        isOn: $settings.showCPU
                    )
                    Divider().padding(.horizontal, 14)

                    MonitorToggleRow(
                        icon: "memorychip",
                        title: LocalizedString.monitor("memory"),
                        isOn: $settings.showMemory
                    )
                    Divider().padding(.horizontal, 14)

                    MonitorToggleRow(
                        icon: "externaldrive",
                        title: LocalizedString.monitor("storage"),
                        isOn: $settings.showStorage
                    )
                    Divider().padding(.horizontal, 14)

                    MonitorToggleRow(
                        icon: "battery.100",
                        title: LocalizedString.monitor("battery"),
                        isOn: $settings.showBattery
                    )
                    Divider().padding(.horizontal, 14)

                    MonitorToggleRow(
                        icon: "network",
                        title: LocalizedString.monitor("network"),
                        isOn: $settings.showNetwork
                    )
                    Divider().padding(.horizontal, 14)

                    MonitorToggleRow(
                        icon: "clock",
                        title: LocalizedString.monitor("uptime"),
                        isOn: $settings.showUptime
                    )
                    Divider().padding(.horizontal, 14)

                    MonitorToggleRow(
                        icon: "thermometer",
                        title: LocalizedString.monitor("temperature"),
                        isOn: $settings.showTemperature
                    )
                    Divider().padding(.horizontal, 14)

                    MonitorToggleRow(
                        icon: "list.bullet.rectangle",
                        title: LocalizedString.monitor("processes"),
                        isOn: $settings.showProcesses
                    )

                    if settings.showProcesses {
                        Divider().padding(.horizontal, 14)

                        MonitorToggleRow(
                            icon: "square.3.layers.3d",
                            title: LocalizedString.monitor("merge_processes"),
                            isOn: $settings.mergeProcesses
                        )
                    }
                }
            }

            SettingsCard(
                icon: "gauge.with.dots.needle.50percent",
                title: LocalizedString.settings("refresh_rate"),
                description: LocalizedString.settings("refresh_rate_desc")
            ) {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(LocalizedString.settings("system_sampling"))
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $settings.systemRefreshRate) {
                        ForEach(SystemRefreshRate.allCases) { rate in
                            Text(rate.displayName(lang: settings.language)).tag(rate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            SettingsCard(
                icon: "bell.badge.fill",
                title: LocalizedString.settings("ai_quota_alerts"),
                description: LocalizedString.settings("ai_quota_alerts_desc")
            ) {
                VStack(spacing: 0) {
                    MonitorToggleRow(
                        icon: "sparkles",
                        title: LocalizedString.settings("ai_quota_alerts"),
                        isOn: $settings.aiQuotaAlertEnabled
                    )
                    .onChange(of: settings.aiQuotaAlertEnabled) { _, enabled in
                        if enabled {
                            QuotaAlertManager.shared.requestAuthorizationIfNeeded {
                                refreshNotificationPermission()
                            }
                        }
                    }
                    .onAppear { refreshNotificationPermission() }

                    if settings.aiQuotaAlertEnabled && notificationPermissionDenied {
                        Divider().padding(.horizontal, 14)
                        Label(
                            LocalizedString.settings("notification_permission_denied"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }

                    Divider().padding(.horizontal, 14)
                    Text(LocalizedString.settings("ai_quota_alerts_note"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - 本地提醒设置

    private var remindersContent: some View {
        VStack(spacing: 16) {
            SettingsCard(
                icon: "bell.badge.fill",
                title: LocalizedString.l(settings.language, en: "Reminder categories", zh: "提醒类别", ja: "通知カテゴリ", ko: "알림 종류"),
                description: LocalizedString.l(settings.language, en: "Enable only what you want to be interrupted for", zh: "只开启真正需要打断你的提醒", ja: "必要な通知だけを有効にします", ko: "필요한 알림만 켜세요")
            ) {
                VStack(spacing: 0) {
                    reminderToggleRow(
                        icon: "hourglass",
                        title: LocalizedString.l(settings.language, en: "Countdowns", zh: "倒数日", ja: "カウントダウン", ko: "카운트다운"),
                        isOn: $settings.countdownRemindersEnabled
                    )
                    Divider().padding(.horizontal, 14)
                    reminderToggleRow(
                        icon: "gift.fill",
                        title: LocalizedString.l(settings.language, en: "Birthdays", zh: "生日", ja: "誕生日", ko: "생일"),
                        isOn: $settings.birthdayRemindersEnabled
                    )
                    Divider().padding(.horizontal, 14)
                    reminderToggleRow(
                        icon: "character.book.closed.fill",
                        title: LocalizedString.l(settings.language, en: "English check-in", zh: "英语打卡", ja: "英語チェックイン", ko: "영어 학습"),
                        isOn: $settings.englishRemindersEnabled
                    )
                    Divider().padding(.horizontal, 14)
                    reminderToggleRow(
                        icon: "exclamationmark.triangle.fill",
                        title: LocalizedString.l(settings.language, en: "Sustained system anomalies", zh: "持续系统异常", ja: "継続するシステム異常", ko: "지속 시스템 이상"),
                        isOn: $settings.systemAnomalyRemindersEnabled
                    )

                    if notificationPermissionDenied && hasAnyLocalReminderEnabled {
                        Divider().padding(.horizontal, 14)
                        Label(LocalizedString.settings("notification_permission_denied"), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                }
            }

            SettingsCard(
                icon: "calendar.badge.clock",
                title: LocalizedString.l(settings.language, en: "Timing", zh: "提醒时间", ja: "通知時刻", ko: "알림 시간"),
                description: LocalizedString.l(settings.language, en: "Shared schedule for date and study reminders", zh: "日期和学习提醒共用此时间设置", ja: "日付と学習通知の共通設定", ko: "날짜 및 학습 알림 공통 설정")
            ) {
                VStack(spacing: 0) {
                    settingsPickerRow(icon: "calendar.badge.minus", title: LocalizedString.l(settings.language, en: "Remind before", zh: "提前提醒", ja: "事前通知", ko: "미리 알림")) {
                        Picker("", selection: $settings.reminderDaysBefore) {
                            ForEach([0, 1, 3, 7], id: \.self) { days in
                                Text(days == 0
                                    ? LocalizedString.l(settings.language, en: "Same day", zh: "当天", ja: "当日", ko: "당일")
                                    : LocalizedString.l(settings.language, en: "\(days) days", zh: "\(days) 天", ja: "\(days)日前", ko: "\(days)일 전"))
                                    .tag(days)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    Divider().padding(.horizontal, 14)
                    settingsPickerRow(icon: "clock", title: LocalizedString.l(settings.language, en: "Delivery time", zh: "送达时间", ja: "通知時刻", ko: "알림 시간")) {
                        Picker("", selection: $settings.reminderHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    Divider().padding(.horizontal, 14)
                    settingsPickerRow(icon: "timer", title: LocalizedString.l(settings.language, en: "Snooze", zh: "稍后提醒", ja: "再通知", ko: "다시 알림")) {
                        Picker("", selection: $settings.reminderSnoozeMinutes) {
                            ForEach([10, 30, 60], id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                }
                .onChange(of: settings.reminderDaysBefore) { _, _ in rescheduleLocalReminders() }
                .onChange(of: settings.reminderHour) { _, _ in rescheduleLocalReminders() }
            }

            SettingsCard(
                icon: "moon.zzz.fill",
                title: LocalizedString.l(settings.language, en: "Quiet hours", zh: "免打扰时段", ja: "静かな時間", ko: "방해 금지 시간"),
                description: LocalizedString.l(settings.language, en: "Noncritical reminders wait until quiet hours end", zh: "非紧急提醒会等免打扰结束后送达", ja: "緊急でない通知は終了後に届きます", ko: "긴급하지 않은 알림은 종료 후 전달됩니다")
            ) {
                VStack(spacing: 0) {
                    MonitorToggleRow(
                        icon: "moon.fill",
                        title: LocalizedString.l(settings.language, en: "Enable quiet hours", zh: "开启免打扰", ja: "静かな時間を有効化", ko: "방해 금지 켜기"),
                        isOn: $settings.reminderQuietHoursEnabled
                    )
                    if settings.reminderQuietHoursEnabled {
                        Divider().padding(.horizontal, 14)
                        HStack(spacing: 8) {
                            Text(LocalizedString.l(settings.language, en: "From", zh: "从", ja: "開始", ko: "시작"))
                                .font(.system(size: 12))
                            hourPicker(selection: $settings.reminderQuietStartHour)
                            Text(LocalizedString.l(settings.language, en: "to", zh: "到", ja: "終了", ko: "종료"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            hourPicker(selection: $settings.reminderQuietEndHour)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .onChange(of: settings.reminderQuietHoursEnabled) { _, _ in rescheduleLocalReminders() }
                .onChange(of: settings.reminderQuietStartHour) { _, _ in rescheduleLocalReminders() }
                .onChange(of: settings.reminderQuietEndHour) { _, _ in rescheduleLocalReminders() }
            }
        }
        .onAppear {
            reminderCenter.refreshAuthorizationStatus {
                refreshNotificationPermission()
            }
        }
    }

    private func reminderToggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        MonitorToggleRow(icon: icon, title: title, isOn: isOn)
            .onChange(of: isOn.wrappedValue) { _, enabled in
                if enabled {
                    reminderCenter.requestAuthorizationIfNeeded {
                        refreshNotificationPermission()
                        rescheduleLocalReminders()
                    }
                } else {
                    rescheduleLocalReminders()
                }
            }
    }

    private func hourPicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour)
            }
        }
        .labelsHidden()
        .frame(width: 92)
    }

    private var hasAnyLocalReminderEnabled: Bool {
        settings.countdownRemindersEnabled || settings.birthdayRemindersEnabled ||
            settings.englishRemindersEnabled || settings.systemAnomalyRemindersEnabled
    }

    private func rescheduleLocalReminders() {
        Task { await reminderCenter.rescheduleAll() }
    }

    // MARK: - 菜单栏设置内容

    private var menubarContent: some View {
        VStack(spacing: 16) {
            SettingsCard(
                icon: "menubar.rectangle",
                title: LocalizedString.settings("menu_bar_display"),
                description: LocalizedString.settings("menu_bar_display_desc")
            ) {
                VStack(spacing: 0) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        MenuBarDisplayRow(
                            mode: mode,
                            isSelected: settings.menuBarDisplayMode == mode
                        ) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                settings.menuBarDisplayMode = mode
                            }
                            Analytics.capture(.menuBarDisplayModeChanged, properties: [
                                "mode": mode.rawValue,
                            ])
                        }

                        if mode != MenuBarDisplayMode.allCases.last {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }

            SettingsCard(
                icon: "rectangle.2.swap",
                title: LocalizedString.l(settings.language, en: "Menu bar composition", zh: "菜单栏组合", ja: "メニューバー構成", ko: "메뉴 막대 구성"),
                description: LocalizedString.l(settings.language, en: "Show one value, a compact pair, or rotate two values", zh: "显示单项、双项紧凑组合，或定时轮播", ja: "単一、2項目、切り替え表示", ko: "단일, 압축 2개 또는 순환 표시")
            ) {
                VStack(spacing: 0) {
                    settingsPickerRow(
                        icon: "rectangle.2.swap",
                        title: LocalizedString.l(settings.language, en: "Layout", zh: "显示方式", ja: "表示方法", ko: "표시 방식")
                    ) {
                        Picker("", selection: $settings.menuBarCompositionStyle) {
                            ForEach(MenuBarCompositionStyle.allCases) { style in
                                Text(style.displayName(lang: settings.language)).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    if settings.menuBarCompositionStyle != .single {
                        Divider().padding(.horizontal, 14)
                        settingsPickerRow(
                            icon: "plus.rectangle.on.rectangle",
                            title: LocalizedString.l(settings.language, en: "Second value", zh: "第二项", ja: "2番目の項目", ko: "두 번째 항목")
                        ) {
                            Picker("", selection: $settings.menuBarSecondaryDisplayMode) {
                                ForEach(MenuBarDisplayMode.allCases.filter { $0 != settings.menuBarDisplayMode }) { mode in
                                    Text(mode.displayName(lang: settings.language)).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }

                    if settings.menuBarCompositionStyle == .rotation {
                        Divider().padding(.horizontal, 14)
                        settingsPickerRow(
                            icon: "timer",
                            title: LocalizedString.l(settings.language, en: "Switch every", zh: "切换间隔", ja: "切り替え間隔", ko: "전환 간격")
                        ) {
                            Picker("", selection: $settings.menuBarRotationSeconds) {
                                ForEach([5, 10, 15, 30], id: \.self) { seconds in
                                    Text("\(seconds)s").tag(seconds)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                    }
                }
            }

            SettingsCard(
                icon: "sparkles",
                title: LocalizedString.settings("menubar_animation"),
                description: LocalizedString.settings("menubar_animation_desc")
            ) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedString.settings("show_coin_icon"))
                                .font(.system(size: 13))
                            Text(LocalizedString.settings("show_coin_icon_note"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.showMenuBarCoinIcon)
                            .labelsHidden()
                    }

                    if settings.showMenuBarCoinIcon {
                        Divider().padding(.leading, 44)

                        HStack(spacing: 10) {
                            Image(systemName: "circle.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(LocalizedString.settings("coin_appearance"))
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $settings.menuBarCoinAppearance) {
                                ForEach(MenuBarCoinAppearance.allCases) { appearance in
                                    Text(appearance.displayName(lang: settings.language)).tag(appearance)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 164)
                        }

                        Divider().padding(.leading, 44)

                        HStack(spacing: 10) {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(LocalizedString.settings("coin_motion"))
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $settings.menuBarCoinMotion) {
                                ForEach(MenuBarCoinMotion.allCases) { motion in
                                    Text(motion.displayName(lang: settings.language)).tag(motion)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 164)
                        }

                        Divider().padding(.leading, 44)

                        HStack(spacing: 10) {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(LocalizedString.settings("animation_rate"))
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $settings.menuBarAnimationRate) {
                                ForEach(MenuBarAnimationRate.allCases) { rate in
                                    Text(rate.displayName(lang: settings.language)).tag(rate)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 164)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            SettingsCard(
                icon: "arrow.triangle.2.circlepath",
                title: LocalizedString.settings("gold_data_alerts"),
                description: LocalizedString.settings("gold_data_alerts_desc")
            ) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(LocalizedString.settings("refresh_every"))
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $settings.goldRefreshRate) {
                            ForEach(GoldRefreshRate.allCases) { rate in
                                Text(rate.displayName(lang: settings.language)).tag(rate)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Divider().padding(.horizontal, 14)

                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(LocalizedString.settings("gold_auto_calibration"))
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $settings.goldAutoCalibrationEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Text(LocalizedString.settings("gold_auto_calibration_note"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)

                    Divider().padding(.horizontal, 14)

                    HStack(spacing: 10) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(LocalizedString.settings("gold_alert"))
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $settings.goldAlertEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: settings.goldAlertEnabled) { _, enabled in
                                if enabled {
                                    // 等授权弹窗有结果后再查权限，当场拒绝也能立即显示提示
                                    GoldPriceAlertManager.shared.requestAuthorizationIfNeeded {
                                        refreshNotificationPermission()
                                    }
                                }
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .onAppear { refreshNotificationPermission() }

                    if settings.goldAlertEnabled {
                        // 通知权限被拒时提示，否则提醒开了也收不到
                        if notificationPermissionDenied {
                            Label(LocalizedString.settings("notification_permission_denied"), systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 2)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.to.line")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(LocalizedString.settings("gold_alert_upper"))
                                .font(.system(size: 13))
                            Spacer()
                            TextField("--", text: $settings.goldAlertUpperText)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)

                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.to.line")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(LocalizedString.settings("gold_alert_lower"))
                                .font(.system(size: 13))
                            Spacer()
                            TextField("--", text: $settings.goldAlertLowerText)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)

                        // 阈值非法/上下限倒挂时即时提示，不等保存时静默失败
                        if let hint = goldAlertValidationHint {
                            Text(hint)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.red)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 4)
                        }

                        Text(LocalizedString.settings("gold_alert_note"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    // 查询系统通知授权状态，被拒时在设置页显示提示行
    private func refreshNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { notifSettings in
            let denied = notifSettings.authorizationStatus == .denied
            DispatchQueue.main.async {
                notificationPermissionDenied = denied
            }
        }
    }

    // 到价提醒阈值校验：非法输入或上下限倒挂时返回提示文案
    private var goldAlertValidationHint: String? {
        let upperText = settings.goldAlertUpperText.trimmingCharacters(in: .whitespaces)
        let lowerText = settings.goldAlertLowerText.trimmingCharacters(in: .whitespaces)
        let upper = Double(upperText)
        let lower = Double(lowerText)
        if (!upperText.isEmpty && (upper == nil || upper! <= 0)) ||
            (!lowerText.isEmpty && (lower == nil || lower! <= 0)) {
            return LocalizedString.settings("gold_alert_invalid")
        }
        if let upper, let lower, upper <= lower {
            return LocalizedString.settings("gold_alert_inverted")
        }
        return nil
    }

    // MARK: - 英语学习设置内容

    private var englishContent: some View {
        VStack(spacing: 16) {
            SettingsCard(
                icon: "speaker.wave.2.fill",
                title: LocalizedString.settings("english_voice"),
                description: LocalizedString.settings("english_voice_desc")
            ) {
                VStack(spacing: 0) {
                    settingsPickerRow(icon: "waveform", title: LocalizedString.english("tts_engine")) {
                        Picker("", selection: $settings.englishTTSBackend) {
                            ForEach(EnglishTTSBackend.allCases) { backend in
                                Text(backend.title).tag(backend)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    if settings.englishTTSBackend == .kokoro {
                        Divider().padding(.horizontal, 14)
                        settingsTextFieldRow(
                            icon: "terminal",
                            title: LocalizedString.settings("kokoro_command"),
                            text: $settings.englishKokoroCommandPath,
                            placeholder: "/usr/local/bin/kokoro-tts"
                        )
                        Divider().padding(.horizontal, 14)
                        settingsTextFieldRow(
                            icon: "person.crop.circle.badge.waveform",
                            title: LocalizedString.settings("kokoro_voice"),
                            text: $settings.englishKokoroVoice,
                            placeholder: KokoroEnglishSpeechProvider.defaultVoice
                        )
                    }

                    Divider().padding(.horizontal, 14)

                    settingsPickerRow(icon: "books.vertical.fill", title: LocalizedString.english("learning_stage")) {
                        Picker("", selection: Binding(
                            get: { textbookStore.selectedTextbook.stage },
                            set: { textbookStore.selectBuiltin(stage: $0) }
                        )) {
                            ForEach(EnglishStage.allCases) { stage in
                                Text(stage.title).tag(stage)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    Text(textbookStore.selectedTextbook.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.top, -4)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().padding(.horizontal, 14)

                    settingsPickerRow(icon: "globe.americas.fill", title: LocalizedString.english("accent")) {
                        Picker("", selection: $settings.englishAccent) {
                            ForEach(EnglishAccent.allCases) { accent in
                                Text(accent.title).tag(accent)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .onChange(of: settings.englishAccent) { _, _ in
                            settings.englishVoiceIdentifier = ""
                        }
                    }

                    Divider().padding(.horizontal, 14)

                    settingsPickerRow(icon: "person.wave.2.fill", title: LocalizedString.english("voice_select")) {
                        Picker("", selection: $settings.englishVoiceIdentifier) {
                            Text(LocalizedString.english("auto_best_voice")).tag("")
                            ForEach(englishVoices, id: \.identifier) { voice in
                                Text(voiceDisplayName(voice)).tag(voice.identifier)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 185)
                    }

                    Divider().padding(.horizontal, 14)

                    voiceQualityHintRow

                    Divider().padding(.horizontal, 14)
                    englishSliderRow(title: LocalizedString.english("normal_rate"), value: $settings.englishNormalRate, range: 0.25...0.60)
                    Divider().padding(.horizontal, 14)
                    englishSliderRow(title: LocalizedString.english("slow_rate"), value: $settings.englishSlowRate, range: 0.15...0.45)
                    Divider().padding(.horizontal, 14)
                    englishSliderRow(title: LocalizedString.english("volume"), value: $settings.englishVolume, range: 0.1...1.0)
                }
            }

            SettingsCard(
                icon: "repeat",
                title: LocalizedString.settings("continuous_learning"),
                description: LocalizedString.settings("continuous_learning_desc")
            ) {
                VStack(spacing: 0) {
                    settingsPickerRow(icon: "repeat.1", title: LocalizedString.english("repeat_count")) {
                        Picker("", selection: $settings.englishRepeatCount) {
                            ForEach(1...3, id: \.self) { count in
                                Text("\(count) \(LocalizedString.english("times"))").tag(count)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    Divider().padding(.horizontal, 14)
                    settingsPickerRow(icon: "timer", title: LocalizedString.english("interval")) {
                        Picker("", selection: $settings.englishItemInterval) {
                            ForEach([3.0, 5.0, 7.0, 10.0, 15.0], id: \.self) { seconds in
                                Text("\(Int(seconds)) \(LocalizedString.english("seconds"))").tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    Divider().padding(.horizontal, 14)
                    settingsPickerRow(icon: "menubar.rectangle", title: LocalizedString.english("menu_text")) {
                        Picker("", selection: $settings.englishMenuTextStyle) {
                            ForEach(EnglishMenuTextStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }
            }

            SettingsCard(
                icon: "target",
                title: LocalizedString.settings("learning_plan"),
                description: LocalizedString.settings("learning_plan_desc")
            ) {
                VStack(spacing: 0) {
                    settingsPickerRow(icon: "checklist", title: LocalizedString.english("daily_goal")) {
                        Picker("", selection: $settings.englishDailyTarget) {
                            ForEach([5, 10, 15, 20, 30], id: \.self) { target in
                                Text("\(target) \(LocalizedString.english("items"))").tag(target)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    Divider().padding(.horizontal, 14)
                    MonitorToggleRow(icon: "text.bubble", title: LocalizedString.english("show_translation"), isOn: $settings.englishShowTranslation)
                    Divider().padding(.horizontal, 14)
                    MonitorToggleRow(icon: "speaker.badge.exclamationmark", title: LocalizedString.english("speak_translation"), isOn: $settings.englishSpeakTranslation)
                }
            }
        }
    }

    private var englishVoices: [AVSpeechSynthesisVoice] {
        EnglishLearningManager.availableVoices(for: settings.englishAccent)
    }

    private func voiceDisplayName(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = " · Premium"
        case .enhanced: quality = " · Enhanced"
        default: quality = ""
        }
        return "\(voice.name)\(quality)"
    }

    private var voiceQualityHintRow: some View {
        let manager = EnglishLearningManager.shared
        let voice = manager.currentEnglishVoice
        let quality = EnglishLearningManager.qualityLabel(for: voice)
        let needsUpgrade = manager.needsHigherQualityEnglishVoice
        return HStack(spacing: 10) {
            Image(systemName: needsUpgrade ? "sparkles" : "checkmark.seal.fill")
                .foregroundStyle(needsUpgrade ? AppTheme.warning : AppTheme.healthy)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(needsUpgrade ? LocalizedString.english("download_better_voice") : LocalizedString.english("high_quality_on"))
                    .font(.system(size: 13))
                Text(needsUpgrade
                    ? LocalizedString.english("voice_current_quality") + "\(quality)" + LocalizedString.english("voice_guide_suffix")
                    : LocalizedString.english("voice_current_quality") + "\(quality)" + LocalizedString.english("voice_good_suffix"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                EnglishLearningManager.openSystemVoiceDownloadSettings()
            } label: {
                // 质量达标时文案改为"查看语音设置"，避免两分支同文案
                Text(needsUpgrade ? LocalizedString.english("go_download") : LocalizedString.english("view_voice_settings"))
                    .font(.system(size: 12))
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(needsUpgrade ? AppTheme.warning : AppTheme.healthy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func settingsPickerRow<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func settingsTextFieldRow(
        icon: String,
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 185)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func englishSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range, step: 0.01)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 数据管理内容

    private var dataContent: some View {
        VStack(spacing: 16) {
            // 数据备份与迁移
            DataBackupCard()

            // 应用更新检查
            UpdateCheckCard()

            // 节假日数据更新
            HolidayUpdateCard()
        }
    }

    // MARK: - 关于内容

    private var aboutContent: some View {
        VStack(spacing: 16) {
            // 应用信息
            VStack(spacing: 0) {
                SettingsRow(icon: "person.fill", label: LocalizedString.settings("author"), value: "kuaoaoaoao")
                Divider().padding(.horizontal, 12)
                SettingsRow(icon: "tag.fill", label: LocalizedString.settings("version"), value: AppVersion.current.displayText)
                Divider().padding(.horizontal, 12)
                SettingsRow(icon: "hammer.fill", label: "Swift", value: "SwiftUI + AppKit")
                Divider().padding(.horizontal, 12)
                SettingsRow(icon: "desktopcomputer", label: LocalizedString.settings("platform"), value: "macOS 15.0+")
            }
            .appCardSurface(cornerRadius: 12, showsShadow: false)

            // 链接
            VStack(spacing: 0) {
                LinkRow(
                    icon: "globe",
                    label: LocalizedString.settings("project_home"),
                    url: AppLinks.repository
                )
                Divider().padding(.horizontal, 12)
                LinkRow(
                    icon: "arrow.down.circle.fill",
                    label: LocalizedString.settings("check_update"),
                    url: AppLinks.releases
                )
                Divider().padding(.horizontal, 12)
                LinkRow(
                    icon: "hand.raised.fill",
                    label: LocalizedString.settings("privacy_policy"),
                    url: AppLinks.privacy
                )
                Divider().padding(.horizontal, 12)
                LinkRow(
                    icon: "ladybug.fill",
                    label: LocalizedString.settings("report_issue"),
                    url: AppLinks.issues
                )
            }
            .appCardSurface(cornerRadius: 12, showsShadow: false)
        }
    }
}

// MARK: - 设置卡片组件

private struct SettingsCard<Content: View>: View {
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

private struct DataBackupCard: View {
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

        switch settings.language {
        case .chinese:
            return "\(birthdayCount) 条生日 · \(countdownCount) 个倒数日 · \(englishCount) 条进度 · \(goldCount) 条金价"
        case .japanese:
            return "\(birthdayCount) 件の誕生日 · \(countdownCount) 件のカウントダウン · \(englishCount) 件の進捗 · \(goldCount) 件の価格"
        case .korean:
            return "\(birthdayCount) 생일 · \(countdownCount) 카운트다운 · \(englishCount) 학습 기록 · \(goldCount) 가격 기록"
        case .english:
            return "\(birthdayCount) birthdays · \(countdownCount) countdowns · \(englishCount) words · \(goldCount) prices"
        }
    }

    private func clearMessageAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            statusMessage = nil
        }
    }
}

// MARK: - 更新检查卡片

private struct UpdateCheckCard: View {
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

private struct HolidayUpdateCard: View {
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
        switch settings.language {
        case .chinese, .japanese:
            formatter.dateFormat = "yyyy年M月d日 HH:mm"
        case .korean:
            formatter.dateFormat = "yyyy년 M월 d일 HH:mm"
        case .english:
            formatter.dateFormat = "MMM d, yyyy HH:mm"
        }
        return formatter.string(from: date)
    }
}

// MARK: - 语言行

private struct LanguageRow: View {
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

private struct MonitorToggleRow: View {
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

private struct MenuBarDisplayRow: View {
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

private struct SettingsRow: View {
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

private struct LinkRow: View {
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

private enum AppLinks {
    static let repository = URL(string: "https://github.com/kuaoaoaoao/CoolRun")!
    static let releases = URL(string: "https://github.com/kuaoaoaoao/CoolRun/releases")!
    static let privacy = URL(string: "https://github.com/kuaoaoaoao/CoolRun/blob/main/PRIVACY.md")!
    static let issues = URL(string: "https://github.com/kuaoaoaoao/CoolRun/issues/new/choose")!
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
