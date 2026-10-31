import Foundation
import Observation

struct NoteGroupRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
}

struct NoteRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var groupID: UUID?
    var isPinned: Bool
    let createdAt: Date
    var updatedAt: Date
}

enum NoteGroupFilter: Hashable, Identifiable, Sendable {
    case all
    case ungrouped
    case group(UUID)

    var id: String {
        switch self {
        case .all: "all"
        case .ungrouped: "ungrouped"
        case .group(let id): "group-\(id.uuidString)"
        }
    }
}

private struct NotesArchive: Codable {
    var version = 1
    var groups: [NoteGroupRecord] = []
    var notes: [NoteRecord] = []
}

@MainActor
@Observable
final class NotesStore {
    static let shared = NotesStore(fileURL: GoldDataStorage.fileURL(named: "notes.json"))

    private(set) var groups: [NoteGroupRecord] = []
    private(set) var notes: [NoteRecord] = []

    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    @discardableResult
    func addGroup(name: String, now: Date = Date()) -> NoteGroupRecord? {
        let normalized = Self.normalizedSingleLine(name)
        guard !normalized.isEmpty, !containsGroup(named: normalized) else { return nil }
        let group = NoteGroupRecord(id: UUID(), name: normalized, createdAt: now, updatedAt: now)
        groups.append(group)
        sortGroups()
        save()
        return group
    }

    @discardableResult
    func renameGroup(id: UUID, name: String, now: Date = Date()) -> Bool {
        let normalized = Self.normalizedSingleLine(name)
        guard !normalized.isEmpty,
              !containsGroup(named: normalized, excluding: id),
              let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        groups[index].name = normalized
        groups[index].updatedAt = now
        sortGroups()
        save()
        return true
    }

    /// Removing a group never removes its notes. They become ungrouped instead.
    func deleteGroup(id: UUID, now: Date = Date()) {
        guard groups.contains(where: { $0.id == id }) else { return }
        groups.removeAll { $0.id == id }
        for index in notes.indices where notes[index].groupID == id {
            notes[index].groupID = nil
            notes[index].updatedAt = now
        }
        sortNotes()
        save()
    }

    @discardableResult
    func saveNote(
        id: UUID? = nil,
        title: String,
        body: String,
        groupID: UUID?,
        now: Date = Date()
    ) -> NoteRecord? {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = Self.resolvedTitle(title: title, body: normalizedBody)
        guard !normalizedTitle.isEmpty || !normalizedBody.isEmpty else { return nil }

        let validGroupID = groupID.flatMap { candidate in
            groups.contains(where: { $0.id == candidate }) ? candidate : nil
        }

        if let id, let index = notes.firstIndex(where: { $0.id == id }) {
            notes[index].title = normalizedTitle
            notes[index].body = normalizedBody
            notes[index].groupID = validGroupID
            notes[index].updatedAt = now
            let updated = notes[index]
            sortNotes()
            save()
            return updated
        }

        let note = NoteRecord(
            id: id ?? UUID(),
            title: normalizedTitle,
            body: normalizedBody,
            groupID: validGroupID,
            isPinned: false,
            createdAt: now,
            updatedAt: now
        )
        notes.append(note)
        sortNotes()
        save()
        return note
    }

    func togglePin(id: UUID, now: Date = Date()) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        notes[index].updatedAt = now
        sortNotes()
        save()
    }

    func deleteNote(id: UUID) {
        let previousCount = notes.count
        notes.removeAll { $0.id == id }
        guard previousCount != notes.count else { return }
        save()
    }

    func filteredNotes(group filter: NoteGroupFilter, query: String) -> [NoteRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { note in
            let matchesGroup: Bool
            switch filter {
            case .all:
                matchesGroup = true
            case .ungrouped:
                matchesGroup = note.groupID == nil
            case .group(let id):
                matchesGroup = note.groupID == id
            }

            guard matchesGroup else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            return note.title.localizedCaseInsensitiveContains(normalizedQuery)
                || note.body.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    func groupName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return groups.first(where: { $0.id == id })?.name
    }

    nonisolated static func resolvedTitle(title: String, body: String) -> String {
        let explicitTitle = normalizedSingleLine(title)
        if !explicitTitle.isEmpty { return String(explicitTitle.prefix(80)) }

        let firstBodyLine = body
            .components(separatedBy: .newlines)
            .map(normalizedSingleLine)
            .first(where: { !$0.isEmpty }) ?? ""
        return String(firstBodyLine.prefix(80))
    }

    nonisolated private static func normalizedSingleLine(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func containsGroup(named name: String, excluding excludedID: UUID? = nil) -> Bool {
        groups.contains {
            $0.id != excludedID && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private func sortGroups() {
        groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func sortNotes() {
        notes.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(NotesArchive.self, from: data) else { return }
        groups = archive.groups
        let validGroupIDs = Set(groups.map(\.id))
        notes = archive.notes.map { note in
            guard let groupID = note.groupID, !validGroupIDs.contains(groupID) else { return note }
            var recovered = note
            recovered.groupID = nil
            return recovered
        }
        sortGroups()
        sortNotes()
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(NotesArchive(groups: groups, notes: notes)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
