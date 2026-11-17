import Foundation

// MARK: - 金价分析工具

/// 把金价模块里本来就在跑的引擎接给 Agent：技术指标、周预测、策略报告、持仓诊断。
/// 这些引擎的输入输出都已经存在，这里只做「组装参数 + 压成 JSON + 补一段机器解读」。
@MainActor
enum AgentGoldTools {
    private static var registered = false

    static func registerAll() {
        guard !registered else { return }
        registered = true

        registerTechnical()
        registerForecast()
        registerStrategy()
        registerPlan()
        registerPosition()
    }

    // MARK: - 数据准备

    private static func records(days: Int) -> [GoldPriceRecord] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return GoldPriceStore.shared.recordsSince(since)
    }

    private static func currentPrice(from records: [GoldPriceRecord]) -> Double? {
        if let quote = GoldPriceStore.shared.latestQuote?.cnyPerGram, quote > 0 {
            return quote
        }
        return records.last(where: { $0.price > 0 })?.price
    }

    /// 高频采样直接喂给技术指标会失真：本地是分钟级记录，30 天窗口里几千条，
    /// 算出来的年化波动率会低到 0.5%、布林带上下轨只差一块钱。
    /// 所以所有指标统一先归并成日收盘再算；本地不够就去拉一年远程日线。
    private static func dailyQuality(days: Int, fallback: GoldHistoryRange, minimum: Int = 60) async -> GoldDailyHistoryQuality {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let local = GoldPriceStore.shared.recordsSince(since)
            .map { GoldRemotePricePoint(price: $0.price, timestamp: $0.timestamp) }
        var quality = GoldDailyCloseNormalizer.normalize(points: local, now: Date())
        // 少于调用方要求的样本量就去拉远程。默认 60 天：再少连 SMA60 都算不出来。
        if quality.closes.count < minimum,
           let remote = try? await GoldMarketDataService.shared.fetchHistoryPrices(range: fallback) {
            quality = GoldDailyCloseNormalizer.normalize(points: remote, now: Date())
        }
        return quality
    }

    /// 策略引擎吃 `[GoldPriceRecord]`，这里把日线包回去，保证它内部算的也是日频。
    private static func dailyRecords(_ closes: [GoldDailyClose]) -> [GoldPriceRecord] {
        closes.map { GoldPriceRecord(price: $0.close, timestamp: $0.date, source: "daily") }
    }

    private static func num(_ value: Double?, digits: Int = 2) -> JSONValue {
        guard let value, value.isFinite else { return .null }
        // 用字符串格式化收口，避免 871.44000000000005 这种浮点尾巴污染模型输入。
        let rounded = Double(String(format: "%.\(digits)f", value)) ?? value
        return .number(rounded)
    }

    private static func signalLabel(_ direction: SignalDirection) -> String {
        switch direction {
        case .buy: return "买入"
        case .sell: return "卖出"
        case .hold: return "观望"
        }
    }

    private static let disclaimer = "以上为历史统计与规则模型的结果，不构成投资建议。金价受宏观、汇率、地缘影响，任何模型都无法保证未来走势。"

    // MARK: - 技术面

    private static func registerTechnical() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "gold_technical",
            summary: "读取金价技术面全貌：均线（SMA5/20/60、EMA12/26）、RSI、MACD、布林带、年化波动率、ROC、支撑阻力、最大回撤，并附带机器生成的要点解读。回答「现在能不能买」「走势如何」之前必须先调用。",
            parameters: ToolSchema.object(properties: [
                ("days", ToolSchema.integer("回看天数，默认 30", minimum: 5, maximum: 120)),
            ]),
            permission: .read
        )) { arguments in
            let days = max(5, min(365, arguments["days"]?.intValue ?? 60))
            let raw = records(days: days)
            guard let price = currentPrice(from: raw) else {
                return .failure("拿不到当前金价。")
            }
            let quality = await dailyQuality(days: days, fallback: .year)
            let prices = quality.closes.map(\.close)
            guard prices.count >= 20 else {
                return .failure("有效日线只有 \(prices.count) 天，技术指标至少需要 20 天。可以先用 gold_price、gold_history 看现状，或让用户稍后再问。")
            }
            let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: price)
            let drawdown = TechnicalIndicators.maxDrawdown(prices: prices)
            let first = prices.first ?? price
            let changePercent = first > 0 ? (price / first - 1) * 100 : 0

            var payload: [String: JSONValue] = [
                "current_price": num(price),
                "range_change_percent": num(changePercent),
                "sample_count": .number(Double(prices.count)),
                "lookback_days": .number(Double(prices.count)),
                "raw_record_count": .number(Double(raw.count)),
                "sma5": num(snapshot.sma5),
                "sma20": num(snapshot.sma20),
                "sma60": num(snapshot.sma60),
                "ema12": num(snapshot.ema12),
                "ema26": num(snapshot.ema26),
                "rsi14": num(snapshot.rsi14),
                "rsi_state": .string(snapshot.rsiState.rawValue),
                "macd": .object([
                    "line": num(snapshot.macdLine, digits: 3),
                    "signal": num(snapshot.macdSignal, digits: 3),
                    "histogram": num(snapshot.macdHistogram, digits: 3),
                    "state": .string(snapshot.macdState.rawValue),
                ]),
                "bollinger": .object([
                    "upper": num(snapshot.bollingerUpper),
                    "middle": num(snapshot.bollingerMiddle),
                    "lower": num(snapshot.bollingerLower),
                    "position": num(snapshot.bollingerPosition(price: price), digits: 3),
                ]),
                "annualized_volatility_percent": num((snapshot.volatility ?? 0) * 100),
                "roc10_percent": num((snapshot.roc10 ?? 0) * 100),
                "support": num(snapshot.supportLevel),
                "resistance": num(snapshot.resistanceLevel),
                "max_drawdown_percent": num(drawdown * 100),
                "reading": .array(readings(snapshot: snapshot, price: price).map { .string($0) }),
                "disclaimer": .string(disclaimer),
            ]

            payload["generated_at"] = .string(Date().formatted(.iso8601))
            return .text(JSONValue.object(payload).prettyJSONString())
        }
    }

    /// 规则化解读：给模型一个现成的抓手，避免它对着数字瞎猜。
    private static func readings(snapshot: TechnicalSnapshot, price: Double) -> [String] {
        var lines: [String] = []

        if let sma20 = snapshot.sma20 {
            let gap = (price / sma20 - 1) * 100
            let position = gap >= 0 ? "上方" : "下方"
            let deviation = abs(gap) > 3 ? "偏离偏大。" : "偏离不大。"
            lines.append(String(format: "现价 %.2f，位于 20 日均线 %.2f 的%@ %.2f%%，%@", price, sma20, position, abs(gap), deviation))
        }
        if let sma5 = snapshot.sma5, let sma20 = snapshot.sma20 {
            lines.append(sma5 > sma20 ? "短期均线在长期均线上方，短中期偏多。" : "短期均线在长期均线下方，短中期偏空。")
        }
        if let rsi = snapshot.rsi14 {
            lines.append(String(format: "RSI(14) = %.1f，处于%@区间。", rsi, snapshot.rsiState.rawValue))
        }
        if let histogram = snapshot.macdHistogram {
            lines.append(String(format: "MACD 柱状值 %.3f，%@。", histogram, snapshot.macdState.rawValue))
        }
        if let upper = snapshot.bollingerUpper, let lower = snapshot.bollingerLower, upper > lower {
            let position = (price - lower) / (upper - lower)
            if position > 0.9 {
                lines.append("价格贴近布林上轨，短线有回落压力。")
            } else if position < 0.1 {
                lines.append("价格贴近布林下轨，短线有反弹需求。")
            } else {
                lines.append(String(format: "价格在布林带内偏 %@。", position > 0.5 ? "上" : "下"))
            }
        }
        if let support = snapshot.supportLevel, let resistance = snapshot.resistanceLevel {
            lines.append(String(format: "最近支撑 %.2f，最近阻力 %.2f。", support, resistance))
        }
        if let volatility = snapshot.volatility {
            lines.append(String(format: "年化波动率约 %.1f%%，", volatility * 100) + (volatility > 0.25 ? "波动偏大，仓位要控制。" : "波动正常。"))
        }
        return lines
    }

    // MARK: - 周预测

    private static func registerForecast() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "gold_forecast",
            summary: "用本地统计模型（趋势 0.35 / 动量 0.25 / 均值回归 0.15 / 区块自助 0.25）给出未来 7 天的方向判断、期望价和 p10-p90 区间。回答「这周怎么走」「要不要等回调」时调用。",
            parameters: ToolSchema.object(properties: []),
            permission: .read
        )) { _ in
            let raw = records(days: 365)
            guard let price = currentPrice(from: raw) else {
                return .failure("拿不到当前金价，无法生成预测。")
            }

            // 模型要 120 天日线，本地记录通常只有几十天；不够就去拉一年历史。
            let quality = await dailyQuality(
                days: 365,
                fallback: .year,
                minimum: GoldWeeklyForecastPolicy.minimumDailyCloses
            )
            guard quality.closes.count >= GoldWeeklyForecastPolicy.minimumDailyCloses else {
                return .failure("有效日线只有 \(quality.closes.count) 天，模型要求至少 \(GoldWeeklyForecastPolicy.minimumDailyCloses) 天，远程历史也没拉到。请如实告诉用户样本不足、这次不给方向，改用 gold_technical 给现状判断。")
            }

            let now = Date()
            let input = GoldWeeklyForecastEngineInput(
                closes: quality.closes,
                startPrice: price,
                generatedAt: now,
                targetDate: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now,
                seed: UInt64(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
            )
            guard let draft = GoldWeeklyForecastEngine.makeDraft(input) else {
                return .failure("模型没有产出有效结果（数据波动过大或样本异常），请告诉用户这次预测不可用。")
            }

            let payload: [String: JSONValue] = [
                "direction": .string(draft.direction.rawValue),
                "direction_label": .string(forecastLabel(draft.direction)),
                "current_price": num(price),
                "expected_price": num(draft.expectedPrice),
                "expected_return_percent": num(draft.expectedReturn * 100),
                "p10": num(draft.p10),
                "p50": num(draft.p50),
                "p90": num(draft.p90),
                "components": .object([
                    "trend": num(draft.components.trend, digits: 3),
                    "momentum": num(draft.components.momentum, digits: 3),
                    "mean_reversion": num(draft.components.meanReversion, digits: 3),
                    "bootstrap": num(draft.components.bootstrap, digits: 3),
                    "composite": num(draft.components.composite, digits: 3),
                ]),
                "history_days": .number(Double(quality.closes.count)),
                "data_stale": .bool(quality.isStale),
                "target_date": .string((Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now).formatted(.iso8601)),
                "note": .string("方向来自组合分数，不是从 p50 反推。区间越宽说明模型越不确定。"),
                "disclaimer": .string(disclaimer),
            ]
            return .text(JSONValue.object(payload).prettyJSONString())
        }
    }

    private static func forecastLabel(_ direction: GoldWeeklyForecastDirection) -> String {
        switch direction {
        case .up: return "看涨"
        case .down: return "看跌"
        case .flat: return "震荡"
        }
    }

    // MARK: - 策略报告

    private static func registerStrategy() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "gold_strategy",
            summary: "跑完整策略引擎：市场状态（趋势/震荡）、蒙特卡洛 7 日分布、均值回归 z 值、网格计划、风险等级与建议仓位、综合方向与置信度。适合回答「现在适合建仓吗」「仓位多少合适」。",
            parameters: ToolSchema.object(properties: []),
            permission: .read
        )) { _ in
            let raw = records(days: 365)
            guard let price = currentPrice(from: raw) else {
                return .failure("拿不到当前金价，策略引擎无法运行。")
            }
            let quality = await dailyQuality(days: 365, fallback: .year)
            guard quality.closes.count >= 20 else {
                return .failure("有效日线只有 \(quality.closes.count) 天，策略引擎至少要 20 天。")
            }
            let list = dailyRecords(quality.closes)
            let prices = quality.closes.map(\.close)
            let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: price)
            let signal = TradingSignalEngine.generateSignal(prices: prices, currentPrice: price, snapshot: snapshot, lang: AppSettings.shared.language)
            guard let report = GoldAdvancedStrategy.analyze(
                records: list,
                snapshot: snapshot,
                signal: signal,
                lang: AppSettings.shared.language
            ) else {
                return .failure("策略引擎没有产出结果，可能是数据窗口内波动异常。")
            }

            var payload: [String: JSONValue] = [
                "regime": .string(report.regime.regime.displayName(lang: AppSettings.shared.language)),
                "trend_score": num(report.regime.trendScore, digits: 3),
                "ranging_score": num(report.regime.rangingScore, digits: 3),
                "volatility_regime": .string(report.regime.volatilityRegime.displayName(lang: AppSettings.shared.language)),
                "hurst_exponent": num(report.regime.hurstExponent, digits: 3),
                "adx": num(report.regime.adx),
                "technical_opportunity": num(report.technicalOpportunity, digits: 3),
                "composite_direction": .string(signalLabel(report.compositeDirection)),
                "confidence": num(report.confidence * 100),
                "summary": .string(report.summary),
                "beginner_action": .string(report.beginnerAction),
                "beginner_reason": .string(report.beginnerReason),
                "risk": .object([
                    "level": .string(report.risk.riskLevel),
                    "suggested_exposure_percent": num(report.risk.suggestedExposure * 100),
                    "max_single_move_risk_percent": num(report.risk.maxSingleMoveRisk * 100),
                    "warning": report.risk.warning.map { JSONValue.string($0) } ?? .null,
                ]),
                "signal": .object([
                    "direction": .string(signalLabel(signal.direction)),
                    "strength": .string(signal.strength.rawValue),
                    "score": num(signal.score, digits: 3),
                    "entry": num(signal.suggestedEntry),
                    "stop_loss": num(signal.suggestedStopLoss),
                    "take_profit": num(signal.suggestedTakeProfit),
                    "reasons": .array(signal.reasons.map { .string($0) }),
                ]),
                "disclaimer": .string(disclaimer),
            ]

            if let forecast = report.forecast {
                payload["monte_carlo"] = .object([
                    "expected_price": num(forecast.expectedPrice),
                    "expected_return_percent": num(forecast.expectedReturn * 100),
                    "probability_above_current_percent": num(forecast.probabilityAboveCurrent * 100),
                    "p10": num(forecast.p10),
                    "p50": num(forecast.p50),
                    "p90": num(forecast.p90),
                    "simulations": .number(Double(forecast.simulationCount)),
                ])
            }
            if let meanReversion = report.meanReversion {
                payload["mean_reversion"] = .object([
                    "z_score": num(meanReversion.zScore, digits: 3),
                    "half_life_days": num(meanReversion.halfLife),
                ])
            }
            if let grid = report.grid {
                payload["grid"] = .object([
                    "suitable": .bool(grid.isSuitable),
                    "lower": num(grid.lowerPrice),
                    "upper": num(grid.upperPrice),
                    "count": .number(Double(grid.gridCount)),
                    "spacing": num(grid.spacing),
                ])
            }

            return .text(JSONValue.object(payload).prettyJSONString())
        }
    }

    // MARK: - 明确的买卖计划

    /// 与金价页最上面那张「现在怎么办」卡同一套算法：
    /// 动作、仓位、买入区/止损/目标、理由、风险、失效条件，全部给出具体数字。
    private static func registerPlan() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "gold_plan",
            summary: "给出明确的黄金买卖计划：动作（买入/分批买入/持有观望/减仓/卖出）、建议仓位、买入区间、止损价、目标价、3 条理由、风险与失效条件。用户问「现在该不该买」「买多少」「跌到哪该走」时优先调用它，比 gold_strategy 更直接。",
            parameters: ToolSchema.object(properties: []),
            permission: .read
        )) { _ in
            let quality = await dailyQuality(days: 365, fallback: .year)
            guard quality.closes.count >= 20 else {
                return .failure("有效日线只有 \(quality.closes.count) 天，至少需要 20 天才能给出计划。")
            }
            let prices = quality.closes.map(\.close)
            guard let price = currentPrice(from: records(days: 7)) ?? prices.last, price > 0 else {
                return .failure("拿不到当前金价，无法生成计划。")
            }
            let list = dailyRecords(quality.closes)
            let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: price)
            let signal = TradingSignalEngine.generateSignal(prices: prices, currentPrice: price, snapshot: snapshot, lang: AppSettings.shared.language)
            let report = GoldAdvancedStrategy.analyze(records: list, snapshot: snapshot, signal: signal, lang: AppSettings.shared.language)

            guard let plan = GoldActionPlanner.plan(
                currentPrice: price,
                snapshot: snapshot,
                signal: signal,
                report: report,
                weeklyForecast: nil,
                language: AppSettings.shared.language
            ) else {
                return .failure("计划生成失败，可能是波动率数据异常。")
            }

            let payload: [String: JSONValue] = [
                "action": .string(actionLabel(plan.verb)),
                "action_title": .string(plan.verb.title(AppSettings.shared.language)),
                "confidence_percent": num(plan.confidence * 100),
                "suggested_exposure_percent": num(plan.exposurePercent * 100),
                "current_price": num(price),
                "entry_low": num(plan.entryLow),
                "entry_high": num(plan.entryHigh),
                "stop_loss": num(plan.stopLoss),
                "target": num(plan.target),
                "horizon_days": .number(Double(plan.horizonDays)),
                "reasons": .array(plan.reasons.map { .string($0) }),
                "risks": .array(plan.risks.map { .string($0) }),
                "invalidation": .string(plan.invalidation),
                "probability_up_percent": plan.probabilityUp.map { num($0 * 100) } ?? .null,
                "disclaimer": .string(disclaimer),
            ]
            return .text(JSONValue.object(payload).prettyJSONString())
        }
    }

    private static func actionLabel(_ verb: GoldActionVerb) -> String {
        switch verb {
        case .buy: return "buy"
        case .accumulate: return "accumulate"
        case .hold: return "hold"
        case .reduce: return "reduce"
        case .sell: return "sell"
        }
    }

    // MARK: - 持仓诊断

    private static func registerPosition() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "gold_position",
            summary: "读取用户自己的黄金持仓（交易流水汇总的克数与均价），结合当前价格和策略报告给出持仓诊断：盈亏、回本缺口、该加仓/减仓/继续持有。回答「我的持仓怎么办」时调用。",
            parameters: ToolSchema.object(properties: []),
            permission: .read
        )) { _ in
            let trades = GoldTradeStore.shared.records
            let summary = GoldTradeStore.holdingSummary(records: trades)
            guard summary.grams > 0, summary.averageCost > 0 else {
                return .text("用户还没有记录任何黄金交易。如果他想知道「现在该不该买」，用 gold_strategy 给建仓建议即可；如果他愿意，可以提示他在金价页的持仓里录入交易。")
            }

            let raw = records(days: 365)
            guard let price = currentPrice(from: raw) else {
                return .failure("拿不到当前金价，无法计算持仓盈亏。")
            }

            var report: GoldAdvancedStrategyReport?
            var signal: TradingSignal?
            let quality = await dailyQuality(days: 365, fallback: .year)
            if quality.closes.count >= 20 {
                let list = dailyRecords(quality.closes)
                let prices = quality.closes.map(\.close)
                let snapshot = TechnicalIndicators.buildSnapshot(prices: prices, currentPrice: price)
                let generated = TradingSignalEngine.generateSignal(prices: prices, currentPrice: price, snapshot: snapshot, lang: AppSettings.shared.language)
                signal = generated
                report = GoldAdvancedStrategy.analyze(records: list, snapshot: snapshot, signal: generated, lang: AppSettings.shared.language)
            }

            guard let advice = GoldPositionAdvisor.analyze(
                currentPrice: price,
                grams: summary.grams,
                averageCost: summary.averageCost,
                report: report,
                signal: signal,
                lang: AppSettings.shared.language
            ) else {
                return .failure("持仓数据不完整，算不出建议。")
            }

            let payload: [String: JSONValue] = [
                "grams": num(advice.grams),
                "average_cost": num(advice.averageCost),
                "current_price": num(advice.currentPrice),
                "cost_basis": num(advice.costBasis),
                "market_value": num(advice.marketValue),
                "profit_loss": num(advice.profitLoss),
                "profit_percent": num(advice.profitPercent * 100),
                "break_even_gap": num(advice.breakEvenGap),
                "action": .string(advice.actionTitle),
                "reason": .string(advice.reason),
                "action_items": .array(advice.actionItems.map { .string($0) }),
                "reference_line": .string(advice.referenceLine),
                "trade_count": .number(Double(trades.count)),
                "disclaimer": .string(disclaimer),
            ]
            return .text(JSONValue.object(payload).prettyJSONString())
        }
    }
}
