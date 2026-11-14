import XCTest
@testable import CoolRun

/// 插件网络访问的边界。
///
/// 插件能拿到 `coolrun.httpGet`，而 127.0.0.1 上有我们自己的 MCP 服务器
/// （能调工具、能写文件）。所以插件不能去敲那个端口——但连本地模型
/// （比如 11434）是正当用法，不能一刀切封掉整个回环。
@MainActor
final class PluginNetworkTests: XCTestCase {

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    func testLocalAgentPortIsBlocked() {
        XCTAssertTrue(PluginHost.targetsLocalAgentPort(url("http://127.0.0.1:8765/mcp"), agentPort: 8765))
        XCTAssertTrue(PluginHost.targetsLocalAgentPort(url("http://localhost:8765/mcp"), agentPort: 8765))
        XCTAssertTrue(PluginHost.targetsLocalAgentPort(url("http://[::1]:8765/mcp"), agentPort: 8765))
    }

    func testOtherLocalPortsAreAllowed() {
        XCTAssertFalse(PluginHost.targetsLocalAgentPort(url("http://127.0.0.1:11434/api/generate"), agentPort: 8765))
    }

    func testRemoteHostsAreAllowed() {
        XCTAssertFalse(PluginHost.targetsLocalAgentPort(url("https://api.example.com:8765/x"), agentPort: 8765))
    }

    func testUnknownAgentPortBlocksNothing() {
        // Agent 没启动时没有端口可挡，插件行为与以前一致。
        XCTAssertFalse(PluginHost.targetsLocalAgentPort(url("http://127.0.0.1:8765/mcp"), agentPort: nil))
    }

    func testMissingPortIsNotMatched() {
        XCTAssertFalse(PluginHost.targetsLocalAgentPort(url("http://127.0.0.1/mcp"), agentPort: 80))
    }
}
