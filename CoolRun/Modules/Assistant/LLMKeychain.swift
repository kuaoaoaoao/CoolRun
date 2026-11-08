import Foundation

// MARK: - Provider 类型

enum LLMProviderKind: String, CaseIterable, Identifiable, Sendable {
    case openai
    case anthropic
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .ollama: return "Ollama"
        }
    }

    var subtitle: String {
        switch self {
        case .openai: return "GPT-4o / GPT-4o mini"
        case .anthropic: return "Claude 3.5 Sonnet"
        case .ollama: return "Local model (no API key)"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "cloud"
        case .anthropic: return "cloud.fill"
        case .ollama: return "desktopcomputer"
        }
    }

    /// 是否需要 API Key
    var requiresAPIKey: Bool {
        self != .ollama
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com"
        case .anthropic: return "https://api.anthropic.com"
        case .ollama: return "http://localhost:11434"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-3-5-sonnet-20241022"
        case .ollama: return "llama3.2"
        }
    }

    /// Keychain 中存放 API Key 的账号标识
    var keychainAccount: String {
        "llm.\(rawValue).apiKey"
    }
}

// MARK: - 凭据存储

/// LLM 凭据存在本地加密文件里（见 `SecretStore`），不用钥匙串。
///
/// 原因：这个 app 是 ad-hoc 签名分发的，每次重新打包签名都会变，钥匙串 ACL
/// 认不出新签名，读取时会弹「想要使用您存储在钥匙串中的机密信息」并要求输入
/// 密码 —— 每装一次新版就弹一次，太烦。改成加密文件后不再有任何弹窗。
enum LLMKeychain {
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        SecretStore.save(value, account: account)
    }

    static func load(account: String) -> String? {
        SecretStore.load(account)
    }

    static func delete(account: String) {
        SecretStore.delete(account)
    }
}
