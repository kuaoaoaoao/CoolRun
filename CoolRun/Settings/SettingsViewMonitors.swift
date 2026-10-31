import AVFoundation
import SwiftUI
import UserNotifications

// MARK: - 监控设置

extension SettingsView {
    var monitorsContent: some View {
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
}
