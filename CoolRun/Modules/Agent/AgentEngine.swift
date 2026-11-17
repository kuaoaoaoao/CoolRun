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

    nonisolated func subtitle(_ lang: AppLanguage) -> String {
        switch self {
        case .openAIChat:
            return LocalizedString.l(
                lang,
                en: "chat/completions · most compatible",
                zh: "chat/completions · 兼容性最好",
                ja: "chat/completions · 互換性が最も高い",
                ko: "chat/completions · 호환성 최고"
            )
        case .openAIResponses:
            return LocalizedString.l(
                lang,
                en: "responses · newer API",
                zh: "responses · 新接口",
                ja: "responses · 新しい API",
                ko: "responses · 새로운 API"
            )
        case .anthropicMessages:
            return LocalizedString.l(
                lang,
                en: "messages · Claude",
                zh: "messages · Claude",
                ja: "messages · Claude",
                ko: "messages · Claude"
            )
        case .ollama:
            return LocalizedString.l(
                lang,
                en: "Local models · no API key needed",
                zh: "本地模型 · 无需 API Key",
                ja: "ローカルモデル · API キー不要",
                ko: "로컬 모델 · API 키 불필요"
            )
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
    /// 界面语言。wire 层是 nonisolated 的，错误文案要靠它取语言。
    var lang: AppLanguage

    nonisolated init(
        protocolKind: AgentWireProtocol = .openAIChat,
        apiKey: String = "",
        baseURL: String = "",
        model: String = "",
        temperature: Double = 0.6,
        maxTokens: Int = 4096,
        maxRounds: Int = 6,
        lang: AppLanguage = .chinese
    ) {
        self.protocolKind = protocolKind
        self.apiKey = apiKey
        self.baseURL = baseURL.isEmpty ? protocolKind.defaultBaseURL : baseURL
        self.model = model.isEmpty ? protocolKind.defaultModel : model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.maxRounds = maxRounds
        self.lang = lang
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

/// 能按界面语言给出文案的错误。界面层统一用 `localizedMessage(_:)` 取文案，
/// `localizedDescription` 只作为兜底（固定中文）。
protocol AgentLocalizedError: Error {
    nonisolated func localizedMessage(_ lang: AppLanguage) -> String
}

enum AgentError: Error, LocalizedError, AgentLocalizedError {
    case notConfigured
    case missingCredentials(String)
    case invalidEndpoint(String)
    case http(status: Int, message: String)
    case invalidResponse(String)
    case cancelled
    case maxRoundsExceeded(Int)
    case toolFailed(name: String, message: String)

    nonisolated var errorDescription: String? {
        localizedMessage(.chinese)
    }

    /// 本地化的错误文案。`errorDescription` 只是兜底，界面请用这个。
    nonisolated func localizedMessage(_ lang: AppLanguage) -> String {
        switch self {
        case .notConfigured:
            return LocalizedString.l(
                lang,
                en: "Agent isn't configured yet. Pick a model provider in Settings first.",
                zh: "Agent 未配置：请先在设置里选择模型接入方式。",
                ja: "Agent が未設定です。先に設定でモデルの接続方法を選んでください。",
                ko: "Agent가 아직 설정되지 않았습니다. 먼저 설정에서 모델 연결 방식을 선택하세요."
            )
        case .missingCredentials(let detail):
            return detail
        case .invalidEndpoint(let detail):
            return LocalizedString.l(
                lang,
                en: "Invalid endpoint: \(detail)",
                zh: "接口地址无效：\(detail)",
                ja: "エンドポイントが無効です：\(detail)",
                ko: "엔드포인트가 올바르지 않습니다: \(detail)"
            )
        case .http(let status, let message):
            return LocalizedString.l(
                lang,
                en: "Request failed (\(status)): \(message)",
                zh: "请求失败（\(status)）：\(message)",
                ja: "リクエスト失敗（\(status)）：\(message)",
                ko: "요청 실패(\(status)): \(message)"
            )
        case .invalidResponse(let detail):
            return LocalizedString.l(
                lang,
                en: "Unexpected response format: \(detail)",
                zh: "响应格式异常：\(detail)",
                ja: "応答の形式が不正です：\(detail)",
                ko: "응답 형식이 올바르지 않습니다: \(detail)"
            )
        case .cancelled:
            return LocalizedString.l(
                lang,
                en: "Cancelled.",
                zh: "已取消。",
                ja: "キャンセルしました。",
                ko: "취소되었습니다."
            )
        case .maxRoundsExceeded(let rounds):
            return LocalizedString.l(
                lang,
                en: "Stopped after hitting the \(rounds)-round tool call limit. Try splitting the question into smaller parts.",
                zh: "工具调用超过 \(rounds) 轮上限，已停止。请把问题拆小一点。",
                ja: "ツール呼び出しが \(rounds) 回の上限を超えたため停止しました。質問を小さく分けてください。",
                ko: "도구 호출이 \(rounds)회 한도를 넘어 중지했습니다. 질문을 더 작게 나눠 주세요."
            )
        case .toolFailed(let name, let message):
            return LocalizedString.l(
                lang,
                en: "Tool \(name) failed: \(message)",
                zh: "工具 \(name) 执行失败：\(message)",
                ja: "ツール \(name) の実行に失敗しました：\(message)",
                ko: "도구 \(name) 실행 실패: \(message)"
            )
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
