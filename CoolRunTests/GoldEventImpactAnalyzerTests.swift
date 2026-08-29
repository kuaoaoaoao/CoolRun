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
}
