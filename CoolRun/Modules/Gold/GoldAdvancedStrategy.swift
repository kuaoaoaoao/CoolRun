import Foundation

enum GoldStrategyVersion {
    nonisolated static let current = "gold-rules-2026.07.17.2"
}

struct GoldStrategyCalibration: Equatable, Sendable {
    nonisolated static let neutral = GoldStrategyCalibration(
        confidenceMultiplier: 1,
        exposureMultiplier: 1,
        note: "样本积累中，暂不自动调参"
    )

    let confidenceMultiplier: Double
    let exposureMultiplier: Double
    let note: String

    var isNeutral: Bool {
        abs(confidenceMultiplier - 1) < 0.001 && abs(exposureMultiplier - 1) < 0.001
    }
}

enum MarketRegime: String, CaseIterable, Sendable {
    case strongUptrend = "强势上涨"
    case weakUptrend = "温和上涨"
    case ranging = "震荡整理"
    case weakDowntrend = "温和下跌"
    case strongDowntrend = "强势下跌"

    var displayName: String {
        switch self {
        case .strongUptrend: return LocalizedString.gold("strong_uptrend")
        case .weakUptrend: return LocalizedString.gold("weak_uptrend")
        case .ranging: return LocalizedString.gold("ranging")
        case .weakDowntrend: return LocalizedString.gold("weak_downtrend")
        case .strongDowntrend: return LocalizedString.gold("strong_downtrend")
        }
    }

    var strategyLabel: String {
        switch self {
        case .strongUptrend, .weakUptrend:
            LocalizedString.gold("trend_follow")
        case .ranging:
            LocalizedString.gold("mean_reversion")
        case .weakDowntrend, .strongDowntrend:
            LocalizedString.gold("defensive")
        }
    }

    nonisolated var fallbackStrategyLabel: String {
        switch self {
        case .strongUptrend, .weakUptrend:
            "趋势跟随"
        case .ranging:
            "均值回归/网格观察"
        case .weakDowntrend, .strongDowntrend:
            "防守观察"
        }
    }
}

enum VolatilityRegime: String, Sendable {
    case low = "低波动"
    case normal = "正常波动"
    case high = "高波动"
    case extreme = "极端波动"

    var displayName: String {
        switch self {
        case .low: return LocalizedString.gold("vol_low")
        case .normal: return LocalizedString.gold("vol_normal")
        case .high: return LocalizedString.gold("vol_high")
        case .extreme: return LocalizedString.gold("vol_extreme")
        }
    }
}

struct MarketRegimeReport: Sendable {
    let regime: MarketRegime
    let trendScore: Double
    let rangingScore: Double
    let volatilityRegime: VolatilityRegime
    let hurstExponent: Double
    let adx: Double
    let confidence: Double
}

struct MeanReversionReport: Sendable {
    let zScore: Double
    let halfLife: Double?
    let mean: Double
    let standardDeviation: Double
    let direction: SignalDirection
    let confidence: Double
    let summary: String
}

struct MonteCarloForecast: Sendable {
    let expectedPrice: Double
    let expectedReturn: Double
    let probabilityAboveCurrent: Double
    let p10: Double
    let p50: Double
    let p90: Double
    let forecastSteps: Int
    let simulationCount: Int
}

struct GridStrategyPlan: Sendable {
    let lowerPrice: Double
    let upperPrice: Double
    let gridCount: Int
    let spacing: Double
    let isSuitable: Bool
}

struct RiskSummary: Sendable {
    let suggestedExposure: Double
    let maxSingleMoveRisk: Double
    let riskLevel: String
    let warning: String?
}

struct GoldAdvancedStrategyReport: Sendable {
    let strategyVersion: String
    let regime: MarketRegimeReport
    let meanReversion: MeanReversionReport?
    let forecast: MonteCarloForecast?
    let grid: GridStrategyPlan?
    let risk: RiskSummary
    let technicalOpportunity: Double
    let marketContext: GoldMarketContext?
    let calibration: GoldStrategyCalibration
    let compositeDirection: SignalDirection
    let confidence: Double
    let beginnerAction: String
    let beginnerReason: String
    let beginnerTone: BeginnerTone
    let summary: String
}

enum BeginnerTone: Sendable {
    case positive
    case cautious
    case defensive
}

enum GoldAdvancedStrategy {
    nonisolated static func analyze(
        records: [GoldPriceRecord],
        snapshot: TechnicalSnapshot,
        signal: TradingSignal?,
        marketContext: GoldMarketContext? = nil,
        calibration: GoldStrategyCalibration = .neutral
    ) -> GoldAdvancedStrategyReport? {
        let prices = records.map(\.price)
        guard prices.count >= 20, prices.last != nil else { return nil }

        let regime = detectRegime(prices: prices)
        let meanReversion = analyzeMeanReversion(prices: prices)
        let forecast = simulateMonteCarlo(prices: prices, forecastSteps: 7, simulations: 700)
        let technicalOpportunity = scoreTechnicalOpportunity(prices: prices, snapshot: snapshot)
        let grid = buildGridPlan(prices: prices, snapshot: snapshot, regime: regime)
        let risk = buildRiskSummary(
            prices: prices,
            regime: regime,
            signal: signal,
            forecast: forecast,
            technicalOpportunity: technicalOpportunity,
            marketContext: marketContext,
            calibration: calibration
        )
        let composite = buildCompositeDecision(
            regime: regime,
            meanReversion: meanReversion,
            forecast: forecast,
            signal: signal,
            technicalOpportunity: technicalOpportunity,
            marketContext: marketContext,
            calibration: calibration
        )
        let beginner = buildBeginnerGuidance(
            regime: regime,
            risk: risk,
            forecast: forecast,
            composite: composite,
            technicalOpportunity: technicalOpportunity,
            marketContext: marketContext
        )

        return GoldAdvancedStrategyReport(
            strategyVersion: GoldStrategyVersion.current,
            regime: regime,
            meanReversion: meanReversion,
            forecast: forecast,
            grid: grid,
            risk: risk,
            technicalOpportunity: technicalOpportunity,
            marketContext: marketContext,
            calibration: calibration,
            compositeDirection: composite.direction,
            confidence: composite.confidence,
            beginnerAction: beginner.action,
            beginnerReason: beginner.reason,
            beginnerTone: beginner.tone,
            summary: composite.summary
        )
    }

    private nonisolated static func detectRegime(prices: [Double]) -> MarketRegimeReport {
        let trendScore = calculateTrendScore(prices: prices)
        let rangingScore = calculateRangingScore(prices: prices)
        let volatilityRegime = detectVolatilityRegime(prices: prices)
        let hurst = calculateHurstExponent(prices: prices)
        let adx = calculateADX(prices: prices)

        let regime: MarketRegime
        if abs(trendScore) > 0.58 && adx > 24 {
            regime = trendScore > 0 ? .strongUptrend : .strongDowntrend
        } else if abs(trendScore) > 0.28 && adx > 18 {
            regime = trendScore > 0 ? .weakUptrend : .weakDowntrend
        } else {
            regime = .ranging
        }

        let confidence = [
            min(abs(trendScore) * 1.4, 1),
            min(abs(hurst - 0.5) * 3.6, 1),
            min(adx / 46, 1),
            rangingScore
        ].reduce(0, +) / 4

        return MarketRegimeReport(
            regime: regime,
            trendScore: trendScore,
            rangingScore: rangingScore,
            volatilityRegime: volatilityRegime,
            hurstExponent: hurst,
            adx: adx,
            confidence: confidence
        )
    }

    private nonisolated static func analyzeMeanReversion(prices: [Double]) -> MeanReversionReport? {
        let lookback = min(20, prices.count)
        guard lookback >= 10, let currentPrice = prices.last else { return nil }

        let recent = Array(prices.suffix(lookback))
        let mean = recent.reduce(0, +) / Double(recent.count)
        let variance = recent.reduce(0) { $0 + pow($1 - mean, 2) } / Double(recent.count)
        let standardDeviation = sqrt(variance)
        guard standardDeviation > 0 else { return nil }

        let zScore = (currentPrice - mean) / standardDeviation
        let direction: SignalDirection
        let confidence: Double
        let summary: String

        if zScore <= -1.8 {
            direction = .buy
            confidence = min(abs(zScore) / 3, 1)
            summary = "价格低于动态均值，存在回归观察点"
        } else if zScore >= 1.8 {
            direction = .sell
            confidence = min(abs(zScore) / 3, 1)
            summary = "价格高于动态均值，需留意回落"
        } else if abs(zScore) <= 0.5 {
            direction = .hold
            confidence = 0.65
            summary = "价格贴近均值，回归空间有限"
        } else {
            direction = .hold
            confidence = 0.35
            summary = "价格偏离不明显，均值回归信号较弱"
        }

        return MeanReversionReport(
            zScore: zScore,
            halfLife: calculateHalfLife(prices: Array(prices.suffix(min(prices.count, 40)))),
            mean: mean,
            standardDeviation: standardDeviation,
            direction: direction,
            confidence: confidence,
            summary: summary
        )
    }

    private nonisolated static func simulateMonteCarlo(
        prices: [Double],
        forecastSteps: Int,
        simulations: Int
    ) -> MonteCarloForecast? {
        let returns = logReturns(prices: prices)
        guard returns.count >= 12, let currentPrice = prices.last else { return nil }

        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(returns.count - 1, 1))
        let sigma = sqrt(variance)
        guard sigma.isFinite else { return nil }

        var rng = SeededRandom(seed: UInt64(prices.count) &* 1_315_423_911)
        var finalPrices: [Double] = []
        finalPrices.reserveCapacity(simulations)

        for _ in 0..<simulations {
            var price = currentPrice
            for _ in 0..<forecastSteps {
                let randomShock = rng.nextGaussian()
                price *= exp((mean - 0.5 * sigma * sigma) + sigma * randomShock)
            }
            finalPrices.append(price)
        }

        finalPrices.sort()
        guard let first = finalPrices.first, let last = finalPrices.last, first > 0, last > 0 else { return nil }

        let expectedPrice = finalPrices.reduce(0, +) / Double(finalPrices.count)
        let probabilityAboveCurrent = Double(finalPrices.filter { $0 > currentPrice }.count) / Double(finalPrices.count)

        return MonteCarloForecast(
            expectedPrice: expectedPrice,
            expectedReturn: (expectedPrice - currentPrice) / currentPrice,
            probabilityAboveCurrent: probabilityAboveCurrent,
            p10: percentile(finalPrices, 0.10),
            p50: percentile(finalPrices, 0.50),
            p90: percentile(finalPrices, 0.90),
            forecastSteps: forecastSteps,
            simulationCount: simulations
        )
    }

    private nonisolated static func buildGridPlan(
        prices: [Double],
        snapshot: TechnicalSnapshot,
        regime: MarketRegimeReport
    ) -> GridStrategyPlan? {
        guard let currentPrice = prices.last else { return nil }
        let recent = Array(prices.suffix(min(prices.count, 40)))
        guard let recentHigh = recent.max(), let recentLow = recent.min(), recentHigh > recentLow else { return nil }

        let upperCandidates = [snapshot.bollingerUpper, snapshot.resistanceLevel, recentHigh]
            .compactMap { $0 }
            .filter { $0 > currentPrice }
        let lowerCandidates = [snapshot.bollingerLower, snapshot.supportLevel, recentLow]
            .compactMap { $0 }
            .filter { $0 < currentPrice && $0 > 0 }

        let upper = upperCandidates.min() ?? currentPrice * 1.018
        let lower = lowerCandidates.max() ?? currentPrice * 0.982
        guard upper > lower else { return nil }

        let atr = calculateATR(prices: prices, period: 14) ?? max((upper - lower) / 8, currentPrice * 0.001)
        let gridCount = max(4, min(18, Int((upper - lower) / max(atr, 0.01))))
        let suitable = regime.regime == .ranging || regime.rangingScore > 0.52

        return GridStrategyPlan(
            lowerPrice: lower,
            upperPrice: upper,
            gridCount: gridCount,
            spacing: (upper - lower) / Double(gridCount),
            isSuitable: suitable
        )
    }

    private nonisolated static func buildRiskSummary(
        prices: [Double],
        regime: MarketRegimeReport,
        signal: TradingSignal?,
        forecast: MonteCarloForecast?,
        technicalOpportunity: Double,
        marketContext: GoldMarketContext?,
        calibration: GoldStrategyCalibration
    ) -> RiskSummary {
        let volatilityPenalty: Double
        switch regime.volatilityRegime {
        case .low: volatilityPenalty = 1.10
        case .normal: volatilityPenalty = 1.0
        case .high: volatilityPenalty = 0.65
        case .extreme: volatilityPenalty = 0.35
        }

        let signalMultiplier: Double
        switch signal?.strength {
        case .strong: signalMultiplier = 1.0
        case .medium: signalMultiplier = 0.75
        case .weak: signalMultiplier = 0.45
        case .neutral, .none: signalMultiplier = 0.22
        }

        let probabilityMultiplier: Double
        if let forecast {
            probabilityMultiplier = 0.6 + abs(forecast.probabilityAboveCurrent - 0.5) * 1.2
        } else {
            probabilityMultiplier = 0.75
        }

        let opportunityMultiplier: Double
        if technicalOpportunity >= 35 {
            opportunityMultiplier = 1.20
        } else if technicalOpportunity >= 20 {
            opportunityMultiplier = 1.12
        } else if technicalOpportunity <= -35 {
            opportunityMultiplier = 0.65
        } else if technicalOpportunity <= -20 {
            opportunityMultiplier = 0.82
        } else {
            opportunityMultiplier = 1.0
        }

        let contextMultiplier: Double
        switch marketContext?.overallScore ?? 0 {
        case 35...:
            contextMultiplier = 1.12
        case 18..<35:
            contextMultiplier = 1.06
        case ...(-35):
            contextMultiplier = 0.72
        case -35..<(-18):
            contextMultiplier = 0.86
        default:
            contextMultiplier = 1.0
        }

        let rawExposure = 0.28 * signalMultiplier * volatilityPenalty * probabilityMultiplier * opportunityMultiplier * contextMultiplier
        let suggestedExposure = min(max(0.03, rawExposure * calibration.exposureMultiplier), 0.35)
        let maxSingleMoveRisk = calculateATR(prices: prices, period: 14).map { atr in
            min(max(atr / (prices.last ?? atr), 0.002), 0.05)
        } ?? 0.015

        let riskLevel: String
        switch suggestedExposure {
        case ..<0.08: riskLevel = "保守"
        case ..<0.18: riskLevel = "适中"
        case ..<0.28: riskLevel = "偏进取"
        default: riskLevel = "高风险"
        }

        let warning: String?
        if regime.volatilityRegime == .extreme {
            warning = "波动进入极端区间，降低仓位优先"
        } else if regime.regime == .strongDowntrend {
            warning = "强下行状态，避免追涨"
        } else {
            warning = nil
        }

        return RiskSummary(
            suggestedExposure: suggestedExposure,
            maxSingleMoveRisk: maxSingleMoveRisk,
            riskLevel: riskLevel,
            warning: warning
        )
    }

    private nonisolated static func buildCompositeDecision(
        regime: MarketRegimeReport,
        meanReversion: MeanReversionReport?,
        forecast: MonteCarloForecast?,
        signal: TradingSignal?,
        technicalOpportunity: Double,
        marketContext: GoldMarketContext?,
        calibration: GoldStrategyCalibration
    ) -> (direction: SignalDirection, confidence: Double, summary: String) {
        var buyScore = 0.0
        var sellScore = 0.0

        if let signal {
            let weightedScore = max(signal.score, 0.12) * 0.42
            switch signal.direction {
            case .buy: buyScore += weightedScore
            case .sell: sellScore += weightedScore
            case .hold: break
            }
        }

        switch regime.regime {
        case .strongUptrend: buyScore += 0.30
        case .weakUptrend: buyScore += 0.18
        case .ranging: break
        case .weakDowntrend: sellScore += 0.18
        case .strongDowntrend: sellScore += 0.30
        }

        if let meanReversion {
            let weight = regime.regime == .ranging ? 0.28 : 0.14
            switch meanReversion.direction {
            case .buy: buyScore += meanReversion.confidence * weight
            case .sell: sellScore += meanReversion.confidence * weight
            case .hold: break
            }
        }

        switch technicalOpportunity {
        case 45...:
            buyScore += 0.18
        case 25..<45:
            buyScore += 0.12
        case 12..<25:
            buyScore += 0.06
        case ...(-45):
            sellScore += 0.18
        case -45..<(-25):
            sellScore += 0.12
        case -25..<(-12):
            sellScore += 0.06
        default:
            break
        }

        if let context = marketContext {
            let weightedContext = abs(context.overallScore) / 100 * 0.24
            if context.overallScore >= 12 {
                buyScore += weightedContext
            } else if context.overallScore <= -12 {
                sellScore += weightedContext
            }
        }

        if let forecast {
            if forecast.probabilityAboveCurrent > 0.58 {
                buyScore += 0.15
            } else if forecast.probabilityAboveCurrent < 0.42 {
                sellScore += 0.15
            }
        }

        let netScore = (buyScore - sellScore) * calibration.confidenceMultiplier
        let direction: SignalDirection
        if abs(netScore) < 0.12 {
            direction = .hold
        } else {
            direction = netScore > 0 ? .buy : .sell
        }

        let confidence = min(abs(netScore), 1)
        let summary = "\(regime.regime.rawValue)，优先采用\(regime.regime.fallbackStrategyLabel)"
        return (direction, confidence, summary)
    }

    private nonisolated static func buildBeginnerGuidance(
        regime: MarketRegimeReport,
        risk: RiskSummary,
        forecast: MonteCarloForecast?,
        composite: (direction: SignalDirection, confidence: Double, summary: String),
        technicalOpportunity: Double,
        marketContext: GoldMarketContext?
    ) -> (action: String, reason: String, tone: BeginnerTone) {
        if regime.volatilityRegime == .extreme || regime.regime == .strongDowntrend {
            return (
                "不建议追买",
                "当前波动或下跌压力偏大，新手更适合先观察，等价格和趋势稳定。",
                .defensive
            )
        }

        if case .buy = composite.direction,
           composite.confidence >= 0.30,
           risk.suggestedExposure >= 0.06 {
            let probabilityText = forecast.map { "，模拟上涨概率约 \(Int($0.probabilityAboveCurrent * 100))%" } ?? ""
            let contextText = marketContextText(marketContext)
            return (
                "可小额分批观察",
                "多项信号偏正面\(probabilityText)\(contextText)。不适合一次买太多，先用小仓位试探更稳。",
                .positive
            )
        }

        if technicalOpportunity >= 25,
           regime.regime != .strongDowntrend,
           regime.volatilityRegime != .extreme,
           (marketContext?.overallScore ?? 0) > -35 {
            let contextText = marketContextText(marketContext)
            return (
                "可按定投小额买入",
                "技术评分偏正面\(contextText)，但趋势确认还不够强。更适合用固定预算的一小部分分批买，而不是一次性重仓。",
                .positive
            )
        }

        if case .sell = composite.direction,
           composite.confidence >= 0.25 {
            return (
                "暂不建议买入",
                "偏空信号更多，短线可能还有回落压力。新手可以等回稳后再看。",
                .defensive
            )
        }

        return (
            "观望为主",
            "当前信号不够统一，价格可能上也可能下。没有把握时，先等下一轮数据更友好。",
            .cautious
        )
    }

    private nonisolated static func marketContextText(_ context: GoldMarketContext?) -> String {
        guard let context else { return "" }
        if context.overallScore >= 18 {
            return "，宏观新闻也偏正面"
        }
        if context.overallScore <= -18 {
            return "，但宏观新闻偏谨慎"
        }
        return "，宏观新闻暂偏中性"
    }

    private nonisolated static func scoreTechnicalOpportunity(
        prices: [Double],
        snapshot: TechnicalSnapshot
    ) -> Double {
        guard let currentPrice = prices.last, currentPrice > 0 else { return 0 }
        var score = 0.0

        if let sma60 = snapshot.sma60, sma60 > 0 {
            let deviation = (currentPrice - sma60) / sma60
            switch deviation {
            case ..<(-0.06): score += 14
            case -0.06..<(-0.025): score += 8
            case 0.05..<0.10: score -= 6
            case 0.10...: score -= 12
            default: break
            }
        } else if let sma20 = snapshot.sma20, sma20 > 0 {
            let deviation = (currentPrice - sma20) / sma20
            switch deviation {
            case ..<(-0.025): score += 10
            case -0.025..<(-0.01): score += 5
            case 0.018..<0.035: score -= 5
            case 0.035...: score -= 10
            default: break
            }
        }

        if let rsi = snapshot.rsi14 {
            switch rsi {
            case ..<25: score += 15
            case 25..<35: score += 9
            case 35..<42: score += 4
            case 65..<75: score -= 5
            case 75...: score -= 12
            default: break
            }
        }

        if let histogram = snapshot.macdHistogram {
            score += histogram > 0 ? 8 : -8
        }

        if let upper = snapshot.bollingerUpper, let lower = snapshot.bollingerLower {
            let range = upper - lower
            let position = range > 0 ? min(max((currentPrice - lower) / range, 0), 1) : 0.5
            switch position {
            case ..<0.08: score += 12
            case 0.08..<0.25: score += 6
            case 0.75..<0.92: score -= 6
            case 0.92...: score -= 12
            default: break
            }
        }

        return score.clamped(to: -100...100)
    }

    private nonisolated static func calculateTrendScore(prices: [Double]) -> Double {
        let recent = Array(prices.suffix(min(prices.count, 60)))
        let periods = [(10, 0.38), (20, 0.32), (40, 0.20), (60, 0.10)]
        var score = 0.0
        var totalWeight = 0.0

        for (period, weight) in periods where recent.count >= period + 4 {
            let current = TechnicalIndicators.lastSMA(prices: recent, period: period)
            let previous = TechnicalIndicators.lastSMA(prices: Array(recent.dropLast(4)), period: period)
            if let current, let previous, previous > 0 {
                score += ((current - previous) / previous * 120).clamped(to: -1...1) * weight
                totalWeight += weight
            }
        }

        return totalWeight == 0 ? 0 : score / totalWeight
    }

    private nonisolated static func calculateRangingScore(prices: [Double]) -> Double {
        let recent = Array(prices.suffix(min(prices.count, 40)))
        guard recent.count >= 10, let high = recent.max(), let low = recent.min(), high > low else { return 0.5 }

        let mean = recent.reduce(0, +) / Double(recent.count)
        let averageDeviation = recent.map { abs($0 - mean) }.reduce(0, +) / Double(recent.count)
        let deviationScore = (1 - averageDeviation / (high - low) * 2).clamped(to: 0...1)
        let crossingScore = meanCrossingScore(prices: recent, mean: mean)
        return (deviationScore * 0.55 + crossingScore * 0.45).clamped(to: 0...1)
    }

    private nonisolated static func detectVolatilityRegime(prices: [Double]) -> VolatilityRegime {
        guard let shortVol = rollingVolatility(prices: prices, period: 10),
              let longVol = rollingVolatility(prices: prices, period: min(40, max(12, prices.count - 1))),
              longVol > 0 else {
            return .normal
        }

        let ratio = shortVol / longVol
        if ratio > 2.4 { return .extreme }
        if ratio > 1.5 { return .high }
        if ratio < 0.65 { return .low }
        return .normal
    }

    private nonisolated static func calculateHurstExponent(prices: [Double]) -> Double {
        let returns = logReturns(prices: prices)
        let windows = [10, 20, 40].filter { returns.count >= $0 }
        guard windows.count >= 2 else { return 0.5 }

        var logWindowSizes: [Double] = []
        var logRanges: [Double] = []

        for window in windows {
            let slice = Array(returns.suffix(window))
            let mean = slice.reduce(0, +) / Double(window)
            var cumulative = 0.0
            var cumulativeValues: [Double] = []

            for value in slice {
                cumulative += value - mean
                cumulativeValues.append(cumulative)
            }

            let range = (cumulativeValues.max() ?? 0) - (cumulativeValues.min() ?? 0)
            let deviation = sqrt(slice.reduce(0) { $0 + pow($1 - mean, 2) } / Double(window))
            guard range > 0, deviation > 0 else { continue }
            logWindowSizes.append(log(Double(window)))
            logRanges.append(log(range / deviation))
        }

        guard logWindowSizes.count >= 2 else { return 0.5 }
        return linearSlope(x: logWindowSizes, y: logRanges).clamped(to: 0...1)
    }

    private nonisolated static func calculateADX(prices: [Double], period: Int = 14) -> Double {
        guard prices.count > period + 1 else { return 20 }

        var positiveDM: [Double] = []
        var negativeDM: [Double] = []
        var trueRanges: [Double] = []

        for index in 1..<prices.count {
            let change = prices[index] - prices[index - 1]
            positiveDM.append(max(change, 0))
            negativeDM.append(max(-change, 0))
            trueRanges.append(abs(change))
        }

        guard trueRanges.suffix(period).reduce(0, +) > 0 else { return 0 }
        let positive = positiveDM.suffix(period).reduce(0, +)
        let negative = negativeDM.suffix(period).reduce(0, +)
        let trueRange = trueRanges.suffix(period).reduce(0, +)
        let plusDI = positive / trueRange * 100
        let minusDI = negative / trueRange * 100
        let sum = plusDI + minusDI
        return sum == 0 ? 0 : abs(plusDI - minusDI) / sum * 100
    }

    private nonisolated static func calculateHalfLife(prices: [Double]) -> Double? {
        guard prices.count >= 10 else { return nil }
        var previous: [Double] = []
        var delta: [Double] = []

        for index in 1..<prices.count {
            previous.append(prices[index - 1])
            delta.append(prices[index] - prices[index - 1])
        }

        let slope = linearSlope(x: previous, y: delta)
        guard slope < 0 else { return nil }
        return (log(2) / -slope).clamped(to: 1...999)
    }

    private nonisolated static func calculateATR(prices: [Double], period: Int) -> Double? {
        guard prices.count > period else { return nil }
        let ranges = (1..<prices.count).map { abs(prices[$0] - prices[$0 - 1]) }
        let recent = ranges.suffix(period)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }

    private nonisolated static func rollingVolatility(prices: [Double], period: Int) -> Double? {
        let returns = logReturns(prices: Array(prices.suffix(period + 1)))
        guard returns.count >= 2 else { return nil }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.reduce(0) { $0 + pow($1 - mean, 2) } / Double(returns.count - 1)
        return sqrt(variance)
    }

    private nonisolated static func logReturns(prices: [Double]) -> [Double] {
        guard prices.count > 1 else { return [] }
        var values: [Double] = []

        for index in 1..<prices.count where prices[index - 1] > 0 && prices[index] > 0 {
            values.append(log(prices[index] / prices[index - 1]))
        }

        return values
    }

    private nonisolated static func meanCrossingScore(prices: [Double], mean: Double) -> Double {
        guard prices.count > 2 else { return 0.5 }
        var crossings = 0

        for index in 1..<prices.count {
            let wasAbove = prices[index - 1] >= mean
            let isAbove = prices[index] >= mean
            if wasAbove != isAbove {
                crossings += 1
            }
        }

        return min(Double(crossings) / Double(prices.count / 2), 1)
    }

    private nonisolated static func percentile(_ sortedValues: [Double], _ percentile: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let index = Int((Double(sortedValues.count - 1) * percentile).rounded())
        return sortedValues[min(max(index, 0), sortedValues.count - 1)]
    }

    private nonisolated static func linearSlope(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 2 else { return 0 }
        let count = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = x.reduce(0) { $0 + $1 * $1 }
        let denominator = count * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-10 else { return 0 }
        return (count * sumXY - sumX * sumY) / denominator
    }
}

private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    nonisolated init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    nonisolated mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    nonisolated mutating func nextGaussian() -> Double {
        let u1 = max(Double(next()) / Double(UInt64.max), Double.leastNonzeroMagnitude)
        let u2 = Double(next()) / Double(UInt64.max)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

private extension Double {
    nonisolated func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
