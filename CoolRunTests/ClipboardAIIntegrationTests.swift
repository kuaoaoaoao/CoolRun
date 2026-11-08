import XCTest
@testable import CoolRun

/// 剪贴板 AI 的真实模型联调。
///
/// 默认跳过：没有环境变量时，会尝试用 app 自己已经保存的 Agent 配置（密钥走
/// `SecretStore` 解密，不进日志）。两条路都没有才 `XCTSkip`。
final class ClipboardAIIntegrationTests: XCTestCase {

    private func env(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    @MainActor
    private func requireConfig() throws -> AgentRunConfig {
        if let baseURL = env("AGENT_IT_BASEURL"), let apiKey = env("AGENT_IT_KEY") {
            return AgentRunConfig(
                protocolKind: .openAIChat,
                apiKey: apiKey,
                baseURL: baseURL,
                model: env("AGENT_IT_MODEL") ?? "global:deepseek-v4.1-flash",
                temperature: 0.2,
                maxTokens: 1024,
                maxRounds: 1
            )
        }

        // 只有显式打开才跑：常规自检不该因为网络或模型脾气而变红。
        guard env("AGENT_IT_USE_APP_CONFIG") == "1" else {
            throw XCTSkip("未设置 AGENT_IT_BASEURL / AGENT_IT_KEY（或 AGENT_IT_USE_APP_CONFIG=1），跳过剪贴板 AI 联调")
        }

        let settings = AgentSettings.shared
        let saved = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saved.isEmpty, !settings.baseURL.isEmpty, !settings.model.isEmpty else {
            throw XCTSkip("AGENT_IT_USE_APP_CONFIG=1，但 app 里没有配好的模型，跳过")
        }
        return try settings.makeConfig()
    }

    @MainActor
    func testSummarizeRealModel() async throws {
        _ = try requireConfig()

        let source = """
        关于这次发布，有几件事需要同步：第一，v2.3.0 会在下周三上午十点全量推送，\
        灰度从周一早上八点开始，覆盖 5% 用户；第二，本次修复了三个线上问题，\
        分别是登录态偶发丢失、导出文件名乱码、以及后台任务在休眠后不再触发；\
        第三，如果灰度期间错误率超过 0.5%，就回滚到 v2.2.7，回滚脚本是 ./scripts/rollback.sh。
        """

        let ai = ClipboardAI.shared
        ai.clearOutput()
        await ai.transform(source, action: .summarize)

        XCTAssertNil(ai.errorMessage, "整理失败：\(ai.errorMessage ?? "")")
        let output = ai.output
        XCTAssertFalse(output.isEmpty)
        // 要点式输出：应该有 2 行以上，且不该把"任务："/"内容："这类提示词漏出来
        XCTAssertGreaterThanOrEqual(output.components(separatedBy: "\n").count, 2, "输出：\(output)")
        XCTAssertFalse(output.contains("任务："), "输出：\(output)")
        XCTAssertFalse(output.contains("内容："), "输出：\(output)")
    }

    @MainActor
    func testFindByMeaningRealModel() async throws {
        _ = try requireConfig()

        let now = Date()
        let entries = [
            ClipboardHistoryEntry(
                id: UUID(),
                text: "postgres://readonly:pw@10.0.0.7:5432/analytics",
                copiedAt: now,
                isPinned: false
            ),
            ClipboardHistoryEntry(
                id: UUID(),
                text: "明天下午三点和张工对一下排期，会议室 B",
                copiedAt: now,
                isPinned: false
            ),
            ClipboardHistoryEntry(
                id: UUID(),
                text: "https://github.com/PostHog/posthog-ios",
                copiedAt: now,
                isPinned: false
            ),
        ]

        let ai = ClipboardAI.shared
        let hits = await ai.findByMeaning("那个存分析数据的数据库连不上，把连接串找出来", in: entries)

        XCTAssertNil(ai.searchError, "按意思找失败：\(ai.searchError ?? "")")
        XCTAssertEqual(hits, [entries[0].id], "命中的应该是数据库连接串那一条")
    }
}
