import SwiftUI
import Combine
import AppKit
import Observation

// MARK: - 进程明细

struct ProcessSection: View {
    let metrics: ProcessListMetrics
    @State private var sortKey: SortKey = .cpu
    /// 每次点“显示更多”多显示几行，避免一次性撑高整张卡片。
    @State private var extraRows = 0
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    private enum SortKey {
        case cpu
        case memory
    }

    private var collapsedCount: Int { 4 }
    private var maxVisibleCount: Int { 12 }
    private var rowStep: Int { 4 }

    var body: some View {
        CollapsibleSection(
            sectionKey: .processes,
            icon: "square.stack.3d.up.fill",
            title: LocalizedString.monitor("processes", lang: settings.language),
            value: subtitleText
        ) {
            // 宽度不够时依次退化成更短的文案，而不是把「82.4%」截成「82....」
            ViewThatFits(in: .horizontal) {
                Text(subtitleText)
                    .fixedSize(horizontal: true, vertical: false)
                Text(countAndTopNameText)
                    .fixedSize(horizontal: true, vertical: false)
                Text(countText)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .lineLimit(1)
        } content: {
            if displayedProcesses.isEmpty {
                Label(
                    LocalizedString.monitor("process_waiting", lang: settings.language),
                    systemImage: "hourglass"
                )
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 6) {
                    Text(LocalizedString.monitor("sort_by", lang: settings.language))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.85))

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
                        withAnimation(.easeOut(duration: 0.2)) {
                            if canRevealMore {
                                extraRows += rowStep
                            } else {
                                extraRows = 0
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(
                                canRevealMore
                                    ? LocalizedString.monitor("show_more", lang: settings.language)
                                    : LocalizedString.monitor("show_less", lang: settings.language)
                            )
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(canRevealMore ? 0 : 180))
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

    /// 副标题：进程总数 + CPU 占用最高的进程。
    /// 展开前后保持同一段文案，避免点击时表头文字跳动。
    private var subtitleText: String {
        guard metrics.totalCount > 0 else {
            return LocalizedString.monitor("process_waiting", lang: settings.language)
        }
        guard let top = topProcess else { return countText }
        return "\(countText) · \(top.name) \(top.cpuUsage.percentText)"
    }

    private var countAndTopNameText: String {
        guard metrics.totalCount > 0, let top = topProcess else { return countText }
        return "\(countText) · \(top.name)"
    }

    private var countText: String {
        guard metrics.totalCount > 0 else {
            return LocalizedString.monitor("process_waiting", lang: settings.language)
        }
        return "\(metrics.totalCount) \(LocalizedString.monitor("process_count_unit", lang: settings.language))"
    }

    private var topProcess: ProcessMetrics? {
        guard let top = metrics.processes.max(by: { $0.cpuUsage < $1.cpuUsage }),
              top.cpuUsage > 0 else { return nil }
        return top
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

    /// 按「分桶值 + 名称」排序：数值在同一档内时顺序稳定，
    /// 避免每秒采样都能让行位置来回跳动。
    private var sortedProcesses: [ProcessMetrics] {
        switch sortKey {
        case .cpu:
            metrics.processes.sorted { lhs, rhs in
                let left = (lhs.cpuUsage * 100).rounded()
                let right = (rhs.cpuUsage * 100).rounded()
                if left != right { return left > right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        case .memory:
            metrics.processes.sorted { lhs, rhs in
                let left = (Double(lhs.memoryBytes) / 1_048_576).rounded()
                let right = (Double(rhs.memoryBytes) / 1_048_576).rounded()
                if left != right { return left > right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var visibleLimit: Int {
        min(sortedProcesses.count, collapsedCount + extraRows)
    }

    /// 是否还有更多进程可以展开（且未达到上限）
    private var canRevealMore: Bool {
        visibleLimit < min(sortedProcesses.count, maxVisibleCount)
    }

    private var displayedProcesses: [ProcessMetrics] {
        Array(sortedProcesses.prefix(visibleLimit))
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

struct ProcessRow: View {
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

            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.vertical, 4)
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

struct ProcessIcon: View {
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

enum ProcessIconResolver {
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

struct ProcessFallbackIcon {
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

struct StorageSection: View {
    let metrics: StorageMetrics
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(sectionKey: .storage, icon: "externaldrive", title: LocalizedString.monitor("storage", lang: settings.language), value: metrics.usage.percentText) {
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

struct BatterySection: View {
    let metrics: BatteryMetrics
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(sectionKey: .battery, icon: batteryIcon, title: LocalizedString.monitor("battery", lang: settings.language), value: levelText) {
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

struct NetworkSection: View {
    let metrics: NetworkMetrics
    var downloadHistory: MetricHistory = MetricHistory()
    var uploadHistory: MetricHistory = MetricHistory()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(sectionKey: .network, icon: "network", title: LocalizedString.monitor("network", lang: settings.language), value: networkName) {
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

struct UptimeSection: View {
    let metrics: UptimeMetrics
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        CollapsibleSection(sectionKey: .uptime, icon: "clock", title: LocalizedString.monitor("uptime", lang: settings.language), value: metrics.compactFormatted) {
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

