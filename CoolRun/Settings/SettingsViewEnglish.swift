import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 英语学习设置

extension SettingsView {
    var englishContent: some View {
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

    var englishVoices: [AVSpeechSynthesisVoice] {
        EnglishLearningManager.availableVoices(for: settings.englishAccent)
    }

    func voiceDisplayName(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = " · Premium"
        case .enhanced: quality = " · Enhanced"
        default: quality = ""
        }
        return "\(voice.name)\(quality)"
    }

    var voiceQualityHintRow: some View {
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

    func settingsPickerRow<Content: View>(
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

    func settingsTextFieldRow(
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

    func englishSliderRow(
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
}
