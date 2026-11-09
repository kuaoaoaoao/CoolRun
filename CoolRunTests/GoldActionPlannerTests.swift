import XCTest
@testable import CoolRun

/// `GoldActionPlanner` 是「现在怎么办」卡片和 `gold_plan` 工具共用的决策层，
/// 出错的话用户看到的价位就是错的，所以这几个不变量必须有测试兜底。
final class GoldActionPlannerTests: XCTestCase {

    // MARK: - 夹具

    private func snapshot(
        price: Double,
        sma5: Double? = nil,
        sma20: Double? = nil,
        sma60: Double? = nil,
        rsi: Double? = nil,
        volatility: Double? = 0.12,
        support: Double? = nil,
        resistance: Double? = nil
    ) -> TechnicalSnapshot {
        TechnicalSnapshot(
            sma5: sma5,
            sma20: sma20,
            sma60: sma60,
            ema12: nil,
            ema26: nil,
            rsi14: rsi,
            macdLine: nil,
            macdSignal: nil,
            macdHistogram: nil,
            bollingerUpper: nil,
            bollingerMiddle: nil,
            bollingerLower: nil,
            volatility: volatility,
            roc10: nil,
            supportLevel: support,
            resistanceLevel: resistance,
            timestamp: Date()
        )
    }

    // MARK: - 价位

    func testLevelsAreOrderedForBuying() {
        let price = 780.0
        guard let plan = GoldActionPlanner.plan(
            currentPrice: price,
            snapshot: snapshot(price: price, sma5: 790, sma20: 760, rsi: 55, support: 740, resistance: 820),
            signal: nil,
            report: nil,
            weeklyForecast: nil,
            language: .chinese
        ) else {
            return XCTFail("正常输入不该返回 nil")
        }

        XCTAssertLessThan(plan.stopLoss, plan.entryLow, "止损必须低于买入区")
        XCTAssertLessThanOrEqual(plan.entryLow, plan.entryHigh, "买入区上下界不能反")
        XCTAssertLessThan(plan.entryHigh, plan.target, "目标价必须高于买入区")
    }

    func testLevelsAreOrderedForSelling() {
        let price = 780.0
        // 均线空头排列（-0.10）+ RSI 超买（-0.10）+ 空头技术信号（-0.12）
        // 加起来才够「减仓」这一档；单靠 RSI 只能到 -0.10，会判成持有。
        let bearishSignal = TradingSignal(
            direction: .sell,
            strength: .strong,
            score: -100,
            suggestedEntry: nil,
            suggestedStopLoss: nil,
            suggestedTakeProfit: nil,
            reasons: [],
            timestamp: Date()
        )
        guard let plan = GoldActionPlanner.plan(
            currentPrice: price,
            snapshot: snapshot(price: price, sma5: 700, sma20: 760, sma60: 800, rsi: 82, support: 700, resistance: 800),
            signal: bearishSignal,
            report: nil,
            weeklyForecast: nil,
            language: .chinese
        ) else {
            return XCTFail("正常输入不该返回 nil")
        }

        XCTAssertTrue(plan.verb.isBearish, "空头条件下不该给出买入，实际：\(plan.verb)")
        // 减仓/卖出是「离场」语义：止损在价格上方（反弹就认错），目标在下方。
        XCTAssertGreaterThan(plan.stopLoss, price, "离场计划的止损应在上方")
        XCTAssertLessThan(plan.target, price, "离场计划的目标应在下方")
    }

    func testExtremeVolatilitySuppressesBuying() {
        let price = 780.0
        let plan = GoldActionPlanner.plan(
            currentPrice: price,
            snapshot: snapshot(price: price, sma5: 800, sma20: 750, rsi: 50, volatility: 0.95),
            signal: nil,
            report: nil,
            weeklyForecast: nil,
            language: .chinese
        )
        XCTAssertNotNil(plan)
        // 极端波动只压「买入」这类明确指令，允许持有/减仓。
        XCTAssertFalse(plan?.verb == .buy, "极端波动下不该直接喊买入")
    }

    func testInvalidPriceReturnsNil() {
        XCTAssertNil(GoldActionPlanner.plan(
            currentPrice: 0,
            snapshot: snapshot(price: 0),
            signal: nil,
            report: nil,
            weeklyForecast: nil,
            language: .chinese
        ))
    }

    // MARK: - 文案

    func testReasonsAreHumanReadableAndBounded() {
        let price = 780.0
        guard let plan = GoldActionPlanner.plan(
            currentPrice: price,
            snapshot: snapshot(price: price, sma5: 790, sma20: 760, rsi: 62, support: 740, resistance: 820),
            signal: nil,
            report: nil,
            weeklyForecast: nil,
            language: .chinese
        ) else {
            return XCTFail("正常输入不该返回 nil")
        }

        XCTAssertFalse(plan.reasons.isEmpty, "卡片上没有理由等于没解释")
        XCTAssertLessThanOrEqual(plan.reasons.count, 5, "理由超过 5 条就没人看了")
        XCTAssertLessThanOrEqual(plan.risks.count, 3)
        XCTAssertFalse(plan.invalidation.isEmpty)
        for reason in plan.reasons {
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testActionTitlesAreDistinct() {
        let titles = GoldActionVerb.allCases.map { $0.title(.chinese) }
        XCTAssertEqual(Set(titles).count, titles.count, "五个动作的中文标题不能重名：\(titles)")
    }

    func testConfidenceStaysInRange() {
        for composite in stride(from: -1.0, through: 1.0, by: 0.25) {
            let value = GoldActionPlanner.confidenceValue(composite: composite, report: nil)
            XCTAssertGreaterThanOrEqual(value, 0.05)
            XCTAssertLessThanOrEqual(value, 0.92, "不该假装确定")
        }
    }

    func testDailyMoveFallsBackWithoutVolatility() {
        let move = GoldActionPlanner.dailyMoveEstimate(price: 780, snapshot: snapshot(price: 780, volatility: nil))
        XCTAssertEqual(move, 780 * 0.006, accuracy: 0.001)
    }

    func testDailyMoveIsClamped() {
        // 年化 500% 这种离谱值不能推出一个 10% 的日波动。
        let wild = GoldActionPlanner.dailyMoveEstimate(price: 1000, snapshot: snapshot(price: 1000, volatility: 5.0))
        XCTAssertLessThanOrEqual(wild, 50.0)
        let calm = GoldActionPlanner.dailyMoveEstimate(price: 1000, snapshot: snapshot(price: 1000, volatility: 0.0001))
        XCTAssertGreaterThanOrEqual(calm, 1.5)
    }
}
