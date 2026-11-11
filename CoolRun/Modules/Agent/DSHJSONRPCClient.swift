import Foundation

/// DSH SDK 运行时的最小 JSON-RPC 客户端。
///
/// 协议是 newline-delimited JSON-RPC 2.0 over stdio：一行一条消息，
/// 请求带 id、通知不带 id。没有 cancel 方法，取消就是关进程。
@MainActor
final class DSHJSONRPCClient {
    struct ServerError: LocalizedError {
        let code: Int
        let message: String
        var errorDescription: String? { "DSH 错误 \(code): \(message)" }
    }

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var notificationContinuation: AsyncStream<JSONValue>.Continuation?
    private(set) var isRunning = false

    /// 服务端主动推来的通知（session.event / session.status / subagent.*）。
    private(set) lazy var notifications: AsyncStream<JSONValue> = AsyncStream { continuation in
        self.notificationContinuation = continuation
    }

    // MARK: 生命周期

    func start(executable: URL, arguments: [String], environment: [String: String]) throws {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Pipe 回调在别的线程，不能直接抓 @MainActor 的 self，所以甩回主线程。
        // 这里必须用 weak 而不是 unowned：进程退出/被 terminate 的回调是**异步**送达的，
        // 完全可能在本对象已经释放之后才跑到（换引擎、重建客户端都会先丢引用）。
        // 用 unowned 会在那一刻 abort（swift_unownedRetainStrong），直接把 App 崩掉。
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let owner = self else { return }
            Task { @MainActor in owner.ingest(chunk) }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8),
                  let owner = self else { return }
            Task { @MainActor in owner.logStderr(text) }
        }

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            guard let owner = self else { return }
            Task { @MainActor in owner.handleTermination(code: status) }
        }

        try process.run()

        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
        self.stdoutHandle = stdout.fileHandleForReading
        self.stderrHandle = stderr.fileHandleForReading
        self.isRunning = true
    }

    private(set) var stderrTail: [String] = []

    private func logStderr(_ text: String) {
        stderrTail.append(text)
        if stderrTail.count > 40 {
            stderrTail.removeFirst(stderrTail.count - 40)
        }
    }

    func stop() {
        let proc = process
        let wasRunning = proc?.isRunning ?? false
        isRunning = false
        process = nil

        // 先礼后兵：发一条 shutdown，再关 stdin（dsh 见到 EOF 会自己退出），
        // 1 秒后还赖着就强杀。id 用 0，不挂 continuation，回包直接丢弃。
        if wasRunning, let stdinHandle {
            var line = Data(#"{"jsonrpc":"2.0","id":0,"method":"shutdown"}"#.utf8)
            line.append(0x0A)
            try? stdinHandle.write(contentsOf: line)
        }
        stdinHandle?.closeFile()
        stdinHandle = nil

        // 回调必须在放引用之前摘掉：进程退出的回调可能晚到几秒，
        // 那时本对象可能已经没了（换引擎会立刻丢引用）。
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        proc?.terminationHandler = nil
        stdoutHandle = nil
        stderrHandle = nil

        // 等待中的请求不能就这么悬着：统一回错，界面上才能给出提示。
        let error = ServerError(code: -1, message: "DSH 运行时已关闭")
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
        notificationContinuation?.finish()

        guard wasRunning, let proc else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if proc.isRunning {
                proc.terminate()
            }
        }
    }

    private func handleTermination(code: Int32) {
        isRunning = false
        let error = ServerError(code: Int(code), message: "DSH 运行时已退出")
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
        notificationContinuation?.finish()
    }

    // MARK: 请求

    func request(method: String, params: JSONValue?, timeout: Duration = .seconds(120)) async throws -> JSONValue {
        guard isRunning, let stdinHandle else {
            throw ServerError(code: -1, message: "DSH 运行时没有启动")
        }

        let id = nextID
        nextID += 1

        var payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params, let data = try? JSONEncoder().encode(params),
           let object = try? JSONSerialization.jsonObject(with: data) {
            payload["params"] = object
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            throw ServerError(code: -1, message: "无法编码请求")
        }

        return try await withThrowingTaskGroup(of: JSONValue.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.pending[id] = continuation
                    var line = body
                    line.append(0x0A)
                    do {
                        try stdinHandle.write(contentsOf: line)
                    } catch {
                        self.pending.removeValue(forKey: id)
                        continuation.resume(throwing: error)
                    }
                }
            }
            group.addTask { @MainActor in
                try await Task.sleep(for: timeout)
                throw ServerError(code: -1, message: "\(method) 超时")
            }

            guard let first = try await group.next() else {
                throw ServerError(code: -1, message: "空结果")
            }
            group.cancelAll()
            return first
        }
    }

    // MARK: 接收

    private func ingest(_ chunk: Data) {
        stdoutBuffer.append(chunk)

        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[stdoutBuffer.startIndex..<newline]
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            guard !lineData.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            dispatch(object)
        }
    }

    private func dispatch(_ object: [String: Any]) {
        if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
            if let error = object["error"] as? [String: Any] {
                continuation.resume(throwing: ServerError(
                    code: error["code"] as? Int ?? -1,
                    message: error["message"] as? String ?? "未知错误"
                ))
            } else {
                let value = (object["result"] as? [String: Any])
                    .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                    .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .object([:])
                continuation.resume(returning: value)
            }
            return
        }

        guard let method = object["method"] as? String else { return }
        let params = (object["params"] as? [String: Any])
            .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .object([:])

        var wrapped = params.objectValue ?? [:]
        wrapped["__method"] = .string(method)
        notificationContinuation?.yield(.object(wrapped))
    }
}
