import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 菜单栏设置

extension SettingsView {
    var menubarContent: some View {
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
    func refreshNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { notifSettings in
            let denied = notifSettings.authorizationStatus == .denied
            DispatchQueue.main.async {
                notificationPermissionDenied = denied
            }
        }
    }

    // 到价提醒阈值校验：非法输入或上下限倒挂时返回提示文案
    var goldAlertValidationHint: String? {
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
}
