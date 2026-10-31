import Foundation

// MARK: - 国际市场参考

/// 国际市场快照：伦敦金、美元指数、美元兑人民币。
struct GoldGlobalSnapshot: Equatable, Sendable {
    /// XAUUSD 现价（美元/盎司）
    let xauUsd: Double
    /// XAUUSD 昨收（用于算涨跌）
    let xauPrevClose: Double?
    /// USD/CNY 汇率
    let usdCny: Double
    /// 美元指数
    let dollarIndex: Double?
    let updatedAt: Date

    /// 国际金价折算国内克价：美元/盎司 ÷ 31.1034768 克/盎司 × 汇率。
    var convertedCnyPerGram: Double {
        xauUsd / 31.1034768 * usdCny
    }

    /// XAUUSD 当日涨跌幅（%），无昨收时为 nil。
    var xauChangePercent: Double? {
        guard let xauPrevClose, xauPrevClose > 0 else { return nil }
        return (xauUsd - xauPrevClose) / xauPrevClose * 100
    }
}

/// 新浪行情接口（免鉴权，需 Referer 头，响应为 GB18030 编码的 JS 变量文本）。
final class GoldGlobalMarketService: Sendable {
    static let shared = GoldGlobalMarketService()

    private let session: URLSession
    private let cache = GoldGlobalMarketCache()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 拉取国际市场快照（缓存 10 分钟，失败抛错由调用方静默处理）。
    func fetchSnapshot(now: Date = Date()) async throws -> GoldGlobalSnapshot {
        if let cached = await cache.snapshot(maxAge: 10 * 60, now: now) {
            return cached
        }

        guard let url = URL(string: "https://hq.sinajs.cn/list=hf_XAU,fx_susdcny,DINIW") else {
            throw GoldPriceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 8

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw GoldPriceError.invalidResponse
        }

        guard let text = Self.decodeGB18030(data),
              let snapshot = Self.parseSinaQuotes(text: text, now: now) else {
            throw GoldPriceError.invalidResponse
        }

        await cache.store(snapshot, now: now)
        return snapshot
    }

    // MARK: - 纯函数（便于单测）

    /// 解析新浪行情文本（字段下标以真实响应核对）：
    /// - hf_XAU：[0] 现价、[7] 昨收
    /// - fx_susdcny：[3] 最新价（与 [1] 买价一致，兜底用 [1]）
    /// - DINIW：[1] 现值
    nonisolated static func parseSinaQuotes(text: String, now: Date = Date()) -> GoldGlobalSnapshot? {
        let quotes = extractQuotes(text: text)

        guard let xauFields = quotes["hf_XAU"],
              let xauUsd = value(xauFields, at: 0), xauUsd > 0 else {
            return nil
        }

        guard let fxFields = quotes["fx_susdcny"],
              let usdCny = value(fxFields, at: 3) ?? value(fxFields, at: 1),
              usdCny > 0 else {
            return nil
        }

        let xauPrevClose = value(xauFields, at: 7).flatMap { $0 > 0 ? $0 : nil }
        let dollarIndex = quotes["DINIW"]
            .flatMap { value($0, at: 1) }
            .flatMap { $0 > 0 ? $0 : nil }

        return GoldGlobalSnapshot(
            xauUsd: xauUsd,
            xauPrevClose: xauPrevClose,
            usdCny: usdCny,
            dollarIndex: dollarIndex,
            updatedAt: now
        )
    }

    /// 把 `var hq_str_KEY="a,b,c";` 文本拆成 key → 字段数组。
    nonisolated private static func extractQuotes(text: String) -> [String: [String]] {
        var quotes: [String: [String]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equalsIndex = line.firstIndex(of: "="),
                  let prefixRange = line.range(of: "var hq_str_") else { continue }
            let key = String(line[prefixRange.upperBound..<equalsIndex])

            guard let firstQuote = line.firstIndex(of: "\""),
                  let lastQuote = line.lastIndex(of: "\""),
                  firstQuote < lastQuote else { continue }
            let body = line[line.index(after: firstQuote)..<lastQuote]
            quotes[key] = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        return quotes
    }

    nonisolated private static func value(_ fields: [String], at index: Int) -> Double? {
        guard index < fields.count else { return nil }
        return Double(fields[index].trimmingCharacters(in: .whitespaces))
    }

    nonisolated private static func decodeGB18030(_ data: Data) -> String? {
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        return String(data: data, encoding: gb18030) ?? String(data: data, encoding: .utf8)
    }
}

// MARK: - Cache

private actor GoldGlobalMarketCache {
    private var entry: (snapshot: GoldGlobalSnapshot, at: Date)?

    func snapshot(maxAge: TimeInterval, now: Date) -> GoldGlobalSnapshot? {
        guard let entry, now.timeIntervalSince(entry.at) < maxAge else { return nil }
        return entry.snapshot
    }

    func store(_ snapshot: GoldGlobalSnapshot, now: Date) {
        entry = (snapshot, now)
    }
}
