import Foundation

enum GoldAnalysisEngine {
    nonisolated static func makeStatistics(records: [GoldPriceRecord]) -> PriceStatistics? {
        guard let first = records.first, let last = records.last else { return nil }

        let prices = records.map(\.price)
        let change = last.price - first.price
        let changePercent = first.price == 0 ? 0 : change / first.price * 100

        return PriceStatistics(
            currentPrice: last.price,
            periodHigh: prices.max() ?? last.price,
            periodLow: prices.min() ?? last.price,
            periodAverage: prices.reduce(0, +) / Double(prices.count),
            change: change,
            changePercent: changePercent,
            maxDrawdown: TechnicalIndicators.maxDrawdown(prices: prices),
            recordCount: records.count,
            firstRecordDate: first.timestamp,
            lastUpdateDate: last.timestamp
        )
    }

    nonisolated static func makeSnapshot(records: [GoldPriceRecord]) -> TechnicalSnapshot? {
        guard let currentPrice = records.last?.price else { return nil }
        return TechnicalIndicators.buildSnapshot(prices: records.map(\.price), currentPrice: currentPrice)
    }
}

enum TradingSignalEngine {
    nonisolated static func generateSignal(
        prices: [Double],
        currentPrice: Double,
        snapshot: TechnicalSnapshot,
        lang: AppLanguage
    ) -> TradingSignal {
        var buyScore = 0.0
        var sellScore = 0.0
        var reasons: [String] = []

        if let sma5 = snapshot.sma5, let sma20 = snapshot.sma20 {
            if sma5 > sma20 {
                buyScore += 0.25
                reasons.append(LocalizedString.l(
                    lang,
                    en: "SMA5 is above SMA20; short-term momentum is firm",
                    zh: "SMA5 位于 SMA20 上方，短线偏强",
                    ja: "SMA5がSMA20を上回り、短期は強め",
                    ko: "SMA5가 SMA20 위에 있어 단기 흐름이 강합니다"
                ))
            } else {
                sellScore += 0.25
                reasons.append(LocalizedString.l(
                    lang,
                    en: "SMA5 is below SMA20; short-term momentum is soft",
                    zh: "SMA5 位于 SMA20 下方，短线偏弱",
                    ja: "SMA5がSMA20を下回り、短期は弱め",
                    ko: "SMA5가 SMA20 아래에 있어 단기 흐름이 약합니다"
                ))
            }
        }

        if let ema12 = snapshot.ema12, let ema26 = snapshot.ema26 {
            if ema12 > ema26 {
                buyScore += 0.15
                reasons.append(LocalizedString.l(
                    lang,
                    en: "EMA12 is above EMA26; medium-term momentum leans bullish",
                    zh: "EMA12 高于 EMA26，中期动量偏多",
                    ja: "EMA12がEMA26を上回り、中期モメンタムは強気寄り",
                    ko: "EMA12가 EMA26 위에 있어 중기 모멘텀이 상승 쪽입니다"
                ))
            } else {
                sellScore += 0.15
                reasons.append(LocalizedString.l(
                    lang,
                    en: "EMA12 is below EMA26; medium-term momentum leans bearish",
                    zh: "EMA12 低于 EMA26，中期动量偏空",
                    ja: "EMA12がEMA26を下回り、中期モメンタムは弱気寄り",
                    ko: "EMA12가 EMA26 아래에 있어 중기 모멘텀이 하락 쪽입니다"
                ))
            }
        }

        let trendBias = buyScore - sellScore

        if let rsi = snapshot.rsi14 {
            switch rsi {
            case ..<30:
                let score = rsi < 20 ? 0.30 : 0.22
                if trendBias < -0.12 {
                    buyScore += 0.10
                    reasons.append(LocalizedString.l(
                        lang,
                        en: "RSI \(rsi.analysisNumber) is oversold, but the trend is still weak; wait for it to stabilize",
                        zh: "RSI \(rsi.analysisNumber) 已超卖，但趋势仍偏弱，先看企稳",
                        ja: "RSI \(rsi.analysisNumber) は売られすぎですが、トレンドはまだ弱く、落ち着き待ちです",
                        ko: "RSI \(rsi.analysisNumber)는 과매도지만 추세가 아직 약해 안정화를 기다립니다"
                    ))
                } else {
                    buyScore += score
                    reasons.append(LocalizedString.l(
                        lang,
                        en: "RSI \(rsi.analysisNumber) has entered oversold territory; there is room for a low-level rebound",
                        zh: "RSI \(rsi.analysisNumber) 进入超卖区域，存在低位修复机会",
                        ja: "RSI \(rsi.analysisNumber) は売られすぎ圏に入り、低位からの戻り余地があります",
                        ko: "RSI \(rsi.analysisNumber)가 과매도 구간에 들어 저점 반등 여지가 있습니다"
                    ))
                }
            case 70...:
                let score = rsi > 80 ? 0.30 : 0.22
                if trendBias > 0.12 {
                    sellScore += 0.10
                    reasons.append(LocalizedString.l(
                        lang,
                        en: "RSI \(rsi.analysisNumber) is overbought; the trend is still strong but chasing too fast is risky",
                        zh: "RSI \(rsi.analysisNumber) 已超买，趋势仍强但不宜追太急",
                        ja: "RSI \(rsi.analysisNumber) は買われすぎ。トレンドは強いが急いで追随するのは危険です",
                        ko: "RSI \(rsi.analysisNumber)는 과매수입니다. 추세는 강하지만 급하게 따라가기는 위험합니다"
                    ))
                } else {
                    sellScore += score
                    reasons.append(LocalizedString.l(
                        lang,
                        en: "RSI \(rsi.analysisNumber) has entered overbought territory; watch for a pullback",
                        zh: "RSI \(rsi.analysisNumber) 进入超买区域，需留意回落",
                        ja: "RSI \(rsi.analysisNumber) は買われすぎ圏に入り、反落に注意が必要です",
                        ko: "RSI \(rsi.analysisNumber)가 과매수 구간에 들어 조정에 유의해야 합니다"
                    ))
                }
            case 45...55:
                reasons.append(LocalizedString.l(
                    lang,
                    en: "RSI \(rsi.analysisNumber) is close to neutral",
                    zh: "RSI \(rsi.analysisNumber) 接近中性",
                    ja: "RSI \(rsi.analysisNumber) は中立に近い水準です",
                    ko: "RSI \(rsi.analysisNumber)는 중립에 가깝습니다"
                ))
            default:
                break
            }
        }

        if let histogram = snapshot.macdHistogram {
            if histogram > 0 {
                buyScore += 0.20
                reasons.append(LocalizedString.l(
                    lang,
                    en: "MACD histogram is positive; bulls have the momentum edge",
                    zh: "MACD 柱为正，多头动量占优",
                    ja: "MACDヒストグラムがプラスで、強気のモメンタムが優勢です",
                    ko: "MACD 히스토그램이 양수로, 상승 모멘텀이 우세합니다"
                ))
            } else if histogram < 0 {
                sellScore += 0.20
                reasons.append(LocalizedString.l(
                    lang,
                    en: "MACD histogram is negative; bears have the momentum edge",
                    zh: "MACD 柱为负，空头动量占优",
                    ja: "MACDヒストグラムがマイナスで、弱気のモメンタムが優勢です",
                    ko: "MACD 히스토그램이 음수로, 하락 모멘텀이 우세합니다"
                ))
            }
        }

        if let lower = snapshot.bollingerLower, let upper = snapshot.bollingerUpper {
            if currentPrice <= lower {
                buyScore += 0.20
                reasons.append(LocalizedString.l(
                    lang,
                    en: "Price touched the lower Bollinger band; a rebound is worth watching",
                    zh: "价格触及布林下轨，存在反弹观察点",
                    ja: "価格がボリンジャー下限に触れ、反発の観察ポイントです",
                    ko: "가격이 볼린저 하단에 닿아 반등 관찰 지점입니다"
                ))
            } else if currentPrice >= upper {
                sellScore += 0.20
                reasons.append(LocalizedString.l(
                    lang,
                    en: "Price touched the upper Bollinger band; watch for a pullback",
                    zh: "价格触及布林上轨，需留意回落",
                    ja: "価格がボリンジャー上限に触れ、反落に注意です",
                    ko: "가격이 볼린저 상단에 닿아 조정에 유의해야 합니다"
                ))
            }
        }

        if let support = snapshot.supportLevel, abs(currentPrice - support) / currentPrice < 0.002 {
            buyScore += 0.12
                reasons.append(LocalizedString.l(
                    lang,
                    en: "Price is near recent support \(support.analysisPriceNumber)",
                    zh: "价格接近近期支撑位 \(support.analysisPriceNumber)",
                    ja: "価格は直近の支持線 \(support.analysisPriceNumber) 付近です",
                    ko: "가격이 최근 지지선 \(support.analysisPriceNumber) 부근입니다"
                ))
        }

        if let resistance = snapshot.resistanceLevel, abs(currentPrice - resistance) / currentPrice < 0.002 {
            sellScore += 0.12
                reasons.append(LocalizedString.l(
                    lang,
                    en: "Price is near recent resistance \(resistance.analysisPriceNumber)",
                    zh: "价格接近近期压力位 \(resistance.analysisPriceNumber)",
                    ja: "価格は直近の抵抗線 \(resistance.analysisPriceNumber) 付近です",
                    ko: "가격이 최근 저항선 \(resistance.analysisPriceNumber) 부근입니다"
                ))
        }

        if let roc10 = snapshot.roc10 {
            if roc10 > 0.1 {
                buyScore += 0.08
            } else if roc10 < -0.1 {
                sellScore += 0.08
            }
        }

        let netScore = buyScore - sellScore
        let direction: SignalDirection
        if abs(netScore) < 0.12 {
            direction = .hold
        } else {
            direction = netScore > 0 ? .buy : .sell
        }

        let strength: SignalStrength
        switch abs(netScore) {
        case 0.55...: strength = .strong
        case 0.32..<0.55: strength = .medium
        case 0.12..<0.32: strength = .weak
        default: strength = .neutral
        }

        if reasons.isEmpty {
            reasons.append(LocalizedString.l(
                lang,
                en: "History is still accumulating; holding is the main stance for now",
                zh: "历史样本仍在积累，暂以观望为主",
                ja: "履歴がまだ蓄積中です。今は様子見が中心です",
                ko: "이력이 아직 쌓이는 중이라 당분간 관망이 중심입니다"
            ))
        }

        let bollingerRange: Double
        if let upper = snapshot.bollingerUpper, let lower = snapshot.bollingerLower {
            bollingerRange = abs(upper - lower)
        } else {
            bollingerRange = 3.2
        }
        let riskUnit = max(bollingerRange / 4, 0.8)
        let entry: Double?
        let stopLoss: Double?
        let takeProfit: Double?

        switch direction {
        case .buy:
            entry = currentPrice
            stopLoss = currentPrice - riskUnit
            takeProfit = currentPrice + riskUnit * 1.6
        case .sell:
            entry = currentPrice
            stopLoss = currentPrice + riskUnit
            takeProfit = currentPrice - riskUnit * 1.6
        case .hold:
            entry = nil
            stopLoss = nil
            takeProfit = nil
        }

        return TradingSignal(
            direction: direction,
            strength: strength,
            score: min(abs(netScore), 1),
            suggestedEntry: entry,
            suggestedStopLoss: stopLoss,
            suggestedTakeProfit: takeProfit,
            reasons: Array(reasons.prefix(4)),
            timestamp: Date()
        )
    }
}

private extension Double {
    nonisolated var analysisNumber: String {
        formatted(.number.precision(.fractionLength(1)))
    }

    nonisolated var analysisPriceNumber: String {
        formatted(.number.precision(.fractionLength(2)))
    }
}
