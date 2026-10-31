import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 提醒设置

extension SettingsView {
    var remindersContent: some View {
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

    func reminderToggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
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

    func hourPicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour)
            }
        }
        .labelsHidden()
        .frame(width: 92)
    }

    var hasAnyLocalReminderEnabled: Bool {
        settings.countdownRemindersEnabled || settings.birthdayRemindersEnabled ||
            settings.englishRemindersEnabled || settings.systemAnomalyRemindersEnabled
    }

    func rescheduleLocalReminders() {
        Task { await reminderCenter.rescheduleAll() }
    }
}
