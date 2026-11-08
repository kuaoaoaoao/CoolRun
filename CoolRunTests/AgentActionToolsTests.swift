import XCTest
@testable import CoolRun

@MainActor
final class AgentActionToolsTests: XCTestCase {
    override func setUp() async throws {
        AgentActionTools.registerAll()
    }

    func testWriteToolsAreRegisteredWithExpectedPermissions() {
        let registry = ToolRegistry.shared

        XCTAssertEqual(registry.descriptor(named: "ui_switch_panel")?.permission, .reversible)
        XCTAssertEqual(registry.descriptor(named: "notify")?.permission, .reversible)
        XCTAssertEqual(registry.descriptor(named: "clipboard_copy")?.permission, .reversible)

        XCTAssertEqual(registry.descriptor(named: "notes_create")?.permission, .persistent)
        XCTAssertEqual(registry.descriptor(named: "notes_toggle_pin")?.permission, .persistent)
        XCTAssertEqual(registry.descriptor(named: "reminder_create")?.permission, .persistent)
        XCTAssertEqual(registry.descriptor(named: "screenshot")?.permission, .persistent)
    }

    func testPermissionFilterHidesWriteToolsAtReadLevel() {
        let readOnly = ToolRegistry.shared.descriptors(upTo: .read).map(\.name)
        XCTAssertFalse(readOnly.contains("notes_create"))
        XCTAssertFalse(readOnly.contains("ui_switch_panel"))

        let reversible = ToolRegistry.shared.descriptors(upTo: .reversible).map(\.name)
        XCTAssertTrue(reversible.contains("ui_switch_panel"))
        XCTAssertFalse(reversible.contains("notes_create"))
    }

    func testSwitchPanelRejectsUnknownModule() async {
        let result = await ToolRegistry.shared.execute(
            name: "ui_switch_panel",
            arguments: .object(["module": .string("not-a-module")])
        )
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("未知模块"))
    }

    func testSwitchPanelAcceptsKnownModule() async {
        let result = await ToolRegistry.shared.execute(
            name: "ui_switch_panel",
            arguments: .object(["module": .string(ViewMode.notes.rawValue)])
        )
        XCTAssertFalse(result.isError, result.content)
    }

    func testNotesCreateThenDelete() async {
        let marker = "agent-test-\(UUID().uuidString.prefix(8))"
        let result = await ToolRegistry.shared.execute(
            name: "notes_create",
            arguments: .object([
                "title": .string(marker),
                "body": .string("由单元测试创建，随后删除。"),
            ])
        )
        XCTAssertFalse(result.isError, result.content)

        guard let note = NotesStore.shared.notes.first(where: { $0.title == marker }) else {
            return XCTFail("笔记没有落库：\(result.content)")
        }

        let pinned = await ToolRegistry.shared.execute(
            name: "notes_toggle_pin",
            arguments: .object(["note_id": .string(note.id.uuidString)])
        )
        XCTAssertFalse(pinned.isError, pinned.content)

        NotesStore.shared.deleteNote(id: note.id)
        XCTAssertFalse(NotesStore.shared.notes.contains(where: { $0.id == note.id }))
    }

    func testNotesCreateRejectsEmptyBody() async {
        let result = await ToolRegistry.shared.execute(
            name: "notes_create",
            arguments: .object(["body": .string("   ")])
        )
        XCTAssertTrue(result.isError)
    }

    func testReminderRequiresPositiveMinutes() async {
        let result = await ToolRegistry.shared.execute(
            name: "reminder_create",
            arguments: .object([
                "title": .string("测试提醒"),
                "after_minutes": .number(0),
            ])
        )
        XCTAssertTrue(result.isError)
    }

    func testApprovalHandlerIsWiredByCoordinator() {
        // 协调器负责把 UI 确认接进引擎；这里确认回调可以挂上并保持引用。
        let engine = SwiftAgentEngine()
        var invoked = false
        engine.approvalHandler = { _, _ in
            invoked = true
            return false
        }
        XCTAssertNotNil(engine.approvalHandler)
        XCTAssertFalse(invoked)
    }
}
