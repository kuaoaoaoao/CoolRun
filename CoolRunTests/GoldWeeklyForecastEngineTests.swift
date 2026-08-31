import XCTest
@testable import CoolRun

final class GoldWeeklyForecastEngineTests: XCTestCase {
    func testActualReturnClassificationUsesHalfPercentBand() {
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: 0.005_001), .up)
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: 0.005), .flat)
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: 0), .flat)
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: -0.005), .flat)
        XCTAssertEqual(GoldWeeklyForecastDirection.classify(actualReturn: -0.005_001), .down)
    }

    func testUnavailableSnapshotContainsNoForecast() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let snapshot = GoldWeeklyForecastSnapshot.unavailable(
            status: .insufficientHistory,
            message: "历史不足",
            now: now
        )
        XCTAssertNil(snapshot.forecast)
        XCTAssertNil(snapshot.backtest)
        XCTAssertEqual(snapshot.updatedAt, now)
    }

    func testConfidenceCannotUpgradePastHighOrBelowUnavailable() {
        XCTAssertEqual(GoldWeeklyForecastConfidence.high.upgraded, .high)
        XCTAssertEqual(GoldWeeklyForecastConfidence.low.downgraded, .unavailable)
    }
}
