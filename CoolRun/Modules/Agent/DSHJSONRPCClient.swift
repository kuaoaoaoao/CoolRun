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

        // Pipe 回调在别的线程，不能直接抓 @MainActor 的 self。
        // 用 unowned 捕获：stop() 会把 readabilityHandler 清空，生命周期由本对象管。
        stdout.fileHandleForReading.readabilityHandler = { [unowned self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self.ingest(chunk) }
        }

        stderr.fileHandleForReading.readabilityHandler = { [unowned self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            Task { @MainActor in self.logStderr(text) }
        }

        process.terminationHandler = { [unowned self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self.handleTermination(code: status) }
        }

        try process.run()

        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
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
        guard let process, process.isRunning else {
            isRunning = false
            return
        }
        // 先礼后兵：shutdown 请求，1 秒后强杀。
        Task { @MainActor in
            _ = try? await request(method: "shutdown", params: nil, timeout: .seconds(1))
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning {
                process.terminate()
            }
        }
        isRunning = false
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
