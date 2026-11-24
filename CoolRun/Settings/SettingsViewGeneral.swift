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
                icon: "magnifyingglass",
                title: LocalizedString.settings("quick_search"),
                description: LocalizedString.settings("quick_search_desc")
            ) {
                MonitorToggleRow(
                    icon: "command",
                    title: LocalizedString.settings("quick_search_toggle"),
                    isOn: $settings.quickSearchEnabled
                )
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
                title: LocalizedString.l(settings.language, en: "Pet", zh: "桌宠", ja: "ペット", ko: "펫"),
                description: LocalizedString.l(settings.language, en: "Puts a little whale girl on your desktop. Click to tease her, double-click to open Agent, hold and drag to move her, flick and she flies for a while. While she works, a bubble tells you which step she is on.", zh: "在桌面放一只鲸鱼娘。点一下逗她，双击打开 Agent，按住可以拖着走、甩出去她会飞一会儿。她在干活时会冒气泡告诉你进行到哪一步。", ja: "デスクトップに小さなクジラ娘を置きます。クリックでからかい、ダブルクリックで Agent を開き、長押しでドラッグして動かせます。投げるとしばらく飛びます。作業中は吹き出しで進行状況を知らせます。", ko: "바탕화면에 작은 고래 소녀를 띄웁니다. 클릭하면 간지럽히고, 더블클릭하면 Agent를 열고, 길게 누르면 끌어서 옮길 수 있습니다. 던지면 잠시 날아갑니다. 작업 중에는 말풍선으로 진행 상황을 알려줍니다."),
            ) {
                VStack(spacing: 0) {
                    MonitorToggleRow(
                        icon: "fish.fill",
                        title: LocalizedString.l(settings.language, en: "Show Pet", zh: "显示桌宠", ja: "ペットを表示", ko: "펫 표시"),
                        isOn: $petEnabled
                    )
                    Divider().padding(.horizontal, 14)
                    MonitorToggleRow(
                        icon: "wind",
                        title: LocalizedString.l(settings.language, en: "Play Animations", zh: "播放动效", ja: "アニメーションを再生", ko: "애니메이션 재생"),
                        isOn: Binding(
                            get: { PetController.shared.animates },
                            set: { PetController.shared.setAnimates($0) }
                        )
                    )
                    Divider().padding(.horizontal, 14)
                    MonitorToggleRow(
                        icon: "film",
                        title: LocalizedString.l(settings.language, en: "Frame-by-frame Animation", zh: "逐帧动画", ja: "フレームアニメーション", ko: "프레임 애니메이션"),
                        isOn: Binding(
                            get: { PetController.shared.videoEnabled },
                            set: { PetController.shared.setVideoEnabled($0) }
                        )
                    )
                    Divider().padding(.horizontal, 14)
                    MonitorToggleRow(
                        icon: "speaker.wave.2",
                        title: LocalizedString.l(settings.language, en: "Click Sound", zh: "点击音效", ja: "クリック音", ko: "클릭 소리"),
                        isOn: Binding(
                            get: { PetController.shared.soundEnabled },
                            set: { PetController.shared.setSoundEnabled($0) }
                        )
                    )
                    Divider().padding(.horizontal, 14)
                    HStack(spacing: 10) {
                        Text(LocalizedString.l(settings.language, en: "Size", zh: "大小", ja: "サイズ", ko: "크기"))
                            .font(.system(size: 12))
                        Spacer(minLength: 8)
                        Picker(LocalizedString.l(settings.language, en: "Size", zh: "大小", ja: "サイズ", ko: "크기"), selection: Binding(
                            get: { PetController.shared.scale },
                            set: { PetController.shared.setScale($0) }
                        )) {
                            Text(LocalizedString.l(settings.language, en: "Small", zh: "小", ja: "小", ko: "작게")).tag(CGFloat(0.8))
                            Text(LocalizedString.l(settings.language, en: "Medium", zh: "中", ja: "中", ko: "보통")).tag(CGFloat(1.0))
                            Text(LocalizedString.l(settings.language, en: "Large", zh: "大", ja: "大", ko: "크게")).tag(CGFloat(1.25))
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

    @ObservedObject private var settings = AppSettings.shared
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
            title: LocalizedString.l(settings.language, en: "Daily Brief", zh: "每日简报", ja: "デイリーブリーフ", ko: "데일리 브리프"),
            description: LocalizedString.l(settings.language, en: "Reminds you to look at your day at a set time. The brief is generated offline and works without a network.", zh: "每天在指定时间提醒你看一眼今天的情况。简报本身离线生成，不联网也能用。", ja: "指定した時刻に今日の状況を確認するよう通知します。ブリーフはオフラインで生成され、ネットワークなしでも使えます。", ko: "지정한 시간에 오늘의 상황을 확인하도록 알려줍니다. 브리프는 오프라인에서 생성되며 네트워크 없이도 사용할 수 있습니다."),
        ) {
            VStack(spacing: 0) {
                MonitorToggleRow(
                    icon: "bell.badge.fill",
                    title: LocalizedString.l(settings.language, en: "Daily Reminder", zh: "每天提醒", ja: "毎日リマインド", ko: "매일 알림"),
                    isOn: Binding(
                        get: { store.isEnabled },
                        set: { store.isEnabled = $0 }
                    )
                )

                if store.isEnabled {
                    Divider().opacity(0.4)

                    HStack {
                        Text(LocalizedString.l(settings.language, en: "Reminder Time", zh: "提醒时间", ja: "通知時刻", ko: "알림 시간"))
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

    @ObservedObject private var settings = AppSettings.shared
    @State private var patrol = DiagnosticsPatrol.shared

    var body: some View {
        SettingsCard(
            icon: "stethoscope",
            title: LocalizedString.l(settings.language, en: "Background Health Check", zh: "后台体检", ja: "バックグラウンド健診", ko: "백그라운드 점검"),
            description: LocalizedString.l(settings.language, en: "Every few hours it checks disk, memory, sleep and network on its own, and notifies you only when something is really wrong, at most once a day.", zh: "每隔几小时自己看一眼磁盘、内存、睡眠和网络，真有问题才通知你，一天最多一条。", ja: "数時間ごとにディスク、メモリ、スリープ、ネットワークを自動で確認し、本当に問題がある時だけ通知します（1日1回まで）。", ko: "몇 시간마다 디스크, 메모리, 잠자기, 네트워크를 스스로 점검하고 실제 문제가 있을 때만 알려줍니다. 하루 최대 한 번입니다."),
        ) {
            VStack(spacing: 0) {
                MonitorToggleRow(
                    icon: "heart.text.square.fill",
                    title: LocalizedString.l(settings.language, en: "Automatic Check", zh: "自动检查", ja: "自動チェック", ko: "자동 점검"),
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
                        Button(LocalizedString.l(settings.language, en: "Check Now", zh: "现在检查", ja: "今すぐ確認", ko: "지금 점검")) {
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
        let lang = settings.language
        if patrol.isRunning { return LocalizedString.l(lang, en: "Checking…", zh: "正在检查…", ja: "確認中…", ko: "확인 중…") }
        guard let last = patrol.lastRunAt else { return LocalizedString.l(lang, en: "Not checked yet", zh: "还没检查过", ja: "まだ確認していません", ko: "아직 점검한 적 없음") }
        let stamp = last.formatted(date: .omitted, time: .shortened)
        if let first = patrol.findings.first {
            return LocalizedString.l(lang, en: "Checked \(stamp) · \(first.title)", zh: "\(stamp) 检查过 · \(first.title)", ja: "\(stamp) に確認 · \(first.title)", ko: "\(stamp) 점검 · \(first.title)")
        }
        return LocalizedString.l(lang, en: "Checked \(stamp) · All good", zh: "\(stamp) 检查过 · 一切正常", ja: "\(stamp) に確認 · 異常なし", ko: "\(stamp) 점검 · 모두 정상")
    }
}
