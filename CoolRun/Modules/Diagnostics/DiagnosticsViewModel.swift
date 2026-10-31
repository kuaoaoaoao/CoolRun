import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsViewModel {
    static let shared = DiagnosticsViewModel(historyStore: .shared)

    private(set) var latestSleep: SleepDiagnosticSummary?
    private(set) var latestNetwork: NetworkDiagnosticSummary?
    private(set) var storageResult: StorageScanResult?
    private(set) var residueResult: AppResidueScanResult?
    private(set) var residueCleanupReport: AppResidueCleanupReport?
    private(set) var isRunningSleep = false
    private(set) var isRunningNetwork = false
    private(set) var isScanningStorage = false
    private(set) var isScanningResidue = false
    private(set) var isCleaningResidue = false
    private(set) var storageProgress: Double = 0
    private(set) var storageScannedEntryCount = 0
    private(set) var storageCurrentCategory: StorageInsightCategory?
    private(set) var lastOperationError: String?

    @ObservationIgnored private let historyStore: DiagnosticsHistoryStore
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?
    @ObservationIgnored private var storageTask: Task<Void, Never>?
    @ObservationIgnored private var residueTask: Task<Void, Never>?
    @ObservationIgnored private var storageScanID: UUID?

    init(historyStore: DiagnosticsHistoryStore) {
        self.historyStore = historyStore
        latestSleep = historyStore.sleepHistory.first
        latestNetwork = historyStore.networkHistory.first
    }

    var sleepHistory: [SleepDiagnosticSummary] { historyStore.sleepHistory }
    var networkHistory: [NetworkDiagnosticSummary] { historyStore.networkHistory }

    func runSleepDiagnostics() {
        guard !isRunningSleep else { return }
        sleepTask?.cancel()
        isRunningSleep = true
        lastOperationError = nil
        sleepTask = Task {
            let summary = await SleepDiagnosticsService.run()
            guard !Task.isCancelled else { return }
            latestSleep = summary
            historyStore.record(summary)
            isRunningSleep = false
        }
    }

    func runNetworkDiagnostics() {
        guard !isRunningNetwork else { return }
        networkTask?.cancel()
        isRunningNetwork = true
        lastOperationError = nil
        networkTask = Task {
            let summary = await NetworkDiagnosticsService.run()
            guard !Task.isCancelled else { return }
            latestNetwork = summary
            historyStore.record(summary)
            isRunningNetwork = false
        }
    }

    func scanStorage() {
        guard !isScanningStorage else { return }
        storageTask?.cancel()
        let scanID = UUID()
        storageScanID = scanID
        isScanningStorage = true
        storageProgress = 0
        storageScannedEntryCount = 0
        storageCurrentCategory = nil
        lastOperationError = nil
        let model = self
        storageTask = Task {
            let result = await StorageDiagnosticsService.scan { progress in
                Task { @MainActor in
                    guard model.storageScanID == scanID else { return }
                    model.storageProgress = progress.fractionCompleted
                    model.storageScannedEntryCount = progress.visitedEntryCount
                    model.storageCurrentCategory = progress.currentCategory
                }
            }
            guard !Task.isCancelled, storageScanID == scanID else { return }
            storageResult = result
            storageProgress = 1
            storageCurrentCategory = nil
            isScanningStorage = false
            storageScanID = nil
            storageTask = nil
        }
    }

    func cancelStorageScan() {
        guard isScanningStorage else { return }
        storageScanID = nil
        storageTask?.cancel()
        storageTask = nil
        isScanningStorage = false
        storageProgress = 0
        storageScannedEntryCount = 0
        storageCurrentCategory = nil
    }

    func scanResidue() {
        guard !isScanningResidue else { return }
        residueTask?.cancel()
        isScanningResidue = true
        residueCleanupReport = nil
        lastOperationError = nil
        residueTask = Task {
            let result = await AppResidueService.scan()
            guard !Task.isCancelled else { return }
            residueResult = result
            isScanningResidue = false
        }
    }

    func trashResidue(urls: Set<URL>) {
        guard !urls.isEmpty, !isCleaningResidue else { return }
        isCleaningResidue = true
        residueCleanupReport = nil
        Task {
            let report = await AppResidueService.trash(urls: Array(urls))
            residueCleanupReport = report
            if var current = residueResult {
                let trashed = Set(report.trashedURLs)
                current = AppResidueScanResult(
                    timestamp: current.timestamp,
                    candidates: current.candidates.filter { !trashed.contains($0.url) },
                    inspectedEntryCount: current.inspectedEntryCount,
                    excludedEntryCount: current.excludedEntryCount,
                    inaccessibleCount: current.inaccessibleCount
                )
                residueResult = current
            }
            isCleaningResidue = false
        }
    }
}
