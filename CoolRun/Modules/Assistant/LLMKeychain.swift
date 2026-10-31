import Foundation
import Security

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

// MARK: - Keychain 存储

/// LLM 凭据统一存放在 Keychain，不写入 UserDefaults。
/// 使用 kSecClassGenericPassword，服务名固定为 bundle identifier。
enum LLMKeychain {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.coolrun.app"
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // 先删除旧值，避免 duplicate item
        SecItemDelete(baseQuery as CFDictionary)

        guard !value.isEmpty else { return true }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else {
            return nil
        }
        return text
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
