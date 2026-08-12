import SwiftUI
import Combine
import AppKit

// MARK: - 视图模式

enum ViewMode: String, CaseIterable, Sendable {
    case today
    case monitor
    case gold
    case calendar
    case english
    case codex
    case notes
    case clipboard
    case diagnostics

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .monitor: return "chart.bar.fill"
        case .gold: return "chart.line.uptrend.xyaxis"
        case .calendar: return "calendar"
        case .english: return "character.book.closed"
        case .codex: return "sparkles"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .diagnostics: return "stethoscope"
        }
    }

    var displayName: String {
        switch self {
        case .today: return LocalizedString.l(AppSettings.shared.language, en: "Today", zh: "今天", ja: "今日", ko: "오늘")
        case .monitor: return LocalizedString.calendar("monitor")
        case .gold: return LocalizedString.goldPrice("gold_price")
        case .calendar: return LocalizedString.calendar("calendar")
        case .english: return LocalizedString.english("english")
        case .codex: return "Codex"
        case .notes: return LocalizedString.l(AppSettings.shared.language, en: "Notes", zh: "备忘录", ja: "メモ", ko: "메모")
        case .clipboard: return LocalizedString.l(AppSettings.shared.language, en: "Clipboard", zh: "剪切板", ja: "クリップボード", ko: "클립보드")
        case .diagnostics: return LocalizedString.l(AppSettings.shared.language, en: "Diagnostics", zh: "诊断", ja: "診断", ko: "진단")
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .today: return "0"
        case .monitor: return "1"
        case .gold: return "2"
        case .calendar: return "3"
        case .english: return "4"
        case .codex: return "5"
        case .notes: return "6"
        case .clipboard: return "7"
        case .diagnostics: return "8"
        }
    }
}

struct ContentView: View {
    @State private var viewModel = SystemMonitorViewModel()
    // 重启后回到上次使用的模块
    @State private var viewMode: ViewMode = ViewMode(rawValue: AppSettings.shared.lastViewModeRaw) ?? .monitor
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var router = AppNavigationRouter.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var progressStore = EnglishProgressStore.shared
    @State private var goldStore = GoldPriceStore.shared
    @State private var tradeStore = GoldTradeStore.shared
    @State private var codexModel = CodexMonitorViewModel.shared
    @State private var claudeModel = ClaudeMonitorViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            ModuleNavigationRail(selection: $viewMode, todayAttention: todayAttention)
                .padding(.bottom, 8)

            Group {
                switch viewMode {
                case .today:
                    TodayOverviewView(snapshot: viewModel.snapshot)
                case .monitor:
                    MonitorPanel(
                        snapshot: viewModel.snapshot,
                        cpuHistory: viewModel.cpuHistory,
                        memoryHistory: viewModel.memoryHistory,
                        downloadHistory: viewModel.downloadHistory,
                        uploadHistory: viewModel.uploadHistory,
                        cpuTempHistory: viewModel.cpuTempHistory,
                        gpuTempHistory: viewModel.gpuTempHistory
                    )
                case .gold:
                    GoldAnalysisView()
                case .calendar:
                    CalendarView()
                case .english:
                    EnglishLearningView()
                case .codex:
                    AIMonitorView()
                case .notes:
                    NotesView()
                case .clipboard:
                    ClipboardHistoryView()
                case .diagnostics:
                    DiagnosticsView()
                }
            }
            .id(viewMode)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .padding(8)
        .background {
            ZStack {
                VisualEffectBlur(material: colorScheme == .dark ? .hudWindow : .menu, blendingMode: .behindWindow)
                AppTheme.canvas(colorScheme)
                LinearGradient(
                    colors: [
                        AppTheme.accent.opacity(colorScheme == .dark ? 0.08 : 0.055),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
        }
        .onAppear { viewModel.start() }
        .onReceive(router.$request.compactMap { $0 }) { request in
            viewMode = request.mode
        }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewMode) { _, newValue in
            AppSettings.shared.lastViewModeRaw = newValue.rawValue
        }
    }

    private var todayAttention: TodaySeverity? {
        TodaySummaryBuilder.maximumSeverity(in: TodaySummaryBuilder.current(
            snapshot: viewModel.snapshot,
            settings: settings,
            progressStore: progressStore,
            goldStore: goldStore,
            tradeStore: tradeStore,
            codexModel: codexModel,
            claudeModel: claudeModel
        ))
    }
}

// MARK: - 全局模块导航

struct ModuleNavigationRail<Trailing: View>: View {
    @Binding var selection: ViewMode
    @ViewBuilder let trailing: Trailing
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation
    @State private var hoveredMode: ViewMode?
    var todayAttention: TodaySeverity?

    init(
        selection: Binding<ViewMode>,
        todayAttention: TodaySeverity? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        _selection = selection
        self.todayAttention = todayAttention
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            navigationContent(showsSelectionTitle: true)
                .fixedSize(horizontal: true, vertical: false)

            navigationContent(showsSelectionTitle: false)
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.chromeSurface(colorScheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
        .shadow(color: AppTheme.shadow(colorScheme), radius: 8, y: 3)
        .animation(.easeOut(duration: 0.12), value: hoveredMode)
    }

    private func navigationContent(showsSelectionTitle: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    guard selection != mode else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.02)) {
                        selection = mode
                    }
                    Analytics.capture(.viewTabSwitched, properties: [
                        "tab": mode.rawValue,
                    ])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if mode == .today, let todayAttention, todayAttention >= .warning {
                                    Circle()
                                        .fill(todayAttention.color)
                                        .frame(width: 5, height: 5)
                                        .offset(x: 3, y: -3)
                                }
                            }

                        if selection == mode, showsSelectionTitle {
                            Text(mode.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .frame(
                        minWidth: selection == mode ? (showsSelectionTitle ? 28 : 24) : 24,
                        minHeight: 32
                    )
                    .padding(.horizontal, selection == mode ? (showsSelectionTitle ? 5 : 2) : 0)
                    .foregroundStyle(selection == mode ? AppTheme.accent : AppTheme.textSecondary(colorScheme))
                    .background {
                        if selection == mode {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.accent.opacity(colorScheme == .dark ? 0.20 : 0.13))
                                .matchedGeometryEffect(
                                    id: showsSelectionTitle ? "selected-module-titled" : "selected-module-compact",
                                    in: selectionAnimation
                                )
                        } else if hoveredMode == mode {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.07))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(mode.keyboardShortcut, modifiers: .command)
                .help(mode.displayName)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
                .onHover { isHovering in
                    if isHovering {
                        hoveredMode = mode
                    } else if hoveredMode == mode {
                        hoveredMode = nil
                    }
                }
            }

            Spacer(minLength: 2)
            trailing
        }
    }
}

extension ModuleNavigationRail where Trailing == EmptyView {
    init(selection: Binding<ViewMode>, todayAttention: TodaySeverity? = nil) {
        self.init(selection: selection, todayAttention: todayAttention) { EmptyView() }
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
            LazyVStack(spacing: 8) {
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
                }

                if settings.showTemperature {
                    TemperatureSection(
                        metrics: snapshot.temperature,
                        cpuHistory: cpuTempHistory,
                        gpuHistory: gpuTempHistory
                    )
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

// MARK: - 可折叠的 Section 组件

private struct CollapsibleSection<Header: View, Content: View>: View {
    let icon: String
    let title: String
    let value: String
    var healthColor: Color? = nil
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(healthColor ?? AppTheme.icon(colorScheme))
                        .frame(width: 26, height: 26)
                        .background(
                            (healthColor ?? AppTheme.icon(colorScheme)).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )

                    Text(title)
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                        .font(.subheadline.weight(.medium))
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    header()
                        .layoutPriority(2)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.65))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(value)
            .accessibilityHint(
                isExpanded
                    ? LocalizedString.monitor("collapse_hint")
                    : LocalizedString.monitor("expand_hint")
            )

            if isExpanded {
                VStack(spacing: 2) {
                    content()
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 9)
                .background(
                    colorScheme == .dark
                        ? Color.white.opacity(0.025)
                        : Color.black.opacity(0.018)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - 各个监控区域

private enum MonitorHealthStatus {
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

private struct MonitorStatusHeader: View {
    let status: MonitorHealthStatus
    let updatedAt: Date
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedString.monitor("device_status", lang: settings.language))
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))

                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.healthy)
                        .frame(width: 5, height: 5)
                    Text(LocalizedString.monitor("live", lang: settings.language))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }

            Spacer()

            Label(status.title(language: settings.language), systemImage: status.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(status.color.opacity(0.11), in: Capsule())
                .help(updatedAt.formatted(date: .omitted, time: .standard))
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
}

private struct ResourceMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let progress: Double
    let history: [Double]
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))

                Spacer(minLength: 2)

                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
            }

            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .monospacedDigit()

            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

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
            .frame(height: 22)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .monitorCardSurface()
    }
}

private struct TemperatureSection: View {
    let metrics: TemperatureMetrics
    var cpuHistory: MetricHistory = MetricHistory()
    var gpuHistory: MetricHistory = MetricHistory()
    @State private var showsSensors = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(temperatureColor)
                    .frame(width: 28, height: 28)
                    .background(
                        temperatureColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedString.monitor("temperature", lang: settings.language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))

                    Text(temperatureStatusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(temperatureColor)
                }

                Spacer()

                Text(primaryTemperatureText)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(temperatureColor)
                    .monospacedDigit()
            }

            if hasTemperature {
                SparklineChart(
                    values: chartHistory,
                    color: temperatureColor,
                    valueRange: 30...100
                )
                .frame(height: 32)
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
                .padding(.vertical, 5)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monitorCardSurface()
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

private struct ThermalGuide: View {
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

// MARK: - 进程明细

private struct ProcessSection: View {
    let metrics: ProcessListMetrics
    @State private var sortKey: SortKey = .cpu
    @State private var isExpanded = false
    // 列表默认收起，用户的展开选择持久化
    @AppStorage("monitor_process_list_expanded") private var showsList = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    private enum SortKey {
        case cpu
        case memory
    }

    private var collapsedCount: Int { 5 }
    private var expandedCount: Int { 15 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsList.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.icon(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(
                            AppTheme.icon(colorScheme).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(LocalizedString.monitor("processes", lang: settings.language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary(colorScheme))

                        Text(subtitleText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.65))
                        .rotationEffect(.degrees(showsList ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                showsList
                    ? LocalizedString.monitor("collapse_hint", lang: settings.language)
                    : LocalizedString.monitor("expand_hint", lang: settings.language)
            )

            if showsList {
                if displayedProcesses.isEmpty {
                    Label(
                        LocalizedString.monitor("process_waiting", lang: settings.language),
                        systemImage: "hourglass"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .padding(.vertical, 5)
                } else {
                    HStack(spacing: 6) {
                        Label(
                            LocalizedString.monitor("sort_by", lang: settings.language),
                            systemImage: "arrow.up.arrow.down"
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))

                        Spacer()
                        sortToggle
                    }

                    VStack(spacing: 1) {
                        ForEach(displayedProcesses) { process in
                            ProcessRow(
                                process: process,
                                highlightsCPU: sortKey == .cpu,
                                barFraction: barFraction(for: process)
                            )
                        }
                    }

                    if metrics.processes.count > collapsedCount {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(
                                    isExpanded
                                        ? LocalizedString.monitor("show_less", lang: settings.language)
                                        : LocalizedString.monitor("show_more", lang: settings.language)
                                )
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monitorCardSurface()
    }

    /// 副标题：进程总数；收起时附带 CPU 占用最高的进程概览
    private var subtitleText: String {
        guard metrics.totalCount > 0 else {
            return LocalizedString.monitor("process_waiting", lang: settings.language)
        }

        var text = "\(metrics.totalCount) \(LocalizedString.monitor("process_count_unit", lang: settings.language))"
        if !showsList, let top = metrics.processes.max(by: { $0.cpuUsage < $1.cpuUsage }), top.cpuUsage > 0 {
            text += " · \(top.name) \(top.cpuUsage.percentText)"
        }
        return text
    }

    private var sortToggle: some View {
        HStack(spacing: 2) {
            sortButton("CPU", systemImage: "cpu", key: .cpu)
            sortButton(
                LocalizedString.monitor("memory", lang: settings.language),
                systemImage: "memorychip",
                key: .memory
            )
        }
        .padding(2)
        .background(
            colorScheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.045),
            in: Capsule()
        )
        .help(LocalizedString.monitor("sort_by", lang: settings.language))
    }

    private func sortButton(_ title: String, systemImage: String, key: SortKey) -> some View {
        Button {
            guard sortKey != key else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                sortKey = key
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    sortKey == key
                        ? AppTheme.accent
                        : AppTheme.textSecondary(colorScheme)
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    if sortKey == key {
                        Capsule().fill(AppTheme.accent.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var sortedProcesses: [ProcessMetrics] {
        switch sortKey {
        case .cpu:
            metrics.processes.sorted { $0.cpuUsage > $1.cpuUsage }
        case .memory:
            metrics.processes.sorted { $0.memoryBytes > $1.memoryBytes }
        }
    }

    private var displayedProcesses: [ProcessMetrics] {
        Array(sortedProcesses.prefix(isExpanded ? expandedCount : collapsedCount))
    }

    private func barFraction(for process: ProcessMetrics) -> Double {
        switch sortKey {
        case .cpu:
            let maxUsage = displayedProcesses.map(\.cpuUsage).max() ?? 0
            return maxUsage > 0 ? process.cpuUsage / maxUsage : 0
        case .memory:
            let maxMemory = displayedProcesses.map(\.memoryBytes).max() ?? 0
            return maxMemory > 0 ? Double(process.memoryBytes) / Double(maxMemory) : 0
        }
    }
}

private struct ProcessRow: View {
    let process: ProcessMetrics
    let highlightsCPU: Bool
    let barFraction: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = AppSettings.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            ProcessIcon(process: process)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(process.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if process.instanceCount > 1 {
                        Text("×\(process.instanceCount)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.09)
                                    : Color.black.opacity(0.055),
                                in: Capsule()
                            )
                    }
                }

                HStack(spacing: 6) {
                    Text("PID \(process.pid)")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.8))
                        .lineLimit(1)

                    ProgressPill(value: barFraction, tint: barTint)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                metricValue(
                    process.cpuUsage.percentText,
                    systemImage: "cpu",
                    isPrimary: highlightsCPU
                )
                metricValue(
                    process.memoryBytes.memoryText,
                    systemImage: "memorychip",
                    isPrimary: !highlightsCPU
                )
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? AppTheme.elevatedSurface(colorScheme) : Color.clear)
        }
        .contentShape(Rectangle())
        .help(helpText)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if !containsOwnProcess {
                Button(role: .destructive) {
                    for pid in targetPIDs {
                        kill(pid, SIGTERM)
                    }
                } label: {
                    Label(terminateLabel, systemImage: "xmark.circle")
                }
            }
        }
    }

    private var targetPIDs: [pid_t] {
        process.pids.isEmpty ? [process.pid] : process.pids
    }

    private var containsOwnProcess: Bool {
        targetPIDs.contains(ProcessInfo.processInfo.processIdentifier)
    }

    private var terminateLabel: String {
        let base = LocalizedString.monitor("terminate_process", lang: settings.language)
        return process.instanceCount > 1 ? "\(base) (\(process.instanceCount))" : base
    }

    private var helpText: String {
        let pidText = process.instanceCount > 1
            ? "PID \(process.pid) ×\(process.instanceCount)"
            : "PID \(process.pid)"
        return "\(pidText) · CPU \(process.cpuUsage.percentText) · \(process.memoryBytes.memoryText)"
    }

    private func metricValue(_ value: String, systemImage: String, isPrimary: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 10)
            Text(value)
                .font(.system(size: 9, weight: isPrimary ? .bold : .medium, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(isPrimary ? primaryTint : AppTheme.textSecondary(colorScheme))
        .accessibilityElement(children: .combine)
    }

    private var barTint: Color {
        primaryTint
    }

    private var primaryTint: Color {
        highlightsCPU
            ? AppTheme.healthColor(for: min(process.cpuUsage, 1))
            : AppTheme.accent
    }
}

private struct ProcessIcon: View {
    let process: ProcessMetrics
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let resolvedIcon {
                Image(nsImage: resolvedIcon)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: fallback.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(fallback.tint)
            }
        }
        .frame(width: 28, height: 28)
        .background(
            fallback.tint.opacity(colorScheme == .dark ? 0.14 : 0.09),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var resolvedIcon: NSImage? {
        applicationIcon ?? ProcessIconResolver.icon(forExecutableAt: process.executablePath)
    }

    private var applicationIcon: NSImage? {
        for pid in candidatePIDs {
            if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                return icon
            }
        }
        return nil
    }

    private var candidatePIDs: [pid_t] {
        process.pids.isEmpty ? [process.pid] : process.pids
    }

    private var fallback: ProcessFallbackIcon {
        ProcessFallbackIcon(name: process.name)
    }
}

private enum ProcessIconResolver {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    static func icon(forExecutableAt executablePath: String?) -> NSImage? {
        guard let executablePath, !executablePath.isEmpty else { return nil }

        // Helper、XPC 与 Framework 子进程优先继承最近一层父 .app 的真实图标。
        let iconPath = enclosingApplicationPath(for: executablePath) ?? executablePath
        let cacheKey = iconPath as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard FileManager.default.fileExists(atPath: iconPath) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: iconPath)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static func enclosingApplicationPath(for executablePath: String) -> String? {
        var url = URL(fileURLWithPath: executablePath).deletingLastPathComponent()

        while url.path != "/" {
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return url.path
            }

            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { break }
            url = parent
        }

        return nil
    }
}

private struct ProcessFallbackIcon {
    let symbol: String
    let tint: Color

    init(name: String) {
        let normalized = name.lowercased()

        if Self.containsAny(normalized, ["safari", "chrome", "firefox", "edge", "webkit"]) {
            symbol = "globe"
            tint = .blue
        } else if Self.containsAny(normalized, [
            "xcode", "swift", "clang", "git", "node", "python", "java", "terminal", "code"
        ]) {
            symbol = "terminal.fill"
            tint = .purple
        } else if Self.containsAny(normalized, [
            "music", "spotify", "photo", "video", "media", "zoom", "facetime"
        ]) {
            symbol = "play.rectangle.fill"
            tint = .pink
        } else if Self.containsAny(normalized, [
            "network", "cloud", "vpn", "wifi", "bluetooth", "sharing"
        ]) {
            symbol = "network"
            tint = .teal
        } else if Self.containsAny(normalized, [
            "kernel", "launchd", "windowserver", "system", "daemon", "service", "mds"
        ]) {
            symbol = "gearshape.2.fill"
            tint = .orange
        } else {
            symbol = "app.fill"
            tint = AppTheme.accent
        }
    }

    private static func containsAny(_ name: String, _ keywords: [String]) -> Bool {
        keywords.contains(where: name.contains)
    }
}

private struct StorageSection: View {
    let metrics: StorageMetrics
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(icon: "externaldrive", title: LocalizedString.monitor("storage", lang: settings.language), value: metrics.usage.percentText) {
            HStack(spacing: 6) {
                ProgressPill(value: metrics.usage, tint: .blue)
                    .frame(width: 40, height: 4)
                Text(metrics.usage.percentText)
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
        } content: {
            MetricRow(label: LocalizedString.monitor("used", lang: settings.language), value: metrics.used.storageText)
            MetricRow(label: LocalizedString.monitor("available", lang: settings.language), value: metrics.available.storageText)
        }
    }
}

private struct BatterySection: View {
    let metrics: BatteryMetrics
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(icon: batteryIcon, title: LocalizedString.monitor("battery", lang: settings.language), value: levelText) {
            Text(levelText)
                .foregroundStyle(batteryColor)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        } content: {
            MetricRow(label: LocalizedString.monitor("status", lang: settings.language), value: batteryStateText)
            MetricRow(label: LocalizedString.monitor("low_power", lang: settings.language), value: metrics.isLowPowerModeEnabled ? LocalizedString.label("on", lang: settings.language) : LocalizedString.label("off", lang: settings.language))
            if let health = metrics.health {
                if let healthPercent = health.healthPercent {
                    MetricRow(label: LocalizedString.monitor("battery_health", lang: settings.language), value: String(format: "%.0f%%", healthPercent))
                }
                if let cycleCount = health.cycleCount {
                    MetricRow(label: LocalizedString.monitor("cycle_count", lang: settings.language), value: "\(cycleCount)")
                }
                if let maxCapacity = health.maxCapacity, let designCapacity = health.designCapacity {
                    MetricRow(label: LocalizedString.monitor("battery_capacity", lang: settings.language), value: "\(maxCapacity) / \(designCapacity) mAh")
                }
                if let temperature = health.temperatureCelsius {
                    MetricRow(label: LocalizedString.monitor("battery_temp", lang: settings.language), value: String(format: "%.1f°C", temperature))
                }
                if let wattage = health.wattage, abs(wattage) >= 0.05 {
                    MetricRow(label: LocalizedString.monitor("battery_power", lang: settings.language), value: String(format: "%@%.1f W", wattage > 0 ? "+" : "", wattage))
                }
                if let minutes = health.timeRemainingMinutes {
                    MetricRow(
                        label: metrics.state == .charging
                            ? LocalizedString.monitor("time_to_full", lang: settings.language)
                            : LocalizedString.monitor("time_to_empty", lang: settings.language),
                        value: String(format: "%d:%02d", minutes / 60, minutes % 60)
                    )
                }
            }
        }
    }

    private var batteryStateText: String {
        switch metrics.state {
        case .unknown: return LocalizedString.batteryState("unknown", lang: settings.language)
        case .unplugged: return LocalizedString.batteryState("unplugged", lang: settings.language)
        case .charging: return LocalizedString.batteryState("charging", lang: settings.language)
        case .full: return LocalizedString.batteryState("full", lang: settings.language)
        case .noBattery: return LocalizedString.batteryState("no_battery", lang: settings.language)
        }
    }

    private var levelText: String {
        guard let level = metrics.level else { return "--" }
        return level.percentText
    }

    @Environment(\.colorScheme) private var colorScheme

    private var batteryColor: Color {
        guard let level = metrics.level else { return AppTheme.textSecondary(colorScheme) }
        if metrics.state == .charging { return .blue }
        return level < 0.2 ? AppTheme.critical : AppTheme.healthy
    }

    private var batteryIcon: String {
        switch metrics.state {
        case .charging: "battery.100.bolt"
        case .full: "battery.100"
        case .unplugged: "battery.50"
        case .noBattery, .unknown: "battery.0"
        }
    }
}

private struct NetworkSection: View {
    let metrics: NetworkMetrics
    var downloadHistory: MetricHistory = MetricHistory()
    var uploadHistory: MetricHistory = MetricHistory()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(icon: "network", title: LocalizedString.monitor("network", lang: settings.language), value: networkName) {
            if metrics.downloadSpeed > 0 || metrics.uploadSpeed > 0 {
                Text("↓\(formatSpeed(metrics.downloadSpeed))")
                    .foregroundStyle(.blue)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
        } content: {
            MetricRow(label: LocalizedString.monitor("local_ip", lang: settings.language), value: localAddressText)
            MetricRow(label: LocalizedString.monitor("interfaces", lang: settings.language), value: metrics.activeInterfaceCount > 0 ? "\(metrics.activeInterfaceCount)" : "--")
            if metrics.downloadSpeed > 0 || metrics.uploadSpeed > 0 {
                MetricRow(label: "↓ \(LocalizedString.monitor("download", lang: settings.language))", value: formatSpeed(metrics.downloadSpeed))
                MetricRow(label: "↑ \(LocalizedString.monitor("upload", lang: settings.language))", value: formatSpeed(metrics.uploadSpeed))
                DualSparklineChart(
                    values1: downloadHistory.values,
                    values2: uploadHistory.values,
                    color1: .blue,
                    color2: .green
                )
                .frame(height: 20)
                .padding(.top, 2)
            }
        }
    }

    private var networkName: String {
        metrics.activeInterfaceCount > 0 ? LocalizedString.monitor("connected", lang: settings.language) : LocalizedString.monitor("disconnected", lang: settings.language)
    }

    private var localAddressText: String {
        metrics.primaryAddress ?? "--"
    }

    private func formatSpeed(_ bytesPerSecond: UInt64) -> String {
        if bytesPerSecond < 1024 {
            return "\(bytesPerSecond) B/s"
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", Double(bytesPerSecond) / 1024.0)
        } else {
            return String(format: "%.1f MB/s", Double(bytesPerSecond) / (1024.0 * 1024.0))
        }
    }
}

private struct UptimeSection: View {
    let metrics: UptimeMetrics
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(icon: "clock", title: LocalizedString.monitor("uptime", lang: settings.language), value: metrics.compactFormatted) {
            Text(metrics.compactFormatted)
                .foregroundStyle(AppTheme.textPrimary(colorScheme).opacity(0.8))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 50, alignment: .trailing)
        } content: {
            MetricRow(label: LocalizedString.monitor("running_time", lang: settings.language), value: metrics.formatted)
        }
    }
}

// MARK: - 基础组件

private struct MetricRow: View {
    let label: String
    let value: String
    @State private var isCopied = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .font(.system(size: 10, weight: .medium))
            Spacer(minLength: 4)
            Text(value)
                .foregroundStyle(isCopied ? AppTheme.healthy : AppTheme.textPrimary(colorScheme).opacity(0.85))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { copyToClipboard() }
        .help(LocalizedString.label("copy_hint", lang: settings.language))
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(label): \(value)", forType: .string)
        withAnimation(.easeInOut(duration: 0.3)) { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) { isCopied = false }
        }
    }
}

struct Separator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(AppTheme.separator(colorScheme))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
    }
}

// MARK: - 趋势图表

struct SparklineChart: View {
    let values: [Double]
    var color: Color = .blue
    var showGradient: Bool = true
    var valueRange: ClosedRange<Double>? = nil

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }

            let maxValue = valueRange?.upperBound ?? values.max() ?? 1.0
            let minValue = valueRange?.lowerBound ?? values.min() ?? 0.0
            let range = maxValue - minValue
            let normalizedMax = range > 0 ? range : 1.0

            let stepX = size.width / CGFloat(values.count - 1)
            let padding: CGFloat = 1
            let drawHeight = size.height - padding * 2

            var path = Path()
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = min(max((value - minValue) / normalizedMax, 0), 1)
                let y = size.height - padding - CGFloat(normalized) * drawHeight
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }

            if showGradient {
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()
                let gradient = Gradient(colors: [color.opacity(0.25), color.opacity(0.02)])
                context.fill(fillPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            }

            context.stroke(path, with: .color(color), lineWidth: 1.2)

            if let lastValue = values.last {
                let lastX = size.width
                let normalized = min(max((lastValue - minValue) / normalizedMax, 0), 1)
                let lastY = size.height - padding - CGFloat(normalized) * drawHeight
                let pointRect = CGRect(x: lastX - 2, y: lastY - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: pointRect), with: .color(color))
            }
        }
    }
}

private struct DualSparklineChart: View {
    let values1: [Double]
    let values2: [Double]
    var color1: Color = .blue
    var color2: Color = .green

    var body: some View {
        Canvas { context, size in
            let allValues = values1 + values2
            guard allValues.count >= 2 else { return }

            let maxValue = allValues.max() ?? 1.0
            let minValue = allValues.min() ?? 0.0
            let range = maxValue - minValue
            let normalizedMax = range > 0 ? range : 1.0
            let padding: CGFloat = 1
            let drawHeight = size.height - padding * 2

            if values1.count >= 2 {
                drawLine(context: context, size: size, values: values1, color: color1, minValue: minValue, normalizedMax: normalizedMax, padding: padding, drawHeight: drawHeight)
            }
            if values2.count >= 2 {
                drawLine(context: context, size: size, values: values2, color: color2, minValue: minValue, normalizedMax: normalizedMax, padding: padding, drawHeight: drawHeight)
            }
        }
    }

    private func drawLine(context: GraphicsContext, size: CGSize, values: [Double], color: Color, minValue: Double, normalizedMax: Double, padding: CGFloat, drawHeight: CGFloat) {
        let stepX = size.width / CGFloat(values.count - 1)
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (value - minValue) / normalizedMax
            let y = size.height - padding - CGFloat(normalized) * drawHeight
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }
}

// MARK: - 进度条组件

private struct MiniBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                let columns = 16
                for index in 0..<columns {
                    let phase = Double(index) / Double(columns)
                    let dynamic = 0.3 + abs(sin((phase + value) * .pi * 2.2)) * 0.7
                    let barHeight = max(1.5, height * dynamic * max(0.2, value))
                    let x = width * Double(index) / Double(columns)
                    path.addRect(CGRect(x: x, y: height - barHeight, width: max(1.5, width / Double(columns) - 1.5), height: barHeight))
                }
            }
            .fill(tint.opacity(0.7))
        }
    }
}

private struct ProgressPill: View {
    let value: Double
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.progressBg(colorScheme))
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, proxy.size.width * min(max(value, 0), 1)))
            }
        }
    }
}

// MARK: - 监控卡片表面

private struct MonitorCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .appCardSurface(cornerRadius: 11)
    }
}

private extension View {
    func monitorCardSurface() -> some View {
        modifier(MonitorCardSurface())
    }
}

// MARK: - 毛玻璃效果

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - 主题

enum AppTheme {
    // 交互色与状态色分离，避免“选中”和“健康”语义混用。
    static let accent = Color.accentColor
    static let gold = Color(red: 0.86, green: 0.58, blue: 0.18)
    static let healthy = Color(red: 0.2, green: 0.78, blue: 0.4)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.15)
    static let critical = Color(red: 0.95, green: 0.3, blue: 0.3)

    static func healthColor(for usage: Double) -> Color {
        switch usage {
        case ..<0.6: return healthy
        case ..<0.85: return warning
        default: return critical
        }
    }

    static func temperatureColor(for celsius: Double) -> Color {
        switch celsius {
        case ..<80: return healthy
        case ..<95: return warning
        default: return critical
        }
    }

    // 根据 colorScheme 返回对应颜色
    static func icon(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7)
    }

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color.black.opacity(0.9)
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }

    static func progressBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.24)
    }

    static func chromeSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.62)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.58)
    }

    static func elevatedSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.78)
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.075)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.20) : Color.black.opacity(0.065)
    }
}

struct AppCardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let showsShadow: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.surface(colorScheme))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
            }
            .shadow(
                color: showsShadow ? AppTheme.shadow(colorScheme) : .clear,
                radius: showsShadow ? 8 : 0,
                y: showsShadow ? 3 : 0
            )
    }
}

extension View {
    func appCardSurface(cornerRadius: CGFloat = 12, showsShadow: Bool = true) -> some View {
        modifier(AppCardSurface(cornerRadius: cornerRadius, showsShadow: showsShadow))
    }
}

// MARK: - 格式化扩展

private extension Double {
    var percentText: String {
        (self * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

private extension UInt64 {
    var memoryText: String {
        ByteCountFormatter.memoryFormatter.string(fromByteCount: Int64(self))
    }
    var storageText: String {
        ByteCountFormatter.storageFormatter.string(fromByteCount: Int64(self))
    }
}

private extension ByteCountFormatter {
    static let memoryFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .memory
        f.includesUnit = true
        f.isAdaptive = true
        return f
    }()
    static let storageFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB]
        f.countStyle = .file
        f.includesUnit = true
        f.isAdaptive = true
        return f
    }()
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 220, height: 360)
    }
}
