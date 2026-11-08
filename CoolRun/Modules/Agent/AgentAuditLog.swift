import Foundation

// MARK: - 审计日志

/// 记录每一次工具调用。菜单栏常驻应用必须能回答「刚才那个 agent 到底动了什么」。
@MainActor
final class AgentAuditLog {
    static let shared = AgentAuditLog()

    struct Entry: Codable, Identifiable, Sendable {
        var id: UUID
        var timestamp: Date
        var tool: String
        var arguments: String
        var resultPreview: String
        var isError: Bool
        var duration: TimeInterval
    }

    private(set) var entries: [Entry] = []
    nonisolated static let maxEntries = 300

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CoolRun", isDirectory: true)
        let base = directory ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("agent-audit.json")

        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func record(tool: String, arguments: JSONValue, result: ToolResult, duration: TimeInterval) {
        let preview = result.content.count > 400
            ? String(result.content.prefix(400)) + "…"
            : result.content
        let entry = Entry(
            id: UUID(),
            timestamp: Date(),
            tool: tool,
            arguments: arguments.compactJSONString(),
            resultPreview: preview,
            isError: result.isError,
            duration: duration
        )
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([Entry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
