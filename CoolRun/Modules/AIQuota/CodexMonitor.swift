import Foundation
import Observation
import Darwin

struct CodexMonitorSnapshot: Equatable, Sendable {
    var account: String
    var plan: String?
    var limits: [CodexQuotaLimit]
    var resetCreditsAvailableCount: Int?
    var usage: CodexUsageSummary?
    var dailyUsage: [CodexDailyUsage]
    var sessions: [CodexSessionSummary]
    var isRateLimitsStale: Bool
    var isUsageStale: Bool
    var updatedAt: Date
}

struct CodexQuotaLimit: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let windows: [CodexQuotaWindow]
}

struct CodexQuotaWindow: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let remainingPercent: Int?
    let resetsAt: Date?
    let durationMinutes: Int?

    var durationText: String {
        guard let durationMinutes, durationMinutes > 0 else { return "额度" }
        if durationMinutes % 1440 == 0 { return "\(durationMinutes / 1440)d" }
        if durationMinutes % 60 == 0 { return "\(durationMinutes / 60)h" }
        return "\(durationMinutes)m"
    }

    func pace(at now: Date = Date()) -> CodexQuotaPace? {
        guard
            let remainingPercent,
            let resetsAt,
            let durationMinutes,
            durationMinutes > 0
        else {
            return nil
        }

        let duration = TimeInterval(durationMinutes * 60)
        let remainingTime = max(0, min(duration, resetsAt.timeIntervalSince(now)))
        let elapsed = max(0, duration - remainingTime)
        let expectedRemaining = max(0, min(100, remainingTime / duration * 100))
        let delta = Double(remainingPercent) - expectedRemaining
        let usedPercent = Double(100 - remainingPercent)
        let secondsToExhaust: TimeInterval?

        if elapsed >= 60, usedPercent > 0 {
            secondsToExhaust = elapsed / usedPercent * Double(remainingPercent)
        } else {
            secondsToExhaust = nil
        }

        let status: CodexQuotaPace.Status
        if remainingPercent <= 10 {
            status = .critical
        } else if secondsToExhaust.map({ $0 < remainingTime }) == true || delta < -12 {
            status = .fast
        } else if delta > 15 {
            status = .comfortable
        } else {
            status = .balanced
        }

        return CodexQuotaPace(
            status: status,
            expectedRemainingPercent: expectedRemaining,
            secondsUntilReset: remainingTime,
            projectedSecondsUntilExhausted: secondsToExhaust
        )
    }
}

struct CodexQuotaPace: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case balanced
        case comfortable
        case fast
        case critical
    }

    let status: Status
    let expectedRemainingPercent: Double
    let secondsUntilReset: TimeInterval
    let projectedSecondsUntilExhausted: TimeInterval?
}

struct CodexUsageSummary: Equatable, Sendable {
    let lifetimeTokens: Int
    let peakDailyTokens: Int
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let longestRunningTurnSec: Int?
}

struct CodexDailyUsage: Equatable, Sendable, Identifiable {
    let date: String
    let tokens: Int
    var id: String { date }
}

struct CodexSessionSummary: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let projectName: String
    let source: String
    let isActive: Bool
    let updatedAt: Date
    let transcriptPath: String
}

enum CodexMonitorState: Equatable, Sendable {
    case loading
    case unavailable(String)
    case notLoggedIn(String)
    case ready(CodexMonitorSnapshot)
}

@MainActor
@Observable
final class CodexMonitorViewModel {
    // 共享实例由 AI 面板的可见性控制，不在应用启动时常驻轮询。
    static let shared = CodexMonitorViewModel(autoStart: false)

    var state: CodexMonitorState = .loading
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
                try? await Task.sleep(for: .seconds(30))
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
        let result = await Task.detached(priority: .utility) {
            CodexMonitorClient.fetch()
        }.value
        isRefreshing = false
        state = result
        if case let .ready(snapshot) = result {
            QuotaAlertManager.shared.handle(
                provider: "Codex",
                windows: snapshot.limits.flatMap { limit in
                    limit.windows.compactMap { window in
                        window.remainingPercent.map {
                            QuotaAlertManager.WindowInfo(id: window.id, title: "\(limit.title) \(window.title)", remainingPercent: $0)
                        }
                    }
                }
            )
        }
    }
}

private nonisolated enum CodexMonitorClient {
    private static let cache = CodexMonitorCache()

    static func fetch() -> CodexMonitorState {
        guard let executable = resolveCodexExecutable() else {
            return .unavailable("未找到 Codex CLI 或 Codex.app")
        }

        do {
            let client = try AppServerClient(executablePath: executable)
            defer { client.close() }
            let accountResponse: AccountResponse
            do {
                accountResponse = try client.request(
                    "account/read",
                    params: ["refreshToken": false],
                    as: AccountResponse.self
                )
            } catch {
                // 本地 OAuth token 过期时，Codex app-server 需要一次显式刷新。
                accountResponse = try client.request(
                    "account/read",
                    params: ["refreshToken": true],
                    as: AccountResponse.self
                )
            }

            let account: AccountResponse.Account
            if let localAccount = accountResponse.account {
                account = localAccount
            } else {
                let refreshed = try client.request(
                    "account/read",
                    params: ["refreshToken": true],
                    as: AccountResponse.self
                )
                guard let refreshedAccount = refreshed.account else {
                    return .notLoggedIn("account/read 返回空 account")
                }
                account = refreshedAccount
            }
            let limitsRead = try? client.request("account/rateLimits/read", as: RateLimitsResponse.self)
            let usageRead = try? client.request("account/usage/read", as: UsageResponse.self)
            let cached = cache.merge(accountKey: account.email ?? account.type, limits: limitsRead, usage: usageRead)
            let sessions = CodexLocalSessionScanner.scan(environment: runtimeEnvironment())
            let snapshot = CodexMonitorSnapshot(
                account: account.email ?? (account.type == "apiKey" ? "API Key" : account.type),
                plan: account.planType ?? cached.limits?.rateLimits.planType,
                limits: makeLimits(from: cached.limits),
                resetCreditsAvailableCount: cached.limits?.rateLimitResetCredits?.availableCount,
                usage: cached.usage.map {
                    CodexUsageSummary(
                        lifetimeTokens: $0.summary.lifetimeTokens,
                        peakDailyTokens: $0.summary.peakDailyTokens,
                        currentStreakDays: $0.summary.currentStreakDays,
                        longestStreakDays: $0.summary.longestStreakDays,
                        longestRunningTurnSec: $0.summary.longestRunningTurnSec
                    )
                },
                dailyUsage: aggregateDailyUsage(cached.usage?.dailyUsageBuckets ?? []),
                sessions: sessions,
                isRateLimitsStale: cached.isRateLimitsStale,
                isUsageStale: cached.isUsageStale,
                updatedAt: Date()
            )
            return .ready(snapshot)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private static func makeLimits(from response: RateLimitsResponse?) -> [CodexQuotaLimit] {
        guard let response else { return [] }
        let primaryID = response.rateLimits.limitId ?? "codex"
        let entries: [(String, RateLimitsResponse.RateLimit)]
        if let byID = response.rateLimitsByLimitId, !byID.isEmpty {
            entries = byID.sorted { lhs, rhs in
                if (lhs.key == primaryID) != (rhs.key == primaryID) { return lhs.key == primaryID }
                return (lhs.value.limitName ?? lhs.key).localizedStandardCompare(rhs.value.limitName ?? rhs.key) == .orderedAscending
            }
        } else {
            entries = [(primaryID, response.rateLimits)]
        }

        return entries.compactMap { id, limit in
            let windows = [("primary", "主额度", limit.primary), ("secondary", "次额度", limit.secondary)].compactMap { kind, title, window -> CodexQuotaWindow? in
                guard let window else { return nil }
                return CodexQuotaWindow(
                    id: "\(id)-\(kind)",
                    title: title,
                    remainingPercent: window.usedPercent.map { max(0, min(100, 100 - $0)) },
                    resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    durationMinutes: window.windowDurationMins
                )
            }
            guard !windows.isEmpty else { return nil }
            let title = limit.limitName?.isEmpty == false ? limit.limitName! : id.prefix(1).uppercased() + id.dropFirst()
            return CodexQuotaLimit(id: id, title: title, windows: windows)
        }
    }

    private static func aggregateDailyUsage(_ buckets: [UsageResponse.DailyBucket]) -> [CodexDailyUsage] {
        Dictionary(grouping: buckets, by: \.startDate)
            .map { CodexDailyUsage(date: $0.key, tokens: $0.value.reduce(0) { $0 + $1.tokens }) }
            .sorted { $0.date < $1.date }
    }

    private static func resolveCodexExecutable() -> String? {
        let env = runtimeEnvironment()
        let path = env["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/codex"
            if isUsableExecutable(candidate) { return candidate }
        }
        for candidate in ["/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex"] {
            if isUsableExecutable(candidate) { return candidate }
        }
        return nil
    }

    static func runtimeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Sandboxed builds can expose the app container as HOME. Codex credentials
        // belong to the login user's real home directory.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) }
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let codexHome = environment["CODEX_HOME"]?.isEmpty == false
            ? environment["CODEX_HOME"]!
            : "\(home)/.codex"
        let fallbackPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "/Applications/ChatGPT.app/Contents/Resources",
            "/Applications/Codex.app/Contents/Resources",
            "/usr/bin",
            "/bin"
        ]
        let existingPaths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        environment["HOME"] = home
        environment["CODEX_HOME"] = codexHome
        environment["USER"] = NSUserName()
        environment["LOGNAME"] = NSUserName()
        environment["PATH"] = Array(NSOrderedSet(array: existingPaths + fallbackPaths))
            .compactMap { $0 as? String }
            .joined(separator: ":")
        return environment
    }

    private static func isUsableExecutable(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return FileManager.default.isExecutableFile(atPath: resolved)
    }
}

nonisolated enum CodexLocalSessionScanner {
    private static let activeThreshold: TimeInterval = 120
    private static let recentThreshold: TimeInterval = 2 * 24 * 60 * 60
    private static let metadataReadLimit = 64 * 1024
    private static let indexReadLimit: UInt64 = 1024 * 1024

    static func sessionsRootURL(environment: [String: String]? = nil) -> URL {
        let environment = environment ?? CodexMonitorClient.runtimeEnvironment()
        let codexHome = environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        return URL(fileURLWithPath: codexHome, isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    static func scan(
        environment: [String: String],
        now: Date = Date(),
        limit: Int = 5
    ) -> [CodexSessionSummary] {
        let fileManager = FileManager.default
        let root = sessionsRootURL(environment: environment)
        let titleIndex = loadTitleIndex(codexHome: root.deletingLastPathComponent())
        let calendar = Calendar.autoupdatingCurrent
        let folderFormatter = DateFormatter()
        folderFormatter.calendar = Calendar(identifier: .gregorian)
        folderFormatter.locale = Locale(identifier: "en_US_POSIX")
        folderFormatter.timeZone = .autoupdatingCurrent
        folderFormatter.dateFormat = "yyyy/MM/dd"

        let candidates = (0..<3).flatMap { dayOffset -> [URL] in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { return [] }
            let folder = root.appendingPathComponent(folderFormatter.string(from: date), isDirectory: true)
            return (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        .compactMap { url -> (URL, Date)? in
            guard url.pathExtension == "jsonl" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) <= recentThreshold
            else {
                return nil
            }
            return (url, modifiedAt)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(max(limit * 2, limit))

        return candidates.compactMap { url, modifiedAt in
            parseSession(
                at: url,
                modifiedAt: modifiedAt,
                now: now,
                titleIndex: titleIndex
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    static func parseSessionMetadata(
        _ data: Data,
        transcriptPath: String,
        modifiedAt: Date,
        now: Date,
        titleIndex: [String: String] = [:]
    ) -> CodexSessionSummary? {
        let firstLine = data.prefix { $0 != 0x0A }
        guard
            !firstLine.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: Data(firstLine)) as? [String: Any],
            object["type"] as? String == "session_meta",
            let payload = object["payload"] as? [String: Any]
        else {
            return nil
        }

        let id = (payload["session_id"] as? String)
            ?? (payload["id"] as? String)
            ?? URL(fileURLWithPath: transcriptPath).deletingPathExtension().lastPathComponent
        let cwd = payload["cwd"] as? String
        let projectName = cwd
            .map { URL(fileURLWithPath: $0, isDirectory: true).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "本机任务"
        let title = titleIndex[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceLabel(payload: payload)

        return CodexSessionSummary(
            id: id,
            title: title?.isEmpty == false ? title! : projectName,
            projectName: projectName,
            source: source,
            isActive: abs(now.timeIntervalSince(modifiedAt)) <= activeThreshold,
            updatedAt: modifiedAt,
            transcriptPath: transcriptPath
        )
    }

    private static func parseSession(
        at url: URL,
        modifiedAt: Date,
        now: Date,
        titleIndex: [String: String]
    ) -> CodexSessionSummary? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: metadataReadLimit), !data.isEmpty else { return nil }
        return parseSessionMetadata(
            data,
            transcriptPath: url.path,
            modifiedAt: modifiedAt,
            now: now,
            titleIndex: titleIndex
        )
    }

    private static func loadTitleIndex(codexHome: URL) -> [String: String] {
        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: indexURL) else { return [:] }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd() else { return [:] }
        let start = fileSize > indexReadLimit ? fileSize - indexReadLimit : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [:] }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        if start > 0, !lines.isEmpty {
            lines.removeFirst()
        }

        var result: [String: String] = [:]
        for line in lines {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = (object["id"] as? String) ?? (object["session_id"] as? String),
                let title = (object["threadName"] as? String) ?? (object["title"] as? String),
                !title.isEmpty
            else {
                continue
            }
            result[id] = title
        }
        return result
    }

    private static func sourceLabel(payload: [String: Any]) -> String {
        let rawValues = [
            payload["originator"] as? String,
            payload["source"] as? String,
            (payload["source"] as? [String: Any])?["type"] as? String,
        ]
        let raw = rawValues.compactMap { $0 }.joined(separator: " ").lowercased()
        if raw.contains("vscode") || raw.contains("ide") { return "IDE" }
        if raw.contains("desktop") || raw.contains("codex_app") { return "桌面端" }
        if raw.contains("cli") || raw.contains("exec") { return "CLI" }
        return "Codex"
    }
}

private nonisolated struct AccountResponse: Decodable {
    let account: Account?
    struct Account: Decodable {
        let type: String
        let email: String?
        let planType: String?
    }
}

private nonisolated struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimit
    let rateLimitsByLimitId: [String: RateLimit]?
    let rateLimitResetCredits: ResetCredits?
    struct ResetCredits: Decodable { let availableCount: Int }
    struct RateLimit: Decodable {
        let limitId: String?
        let limitName: String?
        let planType: String?
        let primary: Window?
        let secondary: Window?
    }
    struct Window: Decodable {
        let usedPercent: Int?
        let resetsAt: Int?
        let windowDurationMins: Int?
    }
}

private nonisolated struct UsageResponse: Decodable {
    let summary: Summary
    let dailyUsageBuckets: [DailyBucket]
    struct Summary: Decodable {
        let lifetimeTokens: Int
        let peakDailyTokens: Int
        let currentStreakDays: Int?
        let longestStreakDays: Int?
        let longestRunningTurnSec: Int?
    }
    struct DailyBucket: Decodable {
        let startDate: String
        let tokens: Int
    }
}

private nonisolated final class CodexMonitorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var accountKey: String?
    private var limits: RateLimitsResponse?
    private var usage: UsageResponse?

    func merge(accountKey: String, limits newLimits: RateLimitsResponse?, usage newUsage: UsageResponse?) -> (limits: RateLimitsResponse?, usage: UsageResponse?, isRateLimitsStale: Bool, isUsageStale: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if self.accountKey != accountKey {
            self.accountKey = accountKey
            limits = nil
            usage = nil
        }
        if let newLimits { limits = newLimits }
        if let newUsage { usage = newUsage }
        return (limits, usage, newLimits == nil && limits != nil, newUsage == nil && usage != nil)
    }
}

private nonisolated final class AppServerClient {
    private static let requestTimeout: TimeInterval = 20
    private let process: Process
    private let input: FileHandle
    private let reader: AppServerOutputReader
    private var nextID = 1
    private var buffer = Data()

    init(executablePath: String) throws {
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process = Process()
        input = inputPipe.fileHandleForWriting
        reader = AppServerOutputReader(fileHandle: outputPipe.fileHandleForReading)
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = CodexMonitorClient.runtimeEnvironment()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError
        try process.run()
        _ = try request("initialize", params: ["clientInfo": ["name": "CoolRun", "title": "CoolRun", "version": "1.0"]], as: InitializeResponse.self)
        try send(method: "initialized", id: nil, params: nil)
    }

    func request<Response: Decodable>(_ method: String, params: [String: Any]? = nil, as: Response.Type) throws -> Response {
        let id = nextID
        nextID += 1
        try send(method: method, id: id, params: params)
        let deadline = Date().addingTimeInterval(Self.requestTimeout)
        let decoder = JSONDecoder()
        while Date() < deadline {
            guard let line = try readLine(until: deadline), let data = line.data(using: .utf8) else { continue }
            guard (try? decoder.decode(IDEnvelope.self, from: data))?.id == id else { continue }
            let envelope = try decoder.decode(ResponseEnvelope<Response>.self, from: data)
            if let result = envelope.result { return result }
            throw NSError(domain: "Codex", code: 1, userInfo: [NSLocalizedDescriptionKey: envelope.error?.message ?? "Codex 请求失败"])
        }
        throw NSError(domain: "Codex", code: 2, userInfo: [NSLocalizedDescriptionKey: "Codex 响应超时"])
    }

    func close() {
        try? input.close()
        reader.close()
        if process.isRunning { process.terminate() }
    }

    private func send(method: String, id: Int?, params: [String: Any]?) throws {
        var object: [String: Any] = ["method": method]
        if let id { object["id"] = id }
        if let params { object["params"] = params }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func readLine(until deadline: Date) throws -> String? {
        while Date() < deadline {
            if let index = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<index]
                buffer.removeSubrange(...index)
                return String(data: line, encoding: .utf8)
            }
            guard let line = reader.nextLine(timeout: deadline.timeIntervalSinceNow) else { return nil }
            buffer.append(Data(line.utf8))
            buffer.append(0x0A)
        }
        return nil
    }
}

/// stdout 的非阻塞行读取器。FileHandle.read(upToCount:) 会一直阻塞，不能直接用来实现请求超时。
private nonisolated final class AppServerOutputReader {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let fileHandle: FileHandle
    private var buffer = Data()
    private var closed = false

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        fileHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            self.lock.lock()
            if data.isEmpty {
                self.closed = true
            } else {
                self.buffer.append(data)
            }
            self.lock.unlock()
            self.semaphore.signal()
        }
    }

    func nextLine(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while Date() < deadline {
            lock.lock()
            if let index = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<index]
                buffer.removeSubrange(...index)
                lock.unlock()
                return String(data: line, encoding: .utf8)
            }
            let isClosed = closed
            lock.unlock()
            if isClosed { return nil }

            let result = semaphore.wait(timeout: .now() + deadline.timeIntervalSinceNow)
            if result == .timedOut { return nil }
        }
        return nil
    }

    func close() {
        fileHandle.readabilityHandler = nil
        try? fileHandle.close()
        lock.lock()
        closed = true
        lock.unlock()
        semaphore.signal()
    }
}

private nonisolated struct InitializeResponse: Decodable {}
private nonisolated struct IDEnvelope: Decodable { let id: Int? }
private nonisolated struct ResponseEnvelope<Result: Decodable>: Decodable {
    let result: Result?
    let error: ServerError?
}
private nonisolated struct ServerError: Decodable { let message: String }
