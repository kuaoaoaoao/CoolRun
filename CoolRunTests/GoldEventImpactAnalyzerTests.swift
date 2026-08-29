import XCTest
@testable import CoolRun

final class GoldEventImpactAnalyzerTests: XCTestCase {
    func testUnavailableImpactIsNeutralAndContainsNoEvidence() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let impact = GoldEventImpact.unavailable(now: now, language: .chinese)

        XCTAssertEqual(impact.direction, .neutral)
        XCTAssertEqual(impact.confidence, .unavailable)
        XCTAssertEqual(impact.dataState, .unavailable)
        XCTAssertTrue(impact.evidence.isEmpty)
        XCTAssertEqual(impact.updatedAt, now)
    }

    func testDirectionalFactoryRejectsDirectionWithoutObservedEvidence() {
        let impact = GoldEventImpact.make(
            direction: .bearish,
            confidence: .high,
            volatilityRisk: .elevated,
            headline: "短线偏空",
            evidence: [],
            counterRisks: [],
            updatedAt: Date(timeIntervalSince1970: 1_788_000_000),
            dataState: .live,
            language: .chinese
        )

        XCTAssertEqual(impact.direction, .neutral)
        XCTAssertEqual(impact.confidence, .unavailable)
        XCTAssertEqual(impact.dataState, .unavailable)
    }

    // MARK: - Task 3

    func testEmptyInputFailsClosed() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let impact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: [],
                macro: nil,
                globalSnapshot: nil,
                dataState: .unavailable,
                now: now
            ),
            language: .chinese
        )

        XCTAssertEqual(impact.dataState, .unavailable)
        XCTAssertEqual(impact.direction, .neutral)
        XCTAssertTrue(impact.evidence.isEmpty)
    }

    func testHawkishNewsWithoutMarketConfirmationIsLowConfidenceBearish() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let item = GoldNewsItem(
            title: "Fed keeps rate hike option open; gold market watches inflation",
            source: "Reuters",
            link: URL(string: "https://example.com/fed"),
            publishedAt: now.addingTimeInterval(-600),
            sentimentScore: -18
        )

        let impact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: [item],
                macro: nil,
                globalSnapshot: nil,
                dataState: .partial,
                now: now
            ),
            language: .english
        )

        XCTAssertEqual(impact.direction, .bearish)
        XCTAssertEqual(impact.confidence, .low)
        XCTAssertEqual(impact.dataState, .partial)
        XCTAssertFalse(impact.headline.lowercased().contains("sell"))
    }

    func testHawkishNewsWithYieldRiseAndGoldDropReachesHighConfidence() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let item = GoldNewsItem(
            title: "Fed rate hike odds rise as gold price falls",
            source: "Reuters",
            link: URL(string: "https://example.com/market"),
            publishedAt: now.addingTimeInterval(-300),
            sentimentScore: -36
        )
        let macro = GoldMacroSnapshot(
            tenYearYield: 4.72,
            tenYearYieldChangeBps: 5.6,
            observedAt: now
        )
        let global = GoldGlobalSnapshot(
            xauUsd: 4_454.52,
            xauPrevClose: 4_601.30,
            usdCny: 7.10,
            dollarIndex: 99.71,
            updatedAt: now
        )

        let impact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: [item],
                macro: macro,
                globalSnapshot: global,
                dataState: .live,
                now: now
            ),
            language: .english
        )

        XCTAssertEqual(impact.direction, .bearish)
        XCTAssertEqual(impact.confidence, .high)
        XCTAssertTrue(impact.evidence.contains { $0.kind == .treasuryYield })
        XCTAssertTrue(impact.evidence.contains { $0.kind == .goldPrice })
    }

    func testGeopoliticalBullishImpactKeepsHighVolatilityRisk() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let item = GoldNewsItem(
            title: "Gold price rises on geopolitical conflict and safe-haven demand",
            source: "Reuters",
            link: nil,
            publishedAt: now,
            sentimentScore: 36
        )

        let impact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: [item],
                macro: nil,
                globalSnapshot: nil,
                dataState: .partial,
                now: now
            ),
            language: .english
        )

        XCTAssertEqual(impact.direction, .bullish)
        XCTAssertEqual(impact.volatilityRisk, .high)
    }

    // MARK: - 中文场景（自旧局势感知测试迁移；不再断言交易动作）

    func testWarshHawkishChineseScenarioIsBearishWithoutTradeAction() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let items = [
            GoldNewsItem(
                title: "美联储主席沃什在杰克逊霍尔发表鹰派演讲，加息预期升温",
                source: "证券时报",
                link: URL(string: "https://stcn.com/example"),
                publishedAt: now.addingTimeInterval(-600),
                sentimentScore: -36
            )
        ]
        let macro = GoldMacroSnapshot(
            tenYearYield: 4.72,
            tenYearYieldChangeBps: 5.6,
            observedAt: now
        )
        let global = GoldGlobalSnapshot(
            xauUsd: 4_454.52,
            xauPrevClose: 4_601.30,
            usdCny: 7.10,
            dollarIndex: 99.71,
            updatedAt: now
        )

        let impact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: items,
                macro: macro,
                globalSnapshot: global,
                dataState: .live,
                now: now
            ),
            language: .chinese
        )

        XCTAssertEqual(impact.direction, .bearish)
        XCTAssertEqual(impact.confidence, .high)
        XCTAssertTrue(impact.evidence.contains {
            $0.kind == .centralBankStatement && $0.state == .observed
        })
        // 事件影响只负责解释：标题不得出现买卖动作
        XCTAssertFalse(impact.headline.contains("减仓"))
        XCTAssertFalse(impact.headline.contains("卖出"))
        XCTAssertFalse(impact.headline.contains("持有"))
    }

    func testDovishChineseScenarioIsBullish() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let items = [
            GoldNewsItem(
                title: "美联储释放鸽派信号，降息预期升温",
                source: "凤凰财经",
                link: URL(string: "https://ifeng.com/example"),
                publishedAt: now.addingTimeInterval(-600),
                sentimentScore: 36
            )
        ]
        let macro = GoldMacroSnapshot(
            tenYearYield: 4.31,
            tenYearYieldChangeBps: -4.2,
            observedAt: now
        )
        let global = GoldGlobalSnapshot(
            xauUsd: 4_612.00,
            xauPrevClose: 4_560.00,
            usdCny: 7.10,
            dollarIndex: 98.20,
            updatedAt: now
        )

        let impact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: items,
                macro: macro,
                globalSnapshot: global,
                dataState: .live,
                now: now
            ),
            language: .chinese
        )

        XCTAssertEqual(impact.direction, .bullish)
        XCTAssertEqual(impact.confidence, .high)
    }

    func testNeutralChineseNewsFailsClosedWithoutEvidence() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let items = [
            GoldNewsItem(
                title: "黄金市场横盘整理，方向不明",
                source: "证券时报",
                link: nil,
                publishedAt: now.addingTimeInterval(-600),
                sentimentScore: 0
            )
        ]

        let impact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: items,
                macro: nil,
                globalSnapshot: nil,
                dataState: .live,
                now: now
            ),
            language: .chinese
        )

        XCTAssertEqual(impact.direction, .neutral)
        XCTAssertEqual(impact.confidence, .unavailable)
        XCTAssertTrue(impact.evidence.isEmpty)
    }

    // MARK: - 矛盾证据（Task 8）

    func testContradictoryMarketDataCapsConfidenceAndFlagsCounterRisk() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        // 同一事件的三篇转载新闻偏空
        let items = [
            GoldNewsItem(
                title: "美联储主席沃什放鹰，加息预期升温压制黄金",
                source: "新浪财经",
                link: nil,
                publishedAt: now.addingTimeInterval(-600),
                sentimentScore: -30
            ),
            GoldNewsItem(
                title: "美联储主席沃什放鹰，加息预期升温压制黄金",
                source: "东方财富",
                link: nil,
                publishedAt: now.addingTimeInterval(-700),
                sentimentScore: -30
            ),
            GoldNewsItem(
                title: "美联储主席沃什放鹰，加息预期升温压制黄金",
                source: "同花顺",
                link: nil,
                publishedAt: now.addingTimeInterval(-800),
                sentimentScore: -30
            )
        ]
        // 市场维度与新闻矛盾：收益率下行、黄金上涨
        let macro = GoldMacroSnapshot(
            tenYearYield: 4.31,
            tenYearYieldChangeBps: -5.6,
            observedAt: now
        )
        let global = GoldGlobalSnapshot(
            xauUsd: 4_612.00,
            xauPrevClose: 4_560.00,
            usdCny: 7.10,
            dollarIndex: 98.20,
            updatedAt: now
        )

        let impact = GoldEventImpactAnalyzer.analyze(
            GoldEventImpactInput(
                newsItems: items,
                macro: macro,
                globalSnapshot: global,
                dataState: .live,
                now: now
            ),
            language: .chinese
        )

        XCTAssertTrue(
            impact.direction == .neutral || impact.confidence == .low,
            "矛盾证据不得给出高置信方向，实际 direction=\(impact.direction) confidence=\(impact.confidence)"
        )
        XCTAssertTrue(
            impact.counterRisks.contains { $0.contains("市场数据未确认媒体方向") },
            "反方风险必须提示市场数据未确认媒体方向"
        )
        // 三篇转载新闻只算一条媒体证据，不得各自投票压过两个真实市场维度
        let mediaEvidence = impact.evidence.filter {
            $0.state == .observed && $0.kind != .treasuryYield && $0.kind != .goldPrice
        }
        XCTAssertEqual(mediaEvidence.count, 1, "转载新闻聚类后只保留一条媒体证据")
    }
}
