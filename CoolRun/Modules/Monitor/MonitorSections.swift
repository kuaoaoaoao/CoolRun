import SwiftUI
import Combine
import AppKit
import Observation

// MARK: - 可折叠的 Section 组件

struct CollapsibleSection<Header: View, Content: View>: View {
    let sectionKey: MonitorSectionKey
    let icon: String
    let title: String
    let value: String
    var healthColor: Color? = nil
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    private let disclosure = MonitorSectionDisclosure.shared

    private var isExpanded: Bool { disclosure.isExpanded(sectionKey) }

    /// 表头 hover 用强调色的淡色底，替代原来展开后整块的灰色底板。
    private var accentTint: Color {
        healthColor ?? AppTheme.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                disclosure.toggle(sectionKey)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(healthColor ?? AppTheme.icon(colorScheme))
                        .frame(width: 24, height: 24)
                        .background(
                            (healthColor ?? AppTheme.icon(colorScheme)).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        )

                    Text(title)
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)

                    Spacer(minLength: 4)

                    // 右侧详情让位给标题：空间不足时截断这里，而不是把标题压没。
                    header()
                        .layoutPriority(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.55))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentTint.opacity(isHovering ? (colorScheme == .dark ? 0.09 : 0.06) : 0))
            }
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
            .accessibilityValue(value)
            .accessibilityHint(
                isExpanded
                    ? LocalizedString.monitor("collapse_hint")
                    : LocalizedString.monitor("expand_hint")
            )

            if isExpanded {
                VStack(spacing: 0) {
                    Separator()
                        .padding(.top, 1)

                    VStack(spacing: 2) {
                        content()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        // 统一的隐式动画：只做高度与透明度过渡，不再让内容从顶部平移进来。
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isExpanded)
    }
}

// MARK: - 各个监控区域

enum MonitorHealthStatus {
    case healthy
    case warning
    case critical

    var color: Color {
        switch self {
        case .healthy: AppTheme.healthy
        case .warning: AppTheme.warning
        case .critical: AppTheme.critical
        }
    }

    var icon: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .healthy: LocalizedString.monitor("status_normal", lang: language)
        case .warning: LocalizedString.monitor("status_elevated", lang: language)
        case .critical: LocalizedString.monitor("status_attention", lang: language)
        }
    }
}

struct MonitorStatusHeader: View {
    let status: MonitorHealthStatus
    let updatedAt: Date
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = AppSettings.shared
    private let disclosure = MonitorSectionDisclosure.shared

    var body: some View {
        HStack(spacing: 5) {
            Text(LocalizedString.monitor("device_status", lang: settings.language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineLimit(1)

            Circle()
                .fill(AppTheme.healthy)
                .frame(width: 5, height: 5)
                .help(LocalizedString.monitor("live", lang: settings.language))
                .accessibilityLabel(LocalizedString.monitor("live", lang: settings.language))

            Spacer(minLength: 2)

            Label(status.title(language: settings.language), systemImage: status.icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(status.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(status.color.opacity(0.11), in: Capsule())
                .help(updatedAt.formatted(date: .omitted, time: .standard))

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    disclosure.setAll(!disclosure.hasExpandedSection)
                }
            } label: {
                Image(systemName: disclosure.hasExpandedSection
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .frame(width: 20, height: 20)
                    .background(
                        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(disclosure.hasExpandedSection ? collapseAllHint : expandAllHint)
            .accessibilityLabel(disclosure.hasExpandedSection ? collapseAllHint : expandAllHint)
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 24)
    }

    private var expandAllHint: String {
        LocalizedString.monitor("expand_all", lang: settings.language)
    }

    private var collapseAllHint: String {
        LocalizedString.monitor("collapse_all", lang: settings.language)
    }
}

struct ResourceMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let progress: Double
    let history: [Double]
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 2)

                Circle()
                    .fill(tint)
                    .frame(width: 4.5, height: 4.5)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .monospacedDigit()
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }

            ZStack(alignment: .bottom) {
                SparklineChart(
                    values: history,
                    color: tint,
                    showGradient: true,
                    valueRange: 0...1
                )

                ProgressPill(value: progress, tint: tint)
                    .frame(height: 2)
                    .opacity(0.7)
            }
            .frame(height: 16)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .monitorCardSurface()
    }
}

struct TemperatureSection: View {
    let metrics: TemperatureMetrics
    var cpuHistory: MetricHistory = MetricHistory()
    var gpuHistory: MetricHistory = MetricHistory()
    @State private var showsSensors = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(
            sectionKey: .temperature,
            icon: "thermometer.medium",
            title: LocalizedString.monitor("temperature", lang: settings.language),
            value: primaryTemperatureText,
            healthColor: hasTemperature ? temperatureColor : nil
        ) {
            HStack(spacing: 6) {
                Text(temperatureStatusText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(temperatureColor)

                Text(primaryTemperatureText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(temperatureColor)
                    .monospacedDigit()
            }
        } content: {
            if hasTemperature {
                SparklineChart(
                    values: chartHistory,
                    color: temperatureColor,
                    valueRange: 30...100
                )
                .frame(height: 26)
                .background {
                    ThermalGuide()
                }

                HStack(spacing: 6) {
                    temperatureChip(
                        label: "CPU",
                        value: metrics.cpuTemperature
                    )
                    temperatureChip(
                        label: "GPU",
                        value: metrics.gpuTemperature
                    )

                    Spacer(minLength: 2)

                    if !metrics.sensors.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsSensors.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(
                                    "\(metrics.sensors.count) "
                                        + LocalizedString.monitor("sensors", lang: settings.language)
                                )
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(showsSensors ? 90 : 0))
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.06)
                                    : Color.black.opacity(0.045),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if showsSensors {
                    VStack(spacing: 1) {
                        ForEach(Array(sortedSensors.prefix(6).enumerated()), id: \.offset) { _, sensor in
                            MetricRow(label: sensor.name, value: sensor.formatted)
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                Label(
                    LocalizedString.monitor("temperature_unavailable", lang: settings.language),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .padding(.vertical, 4)
            }
        }
    }

    private var availableTemperatures: [Double] {
        [
            metrics.cpuTemperature,
            metrics.gpuTemperature,
            metrics.sensors.map(\.temperature).max()
        ]
        .compactMap { $0 }
    }

    private var primaryTemperature: Double? {
        metrics.cpuTemperature
            ?? metrics.gpuTemperature
            ?? metrics.sensors.map(\.temperature).max()
    }

    private var primaryTemperatureText: String {
        primaryTemperature.map { String(format: "%.1f°C", $0) } ?? "--"
    }

    private var hasTemperature: Bool {
        !availableTemperatures.isEmpty
    }

    private var hottestTemperature: Double {
        availableTemperatures.max() ?? 0
    }

    private var temperatureColor: Color {
        guard hasTemperature else { return AppTheme.textSecondary(colorScheme) }
        return AppTheme.temperatureColor(for: hottestTemperature)
    }

    private var temperatureStatusText: String {
        guard hasTemperature else {
            return LocalizedString.monitor("unavailable", lang: settings.language)
        }

        switch hottestTemperature {
        case ..<80:
            return LocalizedString.monitor("thermal_normal", lang: settings.language)
        case ..<95:
            return LocalizedString.monitor("thermal_warm", lang: settings.language)
        default:
            return LocalizedString.monitor("thermal_hot", lang: settings.language)
        }
    }

    private var chartHistory: [Double] {
        if metrics.cpuTemperature != nil {
            return cpuHistory.values
        }
        return gpuHistory.values
    }

    private var sortedSensors: [SensorReading] {
        metrics.sensors.sorted { $0.temperature > $1.temperature }
    }

    private func temperatureChip(label: String, value: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value.map { String(format: "%.1f°C", $0) } ?? "--")
                .foregroundStyle(
                    value.map { AppTheme.temperatureColor(for: $0) }
                        ?? AppTheme.textSecondary(colorScheme)
                )
                .monospacedDigit()
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            colorScheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.045),
            in: Capsule()
        )
    }
}

struct ThermalGuide: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [
                    AppTheme.healthy.opacity(0.3),
                    AppTheme.warning.opacity(0.32),
                    AppTheme.critical.opacity(0.32)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 2)
            .clipShape(Capsule())
        }
        .opacity(colorScheme == .dark ? 0.8 : 1)
    }
}

