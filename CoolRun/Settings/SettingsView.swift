import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 设置窗口

struct SettingsView: View {
    @Environment(\.openURL) var openURL
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var textbookStore = EnglishTextbookStore.shared
    @ObservedObject var launchAtLogin = LaunchAtLoginManager.shared
    @ObservedObject var reminderCenter = LocalReminderCenter.shared
    @State var selectedCategory: SettingsCategory = .general
    // 系统通知权限被拒时在到价提醒开关下提示，避免用户以为开了就能收到
    @State var notificationPermissionDenied = false
    @AppStorage(ClipboardQuickPasteController.enabledDefaultsKey) var quickPasteEnabled = false
    @AppStorage("pet.enabled") var petEnabled = true
    @State var quickPasteAccessibilityGranted = AXIsProcessTrusted()

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
                        case .ai:
                            aiContent
                        case .plugins:
                            pluginsContent
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

    var settingsSidebar: some View {
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

    var contentHeader: some View {
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
}
