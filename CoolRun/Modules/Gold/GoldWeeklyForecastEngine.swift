import Foundation

// MARK: - 输入与草稿

/// 周预测引擎只消费标准化日线；startPrice 来自当前 App 有效报价。
struct GoldWeeklyForecastEngineInput: Sendable {
    let closes: [GoldDailyClose]
    let startPrice: Double
    let generatedAt: Date
    let targetDate: Date
    let seed: UInt64
}

/// 引擎输出的统计草稿；方向来自组合分数，不从 P50 反推。
struct GoldWeeklyForecastDraft: Sendable, Equatable {
    let direction: GoldWeeklyForecastDirection
    let expectedPrice: Double
    let expectedReturn: Double
    let p10: Double
    let p50: Double
    let p90: Double
    let components: GoldWeeklyForecastComponents
}

// MARK: - 引擎

/// 确定性统计组合模型：趋势 0.35、动量 0.25、均值回归 0.15、区块自助 0.25。
/// 固定 seed 注入保证同输入同输出；权重与阈值变更必须提升 modelVersion。
enum GoldWeeklyForecastEngine {
    nonisolated static func makeDraft(_ input: GoldWeeklyForecastEngineInput) -> GoldWeeklyForecastDraft? {
        let closes = input.closes
        guard closes.count >= GoldWeeklyForecastPolicy.minimumDailyCloses else { return nil }

        let returns = logReturns(closes.map(\.close))
        let sigma20 = max(standardDeviation(Array(returns.suffix(20))), 0.000_1)
        let last = closes.last!.close
        let sma20 = mean(closes.suffix(20).map(\.close))
        let sma60 = mean(closes.suffix(60).map(\.close))
        let trend = tanh(((sma20 - sma60) / last) / (sigma20 * sqrt(7)))

        let return5 = last / closes[closes.count - 6].close - 1
        let return20 = last / closes[closes.count - 21].close - 1
        let momentum = tanh((0.55 * return5 + 0.45 * return20) / (sigma20 * sqrt(7)))

        let std20Price = max(standardDeviation(closes.suffix(20).map(\.close)), 0.000_1)
        let z20 = (last - sma20) / std20Price
        let meanReversion = -tanh(z20 / 2)

        let distribution = blockBootstrapFinalPrices(
            logReturns: Array(returns.suffix(120)),
            startPrice: input.startPrice,
            steps: effectiveStepsForSevenCalendarDays(closes: closes),
            blockLength: 3,
            simulations: GoldWeeklyForecastPolicy.simulationCount,
            seed: input.seed
        )
        let upCount = distribution.filter { $0 / input.startPrice - 1 > 0.005 }.count
        let downCount = distribution.filter { $0 / input.startPrice - 1 < -0.005 }.count
        let bootstrap = distribution.isEmpty ? 0 : Double(upCount - downCount) / Double(distribution.count)

        let composite = 0.35 * trend
            + 0.25 * momentum
            + 0.15 * meanReversion
            + 0.25 * bootstrap

        let direction: GoldWeeklyForecastDirection
        if composite >= GoldWeeklyForecastPolicy.scoreDirectionThreshold {
            direction = .up
        } else if composite <= -GoldWeeklyForecastPolicy.scoreDirectionThreshold {
            direction = .down
        } else {
            direction = .flat
        }

        let sorted = distribution.sorted()
        let fallback = input.startPrice > 0 ? input.startPrice : last
        let p10 = sorted.isEmpty ? fallback : percentile(sorted, 0.10)
        let p50 = sorted.isEmpty ? fallback : percentile(sorted, 0.50)
        let p90 = sorted.isEmpty ? fallback : percentile(sorted, 0.90)
        let expectedPrice = p50
        let expectedReturn = input.startPrice > 0 ? expectedPrice / input.startPrice - 1 : 0

        return GoldWeeklyForecastDraft(
            direction: direction,
            expectedPrice: expectedPrice,
            expectedReturn: expectedReturn,
            p10: p10,
            p50: p50,
            p90: p90,
            components: GoldWeeklyForecastComponents(
                trend: clamped(trend),
                momentum: clamped(momentum),
                meanReversion: clamped(meanReversion),
                bootstrap: clamped(bootstrap),
                composite: clamped(composite)
            )
        )
    }

    // MARK: - 步数估计

    /// 历史数据中 7 个自然日窗口通常包含的有效收盘点中位数，限制在 3...7。
    nonisolated static func effectiveStepsForSevenCalendarDays(closes: [GoldDailyClose]) -> Int {
        guard !closes.isEmpty else { return 3 }
        let calendar = Calendar.goldShanghai
        let dates = closes.map(\.date)
        var counts: [Int] = []
        counts.reserveCapacity(dates.count)
        for date in dates {
            guard let windowEnd = calendar.date(
                byAdding: .day,
                value: GoldWeeklyForecastPolicy.horizonDays,
                to: date
            ) else { continue }
            counts.append(dates.filter { $0 >= date && $0 < windowEnd }.count)
        }
        guard !counts.isEmpty else { return 3 }
        let sortedCounts = counts.sorted()
        let mid = sortedCounts.count / 2
        let median: Double
        if sortedCounts.count % 2 == 0 {
            median = Double(sortedCounts[mid - 1] + sortedCounts[mid]) / 2
        } else {
            median = Double(sortedCounts[mid])
        }
        return min(7, max(3, Int(median.rounded())))
    }

    // MARK: - 区块自助法

    /// 从日收益抽取长度为 3 的连续区块，拼接 steps 个收益并复利，执行 simulations 次。
    /// 使用 SplitMix64 固定 seed，保证确定性。
    nonisolated private static func blockBootstrapFinalPrices(
        logReturns: [Double],
        startPrice: Double,
        steps: Int,
        blockLength: Int,
        simulations: Int,
        seed: UInt64
    ) -> [Double] {
        guard !logReturns.isEmpty, steps > 0, blockLength > 0, simulations > 0 else { return [] }
        let returnsCount = logReturns.count
        var state = seed
        func nextUInt64() -> UInt64 {
            state &+= 0x9E37_7B97_F4A7_C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        var finalPrices: [Double] = []
        finalPrices.reserveCapacity(simulations)
        for _ in 0..<simulations {
            var totalLogReturn = 0.0
            var drawn = 0
            while drawn < steps {
                let startIndex = Int(nextUInt64() % UInt64(returnsCount))
                for offset in 0..<blockLength where drawn < steps {
                    totalLogReturn += logReturns[(startIndex + offset) % returnsCount]
                    drawn += 1
                }
            }
            let price = startPrice * exp(totalLogReturn)
            finalPrices.append(price.isFinite && price > 0 ? price : startPrice)
        }
        return finalPrices
    }

    // MARK: - 数值工具

    nonisolated private static func logReturns(_ prices: [Double]) -> [Double] {
        guard prices.count >= 2 else { return [] }
        return (1..<prices.count).map { log(prices[$0] / prices[$0 - 1]) }
    }

    nonisolated private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    nonisolated private static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let m = mean(values)
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)
        return sqrt(variance)
    }

    /// 有序数组的线性百分位。
    nonisolated private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let rank = p * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = rank - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    nonisolated private static func clamped(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}
