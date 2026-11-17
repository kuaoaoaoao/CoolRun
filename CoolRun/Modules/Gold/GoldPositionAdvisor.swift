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
        signal: TradingSignal?,
        lang: AppLanguage
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
            report: report,
            lang: lang
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
        report: GoldAdvancedStrategyReport?,
        lang: AppLanguage
    ) -> (title: String, reason: String, items: [String], tone: BeginnerTone, referenceLine: String) {
        let trendName = report?.regime.regime.displayName(lang: lang)
            ?? LocalizedString.l(lang, en: "Collecting signals", zh: "信号积累中", ja: "シグナル蓄積中", ko: "신호 수집 중")
        let suggestedExposure = report?.risk.suggestedExposure ?? 0.10
        let maxAddRatio = min(max(suggestedExposure, 0.05), 0.25)

        if profitPercent <= -0.015 {
            if marketTone == .defensive {
                return (
                    LocalizedString.l(lang, en: "Losing; don't rush to average down", zh: "亏损中，先别急着补", ja: "含み損。まずは買い増しを急がない", ko: "손실 중, 서둘러 추가 매수하지 마세요"),
                    LocalizedString.l(
                        lang,
                        en: "You are \(abs(breakEvenGap).goldAdvisorPriceText)/g away from break-even and the market is defensive. To improve returns, the first step is to avoid buying all the way down and piling up too much cost.",
                        zh: "当前离回本价还差 \(abs(breakEvenGap).goldAdvisorPriceText)/g，行情又偏防守。为了争取更高收益，第一步是避免越跌越买把成本压得太重。",
                        ja: "損益分岐まであと \(abs(breakEvenGap).goldAdvisorPriceText)/g、相場も守勢寄りです。収益を狙う第一歩は、下落のたびに買ってコストを重くしないことです。",
                        ko: "본전까지 \(abs(breakEvenGap).goldAdvisorPriceText)/g 남았고 시장도 방어적입니다. 수익을 높이려면 먼저 하락할 때마다 사서 평단을 무겁게 만들지 않는 것이 중요합니다."
                    ),
                    [
                        LocalizedString.l(lang, en: "Wait for price to stabilize before adding; no need to trade often just to break even.", zh: "等价格重新企稳后再考虑补仓，不用为了回本频繁操作。", ja: "価格が落ち着いてから買い増しを検討しましょう。取り戻すために頻繁に売買する必要はありません。", ko: "가격이 다시 안정된 뒤 추가 매수를 검토하세요. 본전을 위해 자주 매매할 필요는 없습니다."),
                        LocalizedString.l(lang, en: "If signals turn stronger later, split the planned add-on budget into 3 parts and use only one at a time.", zh: "如果后面信号转强，把计划补仓资金拆成 3 份，每次只用一小份。", ja: "今後シグナルが強まったら、買い増し予定資金を3分割し、1回につき1つだけ使います。", ko: "이후 신호가 강해지면 추가 매수 자금을 3등분해 한 번에 한 몫만 사용하세요."),
                        LocalizedString.l(lang, en: "Keep \(averageCost.goldAdvisorPriceText)/g as your mental break-even line; below it, focus on risk.", zh: "先把心理回本线记在 \(averageCost.goldAdvisorPriceText)/g，低于它时重点看风险。", ja: "まずは \(averageCost.goldAdvisorPriceText)/g を心の損益分岐として意識し、下回ったらリスクを優先して見ます。", ko: "우선 \(averageCost.goldAdvisorPriceText)/g를 심리적 본전선으로 두고, 그 아래에서는 위험을 우선 보세요.")
                    ],
                    .defensive,
                    LocalizedString.l(lang, en: "Break-even \(averageCost.goldAdvisorPriceText)/g", zh: "回本价 \(averageCost.goldAdvisorPriceText)/g", ja: "損益分岐 \(averageCost.goldAdvisorPriceText)/g", ko: "본전 \(averageCost.goldAdvisorPriceText)/g")
                )
            }

            let targetAverage = averageCost - abs(averageCost - currentPrice) * 0.35
            return (
                LocalizedString.l(lang, en: "Small batches can lower your cost", zh: "可小额分批拉低成本", ja: "少額の分割でコストを下げる", ko: "소액 분할로 평단 낮추기"),
                LocalizedString.l(
                    lang,
                    en: "You are in the red but the market is not strongly defensive. Treat adding as lowering your average cost, not as a one-shot bet on a rebound.",
                    zh: "你现在是浮亏，市场不是强防守状态。可以把补仓当成摊低均价，而不是一次性赌反弹。",
                    ja: "現在は含み損ですが、相場は強い守勢ではありません。買い増しは反発への一発勝負ではなく、平均コストを下げる作業と考えましょう。",
                    ko: "지금은 평가손실이지만 시장이 강한 방어 국면은 아닙니다. 추가 매수를 반등에 대한 한 번의 베팅이 아니라 평단을 낮추는 작업으로 보세요."
                ),
                [
                    LocalizedString.l(lang, en: "Keep the first add-on around \(maxAddRatio.goldAdvisorPercentText) of the planned budget; don't use it all at once.", zh: "第一笔补仓控制在计划资金的 \(maxAddRatio.goldAdvisorPercentText) 左右，别一次打满。", ja: "1回目の買い増しは予定資金の \(maxAddRatio.goldAdvisorPercentText) 程度に抑え、一度に使い切らないように。", ko: "첫 추가 매수는 계획 자금의 \(maxAddRatio.goldAdvisorPercentText) 정도로 제한하고 한 번에 다 쓰지 마세요."),
                    LocalizedString.l(lang, en: "If price keeps sliding, keep the second and third tranches; if it returns near \(averageCost.goldAdvisorPriceText)/g, first check whether you can reduce pressure.", zh: "若价格继续下探，保留第二、第三笔；若回到 \(averageCost.goldAdvisorPriceText)/g 附近，先看能否减压。", ja: "さらに下げる場合は2回目・3回目を残しておき、\(averageCost.goldAdvisorPriceText)/g 付近に戻ったら負担を減らせるか先に確認しましょう。", ko: "가격이 더 내려가면 두 번째·세 번째 몫을 남겨 두고, \(averageCost.goldAdvisorPriceText)/g 부근으로 돌아오면 부담을 줄일 수 있는지 먼저 확인하세요."),
                    LocalizedString.l(lang, en: "A gentle goal is to nudge your average cost toward \(targetAverage.goldAdvisorPriceText)/g rather than turning green right away.", zh: "一个温和目标是把持仓均价慢慢压向 \(targetAverage.goldAdvisorPriceText)/g，而不是马上追求翻红。", ja: "穏やかな目標は、すぐにプラス転換を狙うのではなく、保有平均を \(targetAverage.goldAdvisorPriceText)/g へ徐々に近づけることです。", ko: "완만한 목표는 곧바로 플러스 전환을 노리는 대신 평단을 \(targetAverage.goldAdvisorPriceText)/g 쪽으로 천천히 낮추는 것입니다.")
                ],
                marketTone == .positive ? .positive : .cautious,
                LocalizedString.l(lang, en: "Break-even \(averageCost.goldAdvisorPriceText)/g", zh: "回本价 \(averageCost.goldAdvisorPriceText)/g", ja: "損益分岐 \(averageCost.goldAdvisorPriceText)/g", ko: "본전 \(averageCost.goldAdvisorPriceText)/g")
            )
        }

        if profitPercent >= 0.015 {
            if profitPercent >= 0.08 || marketTone == .defensive {
                return (
                    LocalizedString.l(lang, en: "In profit; consider locking part in", zh: "已有盈利，可先锁一部分", ja: "利益あり。一部を確定してよい", ko: "수익 중, 일부 확정 가능"),
                    LocalizedString.l(
                        lang,
                        en: "You are up about \((currentPrice - averageCost).goldAdvisorPriceText) per gram. Holding on may extend the gain, but banking part of it reduces drawdown.",
                        zh: "当前每克盈利约 \((currentPrice - averageCost).goldAdvisorPriceText)，继续拿有机会扩大收益，但把一部分利润落袋可以降低回撤。",
                        ja: "1gあたり約 \((currentPrice - averageCost).goldAdvisorPriceText) の利益です。持ち続ければ伸びる余地はありますが、一部を確定すると下落時の負担を減らせます。",
                        ko: "그램당 약 \((currentPrice - averageCost).goldAdvisorPriceText) 수익입니다. 계속 보유하면 더 늘릴 수 있지만 일부를 확정하면 조정 폭을 줄일 수 있습니다."
                    ),
                    [
                        LocalizedString.l(lang, en: "Consider selling 20%-30% to lock in profit and let the rest ride.", zh: "可考虑卖出 20%-30% 锁定利润，剩余部分继续跟随行情。", ja: "20%〜30% を売って利益を確定し、残りは相場に追随させましょう。", ko: "20%~30%를 매도해 이익을 확정하고 나머지는 흐름에 맡기세요."),
                        LocalizedString.l(lang, en: "If price stays strong, let the rest run; if it falls back near your average cost, avoid turning a gain into a loss.", zh: "若价格继续强势，剩余仓位跟着跑；若跌回买入均价附近，避免盈利变亏损。", ja: "価格が強いままなら残りを走らせ、買い平均付近まで戻したら利益が損失に変わるのを避けましょう。", ko: "가격이 계속 강하면 나머지는 그대로 두고, 매수 평단 부근까지 내려오면 수익이 손실로 바뀌지 않게 하세요."),
                        LocalizedString.l(lang, en: "Don't add heavily just because you are already up; new buys still follow the signals.", zh: "不要因为已经赚钱就追加过多，新增买入仍看行情信号。", ja: "すでに利益が出ているからと大きく買い増さず、新規買いはシグナルに従いましょう。", ko: "이미 수익 중이라고 크게 추가 매수하지 말고, 신규 매수는 신호를 따르세요.")
                    ],
                    .positive,
                    LocalizedString.l(lang, en: "Break-even \(averageCost.goldAdvisorPriceText)/g", zh: "保本线 \(averageCost.goldAdvisorPriceText)/g", ja: "損益分岐 \(averageCost.goldAdvisorPriceText)/g", ko: "본전선 \(averageCost.goldAdvisorPriceText)/g")
                )
            }

            return (
                LocalizedString.l(lang, en: "In profit; you can keep holding", zh: "盈利中，可继续持有", ja: "利益中。保有を続けてよい", ko: "수익 중, 계속 보유 가능"),
                LocalizedString.l(
                    lang,
                    en: "Your position is above cost, and with \(trendName) you can let profit run, but plan the drawdown line in advance.",
                    zh: "你的持仓已经高于成本，\(trendName) 下可以让利润继续奔跑，但要提前想好回撤线。",
                    ja: "保有はコストを上回っています。\(trendName) なら利益を伸ばせますが、押し目撤退ラインを先に決めておきましょう。",
                    ko: "보유 단가가 원가보다 높습니다. \(trendName) 국면에서는 수익을 더 키울 수 있지만 조정 이탈선을 미리 정해 두세요."
                ),
                [
                    LocalizedString.l(lang, en: "Keep the core position and watch whether it can push higher.", zh: "先保留主仓位，观察能否继续走高。", ja: "まずは中心の建玉を残し、さらに上昇できるか観察します。", ko: "우선 핵심 보유분은 두고 더 오를 수 있는지 지켜보세요."),
                    LocalizedString.l(lang, en: "Treat \(averageCost.goldAdvisorPriceText)/g as your break-even reference; as price nears it, hesitate less.", zh: "把 \(averageCost.goldAdvisorPriceText)/g 附近当作保本参考，跌近它就减少犹豫。", ja: "\(averageCost.goldAdvisorPriceText)/g 付近を損益分岐の目安とし、近づいたら迷わず動きましょう。", ko: "\(averageCost.goldAdvisorPriceText)/g 부근을 본전 기준으로 삼고, 가까워지면 망설이지 마세요."),
                    LocalizedString.l(lang, en: "If it rises too fast in a short time, then consider selling part in batches.", zh: "如果短时间涨太快，再考虑分批卖一部分。", ja: "短期間に上げすぎた場合に、分割で一部売却を検討しましょう。", ko: "짧은 시간에 너무 많이 오르면 그때 분할 매도를 검토하세요.")
                ],
                .positive,
                LocalizedString.l(lang, en: "Break-even \(averageCost.goldAdvisorPriceText)/g", zh: "保本线 \(averageCost.goldAdvisorPriceText)/g", ja: "損益分岐 \(averageCost.goldAdvisorPriceText)/g", ko: "본전선 \(averageCost.goldAdvisorPriceText)/g")
            )
        }

        return (
            LocalizedString.l(lang, en: "Near cost; wait for direction", zh: "接近成本，先等方向", ja: "コスト付近。まず方向待ち", ko: "원가 부근, 방향 대기"),
            LocalizedString.l(
                lang,
                en: "Profit and loss are both small, and rushed trading is what erodes returns most here. To improve results, focus on waiting for a clearer direction.",
                zh: "目前盈亏不大，最容易因为着急操作来回磨损。想提高收益，重点是等更清楚的价格方向。",
                ja: "現在の損益は小さく、焦って売買すると往復で削られやすい局面です。成果を上げる鍵は、より明確な方向を待つことです。",
                ko: "현재 손익이 크지 않고, 조급한 매매가 왕복으로 손실을 키우기 쉬운 구간입니다. 성과를 높이려면 더 분명한 방향을 기다리는 것이 핵심입니다."
            ),
            [
                LocalizedString.l(lang, en: "No need to keep trading just to break even.", zh: "暂时不必为了回本反复买卖。", ja: "取り戻すために何度も売買する必要はありません。", ko: "본전을 위해 반복 매매할 필요는 없습니다."),
                LocalizedString.l(lang, en: "If signals strengthen, add a little; if they weaken, protect your capital first.", zh: "若信号转强，可小额加一点；若转弱，先守住本金。", ja: "シグナルが強まれば少額を足し、弱まればまず元本を守りましょう。", ko: "신호가 강해지면 소액을 더하고, 약해지면 우선 원금을 지키세요."),
                LocalizedString.l(lang, en: "Treat \(averageCost.goldAdvisorPriceText)/g as the dividing line: above it lean offensive, below it lean defensive.", zh: "把 \(averageCost.goldAdvisorPriceText)/g 当作分界线，高于它偏进攻，低于它偏防守。", ja: "\(averageCost.goldAdvisorPriceText)/g を境界線とし、上なら攻め、下なら守りに傾けましょう。", ko: "\(averageCost.goldAdvisorPriceText)/g를 경계선으로 삼아, 위면 공격적, 아래면 방어적으로 대응하세요.")
            ],
            .cautious,
            LocalizedString.l(lang, en: "Cost line \(averageCost.goldAdvisorPriceText)/g", zh: "成本线 \(averageCost.goldAdvisorPriceText)/g", ja: "コスト線 \(averageCost.goldAdvisorPriceText)/g", ko: "원가선 \(averageCost.goldAdvisorPriceText)/g")
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
