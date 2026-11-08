import Foundation

// MARK: - Wire 事件

/// 四种接入协议解析后的统一事件。
enum WireEvent: Sendable {
    case text(String)
    case reasoning(String)
    case toolCallStart(index: Int, id: String, name: String)
    case toolCallArguments(index: Int, fragment: String)
    case finished(reason: String)
}

// MARK: - Wire 协议

/// 只负责「把统一消息翻译成某种 HTTP 协议，再把 SSE 翻译回统一事件」。
/// 不碰工具执行、不碰权限、不碰 UI。
protocol AgentWire: Sendable {
    nonisolated func stream(
        messages: [AgentMessage],
        tools: [ToolDescriptor],
        config: AgentRunConfig
    ) async throws -> AsyncThrowingStream<WireEvent, Error>
}

nonisolated enum AgentWireFactory {
    static func make(_ kind: AgentWireProtocol) -> any AgentWire {
        switch kind {
        case .openAIChat: return OpenAIChatWire()
        case .openAIResponses: return OpenAIResponsesWire()
        case .anthropicMessages: return AnthropicWire()
        case .ollama: return OllamaWire()
        }
    }
}

// MARK: - 公共工具

nonisolated enum WireSupport {
    static func url(base: String, path: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        // 用户可能把 baseURL 填成 https://host/v1，避免拼出 /v1/v1/...
        if trimmed.hasSuffix("/v1"), path.hasPrefix("/v1/") {
            return URL(string: trimmed + String(path.dropFirst(3)))
        }
        return URL(string: trimmed + path)
    }

    static func errorMessage(from data: Data) -> String {
        if let value = try? JSONDecoder().decode(JSONValue.self, from: data),
           let message = value["error"]?["message"]?.stringValue {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    static func openStream(_ request: URLRequest) async throws -> URLSession.AsyncBytes {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.invalidResponse("非 HTTP 响应")
        }
        guard http.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 8192 { break }
            }
            throw AgentError.http(status: http.statusCode, message: errorMessage(from: data))
        }
        return bytes
    }

    static func ssePayload(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        return payload.isEmpty ? nil : payload
    }
}

// MARK: - OpenAI Chat Completions

struct OpenAIChatWire: AgentWire {
    nonisolated init() {}

    nonisolated func stream(
        messages: [AgentMessage],
        tools: [ToolDescriptor],
        config: AgentRunConfig
    ) async throws -> AsyncThrowingStream<WireEvent, Error> {
        guard let url = WireSupport.url(base: config.baseURL, path: "/v1/chat/completions") else {
            throw AgentError.invalidEndpoint(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 180

        var body: [String: JSONValue] = [
            "model": .string(config.model),
            "messages": .array(Self.encode(messages)),
            "temperature": .number(config.temperature),
            "max_tokens": .number(Double(config.maxTokens)),
            "stream": .bool(true),
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { $0.openAISchema })
            body["tool_choice"] = .string("auto")
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let bytes = try await WireSupport.openStream(request)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard let payload = WireSupport.ssePayload(line) else { continue }
                        if payload == "[DONE]" { break }
                        guard let value = JSONValue.parse(payload),
                              let choices = value["choices"]?.arrayValue,
                              let first = choices.first
                        else { continue }

                        if let delta = first["delta"] {
                            if let text = delta["content"]?.stringValue, !text.isEmpty {
                                continuation.yield(.text(text))
                            }
                            if let reasoning = delta["reasoning_content"]?.stringValue, !reasoning.isEmpty {
                                continuation.yield(.reasoning(reasoning))
                            }
                            for call in delta["tool_calls"]?.arrayValue ?? [] {
                                let index = call["index"]?.intValue ?? 0
                                if let id = call["id"]?.stringValue,
                                   let name = call["function"]?["name"]?.stringValue {
                                    continuation.yield(.toolCallStart(index: index, id: id, name: name))
                                }
                                if let fragment = call["function"]?["arguments"]?.stringValue,
                                   !fragment.isEmpty {
                                    continuation.yield(.toolCallArguments(index: index, fragment: fragment))
                                }
                            }
                        }

                        if let reason = first["finish_reason"]?.stringValue {
                            continuation.yield(.finished(reason: reason))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    nonisolated static func encode(_ messages: [AgentMessage]) -> [JSONValue] {
        messages.map { message in
            switch message.role {
            case .system, .user:
                return .object([
                    "role": .string(message.role.rawValue),
                    "content": .string(message.content),
                ])
            case .assistant:
                var object: [String: JSONValue] = ["role": .string("assistant")]
                object["content"] = message.content.isEmpty ? .null : .string(message.content)
                if !message.toolCalls.isEmpty {
                    object["tool_calls"] = .array(message.toolCalls.map { call in
                        .object([
                            "id": .string(call.id),
                            "type": .string("function"),
                            "function": .object([
                                "name": .string(call.name),
                                "arguments": .string(call.argumentsText),
                            ]),
                        ])
                    })
                }
                return .object(object)
            case .tool:
                return .object([
                    "role": .string("tool"),
                    "tool_call_id": .string(message.toolCallID ?? ""),
                    "content": .string(message.content),
                ])
            }
        }
    }
}

// MARK: - OpenAI Responses

struct OpenAIResponsesWire: AgentWire {
    nonisolated init() {}

    nonisolated func stream(
        messages: [AgentMessage],
        tools: [ToolDescriptor],
        config: AgentRunConfig
    ) async throws -> AsyncThrowingStream<WireEvent, Error> {
        guard let url = WireSupport.url(base: config.baseURL, path: "/v1/responses") else {
            throw AgentError.invalidEndpoint(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 180

        let instructions = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")

        var body: [String: JSONValue] = [
            "model": .string(config.model),
            "input": .array(Self.encode(messages)),
            "temperature": .number(config.temperature),
            "max_output_tokens": .number(Double(config.maxTokens)),
            "stream": .bool(true),
        ]
        if !instructions.isEmpty {
            body["instructions"] = .string(instructions)
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { tool in
                .object([
                    "type": .string("function"),
                    "name": .string(tool.name),
                    "description": .string(tool.summary),
                    "parameters": tool.parameters,
                ])
            })
            body["tool_choice"] = .string("auto")
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let bytes = try await WireSupport.openStream(request)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var indexByItemID: [String: Int] = [:]
                    var nextIndex = 0

                    for try await line in bytes.lines {
                        guard let payload = WireSupport.ssePayload(line) else { continue }
                        if payload == "[DONE]" { break }
                        guard let value = JSONValue.parse(payload),
                              let type = value["type"]?.stringValue
                        else { continue }

                        switch type {
                        case "response.output_text.delta":
                            if let delta = value["delta"]?.stringValue, !delta.isEmpty {
                                continuation.yield(.text(delta))
                            }
                        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
                            if let delta = value["delta"]?.stringValue, !delta.isEmpty {
                                continuation.yield(.reasoning(delta))
                            }
                        case "response.output_item.added":
                            guard let item = value["item"],
                                  item["type"]?.stringValue == "function_call",
                                  let itemID = item["id"]?.stringValue
                            else { break }
                            let index = nextIndex
                            nextIndex += 1
                            indexByItemID[itemID] = index
                            continuation.yield(.toolCallStart(
                                index: index,
                                id: item["call_id"]?.stringValue ?? itemID,
                                name: item["name"]?.stringValue ?? ""
                            ))
                        case "response.function_call_arguments.delta":
                            guard let itemID = value["item_id"]?.stringValue,
                                  let index = indexByItemID[itemID],
                                  let fragment = value["delta"]?.stringValue,
                                  !fragment.isEmpty
                            else { break }
                            continuation.yield(.toolCallArguments(index: index, fragment: fragment))
                        case "response.completed":
                            continuation.yield(.finished(reason: "completed"))
                        case "response.failed", "error":
                            let message = value["error"]?["message"]?.stringValue
                                ?? value["response"]?["error"]?["message"]?.stringValue
                                ?? "Responses API 返回错误"
                            throw AgentError.invalidResponse(message)
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    nonisolated static func encode(_ messages: [AgentMessage]) -> [JSONValue] {
        var items: [JSONValue] = []
        for message in messages {
            switch message.role {
            case .system:
                // system 走顶层 instructions，这里跳过
                continue
            case .user:
                items.append(.object([
                    "role": .string("user"),
                    "content": .string(message.content),
                ]))
            case .assistant:
                if !message.content.isEmpty {
                    items.append(.object([
                        "role": .string("assistant"),
                        "content": .array([
                            .object([
                                "type": .string("output_text"),
                                "text": .string(message.content),
                            ]),
                        ]),
                    ]))
                }
                for call in message.toolCalls {
                    items.append(.object([
                        "type": .string("function_call"),
                        "call_id": .string(call.id),
                        "name": .string(call.name),
                        "arguments": .string(call.argumentsText),
                    ]))
                }
            case .tool:
                items.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(message.toolCallID ?? ""),
                    "output": .string(message.content),
                ]))
            }
        }
        return items
    }
}

// MARK: - Anthropic Messages

struct AnthropicWire: AgentWire {
    nonisolated init() {}

    nonisolated func stream(
        messages: [AgentMessage],
        tools: [ToolDescriptor],
        config: AgentRunConfig
    ) async throws -> AsyncThrowingStream<WireEvent, Error> {
        guard let url = WireSupport.url(base: config.baseURL, path: "/v1/messages") else {
            throw AgentError.invalidEndpoint(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 180

        let system = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")

        var body: [String: JSONValue] = [
            "model": .string(config.model),
            "messages": .array(Self.encode(messages)),
            "max_tokens": .number(Double(config.maxTokens)),
            "temperature": .number(config.temperature),
            "stream": .bool(true),
        ]
        if !system.isEmpty {
            body["system"] = .string(system)
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { $0.anthropicSchema })
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let bytes = try await WireSupport.openStream(request)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard let payload = WireSupport.ssePayload(line) else { continue }
                        guard let value = JSONValue.parse(payload),
                              let type = value["type"]?.stringValue
                        else { continue }

                        switch type {
                        case "content_block_start":
                            let index = value["index"]?.intValue ?? 0
                            guard let block = value["content_block"],
                                  block["type"]?.stringValue == "tool_use"
                            else { break }
                            continuation.yield(.toolCallStart(
                                index: index,
                                id: block["id"]?.stringValue ?? UUID().uuidString,
                                name: block["name"]?.stringValue ?? ""
                            ))
                        case "content_block_delta":
                            let index = value["index"]?.intValue ?? 0
                            guard let delta = value["delta"] else { break }
                            switch delta["type"]?.stringValue {
                            case "text_delta":
                                if let text = delta["text"]?.stringValue, !text.isEmpty {
                                    continuation.yield(.text(text))
                                }
                            case "input_json_delta":
                                if let fragment = delta["partial_json"]?.stringValue, !fragment.isEmpty {
                                    continuation.yield(.toolCallArguments(index: index, fragment: fragment))
                                }
                            case "thinking_delta":
                                if let thinking = delta["thinking"]?.stringValue, !thinking.isEmpty {
                                    continuation.yield(.reasoning(thinking))
                                }
                            default:
                                break
                            }
                        case "message_delta":
                            if let reason = value["delta"]?["stop_reason"]?.stringValue {
                                continuation.yield(.finished(reason: reason))
                            }
                        case "message_stop":
                            continuation.yield(.finished(reason: "end_turn"))
                        case "error":
                            throw AgentError.invalidResponse(
                                value["error"]?.compactJSONString() ?? "Anthropic 返回错误"
                            )
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Anthropic 的 tool 结果必须作为 user 消息里的 tool_result block 回传。
    nonisolated static func encode(_ messages: [AgentMessage]) -> [JSONValue] {
        var result: [JSONValue] = []

        for message in messages {
            switch message.role {
            case .system:
                continue
            case .user:
                result.append(.object([
                    "role": .string("user"),
                    "content": .string(message.content),
                ]))
            case .assistant:
                var blocks: [JSONValue] = []
                if !message.content.isEmpty {
                    blocks.append(.object([
                        "type": .string("text"),
                        "text": .string(message.content),
                    ]))
                }
                for call in message.toolCalls {
                    blocks.append(.object([
                        "type": .string("tool_use"),
                        "id": .string(call.id),
                        "name": .string(call.name),
                        "input": call.arguments,
                    ]))
                }
                if !blocks.isEmpty {
                    result.append(.object([
                        "role": .string("assistant"),
                        "content": .array(blocks),
                    ]))
                }
            case .tool:
                let block: JSONValue = .object([
                    "type": .string("tool_result"),
                    "tool_use_id": .string(message.toolCallID ?? ""),
                    "content": .string(message.content),
                    "is_error": .bool(message.isError),
                ])
                // 连续多个 tool 结果合并进同一条 user 消息
                if var last = result.last,
                   last["role"]?.stringValue == "user",
                   var blocks = last["content"]?.arrayValue,
                   blocks.contains(where: { $0["type"]?.stringValue == "tool_result" }) {
                    blocks.append(block)
                    last["content"] = .array(blocks)
                    result[result.count - 1] = last
                } else {
                    result.append(.object([
                        "role": .string("user"),
                        "content": .array([block]),
                    ]))
                }
            }
        }

        return result
    }
}

// MARK: - Ollama

struct OllamaWire: AgentWire {
    nonisolated init() {}

    nonisolated func stream(
        messages: [AgentMessage],
        tools: [ToolDescriptor],
        config: AgentRunConfig
    ) async throws -> AsyncThrowingStream<WireEvent, Error> {
        guard let url = WireSupport.url(base: config.baseURL, path: "/api/chat") else {
            throw AgentError.invalidEndpoint(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        var body: [String: JSONValue] = [
            "model": .string(config.model),
            "messages": .array(Self.encode(messages)),
            "stream": .bool(true),
            "options": .object(["temperature": .number(config.temperature)]),
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { $0.openAISchema })
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let bytes = try await WireSupport.openStream(request)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var emittedToolCalls = false
                    for try await line in bytes.lines {
                        guard let value = JSONValue.parse(line),
                              let message = value["message"]
                        else { continue }

                        if let text = message["content"]?.stringValue, !text.isEmpty {
                            continuation.yield(.text(text))
                        }
                        if let thinking = message["thinking"]?.stringValue, !thinking.isEmpty {
                            continuation.yield(.reasoning(thinking))
                        }

                        // Ollama 的工具调用是一次性返回的，不是增量
                        if let calls = message["tool_calls"]?.arrayValue, !calls.isEmpty {
                            for (index, call) in calls.enumerated() {
                                guard let function = call["function"],
                                      let name = function["name"]?.stringValue
                                else { continue }
                                let id = call["id"]?.stringValue ?? "ollama-call-\(index)"
                                continuation.yield(.toolCallStart(index: index, id: id, name: name))
                                let arguments = function["arguments"] ?? .object([:])
                                continuation.yield(.toolCallArguments(
                                    index: index,
                                    fragment: arguments.compactJSONString()
                                ))
                            }
                            emittedToolCalls = true
                        }

                        if value["done"]?.boolValue == true {
                            continuation.yield(.finished(reason: emittedToolCalls ? "tool_calls" : "stop"))
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    nonisolated static func encode(_ messages: [AgentMessage]) -> [JSONValue] {
        var result: [JSONValue] = []
        for message in messages {
            switch message.role {
            case .system, .user:
                result.append(.object([
                    "role": .string(message.role.rawValue),
                    "content": .string(message.content),
                ]))
            case .assistant:
                var object: [String: JSONValue] = [
                    "role": .string("assistant"),
                    "content": .string(message.content),
                ]
                if !message.toolCalls.isEmpty {
                    object["tool_calls"] = .array(message.toolCalls.map { call in
                        .object([
                            "function": .object([
                                "name": .string(call.name),
                                "arguments": call.arguments,
                            ]),
                        ])
                    })
                }
                result.append(.object(object))
            case .tool:
                result.append(.object([
                    "role": .string("tool"),
                    "content": .string(message.content),
                    "tool_name": .string(message.toolName ?? ""),
                ]))
            }
        }
        return result
    }
}
