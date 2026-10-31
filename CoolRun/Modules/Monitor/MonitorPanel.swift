import SwiftUI
import Combine
import AppKit
import Observation

// MARK: - 监控区域展开状态

/// 监控面板中所有可折叠区域的标识。
enum MonitorSectionKey: String, CaseIterable {
    case history
    case temperature
    case processes
    case storage
    case battery
    case network
    case uptime
}

/// 统一管理监控面板的展开/收起状态：逐区记忆并支持一键全展开/全收起。
@Observable
final class MonitorSectionDisclosure {
    static let shared = MonitorSectionDisclosure()

    private static let defaultsKey = "monitor.section.expanded.v3"

    private var states: [String: Bool]

    private init() {
        states = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Bool] ?? [:]
    }

    func isExpanded(_ key: MonitorSectionKey) -> Bool {
        states[key.rawValue] ?? false
    }

    func setExpanded(_ expanded: Bool, for key: MonitorSectionKey) {
        guard states[key.rawValue] != expanded else { return }
        states[key.rawValue] = expanded
        persist()
    }

    func toggle(_ key: MonitorSectionKey) {
        setExpanded(!isExpanded(key), for: key)
    }

    /// 是否有任意区域处于展开状态，用于决定一键按钮的方向。
    var hasExpandedSection: Bool {
        MonitorSectionKey.allCases.contains { isExpanded($0) }
    }

    func setAll(_ expanded: Bool) {
        for key in MonitorSectionKey.allCases {
            states[key.rawValue] = expanded
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(states, forKey: Self.defaultsKey)
    }
}

struct MonitorPanel: View {
    let snapshot: SystemSnapshot
    var cpuHistory: MetricHistory = MetricHistory()
    var memoryHistory: MetricHistory = MetricHistory()
    var downloadHistory: MetricHistory = MetricHistory()
    var uploadHistory: MetricHistory = MetricHistory()
    var cpuTempHistory: MetricHistory = MetricHistory()
    var gpuTempHistory: MetricHistory = MetricHistory()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 6) {
                MonitorStatusHeader(
                    status: overallStatus,
                    updatedAt: snapshot.updatedAt
                )

                SystemHistoryCard()

                if settings.showCPU || settings.showMemory {
                    HStack(alignment: .top, spacing: 8) {
                        if settings.showCPU {
                            ResourceMetricCard(
                                icon: "cpu",
                                title: LocalizedString.monitor("cpu", lang: settings.language),
                                value: snapshot.cpu.usage.percentText,
                                detail: "\(snapshot.cpu.coreCount) \(LocalizedString.monitor("cores_unit", lang: settings.language))",
                                progress: snapshot.cpu.usage,
                                history: cpuHistory.values,
                                tint: AppTheme.healthColor(for: snapshot.cpu.usage)
                            )
                        }

                        if settings.showMemory {
                            ResourceMetricCard(
                                icon: "memorychip",
                                title: LocalizedString.monitor("memory", lang: settings.language),
                                value: snapshot.memory.usage.percentText,
                                detail: "\(snapshot.memory.used.memoryText) / \(snapshot.memory.total.memoryText)",
                                progress: snapshot.memory.usage,
                                history: memoryHistory.values,
                                tint: AppTheme.healthColor(for: snapshot.memory.usage)
                            )
                        }
                    }
                }

                if settings.showProcesses {
                    ProcessSection(metrics: snapshot.processes)
                        .monitorCardSurface()
                }

                if settings.showTemperature {
                    TemperatureSection(
                        metrics: snapshot.temperature,
                        cpuHistory: cpuTempHistory,
                        gpuHistory: gpuTempHistory
                    )
                    .monitorCardSurface()
                }

                if showsSecondaryMetrics {
                    VStack(spacing: 0) {
                        if settings.showStorage {
                            StorageSection(metrics: snapshot.storage)
                        }

                        if settings.showBattery {
                            if settings.showStorage { Separator() }
                            BatterySection(metrics: snapshot.battery)
                        }

                        if settings.showNetwork {
                            if settings.showStorage || settings.showBattery { Separator() }
                            NetworkSection(
                                metrics: snapshot.network,
                                downloadHistory: downloadHistory,
                                uploadHistory: uploadHistory
                            )
                        }

                        if settings.showUptime {
                            if settings.showStorage || settings.showBattery || settings.showNetwork {
                                Separator()
                            }
                            UptimeSection(metrics: snapshot.uptime)
                        }
                    }
                    .monitorCardSurface()
                }

                if !showsAnyMetric {
                    ContentUnavailableView(
                        LocalizedString.monitor("no_modules", lang: settings.language),
                        systemImage: "gauge.with.dots.needle.0percent",
                        description: Text(LocalizedString.monitor("no_modules_hint", lang: settings.language))
                    )
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .monitorCardSurface()
                }
            }
            .padding(1)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private var showsSecondaryMetrics: Bool {
        settings.showStorage || settings.showBattery || settings.showNetwork || settings.showUptime
    }

    private var showsAnyMetric: Bool {
        settings.showCPU
            || settings.showMemory
            || settings.showTemperature
            || settings.showProcesses
            || showsSecondaryMetrics
    }

    private var overallStatus: MonitorHealthStatus {
        let hottestTemperature: Double? = if settings.showTemperature {
            [
                snapshot.temperature.cpuTemperature,
                snapshot.temperature.gpuTemperature,
                snapshot.temperature.sensors.map(\.temperature).max()
            ]
            .compactMap { $0 }
            .max()
        } else {
            nil
        }

        if (settings.showCPU && snapshot.cpu.usage >= 0.9)
            || (settings.showMemory && snapshot.memory.usage >= 0.9)
            || (settings.showStorage && snapshot.storage.usage >= 0.95)
            || (hottestTemperature ?? 0) >= 95 {
            return .critical
        }

        if (settings.showCPU && snapshot.cpu.usage >= 0.75)
            || (settings.showMemory && snapshot.memory.usage >= 0.75)
            || (settings.showStorage && snapshot.storage.usage >= 0.85)
            || (hottestTemperature ?? 0) >= 80 {
            return .warning
        }

        return .healthy
    }
}

