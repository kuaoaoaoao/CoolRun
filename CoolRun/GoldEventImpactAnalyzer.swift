import Foundation

// MARK: - 分析器输入
//
// dataState 由 GoldMarketIntelligenceService 根据各数据源是否成功以及数据年龄计算；
// 分析器不自行猜测“缓存是否陈旧”。

struct GoldEventImpactInput: Sendable {
    let newsItems: [GoldNewsItem]
    let macro: GoldMacroSnapshot?
    let globalSnapshot: GoldGlobalSnapshot?
    let dataState: GoldIntelligenceDataState
    let now: Date
}

// MARK: - 事件影响分析器
//
// 纯函数分析器：从聚类后的新闻、美债和全球市场快照生成 GoldEventImpact。
// 每个事件对黄金的短线方向、证据强度、波动风险、证据链和反方风险；
// 不生成独立交易动作。

enum GoldEventImpactAnalyzer {
    // 方向阈值：bearish <= -0.25，bullish >= 0.25
    private static let directionThreshold = 0.25

    // 收益率证据阈值：|bps| >= 2
    private static let yieldEvidenceBps = 2.0

    // 金价证据阈值：|涨跌幅| >= 0.3%
    private static let goldPriceEvidenceRatio = 0.003

    nonisolated static func analyze(
        _ input: GoldEventImpactInput,
        language: AppLanguage
    ) -> GoldEventImpact {
        guard input.dataState != .unavailable else {
            return .unavailable(now: input.now, language: language)
        }

        let news = GoldNewsClassifier.deduplicate(items: input.newsItems)
        let observed = makeObservedEvidence(
            news: news,
            macro: input.macro,
            global: input.globalSnapshot,
            now: input.now,
            language: language
        )
        guard !observed.isEmpty else {
            return .unavailable(now: input.now, language: language)
        }

        let direction = aggregateDirection(observed, now: input.now)
        let confidence = makeConfidence(
            evidence: observed,
            direction: direction,
            dataState: input.dataState,
            now: input.now
        )
        let inferred = makeInferences(
            from: observed,
            direction: direction,
            language: language
        )

        return .make(
            direction: direction,
            confidence: confidence,
            volatilityRisk: makeVolatilityRisk(observed, direction: direction),
            headline: makeHeadline(direction, confidence, language),
            evidence: observed + inferred,
            counterRisks: makeCounterRisks(
                direction,
                observed: observed,
                language: language
            ),
            updatedAt: input.now,
            dataState: input.dataState,
            language: language
        )
    }

    // MARK: - Observed 证据

    private nonisolated static func makeObservedEvidence(
        news: [GoldNewsItem],
        macro: GoldMacroSnapshot?,
        global: GoldGlobalSnapshot?,
        now: Date,
        language: AppLanguage
    ) -> [GoldEventEvidence] {
        var evidence: [GoldEventEvidence] = []

        // 媒体证据：每条去重后的新闻一个节点
        for (index, item) in news.enumerated() {
            let classification = GoldNewsClassifier.classify(
                title: item.title,
                source: item.source
            )
            guard classification.isFinanciallyRelevant,
                  classification.direction != .neutral else { continue }
            evidence.append(GoldEventEvidence(
                id: "news-\(index)-\(item.eventKey.isEmpty ? String(index) : item.eventKey)",
                kind: primaryKind(for: classification),
                state: .observed,
                direction: classification.direction,
                summary: item.title,
                source: item.source,
                link: item.link,
                observedAt: item.publishedAt
            ))
        }

        // 美债收益率证据：有变化幅度才有方向
        if let changeBps = macro?.tenYearYieldChangeBps, abs(changeBps) >= yieldEvidenceBps {
            let direction: GoldImpactDirection = changeBps > 0 ? .bearish : .bullish
            evidence.append(GoldEventEvidence(
                id: "macro-yield",
                kind: .treasuryYield,
                state: .observed,
                direction: direction,
                summary: LocalizedString.l(
                    language,
                    en: changeBps > 0
                        ? "U.S. 10Y Treasury yield rose \(oneDigit(changeBps))bp"
                        : "U.S. 10Y Treasury yield fell \(oneDigit(abs(changeBps)))bp",
                    zh: changeBps > 0
                        ? "10年期美债收益率上行 \(oneDigit(changeBps))bp"
                        : "10年期美债收益率回落 \(oneDigit(abs(changeBps)))bp",
                    ja: changeBps > 0
                        ? "米10年債利回りが \(oneDigit(changeBps))bp 上昇"
                        : "米10年債利回りが \(oneDigit(abs(changeBps)))bp 低下",
                    ko: changeBps > 0
                        ? "미국 10년물 금리 \(oneDigit(changeBps))bp 상승"
                        : "미국 10년물 금리 \(oneDigit(abs(changeBps)))bp 하락"
                ),
                source: nil,
                link: nil,
                observedAt: macro?.observedAt
            ))
        }

        // 金价证据：需要昨收前值
        if let xauUsd = global?.xauUsd,
           let prevClose = global?.xauPrevClose,
           prevClose > 0 {
            let ratio = (xauUsd - prevClose) / prevClose
            if abs(ratio) >= goldPriceEvidenceRatio {
                let direction: GoldImpactDirection = ratio > 0 ? .bullish : .bearish
                let percent = oneDigit(ratio * 100)
                evidence.append(GoldEventEvidence(
                    id: "global-xau",
                    kind: .goldPrice,
                    state: .observed,
                    direction: direction,
                    summary: LocalizedString.l(
                        language,
                        en: "XAUUSD moved \(percent)% on the day",
                        zh: "XAUUSD 当日变动 \(percent)%",
                        ja: "XAUUSD 本日 \(percent)% 変動",
                        ko: "XAUUSD 당일 \(percent)% 변동"
                    ),
                    source: nil,
                    link: nil,
                    observedAt: global?.updatedAt
                ))
            }
        }

        // 注意：dollarIndex 只有当前值、没有前值时，不生成 dollar 方向证据。

        return evidence
    }

    /// 媒体证据的主事实类型。
    private nonisolated static func primaryKind(
        for classification: GoldNewsClassification
    ) -> GoldEvidenceKind {
        if classification.isGeopolitical { return .geopolitical }
        if classification.matchedFacts.contains(.centralBankStatement) {
            return .centralBankStatement
        }
        if let market = classification.matchedFacts.first(where: {
            $0 == .treasuryYield || $0 == .dollar || $0 == .goldPrice
        }) {
            return market
        }
        return .mediaReport
    }

    // MARK: - 方向聚合

    /// 方向总分除以有效事件权重总和，最终范围固定为 -1...1。
    private nonisolated static func aggregateDirection(
        _ evidence: [GoldEventEvidence],
        now: Date
    ) -> GoldImpactDirection {
        struct Contribution {
            let value: Double
            let weight: Double
        }

        var contributions: [Contribution] = []

        // 媒体事件：tier 权重 × recency 权重，单事件绝对贡献上限 1.0
        let mediaKinds: Set<GoldEvidenceKind> = [
            .centralBankStatement, .policyExpectation, .mediaReport, .geopolitical
        ]
        let tierWeights: [GoldNewsSourceTier: Double] = [
            .primary: 1.0, .established: 0.8, .secondary: 0.5, .unknown: 0.25
        ]
        for item in evidence where mediaKinds.contains(item.kind) {
            guard let directionValue = directionValue(for: item.direction) else { continue }
            let sourceTier = GoldNewsClassifier.sourceTier(item.source)
            let tierWeight = tierWeights[sourceTier] ?? 0.25

            let recencyWeight: Double
            if let observedAt = item.observedAt {
                let ageHours = max(0, now.timeIntervalSince(observedAt) / 3600)
                if ageHours <= 24 {
                    recencyWeight = 1.0
                } else if ageHours <= 72 {
                    recencyWeight = 1.0 - (ageHours - 24) / 48.0 * 0.6
                } else {
                    recencyWeight = 0.4
                }
            } else {
                recencyWeight = 0.35
            }

            let raw = directionValue * tierWeight * recencyWeight
            contributions.append(Contribution(
                value: min(max(raw, -1.0), 1.0),
                weight: 1.0
            ))
        }

        // 市场维度证据：固定权重 1.0
        for item in evidence where !mediaKinds.contains(item.kind) {
            guard let directionValue = directionValue(for: item.direction) else { continue }
            contributions.append(Contribution(value: directionValue, weight: 1.0))
        }

        guard !contributions.isEmpty else { return .neutral }
        let totalWeight = contributions.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return .neutral }
        let score = contributions.map { $0.value * $0.weight }.reduce(0, +) / totalWeight

        if score <= -directionThreshold { return .bearish }
        if score >= directionThreshold { return .bullish }
        return .neutral
    }

    private nonisolated static func directionValue(
        for direction: GoldImpactDirection
    ) -> Double? {
        switch direction {
        case .bearish: return -1.0
        case .bullish: return 1.0
        case .neutral: return nil
        }
    }

    /// 一位小数格式化（仅供本文件摘要使用）。
    private nonisolated static func oneDigit(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - 置信度

    private nonisolated static func makeConfidence(
        evidence: [GoldEventEvidence],
        direction: GoldImpactDirection,
        dataState: GoldIntelligenceDataState,
        now: Date
    ) -> GoldImpactConfidence {
        let observed = evidence.filter { $0.state == .observed }
        let agreeingKinds = Set(
            observed
                .filter { $0.direction == direction }
                .map(\.kind)
        )
        let hasContradiction = observed.contains {
            directionValue(for: $0.direction) != nil && $0.direction != direction
        }
        let marketKinds: Set<GoldEvidenceKind> = [.treasuryYield, .goldPrice, .dollar]
        let agreeingMarketKinds = agreeingKinds.intersection(marketKinds)

        var confidence: GoldImpactConfidence
        if agreeingKinds.isEmpty {
            confidence = .unavailable
        } else if agreeingKinds.count >= 3 && !agreeingMarketKinds.isEmpty {
            confidence = .high
        } else if agreeingKinds.count >= 2 {
            confidence = .medium
        } else {
            // 只凭媒体标题最多 low confidence
            confidence = .low
        }

        // 矛盾证据：市场数据未确认媒体方向，置信度至多 low
        if hasContradiction, confidence > .low {
            confidence = .low
        }

        // dataState == partial 时 confidence 最高为 low
        if dataState == .partial, confidence > .low {
            confidence = .low
        }

        // dataState == stale 时 confidence 至少下降一级且最高为 medium
        if dataState == .stale {
            if confidence > .medium {
                confidence = .medium
            }
            confidence = downgrade(confidence)
        }

        return confidence
    }

    private nonisolated static func downgrade(_ confidence: GoldImpactConfidence) -> GoldImpactConfidence {
        switch confidence {
        case .high: return .medium
        case .medium: return .low
        case .low, .unavailable: return .unavailable
        }
    }

    // MARK: - 波动风险

    /// 波动风险与方向独立；地缘事件可以 bullish 且 high risk。
    private nonisolated static func makeVolatilityRisk(
        _ evidence: [GoldEventEvidence],
        direction: GoldImpactDirection
    ) -> GoldVolatilityRisk {
        let observed = evidence.filter { $0.state == .observed }
        if observed.contains(where: { $0.kind == .geopolitical }) {
            return .high
        }
        let agreeingKinds = Set(observed.filter { $0.direction == direction }.map(\.kind))
        if agreeingKinds.count >= 3 {
            return .elevated
        }
        let hasContradiction = observed.contains { $0.direction != direction }
        if hasContradiction {
            return .elevated
        }
        return .normal
    }

    // MARK: - 推断（受限）

    /// inferred 证据只能基于已有 observed 节点生成；
    /// 只有新闻、没有收益率/价格/美元确认时，不得生成资金流入流出。
    private nonisolated static func makeInferences(
        from observed: [GoldEventEvidence],
        direction: GoldImpactDirection,
        language: AppLanguage
    ) -> [GoldEventEvidence] {
        var inferred: [GoldEventEvidence] = []

        let hasCentralBankBearish = observed.contains {
            $0.kind == .centralBankStatement && $0.direction == .bearish
        }
        let hasYieldBearish = observed.contains {
            $0.kind == .treasuryYield && $0.direction == .bearish
        }
        if hasCentralBankBearish, hasYieldBearish {
            inferred.append(GoldEventEvidence(
                id: "inferred-rate-cost",
                kind: .policyExpectation,
                state: .inferred,
                direction: .bearish,
                summary: LocalizedString.l(
                    language,
                    en: "The rate environment may raise the opportunity cost of holding non-yielding assets",
                    zh: "利率环境可能提高持有无息资产的机会成本",
                    ja: "金利環境は無利子資産の保有機会コストを引き上げる可能性があります",
                    ko: "금리 환경은 무이자 자산 보유의 기회비용을 높일 수 있습니다"
                ),
                source: nil,
                link: nil,
                observedAt: nil
            ))
        }

        let hasGeopoliticalBullish = observed.contains {
            $0.kind == .geopolitical && $0.direction == .bullish
        }
        if hasGeopoliticalBullish {
            inferred.append(GoldEventEvidence(
                id: "inferred-safe-haven",
                kind: .geopolitical,
                state: .inferred,
                direction: .bullish,
                summary: LocalizedString.l(
                    language,
                    en: "Safe-haven demand may support gold",
                    zh: "避险需求可能支撑黄金",
                    ja: "安全資産需要が金を支える可能性があります",
                    ko: "안전자산 수요가 금을 지지할 수 있습니다"
                ),
                source: nil,
                link: nil,
                observedAt: nil
            ))
        }

        return inferred
    }

    // MARK: - 标题

    /// headline 只能概括已有证据，不能出现未观测到的具体概率或价格变化，
    /// 更不能出现买卖动作。
    private nonisolated static func makeHeadline(
        _ direction: GoldImpactDirection,
        _ confidence: GoldImpactConfidence,
        _ language: AppLanguage
    ) -> String {
        switch direction {
        case .bearish:
            return LocalizedString.l(
                language,
                en: confidence >= .medium
                    ? "Short-term bearish: policy and market data align"
                    : "Short-term bearish on limited evidence",
                zh: confidence >= .medium
                    ? "短线偏空：政策与市场数据相互印证"
                    : "短线偏空：证据有限",
                ja: confidence >= .medium
                    ? "短期的に弱気：政策と市場データが一致"
                    : "短期的に弱気：証拠は限定的",
                ko: confidence >= .medium
                    ? "단기 약세: 정책과 시장 데이터가 부합"
                    : "단기 약세: 근거 제한적"
            )
        case .bullish:
            return LocalizedString.l(
                language,
                en: confidence >= .medium
                    ? "Short-term bullish: policy and market data align"
                    : "Short-term bullish on limited evidence",
                zh: confidence >= .medium
                    ? "短线偏多：政策与市场数据相互印证"
                    : "短线偏多：证据有限",
                ja: confidence >= .medium
                    ? "短期的に強気：政策と市場データが一致"
                    : "短期的に強気：証拠は限定的",
                ko: confidence >= .medium
                    ? "단기 강세: 정책과 시장 데이터가 부합"
                    : "단기 강세: 근거 제한적"
            )
        case .neutral:
            return LocalizedString.l(
                language,
                en: "No clear direction: evidence is mixed or insufficient",
                zh: "方向不明：证据冲突或不足",
                ja: "方向感なし：証拠が混在または不足",
                ko: "방향 불명확: 근거 혼재 또는 부족"
            )
        }
    }

    // MARK: - 反方风险

    private nonisolated static func makeCounterRisks(
        _ direction: GoldImpactDirection,
        observed: [GoldEventEvidence],
        language: AppLanguage
    ) -> [String] {
        var risks: [String] = []

        let hasContradiction = observed.contains {
            directionValue(for: $0.direction) != nil && $0.direction != direction
        }
        if hasContradiction {
            risks.append(LocalizedString.l(
                language,
                en: "Market data has not confirmed the media direction",
                zh: "市场数据未确认媒体方向",
                ja: "市場データがメディアの方向性を確認していません",
                ko: "시장 데이터가 미디어 방향성을 확인하지 못했습니다"
            ))
        }

        if observed.contains(where: { $0.kind == .geopolitical }) {
            risks.append(LocalizedString.l(
                language,
                en: "Geopolitical premium can fade quickly once tensions ease",
                zh: "地缘紧张缓和后，地缘溢价可能快速回吐",
                ja: "緊張緩和後、地政学プレミアムは急速に縮小する可能性があります",
                ko: "긴장 완화 후 지정학 프리미엄은 빠르게 축소될 수 있습니다"
            ))
        }

        if risks.isEmpty {
            risks.append(LocalizedString.l(
                language,
                en: "Markets may have already priced this in; incoming data could reverse the move",
                zh: "市场可能已快速定价，后续数据可能逆转走势",
                ja: "市場はすでに織り込んだ可能性があり、今後のデータで反転するおそれがあります",
                ko: "시장이 이미 반영했을 수 있으며, 향후 데이터로 반전 가능성이 있습니다"
            ))
        }

        return risks
    }
}
