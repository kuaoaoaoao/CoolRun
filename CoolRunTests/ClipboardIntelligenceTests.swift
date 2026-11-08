import XCTest
@testable import CoolRun

final class ClipboardIntelligenceTests: XCTestCase {
    // MARK: - 本地分类

    func testClassifiesLinks() {
        XCTAssertEqual(ClipClassifier.kind(of: "https://github.com/PostHog/posthog-ios"), .link)
        XCTAssertEqual(ClipClassifier.kind(of: "  http://127.0.0.1:11434/v1  "), .link)
        XCTAssertEqual(ClipClassifier.kind(of: "www.apple.com/mac"), .link)
        // 只是提到网址的句子不是链接
        XCTAssertEqual(ClipClassifier.kind(of: "文档在 https://example.com 这里"), .text)
    }

    func testClassifiesCommands() {
        XCTAssertEqual(ClipClassifier.kind(of: "git commit -m \"fix: thing\""), .command)
        XCTAssertEqual(ClipClassifier.kind(of: "sudo launchctl bootout system/x"), .command)
        XCTAssertEqual(ClipClassifier.kind(of: "curl -s http://localhost:7863/v1/models"), .command)
    }

    func testClassifiesCode() {
        let swift = """
        struct Foo {
            let bar: Int
            func baz() { print(bar) }
        }
        """
        XCTAssertEqual(ClipClassifier.kind(of: swift), .code)
        XCTAssertEqual(ClipClassifier.kind(of: "def main():\n    return 1"), .code)
    }

    func testClassifiesNumbers() {
        XCTAssertEqual(ClipClassifier.kind(of: "1,299.50"), .number)
        XCTAssertEqual(ClipClassifier.kind(of: "+3.25%"), .number)
        XCTAssertEqual(ClipClassifier.kind(of: "¥ 1 024"), .number)
        // 含字母就不是纯数字
        XCTAssertEqual(ClipClassifier.kind(of: "1024 MB"), .text)
    }

    func testClassifiesLongText() {
        let paragraph = String(repeating: "这是一段很长的说明文字。", count: 40)
        XCTAssertEqual(ClipClassifier.kind(of: paragraph), .long)
    }

    func testShortPlainTextFallsBackToText() {
        XCTAssertEqual(ClipClassifier.kind(of: "明天下午三点开会"), .text)
        XCTAssertEqual(ClipClassifier.kind(of: ""), .text)
    }

    func testCountsByKind() {
        let now = Date()
        let entries = [
            ClipboardHistoryEntry(id: UUID(), text: "https://a.example.com", copiedAt: now, isPinned: false),
            ClipboardHistoryEntry(id: UUID(), text: "https://b.example.com", copiedAt: now, isPinned: false),
            ClipboardHistoryEntry(id: UUID(), text: "git status", copiedAt: now, isPinned: false),
            ClipboardHistoryEntry(id: UUID(), text: "随便一句话", copiedAt: now, isPinned: false),
        ]
        let counts = ClipClassifier.counts(for: entries)
        XCTAssertEqual(counts[.link], 2)
        XCTAssertEqual(counts[.command], 1)
        XCTAssertEqual(counts[.text], 1)
        XCTAssertNil(counts[.code])
    }

    // MARK: - 语义搜索的回复解析

    func testParsesIndicesFromPlainArray() {
        XCTAssertEqual(ClipboardAI.parseIndices("[3,7]", upperBound: 10), [2, 6])
    }

    func testParsesIndicesThroughCodeFence() {
        let reply = """
        ```json
        [1, 4, 9]
        ```
        """
        XCTAssertEqual(ClipboardAI.parseIndices(reply, upperBound: 10), [0, 3, 8])
    }

    func testParsesIndicesDropsOutOfRangeAndDuplicates() {
        XCTAssertEqual(ClipboardAI.parseIndices("[0, 2, 2, 99, 5]", upperBound: 5), [1, 4])
    }

    func testParsesIndicesIgnoresProse() {
        XCTAssertEqual(ClipboardAI.parseIndices("我挑了第 2 条和第 3 条", upperBound: 5), [1, 2])
        XCTAssertEqual(ClipboardAI.parseIndices("[]", upperBound: 5), [])
        XCTAssertEqual(ClipboardAI.parseIndices("都不相关", upperBound: 5), [])
        XCTAssertEqual(ClipboardAI.parseIndices("3", upperBound: 0), [])
    }

    // MARK: - 片段压缩

    func testSnippetCollapsesWhitespaceAndTruncates() {
        let messy = "第一行\n\n   第二行   \t 第三行"
        XCTAssertEqual(ClipboardAI.snippet(messy), "第一行 第二行 第三行")

        let long = String(repeating: "字", count: 500)
        XCTAssertEqual(ClipboardAI.snippet(long, limit: 12).count, 12)
    }
}
