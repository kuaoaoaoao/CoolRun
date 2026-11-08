import XCTest
@testable import CoolRun

/// 失败之后的两条出路：去设置、重试。这里只测"该给哪个按钮"的判断，
/// 真正的重试要跑模型，放在 gated 联调里。
final class AgentRecoveryTests: XCTestCase {

    func testConfigurationProblemsRouteToSettings() {
        XCTAssertTrue(AgentCoordinator.looksLikeConfigurationProblem("还没有配置 OpenAI 的 API Key。"))
        XCTAssertTrue(AgentCoordinator.looksLikeConfigurationProblem("还没有填写模型名称。"))
        XCTAssertTrue(AgentCoordinator.looksLikeConfigurationProblem("接口地址无效：htp://x"))
        XCTAssertTrue(AgentCoordinator.looksLikeConfigurationProblem("请求失败（401）：invalid api key"))
        XCTAssertTrue(AgentCoordinator.looksLikeConfigurationProblem("Agent 未配置：请先在设置里选择模型接入方式。"))
    }

    func testOtherFailuresOfferRetry() {
        XCTAssertFalse(AgentCoordinator.looksLikeConfigurationProblem("请求失败（500）：upstream timeout"))
        XCTAssertFalse(AgentCoordinator.looksLikeConfigurationProblem("响应格式异常：unexpected token"))
        XCTAssertFalse(AgentCoordinator.looksLikeConfigurationProblem("工具调用超过 6 轮上限，已停止。请把问题拆小一点。"))
        XCTAssertFalse(AgentCoordinator.looksLikeConfigurationProblem("已取消。"))
    }

    @MainActor
    func testHasUserMessageTracksHistory() {
        let coordinator = AgentCoordinator.shared
        coordinator.reset()
        XCTAssertFalse(coordinator.hasUserMessage)

        AgentHistoryStore.shared.append(role: .user, content: "看一下磁盘")
        XCTAssertTrue(coordinator.hasUserMessage)

        coordinator.reset()
        XCTAssertFalse(coordinator.hasUserMessage)
    }
}
