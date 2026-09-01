import XCTest
@testable import CoolRun

final class GoldWeeklyForecastServiceTests: XCTestCase {

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private func makeHistoryPoints(count: Int, endingAt: Date) -> [GoldRemotePricePoint] {
        let calendar = Calendar.goldShanghai
        return (0..<count).map { index in
            let offset = index - (count - 1)
            let timestamp = calendar.date(byAdding: .day, value: offset, to: endingAt)!
            return GoldRemotePricePoint(price: 580 + Double(index) * 0.1, timestamp: timestamp)
        }
    }

    private func makeDraft() -> GoldWeeklyForecastDraft {
        GoldWeeklyForecastDraft(
            direction: .up,
            expectedPrice: 606,
            expectedReturn: 0.01,
            p10: 594,
            p50: 606,
            p90: 618,
            components: GoldWeeklyForecastComponents(
                trend: 0.5, momentum: 0.4, meanReversion: 0.2, bootstrap: 0.3, composite: 0.35
            )
        )
    }

    private func makePassingBacktest() -> GoldWeeklyForecastBacktestSummary {
        GoldWeeklyForecastBacktestSummary(
            resolvedCount: 40,
            classCounts: [.up: 15, .flat: 12, .down: 13],
            overallAccuracy: 0.55,
            balancedAccuracy: 0.46,
            majorityBaselineAccuracy: 0.40,
            meanAbsoluteReturnError: 0.012,
            confusionMatrix: [
                .up: [.up: 8, .flat: 4, .down: 3],
                .flat: [.up: 3, .flat: 6, .down: 3],
                .down: [.up: 2, .flat: 5, .down: 6]
            ],
            passedReleaseGate: true,
            failureReasons: []
        )
    }

    private func makeFailingBacktest() -> GoldWeeklyForecastBacktestSummary {
        GoldWeeklyForecastBacktestSummary(
            resolvedCount: 10,
            classCounts: [.up: 5, .flat: 4, .down: 1],
            overallAccuracy: 0.30,
            balancedAccuracy: 0.28,
            majorityBaselineAccuracy: 0.50,
            meanAbsoluteReturnError: 0.02,
            confusionMatrix: [:],
            passedReleaseGate: false,
            failureReasons: ["resolved_samples", "balanced_accuracy"]
        )
    }

    private func makeRequest(
        price: Double = 600,
        source: String = "JD-MS",
        event: GoldEventImpact? = nil,
        at date: Date? = nil
    ) -> GoldWeeklyForecastRequest {
        GoldWeeklyForecastRequest(
            currentPrice: price,
            currentPriceSource: source,
            eventImpact: event,
            now: date ?? now
        )
    }

    private func makeEvent(
        direction: GoldImpactDirection,
        confidence: GoldImpactConfidence = .high,
        dataState: GoldIntelligenceDataState = .live
    ) -> GoldEventImpact {
        GoldEventImpact(
            direction: direction,
            confidence: confidence,
            volatilityRisk: .normal,
            headline: "fixture",
            evidence: [],
            counterRisks: [],
            updatedAt: now,
            dataState: dataState
        )
    }

    private func makeService(
        history: GoldWeeklyForecastServiceTests.HistoryProviderStub,
        draft: GoldWeeklyForecastDraft? = nil,
        backtest: GoldWeeklyForecastBacktestSummary
    ) -> GoldWeeklyForecastService {
        let fixedDraft = draft ?? makeDraft()
        return GoldWeeklyForecastService(
            historyProvider: history,
            modelRunner: GoldWeeklyForecastModelRunner(
                makeDraft: { _ in fixedDraft },
                backtest: { _, _ in backtest }
            )
        )
    }

    // MARK: - 历史数据 stub（actor，记录调用次数）

    private actor HistoryProviderStub: GoldWeeklyHistoryProviding {
        private let points: [GoldRemotePricePoint]
        private let error: Error?
        private(set) var callCount = 0

        init(points: [GoldRemotePricePoint] = [], error: Error? = nil) {
            self.points = points
            self.error = error
        }

        func fetchHistoryPrices(
            range: GoldHistoryRange,
            now: Date
        ) async throws -> [GoldRemotePricePoint] {
            callCount += 1
            if let error { throw error }
            return points
        }
    }

    private struct StubError: Error {}

    // MARK: - 来源兼容性解析

    func testResolverMapsKnownSources() {
        XCTAssertEqual(GoldForecastSourceCompatibilityResolver.resolve(
            currentSource: "JD-MS", historySource: "JD-MS-history"), .verified)
        XCTAssertEqual(GoldForecastSourceCompatibilityResolver.resolve(
            currentSource: "JD-official", historySource: "JD-MS-history"), .verified)
        XCTAssertEqual(GoldForecastSourceCompatibilityResolver.resolve(
            currentSource: "CZB-JCJ", historySource: "JD-MS-history"), .proxy)
        XCTAssertEqual(GoldForecastSourceCompatibilityResolver.resolve(
            currentSource: "unknown-src", historySource: "JD-MS-history"), .incompatible)
        XCTAssertEqual(GoldForecastSourceCompatibilityResolver.resolve(
            currentSource: "JD-MS", historySource: "other-history"), .incompatible)
    }

    // MARK: - 六种服务状态

    func testInsufficientHistoryWhenFewerThanOneHundredTwentyPoints() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 119, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .insufficientHistory)
        XCTAssertNil(snapshot.forecast)
        XCTAssertTrue(snapshot.message.contains("119"))
        XCTAssertTrue(snapshot.message.contains("120"))
    }

    func testStaleDataWhenLatestCloseIsNinetySevenHoursOld() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 130, endingAt: now.addingTimeInterval(-97 * 3600))
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .staleData)
        XCTAssertNil(snapshot.forecast)
    }

    func testUnknownCurrentSourceIsSourceMismatch() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(source: "unknown-src"), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .sourceMismatch)
        XCTAssertNil(snapshot.forecast)
    }

    func testFailedBacktestReturnsValidationFailedWithReasons() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makeFailingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .validationFailed)
        XCTAssertNil(snapshot.forecast)
        XCTAssertNotNil(snapshot.backtest)
        XCTAssertTrue(
            snapshot.message.contains("resolved_samples") || snapshot.message.contains("样本")
        )
    }

    func testProxySourceCapsConfidenceAtLow() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(source: "CZB-JCJ"), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.forecast?.sourceCompatibility, .proxy)
        XCTAssertLessThanOrEqual(snapshot.forecast?.confidence ?? .unavailable, .low)
    }

    func testVerifiedSourceAllowsElevatedConfidence() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(source: "JD-MS"), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.forecast?.sourceCompatibility, .verified)
        XCTAssertGreaterThanOrEqual(snapshot.forecast?.confidence ?? .unavailable, .medium)
        XCTAssertEqual(snapshot.forecast?.historySource, "JD-MS-history")
        XCTAssertEqual(
            snapshot.forecast?.targetDate,
            Calendar.goldShanghai.date(byAdding: .day, value: 7, to: now)
        )
    }

    // MARK: - sourceUnavailable 状态

    func testInvalidCurrentPriceIsSourceUnavailable() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        for price in [Double.nan, 0, 50, 5_000, .infinity] {
            let snapshot = await service.fetchSnapshot(
                request: makeRequest(price: price), language: .chinese
            )
            XCTAssertEqual(snapshot.status, .sourceUnavailable, "price \(price)")
            XCTAssertNil(snapshot.forecast)
        }
    }

    func testHistoryFetchFailureIsSourceUnavailable() async {
        let stub = HistoryProviderStub(error: StubError())
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .sourceUnavailable)
        XCTAssertNil(snapshot.forecast)
    }

    // MARK: - 事件只调整信心

    func testConflictingEventLowersConfidenceWithoutTouchingForecastNumbers() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let aligned = await service.fetchSnapshot(
            request: makeRequest(event: makeEvent(direction: .bullish)), language: .chinese
        )
        let conflicted = await service.fetchSnapshot(
            request: makeRequest(event: makeEvent(direction: .bearish)), language: .chinese
        )
        let alignedForecast = aligned.forecast
        let conflictedForecast = conflicted.forecast
        XCTAssertNotNil(alignedForecast)
        XCTAssertNotNil(conflictedForecast)
        XCTAssertEqual(alignedForecast?.direction, conflictedForecast?.direction)
        XCTAssertEqual(alignedForecast?.expectedReturn, conflictedForecast?.expectedReturn)
        XCTAssertEqual(alignedForecast?.p10, conflictedForecast?.p10)
        XCTAssertEqual(alignedForecast?.p50, conflictedForecast?.p50)
        XCTAssertEqual(alignedForecast?.p90, conflictedForecast?.p90)
        XCTAssertEqual(alignedForecast?.startPrice, conflictedForecast?.startPrice)
        XCTAssertGreaterThan(alignedForecast?.confidence ?? .unavailable,
                             conflictedForecast?.confidence ?? .unavailable)
        XCTAssertFalse(conflictedForecast?.counterRisks.isEmpty ?? true)
    }

    func testAlignedEventAddsReason() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let withoutEvent = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        let aligned = await service.fetchSnapshot(
            request: makeRequest(event: makeEvent(direction: .bullish)), language: .chinese
        )
        let baseReasonCount = withoutEvent.forecast?.reasons.count ?? 0
        XCTAssertGreaterThan(aligned.forecast?.reasons.count ?? 0, baseReasonCount)
        XCTAssertEqual(aligned.forecast?.direction, .up)
    }

    func testNonLiveEventDoesNotAdjustConfidence() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let baseline = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        let staleEvent = await service.fetchSnapshot(
            request: makeRequest(
                event: makeEvent(direction: .bearish, dataState: .stale)
            ), language: .chinese
        )
        let weakEvent = await service.fetchSnapshot(
            request: makeRequest(
                event: makeEvent(direction: .bearish, confidence: .low)
            ), language: .chinese
        )
        XCTAssertEqual(baseline.forecast?.confidence, staleEvent.forecast?.confidence)
        XCTAssertEqual(baseline.forecast?.confidence, weakEvent.forecast?.confidence)
    }

    func testAlignedEventCannotPromoteProxyAboveLow() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(
                source: "CZB-JCJ",
                event: makeEvent(direction: .bullish)
            ), language: .chinese
        )
        XCTAssertEqual(snapshot.forecast?.sourceCompatibility, .proxy)
        XCTAssertLessThanOrEqual(snapshot.forecast?.confidence ?? .unavailable, .low)
    }

    // MARK: - 缓存与并发

    func testConcurrentRequestsShareSingleHistoryFetch() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        async let first = service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        async let second = service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        let snapshots = await [first, second]
        let count = await stub.callCount
        XCTAssertEqual(count, 1)
        XCTAssertTrue(snapshots.allSatisfy { $0.status == .ready })
    }

    func testSequentialRequestsInsideSixHoursUseCache() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        _ = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        _ = await service.fetchSnapshot(
            request: makeRequest(price: 601), language: .chinese
        )
        let count = await stub.callCount
        XCTAssertEqual(count, 1)
    }

    func testCacheExpiresAfterSixHours() async {
        let stub = HistoryProviderStub(
            points: makeHistoryPoints(count: 260, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        _ = await service.fetchSnapshot(
            request: makeRequest(at: now), language: .chinese
        )
        let callsAfterFirst = await stub.callCount
        XCTAssertEqual(callsAfterFirst, 1)
        _ = await service.fetchSnapshot(
            request: makeRequest(at: now.addingTimeInterval(7 * 3600)), language: .chinese
        )
        let callsAfterExpiry = await stub.callCount
        XCTAssertEqual(callsAfterExpiry, 2)
    }

    // MARK: - Task 8：日历边界回归

    /// 记录引擎输入的线程安全盒子。
    private final class InputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var inputs: [GoldWeeklyForecastEngineInput] = []

        func append(_ input: GoldWeeklyForecastEngineInput) {
            lock.lock()
            defer { lock.unlock() }
            inputs.append(input)
        }

        var recorded: [GoldWeeklyForecastEngineInput] {
            lock.lock()
            defer { lock.unlock() }
            return inputs
        }
    }

    /// 覆盖月末、年末、闰年 2 月、周末和普通工作日：
    /// targetDate 必须是 generatedAt 的上海日历第 7 天。
    func testTargetDateIsSeventhShanghaiCalendarDayAcrossBoundaries() async {
        let calendar = Calendar.goldShanghai
        let boundaries: [(Date, Date)] = [
            // 月末：2026-01-31 → 2026-02-07
            (calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))!,
             calendar.date(from: DateComponents(year: 2026, month: 2, day: 7, hour: 12))!),
            // 年末：2026-12-31 → 2027-01-07
            (calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))!,
             calendar.date(from: DateComponents(year: 2027, month: 1, day: 7, hour: 12))!),
            // 闰年 2 月：2028-02-28 → 2028-03-06
            (calendar.date(from: DateComponents(year: 2028, month: 2, day: 28, hour: 12))!,
             calendar.date(from: DateComponents(year: 2028, month: 3, day: 6, hour: 12))!),
            // 周日：2026-08-30 → 2026-09-06
            (calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 12))!,
             calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!),
            // 周二：2026-09-01 → 2026-09-08
            (calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!,
             calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!)
        ]

        for (generatedAt, expectedTarget) in boundaries {
            let stub = HistoryProviderStub(
                points: makeHistoryPoints(count: 130, endingAt: generatedAt)
            )
            let box = InputBox()
            let fixedDraft = makeDraft()
            let service = GoldWeeklyForecastService(
                historyProvider: stub,
                modelRunner: GoldWeeklyForecastModelRunner(
                    makeDraft: { input in
                        box.append(input)
                        return fixedDraft
                    },
                    backtest: { _, _ in self.makePassingBacktest() }
                )
            )
            let snapshot = await service.fetchSnapshot(
                request: makeRequest(at: generatedAt), language: .chinese
            )
            XCTAssertEqual(snapshot.status, .ready)

            let inputs = box.recorded
            XCTAssertEqual(inputs.count, 1)
            let input = inputs[0]
            XCTAssertEqual(input.generatedAt, generatedAt)
            XCTAssertEqual(input.targetDate, expectedTarget)
            XCTAssertEqual(
                calendar.dateComponents([.day], from: input.generatedAt, to: input.targetDate).day,
                GoldWeeklyForecastPolicy.horizonDays
            )
        }
    }

    // MARK: - Task 8：数据故障矩阵

    func testEmptyHistoryIsInsufficientHistory() async {
        let stub = HistoryProviderStub(points: [])
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .insufficientHistory)
        XCTAssertTrue(snapshot.message.contains("0"))
        XCTAssertNil(snapshot.forecast)
    }

    func testAllOutlierHistoryIsInsufficientHistory() async {
        // 相邻日价格交替相差 20%（>8%），大部分点被剔除，剩余不足 120 个。
        let calendar = Calendar.goldShanghai
        let start = calendar.startOfDay(for: now)
        let points = (0..<130).map { index in
            GoldRemotePricePoint(
                price: index % 2 == 0 ? 500 : 600,
                timestamp: calendar.date(byAdding: .day, value: -index, to: start)!
            )
        }
        let stub = HistoryProviderStub(points: points)
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .insufficientHistory)
        XCTAssertNil(snapshot.forecast)
    }

    func testHistoryCountBoundariesAroundMinimum() async {
        for (count, expectedReady) in [(120, true), (119, false)] {
            let stub = HistoryProviderStub(
                points: makeHistoryPoints(count: count, endingAt: now)
            )
            let service = makeService(history: stub, backtest: makePassingBacktest())
            let snapshot = await service.fetchSnapshot(
                request: makeRequest(), language: .chinese
            )
            XCTAssertEqual(snapshot.status == .ready, expectedReady, "count \(count)")
        }
    }

    func testHistoryCountBoundariesAroundNormalDailyCloses() async {
        // 180 点且分量同向 → medium；179 点 → low。
        for (count, expectedConfidence) in [(180, GoldWeeklyForecastConfidence.medium),
                                            (179, GoldWeeklyForecastConfidence.low)] {
            let stub = HistoryProviderStub(
                points: makeHistoryPoints(count: count, endingAt: now)
            )
            let service = makeService(history: stub, backtest: makePassingBacktest())
            let snapshot = await service.fetchSnapshot(
                request: makeRequest(), language: .chinese
            )
            XCTAssertEqual(snapshot.status, .ready, "count \(count)")
            XCTAssertEqual(snapshot.forecast?.confidence, expectedConfidence, "count \(count)")
        }
    }

    func testHistoryCountBoundariesAroundHighDailyCloses() async {
        // 240 点且回测指标达标 → high；239 点 → medium。
        for (count, expectedConfidence) in [(240, GoldWeeklyForecastConfidence.high),
                                            (239, GoldWeeklyForecastConfidence.medium)] {
            let stub = HistoryProviderStub(
                points: makeHistoryPoints(count: count, endingAt: now)
            )
            let service = makeService(history: stub, backtest: makePassingBacktest())
            let snapshot = await service.fetchSnapshot(
                request: makeRequest(), language: .chinese
            )
            XCTAssertEqual(snapshot.status, .ready, "count \(count)")
            XCTAssertEqual(snapshot.forecast?.confidence, expectedConfidence, "count \(count)")
        }
    }

    func testStalenessBoundaryAtNinetySixHours() async {
        let calendar = Calendar.goldShanghai
        // 上海午夜作为 now，使 latestAge 与日历日对齐
        let nowMidnight = calendar.startOfDay(for: now)

        // 最新收盘在 95:59 前 → 不陈旧
        let fresh = HistoryProviderStub(
            points: makeHistoryPoints(
                count: 130, endingAt: nowMidnight.addingTimeInterval(-96 * 3600 + 60)
            )
        )
        let freshService = makeService(history: fresh, backtest: makePassingBacktest())
        let freshSnapshot = await freshService.fetchSnapshot(
            request: makeRequest(at: nowMidnight), language: .chinese
        )
        XCTAssertEqual(freshSnapshot.status, .ready)

        // 最新收盘在 96:01 后 → 陈旧
        let stale = HistoryProviderStub(
            points: makeHistoryPoints(
                count: 130, endingAt: nowMidnight.addingTimeInterval(-96 * 3600 - 60)
            )
        )
        let staleService = makeService(history: stale, backtest: makePassingBacktest())
        let staleSnapshot = await staleService.fetchSnapshot(
            request: makeRequest(at: nowMidnight), language: .chinese
        )
        XCTAssertEqual(staleSnapshot.status, .staleData)
        XCTAssertNil(staleSnapshot.forecast)
    }

    private func makeGapHistory(totalDays: Int, removedDays: Int, endingAt: Date) -> [GoldRemotePricePoint] {
        let calendar = Calendar.goldShanghai
        var offsets = Array(0..<totalDays)
        offsets.removeSubrange(11..<(11 + removedDays))
        return offsets.map { offset in
            let timestamp = calendar.date(byAdding: .day, value: offset - (totalDays - 1), to: endingAt)!
            return GoldRemotePricePoint(price: 580 + Double(offset) * 0.1, timestamp: timestamp)
        }
    }

    func testFifteenDayGapLowersConfidenceAndAddsCounterRisk() async {
        // 去掉 14 天 → 缺口 15 天 → 信心下调一级并追加对冲风险。
        let stub = HistoryProviderStub(
            points: makeGapHistory(totalDays: 200, removedDays: 14, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.forecast?.confidence, .low)
        XCTAssertTrue(snapshot.forecast?.counterRisks.contains { $0.contains("15") } ?? false)
    }

    func testFourteenDayGapDoesNotLowerConfidence() async {
        // 去掉 13 天 → 缺口 14 天 → 不触发降级。
        let stub = HistoryProviderStub(
            points: makeGapHistory(totalDays: 200, removedDays: 13, endingAt: now)
        )
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.forecast?.confidence, .medium)
        XCTAssertFalse(snapshot.forecast?.counterRisks.contains { $0.contains("14") } ?? true)
    }

    func testNonFiniteHistoryPricesAreRejected() async {
        var points = makeHistoryPoints(count: 260, endingAt: now)
        points[10] = GoldRemotePricePoint(price: .nan, timestamp: points[10].timestamp)
        points[20] = GoldRemotePricePoint(price: .infinity, timestamp: points[20].timestamp)
        let stub = HistoryProviderStub(points: points)
        let service = makeService(history: stub, backtest: makePassingBacktest())
        let snapshot = await service.fetchSnapshot(
            request: makeRequest(), language: .chinese
        )
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertTrue(snapshot.forecast?.expectedPrice.isFinite ?? false)
        XCTAssertTrue((snapshot.forecast?.p10.isFinite ?? false) && (snapshot.forecast?.p90.isFinite ?? false))
    }
}
