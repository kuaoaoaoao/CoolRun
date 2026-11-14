import XCTest
@testable import CoolRun

/// MCP 服务器的协议层端到端测试：真起一个监听，用 HTTP 走一遍。
///
/// 之前这里完全没有测试，而它是 Agent 与 DSH 之间唯一的通道 ——
/// 协议写错的表现是「模型说工具不存在」，从界面上根本看不出是哪里坏了。
@MainActor
final class MCPProtocolTests: XCTestCase {

    private var host: CoolRunMCPHost { CoolRunMCPHost.shared }

    override func setUp() async throws {
        try await super.setUp()
        // token 默认每个进程随机，测试里固定一个才能自己发请求。
        setenv("COOLRUN_MCP_TOKEN", "mcp-protocol-test-token", 1)
        AgentTools.registerAll()
        host.start()
        // 监听是异步就绪的，端口要等一拍。
        for _ in 0..<50 where host.port == nil {
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertNotNil(host.port, "MCP 服务器没起来：\(host.lastError ?? "未知原因")")
    }

    override func tearDown() async throws {
        host.stop()
        unsetenv("COOLRUN_MCP_TOKEN")
        try await super.tearDown()
    }

    // MARK: 请求工具

    private func call(
        _ method: String,
        _ path: String = "/mcp",
        body: String? = nil,
        authorized: Bool = true
    ) async throws -> (status: Int, json: [String: Any]) {
        let port = try XCTUnwrap(host.port)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 10
        if authorized {
            request.setValue("Bearer mcp-protocol-test-token", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (status, json)
    }

    private func rpc(_ method: String, params: String = "{}", id: Int = 1) async throws -> (Int, [String: Any]) {
        try await call("POST", body: #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":\#(params)}"#)
    }

    // MARK: 用例

    func testHealthNeedsNoToken() async throws {
        let (status, json) = try await call("GET", "/health", authorized: false)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertGreaterThan(json["tools"] as? Int ?? 0, 0)
    }

    func testMissingTokenIsRejected() async throws {
        let (status, json) = try await call("POST", body: #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, authorized: false)
        XCTAssertEqual(status, 401)
        XCTAssertEqual(json["error"] as? String, "unauthorized")
    }

    func testWrongPathIsNotFound() async throws {
        let (status, _) = try await call("GET", "/nope")
        XCTAssertEqual(status, 404)
    }

    func testInitializeAdvertisesToolsCapability() async throws {
        let (status, json) = try await rpc("initialize")
        XCTAssertEqual(status, 200)
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["tools"])
    }

    func testToolsListReturnsSchemas() async throws {
        let (_, json) = try await rpc("tools/list")
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        XCTAssertFalse(tools.isEmpty)
        for tool in tools {
            XCTAssertNotNil(tool["name"] as? String)
            XCTAssertNotNil(tool["description"] as? String)
            XCTAssertNotNil(tool["inputSchema"] as? [String: Any], "\(tool["name"] ?? "?") 缺 inputSchema")
        }
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("system_snapshot"), "至少要有系统快照：\(names)")
    }

    func testNotificationGetsAcceptedWithoutBody() async throws {
        // 通知没有 id，服务器该回 202 且不回 JSON-RPC 结果。
        let (status, json) = try await call(
            "POST",
            body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        )
        XCTAssertEqual(status, 202)
        XCTAssertTrue(json.isEmpty)
    }

    func testUnknownMethodIsMethodNotFound() async throws {
        let (_, json) = try await rpc("does/not/exist")
        let error = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    func testBrokenJSONIsParseError() async throws {
        let (_, json) = try await call("POST", body: "{not json")
        let error = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32700)
    }

    func testToolsCallReturnsContent() async throws {
        let (_, json) = try await rpc("tools/call", params: #"{"name":"system_snapshot","arguments":{}}"#)
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        XCTAssertTrue(text.contains("cpu"), "系统快照里应该有 cpu：\(text.prefix(120))")
    }

    func testToolsCallOnUnknownToolReportsError() async throws {
        let (_, json) = try await rpc("tools/call", params: #"{"name":"definitely_not_a_tool","arguments":{}}"#)
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testToolsCallUpToConfiguredBoundary() async throws {
        // 工具等级收紧后，tools/list 不该再暴露超纲工具。
        let original = AgentSettings.shared.toolLevel
        defer { AgentSettings.shared.toolLevel = original }
        AgentSettings.shared.toolLevel = .read

        let (_, json) = try await rpc("tools/list")
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("system_snapshot"))
        XCTAssertFalse(names.contains("notes_create"), "只读档不该暴露写入工具：\(names)")
    }
}
