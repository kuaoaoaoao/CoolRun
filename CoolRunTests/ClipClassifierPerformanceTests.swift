import XCTest
@testable import CoolRun

/// 分类曾经把 CPU 打满：它在 `body` 里被反复重算，而每条文本要跑十几次
/// Foundation 的 `range(of:)`。这两个用例把"够快"和"结果稳定"钉住，
/// 免得哪天又被挪回 body 里。
final class ClipClassifierPerformanceTests: XCTestCase {

    /// 造 200 条接近真实的混合历史：长文、代码、命令、链接、数字各占一部分。
    private func makeEntries(count: Int = 200) -> [ClipboardHistoryEntry] {
        let samples: [String] = [
            "https://github.com/PostHog/posthog-ios/blob/main/README.md",
            "git commit -m \"fix: 修一下登录态丢失\"",
            """
            struct Foo {
                let bar: Int
                func baz() { print(bar) }
            }
            """,
            "1,299.50",
            String(repeating: "这是一段很长的会议记录，需要整理成要点。", count: 30),
            "明天下午三点和张工对一下排期，会议室B",
            "sudo launchctl bootout system/com.apple.foo",
            "def main():\n    return 1\n",
        ]
        let now = Date()
        return (0..<count).map { index in
            ClipboardHistoryEntry(
                id: UUID(),
                text: samples[index % samples.count],
                copiedAt: now.addingTimeInterval(TimeInterval(-index)),
                isPinned: false
            )
        }
    }

    /// 真实的剪贴板里会躺着几 MB 的文本（整份日志、整段代码）。
    /// 分类器曾经对这种文本逐字符扫全文，一次分类要几秒。
    func testClassifyingHugeEntriesIsFast() {
        let huge = String(repeating: "这是一行很长的日志内容 abcdefghijklmnopqrstuvwxyz 0123456789\n", count: 40_000)
        XCTAssertGreaterThan(huge.utf8.count, 2_000_000)

        let start = Date()
        let kind = ClipClassifier.kind(of: huge)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.2, "分类一条 2MB 文本花了 \(elapsed)s")
        XCTAssertEqual(kind, .long)
    }

    /// 截断采样不能改变短文本的判定结果。
    func testSampleKeepsShortTextsIntact() {
        let short = "https://example.com/a"
        XCTAssertEqual(ClipClassifier.sample(of: short), short)
        XCTAssertEqual(ClipClassifier.kind(of: short), .link)
    }

    func testClassifyingTwoHundredEntriesIsFast() {
        let entries = makeEntries()
        let start = Date()
        for _ in 0..<20 {
            _ = ClipClassifier.classify(entries)
        }
        let elapsed = Date().timeIntervalSince(start)
        // 20 轮 × 200 条 = 4000 次判定。旧实现在这里要几秒；
        // 新实现应该远低于 0.5 秒，留足余量给慢机器。
        XCTAssertLessThan(elapsed, 0.5, "分类太慢了：20 轮 200 条用了 \(elapsed) 秒")
    }

    func testClassificationIsStable() {
        let entries = makeEntries()
        let first = ClipClassifier.classify(entries)
        let second = ClipClassifier.classify(entries)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, entries.count)

        let counts = ClipClassifier.counts(from: first)
        XCTAssertEqual(counts.values.reduce(0, +), entries.count)
        // 8 个样本按顺序循环 25 轮：link 25、command 50、code 50、number 25、long 25、text 25。
        XCTAssertEqual(counts[.link], 25)
        XCTAssertEqual(counts[.command], 50)
        XCTAssertEqual(counts[.code], 50)
        XCTAssertEqual(counts[.number], 25)
        XCTAssertEqual(counts[.long], 25)
        XCTAssertEqual(counts[.text], 25)
    }
}
