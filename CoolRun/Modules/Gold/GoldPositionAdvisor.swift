import Foundation

struct GoldHoldingAdvice: Sendable {
    let grams: Double
    let averageCost: Double
    let currentPrice: Double
    let costBasis: Double
    let marketValue: Double
    let profitLoss: Double
    let profitPercent: Double
    let breakEvenGap: Double
    let actionTitle: String
    let reason: String
    let actionItems: [String]
    let tone: BeginnerTone
    let referenceLine: String
}

enum GoldPositionAdvisor {
    static func analyze(
        currentPrice: Double,
        grams: Double,
        averageCost: Double,
        report: GoldAdvancedStrategyReport?,
        signal: TradingSignal?
    ) -> GoldHoldingAdvice? {
        guard grams > 0, averageCost > 0, currentPrice > 0 else { return nil }

        let costBasis = grams * averageCost
        let marketValue = grams * currentPrice
        let profitLoss = marketValue - costBasis
        let profitPercent = (currentPrice - averageCost) / averageCost
        let breakEvenGap = averageCost - currentPrice
        let marketTone = makeMarketTone(report: report, signal: signal)
        let plan = makePlan(
            currentPrice: currentPrice,
            averageCost: averageCost,
            profitPercent: profitPercent,
            breakEvenGap: breakEvenGap,
            marketTone: marketTone,
            report: report
        )

        return GoldHoldingAdvice(
            grams: grams,
            averageCost: averageCost,
            currentPrice: currentPrice,
            costBasis: costBasis,
            marketValue: marketValue,
            profitLoss: profitLoss,
            profitPercent: profitPercent,
            breakEvenGap: breakEvenGap,
            actionTitle: plan.title,
            reason: plan.reason,
            actionItems: plan.items,
            tone: plan.tone,
            referenceLine: plan.referenceLine
        )
    }

    private static func makePlan(
        currentPrice: Double,
        averageCost: Double,
        profitPercent: Double,
        breakEvenGap: Double,
        marketTone: PositionMarketTone,
        report: GoldAdvancedStrategyReport?
    ) -> (title: String, reason: String, items: [String], tone: BeginnerTone, referenceLine: String) {
        let trendName = report?.regime.regime.rawValue ?? "信号积累中"
        let suggestedExposure = report?.risk.suggestedExposure ?? 0.10
        let maxAddRatio = min(max(suggestedExposure, 0.05), 0.25)

        if profitPercent <= -0.015 {
            if marketTone == .defensive {
                return (
                    "亏损中，先别急着补",
                    "当前离回本价还差 \(abs(breakEvenGap).goldAdvisorPriceText)/g，行情又偏防守。为了争取更高收益，第一步是避免越跌越买把成本压得太重。",
                    [
                        "等价格重新企稳后再考虑补仓，不用为了回本频繁操作。",
                        "如果后面信号转强，把计划补仓资金拆成 3 份，每次只用一小份。",
                        "先把心理回本线记在 \(averageCost.goldAdvisorPriceText)/g，低于它时重点看风险。"
                    ],
                    .defensive,
                    "回本价 \(averageCost.goldAdvisorPriceText)/g"
                )
            }

            let targetAverage = averageCost - abs(averageCost - currentPrice) * 0.35
            return (
                "可小额分批拉低成本",
                "你现在是浮亏，市场不是强防守状态。可以把补仓当成摊低均价，而不是一次性赌反弹。",
                [
                    "第一笔补仓控制在计划资金的 \(maxAddRatio.goldAdvisorPercentText) 左右，别一次打满。",
                    "若价格继续下探，保留第二、第三笔；若回到 \(averageCost.goldAdvisorPriceText)/g 附近，先看能否减压。",
                    "一个温和目标是把持仓均价慢慢压向 \(targetAverage.goldAdvisorPriceText)/g，而不是马上追求翻红。"
                ],
                marketTone == .positive ? .positive : .cautious,
                "回本价 \(averageCost.goldAdvisorPriceText)/g"
            )
        }

        if profitPercent >= 0.015 {
            if profitPercent >= 0.08 || marketTone == .defensive {
                return (
                    "已有盈利，可先锁一部分",
                    "当前每克盈利约 \((currentPrice - averageCost).goldAdvisorPriceText)，继续拿有机会扩大收益，但把一部分利润落袋可以降低回撤。",
                    [
                        "可考虑卖出 20%-30% 锁定利润，剩余部分继续跟随行情。",
                        "若价格继续强势，剩余仓位跟着跑；若跌回买入均价附近，避免盈利变亏损。",
                        "不要因为已经赚钱就追加过多，新增买入仍看行情信号。"
                    ],
                    .positive,
                    "保本线 \(averageCost.goldAdvisorPriceText)/g"
                )
            }

            return (
                "盈利中，可继续持有",
                "你的持仓已经高于成本，\(trendName) 下可以让利润继续奔跑，但要提前想好回撤线。",
                [
                    "先保留主仓位，观察能否继续走高。",
                    "把 \(averageCost.goldAdvisorPriceText)/g 附近当作保本参考，跌近它就减少犹豫。",
                    "如果短时间涨太快，再考虑分批卖一部分。"
                ],
                .positive,
                "保本线 \(averageCost.goldAdvisorPriceText)/g"
            )
        }

        return (
            "接近成本，先等方向",
            "目前盈亏不大，最容易因为着急操作来回磨损。想提高收益，重点是等更清楚的价格方向。",
            [
                "暂时不必为了回本反复买卖。",
                "若信号转强，可小额加一点；若转弱，先守住本金。",
                "把 \(averageCost.goldAdvisorPriceText)/g 当作分界线，高于它偏进攻，低于它偏防守。"
            ],
            .cautious,
            "成本线 \(averageCost.goldAdvisorPriceText)/g"
        )
    }

    private static func makeMarketTone(
        report: GoldAdvancedStrategyReport?,
        signal: TradingSignal?
    ) -> PositionMarketTone {
        if report?.regime.volatilityRegime == .extreme ||
            report?.regime.regime == .strongDowntrend ||
            signal?.direction == .sell {
            return .defensive
        }

        if report?.compositeDirection == .buy ||
            signal?.direction == .buy ||
            report?.regime.regime == .strongUptrend ||
            report?.regime.regime == .weakUptrend {
            return .positive
        }

        return .cautious
    }
}

private enum PositionMarketTone {
    case positive
    case cautious
    case defensive
}

private extension Double {
    var goldAdvisorPriceText: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var goldAdvisorPercentText: String {
        formatted(.percent.precision(.fractionLength(0)))
    }
}
