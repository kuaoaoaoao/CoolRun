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
}
