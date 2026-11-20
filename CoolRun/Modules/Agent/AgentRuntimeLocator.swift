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

        nonisolated func displayName(_ lang: AppLanguage) -> String {
            switch self {
            case .bundled:
                return LocalizedString.l(
                    lang,
                    en: "Bundled",
                    zh: "内置",
                    ja: "内蔵",
                    ko: "내장"
                )
            case .downloaded:
                return LocalizedString.l(
                    lang,
                    en: "Downloaded",
                    zh: "已下载",
                    ja: "ダウンロード済み",
                    ko: "다운로드됨"
                )
            case .systemPath:
                return LocalizedString.l(
                    lang,
                    en: "System",
                    zh: "系统安装",
                    ja: "システム",
                    ko: "시스템"
                )
            }
        }
    }

    struct Runtime: Sendable, Equatable {
        let executable: URL
        let source: Source
        let version: String?
    }

    private(set) var runtime: Runtime?

    /// 被优先级挡在后面、没有生效的那一个。设置页要能说清「你下载了但它没在用」,
    /// 否则完整版里点「下载」看上去成功、实际毫无变化。
    private(set) var shadowed: Runtime?

    /// 用户是否点名要「已下载的」优先于「内置的」。
    ///
    /// 默认关：完整版靠内置运行时自包含，不该被用户目录里一份来路不明的旧二进制顶掉。
    /// 但完整版也要有办法试新版引擎 —— 不重打 dmg 就只能靠这个开关。
    private(set) var preferDownloaded = AgentRuntimeLocator.storedPreferDownloaded

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

    nonisolated static let preferDownloadedKey = "agent.preferDownloadedRuntime"

    nonisolated static var storedPreferDownloaded: Bool {
        UserDefaults.standard.bool(forKey: preferDownloadedKey)
    }

    func setPreferDownloaded(_ value: Bool) {
        guard value != preferDownloaded else { return }
        preferDownloaded = value
        UserDefaults.standard.set(value, forKey: Self.preferDownloadedKey)
        refresh()
    }

    func refresh() {
        let resolved = Self.resolve(
            bundled: Self.bundledRuntime(),
            downloaded: Self.downloadedRuntime(),
            system: Self.systemRuntime(),
            preferDownloaded: preferDownloaded
        )
        runtime = resolved.active
        shadowed = resolved.shadowed
    }

    /// 纯选择逻辑，不碰文件系统，便于单测。
    ///
    /// 默认顺序：内置 → 已下载 → 系统 PATH。勾了开关就改成 已下载 → 内置 → 系统 PATH。
    nonisolated static func resolve(
        bundled: Runtime?,
        downloaded: Runtime?,
        system: Runtime?,
        preferDownloaded: Bool
    ) -> (active: Runtime?, shadowed: Runtime?) {
        if preferDownloaded, let downloaded {
            return (downloaded, bundled)
        }
        if let bundled {
            return (bundled, downloaded)
        }
        if let downloaded {
            return (downloaded, nil)
        }
        return (system, nil)
    }

    nonisolated static func bundledRuntime() -> Runtime? {
        guard let executable = CoolRunEdition.bundledRuntimeExecutable else { return nil }
        return Runtime(
            executable: executable,
            source: .bundled,
            version: readVersion(in: executable.deletingLastPathComponent())
        )
    }

    nonisolated static func downloadedRuntime() -> Runtime? {
        let executable = downloadedExecutable
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return Runtime(
            executable: executable,
            source: .downloaded,
            version: readVersion(in: downloadedRoot)
        )
    }

    /// 系统 PATH 里的 `dsh` 只认真正可执行的单文件 runtime，不认 npm 全局装的脚本入口 ——
    /// 那个依赖系统 Node，菜单栏 app 不该假设有。
    nonisolated static func systemRuntime() -> Runtime? {
        guard let path = which("dsh") else { return nil }
        return Runtime(executable: URL(fileURLWithPath: path), source: .systemPath, version: nil)
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
