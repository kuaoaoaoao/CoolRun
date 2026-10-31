import Foundation

enum TechnicalIndicators {
    struct MACDResult {
        let macdLine: [Double?]
        let signalLine: [Double?]
        let histogram: [Double?]
    }

    struct BollingerBands {
        let upper: [Double?]
        let middle: [Double?]
        let lower: [Double?]
    }

    nonisolated static func sma(prices: [Double], period: Int) -> [Double?] {
        guard period > 0 else { return prices.map { _ in nil } }
        guard prices.count >= period else { return prices.map { _ in nil } }

        var result: [Double?] = Array(repeating: nil, count: period - 1)
        var sum = prices.prefix(period).reduce(0, +)
        result.append(sum / Double(period))

        for index in period..<prices.count {
            sum += prices[index] - prices[index - period]
            result.append(sum / Double(period))
        }

        return result
    }

    nonisolated static func lastSMA(prices: [Double], period: Int) -> Double? {
        guard prices.count >= period else { return nil }
        return prices.suffix(period).reduce(0, +) / Double(period)
    }

    nonisolated static func ema(prices: [Double], period: Int) -> [Double?] {
        guard period > 0 else { return prices.map { _ in nil } }
        guard prices.count >= period else { return prices.map { _ in nil } }

        let multiplier = 2.0 / Double(period + 1)
        var result: [Double?] = Array(repeating: nil, count: period - 1)
        let seed = prices.prefix(period).reduce(0, +) / Double(period)
        result.append(seed)

        for index in period..<prices.count {
            guard let previous = result.last ?? nil else {
                result.append(nil)
                continue
            }
            result.append((prices[index] - previous) * multiplier + previous)
        }

        return result
    }

    nonisolated static func lastEMA(prices: [Double], period: Int) -> Double? {
        ema(prices: prices, period: period).last ?? nil
    }

    nonisolated static func rsi(prices: [Double], period: Int = 14) -> [Double?] {
        guard period > 0 else { return prices.map { _ in nil } }
        guard prices.count > period else { return prices.map { _ in nil } }

        var gains: [Double] = []
        var losses: [Double] = []

        for index in 1..<prices.count {
            let change = prices[index] - prices[index - 1]
            gains.append(max(change, 0))
            losses.append(max(-change, 0))
        }

        var result: [Double?] = Array(repeating: nil, count: period)
        var averageGain = gains.prefix(period).reduce(0, +) / Double(period)
        var averageLoss = losses.prefix(period).reduce(0, +) / Double(period)

        result.append(rsiValue(averageGain: averageGain, averageLoss: averageLoss))

        for index in period..<gains.count {
            averageGain = (averageGain * Double(period - 1) + gains[index]) / Double(period)
            averageLoss = (averageLoss * Double(period - 1) + losses[index]) / Double(period)
            result.append(rsiValue(averageGain: averageGain, averageLoss: averageLoss))
        }

        return Array(result.prefix(prices.count))
    }

    nonisolated static func lastRSI(prices: [Double], period: Int = 14) -> Double? {
        rsi(prices: prices, period: period).last ?? nil
    }

    nonisolated static func macd(
        prices: [Double],
        fastPeriod: Int = 12,
        slowPeriod: Int = 26,
        signalPeriod: Int = 9
    ) -> MACDResult {
        let fastEMA = ema(prices: prices, period: fastPeriod)
        let slowEMA = ema(prices: prices, period: slowPeriod)

        var macdValues: [Double] = []
        var macdIndices: [Int] = []

        for index in prices.indices {
            if let fast = fastEMA[index], let slow = slowEMA[index] {
                macdValues.append(fast - slow)
                macdIndices.append(index)
            }
        }

        let signalEMA = ema(prices: macdValues, period: signalPeriod)
        var macdLine: [Double?] = Array(repeating: nil, count: prices.count)
        var signalLine: [Double?] = Array(repeating: nil, count: prices.count)
        var histogram: [Double?] = Array(repeating: nil, count: prices.count)

        for index in macdValues.indices {
            let alignedIndex = macdIndices[index]
            macdLine[alignedIndex] = macdValues[index]
            if index < signalEMA.count, let signal = signalEMA[index] {
                signalLine[alignedIndex] = signal
                histogram[alignedIndex] = macdValues[index] - signal
            }
        }

        return MACDResult(macdLine: macdLine, signalLine: signalLine, histogram: histogram)
    }

    nonisolated static func bollingerBands(prices: [Double], period: Int = 20, multiplier: Double = 2.0) -> BollingerBands {
        let middle = sma(prices: prices, period: period)
        var upper: [Double?] = []
        var lower: [Double?] = []

        for index in prices.indices {
            guard let mean = middle[index], index >= period - 1 else {
                upper.append(nil)
                lower.append(nil)
                continue
            }

            let slice = prices[(index - period + 1)...index]
            let variance = slice.reduce(0) { $0 + pow($1 - mean, 2) } / Double(period)
            let deviation = sqrt(variance)
            upper.append(mean + multiplier * deviation)
            lower.append(mean - multiplier * deviation)
        }

        return BollingerBands(upper: upper, middle: middle, lower: lower)
    }

    nonisolated static func annualizedVolatility(prices: [Double], period: Int = 20) -> Double? {
        guard prices.count > 1 else { return nil }
        let returns = logReturns(prices: prices)
        let slice = returns.suffix(period)
        guard slice.count >= 2 else { return nil }

        let mean = slice.reduce(0, +) / Double(slice.count)
        let variance = slice.reduce(0) { $0 + pow($1 - mean, 2) } / Double(slice.count - 1)
        return sqrt(variance) * sqrt(252)
    }

    nonisolated static func roc(prices: [Double], period: Int = 10) -> [Double?] {
        guard prices.count > period else { return prices.map { _ in nil } }

        var result: [Double?] = Array(repeating: nil, count: period)
        for index in period..<prices.count {
            let previous = prices[index - period]
            result.append(previous == 0 ? nil : (prices[index] - previous) / previous * 100)
        }
        return result
    }

    nonisolated static func findSupportResistance(
        prices: [Double],
        window: Int = 5,
        currentPrice: Double
    ) -> (support: Double?, resistance: Double?) {
        guard prices.count > window * 2 + 1 else { return (nil, nil) }

        var supports: [Double] = []
        var resistances: [Double] = []

        for index in window..<(prices.count - window) {
            let value = prices[index]
            let left = prices[(index - window)..<index]
            let right = prices[(index + 1)...(index + window)]

            if left.allSatisfy({ $0 >= value }) && right.allSatisfy({ $0 >= value }) && value < currentPrice {
                supports.append(value)
            }

            if left.allSatisfy({ $0 <= value }) && right.allSatisfy({ $0 <= value }) && value > currentPrice {
                resistances.append(value)
            }
        }

        return (supports.max(), resistances.min())
    }

    nonisolated static func maxDrawdown(prices: [Double]) -> Double {
        guard let first = prices.first else { return 0 }

        var peak = first
        var maximum = 0.0

        for price in prices where price > 0 {
            peak = max(peak, price)
            maximum = max(maximum, (peak - price) / peak)
        }

        return maximum
    }

    nonisolated static func buildSnapshot(prices: [Double], currentPrice: Double) -> TechnicalSnapshot {
        let macdResult = macd(prices: prices)
        let bollinger = bollingerBands(prices: prices)
        let lastIndex = prices.count - 1
        let supportResistance = findSupportResistance(prices: prices, currentPrice: currentPrice)

        return TechnicalSnapshot(
            sma5: lastSMA(prices: prices, period: 5),
            sma20: lastSMA(prices: prices, period: 20),
            sma60: lastSMA(prices: prices, period: 60),
            ema12: lastEMA(prices: prices, period: 12),
            ema26: lastEMA(prices: prices, period: 26),
            rsi14: lastRSI(prices: prices),
            macdLine: macdResult.macdLine[lastIndex],
            macdSignal: macdResult.signalLine[lastIndex],
            macdHistogram: macdResult.histogram[lastIndex],
            bollingerUpper: bollinger.upper[lastIndex],
            bollingerMiddle: bollinger.middle[lastIndex],
            bollingerLower: bollinger.lower[lastIndex],
            volatility: annualizedVolatility(prices: prices),
            roc10: roc(prices: prices).last ?? nil,
            supportLevel: supportResistance.support,
            resistanceLevel: supportResistance.resistance,
            timestamp: Date()
        )
    }

    private nonisolated static func rsiValue(averageGain: Double, averageLoss: Double) -> Double {
        if averageLoss == 0 {
            return averageGain == 0 ? 50 : 100
        }

        let relativeStrength = averageGain / averageLoss
        return 100 - 100 / (1 + relativeStrength)
    }

    private nonisolated static func logReturns(prices: [Double]) -> [Double] {
        var returns: [Double] = []

        for index in 1..<prices.count where prices[index - 1] > 0 && prices[index] > 0 {
            returns.append(log(prices[index] / prices[index - 1]))
        }

        return returns
    }
}
