import XCTest
import Network
@testable import CoolRun

/// A minimal HTTP/1.1 server that answers every request with a fixed SSE body,
/// so the wire implementations can be exercised without a real LLM.
final class MockLLMServer {
    private let listener: NWListener
    private let responder: (String) -> String
    private let queue = DispatchQueue(label: "coolrun.mock-llm")
    private(set) var port: UInt16 = 0

    init(responder: @escaping (String) -> String) throws {
        self.responder = responder
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                self.port = self.listener.port?.rawValue ?? 0
                ready.signal()
            } else if case .failed = state {
                ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }

            if let separator = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: accumulated[..<separator.lowerBound], as: UTF8.self)
                var contentLength = 0
                for line in head.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
                    let value = line.split(separator: ":", maxSplits: 1).last ?? ""
                    contentLength = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
                }
                let bodyStart = separator.upperBound
                if accumulated.count - bodyStart >= contentLength {
                    let body = String(decoding: accumulated[bodyStart...], as: UTF8.self)
                    self.respond(connection, requestBody: body)
                    return
                }
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receive(connection, buffer: accumulated)
        }
    }

    private func respond(_ connection: NWConnection, requestBody: String) {
        let payload = Data(responder(requestBody).utf8)
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: text/event-stream\r\n"
        response += "Connection: close\r\n"
        response += "Content-Length: \(payload.count)\r\n\r\n"
        var outbound = Data(response.utf8)
        outbound.append(payload)
        connection.send(content: outbound, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

final class AgentWireTests: XCTestCase {

    private func openAITextStream(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        data: {"choices":[{"delta":{"content":"\(escaped)"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """
    }

    private func openAIToolCallStream(name: String, arguments: String) -> String {
        let escapedArgs = arguments.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"\(name)","arguments":""}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\(escapedArgs)"}}]}}]}

        data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]


        """
    }

    @MainActor
    func testOpenAIChatParsesTextAndToolCalls() async throws {
        let server = try MockLLMServer { _ in
            """
            data: {"choices":[{"delta":{"content":"你好"}}]}

            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"system_snapshot","arguments":""}}]}}]}

            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{}"}}]}}]}

            data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

            data: [DONE]


            """
        }
        defer { server.stop() }

        let config = AgentRunConfig(
            protocolKind: .openAIChat,
            apiKey: "test",
            baseURL: "http://127.0.0.1:\(server.port)",
            model: "mock",
            temperature: 0.2,
            maxTokens: 256,
            maxRounds: 2
        )

        let wire = AgentWireFactory.make(.openAIChat)
        var text = ""
        var starts: [(Int, String?, String)] = []
        var fragments: [String: String] = [:]
        var finishReason: String?

        let stream = try await wire.stream(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            config: config
        )
        for try await event in stream {
            switch event {
            case .text(let value):
                text += value
            case .reasoning:
                break
            case .toolCallStart(let index, let id, let name):
                starts.append((index, id, name))
            case .toolCallArguments(let index, let fragment):
                fragments[String(index), default: ""] += fragment
            case .finished(let reason):
                finishReason = reason
            }
        }

        XCTAssertEqual(text, "你好")
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(starts.first?.1, "call_1")
        XCTAssertEqual(starts.first?.2, "system_snapshot")
        XCTAssertEqual(fragments["0"], "{}")
        XCTAssertEqual(finishReason, "tool_calls")
    }

    @MainActor
    func testOpenAIResponsesParsesText() async throws {
        let server = try MockLLMServer { _ in
            """
            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"响应"}

            event: response.completed
            data: {"type":"response.completed","response":{"id":"resp_1"}}

            """
        }
        defer { server.stop() }

        let config = AgentRunConfig(
            protocolKind: .openAIResponses,
            apiKey: "test",
            baseURL: "http://127.0.0.1:\(server.port)",
            model: "mock",
            temperature: 0.2,
            maxTokens: 256,
            maxRounds: 2
        )

        let wire = AgentWireFactory.make(.openAIResponses)
        var text = ""
        let stream = try await wire.stream(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            config: config
        )
        for try await event in stream {
            if case .text(let value) = event { text += value }
        }
        XCTAssertEqual(text, "响应")
    }

    @MainActor
    func testSwiftAgentEngineExecutesToolRoundTrip() async throws {
        AgentTools.registerAll()

        let server = try MockLLMServer { requestBody in
            if requestBody.contains("\"role\":\"tool\"") {
                return self.openAITextStream("系统运行正常")
            }
            return self.openAIToolCallStream(name: "system_snapshot", arguments: "{}")
        }
        defer { server.stop() }

        let engine = SwiftAgentEngine()
        let config = AgentRunConfig(
            protocolKind: .openAIChat,
            apiKey: "test",
            baseURL: "http://127.0.0.1:\(server.port)",
            model: "mock",
            temperature: 0.2,
            maxTokens: 512,
            maxRounds: 4
        )

        var text = ""
        var started: [String] = []
        var finished: [(String, Bool)] = []

        let stream = engine.run(prompt: "现在系统怎么样", history: [], config: config)
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                text += delta
            case .toolCallStarted(_, let name, _):
                started.append(name)
            case .toolCallFinished(_, let name, _, let isError):
                finished.append((name, isError))
            case .turnFinished:
                break
            case .reasoningDelta, .confirmationRequired:
                break
            }
        }

        XCTAssertEqual(started, ["system_snapshot"])
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished.first?.0, "system_snapshot")
        XCTAssertEqual(finished.first?.1, false)
        XCTAssertTrue(text.contains("系统运行正常"), "最终文本: \(text)")
    }

    @MainActor
    func testOllamaParsesTextAndToolCalls() async throws {
        let server = try MockLLMServer { _ in
            """
            {"model":"mock","message":{"role":"assistant","content":"你好"},"done":false}
            {"model":"mock","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"system_snapshot","arguments":{}}}]},"done":false}
            {"model":"mock","message":{"role":"assistant","content":""},"done":true}


            """
        }
        defer { server.stop() }

        let config = AgentRunConfig(
            protocolKind: .ollama,
            apiKey: "",
            baseURL: "http://127.0.0.1:\(server.port)",
            model: "mock",
            temperature: 0.2,
            maxTokens: 256,
            maxRounds: 2
        )

        let wire = AgentWireFactory.make(.ollama)
        var text = ""
        var names: [String] = []
        var arguments = ""
        var finishReason: String?

        let stream = try await wire.stream(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            config: config
        )
        for try await event in stream {
            switch event {
            case .text(let value):
                text += value
            case .toolCallStart(_, _, let name):
                names.append(name)
            case .toolCallArguments(_, let fragment):
                arguments += fragment
            case .finished(let reason):
                finishReason = reason
            case .reasoning:
                break
            }
        }

        XCTAssertEqual(text, "你好")
        XCTAssertEqual(names, ["system_snapshot"])
        XCTAssertEqual(arguments, "{}")
        XCTAssertEqual(finishReason, "tool_calls")
    }

    @MainActor
    func testAnthropicParsesTextAndToolUse() async throws {
        let server = try MockLLMServer { _ in
            """
            event: message_start
            data: {"type":"message_start","message":{"id":"msg_1"}}

            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好"}}

            event: content_block_start
            data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"system_snapshot","input":{}}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{}"}}

            event: message_delta
            data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}

            event: message_stop
            data: {"type":"message_stop"}


            """
        }
        defer { server.stop() }

        let config = AgentRunConfig(
            protocolKind: .anthropicMessages,
            apiKey: "test",
            baseURL: "http://127.0.0.1:\(server.port)",
            model: "mock",
            temperature: 0.2,
            maxTokens: 256,
            maxRounds: 2
        )

        let wire = AgentWireFactory.make(.anthropicMessages)
        var text = ""
        var names: [(Int, String, String)] = []
        var arguments = ""
        var finishReasons: [String] = []

        let stream = try await wire.stream(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            config: config
        )
        for try await event in stream {
            switch event {
            case .text(let value):
                text += value
            case .toolCallStart(let index, let id, let name):
                names.append((index, id, name))
            case .toolCallArguments(_, let fragment):
                arguments += fragment
            case .finished(let reason):
                finishReasons.append(reason)
            case .reasoning:
                break
            }
        }

        XCTAssertEqual(text, "你好")
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(names.first?.0, 1)
        XCTAssertEqual(names.first?.1, "toolu_1")
        XCTAssertEqual(names.first?.2, "system_snapshot")
        XCTAssertEqual(arguments, "{}")
        XCTAssertEqual(finishReasons.first, "tool_use")
    }
}
