import XCTest
@testable import CoolRun

/// MCP 服务器的来源校验。
///
/// 这两道检查是给 token 兜底的：浏览器里的网页也能往 127.0.0.1 发请求，
/// DNS rebinding 还能让 evil.com 解析到本机，所以光有 token 不够。
@MainActor
final class MCPOriginTests: XCTestCase {

    private func request(_ headers: [String: String]) -> HTTPRequest {
        HTTPRequest(method: "POST", path: "/mcp", headers: headers, body: Data())
    }

    func testLocalHostIsAllowed() {
        XCTAssertNil(CoolRunMCPHost.requestRejectionReason(
            request(["host": "127.0.0.1:8765"])
        ))
        XCTAssertNil(CoolRunMCPHost.requestRejectionReason(
            request(["host": "localhost:8765"])
        ))
        XCTAssertNil(CoolRunMCPHost.requestRejectionReason(
            request(["host": "[::1]:8765"])
        ))
        XCTAssertNil(CoolRunMCPHost.requestRejectionReason(
            request(["host": "127.0.0.1"])
        ))
    }

    func testCrossOriginRequestIsRejected() {
        let reason = CoolRunMCPHost.requestRejectionReason(
            request(["host": "127.0.0.1:8765", "origin": "https://evil.example"])
        )
        XCTAssertEqual(reason, "cross-origin requests are not allowed")
    }

    func testNullOriginIsRejected() {
        // file:// 页面发请求时 Origin 是字面量 "null"，同样不该放行。
        XCTAssertNotNil(CoolRunMCPHost.requestRejectionReason(
            request(["host": "127.0.0.1:8765", "origin": "null"])
        ))
    }

    func testMissingHostIsRejected() {
        XCTAssertEqual(
            CoolRunMCPHost.requestRejectionReason(request([:])),
            "missing Host header"
        )
    }

    func testForeignHostIsRejected() {
        // DNS rebinding：浏览器发出的 Host 仍是攻击者域名。
        XCTAssertEqual(
            CoolRunMCPHost.requestRejectionReason(request(["host": "evil.example:8765"])),
            "unexpected Host header"
        )
        // 只匹配完整主机名，"127.0.0.1.evil.example" 不能因为前缀相同就放行。
        XCTAssertNotNil(CoolRunMCPHost.requestRejectionReason(
            request(["host": "127.0.0.1.evil.example:8765"])
        ))
    }
}
