import AppKit
import Foundation
import Observation

struct ClipboardHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var copiedAt: Date
    var isPinned: Bool
}

private struct ClipboardHistoryArchive: Codable {
    var version = 1
    var entries: [ClipboardHistoryEntry] = []
}

@MainActor
@Observable
final class ClipboardHistoryStore {
    static let shared = ClipboardHistoryStore(
        fileURL: GoldDataStorage.fileURL(named: "clipboard_history.json"),
        userDefaults: .standard,
        pasteboard: .general
    )

    nonisolated static let entryLimit = 200
    nonisolated static let monitoringDefaultsKey = "clipboard_history_monitoring_enabled"

    private(set) var entries: [ClipboardHistoryEntry] = []
    private(set) var isMonitoringEnabled: Bool

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var monitorTimer: Timer?
    @ObservationIgnored private var lastChangeCount: Int

    init(fileURL: URL?, userDefaults: UserDefaults, pasteboard: NSPasteboard) {
        self.fileURL = fileURL
        self.userDefaults = userDefaults
        self.pasteboard = pasteboard
        self.isMonitoringEnabled = userDefaults.object(forKey: Self.monitoringDefaultsKey) as? Bool ?? true
        self.lastChangeCount = pasteboard.changeCount
        load()
    }

    func startMonitoring() {
        guard monitorTimer == nil else { return }
        // Do not import pasteboard content that predates this monitoring session.
        lastChangeCount = pasteboard.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.capturePasteboardChangeIfNeeded()
            }
        }
        timer.tolerance = 0.2
        monitorTimer = timer
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func setMonitoringEnabled(_ enabled: Bool) {
        guard isMonitoringEnabled != enabled else { return }
        isMonitoringEnabled = enabled
        userDefaults.set(enabled, forKey: Self.monitoringDefaultsKey)
        // Skips any values copied while collection was paused.
        lastChangeCount = pasteboard.changeCount
    }

    func filteredEntries(query: String) -> [ClipboardHistoryEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(normalized) }
    }

    /// Writes an entry to the pasteboard without promoting it to the top of
    /// history, so in-app copies and quick-paste shortcuts keep a stable order.
    func copyToPasteboard(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        sortEntries()
        save()
    }

    func deleteEntry(id: UUID) {
        let previousCount = entries.count
        entries.removeAll { $0.id == id }
        guard previousCount != entries.count else { return }
        save()
    }

    func clearHistory() {
        guard !entries.isEmpty else { return }
        entries = []
        save()
    }

    /// Internal entry point used by pasteboard polling and deterministic tests.
    func ingest(_ text: String, at now: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let existingIndex = entries.firstIndex(where: { $0.text == text }) {
            var existing = entries.remove(at: existingIndex)
            existing.copiedAt = now
            entries.append(existing)
        } else {
            entries.append(ClipboardHistoryEntry(id: UUID(), text: text, copiedAt: now, isPinned: false))
        }
        entries = Self.retained(entries, limit: Self.entryLimit)
        save()
    }

    nonisolated static func retained(
        _ source: [ClipboardHistoryEntry],
        limit: Int = entryLimit
    ) -> [ClipboardHistoryEntry] {
        let safeLimit = max(0, limit)
        var uniqueByText: [String: ClipboardHistoryEntry] = [:]
        for entry in source.sorted(by: { $0.copiedAt < $1.copiedAt }) {
            if let existing = uniqueByText[entry.text] {
                uniqueByText[entry.text] = ClipboardHistoryEntry(
                    id: existing.id,
                    text: entry.text,
                    copiedAt: max(existing.copiedAt, entry.copiedAt),
                    isPinned: existing.isPinned || entry.isPinned
                )
            } else {
                uniqueByText[entry.text] = entry
            }
        }

        var retained = uniqueByText.values.sorted(by: Self.precedes)
        while retained.count > safeLimit {
            if let oldestUnpinned = retained.indices.reversed().first(where: { !retained[$0].isPinned }) {
                retained.remove(at: oldestUnpinned)
            } else {
                retained.removeLast()
            }
        }
        return retained
    }

    nonisolated private static func precedes(_ lhs: ClipboardHistoryEntry, _ rhs: ClipboardHistoryEntry) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
        return lhs.copiedAt > rhs.copiedAt
    }

    /// Checks the pasteboard once. Kept internal so pause/resume behavior can be
    /// verified deterministically without waiting for the monitoring timer.
    func capturePasteboardChangeIfNeeded() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        guard isMonitoringEnabled,
              let text = pasteboard.string(forType: .string) else { return }
        ingest(text)
    }

    private func sortEntries() {
        entries.sort(by: Self.precedes)
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(ClipboardHistoryArchive.self, from: data) else { return }
        entries = Self.retained(archive.entries, limit: Self.entryLimit)
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(ClipboardHistoryArchive(entries: entries)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
