import Foundation

/// 找 DeepSeek Harness 运行时。
///
/// 三个来源，优先级从高到低：
/// 1. 完整版内置在 `.app/Contents/Resources/AgentRuntime` 里的；
/// 2. 用户从设置页下载到 Application Support 的；
/// 3. 系统里已经装好的 `dsh`（开发机常见）。
///
/// 找到之后要 spawn 它跑 JSON-RPC，所以只认真正可执行的单文件 runtime，
/// 不认 npm 全局装的脚本入口 —— 那个依赖系统 Node，菜单栏 app 不该假设有。
@MainActor
@Observable
final class AgentRuntimeLocator {
    static let shared = AgentRuntimeLocator()

    enum Source: String, Sendable {
        case bundled
        case downloaded
        case systemPath

        nonisolated var displayName: String {
            switch self {
            case .bundled: return "内置"
            case .downloaded: return "已下载"
            case .systemPath: return "系统安装"
            }
        }
    }

    struct Runtime: Sendable, Equatable {
        let executable: URL
        let source: Source
        let version: String?
    }

    private(set) var runtime: Runtime?

    private init() {
        refresh()
    }

    /// 下载的运行时放这儿，和内置的完全隔离，升级 app 不会覆盖。
    nonisolated static var downloadedRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("CoolRun", isDirectory: true)
            .appendingPathComponent("AgentRuntime", isDirectory: true)
    }

    nonisolated static var downloadedExecutable: URL {
        downloadedRoot.appendingPathComponent("deepseek-harness-sdk-runtime")
    }

    func refresh() {
        runtime = Self.locate()
    }

    nonisolated static func locate() -> Runtime? {
        // 1. 内置
        if let bundled = CoolRunEdition.bundledRuntimeExecutable {
            return Runtime(
                executable: bundled,
                source: .bundled,
                version: readVersion(in: bundled.deletingLastPathComponent())
            )
        }

        // 2. 下载的
        let downloaded = downloadedExecutable
        if FileManager.default.isExecutableFile(atPath: downloaded.path) {
            return Runtime(
                executable: downloaded,
                source: .downloaded,
                version: readVersion(in: downloadedRoot)
            )
        }

        // 3. 系统 PATH 里的 dsh
        if let path = which("dsh") {
            return Runtime(executable: URL(fileURLWithPath: path), source: .systemPath, version: nil)
        }

        return nil
    }

    nonisolated static func readVersion(in directory: URL) -> String? {
        let file = directory.appendingPathComponent("version.txt")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 不用 `Process` 跑 `which`，免得为一次查找开个子进程。
    nonisolated static func which(_ command: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }
}
