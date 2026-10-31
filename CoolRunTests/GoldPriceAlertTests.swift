import XCTest
@testable import CoolRun

final class GoldPriceAlertTests: XCTestCase {

    private typealias State = GoldPriceAlertManager.State

    /// 固定时区的日历，避免用例结果随运行机器的时区漂移。
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func evaluate(
        price: Double,
        upper: Double?,
        lower: Double?,
        state: State,
        now: Date
    ) -> (alert: GoldPriceAlertManager.Direction?, newState: State) {
        GoldPriceAlertManager.evaluate(
            price: price, upper: upper, lower: lower, state: state, now: now, calendar: calendar
        )
    }

    // MARK: - 每个自然日只提醒一次

    func testUpperFiresOncePerCalendarDay() {
        let day1 = date(2026, 10, 31, 10, 0)

        let first = evaluate(price: 901, upper: 900, lower: nil, state: State(), now: day1)
        XCTAssertEqual(first.alert, .upper)
        XCTAssertEqual(first.newState.lastUpperFiredAt, day1)

        // 同一天内价格继续在上限之上：静默
        let sameDayLater = evaluate(
            price: 905, upper: 900, lower: nil,
            state: first.newState, now: day1.addingTimeInterval(60)
        )
        XCTAssertNil(sameDayLater.alert)

        // 同一天深夜：仍然静默（旧实现这里会因「回落 0.5% 重新武装」再次触发）
        let sameDayNight = evaluate(
            price: 910, upper: 900, lower: nil,
            state: sameDayLater.newState, now: date(2026, 10, 31, 23, 59)
        )
        XCTAssertNil(sameDayNight.alert)

        // 跨到第二天：重新武装，再提醒一次
        let nextDay = evaluate(
            price: 905, upper: 900, lower: nil,
            state: sameDayNight.newState, now: date(2026, 11, 1, 9, 0)
        )
        XCTAssertEqual(nextDay.alert, .upper)
    }

    func testLowerFiresOncePerCalendarDay() {
        let day1 = date(2026, 10, 31, 10, 0)

        let first = evaluate(price: 799, upper: nil, lower: 800, state: State(), now: day1)
        XCTAssertEqual(first.alert, .lower)
        XCTAssertEqual(first.newState.lastLowerFiredAt, day1)

        let sameDay = evaluate(
            price: 795, upper: nil, lower: 800,
            state: first.newState, now: day1.addingTimeInterval(600)
        )
        XCTAssertNil(sameDay.alert)

        let nextDay = evaluate(
            price: 795, upper: nil, lower: 800,
            state: sameDay.newState, now: date(2026, 11, 1, 0, 1)
        )
        XCTAssertEqual(nextDay.alert, .lower)
    }

    func testUpperNotFiredBelowThreshold() {
        let result = evaluate(
            price: 899.99, upper: 900, lower: nil, state: State(), now: date(2026, 10, 31, 10, 0)
        )
        XCTAssertNil(result.alert)
        XCTAssertNil(result.newState.lastUpperFiredAt)
    }

    /// 上下限同轮都满足（上限设得比下限低的极端配置）时优先报下限。
    func testLowerWinsWhenBothCrossed() {
        let now = date(2026, 10, 31, 10, 0)
        let result = evaluate(price: 850, upper: 800, lower: 900, state: State(), now: now)
        XCTAssertEqual(result.alert, .lower)
        XCTAssertEqual(result.newState.lastUpperFiredAt, now)
        XCTAssertEqual(result.newState.lastLowerFiredAt, now)
    }

    /// 上下限互不干扰：上限当天已提醒，不影响下限当天提醒。
    func testDirectionsAreIndependentWithinSameDay() {
        let now = date(2026, 10, 31, 10, 0)
        let upperFired = evaluate(price: 901, upper: 900, lower: 800, state: State(), now: now)
        XCTAssertEqual(upperFired.alert, .upper)

        let lowerFired = evaluate(
            price: 799, upper: 900, lower: 800,
            state: upperFired.newState, now: now.addingTimeInterval(600)
        )
        XCTAssertEqual(lowerFired.alert, .lower)
    }

    // MARK: - 改阈值即重新武装

    func testChangingThresholdRearmsImmediately() {
        let now = date(2026, 10, 31, 10, 0)
        let fired = evaluate(price: 901, upper: 900, lower: nil, state: State(), now: now)
        XCTAssertEqual(fired.alert, .upper)

        // 当天把上限从 900 调到 950，价格 960 已经越过新上限：应该立刻提醒，
        // 不能因为「今天已经提醒过」被压制到明天。
        let afterEdit = evaluate(
            price: 960, upper: 950, lower: nil,
            state: fired.newState, now: now.addingTimeInterval(120)
        )
        XCTAssertEqual(afterEdit.alert, .upper)
    }

    func testSameThresholdDoesNotRearm() {
        let now = date(2026, 10, 31, 10, 0)
        let fired = evaluate(price: 901, upper: 900, lower: nil, state: State(), now: now)
        let again = evaluate(
            price: 960, upper: 900, lower: nil,
            state: fired.newState, now: now.addingTimeInterval(120)
        )
        XCTAssertNil(again.alert)
    }

    // MARK: - 空阈值

    func testNoThresholdsNeverFires() {
        let result = evaluate(
            price: 900, upper: nil, lower: nil, state: State(), now: date(2026, 10, 31, 10, 0)
        )
        XCTAssertNil(result.alert)
        XCTAssertEqual(result.newState, State())
    }

    func testClearingThresholdResetsState() {
        var state = State()
        state.lastUpperFiredAt = date(2026, 10, 31, 9, 0)
        state.upperThreshold = 900

        let result = evaluate(
            price: 950, upper: nil, lower: nil, state: state, now: date(2026, 10, 31, 10, 0)
        )
        XCTAssertNil(result.newState.lastUpperFiredAt)
        XCTAssertNil(result.newState.upperThreshold)
    }

    // MARK: - 阈值解析

    func testParseThreshold() {
        XCTAssertEqual(GoldPriceAlertManager.parseThreshold(" 880.5 "), 880.5)
        XCTAssertNil(GoldPriceAlertManager.parseThreshold(""))
        XCTAssertNil(GoldPriceAlertManager.parseThreshold("abc"))
        XCTAssertNil(GoldPriceAlertManager.parseThreshold("0"))
        XCTAssertNil(GoldPriceAlertManager.parseThreshold("-10"))
    }
}
