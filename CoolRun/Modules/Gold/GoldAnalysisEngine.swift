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
    nonisolated static func generateSignal(prices: [Double], currentPrice: Double, snapshot: TechnicalSnapshot) -> TradingSignal {
        var buyScore = 0.0
        var sellScore = 0.0
        var reasons: [String] = []

        if let sma5 = snapshot.sma5, let sma20 = snapshot.sma20 {
            if sma5 > sma20 {
                buyScore += 0.25
                reasons.append("SMA5 位于 SMA20 上方，短线偏强")
            } else {
                sellScore += 0.25
                reasons.append("SMA5 位于 SMA20 下方，短线偏弱")
            }
        }

        if let ema12 = snapshot.ema12, let ema26 = snapshot.ema26 {
            if ema12 > ema26 {
                buyScore += 0.15
                reasons.append("EMA12 高于 EMA26，中期动量偏多")
            } else {
                sellScore += 0.15
                reasons.append("EMA12 低于 EMA26，中期动量偏空")
            }
        }

        let trendBias = buyScore - sellScore

        if let rsi = snapshot.rsi14 {
            switch rsi {
            case ..<30:
                let score = rsi < 20 ? 0.30 : 0.22
                if trendBias < -0.12 {
                    buyScore += 0.10
                    reasons.append("RSI \(rsi.analysisNumber) 已超卖，但趋势仍偏弱，先看企稳")
                } else {
                    buyScore += score
                    reasons.append("RSI \(rsi.analysisNumber) 进入超卖区域，存在低位修复机会")
                }
            case 70...:
                let score = rsi > 80 ? 0.30 : 0.22
                if trendBias > 0.12 {
                    sellScore += 0.10
                    reasons.append("RSI \(rsi.analysisNumber) 已超买，趋势仍强但不宜追太急")
                } else {
                    sellScore += score
                    reasons.append("RSI \(rsi.analysisNumber) 进入超买区域，需留意回落")
                }
            case 45...55:
                reasons.append("RSI \(rsi.analysisNumber) 接近中性")
            default:
                break
            }
        }

        if let histogram = snapshot.macdHistogram {
            if histogram > 0 {
                buyScore += 0.20
                reasons.append("MACD 柱为正，多头动量占优")
            } else if histogram < 0 {
                sellScore += 0.20
                reasons.append("MACD 柱为负，空头动量占优")
            }
        }

        if let lower = snapshot.bollingerLower, let upper = snapshot.bollingerUpper {
            if currentPrice <= lower {
                buyScore += 0.20
                reasons.append("价格触及布林下轨，存在反弹观察点")
            } else if currentPrice >= upper {
                sellScore += 0.20
                reasons.append("价格触及布林上轨，需留意回落")
            }
        }

        if let support = snapshot.supportLevel, abs(currentPrice - support) / currentPrice < 0.002 {
            buyScore += 0.12
                reasons.append("价格接近近期支撑位 \(support.analysisPriceNumber)")
        }

        if let resistance = snapshot.resistanceLevel, abs(currentPrice - resistance) / currentPrice < 0.002 {
            sellScore += 0.12
                reasons.append("价格接近近期压力位 \(resistance.analysisPriceNumber)")
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
            reasons.append("历史样本仍在积累，暂以观望为主")
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
