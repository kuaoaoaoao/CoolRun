import XCTest
@testable import CoolRun

final class GoldPositionAdvisorTests: XCTestCase {
    func testRejectsInvalidHoldingInput() {
        XCTAssertNil(GoldPositionAdvisor.analyze(
            currentPrice: 800,
            grams: 0,
            averageCost: 700,
            report: nil,
            signal: nil,
            lang: .chinese
        ))
    }

    func testCalculatesHoldingProfit() throws {
        let advice = try XCTUnwrap(GoldPositionAdvisor.analyze(
            currentPrice: 800,
            grams: 10,
            averageCost: 700,
            report: nil,
            signal: nil,
            lang: .chinese
        ))

        XCTAssertEqual(advice.costBasis, 7_000, accuracy: 0.001)
        XCTAssertEqual(advice.marketValue, 8_000, accuracy: 0.001)
        XCTAssertEqual(advice.profitLoss, 1_000, accuracy: 0.001)
        XCTAssertEqual(advice.profitPercent, 1.0 / 7.0, accuracy: 0.000_001)
    }
}
