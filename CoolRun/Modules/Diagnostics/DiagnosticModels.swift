import Foundation
import Observation

enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case healthy
    case notice
    case warning
    case critical
    case unavailable

    var rank: Int {
        switch self {
        case .healthy: 0
        case .notice: 1
        case .warning: 2
        case .critical: 3
        case .unavailable: -1
        }
    }
}

enum DiagnosticCheckState: String, Codable, Sendable {
    case success
    case warning
    case failure
    case unavailable
    case skipped
}

struct SleepBlocker: Codable, Equatable, Identifiable, Sendable {
    let owner: String
    let processID: Int?
    let assertionType: String
    let reason: String?

    var id: String {
        "\(processID ?? -1)|\(owner)|\(assertionType)|\(reason ?? "")"
    }
}

struct SleepDiagnosticSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let severity: DiagnosticSeverity
    let blockers: [SleepBlocker]
    let windowStart: Date?
    let windowEnd: Date?
    let sleepCount: Int
    let wakeCount: Int
    let darkWakeCount: Int
    let batteryStartPercent: Int?
    let batteryEndPercent: Int?
    let unavailableChecks: [String]

    var batteryDropPercentagePoints: Int? {
        guard let batteryStartPercent, let batteryEndPercent else { return nil }
        return max(batteryStartPercent - batteryEndPercent, 0)
    }

    var observationDuration: TimeInterval? {
        guard let windowStart, let windowEnd, windowEnd >= windowStart else { return nil }
        return windowEnd.timeIntervalSince(windowStart)
    }
}

enum NetworkCheckKind: String, Codable, CaseIterable, Sendable {
    case interface
    case gateway
    case dns
    case ping
    case https
    case vpn
}

struct NetworkCheckResult: Codable, Equatable, Identifiable, Sendable {
    let kind: NetworkCheckKind
    let state: DiagnosticCheckState
    let detail: String
    let durationMilliseconds: Double?

    var id: NetworkCheckKind { kind }
}

enum NetworkLikelyCause: String, Codable, Sendable {
    case none
    case localInterface
    case gateway
    case dns
    case internet
    case unstable
    case partial
}

struct NetworkDiagnosticSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let severity: DiagnosticSeverity
    let interfaceName: String?
    let localAddress: String?
    let gateway: String?
    let vpnActive: Bool
    let latencyMilliseconds: Double?
    let packetLossPercent: Double?
    let likelyCause: NetworkLikelyCause
    let checks: [NetworkCheckResult]
}

enum StorageInsightCategory: String, CaseIterable, Codable, Sendable {
    case caches
    case logs
    case applicationSupport
    case containers
    case developer
    case deviceBackups
}

struct StorageHotspot: Equatable, Identifiable, Sendable {
    let url: URL
    let allocatedBytes: UInt64
    let inaccessibleCount: Int
    let skippedCloudItemCount: Int
    let reachedEntryLimit: Bool

    var id: URL { url }
}

struct StorageInsightItem: Equatable, Identifiable, Sendable {
    let category: StorageInsightCategory
    let url: URL
    let allocatedBytes: UInt64
    let hotspots: [StorageHotspot]
    let inaccessibleCount: Int
    let skippedCloudItemCount: Int
    let reachedEntryLimit: Bool

    var id: StorageInsightCategory { category }
}

struct StorageScanResult: Equatable, Sendable {
    let timestamp: Date
    let items: [StorageInsightItem]
    let duration: TimeInterval

    var allocatedBytes: UInt64 {
        items.reduce(0) { $0 &+ $1.allocatedBytes }
    }

    var inaccessibleCount: Int {
        items.reduce(0) { $0 + $1.inaccessibleCount }
    }

    var isPartial: Bool {
        inaccessibleCount > 0 || items.contains(where: \.reachedEntryLimit)
    }
}

struct AppResidueCandidate: Equatable, Identifiable, Sendable {
    let identifier: String
    let url: URL
    let allocatedBytes: UInt64
    let modifiedAt: Date
    let sourceCategory: StorageInsightCategory

    var id: URL { url }
}

struct AppResidueScanResult: Equatable, Sendable {
    let timestamp: Date
    let candidates: [AppResidueCandidate]
    let inspectedEntryCount: Int
    let excludedEntryCount: Int
    let inaccessibleCount: Int
}

struct AppResidueCleanupFailure: Equatable, Identifiable, Sendable {
    let url: URL
    let message: String

    var id: URL { url }
}

struct AppResidueCleanupReport: Equatable, Sendable {
    let trashedURLs: [URL]
    let failures: [AppResidueCleanupFailure]
}

private struct DiagnosticsHistoryArchive: Codable {
    var sleep: [SleepDiagnosticSummary] = []
    var network: [NetworkDiagnosticSummary] = []
}

@MainActor
@Observable
final class DiagnosticsHistoryStore {
    static let shared = DiagnosticsHistoryStore(
        fileURL: GoldDataStorage.fileURL(named: "diagnostics_history.json")
    )

    private(set) var sleepHistory: [SleepDiagnosticSummary] = []
    private(set) var networkHistory: [NetworkDiagnosticSummary] = []

    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    func record(_ summary: SleepDiagnosticSummary) {
        sleepHistory.insert(summary, at: 0)
        sleepHistory = Array(Self.retainedSleep(sleepHistory).prefix(20))
        save()
    }

    func record(_ summary: NetworkDiagnosticSummary) {
        networkHistory.insert(summary, at: 0)
        networkHistory = Array(Self.retainedNetwork(networkHistory).prefix(30))
        save()
    }

    func clear() {
        sleepHistory = []
        networkHistory = []
        save()
    }

    nonisolated static func retainedSleep(
        _ values: [SleepDiagnosticSummary],
        now: Date = Date()
    ) -> [SleepDiagnosticSummary] {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        return values
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }

    nonisolated static func retainedNetwork(
        _ values: [NetworkDiagnosticSummary],
        now: Date = Date()
    ) -> [NetworkDiagnosticSummary] {
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        return values
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let archive = try? JSONDecoder().decode(DiagnosticsHistoryArchive.self, from: data) else { return }
        sleepHistory = Array(Self.retainedSleep(archive.sleep).prefix(20))
        networkHistory = Array(Self.retainedNetwork(archive.network).prefix(30))
    }

    private func save() {
        guard let fileURL else { return }
        let archive = DiagnosticsHistoryArchive(sleep: sleepHistory, network: networkHistory)
        guard let data = try? JSONEncoder().encode(archive) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
