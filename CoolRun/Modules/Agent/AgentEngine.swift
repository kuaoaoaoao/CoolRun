import Foundation

// MARK: - 引擎类型

enum AgentEngineKind: String, CaseIterable, Identifiable, Sendable {
    case native
    case dsh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native: return "CoolRun Native"
        case .dsh: return "DeepSeek Harness"
        }
    }
}

// MARK: - 接入协议

/// 模型接入的 wire 协议。决定 URL 路径与请求/响应形状，不决定业务逻辑。
enum AgentWireProtocol: String, CaseIterable, Identifiable, Sendable {
    /// OpenAI / 兼容端点：POST /v1/chat/completions
    case openAIChat
    /// OpenAI Responses API：POST /v1/responses
    case openAIResponses
    /// Anthropic Messages：POST /v1/messages
    case anthropicMessages
    /// Ollama 原生：POST /api/chat
    case ollama

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .openAIChat: return "OpenAI Chat"
        case .openAIResponses: return "OpenAI Responses"
        case .anthropicMessages: return "Anthropic Messages"
        case .ollama: return "Ollama"
        }
    }

    /// 窄面板里的短名，分段控件放不下全称。
    nonisolated var shortName: String {
        switch self {
        case .openAIChat: return "Chat"
        case .openAIResponses: return "Responses"
        case .anthropicMessages: return "Claude"
        case .ollama: return "Ollama"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .openAIChat: return "chat/completions · 兼容性最好"
        case .openAIResponses: return "responses · 新接口"
        case .anthropicMessages: return "messages · Claude"
        case .ollama: return "本地模型 · 无需 API Key"
        }
    }

    nonisolated var requiresAPIKey: Bool {
        self != .ollama
    }

    nonisolated var defaultBaseURL: String {
        switch self {
        case .openAIChat, .openAIResponses: return "https://api.openai.com"
        case .anthropicMessages: return "https://api.anthropic.com"
        case .ollama: return "http://localhost:11434"
        }
    }

    nonisolated var defaultModel: String {
        switch self {
        case .openAIChat: return "gpt-4o-mini"
        case .openAIResponses: return "gpt-4.1-mini"
        case .anthropicMessages: return "claude-sonnet-4-20250514"
        case .ollama: return "qwen2.5:3b"
        }
    }
}

// MARK: - 运行配置

struct AgentRunConfig: Sendable {
    var protocolKind: AgentWireProtocol
    var apiKey: String
    var baseURL: String
    var model: String
    var temperature: Double
    var maxTokens: Int
    /// 一次用户输入内最多允许的「模型→工具→模型」往返次数，防止死循环。
    var maxRounds: Int

    nonisolated init(
        protocolKind: AgentWireProtocol = .openAIChat,
        apiKey: String = "",
        baseURL: String = "",
        model: String = "",
        temperature: Double = 0.6,
        maxTokens: Int = 4096,
        maxRounds: Int = 6
    ) {
        self.protocolKind = protocolKind
        self.apiKey = apiKey
        self.baseURL = baseURL.isEmpty ? protocolKind.defaultBaseURL : baseURL
        self.model = model.isEmpty ? protocolKind.defaultModel : model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.maxRounds = maxRounds
    }
}

// MARK: - 事件

/// 引擎向 UI 暴露的流式事件。所有引擎（原生 / DSH）都必须产出同一套事件。
enum AgentEvent: Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallStarted(id: String, name: String, arguments: JSONValue)
    case toolCallFinished(id: String, name: String, output: String, isError: Bool)
    /// 整轮结束（可能包含多轮工具调用）
    case turnFinished
    /// 需要用户确认后才能继续的持久写入
    case confirmationRequired(id: String, name: String, arguments: JSONValue)
}

// MARK: - 错误

enum AgentError: Error, LocalizedError {
    case notConfigured
    case missingCredentials(String)
    case invalidEndpoint(String)
    case http(status: Int, message: String)
    case invalidResponse(String)
    case cancelled
    case maxRoundsExceeded(Int)
    case toolFailed(name: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Agent 未配置：请先在设置里选择模型接入方式。"
        case .missingCredentials(let detail):
            return detail
        case .invalidEndpoint(let detail):
            return "接口地址无效：\(detail)"
        case .http(let status, let message):
            return "请求失败（\(status)）：\(message)"
        case .invalidResponse(let detail):
            return "响应格式异常：\(detail)"
        case .cancelled:
            return "已取消。"
        case .maxRoundsExceeded(let rounds):
            return "工具调用超过 \(rounds) 轮上限，已停止。请把问题拆小一点。"
        case .toolFailed(let name, let message):
            return "工具 \(name) 执行失败：\(message)"
        }
    }
}

// MARK: - 引擎协议

/// 可插拔的 Agent 引擎。原生实现与 DSH 子进程实现都遵循它，
/// 上层 UI / 会话 / 权限完全不感知差异。
@MainActor
protocol AgentEngine: AnyObject {
    var kind: AgentEngineKind { get }
    var displayName: String { get }
    var isAvailable: Bool { get }

    /// 执行一轮对话。事件流结束时本轮完成。
    func run(
        prompt: String,
        history: [AgentMessage],
        config: AgentRunConfig
    ) -> AsyncThrowingStream<AgentEvent, Error>

    /// 中断当前轮次。
    func cancel()

    func shutdown()
}
