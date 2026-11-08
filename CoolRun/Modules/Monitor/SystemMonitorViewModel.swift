import Foundation
import Observation

/// 历史数据追踪器，用于趋势图表
struct MetricHistory {
    private(set) var values: [Double] = []
    let maxCount: Int

    init(maxCount: Int = 60) {
        self.maxCount = maxCount
    }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > maxCount {
            values.removeFirst(values.count - maxCount)
        }
    }

    var latest: Double? { values.last }
}

@MainActor
@Observable
final class SystemMonitorViewModel {
    /// 采样范围。菜单栏常驻轮询用 `.light`——只要 CPU/内存/网速这几个便宜的
    /// Mach 调用；等面板真的弹出来再切 `.full`，把磁盘容量、温度、进程列表补上。
    ///
    /// 这么分是因为磁盘容量查询会走 APFS 卷角色枚举，一秒一次能把待机 CPU
    /// 顶到 5% 以上，而菜单栏根本不需要它。
    enum Scope {
        case light
        case full
    }

    var snapshot = SystemSnapshot()

    /// 面板是否可见。不可见时降级采样，并且不写历史（否则会存进一堆 0）。
    var scope: Scope = .light

    /// 历史数据
    var cpuHistory = MetricHistory()
    var memoryHistory = MetricHistory()
    var downloadHistory = MetricHistory()
    var uploadHistory = MetricHistory()
    var cpuTempHistory = MetricHistory()
    var gpuTempHistory = MetricHistory()

    private let sampler = SystemSampler()
    private var refreshTask: Task<Void, Never>?

    init() {
        refresh()
        start()
    }

    func start() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                let refreshInterval = AppSettings.shared.systemRefreshRate.duration
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        let isFull = scope == .full
        snapshot = sampler.sample(
            includeProcesses: isFull && AppSettings.shared.showProcesses,
            mergeProcesses: AppSettings.shared.mergeProcesses,
            includeStorage: isFull,
            includeSensors: isFull
        )

        // 更新历史数据
        cpuHistory.append(snapshot.cpu.usage)
        memoryHistory.append(snapshot.memory.usage)
        downloadHistory.append(Double(snapshot.network.downloadSpeed))
        uploadHistory.append(Double(snapshot.network.uploadSpeed))

        if let cpuTemp = snapshot.temperature.cpuTemperature {
            cpuTempHistory.append(cpuTemp)
        }
        if let gpuTemp = snapshot.temperature.gpuTemperature {
            gpuTempHistory.append(gpuTemp)
        }

        if isFull {
            SystemHistoryStore.shared.record(snapshot: snapshot)
        }
    }
}
