import XCTest
@testable import CoolRun

final class GoldMarketDataServiceTests: XCTestCase {

    // MARK: - 京东 latestPrice 解码

    func testDecodeLatestPriceResponse() throws {
        let json = """
        {
          "resultData": {
            "datas": {
              "price": "886.16",
              "yesterdayPrice": "888.42",
              "upAndDownAmt": "-2.26",
              "upAndDownRate": "-0.25%",
              "productSku": "21001001000001",
              "demode": true,
              "id": 11852516,
              "time": "1784915999000"
            },
            "status": "SUCCESS"
          },
          "success": true,
          "resultCode": 0,
          "resultMsg": "成功"
        }
        """
        let payload = try JSONDecoder().decode(JDLatestPriceResponse.self, from: Data(json.utf8))

        XCTAssertTrue(payload.success)
        XCTAssertEqual(payload.resultCode, 0)
        let datas = try XCTUnwrap(payload.resultData?.datas)
        XCTAssertEqual(Double(datas.price), 886.16)
        XCTAssertEqual(datas.yesterdayPrice.flatMap(Double.init), 888.42)
        XCTAssertEqual(datas.upAndDownAmt.flatMap(Double.init), -2.26)
        XCTAssertEqual(datas.demode, true)
        // 涨跌幅带 % 号，按服务层逻辑清洗后可转数值
        let rate = try XCTUnwrap(datas.upAndDownRate).replacingOccurrences(of: "%", with: "")
        XCTAssertEqual(Double(rate), -0.25)
        // 毫秒时间戳
        let millis = try XCTUnwrap(datas.time.flatMap(Double.init))
        XCTAssertEqual(Date(timeIntervalSince1970: millis / 1000).timeIntervalSince1970, 1_784_915_999, accuracy: 1)
    }

    // MARK: - 京东 todayPrices 解码

    func testDecodeTodayPricesResponse() throws {
        let json = """
        {
          "resultData": {
            "datas": [
              {"name": "2026-07-25 00:00:00", "value": ["2026-07-25 00:00:00", "888.42"]},
              {"name": "2026-07-25 00:06:00", "value": ["2026-07-25 00:06:00", "888.44"]},
              {"name": "bad", "value": ["not-a-date"]}
            ],
            "status": "SUCCESS"
          },
          "success": true,
          "resultCode": 0
        }
        """
        let payload = try JSONDecoder().decode(JDTodayPricesResponse.self, from: Data(json.utf8))

        XCTAssertTrue(payload.success)
        let datas = try XCTUnwrap(payload.resultData?.datas)
        XCTAssertEqual(datas.count, 3)
        XCTAssertEqual(datas[0].value, ["2026-07-25 00:00:00", "888.42"])
        XCTAssertEqual(Double(datas[1].value[1]), 888.44)
    }

    // MARK: - 京东 historyPrices 解码（price/time 兼容字符串与数字）

    func testDecodeHistoryPricesResponse() throws {
        let json = """
        {
          "resultData": {
            "datas": [
              {"demode": false, "price": "869.0400", "time": "1782316800000"},
              {"demode": true, "price": 876.82, "time": 1782403200000}
            ],
            "status": "SUCCESS"
          },
          "success": true,
          "resultCode": 0
        }
        """
        let payload = try JSONDecoder().decode(JDHistoryPricesResponse.self, from: Data(json.utf8))

        let datas = try XCTUnwrap(payload.resultData?.datas)
        XCTAssertEqual(datas.count, 2)
        XCTAssertEqual(Double(datas[0].price), 869.04)
        XCTAssertEqual(Double(datas[0].time), 1_782_316_800_000)
        XCTAssertEqual(datas[0].demode, false)
        // 数字形式同样可解析
        XCTAssertEqual(Double(datas[1].price), 876.82)
        XCTAssertEqual(Double(datas[1].time), 1_782_403_200_000)
        XCTAssertEqual(datas[1].demode, true)
    }

    // MARK: - rsky 多源价格解码（change/change_rate 为 Double 与 String 混排）

    func testDecodeMultiSourceResponseWithMixedNumberTypes() throws {
        let json = """
        {
          "code": 200,
          "data": {
            "prices": [
              {"name": "新浪-股票|基金API", "price": 886.61, "change": 2.92, "change_rate": 0.33, "readable_time": "2026-07-25 22:18:22", "success": true},
              {"name": "民生银行", "price": "886.16", "change": "-2.26", "change_rate": "-0.25%", "readable_time": "2026-07-25 22:18:23", "success": true},
              {"name": "故障源", "price": null, "change": null, "change_rate": null, "success": false}
            ],
            "total": 3,
            "update_time": "2026-07-25 22:18:25"
          },
          "message": "success"
        }
        """
        let payload = try JSONDecoder().decode(RSkyMultiSourceResponse.self, from: Data(json.utf8))

        XCTAssertEqual(payload.code, 200)
        let items = try XCTUnwrap(payload.data?.prices)
        XCTAssertEqual(items.count, 3)

        // Double 形式
        XCTAssertEqual(items[0].price?.doubleValue, 886.61)
        XCTAssertEqual(items[0].change?.doubleValue, 2.92)
        XCTAssertEqual(items[0].changeRate?.doubleValue, 0.33)
        // String 形式（含 % 号）
        XCTAssertEqual(items[1].price?.doubleValue, 886.16)
        XCTAssertEqual(items[1].change?.doubleValue, -2.26)
        XCTAssertEqual(items[1].changeRate?.doubleValue, -0.25)
        // 故障源标记
        XCTAssertEqual(items[2].success, false)
    }

    // MARK: - GoldPriceStore 官方点合并筛选（去重与过滤）

    func testOfficialRecordsToInsertSkipsPointsNearExistingRecords() {
        let anchor = Date(timeIntervalSince1970: 1_784_900_000)
        let existing = [
            GoldPriceRecord(price: 880.0, timestamp: anchor),
            GoldPriceRecord(price: 880.2, timestamp: anchor.addingTimeInterval(300))
        ]

        let inserted = GoldPriceStore.officialRecordsToInsert(
            points: [
                GoldRemotePricePoint(price: 880.5, timestamp: anchor.addingTimeInterval(30)),   // 30 秒内已有记录，跳过
                GoldRemotePricePoint(price: 880.8, timestamp: anchor.addingTimeInterval(150)),  // 断档处，插入
                GoldRemotePricePoint(price: 881.0, timestamp: anchor.addingTimeInterval(180)),  // 与上一插入点仅隔 30 秒，跳过
                GoldRemotePricePoint(price: 50.0, timestamp: anchor.addingTimeInterval(600))    // 超出合理区间，丢弃
            ],
            existing: existing
        )

        XCTAssertEqual(inserted.count, 1)
        XCTAssertEqual(inserted[0].price, 880.8)
        XCTAssertEqual(inserted[0].source, "JD-official")
    }

    func testOfficialRecordsToInsertBackfillsEmptyStore() {
        let anchor = Date(timeIntervalSince1970: 1_784_900_000)
        let points = (0..<5).map {
            GoldRemotePricePoint(price: 880.0 + Double($0), timestamp: anchor.addingTimeInterval(Double($0) * 120))
        }

        let inserted = GoldPriceStore.officialRecordsToInsert(points: points, existing: [])

        XCTAssertEqual(inserted.count, 5)
        let timestamps = inserted.map(\.timestamp)
        XCTAssertEqual(timestamps, timestamps.sorted())
    }

    // MARK: - 周预测历史来源（协议与固定来源 ID）

    func testHistorySourceIDIsFixed() {
        XCTAssertEqual(GoldMarketDataService.historySourceID, "JD-MS-history")
    }

    func testServiceSatisfiesWeeklyHistoryProtocol() {
        // 协议存在性由编译保证；运行时确认共享实例可作为历史提供方传递。
        let provider: any GoldWeeklyHistoryProviding = GoldMarketDataService.shared
        XCTAssertEqual(
            type(of: provider) == GoldMarketDataService.self,
            true
        )
    }
}
