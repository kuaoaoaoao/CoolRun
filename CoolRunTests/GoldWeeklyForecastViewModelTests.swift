import XCTest
@testable import CoolRun

@MainActor
final class GoldWeeklyForecastViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTemporaryStore() -> GoldWeeklyForecastStore {
        GoldWeeklyForecastStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("weekly-forecast-vm-\(UUID().uuidString).json")
        )
    }

    private func makeReadySnapshot(
        generatedAt: Date,
        startPrice: Double,
        source: String = "JD-MS"
    ) -> GoldWeeklyForecastSnapshot {
        let target = Calendar.goldShanghai.date(byAdding: .day, value: 7, to: generatedAt)!
        let forecast = GoldWeeklyForecast(
            direction: .up,
            confidence: .low,
            startPrice: startPrice,
            expectedPrice: startPrice * 1.01,
            expectedReturn: 0.01,
            p10: startPrice * 0.98,
            p50: startPrice * 1.01,
            p90: startPrice * 1.04,
            generatedAt: generatedAt,
            targetDate: target,
            dataUpdatedAt: generatedAt,
            currentPriceSource: source,
            historySource: GoldMarketDataService.historySourceID,
            sourceCompatibility: source == "CZB-JCJ" ? .proxy : .verified,
            components: GoldWeeklyForecastComponents(
                trend: 0.4, momentum: 0.3, meanReversion: -0.1, bootstrap: 0.3, composite: 0.275
            ),
            reasons: ["fixture"],
            counterRisks: [],
            modelVersion: GoldWeeklyForecastPolicy.modelVersion
        )
        return GoldWeeklyForecastSnapshot(
            status: .ready,
            forecast: forecast,
            backtest: GoldWeeklyForecastBacktestSummary(
                resolvedCount: 30,
                classCounts: [.up: 10, .flat: 10, .down: 10],
                overallAccuracy: 0.50,
                balancedAccuracy: 0.50,
                majorityBaselineAccuracy: 1.0 / 3.0,
                meanAbsoluteReturnError: 0.01,
                confusionMatrix: [:],
                passedReleaseGate: true,
                failureReasons: []
            ),
            message: "ready",
            updatedAt: generatedAt
        )
    }

    private func makeRecords(price: Double, source: String = "JD-MS") -> [GoldPriceRecord] {
        [
            GoldPriceRecord(
                price: price,
                timestamp: Date(timeIntervalSince1970: 1_788_000_000),
                source: source
            )
        ]
    }

    /// 轮询等待条件成立，超时失败。
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "等待条件超时")
    }

    // MARK: - 服务 stub

    private actor ServiceStub: GoldWeeklyForecastProviding {
        private(set) var requests: [GoldWeeklyForecastRequest] = []
        private let respond: @Sendable (GoldWeeklyForecastRequest) async -> GoldWeeklyForecastSnapshot

        init(respond: @escaping @Sendable (GoldWeeklyForecastRequest) async -> GoldWeeklyForecastSnapshot) {
            self.respond = respond
        }

        func fetchSnapshot(
            request: GoldWeeklyForecastRequest,
            language: AppLanguage
        ) async -> GoldWeeklyForecastSnapshot {
            requests.append(request)
            return await respond(request)
        }
    }

    // MARK: - 当天已有正式记录：不调用 service

    func testFrozenRecordSkipsServiceAndRestoresSnapshot() async throws {
        let store = makeTemporaryStore()
        // 当天已冻结的正式记录（generatedAt 为今天）
        let generatedAt = Date()
        store.observe(snapshot: makeReadySnapshot(generatedAt: generatedAt, startPrice: 600))

        let service = ServiceStub { _ in
            XCTFail("当天已有正式记录时不应调用 service")
            return .unavailable(status: .sourceUnavailable, message: "unreachable", now: Date())
        }
        let viewModel = GoldAnalysisViewModel(
            weeklyForecastService: service,
            weeklyForecastStore: store
        )

        viewModel.refreshWeeklyForecast(records: makeRecords(price: 610), eventImpact: nil)

        let requestCount = await service.requests.count
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(viewModel.weeklyForecastSnapshot?.status, .ready)
        XCTAssertEqual(viewModel.weeklyForecastSnapshot?.forecast?.startPrice, 600)
        XCTAssertEqual(viewModel.weeklyForecastSnapshot?.updatedAt, generatedAt)
        XCTAssertFalse(viewModel.isWeeklyForecastLoading)
    }

    // MARK: - 当天无记录：调用一次 service 并写 Store

    func testReadySnapshotIsObservedIntoStore() async throws {
        let store = makeTemporaryStore()
        let snapshot = makeReadySnapshot(generatedAt: Date(timeIntervalSince1970: 1_788_000_000), startPrice: 600)
        let service = ServiceStub { _ in snapshot }
        let viewModel = GoldAnalysisViewModel(
            weeklyForecastService: service,
            weeklyForecastStore: store
        )

        viewModel.refreshWeeklyForecast(records: makeRecords(price: 600), eventImpact: nil)
        await waitUntil { viewModel.weeklyForecastSnapshot != nil }

        let requestCount = await service.requests.count
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(viewModel.weeklyForecastSnapshot?.status, .ready)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.forecast.startPrice, 600)
        XCTAssertFalse(viewModel.isWeeklyForecastLoading)
    }

    func testRequestCarriesLastPriceSourceAndEventImpact() async throws {
        let store = makeTemporaryStore()
        let snapshot = makeReadySnapshot(generatedAt: Date(), startPrice: 600)
        let service = ServiceStub { _ in snapshot }
        let viewModel = GoldAnalysisViewModel(
            weeklyForecastService: service,
            weeklyForecastStore: store
        )
        let event = GoldEventImpact(
            direction: .bullish,
            confidence: .high,
            volatilityRisk: .normal,
            headline: "fixture",
            evidence: [],
            counterRisks: [],
            updatedAt: Date(),
            dataState: .live
        )

        viewModel.refreshWeeklyForecast(records: makeRecords(price: 612, source: "JD-MS"), eventImpact: event)
        await waitUntil { viewModel.weeklyForecastSnapshot != nil }

        let requests = await service.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.currentPrice, 612)
        XCTAssertEqual(requests.first?.currentPriceSource, "JD-MS")
        XCTAssertEqual(requests.first?.eventImpact?.direction, .bullish)
    }

    // MARK: - 取消与迟到结果

    func testNewRefreshCancelsLateResult() async throws {
        let store = makeTemporaryStore()
        // 价格 600 → 慢响应；价格 610 → 快响应
        let slowSnapshot = makeReadySnapshot(generatedAt: Date().addingTimeInterval(-100), startPrice: 600)
        let fastSnapshot = makeReadySnapshot(generatedAt: Date(), startPrice: 610)
        let service = ServiceStub { request in
            if request.currentPrice == 600 {
                try? await Task.sleep(for: .milliseconds(400))
                return slowSnapshot
            }
            return fastSnapshot
        }
        let viewModel = GoldAnalysisViewModel(
            weeklyForecastService: service,
            weeklyForecastStore: store
        )

        viewModel.refreshWeeklyForecast(records: makeRecords(price: 600), eventImpact: nil)
        try await Task.sleep(for: .milliseconds(50))
        viewModel.refreshWeeklyForecast(records: makeRecords(price: 610), eventImpact: nil)
        await waitUntil { viewModel.weeklyForecastSnapshot != nil }

        // 等慢任务彻底结束，确认迟到结果未覆盖快照
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(viewModel.weeklyForecastSnapshot?.forecast?.startPrice, 610)
        // Store 只冻结当天第一条 ready 预测
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.forecast.startPrice, 610)
    }

    func testCancelResetsLoadingAndRejectsLateResult() async throws {
        let store = makeTemporaryStore()
        let snapshot = makeReadySnapshot(generatedAt: Date(), startPrice: 600)
        let stream = AsyncStream<Void> { continuation in
            Task.detached {
                try? await Task.sleep(for: .milliseconds(300))
                continuation.yield(())
                continuation.finish()
            }
        }
        let box = StreamBox(stream)
        let service = ServiceStub { _ in
            for await _ in box.stream {
                return snapshot
            }
            return snapshot
        }
        let viewModel = GoldAnalysisViewModel(
            weeklyForecastService: service,
            weeklyForecastStore: store
        )

        viewModel.refreshWeeklyForecast(records: makeRecords(price: 600), eventImpact: nil)
        XCTAssertTrue(viewModel.isWeeklyForecastLoading)

        viewModel.cancel()
        XCTAssertFalse(viewModel.isWeeklyForecastLoading)

        // 迟到结果不能覆盖快照
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(viewModel.weeklyForecastSnapshot)
    }

    // MARK: - 本地验证

    func testRefreshValidatesPendingRecordsWithLocalPrices() async throws {
        let store = makeTemporaryStore()
        let generatedAt = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(generatedAt: generatedAt, startPrice: 600, source: "JD-MS"))
        let target = Calendar.goldShanghai.date(byAdding: .day, value: 7, to: generatedAt)!

        let frozenService = ServiceStub { _ in
            .unavailable(status: .sourceUnavailable, message: "unreachable", now: Date())
        }
        let viewModel = GoldAnalysisViewModel(
            weeklyForecastService: frozenService,
            weeklyForecastStore: store
        )

        // 当天已有记录（次日刷新），本地 records 含目标日价格 → 应被验证
        viewModel.refreshWeeklyForecast(
            records: [GoldPriceRecord(price: 620, timestamp: target, source: "JD-MS")],
            eventImpact: nil
        )

        XCTAssertEqual(store.records.first?.status, .validated)
        XCTAssertEqual(store.records.first?.endPrice, 620)
    }

    func testNoValidPriceSetsUnavailableWithoutCallingService() async throws {
        let store = makeTemporaryStore()
        let service = ServiceStub { _ in
            XCTFail("无有效价格时不应调用 service")
            return .unavailable(status: .sourceUnavailable, message: "unreachable", now: Date())
        }
        let viewModel = GoldAnalysisViewModel(
            weeklyForecastService: service,
            weeklyForecastStore: store
        )

        viewModel.refreshWeeklyForecast(records: [], eventImpact: nil)

        XCTAssertEqual(viewModel.weeklyForecastSnapshot?.status, .sourceUnavailable)
        XCTAssertFalse(viewModel.isWeeklyForecastLoading)
        let requestCount = await service.requests.count
        XCTAssertEqual(requestCount, 0)
    }
}

/// 让 actor 内持有 AsyncStream 以便 await。
private final class StreamBox: @unchecked Sendable {
    let stream: AsyncStream<Void>
    init(_ stream: AsyncStream<Void>) {
        self.stream = stream
    }
}
