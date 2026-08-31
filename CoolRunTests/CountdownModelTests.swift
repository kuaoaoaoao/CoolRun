import XCTest
@testable import CoolRun

final class CountdownModelTests: XCTestCase {
    private var calendar: Calendar { Calendar.current }

    func testSolarRepeatingEventCountsTodayAsZero() {
        let today = calendar.dateComponents([.month, .day], from: Date())
        let event = CountdownEvent(name: "今天", month: today.month!, day: today.day!)
        XCTAssertEqual(event.daysRemaining(), 0)
    }

    func testSolarRepeatingEventRollsToNextYearWhenPassed() {
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return XCTFail("无法构造昨天日期")
        }
        let components = calendar.dateComponents([.month, .day], from: yesterday)
        let event = CountdownEvent(name: "昨天", month: components.month!, day: components.day!)
        let days = event.daysRemaining(from: now)
        XCTAssertNotNil(days)
        // 昨天的周年日应落在明年，跨闰年时在 364~366 天之间
        XCTAssertGreaterThanOrEqual(days!, 363)
        XCTAssertLessThanOrEqual(days!, 366)
    }

    func testOneTimePastEventIsNegative() {
        let event = CountdownEvent(name: "过去", month: 1, day: 1, repeatsAnnually: false, targetYear: 2020)
        let days = event.daysRemaining()
        XCTAssertNotNil(days)
        XCTAssertLessThan(days!, 0)
    }

    func testOneTimeFutureEventMatchesTargetDate() {
        let futureYear = calendar.component(.year, from: Date()) + 2
        let event = CountdownEvent(name: "未来", month: 6, day: 7, repeatsAnnually: false, targetYear: futureYear)
        let next = event.nextOccurrence()
        XCTAssertNotNil(next)
        let components = calendar.dateComponents([.year, .month, .day], from: next!)
        XCTAssertEqual(components.year, futureYear)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 7)
    }

    func testLunarRepeatingEventReturnsUpcomingDate() {
        // 农历八月十五（中秋），每年都存在
        let event = CountdownEvent(name: "中秋", isLunar: true, month: 8, day: 15)
        let days = event.daysRemaining()
        XCTAssertNotNil(days)
        XCTAssertGreaterThanOrEqual(days!, 0)
        XCTAssertLessThanOrEqual(days!, 385)
    }

    func testDateStringFormatsSolarAndLunar() {
        let solar = CountdownEvent(name: "a", month: 3, day: 8)
        XCTAssertEqual(solar.dateString, "3月8日")

        let lunar = CountdownEvent(name: "b", isLunar: true, month: 2, day: 8, isLeapMonth: true)
        XCTAssertEqual(lunar.dateString, "闰二月初八")

        let oneTime = CountdownEvent(name: "c", month: 6, day: 7, repeatsAnnually: false, targetYear: 2027)
        XCTAssertEqual(oneTime.dateString, "2027年6月7日")
    }

    func testOccursOnMatchesRepeatingAndOneTimeSolarEvents() throws {
        let target = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2028, month: 6, day: 7))
        )
        let anotherYear = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2029, month: 6, day: 7))
        )

        let repeating = CountdownEvent(name: "周年", month: 6, day: 7)
        let oneTime = CountdownEvent(
            name: "考试",
            month: 6,
            day: 7,
            repeatsAnnually: false,
            targetYear: 2028
        )

        XCTAssertTrue(repeating.occurs(on: target))
        XCTAssertTrue(repeating.occurs(on: anotherYear))
        XCTAssertTrue(oneTime.occurs(on: target))
        XCTAssertFalse(oneTime.occurs(on: anotherYear))
    }

    func testOccursOnMatchesLunarDateIncludingLeapMonth() {
        let solarDate = Date(timeIntervalSince1970: 1_800_000_000)
        let lunarDate = LunarCalendar.convertSolarToLunar(date: solarDate)
        let event = CountdownEvent(
            name: "农历事件",
            isLunar: true,
            month: lunarDate.month,
            day: lunarDate.day,
            isLeapMonth: lunarDate.isLeapMonth
        )
        let wrongLeapMonth = CountdownEvent(
            name: "错误闰月",
            isLunar: true,
            month: lunarDate.month,
            day: lunarDate.day,
            isLeapMonth: !lunarDate.isLeapMonth
        )

        XCTAssertTrue(event.occurs(on: solarDate))
        XCTAssertFalse(wrongLeapMonth.occurs(on: solarDate))
    }

    func testEventCodableRoundTrip() throws {
        let event = CountdownEvent(name: "高考", isLunar: false, month: 6, day: 7, repeatsAnnually: true, note: "加油")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CountdownEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testMergeEventsKeepsExistingAndAddsOnlyNewIdentifiers() {
        let existing = CountdownEvent(name: "已有", month: 1, day: 1)
        let newEvent = CountdownEvent(name: "新增", month: 6, day: 7)
        var duplicate = existing
        duplicate.name = "不应覆盖"

        let result = CountdownManager.mergedEvents(
            existing: [existing],
            incoming: [duplicate, newEvent, newEvent]
        )

        XCTAssertEqual(result, [existing, newEvent])
    }

    func testVersionOneArchiveWithoutCountdownsStillDecodes() throws {
        let json = """
        {
          "version": 1,
          "exportedAt": "2026-07-29T00:00:00Z",
          "appVersion": "1.0",
          "birthdays": [],
          "englishProgress": null,
          "goldPriceRecords": [],
          "goldPredictionLearningRecords": [],
          "goldTrades": null,
          "appSettings": {
            "language": "chinese",
            "menuBarDisplayMode": "goldPrice",
            "systemRefreshRate": "balanced",
            "goldRefreshRate": "minute",
            "menuBarAnimationRate": "energySaving",
            "englishAccent": "american",
            "englishStage": "daily",
            "englishTTSBackend": "system",
            "englishNormalRate": 0.43,
            "englishSlowRate": 0.30,
            "englishVolume": 0.90,
            "englishRepeatCount": 2,
            "englishItemInterval": 7,
            "englishDailyTarget": 10,
            "englishShowTranslation": true,
            "englishSpeakTranslation": false
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archive = try decoder.decode(DataArchive.self, from: Data(json.utf8))

        XCTAssertEqual(archive.version, 1)
        XCTAssertNil(archive.countdownEvents)
        XCTAssertNil(archive.appSettings?.aiQuotaAlertEnabled)
        XCTAssertNil(archive.appSettings?.goldHoldingGramsText)
    }

    // MARK: - v3 周预测档案兼容

    func testVersionTwoArchiveWithoutWeeklyForecastRecordsStillDecodes() throws {
        let json = """
        {
          "version": 2,
          "exportedAt": "2026-08-30T00:00:00Z",
          "appVersion": "1.0",
          "birthdays": [],
          "englishProgress": null,
          "goldPriceRecords": [],
          "goldPredictionLearningRecords": [],
          "goldTrades": null,
          "appSettings": null
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archive = try decoder.decode(DataArchive.self, from: Data(json.utf8))

        XCTAssertEqual(archive.version, 2)
        XCTAssertNil(archive.goldWeeklyForecastRecords)
    }

    func testVersionThreeArchiveRoundTripsWeeklyForecastRecords() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let forecast = GoldWeeklyForecast(
            direction: .up,
            confidence: .low,
            startPrice: 600,
            expectedPrice: 606,
            expectedReturn: 0.01,
            p10: 594,
            p50: 606,
            p90: 618,
            generatedAt: generatedAt,
            targetDate: Calendar.goldShanghai.date(byAdding: .day, value: 7, to: generatedAt)!,
            dataUpdatedAt: generatedAt,
            currentPriceSource: "JD-MS",
            historySource: GoldMarketDataService.historySourceID,
            sourceCompatibility: .verified,
            components: GoldWeeklyForecastComponents(
                trend: 0.4, momentum: 0.3, meanReversion: -0.1,
                bootstrap: 0.3, composite: 0.275
            ),
            reasons: ["fixture"],
            counterRisks: [],
            modelVersion: GoldWeeklyForecastPolicy.modelVersion
        )
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
        let record = GoldWeeklyForecastRecord(
            id: UUID(),
            forecast: forecast,
            backtest: backtest,
            status: .validated,
            resolvedAt: generatedAt.addingTimeInterval(7 * 24 * 3600),
            endPrice: 620,
            actualReturn: 0.02,
            actualDirection: .up,
            wasDirectionalHit: true,
            absoluteReturnError: 0.01
        )
        let archive = DataArchive(
            version: 3,
            exportedAt: Date(),
            appVersion: "1.0",
            birthdays: [],
            countdownEvents: nil,
            englishProgress: nil,
            goldPriceRecords: [],
            goldPredictionLearningRecords: [],
            goldTrades: nil,
            appSettings: nil,
            goldWeeklyForecastRecords: [record]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DataArchive.self, from: encoder.encode(archive))

        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.goldWeeklyForecastRecords, [record])
    }
}
