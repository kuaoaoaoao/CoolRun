import Foundation

// MARK: - Models

struct GoldRemotePricePoint: Equatable, Sendable {
    let price: Double
    let timestamp: Date
}

enum GoldHistoryRange: String, CaseIterable, Sendable {
    case week = "w"
    case month = "m"
    case quarter = "q"
    case halfYear = "h"
    case year = "y"
}

/// 走势图展示范围：今日取官方分时，其余取历史日线
enum GoldChartRange: String, CaseIterable, Sendable {
    case today
    case week
    case month
    case quarter
    case halfYear
    case year

    // 金融通用缩写，无需本地化
    var shortLabel: String {
        switch self {
        case .today: "1D"
        case .week: "1W"
        case .month: "1M"
        case .quarter: "3M"
        case .halfYear: "6M"
        case .year: "1Y"
        }
    }

    var historyRange: GoldHistoryRange? {
        switch self {
        case .today: nil
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .halfYear: .halfYear
        case .year: .year
        }
    }
}

struct GoldMultiSourcePrice: Identifiable, Equatable, Sendable {
    let id = UUID()
    let name: String
    let price: Double
    let change: Double?
    let changeRatePercent: Double?
    let updatedAt: Date?
}

// MARK: - 周预测历史窄协议

/// 周预测只依赖这一个历史接口；请求 URL、period 和缓存时长与走势图共用。
protocol GoldWeeklyHistoryProviding: Sendable {
    func fetchHistoryPrices(
        range: GoldHistoryRange,
        now: Date
    ) async throws -> [GoldRemotePricePoint]
}

// MARK: - Service

/// 官方走势（京东金融）与多平台金价对比（gold.rsky.cn）数据服务。
final class GoldMarketDataService: Sendable {
    static let shared = GoldMarketDataService()

    private let session: URLSession
    private let cache = GoldMarketDataCache()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: 今日分时（京东 todayPrices，缓存 2 分钟）

    func fetchTodayPrices(now: Date = Date()) async throws -> [GoldRemotePricePoint] {
        if let cached = await cache.todayPoints(maxAge: 120, now: now) {
            return cached
        }

        let data = try await postJD(path: "/gw/generic/hj/h5/m/todayPrices", reqData: "{}")
        let payload = try JSONDecoder().decode(JDTodayPricesResponse.self, from: data)
        guard payload.success, let datas = payload.resultData?.datas else {
            throw GoldPriceError.invalidResponse
        }

        let formatter = Self.makeShanghaiFormatter()
        let points: [GoldRemotePricePoint] = datas.compactMap { item in
            guard item.value.count >= 2,
                  let date = formatter.date(from: item.value[0]),
                  let price = Double(item.value[1]) else { return nil }
            return GoldRemotePricePoint(price: price, timestamp: date)
        }
        guard !points.isEmpty else { throw GoldPriceError.invalidResponse }

        await cache.storeTodayPoints(points, now: now)
        return points
    }

    // MARK: 历史走势（京东 historyPrices，缓存 30 分钟）

    func fetchHistoryPrices(range: GoldHistoryRange, now: Date = Date()) async throws -> [GoldRemotePricePoint] {
        if let cached = await cache.historyPoints(for: range, maxAge: 30 * 60, now: now) {
            return cached
        }

        let data = try await postJD(
            path: "/gw/generic/hj/h5/m/historyPrices",
            reqData: #"{"period":"\#(range.rawValue)"}"#
        )
        let payload = try JSONDecoder().decode(JDHistoryPricesResponse.self, from: data)
        guard payload.success, let datas = payload.resultData?.datas else {
            throw GoldPriceError.invalidResponse
        }

        let points: [GoldRemotePricePoint] = datas.compactMap { item in
            guard let price = Double(item.price), let millis = Double(item.time) else { return nil }
            return GoldRemotePricePoint(price: price, timestamp: Date(timeIntervalSince1970: millis / 1000))
        }
        guard !points.isEmpty else { throw GoldPriceError.invalidResponse }

        await cache.storeHistoryPoints(points, for: range, now: now)
        return points
    }

    // MARK: 多平台金价（gold.rsky.cn，缓存 5 分钟）

    func fetchMultiSourcePrices(now: Date = Date()) async throws -> [GoldMultiSourcePrice] {
        if let cached = await cache.multiSourcePrices(maxAge: 5 * 60, now: now) {
            return cached
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "gold.rsky.cn"
        components.path = "/api/multi-source-prices"
        guard let url = components.url else { throw GoldPriceError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw GoldPriceError.invalidResponse
        }

        let payload = try JSONDecoder().decode(RSkyMultiSourceResponse.self, from: data)
        guard payload.code == 200, let items = payload.data?.prices else {
            throw GoldPriceError.apiMessage(payload.message ?? "Invalid multi-source response")
        }

        let formatter = Self.makeShanghaiFormatter()
        let prices: [GoldMultiSourcePrice] = items.compactMap { item in
            guard item.success ?? true, let price = item.price?.doubleValue, price > 0 else { return nil }
            return GoldMultiSourcePrice(
                name: item.name,
                price: price,
                change: item.change?.doubleValue,
                changeRatePercent: item.changeRate?.doubleValue,
                updatedAt: item.readableTime.flatMap(formatter.date(from:))
            )
        }
        guard !prices.isEmpty else { throw GoldPriceError.invalidResponse }

        await cache.storeMultiSourcePrices(prices, now: now)
        return prices
    }

    // MARK: - Helpers

    private func postJD(path: String, reqData: String) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "ms.jr.jd.com"
        components.path = path
        guard let url = components.url else { throw GoldPriceError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = reqData.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? reqData
        request.httpBody = "reqData=\(encoded)".data(using: .utf8)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw GoldPriceError.invalidResponse
        }
        return data
    }

    private static func makeShanghaiFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

// MARK: - 周预测历史来源

extension GoldMarketDataService: GoldWeeklyHistoryProviding {}

extension GoldMarketDataService {
    /// 历史日线固定来源标识（京东 historyPrices）。
    nonisolated static let historySourceID = "JD-MS-history"
}

// MARK: - Cache

private actor GoldMarketDataCache {
    private var today: (points: [GoldRemotePricePoint], at: Date)?
    private var history: [GoldHistoryRange: (points: [GoldRemotePricePoint], at: Date)] = [:]
    private var multiSource: (prices: [GoldMultiSourcePrice], at: Date)?

    func todayPoints(maxAge: TimeInterval, now: Date) -> [GoldRemotePricePoint]? {
        guard let today, now.timeIntervalSince(today.at) < maxAge else { return nil }
        return today.points
    }

    func storeTodayPoints(_ points: [GoldRemotePricePoint], now: Date) {
        today = (points, now)
    }

    func historyPoints(for range: GoldHistoryRange, maxAge: TimeInterval, now: Date) -> [GoldRemotePricePoint]? {
        guard let entry = history[range], now.timeIntervalSince(entry.at) < maxAge else { return nil }
        return entry.points
    }

    func storeHistoryPoints(_ points: [GoldRemotePricePoint], for range: GoldHistoryRange, now: Date) {
        history[range] = (points, now)
    }

    func multiSourcePrices(maxAge: TimeInterval, now: Date) -> [GoldMultiSourcePrice]? {
        guard let multiSource, now.timeIntervalSince(multiSource.at) < maxAge else { return nil }
        return multiSource.prices
    }

    func storeMultiSourcePrices(_ prices: [GoldMultiSourcePrice], now: Date) {
        multiSource = (prices, now)
    }
}

// MARK: - Response payloads

struct JDTodayPricesResponse: Decodable {
    var resultData: ResultData?
    var success: Bool

    struct ResultData: Decodable {
        var datas: [Item]?
        var status: String?
    }

    struct Item: Decodable {
        var value: [String]
    }
}

struct JDHistoryPricesResponse: Decodable {
    var resultData: ResultData?
    var success: Bool

    struct ResultData: Decodable {
        var datas: [Item]?
        var status: String?
    }

    struct Item: Decodable {
        var price: String
        var time: String
        var demode: Bool?

        private enum CodingKeys: String, CodingKey {
            case price, time, demode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            price = try Self.lenientString(container, key: .price)
            time = try Self.lenientString(container, key: .time)
            demode = try container.decodeIfPresent(Bool.self, forKey: .demode)
        }

        private static func lenientString(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> String {
            if let string = try? container.decode(String.self, forKey: key) { return string }
            if let number = try? container.decode(Double.self, forKey: key) {
                return number.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int64(number))
                    : String(number)
            }
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected string or number")
        }
    }
}

struct RSkyMultiSourceResponse: Decodable {
    var code: Int
    var message: String?
    var data: DataPayload?

    struct DataPayload: Decodable {
        var prices: [Item]?
        var updateTime: String?

        private enum CodingKeys: String, CodingKey {
            case prices
            case updateTime = "update_time"
        }
    }

    struct Item: Decodable {
        var name: String
        var price: LenientNumber?
        var change: LenientNumber?
        var changeRate: LenientNumber?
        var readableTime: String?
        var success: Bool?

        private enum CodingKeys: String, CodingKey {
            case name, price, change, success
            case changeRate = "change_rate"
            case readableTime = "readable_time"
        }
    }
}

/// 兼容 Double 与 String（可含 % 号）混排的数值字段。
struct LenientNumber: Decodable {
    let doubleValue: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            doubleValue = number
            return
        }
        if let string = try? container.decode(String.self) {
            let cleaned = string
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces)
            doubleValue = Double(cleaned)
            return
        }
        doubleValue = nil
    }
}
