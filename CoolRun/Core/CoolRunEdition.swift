import Foundation

/// 发行版本。
///
/// 两个版本共用一份代码和一个 bundle id，区别只在于 `.app` 里有没有内置的
/// Agent 运行时。判断方式是看资源目录，而不是编译期开关 —— 这样打包脚本
/// 只要决定拷不拷运行时，不需要第二个 Xcode target。
enum CoolRunEdition: String, Sendable {
    /// 轻量版：运行时按需下载。
    case lite
    /// 完整版：运行时内置，断网也能跑。
    case full

    nonisolated static var current: CoolRunEdition {
        bundledRuntimeExecutable == nil ? .lite : .full
    }

    /// 内置运行时里真正被 `Process` 启动的那个可执行文件。
    nonisolated static var bundledRuntimeExecutable: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources
            .appendingPathComponent("AgentRuntime", isDirectory: true)
            .appendingPathComponent("deepseek-harness-sdk-runtime")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    nonisolated var displayName: String {
        self == .full ? "CoolRun" : "CoolRun Lite"
    }

    nonisolated var hasBundledRuntime: Bool { self == .full }
}

extension CoolRunEdition {
    /// 写进 UserDefaults，用于诊断上报和设置页展示。
    nonisolated static let defaultsKey = "coolrun.edition"

    @MainActor
    static func recordCurrent() {
        UserDefaults.standard.set(current.rawValue, forKey: defaultsKey)
    }
}
