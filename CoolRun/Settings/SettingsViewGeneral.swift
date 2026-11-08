import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 通用设置

extension SettingsView {
    var generalContent: some View {
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
                icon: "rectangle.split.3x1",
                title: LocalizedString.settings("panel_tabs"),
                description: LocalizedString.settings("panel_tabs_desc")
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                        MonitorToggleRow(
                            icon: mode.icon,
                            title: mode.displayName,
                            isOn: Binding(
                                get: { settings.isTabVisible(mode) },
                                set: { settings.setTabVisible(mode, $0) }
                            )
                        )
                        // 保底至少保留一个模块可见，最后一个是唯一可见时禁止关闭
                        .disabled(settings.isTabVisible(mode) && settings.visibleViewModes.count <= 1)

                        if index != ViewMode.allCases.count - 1 {
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

            DiagnosticsPatrolSettingsCard()

            MorningBriefSettingsCard()

            SettingsCard(
                icon: "fish.fill",
                title: "桌宠",
                description: "在桌面放一只鲸鱼娘。点一下逗她，双击打开 Agent，按住可以拖着走、甩出去她会飞一会儿。她在干活时会冒气泡告诉你进行到哪一步。"
            ) {
                VStack(spacing: 0) {
                    MonitorToggleRow(
                        icon: "fish.fill",
                        title: "显示桌宠",
                        isOn: $petEnabled
                    )
                    Divider().padding(.horizontal, 14)
                    HStack(spacing: 10) {
                        Text("大小")
                            .font(.system(size: 12))
                        Spacer(minLength: 8)
                        Picker("大小", selection: Binding(
                            get: { PetController.shared.scale },
                            set: { PetController.shared.setScale($0) }
                        )) {
                            Text("小").tag(CGFloat(0.8))
                            Text("中").tag(CGFloat(1.0))
                            Text("大").tag(CGFloat(1.25))
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 156)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: petEnabled) { _, enabled in
                    if enabled {
                        PetController.shared.show()
                    } else {
                        PetController.shared.hide()
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
}


// MARK: - 每日简报设置

struct MorningBriefSettingsCard: View {

    @State private var store = MorningBriefStore.shared
    @State private var time: Date

    init() {
        let store = MorningBriefStore.shared
        var components = DateComponents()
        components.hour = store.hour
        components.minute = store.minute
        let base = Calendar.current.date(from: components) ?? Date()
        _time = State(initialValue: base)
    }

    var body: some View {
        SettingsCard(
            icon: "sunrise.fill",
            title: "每日简报",
            description: "每天在指定时间提醒你看一眼今天的情况。简报本身离线生成，不联网也能用。"
        ) {
            VStack(spacing: 0) {
                MonitorToggleRow(
                    icon: "bell.badge.fill",
                    title: "每天提醒",
                    isOn: Binding(
                        get: { store.isEnabled },
                        set: { store.isEnabled = $0 }
                    )
                )

                if store.isEnabled {
                    Divider().opacity(0.4)

                    HStack {
                        Text("提醒时间")
                            .font(.system(size: 12))
                        Spacer()
                        DatePicker(
                            "",
                            selection: $time,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .frame(width: 92)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: time) { _, value in
                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                store.hour = components.hour ?? 8
                store.minute = components.minute ?? 30
            }
        }
    }
}

/// 后台体检的开关与最近一次结果。
struct DiagnosticsPatrolSettingsCard: View {

    @State private var patrol = DiagnosticsPatrol.shared

    var body: some View {
        SettingsCard(
            icon: "stethoscope",
            title: "后台体检",
            description: "每隔几小时自己看一眼磁盘、内存、睡眠和网络，真有问题才通知你，一天最多一条。"
        ) {
            VStack(spacing: 0) {
                MonitorToggleRow(
                    icon: "heart.text.square.fill",
                    title: "自动检查",
                    isOn: Binding(
                        get: { patrol.isEnabled },
                        set: { patrol.isEnabled = $0 }
                    )
                )

                if patrol.isEnabled {
                    Divider().opacity(0.4)

                    HStack(spacing: 8) {
                        Image(systemName: patrol.isRunning ? "arrow.triangle.2.circlepath" : "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("现在检查") {
                            Task { await patrol.runNow() }
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .disabled(patrol.isRunning)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var statusText: String {
        if patrol.isRunning { return "正在检查…" }
        guard let last = patrol.lastRunAt else { return "还没检查过" }
        let stamp = last.formatted(date: .omitted, time: .shortened)
        if let first = patrol.findings.first {
            return "\(stamp) 检查过 · \(first.title)"
        }
        return "\(stamp) 检查过 · 一切正常"
    }
}
