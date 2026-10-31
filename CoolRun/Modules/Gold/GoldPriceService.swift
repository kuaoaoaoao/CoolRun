import Foundation

struct GoldPriceQuote: Equatable, Sendable {
    var cnyPerGram: Double
    var updatedAt: Date
    // 官方行情附加信息（回退源不提供时为 nil）
    var yesterdayPrice: Double?
    var changeAmount: Double?
    var changeRatePercent: Double?
    var isMarketClosed: Bool = false
    var source: String = "CZB-JCJ"
}

enum GoldPriceError: LocalizedError {
    case invalidResponse
    case apiMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid gold price response"
        case .apiMessage(let message):
            message
        }
    }
}

final class GoldPriceService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCNYPerGram() async throws -> GoldPriceQuote {
        // 优先使用京东金融 latestPrice（含昨收/涨跌/休市），失败时回退旧接口
        do {
            return try await fetchLatestQuote()
        } catch {
            return try await fetchLegacyQuote()
        }
    }

    // MARK: - 京东金融 latestPrice（主源）

    func fetchLatestQuote() async throws -> GoldPriceQuote {
        var request = URLRequest(url: try makeLatestPriceURL())
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "reqData={}".data(using: .utf8)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw GoldPriceError.invalidResponse
        }

        let payload = try JSONDecoder().decode(JDLatestPriceResponse.self, from: data)
        guard payload.success, payload.resultCode == 0,
              let datas = payload.resultData?.datas,
              let price = Double(datas.price) else {
            throw GoldPriceError.apiMessage(payload.resultMsg ?? "Invalid latestPrice response")
        }

        var updatedAt = Date()
        if let millis = datas.time.flatMap(Double.init) {
            updatedAt = Date(timeIntervalSince1970: millis / 1000)
        }

        return GoldPriceQuote(
            cnyPerGram: price,
            updatedAt: updatedAt,
            yesterdayPrice: datas.yesterdayPrice.flatMap(Double.init),
            changeAmount: datas.upAndDownAmt.flatMap(Double.init),
            changeRatePercent: datas.upAndDownRate.flatMap { Double($0.replacingOccurrences(of: "%", with: "")) },
            isMarketClosed: datas.demode ?? false,
            source: "JD-MS"
        )
    }

    // MARK: - 旧接口（回退源，浙商金条价）

    func fetchLegacyQuote() async throws -> GoldPriceQuote {
        let url = try makeURL()
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw GoldPriceError.invalidResponse
        }

        let payload = try JSONDecoder().decode(ZSBankGoldPriceResponse.self, from: data)

        guard payload.success, payload.resultCode == 0 else {
            throw GoldPriceError.apiMessage(payload.resultMsg)
        }

        let resultData = payload.resultData
        guard resultData.success, resultData.code == "0000" else {
            throw GoldPriceError.apiMessage(payload.resultMsg)
        }

        return GoldPriceQuote(
            cnyPerGram: resultData.data.lastPrice,
            updatedAt: resultData.data.tradeDateTime.date ?? Date()
        )
    }

    private func makeLatestPriceURL() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "ms.jr.jd.com"
        components.path = "/gw/generic/hj/h5/m/latestPrice"

        guard let url = components.url else {
            throw GoldPriceError.invalidResponse
        }
        return url
    }

    private func makeURL() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.jdjygold.com"
        components.path = "/gw2/generic/produTools/h5/m/getGoldPrice"
        components.queryItems = [
            URLQueryItem(name: "goldCode", value: "CZB-JCJ")
        ]

        guard let url = components.url else {
            throw GoldPriceError.invalidResponse
        }
        return url
    }
}

struct JDLatestPriceResponse: Decodable {
    var resultData: ResultData?
    var success: Bool
    var resultCode: Int
    var resultMsg: String?

    struct ResultData: Decodable {
        var datas: Datas?
        var status: String?
    }

    struct Datas: Decodable {
        var price: String
        var yesterdayPrice: String?
        var upAndDownAmt: String?
        var upAndDownRate: String?
        var demode: Bool?
        var time: String?
    }
}

private struct ZSBankGoldPriceResponse: Decodable {
    var resultData: ResultData
    var success: Bool
    var resultCode: Int
    var resultMsg: String

    struct ResultData: Decodable {
        var code: String
        var data: GoldData
        var success: Bool
    }

    struct GoldData: Decodable {
        var lastPrice: Double
        var tradeDateTime: TradeDateTime
    }

    struct TradeDateTime: Decodable {
        var year: Int
        var monthValue: Int
        var dayOfMonth: Int
        var hour: Int
        var minute: Int
        var second: Int

        var date: Date? {
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = TimeZone(identifier: "Asia/Shanghai")
            components.year = year
            components.month = monthValue
            components.day = dayOfMonth
            components.hour = hour
            components.minute = minute
            components.second = second
            return components.date
        }
    }
}
