import Foundation

struct AppResidueRoot: Equatable, Sendable {
    let category: StorageInsightCategory
    let url: URL
}

enum AppResidueService {
    nonisolated static let minimumAge: TimeInterval = 30 * 24 * 60 * 60

    static func scan(now: Date = Date()) async -> AppResidueScanResult {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let home = fileManager.homeDirectoryForCurrentUser
            let installedIdentifiers = installedApplicationIdentifiers(home: home, fileManager: fileManager)
            let roots = approvedRoots(home: home)
            var candidates: [AppResidueCandidate] = []
            var inspectedCount = 0
            var excludedCount = 0
            var inaccessibleCount = 0

            for root in roots {
                if Task.isCancelled { break }
                guard fileManager.fileExists(atPath: root.url.path) else { continue }
                let entries: [URL]
                do {
                    entries = try fileManager.contentsOfDirectory(
                        at: root.url,
                        includingPropertiesForKeys: [
                            .contentModificationDateKey,
                            .isSymbolicLinkKey,
                            .isDirectoryKey,
                            .isRegularFileKey,
                            .fileAllocatedSizeKey,
                            .totalFileAllocatedSizeKey
                        ],
                        options: []
                    )
                } catch {
                    inaccessibleCount += 1
                    continue
                }

                for entry in entries {
                    if Task.isCancelled { break }
                    inspectedCount += 1
                    guard let identifier = inferredIdentifier(from: entry.lastPathComponent),
                          isIdentifierEligible(identifier, installedIdentifiers: installedIdentifiers),
                          isDirectChild(entry, ofAny: roots.map(\.url)) else {
                        excludedCount += 1
                        continue
                    }

                    do {
                        let values = try entry.resourceValues(forKeys: [
                            .contentModificationDateKey,
                            .isSymbolicLinkKey,
                            .isDirectoryKey,
                            .isRegularFileKey,
                            .fileAllocatedSizeKey,
                            .totalFileAllocatedSizeKey
                        ])
                        guard values.isSymbolicLink != true,
                              let modifiedAt = values.contentModificationDate,
                              now.timeIntervalSince(modifiedAt) >= minimumAge else {
                            excludedCount += 1
                            continue
                        }

                        let size = allocatedSize(of: entry, values: values, fileManager: fileManager)
                        candidates.append(AppResidueCandidate(
                            identifier: identifier,
                            url: entry,
                            allocatedBytes: size,
                            modifiedAt: modifiedAt,
                            sourceCategory: root.category
                        ))
                    } catch {
                        inaccessibleCount += 1
                    }
                }
            }

            return AppResidueScanResult(
                timestamp: now,
                candidates: Array(candidates.sorted { lhs, rhs in
                    if lhs.allocatedBytes == rhs.allocatedBytes {
                        return lhs.identifier.localizedStandardCompare(rhs.identifier) == .orderedAscending
                    }
                    return lhs.allocatedBytes > rhs.allocatedBytes
                }.prefix(120)),
                inspectedEntryCount: inspectedCount,
                excludedEntryCount: excludedCount,
                inaccessibleCount: inaccessibleCount
            )
        }.value
    }

    static func trash(urls: [URL], now: Date = Date()) async -> AppResidueCleanupReport {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let home = fileManager.homeDirectoryForCurrentUser
            let roots = approvedRoots(home: home)
            let installedIdentifiers = installedApplicationIdentifiers(home: home, fileManager: fileManager)
            var trashed: [URL] = []
            var failures: [AppResidueCleanupFailure] = []

            for url in urls {
                if Task.isCancelled { break }
                guard let identifier = inferredIdentifier(from: url.lastPathComponent),
                      isDirectChild(url, ofAny: roots.map(\.url)),
                      isIdentifierEligible(identifier, installedIdentifiers: installedIdentifiers) else {
                    failures.append(AppResidueCleanupFailure(url: url, message: "The path no longer passes the safety checks."))
                    continue
                }

                do {
                    let values = try url.resourceValues(forKeys: [
                        .contentModificationDateKey,
                        .isSymbolicLinkKey
                    ])
                    guard values.isSymbolicLink != true,
                          let modifiedAt = values.contentModificationDate,
                          now.timeIntervalSince(modifiedAt) >= minimumAge else {
                        failures.append(AppResidueCleanupFailure(url: url, message: "The item changed or is too recent."))
                        continue
                    }
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                    trashed.append(url)
                } catch {
                    failures.append(AppResidueCleanupFailure(url: url, message: error.localizedDescription))
                }
            }

            return AppResidueCleanupReport(trashedURLs: trashed, failures: failures)
        }.value
    }

    nonisolated static func approvedRoots(home: URL) -> [AppResidueRoot] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        return [
            AppResidueRoot(category: .caches, url: library.appendingPathComponent("Caches", isDirectory: true)),
            AppResidueRoot(category: .logs, url: library.appendingPathComponent("Logs", isDirectory: true)),
            AppResidueRoot(category: .applicationSupport, url: library.appendingPathComponent("Preferences", isDirectory: true)),
            AppResidueRoot(category: .applicationSupport, url: library.appendingPathComponent("Saved Application State", isDirectory: true)),
            AppResidueRoot(category: .caches, url: library.appendingPathComponent("HTTPStorages", isDirectory: true)),
            AppResidueRoot(category: .caches, url: library.appendingPathComponent("WebKit", isDirectory: true)),
            AppResidueRoot(category: .containers, url: library.appendingPathComponent("Containers", isDirectory: true))
        ]
    }

    nonisolated static func inferredIdentifier(from entryName: String) -> String? {
        var candidate = entryName
        let knownSuffixes = [".plist", ".savedState", ".binarycookies"]
        if let suffix = knownSuffixes.first(where: { candidate.lowercased().hasSuffix($0.lowercased()) }) {
            candidate.removeLast(suffix.count)
        }
        guard candidate.count <= 180,
              candidate.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*(?:\.[A-Za-z0-9][A-Za-z0-9_-]*){2,}$"#,
                options: .regularExpression
              ) != nil else { return nil }
        return candidate
    }

    nonisolated static func isIdentifierEligible(
        _ identifier: String,
        installedIdentifiers: Set<String>
    ) -> Bool {
        let value = identifier.lowercased()
        let protectedPrefixes = [
            "com.apple.", "group.com.apple.", "apple.",
            "com.openai.coolrun", "kuao.coolrun"
        ]
        guard !protectedPrefixes.contains(where: value.hasPrefix) else { return false }

        for installed in installedIdentifiers.map({ $0.lowercased() }) {
            if value == installed || value.hasPrefix(installed + ".") || installed.hasPrefix(value + ".") {
                return false
            }
        }
        return true
    }

    nonisolated static func isDirectChild(_ url: URL, ofAny roots: [URL]) -> Bool {
        let candidate = url.standardizedFileURL
        return roots.contains { candidate.deletingLastPathComponent() == $0.standardizedFileURL }
    }

    nonisolated static func installedApplicationIdentifiers(
        home: URL,
        fileManager: FileManager = .default
    ) -> Set<String> {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        var identifiers = Set<String>()
        if let current = Bundle.main.bundleIdentifier { identifiers.insert(current) }

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                if let identifier = Bundle(url: url)?.bundleIdentifier {
                    identifiers.insert(identifier)
                }
                enumerator.skipDescendants()
            }
        }
        return identifiers
    }

    private nonisolated static func allocatedSize(
        of url: URL,
        values: URLResourceValues,
        fileManager: FileManager
    ) -> UInt64 {
        if values.isRegularFile == true {
            return UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0, 0))
        }
        return DiagnosticDirectorySizer.measure(
            url: url,
            maxEntries: 100_000,
            fileManager: fileManager
        ).allocatedBytes
    }
}
