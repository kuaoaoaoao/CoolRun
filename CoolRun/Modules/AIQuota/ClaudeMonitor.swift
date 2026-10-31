import Foundation
import Observation
import Darwin

// MARK: - Claude Code 额度监控
// 读取 Claude Code CLI 的本地 OAuth 凭据，调用官方 usage 接口获取 5 小时 / 周额度。
// 参考 CodexBar 的 ClaudeOAuthUsageFetcher 实现。

struct ClaudeMonitorSnapshot: Equatable, Sendable {
    var account: String
    var plan: String?
    var windows: [CodexQuotaWindow]
    var extraUsage: ClaudeExtraUsage?
    var updatedAt: Date
}

struct ClaudeExtraUsage: Equatable, Sendable {
    let usedCredits: Double
    let monthlyLimit: Double
    let currency: String?
}

enum ClaudeMonitorState: Equatable, Sendable {
    case loading
    case unavailable(String)
    case notLoggedIn(String)
    case ready(ClaudeMonitorSnapshot)
}

@MainActor
@Observable
final class ClaudeMonitorViewModel {
    // 共享实例由 AI 面板的可见性控制，避免后台空转和 usage 接口限频。
    static let shared = ClaudeMonitorViewModel(autoStart: false)

    var state: ClaudeMonitorState = .loading
    var isRefreshing = false
    private var refreshTask: Task<Void, Never>?

    init(autoStart: Bool = true) {
        if autoStart {
            start()
        }
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // usage 接口有官方限频，轮询间隔比 Codex 稍长
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        state = await ClaudeMonitorClient.fetch()
        isRefreshing = false
        if case let .ready(snapshot) = state {
            QuotaAlertManager.shared.handle(
                provider: "Claude",
                windows: snapshot.windows.compactMap { window in
                    window.remainingPercent.map {
                        QuotaAlertManager.WindowInfo(id: window.id, title: window.title, remainingPercent: $0)
                    }
                }
            )
        }
    }
}

nonisolated enum ClaudeMonitorClient {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.1.0"

    static func fetch() async -> ClaudeMonitorState {
        let credentials: ClaudeCredentials
        switch loadCredentials() {
        case let .success(value):
            credentials = value
        case let .failure(reason):
            return .notLoggedIn(reason)
        }

        if let expiresAt = credentials.expiresAt, expiresAt < Date() {
            // 不主动刷新 token：refresh token 是轮换的，抢刷会破坏 CLI 的登录态
            return .notLoggedIn("Claude 登录已过期，请在终端运行 claude 后重试")
        }

        do {
            let response = try await requestUsage(accessToken: credentials.accessToken)
            let snapshot = ClaudeMonitorSnapshot(
                account: credentials.account,
                plan: credentials.plan,
                windows: makeWindows(from: response),
                extraUsage: response.extraUsage.flatMap { extra in
                    guard extra.isEnabled == true, let used = extra.usedCredits, let limit = extra.monthlyLimit else { return nil }
                    return ClaudeExtraUsage(usedCredits: used, monthlyLimit: limit, currency: extra.currency)
                },
                updatedAt: Date()
            )
            return .ready(snapshot)
        } catch let error as UsageError {
            switch error {
            case .unauthorized:
                return .notLoggedIn("凭据已失效，请在终端运行 claude 重新登录")
            case .rateLimited:
                return .unavailable("usage 接口被限频，稍后自动重试")
            case let .server(code):
                return .unavailable("Claude 接口错误：HTTP \(code)")
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    // MARK: - 凭据

    struct ClaudeCredentials {
        let accessToken: String
        let expiresAt: Date?
        let plan: String?
        let account: String
    }

    enum CredentialResult {
        case success(ClaudeCredentials)
        case failure(String)
    }

    static func loadCredentials() -> CredentialResult {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) }
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let fileURL = URL(fileURLWithPath: home).appendingPathComponent(".claude/.credentials.json")

        // 只读本地凭据文件，不碰钥匙串，避免触发系统授权弹窗
        if let data = try? Data(contentsOf: fileURL), let credentials = parseCredentials(data) {
            return .success(credentials)
        }
        return .failure("未找到 Claude Code 登录凭据，请在终端运行 claude 登录")
    }

    private static func parseCredentials(_ data: Data) -> ClaudeCredentials? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = object["claudeAiOauth"] as? [String: Any],
            let accessToken = oauth["accessToken"] as? String,
            !accessToken.isEmpty
        else {
            return nil
        }
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        let plan = oauth["subscriptionType"] as? String
        return ClaudeCredentials(
            accessToken: accessToken,
            expiresAt: expiresAt,
            plan: plan,
            account: "Claude Code"
        )
    }

    // MARK: - usage 请求

    private enum UsageError: Error {
        case unauthorized
        case rateLimited
        case server(Int)
    }

    private static func requestUsage(accessToken: String) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch statusCode {
        case 200:
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        case 401:
            throw UsageError.unauthorized
        case 429:
            throw UsageError.rateLimited
        default:
            throw UsageError.server(statusCode)
        }
    }

    private static func makeWindows(from response: UsageResponse) -> [CodexQuotaWindow] {
        let candidates: [(id: String, title: String, minutes: Int, window: UsageResponse.Window?)] = [
            ("claude-5h", "5 小时额度", 300, response.fiveHour),
            ("claude-7d", "周额度", 10080, response.sevenDay),
            ("claude-7d-opus", "Opus 周额度", 10080, response.sevenDayOpus),
            ("claude-7d-sonnet", "Sonnet 周额度", 10080, response.sevenDaySonnet),
        ]
        return candidates.compactMap { candidate in
            guard let window = candidate.window, let utilization = window.utilization else { return nil }
            let remaining = max(0, min(100, 100 - Int(utilization.rounded())))
            return CodexQuotaWindow(
                id: candidate.id,
                title: candidate.title,
                remainingPercent: remaining,
                resetsAt: parseISO8601(window.resetsAt),
                durationMinutes: candidate.minutes
            )
        }
    }

    private static func parseISO8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - 响应模型

    private struct UsageResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDayOpus: Window?
        let sevenDaySonnet: Window?
        let extraUsage: Extra?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
            case extraUsage = "extra_usage"
        }

        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
        }

        struct Extra: Decodable {
            let isEnabled: Bool?
            let monthlyLimit: Double?
            let usedCredits: Double?
            let currency: String?

            enum CodingKeys: String, CodingKey {
                case isEnabled = "is_enabled"
                case monthlyLimit = "monthly_limit"
                case usedCredits = "used_credits"
                case currency
            }
        }
    }
}
