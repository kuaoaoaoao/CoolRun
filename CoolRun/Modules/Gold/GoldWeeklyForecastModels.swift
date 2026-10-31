import Foundation

// MARK: - 方向与信心

/// 一周方向三分类。实际收益率 > 0.5% 为 up，-0.5%...0.5% 为 flat，< -0.5% 为 down。
enum GoldWeeklyForecastDirection: String, Codable, Sendable, Equatable {
    case up, flat, down

    nonisolated static func classify(actualReturn: Double) -> Self {
        if actualReturn > GoldWeeklyForecastPolicy.flatReturnThreshold { return .up }
        if actualReturn < -GoldWeeklyForecastPolicy.flatReturnThreshold { return .down }
        return .flat
    }
}

/// 信心等级不是上涨概率；只表达数据、来源与回测对结论的支持程度。
enum GoldWeeklyForecastConfidence: String, Codable, Sendable, Equatable, Comparable {
    case unavailable, low, medium, high
}

extension GoldWeeklyForecastConfidence {
    nonisolated static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.unavailable, .low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    nonisolated var upgraded: Self {
        switch self {
        case .unavailable: .low
        case .low: .medium
        case .medium, .high: .high
        }
    }

    nonisolated var downgraded: Self {
        switch self {
        case .high: .medium
        case .medium: .low
        case .low, .unavailable: .unavailable
        }
    }
}

// MARK: - 状态与来源兼容性

/// 只有 ready 可以携带 forecast；其余状态必须说明原因并停止发布方向。
enum GoldWeeklyForecastStatus: String, Codable, Sendable, Equatable {
    case ready
    case insufficientHistory
    case staleData
    case sourceMismatch
    case validationFailed
    case sourceUnavailable
}

enum GoldForecastSourceCompatibility: String, Codable, Sendable, Equatable {
    case verified, proxy, incompatible
}

// MARK: - 固定策略参数

enum GoldWeeklyForecastPolicy {
    nonisolated static let modelVersion = "gold-weekly-2026.08.30.1"
    nonisolated static let flatReturnThreshold = 0.005
    nonisolated static let scoreDirectionThreshold = 0.18
    nonisolated static let minimumDailyCloses = 120
    nonisolated static let normalDailyCloses = 180
    nonisolated static let highDailyCloses = 240
    nonisolated static let horizonDays = 7
    nonisolated static let validationGraceDays = 3
    nonisolated static let maximumLatestAge: TimeInterval = 96 * 60 * 60
    nonisolated static let simulationCount = 2_000
}

// MARK: - 数据点与分量

/// 上海日历归并后的有效日收盘。
struct GoldDailyClose: Codable, Sendable, Equatable {
    let date: Date
    let close: Double
}

struct GoldWeeklyForecastComponents: Codable, Sendable, Equatable {
    let trend: Double
    let momentum: Double
    let meanReversion: Double
    let bootstrap: Double
    let composite: Double
}

// MARK: - 回测摘要

struct GoldWeeklyForecastBacktestSummary: Codable, Sendable, Equatable {
    let resolvedCount: Int
    let classCounts: [GoldWeeklyForecastDirection: Int]
    let overallAccuracy: Double?
    let balancedAccuracy: Double?
    let majorityBaselineAccuracy: Double?
    let meanAbsoluteReturnError: Double?
    let confusionMatrix: [GoldWeeklyForecastDirection: [GoldWeeklyForecastDirection: Int]]
    let passedReleaseGate: Bool
    let failureReasons: [String]
}

// MARK: - 预测

struct GoldWeeklyForecast: Codable, Sendable, Equatable {
    let direction: GoldWeeklyForecastDirection
    let confidence: GoldWeeklyForecastConfidence
    let startPrice: Double
    let expectedPrice: Double
    let expectedReturn: Double
    let p10: Double
    let p50: Double
    let p90: Double
    let generatedAt: Date
    let targetDate: Date
    let dataUpdatedAt: Date
    let currentPriceSource: String
    let historySource: String
    let sourceCompatibility: GoldForecastSourceCompatibility
    let components: GoldWeeklyForecastComponents
    let reasons: [String]
    let counterRisks: [String]
    let modelVersion: String
}

struct GoldWeeklyForecastSnapshot: Sendable, Equatable {
    let status: GoldWeeklyForecastStatus
    let forecast: GoldWeeklyForecast?
    let backtest: GoldWeeklyForecastBacktestSummary?
    let message: String
    let updatedAt: Date
}

extension GoldWeeklyForecastSnapshot {
    /// 非 ready 快照的安全工厂：不携带 forecast 和 backtest。
    nonisolated static func unavailable(
        status: GoldWeeklyForecastStatus,
        message: String,
        now: Date
    ) -> Self {
        precondition(status != .ready)
        return Self(status: status, forecast: nil, backtest: nil, message: message, updatedAt: now)
    }
}

// MARK: - 上海日历

extension Calendar {
    nonisolated static var goldShanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
}
