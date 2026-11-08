import Foundation
import UserNotifications

/// 后台体检：隔一段时间自己看一眼，只有真有问题才出声。
///
/// 设计上刻意保守——
/// - 只报 `warning` 及以上，`notice` 这种「顺带一提」不进通知；
/// - 同一天最多推一条，避免反复打扰；
/// - 每轮之间隔 6 小时，启动后先等 20 秒，不和冷启动抢资源。
@MainActor
@Observable
final class DiagnosticsPatrol {
    static let shared = DiagnosticsPatrol()

    struct Finding: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let detail: String
        let severity: DiagnosticSeverity
    }

    private enum Keys {
        static let enabled = "patrol.enabled"
        static let lastRun = "patrol.lastRun"
        static let lastNotified = "patrol.lastNotified"
    }

    private nonisolated static let interval: TimeInterval = 6 * 60 * 60
    private nonisolated static let startupDelay: TimeInterval = 20

    private(set) var findings: [Finding] = []
    private(set) var lastRunAt: Date?
    private(set) var isRunning = false
    private(set) var lastError: String?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    @ObservationIgnored private var loop: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        if let stamp = defaults.object(forKey: Keys.lastRun) as? Date {
            lastRunAt = stamp
        }
    }

    func start() {
        guard isEnabled, loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.startupDelay))
            while !Task.isCancelled {
                await self?.runNow()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func runNow() async {
        guard isEnabled, !isRunning else { return }
        isRunning = true
        lastError = nil

        var collected: [Finding] = []
        let snapshot = SystemSampler().sample(includeProcesses: false, mergeProcesses: false)

        if let storage = storageFinding(snapshot.storage) {
            collected.append(storage)
        }
        if let memory = memoryFinding(snapshot.memory) {
            collected.append(memory)
        }

        let sleep = await SleepDiagnosticsService.run()
        if sleep.severity.rank >= DiagnosticSeverity.warning.rank {
            collected.append(sleepFinding(sleep))
        }

        let network = await NetworkDiagnosticsService.run()
        if network.severity.rank >= DiagnosticSeverity.warning.rank {
            collected.append(networkFinding(network))
        }

        findings = collected
        lastRunAt = Date()
        isRunning = false
        UserDefaults.standard.set(lastRunAt, forKey: Keys.lastRun)

        await notifyIfNeeded(collected)
    }

    // MARK: - 各项检查

    private func storageFinding(_ storage: StorageMetrics) -> Finding? {
        let usage = storage.usage
        guard usage >= 0.88 else { return nil }
        let free = Self.formattedBytes(storage.available)
        let title = usage >= 0.95 ? "磁盘就快满了" : "磁盘不太够了"
        let detail = "只剩 \(free) 可用（已用 \(Int(usage * 100))%），去诊断里看看能清什么。"
        return Finding(
            id: "storage",
            title: title,
            detail: detail,
            severity: usage >= 0.95 ? .critical : .warning
        )
    }

    private func memoryFinding(_ memory: MemoryMetrics) -> Finding? {
        guard memory.usage >= 0.92 else { return nil }
        let used = Self.formattedBytes(memory.used)
        return Finding(
            id: "memory",
            title: "内存快撑不住了",
            detail: "已用 \(used)（\(Int(memory.usage * 100))%），有程序在偷偷吃内存。",
            severity: .warning
        )
    }

    private func sleepFinding(_ summary: SleepDiagnosticSummary) -> Finding {
        let drop = summary.batteryDropPercentagePoints ?? 0
        let blocker = summary.blockers.first?.owner
        let detail: String
        if drop >= 5 {
            detail = "合盖期间掉了 \(drop)% 电，可能有程序没睡。"
        } else if let blocker {
            detail = "「\(blocker)」一直拦着不让睡。"
        } else {
            detail = "睡眠记录里有异常，去诊断里看看。"
        }
        return Finding(id: "sleep", title: "睡眠不太对劲", detail: detail, severity: summary.severity)
    }

    private func networkFinding(_ summary: NetworkDiagnosticSummary) -> Finding {
        let detail: String
        switch summary.likelyCause {
        case .dns: detail = "DNS 解析有问题，网页会转圈。"
        case .gateway: detail = "路由器这一跳不通，先看看 Wi-Fi。"
        case .internet: detail = "连上了但出不去，可能是运营商。"
        case .unstable: detail = "丢包 \(Int(summary.packetLossPercent ?? 0))%，网络在抖。"
        case .localInterface: detail = "网卡本身没起来。"
        case .partial, .none: detail = "有几项网络检查没通过。"
        }
        return Finding(id: "network", title: "网络有点问题", detail: detail, severity: summary.severity)
    }

    // MARK: - 通知

    private func notifyIfNeeded(_ items: [Finding]) async {
        let urgent = items.filter { $0.severity.rank >= DiagnosticSeverity.warning.rank }
        guard !urgent.isEmpty else { return }

        let calendar = Calendar.current
        if let last = UserDefaults.standard.object(forKey: Keys.lastNotified) as? Date,
           calendar.isDateInToday(last) {
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = urgent.count == 1 ? urgent[0].title : "体检发现 \(urgent.count) 个问题"
        content.body = urgent.prefix(2).map(\.detail).joined(separator: "\n")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "coolrun.patrol",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            UserDefaults.standard.set(Date(), forKey: Keys.lastNotified)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - 工具

    nonisolated static func formattedBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
