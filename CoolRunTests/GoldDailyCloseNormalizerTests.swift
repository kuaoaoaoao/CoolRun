import XCTest
@testable import CoolRun

final class GoldDailyCloseNormalizerTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    func testKeepsLastValidPointPerShanghaiDayAndSortsAscending() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let points = [
            GoldRemotePricePoint(price: 600, timestamp: day.addingTimeInterval(9 * 3600)),
            GoldRemotePricePoint(price: 602, timestamp: day.addingTimeInterval(15 * 3600)),
            GoldRemotePricePoint(price: 603, timestamp: day.addingTimeInterval(24 * 3600 + 10 * 3600))
        ]
        let quality = GoldDailyCloseNormalizer.normalize(
            points: points,
            now: day.addingTimeInterval(25 * 3600)
        )
        XCTAssertEqual(quality.closes.map(\.close), [602, 603])
    }

    func testRejectsOutOfRangeAndEightPercentSpike() {
        let points = makeDailyPoints(prices: [600, 602, 700, 603, 50])
        let quality = GoldDailyCloseNormalizer.normalize(points: points, now: points.last!.timestamp)
        XCTAssertEqual(quality.closes.map(\.close), [600, 602, 603])
        XCTAssertEqual(quality.rejectedCount, 2)
    }

    func testHistoryOlderThanNinetySixHoursIsStale() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let points = makeDailyPoints(count: 130, endingAt: now.addingTimeInterval(-97 * 3600))
        let quality = GoldDailyCloseNormalizer.normalize(points: points, now: now)
        XCTAssertTrue(quality.isStale)
    }

    func testSpikeDoesNotBecomeBaseForNextPointComparison() {
        // 700 被相邻 8% 规则过滤。
        // 若 700 成为比较基准，603（相对 700 下跌 13.9%）会被误判为异常。
        let points = makeDailyPoints(prices: [600, 602, 700, 603, 605])
        let quality = GoldDailyCloseNormalizer.normalize(points: points, now: points.last!.timestamp)
        XCTAssertEqual(quality.closes.map(\.close), [600, 602, 603, 605])
        XCTAssertEqual(quality.rejectedCount, 1)
    }

    func testMaximumGapDaysReflectsLargestCalendarHole() {
        let calendar = Calendar.goldShanghai
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        // 0, 1, 20, 21 天：最大缺口 19 天
        let points = [0, 1, 20, 21].compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }.map {
            GoldRemotePricePoint(price: 600, timestamp: $0)
        }
        let quality = GoldDailyCloseNormalizer.normalize(points: points, now: start.addingTimeInterval(22 * 86400))
        XCTAssertEqual(quality.maximumGapDays, 19)
    }

    // MARK: - 确定性 fixture（不使用真实网络）

    private func makeDailyPoints(
        prices: [Double],
        endingAt: Date = Date(timeIntervalSince1970: 1_788_000_000)
    ) -> [GoldRemotePricePoint] {
        let calendar = Calendar.goldShanghai
        return prices.enumerated().map { index, price in
            let offset = index - (prices.count - 1)
            let timestamp = calendar.date(byAdding: .day, value: offset, to: endingAt)!
            return GoldRemotePricePoint(price: price, timestamp: timestamp)
        }
    }

    private func makeDailyPoints(count: Int, endingAt: Date) -> [GoldRemotePricePoint] {
        makeDailyPoints(
            prices: (0..<count).map { 580 + Double($0) * 0.1 },
            endingAt: endingAt
        )
    }
}
