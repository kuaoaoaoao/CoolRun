import XCTest
@testable import CoolRun

final class GoldWeeklyForecastBacktesterTests: XCTestCase {
    func testAnchorsUseOnlyTheirHistoricalPrefixAndAreSevenDaysApart() {
        let closes = makeBacktestCloses(count: 420)
        let trace = GoldWeeklyForecastBacktester.debugTrace(closes: closes, seed: 10)
        XCTAssertTrue(trace.allSatisfy { $0.inputLastDate <= $0.anchorDate })
        for pair in zip(trace, trace.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.anchorDate.timeIntervalSince(pair.0.anchorDate),
                7 * 24 * 60 * 60
            )
        }
    }

    func testReleaseGateRejectsFewerThanTwentyFourResolvedSamples() {
        let summary = GoldWeeklyForecastBacktester.evaluate(
            closes: makeBacktestCloses(count: 220),
            seed: 11
        )
        XCTAssertFalse(summary.passedReleaseGate)
        XCTAssertTrue(summary.failureReasons.contains("resolved_samples"))
    }

    func testMajorityClassOnlyModelCannotPassBalancedAccuracyGate() {
        let summary = GoldWeeklyForecastBacktester.makeSummary(
            observations: makeObservationsAlwaysPredictingUp()
        )
        XCTAssertFalse(summary.passedReleaseGate)
        XCTAssertLessThan(summary.balancedAccuracy ?? 1, 0.38)
    }

    // MARK: - Task 4 Step 5：结果反转防泄漏

    func testChangingOnlyFuturePricesKeepsAnchorPredictionIdentical() throws {
        let base = makeBacktestCloses(count: 260)
        // 只修改第 200 点之后的未来价格
        var twisted = base
        for index in 200..<twisted.count {
            twisted[index] = GoldDailyClose(
                date: twisted[index].date,
                close: twisted[index].close * (index % 2 == 0 ? 1.03 : 0.97)
            )
        }

        // 第 199 点是满足 >=120 历史前缀的 anchor
        let anchorIndex = GoldWeeklyForecastPolicy.minimumDailyCloses - 1
        let baseAnchor = base[anchorIndex]
        let twistedAnchor = twisted[anchorIndex]

        let baseDraft = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(
            GoldWeeklyForecastEngineInput(
                closes: Array(base[...anchorIndex]),
                startPrice: baseAnchor.close,
                generatedAt: baseAnchor.date,
                targetDate: Calendar.goldShanghai.date(byAdding: .day, value: 7, to: baseAnchor.date)!,
                seed: 77
            )
        ))
        let twistedDraft = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(
            GoldWeeklyForecastEngineInput(
                closes: Array(twisted[...anchorIndex]),
                startPrice: twistedAnchor.close,
                generatedAt: twistedAnchor.date,
                targetDate: Calendar.goldShanghai.date(byAdding: .day, value: 7, to: twistedAnchor.date)!,
                seed: 77
            )
        ))

        // 前缀完全相同 → 该 anchor 的预测必须完全一致
        XCTAssertEqual(baseDraft, twistedDraft)

        // 但第 199 点 anchor 的 actual label 可以不同（未来价格不同）
        let baseOutcomeIndex = anchorIndex + 7
        let twistedOutcomeIndex = anchorIndex + 7
        let baseReturn = base[baseOutcomeIndex].close / baseAnchor.close - 1
        let twistedReturn = twisted[twistedOutcomeIndex].close / twistedAnchor.close - 1
        if baseReturn != twistedReturn {
            XCTAssertNotEqual(
                GoldWeeklyForecastDirection.classify(actualReturn: baseReturn),
                GoldWeeklyForecastDirection.classify(actualReturn: twistedReturn)
            )
        }
    }

    func testFixedInputProducesIdenticalMetrics() {
        let closes = makeBacktestCloses(count: 320)
        let lhs = GoldWeeklyForecastBacktester.evaluate(closes: closes, seed: 21)
        let rhs = GoldWeeklyForecastBacktester.evaluate(closes: closes, seed: 21)
        XCTAssertEqual(lhs, rhs)
    }

    // MARK: - 确定性 fixture

    private func makeBacktestCloses(count: Int) -> [GoldDailyClose] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            GoldDailyClose(
                date: Calendar.goldShanghai.date(byAdding: .day, value: index, to: start)!,
                close: 520 + Double(index) * 0.12 + sin(Double(index) / 9) * 5
            )
        }
    }

    private func makeObservationsAlwaysPredictingUp() -> [GoldWeeklyForecastBacktestObservation] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let actuals: [GoldWeeklyForecastDirection] = [.up, .up, .up, .flat, .flat, .flat, .down, .down, .down]
        return actuals.enumerated().map { index, actual in
            let date = Calendar.goldShanghai.date(byAdding: .day, value: index * 7, to: start)!
            let actualReturn: Double = actual == .up ? 0.01 : (actual == .down ? -0.01 : 0)
            return GoldWeeklyForecastBacktestObservation(
                anchorDate: date,
                inputLastDate: date,
                predicted: .up,
                actual: actual,
                predictedReturn: 0.01,
                actualReturn: actualReturn
            )
        }
    }
}
