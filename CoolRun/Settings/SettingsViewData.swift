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
                Divider().padding(.horizontal, 12)
                Button {
                    if let url = URL(string: "mailto:\(AppLinks.feedbackEmail)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedString.l(
                                settings.language,
                                en: "Send Feedback",
                                zh: "发送反馈",
                                ja: "フィードバックを送信",
                                ko: "피드 보내기"
                            ))
                            .font(.subheadline.weight(.medium))
                            Text(AppLinks.feedbackEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedString.l(
                    settings.language,
                    en: "Send Feedback",
                    zh: "发送反馈",
                    ja: "フィードバックを送信",
                    ko: "피드백 보내기"
                ))
            }
            .appCardSurface(cornerRadius: 12, showsShadow: false)
        }
    }
}
