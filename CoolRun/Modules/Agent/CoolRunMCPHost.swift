import Foundation
import Network
import Security

/// 本地 MCP 服务器：把 CoolRun 的工具以标准 MCP 协议暴露出去。
///
/// 为什么走 MCP 而不是给 DSH 写插件：MCP 是进程外标准，DSH、Claude Desktop、
/// 别的客户端都能直接连，而 DSH 插件要打进 pnpm 依赖树里，耦合太深。
///
/// 只监听 127.0.0.1，每个进程随机端口 + 随机 Bearer token，不接受外部连接。
@MainActor
@Observable
final class CoolRunMCPHost {
    static let shared = CoolRunMCPHost()

    private(set) var isRunning = false
    private(set) var port: UInt16?
    private(set) var token: String?
    private(set) var lastError: String?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connections: [ObjectIdentifier: NWConnection] = [:]
    @ObservationIgnored private let queue = DispatchQueue(label: "com.coolrun.mcp", qos: .userInitiated)

    private init() {}

    var endpoint: URL? {
        guard let port else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/mcp")
    }

    // MARK: 生命周期

    func start() {
        guard !isRunning else { return }
        lastError = nil

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(.loopback),
                port: .any
            )
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { connection in
                Task { @MainActor in CoolRunMCPHost.shared.accept(connection) }
            }
            listener.stateUpdateHandler = { state in
                Task { @MainActor in
                    let host = CoolRunMCPHost.shared
                    switch state {
                    case .ready:
                        host.port = host.listener?.port?.rawValue
                        // 脚本化 UI 测试（以及本机调试）可以用环境变量固定 token，
                        // 否则每次启动都是随机的、外部读不到。只在显式设置时生效，
                        // 监听仍然只绑 127.0.0.1。
                        let override = ProcessInfo.processInfo.environment["COOLRUN_MCP_TOKEN"] ?? ""
                        host.token = override.isEmpty ? Self.makeToken() : override
                        host.isRunning = true
                        // 留个脚印，排查「工具没生效」时能直接看到端口。
                        UserDefaults.standard.set(Int(host.port ?? 0), forKey: "agent.mcpPort")
                        #if DEBUG
                        UserDefaults.standard.set(host.token ?? "", forKey: "agent.mcpToken")
                        #endif
                    case .failed(let error):
                        host.lastError = error.localizedDescription
                        host.isRunning = false
                        UserDefaults.standard.set("failed: \(error.localizedDescription)", forKey: "agent.mcpError")
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            isRunning = false
            UserDefaults.standard.set("start threw: \(error.localizedDescription)", forKey: "agent.mcpError")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        isRunning = false
        port = nil
        token = nil
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 连接

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection

        connection.stateUpdateHandler = { state in
            Task { @MainActor in
                if case .failed = state {
                    CoolRunMCPHost.shared.close(key)
                } else if case .cancelled = state {
                    CoolRunMCPHost.shared.close(key)
                }
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func close(_ key: ObjectIdentifier) {
        connections.removeValue(forKey: key)?.cancel()
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { chunk, _, isComplete, error in
            Task { @MainActor in
                let host = CoolRunMCPHost.shared
                var accumulated = buffer
                if let chunk {
                    accumulated.append(chunk)
                }

                if let request = HTTPRequest.parse(accumulated) {
                    await host.handle(request, on: connection)
                    return
                }

                if error != nil || isComplete {
                    host.close(ObjectIdentifier(connection))
                    return
                }

                // 头还没收全，继续收；上限 1 MB 防止被撑爆。
                guard accumulated.count < 1_048_576 else {
                    host.close(ObjectIdentifier(connection))
                    return
                }
                host.receive(on: connection, buffer: accumulated)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) async {
        // 纵深防御：只接受「本地客户端」的请求。
        // token 已经能挡住没凭据的人，但浏览器里的任意网页都能往
        // 127.0.0.1 发请求（还会自动带 Origin），DNS rebinding 也能把
        // evil.com 指到这里。这两道检查成本几乎为零，先挡在前面。
        if let rejection = Self.requestRejectionReason(request) {
            respond(connection, status: 403, body: ["error": rejection])
            return
        }

        // 鉴权：除了 health，全部要求 Bearer token。
        if request.path != "/health" {
            let expected = "Bearer \(token ?? "")"
            guard request.headers["authorization"] == expected else {
                respond(connection, status: 401, body: ["error": "unauthorized"])
                return
            }
        }

        if request.path == "/health" {
            respond(connection, status: 200, body: ["ok": true, "tools": ToolRegistry.shared.allDescriptors.count])
            return
        }

        guard request.method == "POST", request.path == "/mcp" else {
            respond(connection, status: 404, body: ["error": "not found"])
            return
        }

        guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            respondJSONRPC(connection, id: nil, errorCode: -32700, errorMessage: "Parse error")
            return
        }

        // 通知（没有 id）不需要回包。
        guard payload["id"] != nil else {
            respond(connection, status: 202, body: nil)
            return
        }

        let result = await Self.handleRPC(payload)
        respondJSONRPC(
            connection,
            id: payload["id"],
            result: result.result,
            errorCode: result.errorCode,
            errorMessage: result.errorMessage
        )
    }

    // MARK: 请求来源校验

    /// 返回 nil 表示放行，否则是要写进 403 响应的原因。
    ///
    /// 规则刻意简单：
    /// - 带 `Origin` 头的一律拒绝。本地 MCP 客户端（DSH、curl）不会发这个头，
    ///   会发的只有浏览器——那正是我们要挡的。
    /// - `Host` 必须是 127.0.0.1 / localhost / [::1]，且端口对得上。
    ///   防的是 DNS rebinding：攻击者让 evil.com 解析到 127.0.0.1 后，
    ///   浏览器发出的 Host 仍然是 evil.com。
    nonisolated static func requestRejectionReason(_ request: HTTPRequest) -> String? {
        if request.headers["origin"] != nil {
            return "cross-origin requests are not allowed"
        }

        guard let host = request.headers["host"]?.lowercased(), !host.isEmpty else {
            return "missing Host header"
        }

        // 去掉端口后再比对；IPv6 字面量形如 [::1]:1234。
        let hostOnly: String
        if host.hasPrefix("[") {
            guard let closing = host.firstIndex(of: "]") else { return "invalid Host header" }
            hostOnly = String(host[host.startIndex...closing])
        } else if let colon = host.lastIndex(of: ":") {
            hostOnly = String(host[host.startIndex..<colon])
        } else {
            hostOnly = host
        }

        let allowed: Set<String> = ["127.0.0.1", "localhost", "[::1]"]
        guard allowed.contains(hostOnly) else {
            return "unexpected Host header"
        }
        return nil
    }

    // MARK: JSON-RPC

    struct RPCResult {
        var result: Any?
        var errorCode: Int?
        var errorMessage: String?
    }

    private static func handleRPC(_ payload: [String: Any]) async -> RPCResult {
        guard let method = payload["method"] as? String else {
            return RPCResult(errorCode: -32600, errorMessage: "Invalid Request")
        }

        switch method {
        case "initialize":
            return RPCResult(result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "coolrun", "version": "1.0.0"],
            ])

        case "ping":
            return RPCResult(result: [:])

        case "tools/list":
            let tools = ToolRegistry.shared.descriptors(upTo: AgentSettings.shared.toolLevel).map { descriptor -> [String: Any] in
                [
                    "name": descriptor.name,
                    "description": descriptor.summary,
                    "inputSchema": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor.parameters))) ?? [:],
                ]
            }
            return RPCResult(result: ["tools": tools])

        case "tools/call":
            guard let params = payload["params"] as? [String: Any],
                  let name = params["name"] as? String
            else {
                return RPCResult(errorCode: -32602, errorMessage: "Invalid params")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let argumentsJSON = (try? JSONSerialization.data(withJSONObject: arguments))
                .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .object([:])

            let result = await ToolRegistry.shared.execute(
                name: name,
                arguments: argumentsJSON,
                policy: ToolRegistry.ExecutionPolicy(
                    maxLevel: AgentSettings.shared.toolLevel,
                    approval: { descriptor, arguments in
                        await AgentCoordinator.shared.requestApproval(descriptor, arguments)
                    }
                )
            )
            return RPCResult(result: [
                "content": [["type": "text", "text": result.content]],
                "isError": result.isError,
            ])

        default:
            return RPCResult(errorCode: -32601, errorMessage: "Method not found: \(method)")
        }
    }

    // MARK: 响应

    private func respondJSONRPC(
        _ connection: NWConnection,
        id: Any?,
        result: Any? = nil,
        errorCode: Int? = nil,
        errorMessage: String? = nil
    ) {
        var body: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull()]
        if let errorCode {
            body["error"] = ["code": errorCode, "message": errorMessage ?? "error"]
        } else {
            body["result"] = result ?? [:]
        }
        respond(connection, status: 200, body: body)
    }

    private func respond(_ connection: NWConnection, status: Int, body: [String: Any]?) {
        let payload = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(payload.count)\r\n"
        head += "Connection: close\r\n\r\n"

        var response = Data(head.utf8)
        response.append(payload)

        connection.send(content: response, completion: .contentProcessed { _ in
            Task { @MainActor in
                CoolRunMCPHost.shared.close(ObjectIdentifier(connection))
            }
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}

// MARK: - 极简 HTTP 解析

/// 只解析 MCP 客户端会发的那点东西：请求行 + 头 + Content-Length 定长的 body。
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// 数据还不完整时返回 nil。
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        let headData = data[..<separator.lowerBound]
        guard let headText = String(data: headData, encoding: .utf8) else { return nil }

        var lines = headText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = separator.upperBound
        let available = data.count - bodyStart
        guard available >= contentLength else { return nil }

        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: body
        )
    }
}
