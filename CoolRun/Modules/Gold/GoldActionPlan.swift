import Foundation

// MARK: - 明确的动作

/// 五档动作，从「明确买入」到「明确卖出」。
/// 之所以不用「谨慎」「观望」这种糊话，是因为用户要的是能执行的结论：
/// 买不买、买多少、什么价位、错了在哪走。
enum GoldActionVerb: String, Sendable, CaseIterable {
    case buy
    case accumulate
    case hold
    case reduce
    case sell

    nonisolated func title(_ language: AppLanguage) -> String {
        switch self {
        case .buy:
            LocalizedString.l(language, en: "Buy", zh: "买入", ja: "買い", ko: "매수")
        case .accumulate:
            LocalizedString.l(language, en: "Buy in steps", zh: "分批买入", ja: "分割買い", ko: "분할 매수")
        case .hold:
            LocalizedString.l(language, en: "Hold", zh: "持有观望", ja: "様子見", ko: "보유 관망")
        case .reduce:
            LocalizedString.l(language, en: "Trim", zh: "减仓", ja: "一部売却", ko: "비중 축소")
        case .sell:
            LocalizedString.l(language, en: "Sell", zh: "卖出", ja: "売却", ko: "매도")
        }
    }

    /// 一句话解释这一步在做什么，避免用户只看大字。
    nonisolated func detail(_ language: AppLanguage) -> String {
        switch self {
        case .buy:
            LocalizedString.l(
                language,
                en: "Signals agree; the plan is to buy now at the entry zone.",
                zh: "信号方向一致，按下方区间直接建仓。",
                ja: "シグナルが一致しています。下のゾーンで買い建てます。",
                ko: "신호가 일치합니다. 아래 구간에서 매수합니다."
            )
        case .accumulate:
            LocalizedString.l(
                language,
                en: "Leaning up, not confirmed; split the position instead of one shot.",
                zh: "方向偏多但还没确认，分几次买，别一把梭。",
                ja: "上方向だが未確認。一度に買わず分割で。",
                ko: "상방이지만 미확인. 한 번에 사지 말고 분할하세요."
            )
        case .hold:
            LocalizedString.l(
                language,
                en: "Signals conflict. No position: buy only near the lower entry edge, in steps. Holding: keep it, exit below the stop.",
                zh: "多空信号互相抵消。没仓位就等价格回到买入区下沿再分批；已有仓位拿着，跌破止损再走。",
                ja: "強弱が拮抗。未保有なら買いゾーン下沿で分割、保有中なら損切りまで維持。",
                ko: "신호가 상충합니다. 미보유 시 매수 구간 하단에서 분할, 보유 중이면 손절까지 유지."
            )
        case .reduce:
            LocalizedString.l(
                language,
                en: "Downside risk is rising; cut part of the position, keep the rest.",
                zh: "下行风险在变大，先减掉一部分，别全砸出去。",
                ja: "下振れリスクが増加。一部を利確・損切りします。",
                ko: "하방 위험이 커집니다. 일부를 줄이세요."
            )
        case .sell:
            LocalizedString.l(
                language,
                en: "Bearish signals dominate; exit rather than hope for a bounce.",
                zh: "空头信号占优，先离场，别赌反弹。",
                ja: "弱気が優勢。リバウンド狙いより退避を。",
                ko: "약세 우위. 반등 기대보다 이탈이 낫습니다."
            )
        }
    }

    nonisolated var symbol: String {
        switch self {
        case .buy: "arrow.up.forward.circle.fill"
        case .accumulate: "arrow.up.right.circle"
        case .hold: "pause.circle.fill"
        case .reduce: "arrow.down.right.circle"
        case .sell: "arrow.down.forward.circle.fill"
        }
    }

    /// 用于排序/测试：正数偏多，负数偏空。
    nonisolated var bias: Int {
        switch self {
        case .buy: 2
        case .accumulate: 1
        case .hold: 0
        case .reduce: -1
        case .sell: -2
        }
    }

    nonisolated var isBullish: Bool { bias > 0 }
    nonisolated var isBearish: Bool { bias < 0 }
}

// MARK: - 计划

/// 一份能照着做的计划：动作、仓位、三个价位、理由、风险、失效条件。
struct GoldActionPlan: Sendable, Equatable {
    let verb: GoldActionVerb
    /// 0…1
    let confidence: Double
    /// 建议占总资金的比例（0…1）
    let exposurePercent: Double
    let entryLow: Double
    let entryHigh: Double
    let stopLoss: Double
    let target: Double
    let horizonDays: Int
    let reasons: [String]
    let risks: [String]
    let invalidation: String
    /// 模型给的一周上涨概率，没有预测时为空
    let probabilityUp: Double?
    let generatedAt: Date

    nonisolated var isActionable: Bool { verb != .hold }
}

// MARK: - 计划生成

enum GoldActionPlanner {
    /// 一周预测的持有窗口
    nonisolated static let defaultHorizonDays = 7
    /// 动作分档阈值：|score| 超过它才算明确方向
    nonisolated static let decisiveThreshold = 0.42
    nonisolated static let leanThreshold = 0.18

    /// 综合打分：每个分项都落在 -1…1，再按权重相加。
    /// 权重体现的是「这个信号有多可信」，不是「它有多重要」——
    /// 趋势和模型预测权重最高，宏观新闻最低（它噪音最大）。
    nonisolated static func score(
        snapshot: TechnicalSnapshot,
        signal: TradingSignal?,
        report: GoldAdvancedStrategyReport?,
        weeklyForecast: GoldWeeklyForecast?
    ) -> Double {
        var total = 0.0

        if let report {
            // 趋势：-1…1
            total += clamp(report.regime.trendScore) * 0.30
            // 蒙特卡洛 7 日上涨概率：0.5 为中性
            if let forecast = report.forecast {
                total += clamp((forecast.probabilityAboveCurrent - 0.5) * 2.4) * 0.22
            }
            // 均值回归：价格越偏离均值越有反向压力
            if let meanReversion = report.meanReversion {
                total += clamp(-meanReversion.zScore / 2.2) * 0.10
            }
            // 宏观新闻：噪音大，只给一点权重
            if let context = report.marketContext {
                total += clamp(context.overallScore / 100) * 0.08
            }
        }

        if let weeklyForecast {
            let directionBias: Double
            switch weeklyForecast.direction {
            case .up: directionBias = 1
            case .flat: directionBias = 0
            case .down: directionBias = -1
            }
            let weight: Double
            switch weeklyForecast.confidence {
            case .high: weight = 0.20
            case .medium: weight = 0.14
            case .low: weight = 0.06
            case .unavailable: weight = 0
            }
            total += directionBias * weight
        } else if let signal {
            // 没有周预测时，用技术信号补位
            total += clamp(signal.score / 100) * 0.12
        }

        // RSI 极值：超卖加分、超买减分
        if let rsi = snapshot.rsi14 {
            if rsi <= 30 { total += 0.10 }
            else if rsi >= 70 { total -= 0.10 }
        }

        // 均线排列
        if let sma5 = snapshot.sma5, let sma20 = snapshot.sma20, let sma60 = snapshot.sma60 {
            if sma5 > sma20 && sma20 > sma60 { total += 0.10 }
            else if sma5 < sma20 && sma20 < sma60 { total -= 0.10 }
        }

        return clamp(total)
    }

    nonisolated static func verb(for score: Double) -> GoldActionVerb {
        if score >= decisiveThreshold { return .buy }
        if score >= leanThreshold { return .accumulate }
        if score <= -decisiveThreshold { return .sell }
        if score <= -leanThreshold { return .reduce }
        return .hold
    }

    /// 主入口。拿不到当前价或波动率时返回 nil，UI 直接不显示这张卡。
    nonisolated static func plan(
        currentPrice: Double,
        snapshot: TechnicalSnapshot,
        signal: TradingSignal?,
        report: GoldAdvancedStrategyReport?,
        weeklyForecast: GoldWeeklyForecast?,
        language: AppLanguage,
        now: Date = Date()
    ) -> GoldActionPlan? {
        guard currentPrice > 0 else { return nil }

        var composite = score(
            snapshot: snapshot,
            signal: signal,
            report: report,
            weeklyForecast: weeklyForecast
        )

        // 极端波动里不给「买入」这种明确指令——那种时候任何计划都会被打穿。
        let isExtreme = report?.regime.volatilityRegime == .extreme
        if isExtreme {
            composite = min(composite, leanThreshold - 0.01)
        }

        let verb = verb(for: composite)
        let confidence = confidenceValue(composite: composite, report: report)
        let dailyMove = dailyMoveEstimate(price: currentPrice, snapshot: snapshot)
        let levels = priceLevels(
            verb: verb,
            price: currentPrice,
            dailyMove: dailyMove,
            snapshot: snapshot,
            forecast: report?.forecast
        )

        let exposure = suggestedExposure(verb: verb, report: report)
        let reasons = buildReasons(
            verb: verb,
            snapshot: snapshot,
            report: report,
            weeklyForecast: weeklyForecast,
            language: language
        )
        let risks = buildRisks(
            snapshot: snapshot,
            report: report,
            forecast: report?.forecast,
            language: language
        )

        return GoldActionPlan(
            verb: verb,
            confidence: confidence,
            exposurePercent: exposure,
            entryLow: levels.entryLow,
            entryHigh: levels.entryHigh,
            stopLoss: levels.stopLoss,
            target: levels.target,
            horizonDays: defaultHorizonDays,
            reasons: reasons,
            risks: risks,
            invalidation: invalidationText(
                verb: verb,
                stopLoss: levels.stopLoss,
                entryHigh: levels.entryHigh,
                language: language
            ),
            probabilityUp: report?.forecast?.probabilityAboveCurrent,
            generatedAt: now
        )
    }

    // MARK: - 分项

    nonisolated static func confidenceValue(
        composite: Double,
        report: GoldAdvancedStrategyReport?
    ) -> Double {
        // 方向越明确、市场状态越清楚，信心越高；封顶 0.92，不假装确定。
        let strength = min(abs(composite) / 0.9, 1)
        let regimeConfidence = report?.regime.confidence ?? 0.4
        return clamp(0.30 + strength * 0.45 + regimeConfidence * 0.20, lower: 0.05, upper: 0.92)
    }

    /// 单日波动幅度估计：优先用年化波动率换算，退化时用 0.6%。
    nonisolated static func dailyMoveEstimate(price: Double, snapshot: TechnicalSnapshot) -> Double {
        if let annualized = snapshot.volatility, annualized > 0, annualized.isFinite {
            let daily = price * annualized / 252.0.squareRoot()
            return min(max(daily, price * 0.0015), price * 0.05)
        }
        return price * 0.006
    }

    struct PriceLevels: Sendable, Equatable {
        let entryLow: Double
        let entryHigh: Double
        let stopLoss: Double
        let target: Double
    }

    nonisolated static func priceLevels(
        verb: GoldActionVerb,
        price: Double,
        dailyMove: Double,
        snapshot: TechnicalSnapshot,
        forecast: MonteCarloForecast?
    ) -> PriceLevels {
        // 止损放在 1.8 倍日均波动外，再被支撑/压力位修正一次：
        // 支撑位比「价格减固定百分比」更接近真实会被打到的位置。
        let stopDistance = dailyMove * 1.8
        let targetDistance = dailyMove * 3.2

        switch verb {
        case .buy, .accumulate:
            let supportStop = snapshot.supportLevel.map { min($0 * 0.997, price - dailyMove * 0.8) } ?? (price - stopDistance)
            let stop = min(price - stopDistance * 0.6, supportStop)
            var target = price + targetDistance
            if let forecast, forecast.p90 > price {
                // 模型自己给的 7 日上界更贴近现实，别喊一个模型都不同意的目标
                target = min(target, forecast.p90)
            }
            if let resistance = snapshot.resistanceLevel, resistance > price {
                target = min(max(target, price + dailyMove * 1.5), max(resistance, price + dailyMove * 1.5))
            }
            return PriceLevels(
                entryLow: price - dailyMove * 0.55,
                entryHigh: price + dailyMove * 0.25,
                stopLoss: stop,
                target: max(target, price + dailyMove * 1.2)
            )

        case .hold:
            return PriceLevels(
                entryLow: price - dailyMove * 0.8,
                entryHigh: price + dailyMove * 0.8,
                stopLoss: price - stopDistance,
                target: price + targetDistance
            )

        case .reduce, .sell:
            var target = price - targetDistance
            if let forecast, forecast.p10 > 0, forecast.p10 < price {
                target = max(target, forecast.p10)
            }
            let resistanceStop = snapshot.resistanceLevel.map { max($0 * 1.003, price + dailyMove * 0.8) } ?? (price + stopDistance)
            return PriceLevels(
                entryLow: price - dailyMove * 0.25,
                entryHigh: price + dailyMove * 0.55,
                stopLoss: max(price + stopDistance * 0.6, resistanceStop),
                target: min(target, price - dailyMove * 1.2)
            )
        }
    }

    nonisolated static func suggestedExposure(
        verb: GoldActionVerb,
        report: GoldAdvancedStrategyReport?
    ) -> Double {
        let base = report?.risk.suggestedExposure ?? 0.05
        switch verb {
        case .buy: return clamp(base, lower: 0.02, upper: 0.30)
        case .accumulate: return clamp(base * 0.6, lower: 0.01, upper: 0.20)
        case .hold: return clamp(base * 0.8, lower: 0.01, upper: 0.20)
        case .reduce: return clamp(base * 0.4, lower: 0, upper: 0.12)
        case .sell: return 0
        }
    }

    nonisolated static func buildReasons(
        verb: GoldActionVerb,
        snapshot: TechnicalSnapshot,
        report: GoldAdvancedStrategyReport?,
        weeklyForecast: GoldWeeklyForecast?,
        language: AppLanguage
    ) -> [String] {
        var reasons: [String] = []

        if let report {
            reasons.append(regimeReason(report, language: language))
        }

        if let sma5 = snapshot.sma5, let sma20 = snapshot.sma20 {
            let gap = (sma5 - sma20) / sma20 * 100
            if gap >= 0.3 {
                reasons.append(LocalizedString.l(
                    language,
                    en: "SMA5 is \(signed(gap))% above SMA20 — short-term trend is up.",
                    zh: "SMA5 比 SMA20 高 \(signed(gap))%，短线在上方。",
                    ja: "SMA5 は SMA20 より \(signed(gap))% 上。短期は上向き。",
                    ko: "SMA5가 SMA20보다 \(signed(gap))% 위. 단기 상승."
                ))
            } else if gap <= -0.3 {
                reasons.append(LocalizedString.l(
                    language,
                    en: "SMA5 is \(signed(gap))% below SMA20 — short-term trend is down.",
                    zh: "SMA5 比 SMA20 低 \(signed(gap))%，短线在下方。",
                    ja: "SMA5 は SMA20 より \(signed(gap))% 下。短期は下向き。",
                    ko: "SMA5가 SMA20보다 \(signed(gap))% 아래. 단기 하락."
                ))
            } else {
                reasons.append(LocalizedString.l(
                    language,
                    en: "SMA5 and SMA20 are within 0.3% — no short-term trend.",
                    zh: "SMA5 与 SMA20 相差不到 0.3%，短线没有方向。",
                    ja: "SMA5 と SMA20 の差は 0.3% 未満で方向なし。",
                    ko: "SMA5와 SMA20 차이가 0.3% 미만. 방향 없음."
                ))
            }
        }

        if let rsi = snapshot.rsi14 {
            let value = formatted(rsi, digits: 1)
            if rsi >= 70 {
                reasons.append(LocalizedString.l(
                    language,
                    en: "RSI \(value) is overbought — chasing here has poor odds.",
                    zh: "RSI \(value) 已超买，这个位置追进去性价比低。",
                    ja: "RSI \(value) は買われ過ぎ。ここでの追随は分が悪い。",
                    ko: "RSI \(value) 과매수. 여기서 추격은 불리."
                ))
            } else if rsi <= 30 {
                reasons.append(LocalizedString.l(
                    language,
                    en: "RSI \(value) is oversold — bounce odds improve.",
                    zh: "RSI \(value) 已超卖，反弹概率在上升。",
                    ja: "RSI \(value) は売られ過ぎ。反発の確率が上がる。",
                    ko: "RSI \(value) 과매도. 반등 확률 상승."
                ))
            } else {
                reasons.append(LocalizedString.l(
                    language,
                    en: "RSI \(value) sits mid-range — room to move either way.",
                    zh: "RSI \(value) 在中段，上下都还有空间。",
                    ja: "RSI \(value) は中間。上下どちらにも余地。",
                    ko: "RSI \(value) 중간대. 양방향 여지 있음."
                ))
            }
        }

        if let forecast = weeklyForecast {
            let probability = formatted(forecast.p50, digits: 2)
            let direction: String
            switch forecast.direction {
            case .up: direction = LocalizedString.l(language, en: "up", zh: "上涨", ja: "上昇", ko: "상승")
            case .flat: direction = LocalizedString.l(language, en: "flat", zh: "持平", ja: "横ばい", ko: "보합")
            case .down: direction = LocalizedString.l(language, en: "down", zh: "下跌", ja: "下落", ko: "하락")
            }
            reasons.append(LocalizedString.l(
                language,
                en: "Weekly model: \(direction), median \(probability) (p10 \(formatted(forecast.p10, digits: 2)), p90 \(formatted(forecast.p90, digits: 2))).",
                zh: "一周模型看\(direction)，中位价 \(probability)（区间 \(formatted(forecast.p10, digits: 2))–\(formatted(forecast.p90, digits: 2))）。",
                ja: "週間モデルは\(direction)、中値 \(probability)（\(formatted(forecast.p10, digits: 2))–\(formatted(forecast.p90, digits: 2))）。",
                ko: "주간 모델 \(direction), 중간값 \(probability) (\(formatted(forecast.p10, digits: 2))–\(formatted(forecast.p90, digits: 2)))."
            ))
        } else if let forecast = report?.forecast {
            let probability = Int((forecast.probabilityAboveCurrent * 100).rounded())
            reasons.append(LocalizedString.l(
                language,
                en: "Monte Carlo: \(probability)% chance price is higher in 7 days.",
                zh: "蒙特卡洛：7 天后价格更高的概率 \(probability)%。",
                ja: "モンテカルロ：7 日後に上昇する確率 \(probability)%。",
                ko: "몬테카를로: 7일 후 상승 확률 \(probability)%."
            ))
        }

        if let context = report?.marketContext, abs(context.overallScore) >= 10 {
            let score = Int(context.overallScore.rounded())
            reasons.append(LocalizedString.l(
                language,
                en: "Macro/news score \(signed(Double(score))) — \(score > 0 ? "supportive" : "a headwind").",
                zh: "宏观与消息面评分 \(signed(Double(score)))，\(score > 0 ? "偏正面" : "偏压制")。",
                ja: "マクロ・ニュース評価 \(signed(Double(score)))、\(score > 0 ? "追い風" : "向かい風")。",
                ko: "거시·뉴스 점수 \(signed(Double(score))), \(score > 0 ? "우호적" : "부담")."
            ))
        }

        // 动作本身至少有一条支撑句，避免出现「理由为空」的卡片
        if reasons.isEmpty {
            reasons.append(LocalizedString.l(
                language,
                en: "Signals are \(verb.isBullish ? "mildly positive" : verb.isBearish ? "mildly negative" : "mixed"); no single factor dominates.",
                zh: "信号\(verb.isBullish ? "略偏正面" : verb.isBearish ? "略偏负面" : "多空交织")，没有单项占绝对优势。",
                ja: "シグナルは\(verb.isBullish ? "やや強気" : verb.isBearish ? "やや弱気" : "拮抗")。決め手に欠けます。",
                ko: "신호가 \(verb.isBullish ? "약간 긍정" : verb.isBearish ? "약간 부정" : "혼재"). 결정적 요인 없음."
            ))
        }

        return Array(reasons.prefix(4))
    }

    nonisolated static func buildRisks(
        snapshot: TechnicalSnapshot,
        report: GoldAdvancedStrategyReport?,
        forecast: MonteCarloForecast?,
        language: AppLanguage
    ) -> [String] {
        var risks: [String] = []

        if report?.regime.volatilityRegime == .extreme {
            risks.append(LocalizedString.l(
                language,
                en: "Volatility is extreme — widen stops or stay out.",
                zh: "波动率处于极端区间，止损要放宽或者干脆别进场。",
                ja: "ボラティリティが極端。損切りを広げるか見送り。",
                ko: "변동성이 극단적. 손절을 넓히거나 관망."
            ))
        }

        if let forecast, let price = snapshot.bollingerMiddle, forecast.p10 < price * 0.94 {
            risks.append(LocalizedString.l(
                language,
                en: "Downside tail: 10% of simulations end below \(formatted(forecast.p10, digits: 2)).",
                zh: "下行尾部：有 10% 的模拟结果会跌到 \(formatted(forecast.p10, digits: 2)) 以下。",
                ja: "下振れテール：10% のシナリオは \(formatted(forecast.p10, digits: 2)) 未満。",
                ko: "하방 꼬리: 시뮬레이션 10%가 \(formatted(forecast.p10, digits: 2)) 미만."
            ))
        }

        if let report, report.risk.warning != nil {
            risks.append(LocalizedString.l(
                language,
                en: "Position size warning from the risk model — do not exceed the suggested exposure.",
                zh: "风险模型给了仓位警告，别超过建议仓位。",
                ja: "リスクモデルが警告。推奨比率を超えないでください。",
                ko: "리스크 모델 경고. 권장 비중을 넘기지 마세요."
            ))
        }

        if risks.isEmpty {
            risks.append(LocalizedString.l(
                language,
                en: "Model risk: this is a statistical read, not a guarantee. Gold can gap on news.",
                zh: "模型风险：这是统计判断，不是保证；消息面会让金价跳空。",
                ja: "モデルリスク：統計的判断であり保証ではありません。ニュースで窓が開きます。",
                ko: "모델 위험: 통계적 판단이며 보장이 아닙니다. 뉴스로 갭이 생깁니다."
            ))
        }

        return Array(risks.prefix(2))
    }

    nonisolated static func invalidationText(
        verb: GoldActionVerb,
        stopLoss: Double,
        entryHigh: Double? = nil,
        language: AppLanguage
    ) -> String {
        let level = formatted(stopLoss, digits: 2)
        switch verb {
        case .buy, .accumulate:
            return LocalizedString.l(
                language,
                en: "Plan is void if price closes below \(level) — exit, do not average down.",
                zh: "价格收在 \(level) 下方，这份计划作废，直接走，别补仓摊平。",
                ja: "\(level) を下回って引けたら計画は無効。買い増しせず撤退。",
                ko: "\(level) 아래로 마감하면 계획 무효. 물타지 말고 이탈."
            )
        case .hold:
            let upper = entryHigh.map { formatted($0, digits: 2) } ?? level
            return LocalizedString.l(
                language,
                en: "Re-run this plan if price closes with volume above \(upper) or below \(level).",
                zh: "收盘价带量站上 \(upper) 或跌破 \(level)，这份计划作废，按新趋势重算。",
                ja: "\(upper) を上抜け、または \(level) を下抜けて引けたら計画は無効。再計算。",
                ko: "\(upper) 위 또는 \(level) 아래로 마감하면 계획 무효. 다시 계산."
            )
        case .reduce, .sell:
            return LocalizedString.l(
                language,
                en: "Bearish plan is void if price closes above \(level).",
                zh: "价格收在 \(level) 上方，看空计划作废。",
                ja: "\(level) を上回って引けたら弱気計画は無効。",
                ko: "\(level) 위로 마감하면 약세 계획 무효."
            )
        }
    }

    // MARK: - 文案小工具

    nonisolated private static func regimeReason(
        _ report: GoldAdvancedStrategyReport,
        language: AppLanguage
    ) -> String {
        let regime: String
        switch report.regime.regime {
        case .strongUptrend:
            regime = LocalizedString.l(language, en: "strong uptrend", zh: "强上升趋势", ja: "強い上昇トレンド", ko: "강한 상승 추세")
        case .weakUptrend:
            regime = LocalizedString.l(language, en: "weak uptrend", zh: "弱上升趋势", ja: "弱い上昇トレンド", ko: "약한 상승 추세")
        case .ranging:
            regime = LocalizedString.l(language, en: "range-bound", zh: "区间震荡", ja: "レンジ相場", ko: "박스권")
        case .weakDowntrend:
            regime = LocalizedString.l(language, en: "weak downtrend", zh: "弱下降趋势", ja: "弱い下降トレンド", ko: "약한 하락 추세")
        case .strongDowntrend:
            regime = LocalizedString.l(language, en: "strong downtrend", zh: "强下降趋势", ja: "強い下降トレンド", ko: "강한 하락 추세")
        }
        let adx = formatted(report.regime.adx, digits: 1)
        return LocalizedString.l(
            language,
            en: "Market state: \(regime) (ADX \(adx)).",
            zh: "市场状态：\(regime)，ADX \(adx)。",
            ja: "相場状態：\(regime)（ADX \(adx)）。",
            ko: "시장 상태: \(regime) (ADX \(adx))."
        )
    }

    nonisolated static func formatted(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    nonisolated private static func signed(_ value: Double) -> String {
        let text = formatted(abs(value), digits: 2)
        return value >= 0 ? "+\(text)" : "-\(text)"
    }

    nonisolated private static func clamp(
        _ value: Double,
        lower: Double = -1,
        upper: Double = 1
    ) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, lower), upper)
    }
}
