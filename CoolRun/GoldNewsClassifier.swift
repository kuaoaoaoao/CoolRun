import Foundation

// MARK: - 新闻来源等级
//
// 来源表集中在 GoldNewsClassifier.swift，不得散落在 UI 和服务中。
// 来源等级只影响 confidence，不得改变一条证据本身的方向。

enum GoldNewsSourceTier: Int, Sendable, Equatable {
    case primary = 3
    case established = 2
    case secondary = 1
    case unknown = 0
}

// MARK: - 分类结果

struct GoldNewsClassification: Sendable, Equatable {
    let isFinanciallyRelevant: Bool
    let isGeopolitical: Bool
    let direction: GoldImpactDirection
    let sentimentScore: Double
    let matchedFacts: [GoldEvidenceKind]
    let sourceTier: GoldNewsSourceTier
}

// MARK: - 分类器
//
// 纯函数实现，不读 AppSettings.shared；人名、机构名和会场名只能作为实体，
// 不得单独代表方向；Warsh 不得命中 war。

enum GoldNewsClassifier {
    // MARK: 排除词（赛车、足球、奖杯等优先于包含词）

    private static let excludedSportsPhrases: [String] = [
        "gold cup", "racing", "speedway", "motorsport", "nascar", "formula 1",
        "f1 grand prix", "grand prix", "race results", "rally results",
        "赛程", "赛车", "杯赛", "足球", "联赛", "夺冠", "锦标赛"
    ]

    // MARK: 黄金市场路径词

    private static let goldAssetPhrases: [String] = [
        "黄金", "金价", "贵金属", "金条",
        "gold price", "gold market", "gold rises", "gold falls",
        "gold drops", "gold climbs", "gold jumps", "gold slides",
        "bullion", "xauusd", "xau/usd", "gold bullion"
    ]

    private static let financialContextPhrases: [String] = [
        "price", "market", "inflation", "rate", "yield", "yields",
        "fed", "federal reserve", "fomc", "central bank",
        "美元指数", "收益率", "避险", "通胀", "利率", "行情", "市场",
        "美联储", "央行", "货币政策"
    ]

    // MARK: 宏观事件路径词

    private static let policyEntityPhrases: [String] = [
        "fed", "federal reserve", "fomc", "美联储", "联邦储备", "央行",
        "欧洲央行", "日本央行", "英央行", "ecb", "boj", "central bank"
    ]

    private static let policyFactPhrases: [String] = [
        "inflation", "rate hike", "rate cut", "policy", "rates",
        "通胀", "加息", "降息", "货币政策", "利率", "鹰派", "鸽派"
    ]

    // MARK: 方向事实（仅这些贡献方向分，人名/机构/会场不在其中）

    private static let bearishPhrases: [String] = [
        "加息", "鹰派", "美元指数上涨", "美元指数上行", "收益率上行", "收益率上升",
        "金价下跌", "黄金下跌", "金价跳水", "黄金跳水",
        "rate hike", "hawkish", "dollar index rises", "dollar index strengthens",
        "dollar index climbs", "yields rise", "yields climb", "yields jump",
        "gold price falls", "gold falls", "gold drops", "gold slides",
        "higher yields", "stronger dollar"
    ]

    private static let bullishPhrases: [String] = [
        "降息", "鸽派", "美元指数下跌", "美元指数下行", "收益率下行", "收益率下降",
        "金价上涨", "黄金上涨", "避险需求", "金价反弹", "黄金反弹",
        "rate cut", "dovish", "dollar index falls", "dollar index weakens",
        "dollar index drops", "yields fall", "yields decline", "yields drop",
        "gold price rises", "gold rises", "gold climbs", "gold rebounds",
        "safe-haven demand", "safe haven demand", "lower yields", "weaker dollar"
    ]

    // MARK: 地缘事实

    private static let geopoliticalPhrases: [String] = [
        "战争", "冲突", "地缘", "war", "conflict", "geopolitical"
    ]

    // MARK: 否定窗口

    /// 否定词窗口至少覆盖目标短语前后各 24 个字符；
    /// 命中后该短语不计方向分。
    private static let negationPhrases: [String] = [
        "not", "no ", " unlikely", "undecided", "not decided", "rules out", "won't",
        "不会", "并未", "否认", "不考虑", "尚未决定", "未决定", "排除"
    ]

    private static let negationWindow = 24

    // MARK: 停用词（eventKey 用）

    private static let eventStopWords: Set<String> = [
        "as", "the", "a", "an", "of", "in", "on", "at", "to", "for", "and", "or",
        "称", "表示", "据悉", "称。"
    ]

    private static let entityPhrases: [String] = [
        "warsh", "powell", "fed", "federal reserve", "fomc", "jackson hole",
        "ecb", "boj", "yellen",
        "沃什", "鲍威尔", "美联储", "杰克逊霍尔", "耶伦"
    ]

    // MARK: - 入口

    nonisolated static func classify(title: String, source: String?) -> GoldNewsClassification {
        let normalized = title.lowercased()
        let normalizedWithSource = normalized + " " + (source ?? "").lowercased()
        let relevant = !hasExcludedSportsContext(normalized) && (
            (hasGoldAssetPhrase(normalized) && hasFinancialContext(normalized)) ||
            (hasPolicyEntity(normalizedWithSource) && hasPolicyFact(normalized))
        )
        guard relevant else {
            return GoldNewsClassification(
                isFinanciallyRelevant: false,
                isGeopolitical: false,
                direction: .neutral,
                sentimentScore: 0,
                matchedFacts: [],
                sourceTier: sourceTier(source)
            )
        }

        let bearishMatches = affirmedMatches(in: normalized, phrases: bearishPhrases)
        let bullishMatches = affirmedMatches(in: normalized, phrases: bullishPhrases)
        let bearish = !bearishMatches.isEmpty
        let bullish = !bullishMatches.isEmpty
        let geopolitical = containsWholePhrase(
            in: normalized,
            phrases: geopoliticalPhrases
        )

        let direction: GoldImpactDirection =
            bearish == bullish ? .neutral : (bearish ? .bearish : .bullish)

        return GoldNewsClassification(
            isFinanciallyRelevant: true,
            isGeopolitical: geopolitical,
            direction: direction,
            sentimentScore: makeSentimentScore(
                bearishMatches: bearishMatches,
                bullishMatches: bullishMatches
            ),
            matchedFacts: matchedKinds(
                in: normalized,
                bearishMatches: bearishMatches,
                bullishMatches: bullishMatches
            ),
            sourceTier: sourceTier(source)
        )
    }

    // MARK: - 来源等级

    nonisolated static func sourceTier(_ source: String?) -> GoldNewsSourceTier {
        let normalized = source?.lowercased() ?? ""
        if normalized.isEmpty { return .unknown }

        // 官方机构：primary
        let primarySources = [
            "federal reserve", "fomc", "美联储官方", "us treasury", "美国财政部",
            "欧洲央行", "日本央行"
        ]
        if primarySources.contains(where: { normalized.contains($0) }) {
            return .primary
        }

        // 主要通讯社与主流财经媒体：established
        let establishedSources = [
            "reuters", "associated press", " bloomberg", "bloomberg news",
            "证券时报", "凤凰财经", "凤凰网", "华尔街见闻", "财联社", "新华社",
            "中国证券报", "上海证券报", "第一财经", "financial times", "nikkei",
            "cnbc", "wall street journal", "wsj", "yahoo finance"
        ]
        if establishedSources.contains(where: { normalized.contains($0) }) {
            return .established
        }

        // 次级财经站点：secondary
        let secondarySources = [
            "新浪财经", "东方财富", "同花顺", "和讯", "金十", "investing.com",
            "marketwatch", "seeking alpha", "fxstreet", "chinamoney",
            "eeo.com.cn", "chnfund.com", "搜狐财经", "网易财经", "腾讯财经"
        ]
        if secondarySources.contains(where: { normalized.contains($0) }) {
            return .secondary
        }

        return .unknown
    }

    // MARK: - 事件键

    /// 处理顺序固定：小写 → 去来源后缀 → 去标点 → 合并空白 →
    /// 去停用词/纯数字 token → 排序连接。
    nonisolated static func eventKey(title: String) -> String {
        var text = title.lowercased()

        // 去掉常见来源后缀
        let sourceSuffixes = [
            " - reuters", " | yahoo finance", " - bloomberg", " - cnbc",
            " - wall street journal", " - associated press", " - 证券时报",
            " - 凤凰网", " - 凤凰财经", " - 华尔街见闻", " - 财联社", " - 新浪财经",
            " - 东方财富"
        ]
        for suffix in sourceSuffixes where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
            break
        }

        // 去标点、合并空白
        let tokens = text
            .replacingOccurrences(
                of: #"[^\p{L}\p{N}\s]"#,
                with: " ",
                options: .regularExpression
            )
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                !token.isEmpty
                    && !eventStopWords.contains(token)
                    && !isPureNumber(token)
            }

        return tokens.sorted().joined(separator: " ")
    }

    // MARK: - 聚类去重
    //
    // - eventKey 相同只保留一条。
    // - 优先 sourceTier 高的条目。
    // - 同等级优先发布时间更新且链接存在的条目。
    // - 同一 48 小时窗口内，主体实体相同且内容 token 的 Jaccard 相似度 >= 0.72
    //   时也归为同一事件（阈值固定，不随标题条数变化）。

    nonisolated static func deduplicate(items: [GoldNewsItem]) -> [GoldNewsItem] {
        var accepted: [GoldNewsItem] = []

        for item in items.sorted(by: preferredOrder) {
            let isDuplicate = accepted.contains { existing in
                isSameEvent(item, existing)
            }
            if !isDuplicate {
                accepted.append(item)
            }
        }

        return accepted
    }

    // MARK: - 私有辅助

    private nonisolated static func preferredOrder(_ lhs: GoldNewsItem, _ rhs: GoldNewsItem) -> Bool {
        if lhs.sourceTier != rhs.sourceTier {
            return lhs.sourceTier.rawValue > rhs.sourceTier.rawValue
        }
        let lhsHasLink = lhs.link != nil
        let rhsHasLink = rhs.link != nil
        if lhsHasLink != rhsHasLink {
            return lhsHasLink
        }
        return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
    }

    private nonisolated static func isSameEvent(_ lhs: GoldNewsItem, _ rhs: GoldNewsItem) -> Bool {
        if lhs.eventKey == rhs.eventKey, !lhs.eventKey.isEmpty {
            return true
        }

        // 48 小时窗口
        switch (lhs.publishedAt, rhs.publishedAt) {
        case let (l?, r?):
            guard abs(l.timeIntervalSince(r)) <= 48 * 3600 else { return false }
        default:
            return false
        }

        // 主体实体相同且 Jaccard >= 0.72
        let lhsEntities = entities(in: lhs.title.lowercased())
        let rhsEntities = entities(in: rhs.title.lowercased())
        guard !lhsEntities.isEmpty, !lhsEntities.isEmpty,
              !lhsEntities.isDisjoint(with: rhsEntities) else {
            return false
        }

        let lhsTokens = Set(lhs.eventKey.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.eventKey.split(separator: " ").map(String.init))
        return jaccard(lhsTokens, rhsTokens) >= 0.72
    }

    private nonisolated static func entities(in text: String) -> Set<String> {
        var result: Set<String> = []
        for phrase in entityPhrases where text.contains(phrase) {
            result.insert(phrase)
        }
        return result
    }

    private nonisolated static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private nonisolated static func isPureNumber(_ token: String) -> Bool {
        token.allSatisfy { $0.isNumber }
    }

    private nonisolated static func hasExcludedSportsContext(_ text: String) -> Bool {
        excludedSportsPhrases.contains { text.contains($0) }
    }

    private nonisolated static func hasGoldAssetPhrase(_ text: String) -> Bool {
        goldAssetPhrases.contains { text.contains($0) }
    }

    private nonisolated static func hasFinancialContext(_ text: String) -> Bool {
        financialContextPhrases.contains { text.contains($0) }
    }

    private nonisolated static func hasPolicyEntity(_ text: String) -> Bool {
        policyEntityPhrases.contains { containsWholePhrase(in: text, single: $0) }
    }

    private nonisolated static func hasPolicyFact(_ text: String) -> Bool {
        policyFactPhrases.contains { text.contains($0) }
    }

    /// 英文短语使用词边界匹配；中文短语退化为 contains。
    private nonisolated static func containsWholePhrase(
        in text: String,
        phrases: [String]
    ) -> Bool {
        phrases.contains { containsWholePhrase(in: text, single: $0) }
    }

    private nonisolated static func containsWholePhrase(
        in text: String,
        single phrase: String
    ) -> Bool {
        let isAsciiWord = phrase.allSatisfy { $0.isASCII && $0.isLetter }
        guard isAsciiWord else {
            return text.contains(phrase)
        }
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        ) else {
            return text.contains(phrase)
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// 返回通过否定窗口确认的短语出现（每个短语只计一次）。
    private nonisolated static func affirmedMatches(
        in text: String,
        phrases: [String]
    ) -> [String] {
        phrases.filter { phrase in
            guard let range = text.range(of: phrase) else { return false }
            let start = text.index(
                range.lowerBound,
                offsetBy: -min(negationWindow, text.distance(from: text.startIndex, to: range.lowerBound)),
                limitedBy: text.startIndex
            ) ?? text.startIndex
            let end = text.index(
                range.upperBound,
                offsetBy: min(negationWindow, text.distance(from: range.upperBound, to: text.endIndex)),
                limitedBy: text.endIndex
            ) ?? text.endIndex
            let window = String(text[start..<end])
            return !negationPhrases.contains { negation in
                window.contains(negation)
            }
        }
    }

    /// 每个独立方向事实贡献 18 分，范围限制在 -54...54。
    /// 人名、机构、地点和单独的 inflation 不贡献分数。
    private nonisolated static func makeSentimentScore(
        bearishMatches: [String],
        bullishMatches: [String]
    ) -> Double {
        let score = Double(bullishMatches.count - bearishMatches.count) * 18
        return min(max(score, -54), 54)
    }

    /// 只使用已经通过词边界和否定窗口确认的事实。
    private nonisolated static func matchedKinds(
        in text: String,
        bearishMatches: [String],
        bullishMatches: [String]
    ) -> [GoldEvidenceKind] {
        var kinds: [GoldEvidenceKind] = []
        let all = bearishMatches + bullishMatches

        if all.contains(where: { $0.contains("加息") || $0.contains("降息") || $0.contains("鹰派") || $0.contains("鸽派") || $0.contains("rate hike") || $0.contains("rate cut") || $0.contains("hawkish") || $0.contains("dovish") }) {
            kinds.append(.centralBankStatement)
        }
        if all.contains(where: { $0.contains("收益率") || $0.contains("yields") || $0.contains("yield") }) {
            kinds.append(.treasuryYield)
        }
        if all.contains(where: { $0.contains("美元") || $0.contains("dollar") }) {
            kinds.append(.dollar)
        }
        if all.contains(where: { $0.contains("金价") || $0.contains("黄金") || $0.contains("gold") }) {
            kinds.append(.goldPrice)
        }
        if containsWholePhrase(in: text, phrases: geopoliticalPhrases) {
            kinds.append(.geopolitical)
        }
        if kinds.isEmpty, !all.isEmpty {
            kinds.append(.mediaReport)
        }
        return kinds
    }
}
