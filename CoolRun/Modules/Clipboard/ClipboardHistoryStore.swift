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
    /// 单条最多留这么多字节。
    ///
    /// 剪贴板里偶尔会进来几 MB 的东西（整页 HTML、整段 JSON）。留着它们不只是占
    /// 磁盘：整个文件要重新编码落盘、分类要扫、SwiftUI 的 diff 也要比，每次复制
    /// 都会卡一下。64 KB 足够放下一屏代码或一篇短文。
    nonisolated static let textByteLimit = 64 * 1024
    nonisolated static let monitoringDefaultsKey = "clipboard_history_monitoring_enabled"
    nonisolated static let truncationMarker = "\n…（超过 64 KB 的部分没有保存）"

    private(set) var entries: [ClipboardHistoryEntry] = []
    /// 内容版本号。视图监听它而不是直接监听 `entries`：
    /// 比较两个十几 MB 的字符串数组本身就是开销。
    private(set) var revision: Int = 0
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
        revision &+= 1
        save()
    }

    func deleteEntry(id: UUID) {
        let previousCount = entries.count
        entries.removeAll { $0.id == id }
        guard previousCount != entries.count else { return }
        revision &+= 1
        save()
    }

    func clearHistory() {
        guard !entries.isEmpty else { return }
        entries = []
        revision &+= 1
        save()
    }

    /// Internal entry point used by pasteboard polling and deterministic tests.
    func ingest(_ text: String, at now: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = Self.clamped(text)

        if let existingIndex = entries.firstIndex(where: { $0.text == text }) {
            var existing = entries.remove(at: existingIndex)
            existing.copiedAt = now
            entries.append(existing)
        } else {
            entries.append(ClipboardHistoryEntry(id: UUID(), text: text, copiedAt: now, isPinned: false))
        }
        entries = Self.retained(entries, limit: Self.entryLimit)
        revision &+= 1
        save()
    }

    /// 超长文本按 UTF-8 字节截断，并留一句说明，避免"复制回去少了半截"的困惑。
    nonisolated static func clamped(_ text: String) -> String {
        let utf8 = text.utf8
        guard utf8.count > textByteLimit else { return text }
        let head = String(decoding: utf8.prefix(textByteLimit), as: UTF8.self)
        return head + truncationMarker
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
        let loaded = Self.retained(archive.entries, limit: Self.entryLimit)

        // 一次性瘦身：早期版本把几 MB 的条目原样存了下来，文件涨到十几 MB，
        // 每次落盘和 diff 都跟着变慢。这里把历史里的超长条目截断，
        // 截断后写回一次，之后就不会再触发。
        var trimmed = false
        let migrated = loaded.map { entry -> ClipboardHistoryEntry in
            let clamped = Self.clamped(entry.text)
            guard clamped != entry.text else { return entry }
            trimmed = true
            return ClipboardHistoryEntry(
                id: entry.id,
                text: clamped,
                copiedAt: entry.copiedAt,
                isPinned: entry.isPinned
            )
        }
        entries = migrated
        if trimmed { save() }
    }

    private func save() {
        guard let fileURL else { return }
        // 编码留在主线程（截断之后一次只要几毫秒），真正的写盘挪到后台队列：
        // 原子写十几 MB 不该发生在复制动作的同一帧里。串行队列保证先后顺序，
        // 后写的快照覆盖先写的。
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ClipboardHistoryArchive(entries: entries)) else { return }
        Self.saveQueue.async {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 等挂起的落盘跑完。测试和 App 退出前用——落盘在后台队列上，
    /// 进程直接退出会丢掉最后一次写。
    nonisolated func flushPendingWrites() {
        Self.saveQueue.sync {}
    }

    private nonisolated static let saveQueue = DispatchQueue(label: "coolrun.clipboard.save", qos: .utility)
}
