import XCTest
@testable import CoolRun

/// 权限闸门的回归测试。
///
/// 这几个用例盯的是「限定 agent 能做什么」到底有没有落在执行路径上：
/// 只把工具从 schema 里藏起来是不够的，模型完全可以凭名字直接调用。
@MainActor
final class ToolGateTests: XCTestCase {

    private func makeDescriptor(_ name: String, _ permission: ToolPermission) -> ToolDescriptor {
        ToolDescriptor(
            name: name,
            summary: "测试工具",
            parameters: ToolSchema.object(properties: []),
            permission: permission
        )
    }

    override func tearDown() {
        for name in ["test_read", "test_persistent", "test_slow"] {
            ToolRegistry.shared.unregister(name: name)
        }
        super.tearDown()
    }

    func testReadToolRunsWithoutApproval() async {
        ToolRegistry.shared.register(makeDescriptor("test_read", .read)) { _ in
            .text("ok")
        }
        let result = await ToolRegistry.shared.execute(
            name: "test_read",
            arguments: .object([:]),
            policy: .init(maxLevel: .read)
        )
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content, "ok")
    }

    func testToolAboveLevelIsRejectedEvenWhenNamedDirectly() async {
        ToolRegistry.shared.register(makeDescriptor("test_persistent", .persistent)) { _ in
            .text("不该被执行")
        }
        let result = await ToolRegistry.shared.execute(
            name: "test_persistent",
            arguments: .object([:]),
            policy: .init(maxLevel: .read)
        )
        XCTAssertTrue(result.isError, "超过权限上限的工具必须被拒绝")
        XCTAssertTrue(result.content.contains("权限不足"), result.content)
    }

    func testPersistentToolNeedsApproval() async {
        var didRun = false
        ToolRegistry.shared.register(makeDescriptor("test_persistent", .persistent)) { _ in
            didRun = true
            return .text("写进去了")
        }

        let denied = await ToolRegistry.shared.execute(
            name: "test_persistent",
            arguments: .object([:]),
            policy: .init(maxLevel: .persistent, approval: { _, _ in .userDeclined })
        )
        XCTAssertTrue(denied.isError)
        XCTAssertFalse(didRun, "用户拒绝后不许执行")

        let approved = await ToolRegistry.shared.execute(
            name: "test_persistent",
            arguments: .object([:]),
            policy: .init(maxLevel: .persistent, approval: { _, _ in .approved })
        )
        XCTAssertFalse(approved.isError)
        XCTAssertTrue(didRun)
    }

    func testPersistentToolIsDeniedWhenNoApprovalChannelExists() async {
        var didRun = false
        ToolRegistry.shared.register(makeDescriptor("test_persistent", .persistent)) { _ in
            didRun = true
            return .text("写进去了")
        }
        let result = await ToolRegistry.shared.execute(
            name: "test_persistent",
            arguments: .object([:]),
            policy: .init(maxLevel: .persistent, approval: nil)
        )
        XCTAssertTrue(result.isError, "没有确认界面时必须拒绝，不能默默写")
        XCTAssertFalse(didRun)
    }

    func testToolTimeoutDoesNotHangTheTurn() async {
        ToolRegistry.shared.register(makeDescriptor("test_slow", .read)) { _ in
            try? await Task.sleep(for: .milliseconds(600))
            return .text("太慢了")
        }
        let started = Date()
        let result = await ToolRegistry.shared.execute(
            name: "test_slow",
            arguments: .object([:]),
            policy: .init(maxLevel: .read, approval: nil, timeout: .milliseconds(80))
        )
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("超时"), result.content)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "超时后必须立刻返回")
    }

    /// 面板关着的时候没有人能点确认，必须立刻拒绝并说清原因，
    /// 而不是让 DSH 那边干等到 60 秒工具超时、模型只看到「超时」。
    func testApprovalFailsFastWhenNoChatWindowIsVisible() async {
        AgentApprovalGate.shared.setChatVisible(false)
        let descriptor = makeDescriptor("gate_probe", .persistent)

        let started = Date()
        let decision = await AgentCoordinator.shared.requestApproval(descriptor, .object([:]))
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 0.5, "没有确认界面时不应该挂起等待")
        guard case .denied(let reason) = decision else {
            return XCTFail("应当直接拒绝，实际是 \(decision)")
        }
        XCTAssertTrue(reason.contains("对话窗口"), reason)
        XCTAssertNil(AgentCoordinator.shared.pendingApproval)
    }

    func testUnknownToolIsRejected() async {
        let result = await ToolRegistry.shared.execute(name: "根本没有这个工具", arguments: .object([:]))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("未知工具"), result.content)
    }
}
