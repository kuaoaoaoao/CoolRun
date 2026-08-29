import XCTest
@testable import CoolRun

final class GoldMarketIntelligenceServiceTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_788_000_000)

    private func makeContext(news: [GoldNewsItem] = []) -> GoldMarketContext {
        GoldMarketContext(
            macroScore: 10,
            newsScore: 10,
            overallScore: 10,
            macro: GoldMacroSnapshot(
                tenYearYield: 4.5,
                tenYearYieldChangeBps: 3,
                observedAt: fixedNow
            ),
            newsItems: news,
            reasons: [],
            updatedAt: fixedNow,
            isPartial: false,
            missingDataDescription: nil,
            isFromCache: false
        )
    }

    private func makeGlobal() -> GoldGlobalSnapshot {
        GoldGlobalSnapshot(
            xauUsd: 4_454.52,
            xauPrevClose: 4_601.30,
            usdCny: 7.10,
            dollarIndex: 99.71,
            updatedAt: fixedNow
        )
    }

    private func hawkishNews(now: Date) -> GoldNewsItem {
        GoldNewsItem(
            title: "Fed rate hike odds rise as gold price falls - Reuters",
            source: "Reuters",
            link: nil,
            publishedAt: now,
            sentimentScore: -36
        )
    }

    // MARK: - 场景 1：两个数据源都成功

    func testBothSourcesSucceedReturnsContextAndEventImpact() async {
        let contextStub = GoldContextProviderStub(result: .success(makeContext(news: [hawkishNews(now: fixedNow)])))
        let globalStub = GoldGlobalProviderStub(result: .success(makeGlobal()))
        let service = GoldMarketIntelligenceService(
            contextProvider: contextStub,
            globalProvider: globalStub
        )

        let snapshot = await service.fetchSnapshot(now: fixedNow, language: .chinese)

        XCTAssertEqual(await contextStub.callCount, 1)
        XCTAssertEqual(await globalStub.callCount, 1)
        XCTAssertEqual(snapshot.context.overallScore, 10)
        XCTAssertEqual(snapshot.eventImpact.dataState, .live)
        XCTAssertEqual(snapshot.globalSnapshot?.xauUsd ?? 0, 4_454.52, accuracy: 0.001)
        XCTAssertNotEqual(snapshot.eventImpact.direction, .neutral)
    }

    // MARK: - 场景 2：global 失败 => partial

    func testGlobalFailureDowngradesToPartial() async {
        let contextStub = GoldContextProviderStub(result: .success(makeContext(news: [hawkishNews(now: fixedNow)])))
        let globalStub = GoldGlobalProviderStub(result: .failure(URLError(.notConnectedToInternet)))
        let service = GoldMarketIntelligenceService(
            contextProvider: contextStub,
            globalProvider: globalStub
        )

        let snapshot = await service.fetchSnapshot(now: fixedNow, language: .chinese)

        XCTAssertEqual(snapshot.eventImpact.dataState, .partial)
        XCTAssertNil(snapshot.globalSnapshot)
        XCTAssertEqual(snapshot.context.overallScore, 10)
    }

    // MARK: - 场景 3：context 抛错 => 安全不可用快照

    func testContextFailureFailsClosed() async {
        let contextStub = GoldContextProviderStub(result: .failure(URLError(.notConnectedToInternet)))
        let globalStub = GoldGlobalProviderStub(result: .success(makeGlobal()))
        let service = GoldMarketIntelligenceService(
            contextProvider: contextStub,
            globalProvider: globalStub
        )

        let snapshot = await service.fetchSnapshot(now: fixedNow, language: .chinese)

        XCTAssertEqual(snapshot.eventImpact.dataState, .unavailable)
        XCTAssertEqual(snapshot.eventImpact.direction, .neutral)
        XCTAssertTrue(snapshot.eventImpact.evidence.isEmpty)
        XCTAssertEqual(snapshot.context.overallScore, 0)
    }

    // MARK: - 场景 4：并发合并

    func testConcurrentCallsShareSingleUnderlyingFetch() async {
        let contextStub = GoldContextProviderStub(result: .success(makeContext(news: [hawkishNews(now: fixedNow)])))
        let globalStub = GoldGlobalProviderStub(result: .success(makeGlobal()))
        let service = GoldMarketIntelligenceService(
            contextProvider: contextStub,
            globalProvider: globalStub
        )

        async let first = service.fetchSnapshot(now: fixedNow, language: .chinese)
        async let second = service.fetchSnapshot(now: fixedNow, language: .chinese)
        let snapshots = await [first, second]

        XCTAssertEqual(await contextStub.callCount, 1, "in-flight 合并后底层 context 只调用一次")
        XCTAssertEqual(await globalStub.callCount, 1, "in-flight 合并后底层 global 只调用一次")
        XCTAssertEqual(snapshots.count, 2)
    }

    // MARK: - 缓存边界（Task 8 会扩展）

    func testFreshCacheWithin15MinutesDoesNotRefetch() async {
        let contextStub = GoldContextProviderStub(result: .success(makeContext(news: [hawkishNews(now: fixedNow)])))
        let globalStub = GoldGlobalProviderStub(result: .success(makeGlobal()))
        let service = GoldMarketIntelligenceService(
            contextProvider: contextStub,
            globalProvider: globalStub
        )

        _ = await service.fetchSnapshot(now: fixedNow, language: .chinese)
        // 14 分 59 秒后：缓存命中，不重新拉取
        _ = await service.fetchSnapshot(
            now: fixedNow.addingTimeInterval(14 * 60 + 59),
            language: .chinese
        )

        XCTAssertEqual(await contextStub.callCount, 1)
        XCTAssertEqual(await globalStub.callCount, 1)
    }

    func testCacheOlderThan15MinutesRefetches() async {
        let contextStub = GoldContextProviderStub(result: .success(makeContext(news: [hawkishNews(now: fixedNow)])))
        let globalStub = GoldGlobalProviderStub(result: .success(makeGlobal()))
        let service = GoldMarketIntelligenceService(
            contextProvider: contextStub,
            globalProvider: globalStub
        )

        _ = await service.fetchSnapshot(now: fixedNow, language: .chinese)
        // 15 分 01 秒后：重新拉取
        _ = await service.fetchSnapshot(
            now: fixedNow.addingTimeInterval(15 * 60 + 1),
            language: .chinese
        )

        XCTAssertEqual(await contextStub.callCount, 2)
        XCTAssertEqual(await globalStub.callCount, 2)
    }
}

// MARK: - Stubs

actor GoldContextProviderStub: GoldMarketContextProviding {
    private(set) var callCount = 0
    private let result: Result<GoldMarketContext, Error>

    init(result: Result<GoldMarketContext, Error>) {
        self.result = result
    }

    func fetchContext(now: Date, language: AppLanguage) async throws -> GoldMarketContext {
        callCount += 1
        switch result {
        case .success(let context): return context
        case .failure(let error): throw error
        }
    }
}

actor GoldGlobalProviderStub: GoldGlobalMarketProviding {
    private(set) var callCount = 0
    private let result: Result<GoldGlobalSnapshot, Error>

    init(result: Result<GoldGlobalSnapshot, Error>) {
        self.result = result
    }

    func fetchSnapshot(now: Date) async throws -> GoldGlobalSnapshot {
        callCount += 1
        switch result {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}
