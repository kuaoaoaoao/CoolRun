import Foundation
import Observation

struct SystemHistorySample: Codable, Identifiable, Equatable, Sendable {
    var id: Date { timestamp }
    let timestamp: Date
    let cpuUsage: Double
    let memoryUsage: Double
    let storageUsage: Double
    let downloadSpeed: UInt64
    let uploadSpeed: UInt64
    let cpuTemperature: Double?
    let gpuTemperature: Double?
}

enum SystemAnomalyKind: String, Codable, CaseIterable, Sendable {
    case cpu
    case memory
    case storage
    case temperature

    var reminderKind: LocalReminderKind {
        switch self {
        case .cpu: .systemCPU
        case .memory: .systemMemory
        case .storage: .systemStorage
        case .temperature: .systemTemperature
        }
    }

    var icon: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .storage: "externaldrive.fill"
        case .temperature: "thermometer.high"
        }
    }
}

struct SystemAnomalyEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: SystemAnomalyKind
    let severity: TodaySeverity
    let value: Double
    let topProcessName: String?
}

private struct SystemHistoryArchive: Codable {
    var samples: [SystemHistorySample] = []
    var anomalies: [SystemAnomalyEvent] = []
}

@MainActor
@Observable
final class SystemHistoryStore {
    static let shared = SystemHistoryStore(fileURL: GoldDataStorage.fileURL(named: "system_history.json"))

    private(set) var samples: [SystemHistorySample] = []
    private(set) var anomalies: [SystemAnomalyEvent] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var lastPersistedAt: Date?
    @ObservationIgnored private var sustainedCounts: [SystemAnomalyKind: Int] = [:]
    @ObservationIgnored private var lastAnomalyAt: [SystemAnomalyKind: Date] = [:]

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    func record(snapshot: SystemSnapshot, now: Date = Date()) {
        evaluateAnomalies(snapshot: snapshot, now: now)

        if let lastPersistedAt, now.timeIntervalSince(lastPersistedAt) < 5 * 60 { return }
        samples.append(SystemHistorySample(
            timestamp: now,
            cpuUsage: snapshot.cpu.usage,
            memoryUsage: snapshot.memory.usage,
            storageUsage: snapshot.storage.usage,
            downloadSpeed: snapshot.network.downloadSpeed,
            uploadSpeed: snapshot.network.uploadSpeed,
            cpuTemperature: snapshot.temperature.cpuTemperature,
            gpuTemperature: snapshot.temperature.gpuTemperature
        ))
        lastPersistedAt = now
        prune(now: now)
        save()
    }

    func recentSamples(hours: Int, now: Date = Date()) -> [SystemHistorySample] {
        let cutoff = now.addingTimeInterval(-TimeInterval(max(hours, 1) * 60 * 60))
        return samples.filter { $0.timestamp >= cutoff }
    }

    func clear() {
        samples = []
        anomalies = []
        sustainedCounts = [:]
        lastAnomalyAt = [:]
        lastPersistedAt = nil
        save()
    }

    nonisolated static func retained(
        samples: [SystemHistorySample],
        anomalies: [SystemAnomalyEvent],
        now: Date
    ) -> (samples: [SystemHistorySample], anomalies: [SystemAnomalyEvent]) {
        let sampleCutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let anomalyCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        return (
            samples.filter { $0.timestamp >= sampleCutoff }.sorted { $0.timestamp < $1.timestamp },
            anomalies.filter { $0.timestamp >= anomalyCutoff }.sorted { $0.timestamp > $1.timestamp }
        )
    }

    private func evaluateAnomalies(snapshot: SystemSnapshot, now: Date) {
        let hottest = [snapshot.temperature.cpuTemperature, snapshot.temperature.gpuTemperature]
            .compactMap { $0 }
            .max() ?? 0
        let candidates: [(SystemAnomalyKind, Double, Double)] = [
            (.cpu, snapshot.cpu.usage, 0.9),
            (.memory, snapshot.memory.usage, 0.9),
            (.storage, snapshot.storage.usage, 0.95),
            (.temperature, hottest, 95)
        ]

        for (kind, value, threshold) in candidates {
            guard value >= threshold else {
                sustainedCounts[kind] = 0
                continue
            }
            let count = (sustainedCounts[kind] ?? 0) + 1
            sustainedCounts[kind] = count
            guard count == 3 else { continue }
            if let last = lastAnomalyAt[kind], now.timeIntervalSince(last) < 60 * 60 { continue }

            lastAnomalyAt[kind] = now
            let topProcess = kind == .cpu
                ? snapshot.processes.processes.max(by: { $0.cpuUsage < $1.cpuUsage })?.name
                : kind == .memory
                    ? snapshot.processes.processes.max(by: { $0.memoryBytes < $1.memoryBytes })?.name
                    : nil
            let event = SystemAnomalyEvent(
                id: UUID(),
                timestamp: now,
                kind: kind,
                severity: .critical,
                value: value,
                topProcessName: topProcess
            )
            anomalies.insert(event, at: 0)
            prune(now: now)
            save()
            notify(event)
        }
    }

    private func notify(_ event: SystemAnomalyEvent) {
        let lang = AppSettings.shared.language
        let name: String
        let valueText: String
        switch event.kind {
        case .cpu:
            name = "CPU"
            valueText = String(format: "%.0f%%", event.value * 100)
        case .memory:
            name = LocalizedString.l(lang, en: "Memory", zh: "内存", ja: "メモリ", ko: "메모리")
            valueText = String(format: "%.0f%%", event.value * 100)
        case .storage:
            name = LocalizedString.l(lang, en: "Storage", zh: "储存", ja: "ストレージ", ko: "저장 공간")
            valueText = String(format: "%.0f%%", event.value * 100)
        case .temperature:
            name = LocalizedString.l(lang, en: "Temperature", zh: "温度", ja: "温度", ko: "온도")
            valueText = String(format: "%.0f°C", event.value)
        }
        let suffix = event.topProcessName.map { " · \($0)" } ?? ""
        LocalReminderCenter.shared.notifySystemAnomaly(
            kind: event.kind.reminderKind,
            title: LocalizedString.l(lang, en: "Mac needs attention", zh: "Mac 状态需要关注", ja: "Mac の状態を確認", ko: "Mac 상태 확인 필요"),
            body: "\(name) \(valueText)\(suffix)",
            now: event.timestamp
        )
    }

    private func prune(now: Date) {
        let retained = Self.retained(samples: samples, anomalies: anomalies, now: now)
        samples = retained.samples
        anomalies = retained.anomalies
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(SystemHistoryArchive.self, from: data) else { return }
        let retained = Self.retained(samples: archive.samples, anomalies: archive.anomalies, now: Date())
        samples = retained.samples
        anomalies = retained.anomalies
        lastPersistedAt = samples.last?.timestamp
        for event in anomalies {
            lastAnomalyAt[event.kind] = max(lastAnomalyAt[event.kind] ?? .distantPast, event.timestamp)
        }
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(SystemHistoryArchive(samples: samples, anomalies: anomalies)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
