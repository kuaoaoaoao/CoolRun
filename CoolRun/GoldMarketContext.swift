import Foundation

enum GoldMarketContextTone: Equatable, Sendable {
    case bullish
    case neutral
    case bearish

    var title: String {
        switch self {
        case .bullish: LocalizedString.gold("macro_bullish")
        case .neutral: LocalizedString.gold("macro_neutral")
        case .bearish: LocalizedString.gold("macro_bearish")
        }
    }
}

struct GoldNewsItem: Identifiable, Sendable {
    let id: UUID
    let title: String
    let source: String?
    let link: URL?
    let publishedAt: Date?
    let sentimentScore: Double
    let eventKey: String
    let sourceTier: GoldNewsSourceTier

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        source: String?,
        link: URL?,
        publishedAt: Date?,
        sentimentScore: Double,
        eventKey: String? = nil,
        sourceTier: GoldNewsSourceTier? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.link = link
        self.publishedAt = publishedAt
        self.sentimentScore = sentimentScore
        self.eventKey = eventKey ?? GoldNewsClassifier.eventKey(title: title)
        self.sourceTier = sourceTier ?? GoldNewsClassifier.sourceTier(source)
    }
}

struct GoldMacroSnapshot: Sendable {
    let tenYearYield: Double?
    let tenYearYieldChangeBps: Double?
    let observedAt: Date?
}

struct GoldMarketContext: Sendable {
    let macroScore: Double
    let newsScore: Double
    let overallScore: Double
    let macro: GoldMacroSnapshot?
    let newsItems: [GoldNewsItem]
    let reasons: [String]
    let updatedAt: Date
    let isPartial: Bool
    let missingDataDescription: String?
    let isFromCache: Bool

    nonisolated init(
        macroScore: Double,
        newsScore: Double,
        overallScore: Double,
        macro: GoldMacroSnapshot?,
        newsItems: [GoldNewsItem],
        reasons: [String],
        updatedAt: Date,
        isPartial: Bool = false,
        missingDataDescription: String? = nil,
        isFromCache: Bool = false
    ) {
        self.macroScore = macroScore
        self.newsScore = newsScore
        self.overallScore = overallScore
        self.macro = macro
        self.newsItems = newsItems
        self.reasons = reasons
        self.updatedAt = updatedAt
        self.isPartial = isPartial
        self.missingDataDescription = missingDataDescription
        self.isFromCache = isFromCache
    }

    var tone: GoldMarketContextTone {
        if overallScore >= 18 { return .bullish }
        if overallScore <= -18 { return .bearish }
        return .neutral
    }

    nonisolated func markedAsCache(_ isFromCache: Bool, missingDataDescription: String? = nil) -> GoldMarketContext {
        GoldMarketContext(
            macroScore: macroScore,
            newsScore: newsScore,
            overallScore: overallScore,
            macro: macro,
            newsItems: newsItems,
            reasons: reasons,
            updatedAt: updatedAt,
            isPartial: isPartial || missingDataDescription != nil,
            missingDataDescription: missingDataDescription ?? self.missingDataDescription,
            isFromCache: isFromCache
        )
    }
}

final class GoldMarketContextService {
    private let session: URLSession
    private static let cache = GoldMarketContextMemoryCache()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchContext(now: Date = Date()) async throws -> GoldMarketContext {
        if let cached = await Self.cache.context(maxAge: 15 * 60, now: now) {
            return cached.markedAsCache(true)
        }

        var macro: GoldMacroSnapshot?
        var newsItems: [GoldNewsItem] = []
        var missingParts: [String] = []

        do {
            macro = try await fetchTreasuryYieldContext(now: now)
        } catch {
            macro = nil
            missingParts.append(LocalizedString.gold("missing_treasury"))
        }

        do {
            newsItems = try await fetchGoldNews(now: now)
        } catch {
            newsItems = []
            missingParts.append(LocalizedString.gold("missing_news_rss"))
        }

        if macro == nil, newsItems.isEmpty,
           let staleContext = await Self.cache.context(maxAge: nil, now: now) {
            return staleContext.markedAsCache(
                true,
                missingDataDescription: LocalizedString.gold("missing_macro_failed")
            )
        }

        let context = GoldMarketContextScorer.makeContext(
            macro: macro,
            newsItems: newsItems,
            language: AppSettings.shared.language,
            now: now,
            missingDataDescription: missingParts.isEmpty ? nil : String(
                format: LocalizedString.gold("missing_unavailable_format"),
                missingParts.joined(separator: ", ")
            )
        )
        await Self.cache.save(context)
        return context
    }

    private struct NewsSearch: Sendable {
        let query: String
        let language: String
        let region: String
        let edition: String
    }

    private func fetchGoldNews(now: Date) async throws -> [GoldNewsItem] {
        let searches = [
            NewsSearch(
                query: "(黄金 OR 金价 OR XAUUSD) when:3d",
                language: "zh-CN",
                region: "CN",
                edition: "CN:zh-Hans"
            ),
            NewsSearch(
                query: "(黄金 OR 金价) (美联储 OR 美元 OR 美债收益率 OR 通胀 OR 地缘冲突) when:3d",
                language: "zh-CN",
                region: "CN",
                edition: "CN:zh-Hans"
            ),
            NewsSearch(
                query: "(gold OR XAUUSD) (Fed OR dollar OR Treasury yields OR inflation OR geopolitics) when:3d",
                language: "en-US",
                region: "US",
                edition: "US:en"
            )
        ]

        let batches = await withTaskGroup(of: [RSSParsedItem].self) { group in
            for search in searches {
                group.addTask { [session] in
                    do {
                        let url = try await Self.newsURL(for: search)
                        let data = try await Self.fetchData(session: session, url: url, timeout: 12)
                        return await GoldNewsRSSParser.parse(data: data)
                    } catch {
                        return []
                    }
                }
            }

            var result: [[RSSParsedItem]] = []
            for await batch in group where !batch.isEmpty {
                result.append(batch)
            }
            return result
        }

        guard !batches.isEmpty else { throw GoldMarketContextError.invalidResponse }

        let oldestAllowed = now.addingTimeInterval(-4 * 24 * 60 * 60)
        var seenTitles = Set<String>()
        let merged = batches
            .flatMap { $0 }
            .filter { item in
                item.publishedAt.map { $0 >= oldestAllowed && $0 <= now.addingTimeInterval(10 * 60) } ?? true
            }
            .sorted { lhs, rhs in
                (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
            }
            .filter { item in
                let key = Self.normalizedNewsTitle(item.title)
                return !key.isEmpty && seenTitles.insert(key).inserted
            }

        return merged.prefix(30).map { item in
            GoldNewsItem(
                title: item.title,
                source: item.source,
                link: item.link,
                publishedAt: item.publishedAt,
                sentimentScore: GoldMarketContextScorer.scoreNewsText(item.title)
            )
        }
    }

    private static func newsURL(for search: NewsSearch) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "news.google.com"
        components.path = "/rss/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: search.query),
            URLQueryItem(name: "hl", value: search.language),
            URLQueryItem(name: "gl", value: search.region),
            URLQueryItem(name: "ceid", value: search.edition)
        ]

        guard let url = components.url else { throw GoldMarketContextError.invalidURL }
        return url
    }

    private static func normalizedNewsTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }

    private func fetchTreasuryYieldContext(now: Date) async throws -> GoldMacroSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)
        var points = try await fetchTreasuryYieldPoints(year: year)

        if points.count < 2 {
            let previousYearPoints = try await fetchTreasuryYieldPoints(year: year - 1)
            points = previousYearPoints + points
        }

        let sorted = points.sorted { $0.date < $1.date }
        guard let latest = sorted.last else {
            return GoldMacroSnapshot(tenYearYield: nil, tenYearYieldChangeBps: nil, observedAt: nil)
        }

        let previous = sorted.dropLast().last
        let changeBps = previous.map { (latest.tenYearYield - $0.tenYearYield) * 100 }

        return GoldMacroSnapshot(
            tenYearYield: latest.tenYearYield,
            tenYearYieldChangeBps: changeBps,
            observedAt: latest.date
        )
    }

    private func fetchTreasuryYieldPoints(year: Int) async throws -> [TreasuryYieldPoint] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "home.treasury.gov"
        components.path = "/resource-center/data-chart-center/interest-rates/pages/xml"
        components.queryItems = [
            URLQueryItem(name: "data", value: "daily_treasury_yield_curve"),
            URLQueryItem(name: "field_tdr_date_value", value: "\(year)")
        ]

        guard let url = components.url else { throw GoldMarketContextError.invalidURL }
        let data = try await fetchData(url: url, timeout: 12)
        return TreasuryYieldXMLParser.parse(data: data)
    }

    private func fetchData(url: URL, timeout: TimeInterval) async throws -> Data {
        try await Self.fetchData(session: session, url: url, timeout: timeout)
    }

    private static func fetchData(session: URLSession, url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("CoolRun gold context", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw GoldMarketContextError.invalidResponse
        }

        return data
    }
}

private actor GoldMarketContextMemoryCache {
    private var cachedContext: GoldMarketContext?

    func context(maxAge: TimeInterval?, now: Date) -> GoldMarketContext? {
        guard let cachedContext else { return nil }
        if let maxAge, now.timeIntervalSince(cachedContext.updatedAt) > maxAge {
            return nil
        }
        return cachedContext
    }

    func save(_ context: GoldMarketContext) {
        cachedContext = context.markedAsCache(false)
    }
}

enum GoldMarketContextError: Error {
    case invalidURL
    case invalidResponse
}

enum GoldMarketContextScorer {
    nonisolated static func makeContext(
        macro: GoldMacroSnapshot?,
        newsItems: [GoldNewsItem],
        language: AppLanguage,
        now: Date = Date(),
        missingDataDescription: String? = nil
    ) -> GoldMarketContext {
        let macroScore = scoreMacro(macro)
        let newsScore = scoreNewsItems(newsItems, now: now)
        let availableWeights = (macro == nil ? 0.0 : 0.55) + (newsItems.isEmpty ? 0.0 : 0.45)
        let overallScore: Double

        if availableWeights > 0 {
            overallScore = ((macro == nil ? 0 : macroScore * 0.55) + (newsItems.isEmpty ? 0 : newsScore * 0.45)) / availableWeights
        } else {
            overallScore = 0
        }

        return GoldMarketContext(
            macroScore: macroScore,
            newsScore: newsScore,
            overallScore: overallScore.clamped(to: -100...100),
            macro: macro,
            newsItems: newsItems,
            reasons: makeReasons(
                macro: macro,
                macroScore: macroScore,
                newsItems: newsItems,
                language: language
            ),
            updatedAt: now,
            isPartial: missingDataDescription != nil,
            missingDataDescription: missingDataDescription,
            isFromCache: false
        )
    }

    nonisolated static func scoreNewsText(_ text: String) -> Double {
        GoldNewsClassifier.classify(title: text, source: nil).sentimentScore
    }

    private nonisolated static func scoreMacro(_ macro: GoldMacroSnapshot?) -> Double {
        guard let changeBps = macro?.tenYearYieldChangeBps else { return 0 }
        return (-changeBps * 2.2).clamped(to: -45...45)
    }

    private nonisolated static func scoreNewsItems(_ items: [GoldNewsItem], now: Date) -> Double {
        guard !items.isEmpty else { return 0 }
        let scoredItems = items.filter { abs($0.sentimentScore) > 0 }
        let source = scoredItems.isEmpty ? items : scoredItems
        let weighted = source.map { item -> (score: Double, weight: Double) in
            guard let publishedAt = item.publishedAt else { return (item.sentimentScore, 0.35) }
            let ageHours = max(0, now.timeIntervalSince(publishedAt) / 3600)
            let recencyWeight = exp(-ageHours / 36)
            return (item.sentimentScore, max(0.15, recencyWeight))
        }
        let totalWeight = weighted.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return 0 }
        return (weighted.map { $0.score * $0.weight }.reduce(0, +) / totalWeight).clamped(to: -100...100)
    }

    private nonisolated static func makeReasons(
        macro: GoldMacroSnapshot?,
        macroScore: Double,
        newsItems: [GoldNewsItem],
        language: AppLanguage
    ) -> [String] {
        var reasons: [String] = []

        if let changeBps = macro?.tenYearYieldChangeBps {
            if changeBps <= -3 {
                reasons.append(LocalizedString.l(language, en: "U.S. 10Y yield fell \(abs(changeBps).oneDigitNumber)bp, usually supportive for gold valuation", zh: "10年期美债收益率回落 \(abs(changeBps).oneDigitNumber)bp，通常利好黄金估值", ja: "米10年債利回りが \(abs(changeBps).oneDigitNumber)bp 低下し、通常は金の評価に追い風です", ko: "미국 10년물 금리가 \(abs(changeBps).oneDigitNumber)bp 하락해 보통 금 가치에 우호적입니다"))
            } else if changeBps >= 3 {
                reasons.append(LocalizedString.l(language, en: "U.S. 10Y yield rose \(changeBps.oneDigitNumber)bp, usually pressuring gold valuation", zh: "10年期美债收益率上行 \(changeBps.oneDigitNumber)bp，通常压制黄金估值", ja: "米10年債利回りが \(changeBps.oneDigitNumber)bp 上昇し、通常は金の評価を圧迫します", ko: "미국 10년물 금리가 \(changeBps.oneDigitNumber)bp 상승해 보통 금 가치에 부담입니다"))
            } else {
                reasons.append(LocalizedString.l(language, en: "U.S. 10Y yield changed little; macro rate impact is neutral", zh: "10年期美债收益率变化不大，宏观利率影响偏中性", ja: "米10年債利回りの変化は小さく、マクロ金利の影響は中立寄りです", ko: "미국 10년물 금리 변화가 크지 않아 매크로 금리 영향은 중립적입니다"))
            }
        } else {
            reasons.append(LocalizedString.l(language, en: "Treasury yield was unavailable; macro rate factor is treated as neutral", zh: "暂未获取到美债收益率，宏观利率项按中性处理", ja: "米国債利回りを取得できず、マクロ金利項目は中立として扱います", ko: "미국 국채 금리를 가져오지 못해 매크로 금리 항목은 중립으로 처리합니다"))
        }

        if abs(macroScore) >= 25 {
            reasons.append(macroScore > 0
                ? LocalizedString.l(language, en: "Rate factor is clearly bullish", zh: "利率项明显偏多", ja: "金利要因は明確に強気寄りです", ko: "금리 요인이 뚜렷하게 상승 우세입니다")
                : LocalizedString.l(language, en: "Rate factor is clearly bearish", zh: "利率项明显偏空", ja: "金利要因は明確に弱気寄りです", ko: "금리 요인이 뚜렷하게 하락 우세입니다"))
        }

        let strongestNews = newsItems
            .filter { abs($0.sentimentScore) > 0 }
            .sorted { abs($0.sentimentScore) > abs($1.sentimentScore) }
            .prefix(2)
            .map(\.title)

        if strongestNews.isEmpty {
            reasons.append(newsItems.isEmpty
                ? LocalizedString.l(language, en: "No news headlines were fetched; news factor is treated as neutral", zh: "暂未获取到新闻标题，新闻项按中性处理", ja: "ニュース見出しを取得できず、ニュース項目は中立として扱います", ko: "뉴스 제목을 가져오지 못해 뉴스 항목은 중립으로 처리합니다")
                : LocalizedString.l(language, en: "News headlines do not contain clear bullish or bearish keywords", zh: "新闻标题未出现明显多空关键词", ja: "ニュース見出しに明確な強弱キーワードはありません", ko: "뉴스 제목에 뚜렷한 상승/하락 키워드가 없습니다"))
        } else {
            reasons.append(contentsOf: strongestNews)
        }
        return Array(reasons.prefix(4))
    }
}

struct TreasuryYieldPoint: Sendable {
    let date: Date
    let tenYearYield: Double
}

private final class TreasuryYieldXMLParser: NSObject, XMLParserDelegate {
    private var points: [TreasuryYieldPoint] = []
    private var currentDateText: String?
    private var currentYieldText: String?
    private var activeElement = ""
    private var buffer = ""
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static func parse(data: Data) -> [TreasuryYieldPoint] {
        let delegate = TreasuryYieldXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.points
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = qName ?? elementName
        activeElement = name
        buffer = ""

        if name.hasSuffix("NEW_DATE") {
            currentDateText = nil
        } else if name.hasSuffix("BC_10YEAR") {
            currentYieldText = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard activeElement.hasSuffix("NEW_DATE") || activeElement.hasSuffix("BC_10YEAR") else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = qName ?? elementName
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.hasSuffix("NEW_DATE") {
            currentDateText = text
        } else if name.hasSuffix("BC_10YEAR") {
            currentYieldText = text
        } else if name == "entry",
                  let dateText = currentDateText,
                  let yieldText = currentYieldText,
                  let date = dateFormatter.date(from: dateText),
                  let tenYearYield = Double(yieldText) {
            points.append(TreasuryYieldPoint(date: date, tenYearYield: tenYearYield))
            currentDateText = nil
            currentYieldText = nil
        }

        buffer = ""
        activeElement = ""
    }
}

struct RSSParsedItem {
    let title: String
    let source: String?
    let link: URL?
    let publishedAt: Date?
}

final class GoldNewsRSSParser: NSObject, XMLParserDelegate {
    private var items: [RSSParsedItem] = []
    private var isInsideItem = false
    private var activeElement = ""
    private var buffer = ""
    private var title = ""
    private var source: String?
    private var linkText: String?
    private var pubDateText: String?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    static func parse(data: Data) -> [RSSParsedItem] {
        let delegate = GoldNewsRSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = qName ?? elementName
        activeElement = name
        buffer = ""

        if name == "item" {
            isInsideItem = true
            title = ""
            source = nil
            linkText = nil
            pubDateText = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = qName ?? elementName
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInsideItem {
            switch name {
            case "title":
                title = text
            case "source":
                source = text.isEmpty ? nil : text
            case "link":
                linkText = text
            case "pubDate":
                pubDateText = text
            case "item":
                if !title.isEmpty {
                    items.append(RSSParsedItem(
                        title: title,
                        source: source,
                        link: linkText.flatMap(URL.init(string:)),
                        publishedAt: pubDateText.flatMap { dateFormatter.date(from: $0) }
                    ))
                }
                isInsideItem = false
            default:
                break
            }
        }

        buffer = ""
        activeElement = ""
    }
}

private extension Double {
    nonisolated func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }

    nonisolated var oneDigitNumber: String {
        formatted(.number.precision(.fractionLength(1)))
    }
}
