import XCTest
@testable import CoolRun

final class GoldSignalEngineTests: XCTestCase {
    func testStrongUptrendIsNotCancelledByOverboughtRSI() {
        let prices = (0..<40).map { 580.0 + Double($0) * 0.5 }
        let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: prices.last!)

        let signal = TradingSignalEngine.generateSignal(
            prices: prices,
            currentPrice: prices.last!,
            snapshot: snapshot
        )

        XCTAssertEqual(signal.direction, .buy)
        XCTAssertGreaterThanOrEqual(signal.score, 0.12)
    }

    func testStrongDowntrendIsNotCancelledByOversoldRSI() {
        let prices = (0..<40).map { 600.0 - Double($0) * 0.4 }
        let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: prices.last!)

        let signal = TradingSignalEngine.generateSignal(
            prices: prices,
            currentPrice: prices.last!,
            snapshot: snapshot
        )

        XCTAssertEqual(signal.direction, .sell)
        XCTAssertGreaterThanOrEqual(signal.score, 0.12)
    }

    func testAdvancedStrategyGivesPositiveGuidanceForClearUptrend() throws {
        let records = (0..<40).map {
            GoldPriceRecord(
                price: 580.0 + Double($0) * 0.5,
                timestamp: Date(timeIntervalSince1970: Double($0) * 60)
            )
        }
        let prices = records.map(\.price)
        let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: prices.last!)
        let signal = TradingSignalEngine.generateSignal(
            prices: prices,
            currentPrice: prices.last!,
            snapshot: snapshot
        )

        let report = try XCTUnwrap(GoldAdvancedStrategy.analyze(
            records: records,
            snapshot: snapshot,
            signal: signal
        ))

        XCTAssertEqual(report.compositeDirection, .buy)
        XCTAssertEqual(report.beginnerTone, .positive)
        XCTAssertGreaterThanOrEqual(report.risk.suggestedExposure, 0.06)
    }

    func testGoldNewsSentimentScoresBullishAndBearishKeywords() {
        let bullish = GoldMarketContextScorer.scoreNewsText("Fed rate cut hopes lift gold as yields fall")
        let bearish = GoldMarketContextScorer.scoreNewsText("Gold pressured as strong dollar and higher yields weigh")

        XCTAssertGreaterThan(bullish, 0)
        XCTAssertLessThan(bearish, 0)
    }

    func testMarketContextChangesSuggestedExposure() throws {
        let records = (0..<40).map {
            GoldPriceRecord(
                price: 580.0 + Double($0) * 0.5,
                timestamp: Date(timeIntervalSince1970: Double($0) * 60)
            )
        }
        let prices = records.map(\.price)
        let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: prices.last!)
        let signal = TradingSignalEngine.generateSignal(
            prices: prices,
            currentPrice: prices.last!,
            snapshot: snapshot
        )
        let bullishContext = GoldMarketContext(
            macroScore: 45,
            newsScore: 35,
            overallScore: 40,
            macro: nil,
            newsItems: [],
            reasons: ["宏观新闻偏多"],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let bearishContext = GoldMarketContext(
            macroScore: -45,
            newsScore: -35,
            overallScore: -40,
            macro: nil,
            newsItems: [],
            reasons: ["宏观新闻偏空"],
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let bullishReport = try XCTUnwrap(GoldAdvancedStrategy.analyze(
            records: records,
            snapshot: snapshot,
            signal: signal,
            marketContext: bullishContext
        ))
        let bearishReport = try XCTUnwrap(GoldAdvancedStrategy.analyze(
            records: records,
            snapshot: snapshot,
            signal: signal,
            marketContext: bearishContext
        ))

        XCTAssertGreaterThan(bullishReport.risk.suggestedExposure, bearishReport.risk.suggestedExposure)
        XCTAssertEqual(bullishReport.marketContext?.tone, .bullish)
        XCTAssertEqual(bearishReport.marketContext?.tone, .bearish)
    }

    // MARK: - 统一宏观状态源（单一快照写入 marketIntelligence / marketContext / globalSnapshot）

    @MainActor
    func testRefreshMarketIntelligenceWritesUnifiedState() async {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let impact = GoldEventImpact.make(
            direction: .bearish,
            confidence: .high,
            volatilityRisk: .elevated,
            headline: "短线偏空：政策与市场数据相互印证",
            evidence: [
                GoldEventEvidence(
                    id: "test-news",
                    kind: .centralBankStatement,
                    state: .observed,
                    direction: .bearish,
                    summary: "Fed rate hike odds rise",
                    source: "Reuters",
                    link: nil,
                    observedAt: now
                )
            ],
            counterRisks: [],
            updatedAt: now,
            dataState: .live,
            language: .chinese
        )
        let context = GoldMarketContext(
            macroScore: 10,
            newsScore: 10,
            overallScore: 10,
            macro: nil,
            newsItems: [],
            reasons: [],
            updatedAt: now
        )
        let global = GoldGlobalSnapshot(
            xauUsd: 4_454.52,
            xauPrevClose: 4_601.30,
            usdCny: 7.10,
            dollarIndex: 99.71,
            updatedAt: now
        )
        let snapshot = GoldMarketIntelligenceSnapshot(
            context: context,
            globalSnapshot: global,
            eventImpact: impact,
            updatedAt: now
        )
        let stub = GoldIntelligenceProviderStub(snapshot: snapshot)
        let viewModel = GoldAnalysisViewModel(marketIntelligenceService: stub)

        viewModel.refreshMarketIntelligence(records: [], candlePeriod: .minute5)
        await waitUntilIntelligenceIdle(viewModel)

        XCTAssertEqual(viewModel.marketIntelligence?.eventImpact, viewModel.eventImpact)
        XCTAssertEqual(viewModel.marketContext?.overallScore, snapshot.context.overallScore)
        XCTAssertEqual(viewModel.globalSnapshot?.xauUsd ?? 0, snapshot.globalSnapshot?.xauUsd ?? 0, accuracy: 0.001)
        XCTAssertFalse(viewModel.isMarketIntelligenceLoading)
    }

    @MainActor
    func testCancelResetsIntelligenceLoading() async {
        let stub = GoldIntelligenceProviderStub(snapshot: Self.makeUnavailableSnapshot())
        let viewModel = GoldAnalysisViewModel(marketIntelligenceService: stub)

        viewModel.refreshMarketIntelligence(records: [], candlePeriod: .minute5)
        viewModel.cancel()

        XCTAssertFalse(viewModel.isMarketIntelligenceLoading)
    }

    @MainActor
    func testLateIntelligenceTaskDoesNotOverwriteNewerSnapshot() async {
        let nowA = Date(timeIntervalSince1970: 1_788_000_000)
        let nowB = nowA.addingTimeInterval(600)
        let stub = GoldSlowIntelligenceProviderStub(
            firstSnapshot: Self.makeUnavailableSnapshot(updatedAt: nowA),
            secondSnapshot: Self.makeUnavailableSnapshot(updatedAt: nowB)
        )
        let viewModel = GoldAnalysisViewModel(marketIntelligenceService: stub)

        viewModel.refreshMarketIntelligence(records: [], candlePeriod: .minute5)
        await Task.yield()
        viewModel.refreshMarketIntelligence(records: [], candlePeriod: .minute5)
        await waitUntilIntelligenceIdle(viewModel)

        XCTAssertEqual(viewModel.marketIntelligence?.updatedAt, nowB, "应保留新快照")

        // 等旧任务 sleep 结束，确认迟到任务不回写旧数据
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(viewModel.marketIntelligence?.updatedAt, nowB, "迟到任务不得覆盖新快照")
    }

    private static func makeUnavailableSnapshot(updatedAt: Date = Date(timeIntervalSince1970: 1_788_000_000)) -> GoldMarketIntelligenceSnapshot {
        GoldMarketIntelligenceSnapshot(
            context: GoldMarketContext(
                macroScore: 0,
                newsScore: 0,
                overallScore: 0,
                macro: nil,
                newsItems: [],
                reasons: [],
                updatedAt: updatedAt
            ),
            globalSnapshot: nil,
            eventImpact: .unavailable(now: updatedAt, language: .chinese),
            updatedAt: updatedAt
        )
    }

    @MainActor
    private func waitUntilIntelligenceIdle(
        _ viewModel: GoldAnalysisViewModel,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while viewModel.isMarketIntelligenceLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// 事件影响解释不参与策略：相同 overallScore 必须得到相同策略输出，
    /// 证明 eventImpact 未被二次加权。
    func testEventImpactExplanationDoesNotChangeStrategyOutput() throws {
        let records = (0..<40).map {
            GoldPriceRecord(
                price: 580.0 + Double($0) * 0.5,
                timestamp: Date(timeIntervalSince1970: Double($0) * 60)
            )
        }
        let prices = records.map(\.price)
        let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: prices.last!)
        let signal = TradingSignalEngine.generateSignal(
            prices: prices,
            currentPrice: prices.last!,
            snapshot: snapshot
        )
        let contextA = GoldMarketContext(
            macroScore: 20,
            newsScore: 10,
            overallScore: 15,
            macro: nil,
            newsItems: [],
            reasons: ["宏观偏多"],
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        // 同 overallScore、不同证据构成（对应不同 eventImpact 解释）
        let contextB = GoldMarketContext(
            macroScore: -5,
            newsScore: 35,
            overallScore: 15,
            macro: nil,
            newsItems: [],
            reasons: ["新闻偏多但利率偏空"],
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let reportA = try XCTUnwrap(GoldAdvancedStrategy.analyze(
            records: records,
            snapshot: snapshot,
            signal: signal,
            marketContext: contextA
        ))
        let reportB = try XCTUnwrap(GoldAdvancedStrategy.analyze(
            records: records,
            snapshot: snapshot,
            signal: signal,
            marketContext: contextB
        ))

        XCTAssertEqual(reportA.compositeDirection, reportB.compositeDirection)
        XCTAssertEqual(reportA.risk.suggestedExposure, reportB.risk.suggestedExposure, accuracy: 0.000_001)
    }

    func testPredictionLearningValidatesMaturedBuyPrediction() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let prediction = GoldPredictionLearningRecord(
            createdAt: createdAt,
            horizonSeconds: 30 * 60,
            startPrice: 600,
            predictedDirection: "buy",
            predictedReturn: 0.004,
            confidence: 0.5,
            suggestedExposure: 0.12,
            technicalOpportunity: 28,
            marketContextScore: 20,
            macroScore: 10,
            newsScore: 30,
            regime: "温和上涨",
            sourceSummary: "测试预测"
        )
        let prices = [
            GoldPriceRecord(price: 600, timestamp: createdAt),
            GoldPriceRecord(price: 604, timestamp: createdAt.addingTimeInterval(30 * 60 + 5))
        ]

        let validated = GoldPredictionLearningEngine.validate(records: prices, prediction: prediction)

        XCTAssertEqual(validated.status, .validated)
        XCTAssertEqual(validated.wasDirectionalHit, true)
        XCTAssertEqual(validated.actualReturn ?? 0, 4 / 600, accuracy: 0.000_001)
        XCTAssertEqual(validated.absoluteError ?? 0, abs(0.004 - 4 / 600), accuracy: 0.000_001)
    }

    func testPredictionLearningSummaryTracksHitRateAndBias() {
        let first = GoldPredictionLearningRecord(
            createdAt: Date(timeIntervalSince1970: 1),
            horizonSeconds: 1,
            startPrice: 600,
            predictedDirection: "buy",
            predictedReturn: 0.004,
            confidence: 0.5,
            suggestedExposure: 0.1,
            technicalOpportunity: 20,
            marketContextScore: nil,
            macroScore: nil,
            newsScore: nil,
            regime: "温和上涨",
            sourceSummary: "测试",
            status: .validated,
            resolvedAt: Date(timeIntervalSince1970: 2),
            endPrice: 604,
            actualReturn: 0.006,
            wasDirectionalHit: true,
            absoluteError: 0.002
        )
        let second = GoldPredictionLearningRecord(
            createdAt: Date(timeIntervalSince1970: 3),
            horizonSeconds: 1,
            startPrice: 604,
            predictedDirection: "sell",
            predictedReturn: -0.003,
            confidence: 0.4,
            suggestedExposure: 0.08,
            technicalOpportunity: -15,
            marketContextScore: nil,
            macroScore: nil,
            newsScore: nil,
            regime: "温和下跌",
            sourceSummary: "测试",
            status: .validated,
            resolvedAt: Date(timeIntervalSince1970: 4),
            endPrice: 606,
            actualReturn: 0.003,
            wasDirectionalHit: false,
            absoluteError: 0.006
        )

        let summary = GoldPredictionLearningEngine.makeSummary(records: [first, second])

        XCTAssertEqual(summary.validatedCount, 2)
        XCTAssertEqual(summary.pendingCount, 0)
        XCTAssertEqual(summary.hitRate ?? 0, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(summary.averageAbsoluteError ?? 0, 0.004, accuracy: 0.000_001)
        XCTAssertEqual(summary.averagePredictionBias ?? 0, -0.004, accuracy: 0.000_001)
    }
}

// MARK: - 统一宏观情报 Stub

private actor GoldIntelligenceProviderStub: GoldMarketIntelligenceProviding {
    let snapshot: GoldMarketIntelligenceSnapshot
    private(set) var callCount = 0

    init(snapshot: GoldMarketIntelligenceSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshot(now: Date, language: AppLanguage) async -> GoldMarketIntelligenceSnapshot {
        callCount += 1
        return snapshot
    }
}

/// 第一次调用 sleep 后返回 firstSnapshot，之后立即返回 secondSnapshot。
private actor GoldSlowIntelligenceProviderStub: GoldMarketIntelligenceProviding {
    let firstSnapshot: GoldMarketIntelligenceSnapshot
    let secondSnapshot: GoldMarketIntelligenceSnapshot
    private(set) var callCount = 0

    init(firstSnapshot: GoldMarketIntelligenceSnapshot, secondSnapshot: GoldMarketIntelligenceSnapshot) {
        self.firstSnapshot = firstSnapshot
        self.secondSnapshot = secondSnapshot
    }

    func fetchSnapshot(now: Date, language: AppLanguage) async -> GoldMarketIntelligenceSnapshot {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            return firstSnapshot
        }
        return secondSnapshot
    }
}
