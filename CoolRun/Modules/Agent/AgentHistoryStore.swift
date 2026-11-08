import Foundation

/// 一条落盘的对话记录。只存用户和助手说过的话，工具调用过程不进历史。
struct AgentHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var role: AgentRole
    var content: String
    var timestamp: Date

    nonisolated init(id: UUID = UUID(), role: AgentRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    nonisolated var isUser: Bool { role == .user }
}

/// 跨启动保留的对话历史，支持逐条删除和整体清空。
@MainActor
@Observable
final class AgentHistoryStore {
    static let shared = AgentHistoryStore()

    private(set) var entries: [AgentHistoryEntry] = []
    private(set) var loadError: String?

    /// 保留上限，超出时丢最早的。
    private let limit = 200

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = support.appendingPathComponent("CoolRun", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("agent-history.json")
        load()
    }

    var isEmpty: Bool { entries.isEmpty }

    // MARK: - 变更

    @discardableResult
    func append(role: AgentRole, content: String) -> AgentHistoryEntry {
        let entry = AgentHistoryEntry(role: role, content: content)
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        save()
        return entry
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// 把最近若干条转成引擎能吃的消息序列。
    func messages(limit: Int = 24) -> [AgentMessage] {
        entries.suffix(limit).map {
            AgentMessage(id: $0.id, role: $0.role, content: $0.content)
        }
    }

    // MARK: - 持久化

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([AgentHistoryEntry].self, from: data)
        } catch {
            loadError = error.localizedDescription
            let backup = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
