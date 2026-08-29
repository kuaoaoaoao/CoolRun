import XCTest
@testable import CoolRun

final class GoldNewsClassifierTests: XCTestCase {
    func testWarshDoesNotMatchWarRiskKeyword() {
        let result = GoldNewsClassifier.classify(
            title: "Warsh discusses the policy framework",
            source: "Federal Reserve"
        )
        XCTAssertFalse(result.isGeopolitical)
        XCTAssertEqual(result.direction, .neutral)
        XCTAssertEqual(result.sentimentScore, 0)
    }

    func testPersonAndVenueDoNotImplyHawkishDirection() {
        let result = GoldNewsClassifier.classify(
            title: "Powell and Warsh attend the Jackson Hole symposium",
            source: "Reuters"
        )
        XCTAssertEqual(result.direction, .neutral)
    }

    func testNegatedRateHikeDoesNotBecomeBearish() {
        let result = GoldNewsClassifier.classify(
            title: "Fed chair says a rate hike is not decided",
            source: "Reuters"
        )
        XCTAssertNotEqual(result.direction, .bearish)
        XCTAssertGreaterThanOrEqual(result.sentimentScore, 0)
    }

    func testDownwardYieldAndDollarSignalsRemainBullishForGold() {
        let result = GoldNewsClassifier.classify(
            title: "Dollar index falls as Treasury yields decline, gold rises",
            source: "Reuters"
        )
        XCTAssertEqual(result.direction, .bullish)
    }

    func testGoldCupRacingTitleIsRejected() {
        let result = GoldNewsClassifier.classify(
            title: "2026 High Limit Racing Gold Cup results at Silver Dollar Speedway",
            source: "FloRacing"
        )
        XCTAssertFalse(result.isFinanciallyRelevant)
    }

    func testSyndicatedTitlesShareOneEventKey() {
        let lhs = GoldNewsClassifier.eventKey(
            title: "Warsh signals inflation concern; gold falls - Reuters"
        )
        let rhs = GoldNewsClassifier.eventKey(
            title: "Warsh signals inflation concern as gold falls | Yahoo Finance"
        )
        XCTAssertEqual(lhs, rhs)
    }

    // MARK: - 来源质量（Task 8）

    func testSourceTiersClassifyOfficialAndEstablishedSources() {
        // 官方机构：primary
        XCTAssertEqual(GoldNewsClassifier.sourceTier("Federal Reserve"), .primary)
        XCTAssertEqual(GoldNewsClassifier.sourceTier("美联储官方"), .primary)
        // 主要通讯社与主流财经媒体：established
        XCTAssertEqual(GoldNewsClassifier.sourceTier("Reuters"), .established)
        XCTAssertEqual(GoldNewsClassifier.sourceTier("Associated Press"), .established)
        XCTAssertEqual(GoldNewsClassifier.sourceTier("证券时报"), .established)
        XCTAssertEqual(GoldNewsClassifier.sourceTier("凤凰财经"), .established)
        // 未知博客：unknown
        XCTAssertEqual(GoldNewsClassifier.sourceTier("某位作者的个人观察博客"), .unknown)
        XCTAssertEqual(GoldNewsClassifier.sourceTier(nil), .unknown)
        // established 不得误判为 primary
        XCTAssertNotEqual(GoldNewsClassifier.sourceTier("Reuters"), .primary)
    }

    func testSourceTierDoesNotChangeEvidenceDirection() {
        let title = "美联储主席放鹰，加息预期升温压制黄金"
        let official = GoldNewsClassifier.classify(title: title, source: "Federal Reserve")
        let blog = GoldNewsClassifier.classify(title: title, source: "某位作者的个人观察博客")

        // 来源等级只影响 confidence，不得改变证据本身的方向
        XCTAssertEqual(official.direction, blog.direction)
        XCTAssertEqual(official.isFinanciallyRelevant, blog.isFinanciallyRelevant)
        XCTAssertEqual(GoldNewsClassifier.sourceTier("Federal Reserve"), .primary)
        XCTAssertEqual(GoldNewsClassifier.sourceTier("某位作者的个人观察博客"), .unknown)
    }
}
