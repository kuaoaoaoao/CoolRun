import AppKit
import XCTest
@testable import CoolRun

@MainActor
final class PersonalToolsTests: XCTestCase {
    func testBodyOnlyNoteDerivesTitleFromFirstNonemptyLine() {
        let title = NotesStore.resolvedTitle(
            title: "   ",
            body: "\n  Pick up the package  \nTracking number 123"
        )

        XCTAssertEqual(title, "Pick up the package")
    }

    func testDeletingGroupMovesNotesToUngrouped() throws {
        let store = NotesStore(fileURL: nil)
        let group = try XCTUnwrap(store.addGroup(name: "Work"))
        let note = try XCTUnwrap(store.saveNote(
            title: "Release checklist",
            body: "Build and verify",
            groupID: group.id
        ))

        store.deleteGroup(id: group.id)

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertNil(store.notes.first(where: { $0.id == note.id })?.groupID)
        XCTAssertEqual(store.filteredNotes(group: .ungrouped, query: "release").map(\.id), [note.id])
    }

    func testNotesPersistAndKeepGroupFilteringAndPinnedOrder() throws {
        let context = try makeTemporaryFile(named: "notes.json")
        defer { try? FileManager.default.removeItem(at: context.directoryURL) }
        let store = NotesStore(fileURL: context.fileURL)
        let work = try XCTUnwrap(store.addGroup(name: "Work", now: Date(timeIntervalSince1970: 100)))
        let personal = try XCTUnwrap(store.addGroup(name: "Personal", now: Date(timeIntervalSince1970: 101)))
        let older = try XCTUnwrap(store.saveNote(
            title: "Older",
            body: "Contains release keyword",
            groupID: work.id,
            now: Date(timeIntervalSince1970: 200)
        ))
        let newer = try XCTUnwrap(store.saveNote(
            title: "Newer release",
            body: "Second item",
            groupID: work.id,
            now: Date(timeIntervalSince1970: 300)
        ))
        _ = store.saveNote(
            title: "Other group release",
            body: "Must not leak into the Work filter",
            groupID: personal.id,
            now: Date(timeIntervalSince1970: 400)
        )
        store.togglePin(id: older.id, now: Date(timeIntervalSince1970: 500))

        let reloaded = NotesStore(fileURL: context.fileURL)

        XCTAssertEqual(reloaded.groups.count, 2)
        XCTAssertEqual(
            reloaded.filteredNotes(group: .group(work.id), query: "release").map(\.id),
            [older.id, newer.id]
        )
        XCTAssertTrue(reloaded.notes.first(where: { $0.id == older.id })?.isPinned == true)
    }

    func testClipboardDeduplicatesAndRefreshesExistingEntry() throws {
        let context = makeClipboardStore()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let store = context.store
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)

        store.ingest("same text", at: firstDate)
        let originalID = try XCTUnwrap(store.entries.first?.id)
        store.togglePin(id: originalID)
        store.ingest("same text", at: secondDate)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].id, originalID)
        XCTAssertEqual(store.entries[0].copiedAt, secondDate)
        XCTAssertTrue(store.entries[0].isPinned)
    }

    func testClipboardRetentionPrefersPinnedEntries() {
        let oldestPinned = ClipboardHistoryEntry(
            id: UUID(),
            text: "keep pinned",
            copiedAt: Date(timeIntervalSince1970: 0),
            isPinned: true
        )
        let entries = [oldestPinned] + (1...205).map { index in
            ClipboardHistoryEntry(
                id: UUID(),
                text: "clip \(index)",
                copiedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                isPinned: false
            )
        }

        let retained = ClipboardHistoryStore.retained(entries, limit: 200)

        XCTAssertEqual(retained.count, 200)
        XCTAssertTrue(retained.contains(where: { $0.id == oldestPinned.id }))
        XCTAssertFalse(retained.contains(where: { $0.text == "clip 1" }))
    }

    func testClipboardPauseSkipsChangesAndResumeCapturesNewText() {
        let context = makeClipboardStore()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let store = context.store

        store.setMonitoringEnabled(false)
        context.pasteboard.clearContents()
        context.pasteboard.setString("copied while paused", forType: .string)
        store.capturePasteboardChangeIfNeeded()
        XCTAssertTrue(store.entries.isEmpty)

        store.setMonitoringEnabled(true)
        context.pasteboard.clearContents()
        context.pasteboard.setString("copied after resume", forType: .string)
        store.capturePasteboardChangeIfNeeded()
        XCTAssertEqual(store.entries.map(\.text), ["copied after resume"])
    }

    func testClipboardPersistsHistoryPreferenceAndFullCopy() throws {
        let fileContext = try makeTemporaryFile(named: "clipboard.json")
        defer { try? FileManager.default.removeItem(at: fileContext.directoryURL) }
        let context = makeClipboardStore(fileURL: fileContext.fileURL)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let text = "First line\nSecond line with full content"

        context.store.ingest(text, at: Date(timeIntervalSince1970: 1_000))
        let entryID = try XCTUnwrap(context.store.entries.first?.id)
        context.store.togglePin(id: entryID)
        context.store.setMonitoringEnabled(false)

        let reloaded = ClipboardHistoryStore(
            fileURL: fileContext.fileURL,
            userDefaults: context.defaults,
            pasteboard: context.pasteboard
        )
        XCTAssertFalse(reloaded.isMonitoringEnabled)
        XCTAssertEqual(reloaded.entries.first?.text, text)
        XCTAssertTrue(reloaded.entries.first?.isPinned == true)

        reloaded.copyToPasteboard(id: entryID)
        XCTAssertEqual(context.pasteboard.string(forType: .string), text)
        XCTAssertEqual(reloaded.entries.first?.copiedAt, Date(timeIntervalSince1970: 1_000))
    }

    private func makeClipboardStore(fileURL: URL? = nil) -> (
        store: ClipboardHistoryStore,
        defaults: UserDefaults,
        suiteName: String,
        pasteboard: NSPasteboard
    ) {
        let suiteName = "CoolRun.PersonalToolsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("\(suiteName).pasteboard"))
        return (
            ClipboardHistoryStore(fileURL: fileURL, userDefaults: defaults, pasteboard: pasteboard),
            defaults,
            suiteName,
            pasteboard
        )
    }

    private func makeTemporaryFile(named filename: String) throws -> (directoryURL: URL, fileURL: URL) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoolRun.PersonalToolsTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return (directoryURL, directoryURL.appendingPathComponent(filename))
    }
}
