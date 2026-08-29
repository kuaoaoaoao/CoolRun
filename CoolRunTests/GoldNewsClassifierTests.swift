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
}
