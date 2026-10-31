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
    var snapshot = SystemSnapshot()

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
        snapshot = sampler.sample(
            includeProcesses: AppSettings.shared.showProcesses,
            mergeProcesses: AppSettings.shared.mergeProcesses
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

        SystemHistoryStore.shared.record(snapshot: snapshot)
    }
}
