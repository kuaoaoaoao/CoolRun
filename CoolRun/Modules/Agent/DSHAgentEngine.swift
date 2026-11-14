import Foundation

/// 用 DSH（DeepSeek Harness）当引擎。
///
/// 它是个独立进程：我们 spawn 一个打包好的 Node 运行时，走 JSON-RPC over stdio
/// 驱动它，工具则通过 CoolRunMCPHost 反向回连到本进程。
@MainActor
final class DSHAgentEngine: AgentEngine {
    let kind: AgentEngineKind = .dsh

    var displayName: String { "DeepSeek Harness" }

    var isAvailable: Bool { AgentRuntimeLocator.shared.runtime != nil }

    private var client: DSHJSONRPCClient?
    private var sessionId = UUID().uuidString
    private var runTask: Task<Void, Never>?
    private var configSignature = ""

    func run(
        prompt: String,
        history: [AgentMessage],
        config: AgentRunConfig
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let client = try await ensureStarted(config: config)
                    continuation.yield(.textDelta(""))

                    // 历史压成一段文本前置，DSH 的 session 是它自己维护的，
                    // 我们这边只负责把上下文递过去。
                    let composed = Self.compose(prompt: prompt, history: history)

                    let result = try await client.request(
                        method: "session/prompt",
                        params: .object([
                            "sessionId": .string(sessionId),
                            "contentBlocks": .array([
                                .object(["type": .string("text"), "text": .string(composed)]),
                            ]),
                        ])
                    )
                    _ = result

                    var finished = false
                    var pending: [String] = []
                    for await notification in client.notifications {
                        for event in Self.translate(notification, pending: &pending) {
                            continuation.yield(event)
                            if case .turnFinished = event { finished = true }
                        }
                        if finished { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            runTask = task
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
    }

    func shutdown() {
        cancel()
        client?.stop()
        client = nil
    }

    // MARK: 进程

    private func ensureStarted(config: AgentRunConfig) async throws -> DSHJSONRPCClient {
        let signature = "\(config.protocolKind.rawValue)|\(config.baseURL)|\(config.model)|\(config.apiKey)"
        if let client, client.isRunning, signature == configSignature {
            return client
        }

        client?.stop()
        client = nil

        guard let runtime = AgentRuntimeLocator.shared.runtime else {
            throw AgentError.notConfigured
        }

        // MCP 服务器要先起来，patch 里才拿得到端口和 token。
        if CoolRunMCPHost.shared.endpoint == nil {
            CoolRunMCPHost.shared.start()
            for _ in 0..<20 {
                if CoolRunMCPHost.shared.endpoint != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        let patchURL = try Self.writePatch(
            config: config,
            endpoint: CoolRunMCPHost.shared.endpoint,
            token: CoolRunMCPHost.shared.token
        )
        let home = Self.homeDirectory()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        var environment = ProcessInfo.processInfo.environment
        environment["DSH_HOME"] = home.path
        // pkg 打包的 native addon 必须有自己的缓存目录，否则会和别的副本打架。
        environment["PKG_NATIVE_CACHE_PATH"] = home.appendingPathComponent("pkgcache").path
        environment["COOLRUN_LLM_KEY"] = config.apiKey
        environment["COOLRUN_LLM_BASE"] = config.baseURL
        environment["COOLRUN_LLM_MODEL"] = config.model

        let client = DSHJSONRPCClient()
        do {
            try client.start(
                executable: runtime.executable,
                arguments: ["--profile", "sdk-minimal", "--patch", patchURL.path],
                environment: environment
            )

            _ = try await client.request(
                method: "initialize",
                params: .object([
                    "cwd": .string(FileManager.default.homeDirectoryForCurrentUser.path),
                    "provider": .string("coolrun"),
                    "model": .string(config.model),
                ])
            )
        } catch {
            // 初始化失败时这个 client 还没挂到 self 上，不主动收尸就会留下一个
            // 孤儿 dsh 进程（几百 MB 常驻），下次换引擎时它的退出回调还要来砸门。
            client.stop()
            throw error
        }

        self.client = client
        self.configSignature = signature
        return client
    }

    private nonisolated static func homeDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CoolRun/agent-home", isDirectory: true)
    }

    /// 生成 DSH 的 patch：把我们的 provider 和 MCP 服务器插进去。
    ///
    /// 注意：这段 YAML 的字段名来自 dsh 的 profile patch 语法，改动前先用
    /// `--dump-config` 验证一遍。
    nonisolated static func writePatch(
        config: AgentRunConfig,
        endpoint: URL?,
        token: String?
    ) throws -> URL {
        let api = switch config.protocolKind {
        case .openAIChat, .ollama: "openai-completions"
        case .openAIResponses: "openai-responses"
        case .anthropicMessages: "anthropic-messages"
        }

        // 用逐行拼接而不是多行字符串：这里必须从第 0 列开始，多行字面量的
        // 缩进剥离会把它变成嵌套在上一项里的非法 YAML。
        var mcpBlock = ""
        if let endpoint, let token {
            // sdk-minimal 里没有 mcp-coolrun 这一行，必须用 insert 新增，
            // 直接写 `- id:` 会被当成覆盖并报 "entry not found"。
            mcpBlock = [
                "- insert:",
                "    - id: mcp-coolrun",
                "      name: '@deepseek-ai/dsh-mcp-client'",
                "      config:",
                "        serverName: coolrun",
                "        transport: streamable-http",
                "        url: \(endpoint.absoluteString)",
                "        headers:",
                "          Authorization: 'Bearer \(token)'",
                "        failOnStartupError: true",
            ].joined(separator: "\n")
        }

        let base = """
        - insert:
            - id: llm-pi-ai
              name: '@deepseek-ai/dsh-llm-pi-ai'
              config:
                providers:
                  coolrun:
                    apiKeyEnv: COOLRUN_LLM_KEY
                    api: \(api)
                    baseURL: \(config.baseURL)
                    models:
                      - id: \(config.model)

        # 关掉 DSH 自带的 shell 和文件工具：CoolRun 的权限闸门管不到它们，
        # 而一个菜单栏小工具不该让模型随便执行命令。
        - id: persistent-bash
          disabled: true
        - id: terminal-bash
          disabled: true
        - id: terminal-pwsh
          disabled: true
        """

        let yaml = mcpBlock.isEmpty ? base : base + "\n" + mcpBlock

        let url = homeDirectory().appendingPathComponent("coolrun.patch.yml")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        // 这个文件里带着 MCP 的 Bearer token（DSH 要用它回连我们），
        // 默认 0644 意味着同一台机器上别的用户/进程能读到，收紧成 0600。
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return url
    }

    // MARK: 事件翻译

    private nonisolated static func compose(prompt: String, history: [AgentMessage]) -> String {
        let recent = history.suffix(12)
        guard !recent.isEmpty else { return prompt }
        let context = recent.compactMap { message -> String? in
            guard !message.content.isEmpty else { return nil }
            let who = switch message.role {
            case .user: "用户"
            case .assistant: "助手"
            case .system: "系统"
            case .tool: "工具"
            }
            return "\(who)：\(message.content)"
        }
        guard !context.isEmpty else { return prompt }
        return """
        以下是之前的对话，供参考：
        \(context.joined(separator: "\n"))

        现在：\(prompt)
        """
    }

    private nonisolated static func translate(_ notification: JSONValue, pending: inout [String]) -> [AgentEvent] {
        guard let object = notification.objectValue,
              let method = object["__method"]?.stringValue
        else { return [] }

        // 只有 agent 整体回到 idle 才算这一轮真的结束；turn/end 只是单轮结束，
        // 后面可能还有工具结果驱动的下一轮。
        if method == "session.status" {
            return object["status"]?.stringValue == "idle" ? [.turnFinished] : []
        }

        guard method == "session.event",
              let event = object["event"]?.objectValue,
              let type = event["type"]?.stringValue
        else { return [] }

        let data = event["data"]?.objectValue ?? [:]

        switch type {
        case "assistant/chunk":
            guard let chunk = data["chunk"]?.objectValue,
                  let chunkType = chunk["type"]?.stringValue,
                  let text = chunk["text"]?.stringValue
            else { return [] }
            switch chunkType {
            case "text-delta": return [.textDelta(text)]
            case "reasoning-delta": return [.reasoningDelta(text)]
            default: return []
            }

        case "assistant/message":
            guard let message = data["message"]?.objectValue,
                  let blocks = message["content"]?.arrayValue
            else { return [] }

            // 上一轮发起的工具调用到这里就算结束了 —— DSH 内部自己执行，
            // 结果不会单独推给我们。
            var events: [AgentEvent] = pending.map {
                .toolCallFinished(id: $0, name: $0, output: "已完成", isError: false)
            }
            pending.removeAll()
            for block in blocks {
                guard let block = block.objectValue,
                      let blockType = block["type"]?.stringValue
                else { continue }

                switch blockType {
                case "text":
                    if let text = block["text"]?.stringValue, !text.isEmpty {
                        events.append(.textDelta(text))
                    }
                case "reasoning":
                    if let text = block["text"]?.stringValue, !text.isEmpty {
                        events.append(.reasoningDelta(text))
                    }
                case "tool_use", "tool-call":
                    guard let name = block["name"]?.stringValue else { continue }
                    let id = block["id"]?.stringValue ?? name
                    let arguments = block["arguments"] ?? block["input"] ?? .object([:])
                    pending.append(id)
                    events.append(.toolCallStarted(id: id, name: name, arguments: arguments))
                default:
                    continue
                }
            }
            return events

        default:
            return []
        }
    }
}
