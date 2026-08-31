import XCTest
@testable import CoolRun

final class GoldWeeklyForecastStoreTests: XCTestCase {

    // MARK: - Fixtures

    @MainActor
    private func makeTemporaryStore() -> GoldWeeklyForecastStore {
        GoldWeeklyForecastStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("weekly-forecast-\(UUID().uuidString).json")
        )
    }

    @MainActor
    private func makeReadySnapshot(
        generatedAt: Date,
        startPrice: Double,
        currentSource: String = "JD-MS",
        direction: GoldWeeklyForecastDirection = .up,
        modelVersion: String = GoldWeeklyForecastPolicy.modelVersion
    ) -> GoldWeeklyForecastSnapshot {
        let target = Calendar.goldShanghai.date(byAdding: .day, value: 7, to: generatedAt)!
        let backtest = GoldWeeklyForecastBacktestSummary(
            resolvedCount: 30,
            classCounts: [.up: 10, .flat: 10, .down: 10],
            overallAccuracy: 0.50,
            balancedAccuracy: 0.50,
            majorityBaselineAccuracy: 1.0 / 3.0,
            meanAbsoluteReturnError: 0.01,
            confusionMatrix: [
                .up: [.up: 5, .flat: 3, .down: 2],
                .flat: [.up: 2, .flat: 5, .down: 3],
                .down: [.up: 2, .flat: 3, .down: 5]
            ],
            passedReleaseGate: true,
            failureReasons: []
        )
        let forecast = GoldWeeklyForecast(
            direction: direction,
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
            currentPriceSource: currentSource,
            historySource: GoldMarketDataService.historySourceID,
            sourceCompatibility: currentSource == "CZB-JCJ" ? .proxy : .verified,
            components: GoldWeeklyForecastComponents(
                trend: 0.4, momentum: 0.3, meanReversion: -0.1,
                bootstrap: 0.3, composite: 0.275
            ),
            reasons: ["fixture"],
            counterRisks: [],
            modelVersion: modelVersion
        )
        return GoldWeeklyForecastSnapshot(
            status: .ready,
            forecast: forecast,
            backtest: backtest,
            message: "ready",
            updatedAt: generatedAt
        )
    }

    private func makeLearningRecord(
        status: GoldPredictionLearningRecord.Status,
        hit: Bool? = nil
    ) -> GoldPredictionLearningRecord {
        let createdAt = Date(timeIntervalSince1970: 1_788_000_000)
        return GoldPredictionLearningRecord(
            id: UUID(),
            createdAt: createdAt,
            horizonSeconds: 1800,
            startPrice: 600,
            predictedDirection: "up",
            predictedReturn: 0.01,
            confidence: 0.6,
            suggestedExposure: 0.5,
            technicalOpportunity: 0.4,
            marketContextScore: 0.5,
            macroScore: 0.2,
            newsScore: 0.1,
            strategyVersion: "fixture",
            regime: "trending",
            sourceSummary: "fixture",
            status: status,
            resolvedAt: status == .validated ? createdAt.addingTimeInterval(1800) : nil,
            endPrice: status == .validated ? 606 : nil,
            actualReturn: status == .validated ? 0.01 : nil,
            wasDirectionalHit: hit,
            absoluteError: status == .validated ? 0.0 : nil
        )
    }

    // MARK: - 每日冻结

    @MainActor
    func testSameShanghaiDayAndModelKeepsFirstReadyForecast() throws {
        let store = makeTemporaryStore()
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(generatedAt: day, startPrice: 600))
        store.observe(snapshot: makeReadySnapshot(generatedAt: day.addingTimeInterval(3600), startPrice: 610))
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.forecast.startPrice, 600)
    }

    @MainActor
    func testNextShanghaiDayCreatesAnotherRecord() throws {
        let store = makeTemporaryStore()
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(generatedAt: day, startPrice: 600))
        store.observe(snapshot: makeReadySnapshot(generatedAt: day.addingTimeInterval(24 * 3600), startPrice: 601))
        XCTAssertEqual(store.records.count, 2)
    }

    @MainActor
    func testDifferentModelVersionCreatesAnotherRecord() throws {
        let store = makeTemporaryStore()
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(generatedAt: day, startPrice: 600))
        store.observe(snapshot: makeReadySnapshot(
            generatedAt: day, startPrice: 610, modelVersion: "gold-weekly-fixture.2"
        ))
        XCTAssertEqual(store.records.count, 2)
    }

    @MainActor
    func testNonReadySnapshotIsNotObserved() throws {
        let store = makeTemporaryStore()
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: .unavailable(status: .insufficientHistory, message: "历史不足", now: day))
        store.observe(snapshot: GoldWeeklyForecastSnapshot(
            status: .validationFailed,
            forecast: nil,
            backtest: nil,
            message: "fixture",
            updatedAt: day
        ))
        XCTAssertTrue(store.records.isEmpty)
    }

    // MARK: - 7 天验证

    @MainActor
    func testValidationUsesFirstCompatiblePriceOnOrAfterDaySeven() throws {
        let store = makeTemporaryStore()
        let createdAt = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(
            generatedAt: createdAt, startPrice: 600, currentSource: "CZB-JCJ"
        ))
        let target = Calendar.goldShanghai.date(byAdding: .day, value: 7, to: createdAt)!
        let prices = [
            GoldPriceRecord(price: 620, timestamp: target.addingTimeInterval(-1), source: "CZB-JCJ"),
            GoldPriceRecord(price: 630, timestamp: target, source: "JD-MS"),
            GoldPriceRecord(price: 606, timestamp: target.addingTimeInterval(60), source: "CZB-JCJ")
        ]
        store.validate(with: prices, now: target.addingTimeInterval(120))
        XCTAssertEqual(store.records.first?.endPrice, 606)
        XCTAssertEqual(store.records.first?.actualDirection, .up)
        XCTAssertEqual(store.records.first?.status, .validated)
        XCTAssertEqual(store.records.first?.wasDirectionalHit, true)
        XCTAssertEqual(store.summary.validatedCount, 1)
    }

    @MainActor
    func testMissingOutcomeAfterGraceExpiresRecord() throws {
        let store = makeTemporaryStore()
        let createdAt = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(generatedAt: createdAt, startPrice: 600))
        let afterDeadline = Calendar.goldShanghai.date(byAdding: .day, value: 11, to: createdAt)!
        store.validate(with: [], now: afterDeadline)
        XCTAssertEqual(store.records.first?.status, .expired)
        XCTAssertEqual(store.summary.expiredCount, 1)
    }

    @MainActor
    func testPendingRecordBeforeDeadlineStaysPending() throws {
        let store = makeTemporaryStore()
        let createdAt = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(generatedAt: createdAt, startPrice: 600))
        let beforeDeadline = Calendar.goldShanghai.date(byAdding: .day, value: 9, to: createdAt)!
        store.validate(with: [], now: beforeDeadline)
        XCTAssertEqual(store.records.first?.status, .pending)
    }

    // MARK: - 与 30 分钟学习隔离

    @MainActor
    func testWeeklyStoreDoesNotAffectThirtyMinuteLearningSummary() throws {
        let learningRecords = [
            makeLearningRecord(status: .validated, hit: true),
            makeLearningRecord(status: .pending)
        ]
        let before = GoldPredictionLearningEngine.makeSummary(records: learningRecords)
        let store = makeTemporaryStore()
        let createdAt = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(generatedAt: createdAt, startPrice: 600))
        let target = Calendar.goldShanghai.date(byAdding: .day, value: 7, to: createdAt)!
        store.validate(
            with: [GoldPriceRecord(price: 620, timestamp: target, source: "JD-MS")],
            now: target.addingTimeInterval(60)
        )
        let after = GoldPredictionLearningEngine.makeSummary(records: learningRecords)
        XCTAssertEqual(before, after)
        XCTAssertEqual(store.summary.totalCount, 1)
    }

    // MARK: - 持久化与合并

    @MainActor
    func testRecordsPersistAcrossStoreInstances() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-forecast-\(UUID().uuidString).json")
        let first = GoldWeeklyForecastStore(fileURL: fileURL)
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        first.observe(snapshot: makeReadySnapshot(generatedAt: day, startPrice: 600))
        XCTAssertEqual(first.records.count, 1)

        let reloaded = GoldWeeklyForecastStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records.first?.forecast.startPrice, 600)
        XCTAssertEqual(reloaded.summary.totalCount, 1)
    }

    @MainActor
    func testMergeKeepsExistingRecordsAndAddsOnlyNewIdentifiers() throws {
        let store = makeTemporaryStore()
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        let existing = makeReadySnapshot(generatedAt: day, startPrice: 600)
        store.observe(snapshot: existing)
        let existingRecord = try XCTUnwrap(store.records.first)

        var duplicate = existingRecord
        var nextDayForecast = existingRecord.forecast
        nextDayForecast = GoldWeeklyForecast(
            direction: nextDayForecast.direction,
            confidence: nextDayForecast.confidence,
            startPrice: 620,
            expectedPrice: nextDayForecast.expectedPrice,
            expectedReturn: nextDayForecast.expectedReturn,
            p10: nextDayForecast.p10,
            p50: nextDayForecast.p50,
            p90: nextDayForecast.p90,
            generatedAt: day.addingTimeInterval(24 * 3600),
            targetDate: Calendar.goldShanghai.date(byAdding: .day, value: 7, to: day.addingTimeInterval(24 * 3600))!,
            dataUpdatedAt: nextDayForecast.dataUpdatedAt,
            currentPriceSource: nextDayForecast.currentPriceSource,
            historySource: nextDayForecast.historySource,
            sourceCompatibility: nextDayForecast.sourceCompatibility,
            components: nextDayForecast.components,
            reasons: nextDayForecast.reasons,
            counterRisks: nextDayForecast.counterRisks,
            modelVersion: nextDayForecast.modelVersion
        )
        duplicate = GoldWeeklyForecastRecord(
            id: duplicate.id,
            forecast: nextDayForecast,
            backtest: duplicate.backtest,
            status: .validated,
            resolvedAt: nil,
            endPrice: nil,
            actualReturn: nil,
            actualDirection: nil,
            wasDirectionalHit: nil,
            absoluteReturnError: nil
        )
        let newRecord = GoldWeeklyForecastRecord(
            id: UUID(),
            forecast: nextDayForecast,
            backtest: existingRecord.backtest,
            status: .pending,
            resolvedAt: nil,
            endPrice: nil,
            actualReturn: nil,
            actualDirection: nil,
            wasDirectionalHit: nil,
            absoluteReturnError: nil
        )

        store.merge([duplicate, newRecord, newRecord])
        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(store.records.first?.forecast.startPrice, 600)
        XCTAssertEqual(store.records.first?.status, .pending)
        XCTAssertEqual(store.records.count(where: { $0.status == .pending }), 2)
    }

    @MainActor
    func testFrozenSnapshotRestoresReadySnapshotFromRecord() throws {
        let store = makeTemporaryStore()
        let day = Date(timeIntervalSince1970: 1_788_000_000)
        store.observe(snapshot: makeReadySnapshot(generatedAt: day, startPrice: 600))
        let record = try XCTUnwrap(store.records.first)
        let frozen = record.frozenSnapshot(message: "frozen")
        XCTAssertEqual(frozen.status, .ready)
        XCTAssertEqual(frozen.forecast, record.forecast)
        XCTAssertEqual(frozen.backtest, record.backtest)
        XCTAssertEqual(frozen.updatedAt, record.forecast.generatedAt)
    }

    // MARK: - 来源验证解析

    func testCanValidateResolverRules() {
        XCTAssertTrue(GoldForecastSourceCompatibilityResolver.canValidate(
            forecastSource: "CZB-JCJ", outcomeSource: "CZB-JCJ"))
        XCTAssertTrue(GoldForecastSourceCompatibilityResolver.canValidate(
            forecastSource: "JD-MS", outcomeSource: "JD-MS"))
        XCTAssertTrue(GoldForecastSourceCompatibilityResolver.canValidate(
            forecastSource: "JD-MS", outcomeSource: "JD-official"))
        XCTAssertTrue(GoldForecastSourceCompatibilityResolver.canValidate(
            forecastSource: "JD-official", outcomeSource: "JD-MS"))
        XCTAssertFalse(GoldForecastSourceCompatibilityResolver.canValidate(
            forecastSource: "CZB-JCJ", outcomeSource: "JD-MS"))
        XCTAssertFalse(GoldForecastSourceCompatibilityResolver.canValidate(
            forecastSource: "JD-MS", outcomeSource: "CZB-JCJ"))
        XCTAssertFalse(GoldForecastSourceCompatibilityResolver.canValidate(
            forecastSource: "JD-MS", outcomeSource: "unknown-src"))
        XCTAssertFalse(GoldForecastSourceCompatibilityResolver.canValidate(
            forecastSource: "unknown-src", outcomeSource: "JD-MS"))
    }
}
