import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 数据与关于

extension SettingsView {
    var dataContent: some View {
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

    var aboutContent: some View {
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
