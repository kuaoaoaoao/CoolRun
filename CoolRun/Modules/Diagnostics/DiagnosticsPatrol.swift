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
        let lang = AppSettings.shared.language
        let free = Self.formattedBytes(storage.available)
        let percent = Int(usage * 100)
        let title = usage >= 0.95
            ? LocalizedString.l(lang, en: "Disk is almost full", zh: "磁盘就快满了", ja: "ディスクがほぼ満杯です", ko: "디스크가 거의 가득 찼습니다")
            : LocalizedString.l(lang, en: "Disk space is running low", zh: "磁盘不太够了", ja: "ディスクの空きが少なくなっています", ko: "디스크 공간이 부족합니다")
        let detail = LocalizedString.l(
            lang,
            en: "Only \(free) left (\(percent)% used). Check Diagnostics for what can be cleaned.",
            zh: "只剩 \(free) 可用（已用 \(percent)%），去诊断里看看能清什么。",
            ja: "空きは \(free) のみ（\(percent)% 使用中）。診断で何を削除できるか確認してください。",
            ko: "\(free)만 남았습니다(\(percent)% 사용 중). 진단에서 무엇을 정리할 수 있는지 확인하세요."
        )
        return Finding(
            id: "storage",
            title: title,
            detail: detail,
            severity: usage >= 0.95 ? .critical : .warning
        )
    }

    private func memoryFinding(_ memory: MemoryMetrics) -> Finding? {
        guard memory.usage >= 0.92 else { return nil }
        let lang = AppSettings.shared.language
        let used = Self.formattedBytes(memory.used)
        let percent = Int(memory.usage * 100)
        return Finding(
            id: "memory",
            title: LocalizedString.l(lang, en: "Memory is nearly exhausted", zh: "内存快撑不住了", ja: "メモリがほぼ限界です", ko: "메모리가 거의 한계입니다"),
            detail: LocalizedString.l(
                lang,
                en: "\(used) used (\(percent)%). Some process is quietly eating memory.",
                zh: "已用 \(used)（\(percent)%），有程序在偷偷吃内存。",
                ja: "\(used) 使用中（\(percent)%）。メモリを密かに消費しているプロセスがあります。",
                ko: "\(used) 사용 중(\(percent)%). 몰래 메모리를 먹는 프로세스가 있습니다."
            ),
            severity: .warning
        )
    }

    private func sleepFinding(_ summary: SleepDiagnosticSummary) -> Finding {
        let lang = AppSettings.shared.language
        let drop = summary.batteryDropPercentagePoints ?? 0
        let blocker = summary.blockers.first?.owner
        let detail: String
        if drop >= 5 {
            detail = LocalizedString.l(
                lang,
                en: "Battery dropped \(drop)% while the lid was closed. Some process may not be sleeping.",
                zh: "合盖期间掉了 \(drop)% 电，可能有程序没睡。",
                ja: "フタを閉じている間に \(drop)% 減りました。スリープしていないプロセスがある可能性があります。",
                ko: "덮개를 닫은 동안 \(drop)% 줄었습니다. 잠들지 않은 프로세스가 있을 수 있습니다."
            )
        } else if let blocker {
            detail = LocalizedString.l(
                lang,
                en: "\"\(blocker)\" keeps preventing sleep.",
                zh: "「\(blocker)」一直拦着不让睡。",
                ja: "「\(blocker)」がスリープを妨げ続けています。",
                ko: "「\(blocker)」이(가) 계속 잠들지 못하게 합니다."
            )
        } else {
            detail = LocalizedString.l(
                lang,
                en: "Sleep records show an anomaly. Check Diagnostics.",
                zh: "睡眠记录里有异常，去诊断里看看。",
                ja: "スリープ記録に異常があります。診断を確認してください。",
                ko: "잠자기 기록에 이상이 있습니다. 진단에서 확인하세요."
            )
        }
        return Finding(
            id: "sleep",
            title: LocalizedString.l(lang, en: "Sleep looks off", zh: "睡眠不太对劲", ja: "スリープに問題があります", ko: "잠자기에 문제가 있습니다"),
            detail: detail,
            severity: summary.severity
        )
    }

    private func networkFinding(_ summary: NetworkDiagnosticSummary) -> Finding {
        let lang = AppSettings.shared.language
        let detail: String
        switch summary.likelyCause {
        case .dns:
            detail = LocalizedString.l(
                lang,
                en: "DNS resolution is failing, so web pages keep spinning.",
                zh: "DNS 解析有问题，网页会转圈。",
                ja: "DNS 解決に問題があり、Web ページが読み込まれません。",
                ko: "DNS 조회에 문제가 있어 웹 페이지가 계속 로딩됩니다."
            )
        case .gateway:
            detail = LocalizedString.l(
                lang,
                en: "The router hop is unreachable. Check Wi-Fi first.",
                zh: "路由器这一跳不通，先看看 Wi-Fi。",
                ja: "ルーターの区間に到達できません。まず Wi-Fi を確認してください。",
                ko: "라우터 구간에 도달할 수 없습니다. 먼저 Wi-Fi를 확인하세요."
            )
        case .internet:
            detail = LocalizedString.l(
                lang,
                en: "Connected but no internet. The carrier may be the cause.",
                zh: "连上了但出不去，可能是运营商。",
                ja: "接続はできていますが外部に出られません。回線事業者の可能性があります。",
                ko: "연결은 되었지만 외부로 나갈 수 없습니다. 통신사 문제일 수 있습니다."
            )
        case .unstable:
            let loss = Int(summary.packetLossPercent ?? 0)
            detail = LocalizedString.l(
                lang,
                en: "\(loss)% packet loss, the connection is unstable.",
                zh: "丢包 \(loss)%，网络在抖。",
                ja: "パケット損失 \(loss)%、接続が不安定です。",
                ko: "패킷 손실 \(loss)%, 연결이 불안정합니다."
            )
        case .localInterface:
            detail = LocalizedString.l(
                lang,
                en: "The network interface itself is down.",
                zh: "网卡本身没起来。",
                ja: "ネットワークインターフェイス自体が起動していません。",
                ko: "네트워크 인터페이스 자체가 올라오지 않았습니다."
            )
        case .partial, .none:
            detail = LocalizedString.l(
                lang,
                en: "Some network checks did not pass.",
                zh: "有几项网络检查没通过。",
                ja: "一部のネットワークチェックが通りませんでした。",
                ko: "일부 네트워크 검사를 통과하지 못했습니다."
            )
        }
        return Finding(
            id: "network",
            title: LocalizedString.l(lang, en: "Network has an issue", zh: "网络有点问题", ja: "ネットワークに問題があります", ko: "네트워크에 문제가 있습니다"),
            detail: detail,
            severity: summary.severity
        )
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
        let lang = AppSettings.shared.language
        content.title = urgent.count == 1
            ? urgent[0].title
            : LocalizedString.l(
                lang,
                en: "Checkup found \(urgent.count) issues",
                zh: "体检发现 \(urgent.count) 个问题",
                ja: "診断で \(urgent.count) 件の問題を検出",
                ko: "진단에서 \(urgent.count)개 문제 발견"
            )
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
