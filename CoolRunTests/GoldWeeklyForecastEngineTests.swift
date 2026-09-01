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

    // MARK: - Task 3：组合模型

    func testRisingDailySeriesProducesUpDraft() throws {
        let closes = makeCloses(count: 220) { 520 + Double($0) * 0.45 }
        let input = makeEngineInput(closes: closes, seed: 42)
        let draft = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(input))
        XCTAssertEqual(draft.direction, .up)
        XCTAssertGreaterThan(draft.components.composite, 0.18)
        XCTAssertLessThanOrEqual(draft.p10, draft.p50)
        XCTAssertLessThanOrEqual(draft.p50, draft.p90)
    }

    func testFlatSeriesProducesFlatDraft() throws {
        let closes = makeCloses(count: 220) { 600 + sin(Double($0)) * 0.3 }
        XCTAssertEqual(
            GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 7))?.direction,
            .flat
        )
    }

    func testFallingDailySeriesProducesDownDraft() throws {
        let closes = makeCloses(count: 220) { 720 - Double($0) * 0.4 }
        XCTAssertEqual(
            GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 8))?.direction,
            .down
        )
    }

    func testSameSeedProducesIdenticalRange() throws {
        let closes = makeNoisyCloses(count: 220)
        let lhs = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 99)))
        let rhs = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 99)))
        XCTAssertEqual(lhs, rhs)
    }

    func testFewerThanOneHundredTwentyClosesReturnsNil() {
        XCTAssertNil(GoldWeeklyForecastEngine.makeDraft(
            makeEngineInput(closes: makeCloses(count: 119) { 600 + Double($0) * 0.1 }, seed: 1)
        ))
    }

    // MARK: - Task 3 Step 5：数值安全

    func testConstantPriceSeriesProducesFlatDraftWithFiniteValues() throws {
        let closes = makeCloses(count: 220) { _ in 600 }
        let draft = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 3)))
        XCTAssertEqual(draft.direction, .flat)
        XCTAssertTrue(draft.expectedPrice.isFinite && draft.expectedPrice > 0)
        XCTAssertTrue(draft.expectedReturn.isFinite)
        XCTAssertTrue(draft.p10.isFinite && draft.p10 > 0)
        XCTAssertTrue(draft.p50.isFinite && draft.p50 > 0)
        XCTAssertTrue(draft.p90.isFinite && draft.p90 > 0)
        XCTAssertLessThanOrEqual(draft.p10, draft.p50)
        XCTAssertLessThanOrEqual(draft.p50, draft.p90)
    }

    func testExtremelyLowVolatilitySeriesStaysFinite() throws {
        let closes = makeCloses(count: 220) { 600 + Double($0) * 1e-6 }
        let draft = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 5)))
        XCTAssertTrue(draft.components.trend.isFinite)
        XCTAssertTrue(draft.components.momentum.isFinite)
        XCTAssertTrue(draft.components.meanReversion.isFinite)
        XCTAssertTrue(draft.components.bootstrap.isFinite)
        XCTAssertTrue(draft.components.composite.isFinite)
        XCTAssertTrue(draft.p10.isFinite && draft.p10 > 0)
    }

    func testSeriesWithRepeatedPricesStaysFiniteAndOrdered() throws {
        // 交替重复价格制造零收益区块，检验区块自助法不得产生 NaN 或乱序区间。
        let closes = makeCloses(count: 220) { index in
            index % 3 == 0 ? 600 : (index % 3 == 1 ? 600 : 601)
        }
        let draft = try XCTUnwrap(GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 6)))
        XCTAssertTrue(draft.p10.isFinite && draft.p10 > 0)
        XCTAssertTrue(draft.p90.isFinite && draft.p90 > 0)
        XCTAssertLessThanOrEqual(draft.p10, draft.p50)
        XCTAssertLessThanOrEqual(draft.p50, draft.p90)
    }

    // MARK: - Task 8 Step 3：模型版本回归

    func testModelVersionMatchesPinnedValue() throws {
        // 固定 220 点 fixture + seed=42 的完整输出快照。
        // 任何改变 direction/components/P10/P50/P90 的算法或权重修改，
        // 必须同时提升 GoldWeeklyForecastPolicy.modelVersion 并更新本快照，
        // 不允许静默改变历史模型语义。
        let closes = makeNoisyCloses(count: 220)
        let draft = try XCTUnwrap(
            GoldWeeklyForecastEngine.makeDraft(makeEngineInput(closes: closes, seed: 42))
        )
        XCTAssertEqual(GoldWeeklyForecastPolicy.modelVersion, "gold-weekly-2026.08.30.1")
        XCTAssertEqual(draft.direction, .flat)
        XCTAssertEqual(draft.components.trend, 0.406_137_461_772_287_2, accuracy: 0.000_001)
        XCTAssertEqual(draft.components.momentum, -0.706_147_453_294_348_9, accuracy: 0.000_001)
        XCTAssertEqual(draft.components.meanReversion, 0.370_277_142_395_021_6, accuracy: 0.000_001)
        XCTAssertEqual(draft.components.bootstrap, 0.052_5, accuracy: 0.000_001)
        XCTAssertEqual(draft.components.composite, 0.034_277_819_655_966_5, accuracy: 0.000_001)
        XCTAssertEqual(draft.p10, 589.542_981_486_232_6, accuracy: 0.000_001)
        XCTAssertEqual(draft.p50, 595.431_403_882_729_7, accuracy: 0.000_001)
        XCTAssertEqual(draft.p90, 601.985_602_334_002_2, accuracy: 0.000_001)
    }

    // MARK: - 确定性 fixture

    private func makeCloses(
        count: Int,
        price: (Int) -> Double
    ) -> [GoldDailyClose] {
        let start = Date(timeIntervalSince1970: 1_740_000_000)
        return (0..<count).map { index in
            GoldDailyClose(
                date: Calendar.goldShanghai.date(byAdding: .day, value: index, to: start)!,
                close: price(index)
            )
        }
    }

    private func makeNoisyCloses(count: Int) -> [GoldDailyClose] {
        makeCloses(count: count) { index in
            580 + Double(index) * 0.08 + sin(Double(index) * 0.71) * 2.4
        }
    }

    private func makeEngineInput(
        closes: [GoldDailyClose],
        seed: UInt64
    ) -> GoldWeeklyForecastEngineInput {
        let generatedAt = closes.last!.date
        return GoldWeeklyForecastEngineInput(
            closes: closes,
            startPrice: closes.last!.close,
            generatedAt: generatedAt,
            targetDate: Calendar.goldShanghai.date(byAdding: .day, value: 7, to: generatedAt)!,
            seed: seed
        )
    }
}
