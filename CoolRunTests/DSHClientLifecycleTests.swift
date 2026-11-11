import XCTest
@testable import CoolRun

/// 回归测试：DSH 客户端被释放之后，它拉起的进程还会继续跑一会儿，
/// 退出回调晚到时不能再碰已经没了的主人。
///
/// 以前这里用的是 `[unowned self]`，于是「换引擎 / 重建客户端」时
/// 进程退出回调一跑到就 `swift_unownedRetainStrong` → SIGABRT，
/// 整个菜单栏 App 直接闪退（崩溃报告里停在 DSHJSONRPCClient.swift:61）。
@MainActor
final class DSHClientLifecycleTests: XCTestCase {

    private func sleeper(_ seconds: Double) -> (URL, [String]) {
        (URL(fileURLWithPath: "/bin/sh"), ["-c", "sleep \(seconds); echo bye"])
    }

    /// 进程还活着就把客户端丢掉：不能崩。
    func testDroppingClientWhileProcessStillRunsDoesNotCrash() async throws {
        var client: DSHJSONRPCClient? = DSHJSONRPCClient()
        let (executable, arguments) = sleeper(0.5)
        try client?.start(executable: executable, arguments: arguments, environment: [:])
        XCTAssertTrue(client?.isRunning == true)

        client = nil

        // 进程在 0.5 秒后退出；回调若还用 unowned，这一步之前就已经 abort 了。
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertTrue(true)
    }

    /// stop() 之后再丢引用：进程退出回调同样不能碰已释放的对象。
    func testStoppingThenDroppingClientDoesNotCrash() async throws {
        var client: DSHJSONRPCClient? = DSHJSONRPCClient()
        let (executable, arguments) = sleeper(0.4)
        try client?.start(executable: executable, arguments: arguments, environment: [:])

        client?.stop()
        client = nil

        try await Task.sleep(for: .milliseconds(900))
        XCTAssertTrue(true)
    }

    /// stop() 要当场把挂着的请求回掉，不能让它一直悬到超时。
    func testStopResumesPendingRequestWithError() async throws {
        let client = DSHJSONRPCClient()
        let (executable, arguments) = sleeper(5)
        try client.start(executable: executable, arguments: arguments, environment: [:])

        let pending = Task { @MainActor in
            try await client.request(method: "initialize", params: nil, timeout: .seconds(30))
        }
        try await Task.sleep(for: .milliseconds(120))
        client.stop()

        do {
            _ = try await pending.value
            XCTFail("进程关闭后挂着的请求应该以错误结束")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("关闭"))
        }
    }

    /// 没启动过就 stop() 是安全的空操作（换引擎时经常这么调）。
    func testStopWithoutStartIsNoOp() {
        let client = DSHJSONRPCClient()
        client.stop()
        XCTAssertFalse(client.isRunning)
    }
}
