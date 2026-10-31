import Foundation

struct DirectoryMeasurement: Equatable, Sendable {
    let allocatedBytes: UInt64
    let inaccessibleCount: Int
    let skippedCloudItemCount: Int
    let reachedEntryLimit: Bool
    let visitedEntryCount: Int
}

struct StorageScanProgress: Equatable, Sendable {
    let currentCategory: StorageInsightCategory
    let fractionCompleted: Double
    let visitedEntryCount: Int
}

enum DiagnosticDirectorySizer {
    nonisolated static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isUbiquitousItemKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey
    ]

    nonisolated static func measure(
        url: URL,
        excluding excludedURLs: [URL] = [],
        maxEntries: Int = 250_000,
        fileManager: FileManager = .default,
        progressBatchSize: Int = 2_048,
        batchPause: TimeInterval = 0,
        progress: (_ visitedEntryCount: Int) -> Void = { _ in }
    ) -> DirectoryMeasurement {
        let normalizedRoot = url.standardizedFileURL
        let normalizedExclusions = excludedURLs.map(\.standardizedFileURL.path)
        guard fileManager.fileExists(atPath: normalizedRoot.path) else {
            return DirectoryMeasurement(
                allocatedBytes: 0,
                inaccessibleCount: 0,
                skippedCloudItemCount: 0,
                reachedEntryLimit: false,
                visitedEntryCount: 0
            )
        }

        var inaccessibleCount = 0
        guard let enumerator = fileManager.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in
                inaccessibleCount += 1
                return true
            }
        ) else {
            return DirectoryMeasurement(
                allocatedBytes: 0,
                inaccessibleCount: 1,
                skippedCloudItemCount: 0,
                reachedEntryLimit: false,
                visitedEntryCount: 0
            )
        }

        var allocatedBytes: UInt64 = 0
        var skippedCloudItems = 0
        var visitedEntries = 0
        var reachedLimit = false
        let limit = max(maxEntries, 1)

        let batchSize = max(progressBatchSize, 1)
        for case let itemURL as URL in enumerator {
            if Task.isCancelled { break }
            let normalizedPath = itemURL.path
            if normalizedExclusions.contains(where: { normalizedPath == $0 || normalizedPath.hasPrefix($0 + "/") }) {
                enumerator.skipDescendants()
                continue
            }

            if visitedEntries >= limit {
                reachedLimit = true
                break
            }
            visitedEntries += 1

            autoreleasepool {
                do {
                    let values = try itemURL.resourceValues(forKeys: resourceKeys)
                    if values.isSymbolicLink == true {
                        enumerator.skipDescendants()
                    } else if values.isUbiquitousItem == true {
                        skippedCloudItems += 1
                        enumerator.skipDescendants()
                    } else if values.isRegularFile == true {
                        let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
                        if bytes > 0 {
                            allocatedBytes = allocatedBytes &+ UInt64(bytes)
                        }
                    }
                } catch {
                    inaccessibleCount += 1
                }
            }

            if visitedEntries.isMultiple(of: batchSize) {
                progress(visitedEntries)
                if batchPause > 0 {
                    Thread.sleep(forTimeInterval: batchPause)
                }
            }
        }
        progress(visitedEntries)

        return DirectoryMeasurement(
            allocatedBytes: allocatedBytes,
            inaccessibleCount: inaccessibleCount,
            skippedCloudItemCount: skippedCloudItems,
            reachedEntryLimit: reachedLimit,
            visitedEntryCount: visitedEntries
        )
    }

    nonisolated static func isSafeDescendant(_ url: URL, of root: URL) -> Bool {
        let candidatePath = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath != rootPath && candidatePath.hasPrefix(rootPath + "/")
    }
}

private struct StorageScanDescriptor: Sendable {
    let category: StorageInsightCategory
    let url: URL
    let excludedURLs: [URL]
}

enum StorageDiagnosticsService {
    nonisolated static let maxEntriesPerCategory = 120_000
    nonisolated static let maxEntriesPerHotspot = 40_000

    nonisolated static func scan(
        progress: @escaping @Sendable (StorageScanProgress) -> Void
    ) async -> StorageScanResult {
        let worker = Task.detached(priority: .background) {
            let startedAt = Date()
            let descriptors = descriptors(home: FileManager.default.homeDirectoryForCurrentUser)
            var items: [StorageInsightItem] = []
            var visitedEntryCount = 0

            for (index, descriptor) in descriptors.enumerated() {
                if Task.isCancelled { break }
                progress(StorageScanProgress(
                    currentCategory: descriptor.category,
                    fractionCompleted: Double(index) / Double(descriptors.count),
                    visitedEntryCount: visitedEntryCount
                ))
                let scanned = scan(descriptor: descriptor) { categoryVisitedEntryCount in
                    let categoryFraction = min(
                        Double(categoryVisitedEntryCount) / Double(maxEntriesPerCategory),
                        0.95
                    )
                    progress(StorageScanProgress(
                        currentCategory: descriptor.category,
                        fractionCompleted: (Double(index) + categoryFraction) / Double(descriptors.count),
                        visitedEntryCount: visitedEntryCount + categoryVisitedEntryCount
                    ))
                }
                items.append(scanned.item)
                visitedEntryCount += scanned.visitedEntryCount
                progress(StorageScanProgress(
                    currentCategory: descriptor.category,
                    fractionCompleted: Double(index + 1) / Double(descriptors.count),
                    visitedEntryCount: visitedEntryCount
                ))
            }

            return StorageScanResult(
                timestamp: Date(),
                items: items.sorted { $0.allocatedBytes > $1.allocatedBytes },
                duration: Date().timeIntervalSince(startedAt)
            )
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated static func configuredRoots(home: URL) -> [StorageInsightCategory: URL] {
        Dictionary(uniqueKeysWithValues: descriptors(home: home).map { ($0.category, $0.url) })
    }

    nonisolated private static func descriptors(home: URL) -> [StorageScanDescriptor] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let appSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        let deviceBackups = appSupport
            .appendingPathComponent("MobileSync", isDirectory: true)
            .appendingPathComponent("Backup", isDirectory: true)
        return [
            StorageScanDescriptor(
                category: .caches,
                url: library.appendingPathComponent("Caches", isDirectory: true),
                excludedURLs: []
            ),
            StorageScanDescriptor(
                category: .logs,
                url: library.appendingPathComponent("Logs", isDirectory: true),
                excludedURLs: []
            ),
            StorageScanDescriptor(
                category: .applicationSupport,
                url: appSupport,
                excludedURLs: [deviceBackups]
            ),
            StorageScanDescriptor(
                category: .containers,
                url: library.appendingPathComponent("Containers", isDirectory: true),
                excludedURLs: []
            ),
            StorageScanDescriptor(
                category: .developer,
                url: library.appendingPathComponent("Developer", isDirectory: true),
                excludedURLs: []
            ),
            StorageScanDescriptor(
                category: .deviceBackups,
                url: deviceBackups,
                excludedURLs: []
            )
        ]
    }

    nonisolated private static func scan(
        descriptor: StorageScanDescriptor,
        progress: (_ visitedEntryCount: Int) -> Void
    ) -> (item: StorageInsightItem, visitedEntryCount: Int) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: descriptor.url.path) else {
            return (
                StorageInsightItem(
                    category: descriptor.category,
                    url: descriptor.url,
                    allocatedBytes: 0,
                    hotspots: [],
                    inaccessibleCount: 0,
                    skippedCloudItemCount: 0,
                    reachedEntryLimit: false
                ),
                0
            )
        }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: descriptor.url,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isUbiquitousItemKey],
                options: []
            )
        } catch {
            return (
                StorageInsightItem(
                    category: descriptor.category,
                    url: descriptor.url,
                    allocatedBytes: 0,
                    hotspots: [],
                    inaccessibleCount: 1,
                    skippedCloudItemCount: 0,
                    reachedEntryLimit: false
                ),
                0
            )
        }

        var hotspots: [StorageHotspot] = []
        var totalBytes: UInt64 = 0
        var inaccessibleCount = 0
        var skippedCloudItems = 0
        var reachedLimit = false
        var visitedEntryCount = 0
        var remainingEntryBudget = maxEntriesPerCategory

        for child in children {
            if Task.isCancelled || remainingEntryBudget <= 0 {
                reachedLimit = true
                break
            }
            if descriptor.excludedURLs.contains(where: { child.standardizedFileURL == $0.standardizedFileURL }) {
                continue
            }
            let exclusions = descriptor.excludedURLs.filter {
                DiagnosticDirectorySizer.isSafeDescendant($0, of: child)
            }
            let visitedBeforeChild = visitedEntryCount
            let measurement = DiagnosticDirectorySizer.measure(
                url: child,
                excluding: exclusions,
                maxEntries: min(remainingEntryBudget, maxEntriesPerHotspot),
                fileManager: fileManager,
                batchPause: 0.002,
                progress: { childVisitedEntryCount in
                    progress(visitedBeforeChild + childVisitedEntryCount)
                }
            )
            visitedEntryCount += measurement.visitedEntryCount
            remainingEntryBudget -= measurement.visitedEntryCount
            totalBytes = totalBytes &+ measurement.allocatedBytes
            inaccessibleCount += measurement.inaccessibleCount
            skippedCloudItems += measurement.skippedCloudItemCount
            reachedLimit = reachedLimit || measurement.reachedEntryLimit
            hotspots.append(StorageHotspot(
                url: child,
                allocatedBytes: measurement.allocatedBytes,
                inaccessibleCount: measurement.inaccessibleCount,
                skippedCloudItemCount: measurement.skippedCloudItemCount,
                reachedEntryLimit: measurement.reachedEntryLimit
            ))
        }

        return (
            StorageInsightItem(
                category: descriptor.category,
                url: descriptor.url,
                allocatedBytes: totalBytes,
                hotspots: Array(hotspots.sorted { $0.allocatedBytes > $1.allocatedBytes }.prefix(6)),
                inaccessibleCount: inaccessibleCount,
                skippedCloudItemCount: skippedCloudItems,
                reachedEntryLimit: reachedLimit
            ),
            visitedEntryCount
        )
    }
}
