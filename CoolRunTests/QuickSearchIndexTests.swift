import XCTest
@testable import CoolRun

/// 统一搜索的排序是纯函数，单独测。索引本身要读各个 store，留给界面验证。
final class QuickSearchIndexTests: XCTestCase {
    private func item(
        _ id: String,
        _ title: String,
        category: QuickSearchCategory = .module,
        keywords: String = ""
    ) -> QuickSearchItem {
        QuickSearchItem(
            id: id,
            title: title,
            detail: "",
            symbol: "circle",
            category: category,
            keywords: keywords,
            action: .openModule(.today)
        )
    }

    func testEmptyQueryReturnsItemsInOrder() {
        let items = [item("a", "今天"), item("b", "监控")]
        let ranked = QuickSearchIndex.rank(items, query: "")
        XCTAssertEqual(ranked.map(\.id), ["a", "b"])
    }

    func testEmptyQueryRespectsLimit() {
        let items = (0..<10).map { item("i\($0)", "项目 \($0)") }
        XCTAssertEqual(QuickSearchIndex.rank(items, query: "", limit: 3).count, 3)
    }

    func testExactTitleBeatsPrefixAndContains() {
        let items = [
            item("contains", "今日金价如何"),
            item("prefix", "金价走势"),
            item("exact", "金价", category: .clipboard)
        ]
        // 完全相等分最高，哪怕类别权重最低（剪贴板）也排第一。
        XCTAssertEqual(QuickSearchIndex.rank(items, query: "金价").map(\.id), ["exact", "prefix", "contains"])
    }

    func testTitleMatchBeatsKeywordMatch() {
        let items = [
            item("keyword", "某某工具", keywords: "screenshot"),
            item("title", "截图")
        ]
        let ranked = QuickSearchIndex.rank(items, query: "截")
        XCTAssertEqual(ranked.first?.id, "title")
    }

    func testKeywordMatchFindsEnglishAlias() {
        let items = [item("gold", "金价", keywords: "gold_price")]
        XCTAssertEqual(QuickSearchIndex.rank(items, query: "gold").first?.id, "gold")
    }

    func testCaseInsensitive() {
        let items = [item("monitor", "Monitor")]
        XCTAssertEqual(QuickSearchIndex.rank(items, query: "MONITOR").count, 1)
    }

    func testMultiWordQueryNeedsAllPieces() {
        let items = [
            item("both", "电脑体检", keywords: "health-check"),
            item("onlyOne", "电脑")
        ]
        let ranked = QuickSearchIndex.rank(items, query: "电脑 体检")
        XCTAssertEqual(ranked.map(\.id), ["both"])
    }

    func testCategoryWeightBreaksTies() {
        let items = [
            item("clip", "备份", category: .clipboard),
            item("module", "备份", category: .module)
        ]
        XCTAssertEqual(QuickSearchIndex.rank(items, query: "备份").first?.id, "module")
    }

    func testNoMatchReturnsEmpty() {
        let items = [item("a", "今天")]
        XCTAssertTrue(QuickSearchIndex.rank(items, query: "zzz").isEmpty)
    }

    func testShorterTitleWinsOnEqualScore() {
        let items = [
            item("long", "今天的天气怎么样"),
            item("short", "今天")
        ]
        XCTAssertEqual(QuickSearchIndex.rank(items, query: "今天").first?.id, "short")
    }
}
