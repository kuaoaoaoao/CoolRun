import Foundation

struct GoldPriceRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let price: Double
    let timestamp: Date
    let source: String

    nonisolated init(id: UUID = UUID(), price: Double, timestamp: Date = Date(), source: String = "CZB-JCJ") {
        self.id = id
        self.price = price
        self.timestamp = timestamp
        self.source = source
    }
}

struct GoldCandlestick: Identifiable, Equatable, Sendable {
    let id = UUID()
    let open: Double
    let close: Double
    let high: Double
    let low: Double
    let volume: Int
    let startDate: Date
    let endDate: Date
    let period: CandlePeriod

    var isUp: Bool { close >= open }
    var change: Double { close - open }
    var changePercent: Double { open == 0 ? 0 : change / open * 100 }
}

enum CandlePeriod: String, CaseIterable, Codable, Sendable {
    case minute5 = "5分钟"
    case minute15 = "15分钟"
    case hour1 = "1小时"
    case day1 = "日线"

    nonisolated var intervalSeconds: TimeInterval {
        switch self {
        case .minute5: 300
        case .minute15: 900
        case .hour1: 3600
        case .day1: 86400
        }
    }

    var displayName: String {
        switch self {
        case .minute5: return LocalizedString.gold("5min")
        case .minute15: return LocalizedString.gold("15min")
        case .hour1: return LocalizedString.gold("1hour")
        case .day1: return LocalizedString.gold("1day")
        }
    }
}

struct TechnicalSnapshot: Sendable {
    let sma5: Double?
    let sma20: Double?
    let sma60: Double?
    let ema12: Double?
    let ema26: Double?
    let rsi14: Double?
    let macdLine: Double?
    let macdSignal: Double?
    let macdHistogram: Double?
    let bollingerUpper: Double?
    let bollingerMiddle: Double?
    let bollingerLower: Double?
    let volatility: Double?
    let roc10: Double?
    let supportLevel: Double?
    let resistanceLevel: Double?
    let timestamp: Date

    var rsiState: RSIState {
        guard let rsi14 else { return .warmingUp }
        if rsi14 >= 80 { return .extremelyOverbought }
        if rsi14 >= 70 { return .overbought }
        if rsi14 <= 20 { return .extremelyOversold }
        if rsi14 <= 30 { return .oversold }
        return .neutral
    }

    var macdState: MACDState {
        guard let macdHistogram, let macdLine else { return .warmingUp }
        if macdHistogram > 0 && macdLine > 0 { return .bullishStrong }
        if macdHistogram > 0 { return .bullish }
        if macdHistogram < 0 && macdLine < 0 { return .bearishStrong }
        return .bearish
    }

    func bollingerPosition(price: Double) -> Double? {
        guard let bollingerUpper, let bollingerLower else { return nil }
        let range = bollingerUpper - bollingerLower
        guard range > 0 else { return 0.5 }
        return min(max((price - bollingerLower) / range, 0), 1)
    }
}

enum RSIState: String, Sendable {
    case warmingUp = "积累中"
    case extremelyOversold = "极度超卖"
    case oversold = "超卖"
    case neutral = "中性"
    case overbought = "超买"
    case extremelyOverbought = "极度超买"

    var displayName: String {
        switch self {
        case .warmingUp: return LocalizedString.gold("warming_up")
        case .extremelyOversold: return LocalizedString.gold("extremely_oversold")
        case .oversold: return LocalizedString.gold("oversold")
        case .neutral: return LocalizedString.gold("neutral")
        case .overbought: return LocalizedString.gold("overbought")
        case .extremelyOverbought: return LocalizedString.gold("extremely_overbought")
        }
    }
}

enum MACDState: String, Sendable {
    case warmingUp = "积累中"
    case bullishStrong = "强势看多"
    case bullish = "看多"
    case bearish = "看空"
    case bearishStrong = "强势看空"

    var displayName: String {
        switch self {
        case .warmingUp: return LocalizedString.gold("warming_up")
        case .bullishStrong: return LocalizedString.gold("bullish_strong")
        case .bullish: return LocalizedString.gold("bullish")
        case .bearish: return LocalizedString.gold("bearish")
        case .bearishStrong: return LocalizedString.gold("bearish_strong")
        }
    }
}

struct TradingSignal: Identifiable, Sendable {
    let id = UUID()
    let direction: SignalDirection
    let strength: SignalStrength
    let score: Double
    let suggestedEntry: Double?
    let suggestedStopLoss: Double?
    let suggestedTakeProfit: Double?
    let reasons: [String]
    let timestamp: Date
}

enum SignalDirection: Sendable {
    case buy
    case sell
    case hold

    var label: String {
        switch self {
        case .buy: LocalizedString.gold("buy")
        case .sell: LocalizedString.gold("sell")
        case .hold: LocalizedString.gold("hold")
        }
    }
}

enum SignalStrength: String, Sendable {
    case strong = "强"
    case medium = "中"
    case weak = "弱"
    case neutral = "观望"

    var displayName: String {
        switch self {
        case .strong: return LocalizedString.gold("strong")
        case .medium: return LocalizedString.gold("medium")
        case .weak: return LocalizedString.gold("weak")
        case .neutral: return LocalizedString.gold("hold")
        }
    }
}

struct PriceStatistics: Sendable {
    let currentPrice: Double
    let periodHigh: Double
    let periodLow: Double
    let periodAverage: Double
    let change: Double
    let changePercent: Double
    let maxDrawdown: Double
    let recordCount: Int
    let firstRecordDate: Date?
    let lastUpdateDate: Date?

    var trendDescription: String {
        if changePercent > 0.5 { return LocalizedString.gold("strong_up") }
        if changePercent > 0.1 { return LocalizedString.gold("mild_up") }
        if changePercent < -0.5 { return LocalizedString.gold("strong_down") }
        if changePercent < -0.1 { return LocalizedString.gold("mild_down") }
        return LocalizedString.gold("sideways")
    }
}
