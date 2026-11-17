import Foundation

/// Agent 的接入配置。默认跟随「AI 助手」模块已经配好的 provider，
/// 用户也可以为 Agent 单独指定协议 / 端点 / 模型。
@MainActor
@Observable
final class AgentSettings {
    static let shared = AgentSettings()

    private enum Keys {
        static let engineKind = "agent.engine"
        static let protocolKind = "agent.protocol"
        static let baseURL = "agent.baseURL"
        static let model = "agent.model"
        static let maxRounds = "agent.maxRounds"
        static let toolLevel = "agent.toolLevel"
        static let apiKeyAccount = "agent.apiKey"
        static let configured = "agent.configured"
    }

    /// 用哪个引擎跑：原生 Swift 实现，还是 DSH 运行时。
    var engineKind: AgentEngineKind {
        didSet { persist() }
    }

    var protocolKind: AgentWireProtocol {
        didSet { persist() }
    }

    var baseURL: String {
        didSet { persist() }
    }

    var model: String {
        didSet { persist() }
    }

    var maxRounds: Int {
        didSet { persist() }
    }

    /// 允许 Agent 调用的最高权限等级。默认只读。
    var toolLevel: ToolPermission {
        didSet { persist() }
    }

    var apiKey: String {
        didSet { LLMKeychain.save(apiKey, account: Keys.apiKeyAccount) }
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 是否需要 API Key 才能运行。
    var requiresAPIKey: Bool {
        protocolKind.requiresAPIKey
    }

    var isConfigured: Bool {
        !requiresAPIKey || hasAPIKey
    }

    private let defaults = UserDefaults.standard

    private init() {
        let storedProtocol = defaults.string(forKey: Keys.protocolKind)
            .flatMap(AgentWireProtocol.init(rawValue:))

        engineKind = defaults.string(forKey: Keys.engineKind)
            .flatMap(AgentEngineKind.init(rawValue:)) ?? .native

        if let storedProtocol {
            protocolKind = storedProtocol
            baseURL = defaults.string(forKey: Keys.baseURL) ?? storedProtocol.defaultBaseURL
            model = defaults.string(forKey: Keys.model) ?? storedProtocol.defaultModel
            let storedRounds = defaults.integer(forKey: Keys.maxRounds)
            maxRounds = storedRounds > 0 ? storedRounds : 6
            toolLevel = ToolPermission(rawValue: defaults.integer(forKey: Keys.toolLevel)) ?? .read
            apiKey = LLMKeychain.load(account: Keys.apiKeyAccount) ?? ""
        } else {
            // 首次使用：从 AI 助手模块的配置派生，避免让用户配两遍。
            let derived = Self.deriveFromAssistant(defaults: defaults)
            protocolKind = derived.protocolKind
            baseURL = derived.baseURL
            model = derived.model
            maxRounds = 6
            toolLevel = .read
            apiKey = derived.apiKey
        }
    }

    /// 把 AI 助手当前的 provider 配置映射成 Agent 的 wire 协议。
    private static func deriveFromAssistant(
        defaults: UserDefaults
    ) -> (protocolKind: AgentWireProtocol, baseURL: String, model: String, apiKey: String) {
        let kind = defaults.string(forKey: "llm.activeKind")
            .flatMap(LLMProviderKind.init(rawValue:)) ?? .openai

        let wireProtocol: AgentWireProtocol
        switch kind {
        case .openai: wireProtocol = .openAIChat
        case .anthropic: wireProtocol = .anthropicMessages
        case .ollama: wireProtocol = .ollama
        }

        let base = defaults.string(forKey: "llm.\(kind.rawValue).baseURL") ?? kind.defaultBaseURL
        let model = defaults.string(forKey: "llm.\(kind.rawValue).model") ?? kind.defaultModel
        let key = LLMKeychain.load(account: kind.keychainAccount) ?? ""
        return (wireProtocol, base, model, key)
    }

    /// 切换协议时，如果当前端点还是上一个协议的默认值，就顺手换成新协议的默认值。
    func applyProtocolDefaults() {
        if baseURL.isEmpty || AgentWireProtocol.allCases.contains(where: { $0.defaultBaseURL == baseURL && $0 != protocolKind }) {
            baseURL = protocolKind.defaultBaseURL
        }
        if model.isEmpty || AgentWireProtocol.allCases.contains(where: { $0.defaultModel == model && $0 != protocolKind }) {
            model = protocolKind.defaultModel
        }
    }

    /// 重新从 AI 助手模块同步一次配置。
    func adoptFromAssistant() {
        let derived = Self.deriveFromAssistant(defaults: defaults)
        protocolKind = derived.protocolKind
        baseURL = derived.baseURL
        model = derived.model
        if !derived.apiKey.isEmpty {
            apiKey = derived.apiKey
        }
    }

    func makeConfig() throws -> AgentRunConfig {
        let lang = AppSettings.shared.language
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if protocolKind.requiresAPIKey && trimmedKey.isEmpty {
            throw AgentError.missingCredentials(
                LocalizedString.l(
                    lang,
                    en: "No API key configured for \(protocolKind.displayName) yet.",
                    zh: "还没有配置 \(protocolKind.displayName) 的 API Key。",
                    ja: "\(protocolKind.displayName) の API キーがまだ設定されていません。",
                    ko: "\(protocolKind.displayName)의 API 키가 아직 설정되지 않았습니다."
                )
            )
        }

        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, URL(string: trimmedBase) != nil else {
            throw AgentError.invalidEndpoint(baseURL)
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw AgentError.missingCredentials(
                LocalizedString.l(
                    lang,
                    en: "Model name is still empty.",
                    zh: "还没有填写模型名称。",
                    ja: "モデル名がまだ入力されていません。",
                    ko: "모델 이름이 아직 입력되지 않았습니다."
                )
            )
        }

        return AgentRunConfig(
            protocolKind: protocolKind,
            apiKey: trimmedKey,
            baseURL: trimmedBase,
            model: trimmedModel,
            maxRounds: max(maxRounds, 1),
            lang: lang
        )
    }

    private func persist() {
        defaults.set(engineKind.rawValue, forKey: Keys.engineKind)
        defaults.set(protocolKind.rawValue, forKey: Keys.protocolKind)
        defaults.set(baseURL, forKey: Keys.baseURL)
        defaults.set(model, forKey: Keys.model)
        defaults.set(maxRounds, forKey: Keys.maxRounds)
        defaults.set(toolLevel.rawValue, forKey: Keys.toolLevel)
        defaults.set(true, forKey: Keys.configured)
    }
}
