import CryptoKit
import Foundation

/// 下载并安装 DeepSeek Harness 运行时（轻量版按需安装用）。
///
/// 从 PyPI 拿单文件 wheel（约 90 MB），校验 SHA256，解包，只留三个可执行文件。
/// 装到 `~/Library/Application Support/CoolRun/AgentRuntime/`，和 `.app` 完全隔离，
/// 升级 app 不会把它覆盖掉。
@MainActor
@Observable
final class AgentRuntimeInstaller {
    static let shared = AgentRuntimeInstaller()

    enum State: Equatable {
        case idle
        case preparing
        case downloading(progress: Double)
        case verifying
        case extracting
        case done
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparing, .downloading, .verifying, .extracting: return true
            case .idle, .done, .failed: return false
            }
        }

        var label: String {
            switch self {
            case .idle: return "未安装"
            case .preparing: return "查询版本…"
            case .downloading(let progress): return "下载中 \(Int(progress * 100))%"
            case .verifying: return "校验中…"
            case .extracting: return "解包中…"
            case .done: return "已安装"
            case .failed(let message): return "失败：\(message)"
            }
        }
    }

    private(set) var state: State = .idle

    /// 上次安装的版本号，用于判断要不要提示升级。
    private(set) var installedVersion: String?

    private init() {
        installedVersion = AgentRuntimeLocator.readVersion(in: AgentRuntimeLocator.downloadedRoot)
        if installedVersion != nil {
            state = .done
        }
    }

    // MARK: 安装

    func install() async {
        guard !state.isBusy else { return }
        do {
            state = .preparing
            let release = try await Self.latestRelease()

            state = .downloading(progress: 0)
            let downloaded = try await Self.download(release) { [unowned self] progress in
                Task { @MainActor in
                    guard case .downloading = self.state else { return }
                    self.state = .downloading(progress: progress)
                }
            }

            state = .verifying
            try Self.verify(downloaded.fileURL, sha256: release.sha256)

            state = .extracting
            try await Self.extractAndInstall(downloaded.fileURL, version: release.version)

            installedVersion = release.version
            AgentRuntimeLocator.shared.refresh()
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func uninstall() {
        let root = AgentRuntimeLocator.downloadedRoot
        try? FileManager.default.removeItem(at: root)
        installedVersion = nil
        AgentRuntimeLocator.shared.refresh()
        state = .idle
    }

    // MARK: 元数据

    struct Release: Sendable {
        let version: String
        let downloadURL: URL
        let sha256: String
        let fileName: String
    }

    /// 问 PyPI 要最新的 macOS arm64 wheel。
    static func latestRelease() async throws -> Release {
        let meta = URL(string: "https://pypi.org/pypi/deepseek-harness-runtime-bin/json")!
        var request = URLRequest(url: meta)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.badResponse
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["info"] as? [String: Any],
              let version = info["version"] as? String,
              let urls = root["urls"] as? [[String: Any]]
        else {
            throw InstallError.badResponse
        }

        // 只要 macOS arm64 的 wheel；Intel 机器先不支持，给个明确错误。
        guard let entry = urls.first(where: { entry in
            let name = entry["filename"] as? String ?? ""
            return name.contains("macosx") && name.contains("arm64")
        }),
            let fileURLString = entry["url"] as? String,
            let fileURL = URL(string: fileURLString),
            let fileName = entry["filename"] as? String,
            let digests = entry["digests"] as? [String: Any],
            let sha256 = digests["sha256"] as? String
        else {
            throw InstallError.unsupportedPlatform
        }

        return Release(
            version: version,
            downloadURL: fileURL,
            sha256: sha256,
            fileName: fileName
        )
    }

    // MARK: 下载

    struct DownloadResult: Sendable {
        let fileURL: URL
    }

    private static func download(
        _ release: Release,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> DownloadResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("coolrun-agent-runtime", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let target = directory.appendingPathComponent(release.fileName)

        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: release.downloadURL)
        request.timeoutInterval = 600
        let task = session.downloadTask(with: request)

        let temporary = try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            task.resume()
        }

        // 系统在回调返回后会删掉临时文件，必须马上搬走。
        try FileManager.default.moveItem(at: temporary, to: target)
        return DownloadResult(fileURL: target)
    }

    // MARK: 校验与解包

    private static func verify(_ file: URL, sha256 expected: String) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1 << 20)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw InstallError.checksumMismatch
        }
    }

    /// 目录枚举是同步 API，放在 async 函数里会报 makeIterator 不可用。
    private nonisolated static func collectRuntimeFiles(in staging: URL) -> [String: URL] {
        let wanted = [
            "deepseek-harness-sdk-runtime",
            "deepseek-harness-sdk-runtime-rg",
            "deepseek-harness-sdk-runtime-spawn-helper",
        ]
        var found: [String: URL] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: staging,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return found }

        for case let file as URL in enumerator {
            let name = file.lastPathComponent
            if wanted.contains(name), found[name] == nil {
                found[name] = file
            }
        }
        return found
    }

    private static func extractAndInstall(_ wheel: URL, version: String) async throws {
        let root = AgentRuntimeLocator.downloadedRoot
        let staging = root.deletingLastPathComponent().appendingPathComponent("AgentRuntime.staging", isDirectory: true)

        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        // wheel 就是个 zip，用系统的 unzip，不引第三方库。
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-oq", wheel.path, "-d", staging.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.unzipFailed
        }

        // 只挑运行时需要的三个文件，其余（wheel 元数据）丢掉。
        let found = Self.collectRuntimeFiles(in: staging)

        guard let executable = found["deepseek-harness-sdk-runtime"] else {
            throw InstallError.missingExecutable
        }

        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for (name, source) in found {
            let destination = root.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
        _ = executable

        try version.write(to: root.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: staging)
    }

    // MARK: 错误

    enum InstallError: LocalizedError {
        case badResponse
        case unsupportedPlatform
        case checksumMismatch
        case unzipFailed
        case missingExecutable

        var errorDescription: String? {
            switch self {
            case .badResponse: return "PyPI 返回的数据看不懂"
            case .unsupportedPlatform: return "这个版本没有 Apple 芯片的包"
            case .checksumMismatch: return "下载的文件校验不通过，可能被改过"
            case .unzipFailed: return "解包失败"
            case .missingExecutable: return "包里找不到可执行文件"
            }
        }
    }
}

// MARK: - 下载回调

/// URLSession 的下载进度回调在后台线程，这里只负责把数值转出去。
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var storedContinuation: CheckedContinuation<URL, Error>?

    var continuation: CheckedContinuation<URL, Error>? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedContinuation
        }
        set {
            lock.lock()
            storedContinuation = newValue
            lock.unlock()
        }
    }

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // 回调返回后 location 会被删除，先搬到不会被清理的临时位置。
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("coolrun-runtime-\(UUID().uuidString).whl")
        do {
            try FileManager.default.moveItem(at: location, to: stable)
            continuation?.resume(returning: stable)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let continuation else { return }
        continuation.resume(throwing: error)
        self.continuation = nil
    }
}
