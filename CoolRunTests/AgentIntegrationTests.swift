import XCTest
@testable import CoolRun

/// 真实模型联调。默认跳过，只有显式提供环境变量时才运行，因此不会拖慢常规 CI。
///
/// 用法（xcodebuild 会把 `TEST_RUNNER_` 前缀去掉后传给测试进程）：
/// ```
/// TEST_RUNNER_AGENT_IT_BASEURL=http://localhost:7863 \
/// TEST_RUNNER_AGENT_IT_KEY=sk-xxx \
/// TEST_RUNNER_AGENT_IT_MODEL=global:deepseek-v4.1-flash \
/// xcodebuild ... -only-testing:CoolRunTests/AgentIntegrationTests test
/// ```
final class AgentIntegrationTests: XCTestCase {

    private func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func requireRemote() throws -> (baseURL: String, apiKey: String, model: String) {
        guard let baseURL = env("AGENT_IT_BASEURL"),
              let apiKey = env("AGENT_IT_KEY") else {
            throw XCTSkip("未设置 AGENT_IT_BASEURL / AGENT_IT_KEY，跳过真实模型联调")
        }
        let model = env("AGENT_IT_MODEL") ?? "global:deepseek-v4.1-flash"
        return (baseURL, apiKey, model)
    }

    @MainActor
    func testRemoteChatCallsToolAndAnswers() async throws {
        let remote = try requireRemote()
        AgentTools.registerAll()

        let engine = SwiftAgentEngine()
        let config = AgentRunConfig(
            protocolKind: .openAIChat,
            apiKey: remote.apiKey,
            baseURL: remote.baseURL,
            model: remote.model,
            temperature: 0.2,
            maxTokens: 1024,
            maxRounds: 4
        )

        var text = ""
        var started: [String] = []
        var finished: [(name: String, isError: Bool)] = []
        var failure: Error?

        let stream = engine.run(prompt: "用 system_snapshot 工具查一下当前 CPU 和内存使用率，然后用一句话总结。", history: [], config: config)
        do {
            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    text += delta
                case .toolCallStarted(_, let name, _):
                    started.append(name)
                case .toolCallFinished(_, let name, _, let isError):
                    finished.append((name, isError))
                case .turnFinished, .reasoningDelta, .confirmationRequired:
                    break
                }
            }
        } catch {
            failure = error
        }

        XCTAssertNil(failure, "引擎报错: \(String(describing: failure))")
        XCTAssertTrue(started.contains("system_snapshot"), "模型没有调用工具，实际调用: \(started)")
        XCTAssertFalse(finished.contains { $0.isError }, "工具执行失败: \(finished)")
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "最终回答为空")
    }

    @MainActor
    func testRemoteMultiTurnHistory() async throws {
        let remote = try requireRemote()
        let engine = SwiftAgentEngine()
        let config = AgentRunConfig(
            protocolKind: .openAIChat,
            apiKey: remote.apiKey,
            baseURL: remote.baseURL,
            model: remote.model,
            temperature: 0.2,
            maxTokens: 256,
            maxRounds: 2
        )

        let history = [
            AgentMessage(role: .user, content: "记住数字 42"),
            AgentMessage(role: .assistant, content: "记住了，是 42。"),
        ]
        var text = ""
        let stream = engine.run(prompt: "我刚才让你记的数字是多少？只回答数字。", history: history, config: config)
        for try await event in stream {
            if case .textDelta(let delta) = event { text += delta }
        }
        XCTAssertTrue(text.contains("42"), "上下文未生效，回答: \(text)")
    }

    /// 本地 Ollama 联调。需要 `AGENT_IT_OLLAMA_MODEL`（例如 `qwen2.5:3b`）。
    @MainActor
    func testOllamaLocalChatCallsTool() async throws {
        guard let model = env("AGENT_IT_OLLAMA_MODEL") else {
            throw XCTSkip("未设置 AGENT_IT_OLLAMA_MODEL，跳过本地模型联调")
        }
        AgentTools.registerAll()

        let engine = SwiftAgentEngine()
        let config = AgentRunConfig(
            protocolKind: .ollama,
            apiKey: "",
            baseURL: env("AGENT_IT_OLLAMA_BASEURL") ?? "http://localhost:11434",
            model: model,
            temperature: 0.2,
            maxTokens: 512,
            maxRounds: 4
        )

        var text = ""
        var started: [String] = []
        var finished: [(name: String, isError: Bool)] = []
        var failure: Error?

        let stream = engine.run(prompt: "查一下当前系统状态，用 system_snapshot 工具，然后一句话总结。", history: [], config: config)
        do {
            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    text += delta
                case .toolCallStarted(_, let name, _):
                    started.append(name)
                case .toolCallFinished(_, let name, _, let isError):
                    finished.append((name, isError))
                case .turnFinished, .reasoningDelta, .confirmationRequired:
                    break
                }
            }
        } catch {
            failure = error
        }

        let toolCount = ToolRegistry.shared.descriptors(upTo: AgentSettings.shared.toolLevel).count
        XCTAssertNil(failure, "引擎报错: \(String(describing: failure))")
        XCTAssertTrue(started.contains("system_snapshot"), "模型没有调用工具。已注册工具数=\(toolCount)，文本=[\(text)]，调用=\(started)")
        XCTAssertFalse(finished.contains { $0.isError }, "工具执行失败: \(finished)")
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "最终回答为空")
    }
}
