import Foundation

// MARK: - LLM 配置错误

enum LLMError: Error, LocalizedError {
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case invalidConfiguration(String)
    case noProviderConfigured

    var errorDescription: String? {
        switch self {
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .invalidResponse:
            return "Unexpected response format from the LLM service."
        case .invalidConfiguration(let detail):
            return "Configuration problem: \(detail)"
        case .noProviderConfigured:
            return "No provider configured. Add an API key in Settings → AI Assistant."
        }
    }
}

// MARK: - Provider 配置读写

/// 只负责「provider 凭据 / 端点 / 模型」的持久化与回填。
/// 实际的模型调用已经统一走 `AgentWire`，这里不再保留 HTTP 实现。
@MainActor
@Observable
final class LLMService {
    static let shared = LLMService()

    private(set) var lastError: String?
    private(set) var activeKind: LLMProviderKind?

    private let defaults = UserDefaults.standard

    private init() {
        loadConfiguration()
    }

    // MARK: - 状态

    var providerDisplayName: String {
        activeKind?.displayName ?? "Not configured"
    }

    var isConfigured: Bool {
        activeKind != nil
    }

    // MARK: - 读取

    /// 当前配置摘要，供设置界面回填
    func currentConfiguration() -> (kind: LLMProviderKind, apiKey: String, baseURL: String, model: String)? {
        guard let kind = activeKind else { return nil }
        return (
            kind,
            LLMKeychain.load(account: kind.keychainAccount) ?? "",
            defaults.string(forKey: "llm.\(kind.rawValue).baseURL") ?? kind.defaultBaseURL,
            defaults.string(forKey: "llm.\(kind.rawValue).model") ?? kind.defaultModel
        )
    }

    /// 读取指定 provider 已保存的配置（切换 provider 时回填表单）
    func savedConfiguration(for kind: LLMProviderKind) -> (apiKey: String, baseURL: String, model: String) {
        (
            LLMKeychain.load(account: kind.keychainAccount) ?? "",
            defaults.string(forKey: "llm.\(kind.rawValue).baseURL") ?? kind.defaultBaseURL,
            defaults.string(forKey: "llm.\(kind.rawValue).model") ?? kind.defaultModel
        )
    }

    // MARK: - 写入

    /// 统一配置入口。apiKey 写入 Keychain，baseURL / model 写入 UserDefaults。
    @discardableResult
    func configure(kind: LLMProviderKind, apiKey: String, baseURL: String, model: String) -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if kind.requiresAPIKey, trimmedKey.isEmpty {
            lastError = "API key is required for \(kind.displayName)."
            return false
        }

        let resolvedBase = trimmedBase.isEmpty ? kind.defaultBaseURL : trimmedBase
        let resolvedModel = trimmedModel.isEmpty ? kind.defaultModel : trimmedModel

        activeKind = kind

        if kind.requiresAPIKey {
            LLMKeychain.save(trimmedKey, account: kind.keychainAccount)
        }
        defaults.set(kind.rawValue, forKey: "llm.activeKind")
        defaults.set(resolvedBase, forKey: "llm.\(kind.rawValue).baseURL")
        defaults.set(resolvedModel, forKey: "llm.\(kind.rawValue).model")

        lastError = nil
        return true
    }

    /// 清空最近一次错误提示（供 UI 主动重置）
    func clearError() {
        lastError = nil
    }

    func clearConfiguration() {
        for kind in LLMProviderKind.allCases {
            LLMKeychain.delete(account: kind.keychainAccount)
            defaults.removeObject(forKey: "llm.\(kind.rawValue).baseURL")
            defaults.removeObject(forKey: "llm.\(kind.rawValue).model")
        }
        defaults.removeObject(forKey: "llm.activeKind")

        activeKind = nil
        lastError = nil
    }

    private func loadConfiguration() {
        guard let raw = defaults.string(forKey: "llm.activeKind"),
              let kind = LLMProviderKind(rawValue: raw) else { return }

        let apiKey = LLMKeychain.load(account: kind.keychainAccount) ?? ""
        if kind.requiresAPIKey, apiKey.isEmpty { return }

        activeKind = kind
    }

    // MARK: - 连通性测试

    /// 用一条最小请求验证配置是否可用。走 AgentWire，与 Agent 实际调用同一套代码路径。
    func testConnection() async -> Result<String, Error> {
        guard let config = currentConfiguration() else {
            return .failure(LLMError.noProviderConfigured)
        }

        let wireProtocol: AgentWireProtocol
        switch config.kind {
        case .openai: wireProtocol = .openAIChat
        case .anthropic: wireProtocol = .anthropicMessages
        case .ollama: wireProtocol = .ollama
        }

        let runConfig = AgentRunConfig(
            protocolKind: wireProtocol,
            apiKey: config.apiKey,
            baseURL: config.baseURL,
            model: config.model,
            maxTokens: 64
        )

        let wire = AgentWireFactory.make(wireProtocol)
        do {
            var text = ""
            let stream = try await wire.stream(
                messages: [AgentMessage(role: .user, content: "Reply with the single word: OK")],
                tools: [],
                config: runConfig
            )
            for try await event in stream {
                if case .text(let delta) = event {
                    text += delta
                }
            }
            return .success(text.isEmpty ? "OK" : text)
        } catch {
            return .failure(error)
        }
    }
}
