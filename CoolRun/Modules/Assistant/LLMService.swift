import Foundation
import SwiftUI

// MARK: - LLM 消息

struct LLMMessage: Sendable {
    let role: LLMRole
    let content: String

    enum LLMRole: String, Sendable {
        case system
        case user
        case assistant
    }
}

// MARK: - LLM Provider 协议

protocol LLMProvider: Sendable {
    var displayName: String { get }
    func complete(messages: [LLMMessage], model: String?) async throws -> String
    /// 流式输出：逐字返回生成的内容。
    func stream(messages: [LLMMessage], model: String?) async throws -> AsyncStream<String>
}

// MARK: - OpenAI Provider

struct OpenAIProvider: LLMProvider {
    let apiKey: String
    let baseURL: String
    let defaultModel: String

    var displayName: String { "OpenAI" }

    init(apiKey: String, baseURL: String = "https://api.openai.com", defaultModel: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.defaultModel = defaultModel
    }

    func complete(messages: [LLMMessage], model: String?) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let bodyMessages = messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": bodyMessages,
            "temperature": 0.7,
            "max_tokens": 2048,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request, retryStrategy: .conservative)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.apiError(statusCode: status, message: Self.extractErrorMessage(data))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stream(messages: [LLMMessage], model: String?) async throws -> AsyncStream<String> {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let bodyMessages = messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": bodyMessages,
            "temperature": 0.7,
            "max_tokens": 2048,
            "stream": true,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw LLMError.apiError(statusCode: status, message: Self.extractErrorMessage(data))
        }

        return AsyncStream { continuation in
            Task {
                defer { continuation.finish() }
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        if jsonString == "[DONE]" { return }
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    static func extractErrorMessage(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}

// MARK: - Anthropic Provider

struct AnthropicProvider: LLMProvider {
    let apiKey: String
    let baseURL: String
    let defaultModel: String

    var displayName: String { "Anthropic" }

    init(apiKey: String, baseURL: String = "https://api.anthropic.com", defaultModel: String = "claude-3-5-sonnet-20241022") {
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.defaultModel = defaultModel
    }

    func complete(messages: [LLMMessage], model: String?) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        // Anthropic 把 system 放在顶层字段，不放进 messages
        var systemContent: String?
        var conversationMessages: [[String: String]] = []
        for msg in messages {
            if msg.role == .system {
                systemContent = msg.content
            } else {
                conversationMessages.append([
                    "role": msg.role.rawValue,
                    "content": msg.content,
                ])
            }
        }

        var body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": conversationMessages,
            "max_tokens": 2048,
            "temperature": 0.7,
        ]

        if let systemContent {
            body["system"] = systemContent
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request, retryStrategy: .conservative)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.apiError(statusCode: status, message: OpenAIProvider.extractErrorMessage(data))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw LLMError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stream(messages: [LLMMessage], model: String?) async throws -> AsyncStream<String> {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        var systemContent: String?
        var conversationMessages: [[String: String]] = []
        for msg in messages {
            if msg.role == .system {
                systemContent = msg.content
            } else {
                conversationMessages.append([
                    "role": msg.role.rawValue,
                    "content": msg.content,
                ])
            }
        }

        var body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": conversationMessages,
            "max_tokens": 2048,
            "temperature": 0.7,
            "stream": true,
        ]

        if let systemContent {
            body["system"] = systemContent
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw LLMError.apiError(statusCode: status, message: OpenAIProvider.extractErrorMessage(data))
        }

        return AsyncStream { continuation in
            Task {
                defer { continuation.finish() }
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let delta = json["delta"] as? [String: Any],
                              let text = delta["text"] as? String else { continue }
                        continuation.yield(text)
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - Ollama Provider (本地模型)

struct OllamaProvider: LLMProvider {
    let baseURL: String
    let defaultModel: String

    var displayName: String { "Ollama" }

    init(baseURL: String = "http://localhost:11434", defaultModel: String = "llama3.2") {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.defaultModel = defaultModel
    }

    func complete(messages: [LLMMessage], model: String?) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let bodyMessages = messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": bodyMessages,
            "stream": false,
            "options": ["temperature": 0.7],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request, retryStrategy: .conservative)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.apiError(statusCode: status, message: OpenAIProvider.extractErrorMessage(data))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stream(messages: [LLMMessage], model: String?) async throws -> AsyncStream<String> {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let bodyMessages = messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": bodyMessages,
            "stream": true,
            "options": ["temperature": 0.7],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw LLMError.apiError(statusCode: status, message: OpenAIProvider.extractErrorMessage(data))
        }

        return AsyncStream { continuation in
            Task {
                defer { continuation.finish() }
                do {
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? [String: Any],
                              let content = message["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - LLM 错误

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

// MARK: - LLM Service

@MainActor
@Observable
final class LLMService {
    static let shared = LLMService()

    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var activeKind: LLMProviderKind?
    private var currentProvider: LLMProvider?

    private let defaults = UserDefaults.standard

    private init() {
        loadConfiguration()
    }

    // MARK: - 配置

    var providerDisplayName: String {
        currentProvider?.displayName ?? "Not configured"
    }

    var isConfigured: Bool {
        currentProvider != nil
    }

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

        switch kind {
        case .openai:
            currentProvider = OpenAIProvider(apiKey: trimmedKey, baseURL: resolvedBase, defaultModel: resolvedModel)
        case .anthropic:
            currentProvider = AnthropicProvider(apiKey: trimmedKey, baseURL: resolvedBase, defaultModel: resolvedModel)
        case .ollama:
            currentProvider = OllamaProvider(baseURL: resolvedBase, defaultModel: resolvedModel)
        }

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

        currentProvider = nil
        activeKind = nil
        lastError = nil
    }

    private func loadConfiguration() {
        guard let raw = defaults.string(forKey: "llm.activeKind"),
              let kind = LLMProviderKind(rawValue: raw) else { return }

        let apiKey = LLMKeychain.load(account: kind.keychainAccount) ?? ""
        let baseURL = defaults.string(forKey: "llm.\(kind.rawValue).baseURL") ?? kind.defaultBaseURL
        let model = defaults.string(forKey: "llm.\(kind.rawValue).model") ?? kind.defaultModel

        if kind.requiresAPIKey, apiKey.isEmpty { return }

        configure(kind: kind, apiKey: apiKey, baseURL: baseURL, model: model)
    }

    // MARK: - 连通性测试

    /// 发送一条最小请求验证配置是否可用。
    func testConnection() async -> Result<String, Error> {
        guard let provider = currentProvider else {
            return .failure(LLMError.noProviderConfigured)
        }

        let probe = [LLMMessage(role: .user, content: "Reply with the single word: OK")]
        do {
            let reply = try await provider.complete(messages: probe, model: nil)
            return .success(reply)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 对话

    func chat(messages: [LLMMessage]) async -> String? {
        guard let provider = currentProvider else {
            lastError = LLMError.noProviderConfigured.localizedDescription
            return nil
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            return try await provider.complete(messages: messages, model: nil)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func askWithContext(userQuestion: String, systemContext: String? = nil) async -> String? {
        let messages: [LLMMessage] = [
            LLMMessage(role: .system, content: systemContext ?? Self.defaultSystemPrompt),
            LLMMessage(role: .user, content: userQuestion),
        ]
        return await chat(messages: messages)
    }

    /// 流式对话：逐字返回模型输出，供 UI 实时显示。
    func askWithContextStream(userQuestion: String, systemContext: String? = nil) async -> AsyncStream<String>? {
        guard let provider = currentProvider else {
            lastError = LLMError.noProviderConfigured.localizedDescription
            return nil
        }

        let messages: [LLMMessage] = [
            LLMMessage(role: .system, content: systemContext ?? Self.defaultSystemPrompt),
            LLMMessage(role: .user, content: userQuestion),
        ]

        isLoading = true
        lastError = nil

        do {
            let stream = try await provider.stream(messages: messages, model: nil)
            return AsyncStream { continuation in
                Task {
                    defer {
                        isLoading = false
                        continuation.finish()
                    }
                    for await chunk in stream {
                        continuation.yield(chunk)
                    }
                }
            }
        } catch {
            isLoading = false
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - 系统提示词

    static let defaultSystemPrompt = """
    You are a helpful assistant built into CoolRun, a macOS menu bar utility. \
    You answer questions about the user's system status, gold price data, and AI quota. \
    Rules:
    - Be concise and practical. Prefer short paragraphs and bullet lists.
    - Only use the data provided in the context. Never invent numbers, prices, or percentages.
    - When discussing gold, always note that the analysis is for reference only and not investment advice.
    - Reply in the same language the user writes in.
    """
}

// MARK: - 上下文构建器

struct LLMContextBuilder {
    /// 构建系统状态上下文
    static func systemContext(_ snapshot: SystemSnapshot) -> String {
        var lines: [String] = ["Current system status:"]
        lines.append("- CPU usage: \(Int((snapshot.cpu.usage * 100).rounded()))% across \(snapshot.cpu.coreCount) cores")
        lines.append("- Memory: \(byteText(snapshot.memory.used)) used of \(byteText(snapshot.memory.total)) (\(Int((snapshot.memory.usage * 100).rounded()))%)")
        if let level = snapshot.battery.level {
            lines.append("- Battery: \(Int((level * 100).rounded()))% (\(snapshot.battery.state.rawValue))")
        }
        if let cpuTemp = snapshot.temperature.cpuTemperature {
            lines.append("- CPU temperature: \(Int(cpuTemp.rounded()))°C")
        }
        lines.append("- Uptime: \(snapshot.uptime.formatted)")
        lines.append("- Active processes: \(snapshot.processes.totalCount)")
        return lines.joined(separator: "\n")
    }

    /// 构建金价上下文
    static func goldContext(_ store: GoldPriceStore) -> String {
        guard let quote = store.latestQuote else {
            return "Gold price data is currently unavailable."
        }
        var lines = ["Current gold price (CZB accumulation gold): ¥\(String(format: "%.2f", quote.cnyPerGram))/g"]
        if let change = quote.changeAmount, let rate = quote.changeRatePercent {
            let changeSign = change >= 0 ? "+" : ""
            let rateSign = rate >= 0 ? "+" : ""
            lines.append("Change today: \(changeSign)\(String(format: "%.2f", change)) (\(rateSign)\(String(format: "%.2f", rate))%)")
        }
        if let yesterday = quote.yesterdayPrice {
            lines.append("Previous close: ¥\(String(format: "%.2f", yesterday))/g")
        }
        lines.append("Market status: \(quote.isMarketClosed ? "closed" : "open")")
        return lines.joined(separator: "\n")
    }

    /// 构建 AI 配额上下文
    static func aiQuotaContext() -> String {
        "AI quota data lives in the AI Quota module. Open it to see current Codex and Claude usage limits and reset times."
    }

    private static func byteText(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
