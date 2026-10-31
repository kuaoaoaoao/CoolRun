import SwiftUI
import AppKit

// MARK: - 价格摘要卡片

struct GoldPriceSummaryCard: View {
    let statistics: PriceStatistics
    let quote: GoldPriceQuote?
    let health: DataHealthStatus
    let lastUpdateDate: Date?
    let updateInterval: TimeInterval?
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    private var displayedChange: (amount: Double, percent: Double) {
        if let amount = quote?.changeAmount, let percent = quote?.changeRatePercent {
            return (amount, percent)
        }
        return (statistics.change, statistics.changePercent)
    }

    private var healthAppearance: (color: Color, icon: String) {
        switch health {
        case .healthy:
            return (AppTheme.healthy, "checkmark.circle")
        case .stale:
            return (AppTheme.gold, "clock.badge.exclamationmark")
        case .priceJump:
            return (Color.orange, "arrow.up.arrow.down.circle")
        case .invalidPrice:
            return (AppTheme.critical, "xmark.octagon")
        }
    }

    private var healthTitle: String {
        guard case .stale(let age) = health else { return health.description }
        guard age.isFinite, age <= Double(Int.max) else {
            return LocalizedString.l(
                language,
                en: "Data delayed",
                zh: "数据延迟",
                ja: "データ遅延",
                ko: "데이터 지연"
            )
        }

        let totalSeconds = max(0, Int(age))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if days > 0 {
            return LocalizedString.l(
                language,
                en: "Delayed \(days)d \(hours)h",
                zh: "延迟 \(days)天\(hours)小时",
                ja: "\(days)日\(hours)時間遅延",
                ko: "\(days)일 \(hours)시간 지연"
            )
        }
        if hours > 0 {
            return LocalizedString.l(
                language,
                en: "Delayed \(hours)h \(minutes)m",
                zh: "延迟 \(hours)小时\(minutes)分",
                ja: "\(hours)時間\(minutes)分遅延",
                ko: "\(hours)시간 \(minutes)분 지연"
            )
        }
        if minutes > 0 {
            return LocalizedString.l(
                language,
                en: "Delayed \(minutes)m",
                zh: "延迟 \(minutes)分钟",
                ja: "\(minutes)分遅延",
                ko: "\(minutes)분 지연"
            )
        }
        return LocalizedString.l(
            language,
            en: "Delayed \(totalSeconds)s",
            zh: "延迟 \(totalSeconds)秒",
            ja: "\(totalSeconds)秒遅延",
            ko: "\(totalSeconds)초 지연"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(LocalizedString.gold("source_name", lang: language))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))

                if quote?.isMarketClosed == true {
                    statusPill(
                        LocalizedString.l(language, en: "Closed", zh: "休市", ja: "休場", ko: "휴장"),
                        icon: nil,
                        color: AppTheme.textSecondary(colorScheme)
                    )
                }

                Spacer(minLength: 4)

                if !health.isHealthy {
                    statusPill(
                        healthTitle,
                        icon: healthAppearance.icon,
                        color: healthAppearance.color
                    )
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Text("¥\(statistics.currentPrice.goldPriceNumber)/g")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 2)

                ChangeBadge(
                    change: displayedChange.amount,
                    percent: displayedChange.percent
                )
            }

            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 7) {
                    if let yesterday = quote?.yesterdayPrice {
                        Text(LocalizedString.l(
                            language,
                            en: "Prev close ¥\(yesterday.goldPriceNumber)",
                            zh: "昨收 ¥\(yesterday.goldPriceNumber)",
                            ja: "前日終値 ¥\(yesterday.goldPriceNumber)",
                            ko: "전일 종가 ¥\(yesterday.goldPriceNumber)"
                        ))
                        .monospacedDigit()
                    }

                    if let lastUpdateDate {
                        Label(
                            LocalizedString.goldAge(
                                max(0, context.date.timeIntervalSince(lastUpdateDate)),
                                lang: language
                            ),
                            systemImage: "clock"
                        )
                    }

                    Spacer(minLength: 2)

                    if let updateInterval {
                        Text(String(
                            format: LocalizedString.gold("refresh_interval_format", lang: language),
                            updateInterval.singleDigitNumber
                        ))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.72))
                    }
                }
                .font(.system(size: 9.25, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            Divider()
                .overlay(AppTheme.separator(colorScheme))

            HStack(spacing: 10) {
                GoldMetric(
                    label: LocalizedString.gold("high", lang: language),
                    value: statistics.periodHigh.goldPriceNumber
                )
                metricDivider
                GoldMetric(
                    label: LocalizedString.gold("low", lang: language),
                    value: statistics.periodLow.goldPriceNumber
                )
                metricDivider
                GoldMetric(
                    label: LocalizedString.gold("avg", lang: language),
                    value: statistics.periodAverage.goldPriceNumber
                )
            }
        }
        .padding(GoldLayout.cardPadding)
        .goldPanelSurface()
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppTheme.separator(colorScheme))
            .frame(width: 0.5, height: 24)
    }

    private func statusPill(_ title: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: 8.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: Capsule())
    }
}

// MARK: - 决策摘要卡片

struct GoldDecisionSummaryCard: View {
    let report: GoldAdvancedStrategyReport
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        switch report.beginnerTone {
        case .positive: AppTheme.healthy
        case .cautious: AppTheme.gold
        case .defensive: AppTheme.critical
        }
    }

    private var iconName: String {
        switch report.beginnerTone {
        case .positive: "arrow.up.right.circle.fill"
        case .cautious: "pause.circle.fill"
        case .defensive: "shield.lefthalf.filled"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label(
                        LocalizedString.l(
                            settings.language,
                            en: "Current view",
                            zh: "当前建议",
                            ja: "現在の見方",
                            ko: "현재 제안"
                        ),
                        systemImage: iconName
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)

                    Spacer()

                    HStack(spacing: 4) {
                        Text("\(Int(report.confidence * 100))%")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                        Text(LocalizedString.gold("confidence", lang: settings.language))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.09), in: Capsule())
                }

                Text(report.beginnerAction)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))

                Text(report.beginnerReason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    decisionChip(report.regime.regime.displayName, icon: "waveform.path")
                    decisionChip(report.risk.riskLevel, icon: "shield")
                    decisionChip(report.risk.suggestedExposure.percentNumber, icon: "chart.pie")
                }

                Text(LocalizedString.l(
                    settings.language,
                    en: "For decision support only, not investment advice.",
                    zh: "仅作辅助判断，不构成投资建议。",
                    ja: "判断補助のみで、投資助言ではありません。",
                    ko: "판단 보조용이며 투자 조언이 아닙니다."
                ))
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.72))
        }
        .padding(GoldLayout.cardPadding)
        .padding(.leading, 6)
        .background {
            ZStack {
                AppTheme.elevatedSurface(colorScheme)
                LinearGradient(
                    colors: [tint.opacity(colorScheme == .dark ? 0.10 : 0.07), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: GoldLayout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldLayout.cardRadius, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 0.5)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, GoldLayout.cardPadding)
                .padding(.leading, 8)
        }
    }

    private func decisionChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(AppTheme.progressBg(colorScheme), in: Capsule())
    }
}

// MARK: - 价格走势图

struct PriceLineChart: View {
    let records: [GoldPriceRecord]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            guard records.count >= 2 else { return }

            let prices = records.map(\.price)
            guard let minPrice = prices.min(), let maxPrice = prices.max() else { return }
            let range = max(maxPrice - minPrice, 0.01)

            // 水平网格参考线
            let gridColor = Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
            for fraction in [0.25, 0.5, 0.75] {
                var gridPath = Path()
                let y = size.height * CGFloat(fraction)
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(gridPath, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }

            var path = Path()
            var lastPoint = CGPoint.zero
            for (index, price) in prices.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(prices.count - 1, 1))
                let y = size.height - (CGFloat((price - minPrice) / range) * size.height)
                lastPoint = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: lastPoint)
                } else {
                    path.addLine(to: lastPoint)
                }
            }

            // 中国市场惯例：涨红跌绿，与 AppTheme.marketUp/marketDown 保持一致。
            let lineColor = NSColor(
                (prices.last ?? 0) >= (prices.first ?? 0) ? AppTheme.marketUp : AppTheme.marketDown
            )
            let tint = Color(nsColor: lineColor)

            // 渐变填充：线色向下淡出
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [
                        tint.opacity(colorScheme == .dark ? 0.28 : 0.20),
                        tint.opacity(0.02)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

            // 最新价端点
            let dotRadius: CGFloat = 2.4
            context.fill(
                Path(ellipseIn: CGRect(
                    x: lastPoint.x - dotRadius,
                    y: lastPoint.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )),
                with: .color(tint)
            )
        }
    }
}

// MARK: - 持仓卡片

struct GoldPositionCard: View {
    @Binding var gramsText: String
    @Binding var averageCostText: String
    let advice: GoldHoldingAdvice?
    let hasInput: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        guard let advice else {
            return Color(red: 0.88, green: 0.57, blue: 0.16)
        }

        switch advice.tone {
        case .positive:
            return AppTheme.healthy
        case .cautious:
            return Color(red: 0.88, green: 0.57, blue: 0.16)
        case .defensive:
            return AppTheme.critical
        }
    }

    private var statusText: String {
        guard let advice else {
            return hasInput ? LocalizedString.gold("check_input") : LocalizedString.gold("not_filled")
        }

        if advice.profitLoss > 0 { return LocalizedString.gold("floating_profit") }
        if advice.profitLoss < 0 { return LocalizedString.gold("floating_loss") }
        return LocalizedString.gold("break_even")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(LocalizedString.gold("my_gold"), systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Spacer(minLength: 6)
                Text(statusText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 6) {
                PositionInputField(
                    title: LocalizedString.gold("holding_grams"),
                    placeholder: LocalizedString.gold("example_grams"),
                    suffix: "g",
                    text: $gramsText
                )
                PositionInputField(
                    title: LocalizedString.gold("average_cost"),
                    placeholder: LocalizedString.gold("example_price"),
                    suffix: "¥/g",
                    text: $averageCostText
                )
            }

            if let advice {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        PositionMetric(title: LocalizedString.gold("cost"), value: "¥\(advice.costBasis.moneyNumber)")
                        PositionMetric(title: LocalizedString.gold("market_value"), value: "¥\(advice.marketValue.moneyNumber)")
                        PositionMetric(
                            title: advice.profitLoss >= 0 ? LocalizedString.gold("profit") : LocalizedString.gold("loss"),
                            value: "\(advice.profitLoss.signedMoneyNumber)"
                        )
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(advice.actionTitle)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            Text(advice.reason)
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(advice.profitPercent.signedCompactPercentText)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(advice.referenceLine)
                                .font(.system(size: 8, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(tint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(advice.actionItems, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Text(hasInput ? LocalizedString.gold("position_input_invalid") : LocalizedString.gold("position_input_hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(tint.opacity(colorScheme == .dark ? 0.12 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
    }
}

struct PositionInputField: View {
    let title: String
    let placeholder: String
    let suffix: String
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            HStack(spacing: 3) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text(suffix)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}

struct PositionMetric: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - 交易信号卡片

struct SignalCardView: View {
    let signal: TradingSignal
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        switch signal.direction {
        case .buy: AppTheme.marketUp
        case .sell: AppTheme.marketDown
        case .hold: Color(red: 0.88, green: 0.57, blue: 0.16)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(signal.direction.label, systemImage: signal.direction == .hold ? "pause.circle" : "arrow.up.arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(signal.strength.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14), in: Capsule())
            }

            ForEach(signal.reasons, id: \.self) { reason in
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let entry = signal.suggestedEntry,
               let stopLoss = signal.suggestedStopLoss,
               let takeProfit = signal.suggestedTakeProfit {
                HStack(spacing: 6) {
                    GoldMetric(label: LocalizedString.gold("entry"), value: entry.goldPriceNumber)
                    GoldMetric(label: LocalizedString.gold("stop_loss"), value: stopLoss.goldPriceNumber)
                    GoldMetric(label: LocalizedString.gold("take_profit"), value: takeProfit.goldPriceNumber)
                }
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

// MARK: - 新手引导卡片

struct BeginnerGuidanceCard: View {
    let report: GoldAdvancedStrategyReport
    let learningSummary: GoldPredictionLearningSummary
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        switch report.beginnerTone {
        case .positive: AppTheme.healthy
        case .cautious: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .defensive: AppTheme.critical
        }
    }

    private var iconName: String {
        switch report.beginnerTone {
        case .positive: "checkmark.seal"
        case .cautious: "pause.circle"
        case .defensive: "hand.raised"
        }
    }

    private var evidenceLines: [String] {
        var lines = [
            "\(LocalizedString.gold("market_state")): \(report.regime.regime.displayName), ADX \(report.regime.adx.shortNumber), \(LocalizedString.gold("volatility")) \(report.regime.volatilityRegime.displayName)",
            "\(LocalizedString.gold("technical_score")): \(report.technicalOpportunity.signedShortNumber), \(LocalizedString.gold("suggested_position")) \(report.risk.suggestedExposure.percentNumber)",
            "\(LocalizedString.gold("strategy_version")): \(report.strategyVersion), \(report.calibration.note)"
        ]

        if let forecast = report.forecast {
            lines.append("\(LocalizedString.gold("simulation_steps")): \(forecast.probabilityAboveCurrent.percentNumber), P50 \(forecast.p50.goldPriceNumber)")
        }

        if let context = report.marketContext {
            lines.append("\(LocalizedString.gold("macro_news_analysis")): \(context.tone.title), \(LocalizedString.gold("total_predictions")) \(context.overallScore.signedShortNumber)")
        } else {
            lines.append(LocalizedString.gold("macro_unavailable"))
        }

        if learningSummary.validatedCount > 0 {
            let hitRate = learningSummary.hitRate?.percentNumber ?? "--"
            lines.append("\(LocalizedString.gold("validated")): \(learningSummary.validatedCount), \(LocalizedString.gold("hit")) \(hitRate)")
        } else {
            lines.append(LocalizedString.l(AppSettings.shared.language, en: "Historical samples are still accumulating.", zh: "历史验证：样本仍在积累，暂不作为强依据", ja: "履歴サンプルはまだ蓄積中です。", ko: "과거 검증 샘플을 아직 쌓는 중입니다."))
        }

        return lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label(LocalizedString.gold("beginner_conclusion"), systemImage: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 6)
                Text("\(Int(report.confidence * 100))%\(LocalizedString.gold("confidence"))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            Text(report.beginnerAction)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(report.beginnerReason)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                Label(LocalizedString.gold("evidence"), systemImage: "list.bullet.clipboard")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))

                ForEach(evidenceLines, id: \.self) { line in
                    EvidenceLine(text: line)
                }
            }
            .padding(8)
            .background(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            HStack(spacing: 6) {
                PlainLanguageChip(text: "\(LocalizedString.gold("suggested_position")) \(report.risk.suggestedExposure.percentNumber)", tint: tint)
                PlainLanguageChip(text: report.regime.regime.displayName, tint: tint)
            }

            ReferenceNotice()
        }
        .padding(10)
        .background(tint.opacity(colorScheme == .dark ? 0.13 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
    }
}

struct PlainLanguageChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct EvidenceLine: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.85))

            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ReferenceNotice: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(
            LocalizedString.gold("reference_notice"),
            systemImage: "info.circle"
        )
        .font(.system(size: 9))
        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.88))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 1)
    }
}

// MARK: - 高级策略卡片

struct AdvancedStrategyCard: View {
    let report: GoldAdvancedStrategyReport
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        switch report.compositeDirection {
        case .buy: AppTheme.marketUp
        case .sell: AppTheme.marketDown
        case .hold: Color(red: 0.88, green: 0.57, blue: 0.16)
        }
    }

    private func technicalOpportunityDetail(_ score: Double) -> String {
        switch score {
        case 35...:
            return LocalizedString.l(AppSettings.shared.language, en: "Opportunity is clear enough for small batches, not heavy chasing.", zh: "机会较明显，适合小额分批，不适合重仓追入", ja: "機会は比較的明確。小口分割向きで、重い追随買いには不向きです。", ko: "기회가 비교적 뚜렷해 소액 분할에는 적합하지만 무거운 추격 매수는 피하는 편이 좋습니다.")
        case 15..<35:
            return LocalizedString.l(AppSettings.shared.language, en: "Opportunity is mildly positive; watch for batch-entry conditions.", zh: "机会偏正面，可观察分批条件", ja: "やや前向き。分割エントリー条件を観察できます。", ko: "기회가 약간 긍정적입니다. 분할 진입 조건을 지켜볼 수 있습니다.")
        case ...(-35):
            return LocalizedString.l(AppSettings.shared.language, en: "Risk is high; control the urge to buy first.", zh: "风险偏高，先控制买入冲动", ja: "リスクが高めです。まず買いたい衝動を抑えましょう。", ko: "위험이 높은 편입니다. 먼저 매수 충동을 조절하세요.")
        case -35..<(-15):
            return LocalizedString.l(AppSettings.shared.language, en: "Conditions are weak; wait for a better level.", zh: "条件偏弱，等待更好位置", ja: "条件は弱め。より良い位置を待ちましょう。", ko: "조건이 약합니다. 더 좋은 자리를 기다리세요.")
        default:
            return LocalizedString.l(AppSettings.shared.language, en: "Opportunity and risk are roughly balanced.", zh: "机会和风险接近平衡", ja: "機会とリスクはおおむね均衡しています。", ko: "기회와 위험이 대체로 균형입니다.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdvancedStrategyHeader(
                title: report.regime.regime.displayName,
                strategy: report.regime.regime.strategyLabel,
                tint: tint
            )

            Text(report.summary)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            HStack(spacing: 6) {
                StrategyMetric(
                    title: LocalizedString.gold("trend_strength"),
                    value: report.regime.adx.shortNumber,
                    detail: report.regime.volatilityRegime.displayName,
                    help: LocalizedString.l(AppSettings.shared.language, en: "Higher values mean price is moving more clearly in one direction.", zh: "越高说明价格越像沿着一个方向走。", ja: "値が高いほど、価格が一方向に動きやすいことを示します。", ko: "값이 높을수록 가격이 한 방향으로 움직이는 경향이 강합니다.")
                )
                StrategyMetric(
                    title: LocalizedString.gold("trend_stickiness"),
                    value: report.regime.hurstExponent.threeDigitNumber,
                    detail: "Hurst",
                    help: LocalizedString.l(AppSettings.shared.language, en: "Near 0.5 means direction is unclear. Above 0.5 suggests stronger trend persistence.", zh: "接近 0.5 表示方向不明显，高于 0.5 更容易延续趋势。", ja: "0.5に近いほど方向感が薄く、0.5を上回るほどトレンド継続性が高まります。", ko: "0.5에 가까우면 방향성이 약하고, 0.5보다 높으면 추세 지속성이 강합니다.")
                )
                StrategyMetric(
                    title: LocalizedString.gold("suggested_position"),
                    value: report.risk.suggestedExposure.percentNumber,
                    detail: report.risk.riskLevel,
                    help: LocalizedString.l(AppSettings.shared.language, en: "This is not a buy instruction. If participating, keep exposure around or below this level.", zh: "不是让你必须买，而是如果要参与，建议资金占比别超过这个量级。", ja: "購入指示ではありません。参加する場合、この水準以下の資金比率に抑える目安です。", ko: "매수 지시가 아닙니다. 참여한다면 이 수준 이하의 비중을 권장합니다.")
                )
            }

            StrategyRow(
                title: LocalizedString.gold("technical_score"),
                value: report.technicalOpportunity.signedShortNumber,
                detail: technicalOpportunityDetail(report.technicalOpportunity),
                help: LocalizedString.l(AppSettings.shared.language, en: "Combines moving average deviation, RSI, MACD and Bollinger position. Positive scores favor small batches; negative scores call for caution.", zh: "借鉴多因子策略里的技术评分思路，综合均线偏离、RSI、MACD 和布林带位置。正分偏适合小额分批，负分偏谨慎。", ja: "移動平均からの乖離、RSI、MACD、ボリンジャーバンド位置を組み合わせたスコアです。プラスは小口分割、マイナスは慎重寄りです。", ko: "이동평균 괴리, RSI, MACD, 볼린저 위치를 종합한 점수입니다. 양수는 소액 분할, 음수는 신중함을 뜻합니다.")
            )

            if let meanReversion = report.meanReversion {
                StrategyRow(
                    title: LocalizedString.gold("mean_reversion_label"),
                    value: meanReversion.zScore.signedShortNumber,
                    detail: meanReversion.summary,
                    help: LocalizedString.l(AppSettings.shared.language, en: "Think of it as how far price is from its recent average. Large gaps may pull back toward the average.", zh: "可以理解成价格离最近平均价有多远。离得太远时，可能会往平均价靠。", ja: "価格が最近の平均からどれだけ離れているかを見る指標です。離れすぎると平均に戻る可能性があります。", ko: "가격이 최근 평균에서 얼마나 떨어졌는지 보는 지표입니다. 너무 멀어지면 평균으로 돌아올 수 있습니다.")
                )
            }

            if let forecast = report.forecast {
                StrategyRow(
                    title: LocalizedString.gold("simulation_steps"),
                    value: forecast.probabilityAboveCurrent.percentNumber,
                    detail: LocalizedString.l(AppSettings.shared.language, en: "Median \(forecast.p50.goldPriceNumber), range \(forecast.p10.goldPriceNumber)-\(forecast.p90.goldPriceNumber)", zh: "中位 \(forecast.p50.goldPriceNumber)，区间 \(forecast.p10.goldPriceNumber)-\(forecast.p90.goldPriceNumber)", ja: "中央値 \(forecast.p50.goldPriceNumber)、範囲 \(forecast.p10.goldPriceNumber)-\(forecast.p90.goldPriceNumber)", ko: "중앙값 \(forecast.p50.goldPriceNumber), 범위 \(forecast.p10.goldPriceNumber)-\(forecast.p90.goldPriceNumber)"),
                    help: LocalizedString.l(AppSettings.shared.language, en: "Runs many random paths from historical volatility to estimate a short-term range. It is not a promise.", zh: "用历史波动随机跑很多次，看看短期大概落在哪个价格区间。不是预测承诺。", ja: "過去の変動率で多数のランダム経路を試し、短期レンジを見積もります。予測の保証ではありません。", ko: "과거 변동성으로 여러 경로를 시뮬레이션해 단기 범위를 추정합니다. 예측 보장이 아닙니다.")
                )
            }

            if let grid = report.grid {
                StrategyRow(
                    title: grid.isSuitable ? LocalizedString.gold("grid_fit") : LocalizedString.gold("grid_caution"),
                    value: String(format: LocalizedString.l(AppSettings.shared.language, en: "%d grids", zh: "%d格", ja: "%dグリッド", ko: "%d칸"), grid.gridCount),
                    detail: LocalizedString.l(AppSettings.shared.language, en: "\(grid.lowerPrice.goldPriceNumber)-\(grid.upperPrice.goldPriceNumber), step \(grid.spacing.goldPriceNumber)", zh: "\(grid.lowerPrice.goldPriceNumber)-\(grid.upperPrice.goldPriceNumber)，间距 \(grid.spacing.goldPriceNumber)", ja: "\(grid.lowerPrice.goldPriceNumber)-\(grid.upperPrice.goldPriceNumber)、間隔 \(grid.spacing.goldPriceNumber)", ko: "\(grid.lowerPrice.goldPriceNumber)-\(grid.upperPrice.goldPriceNumber), 간격 \(grid.spacing.goldPriceNumber)"),
                    help: LocalizedString.l(AppSettings.shared.language, en: "Grid works best in sideways movement and can fail during one-way rallies or selloffs.", zh: "网格适合价格来回震荡时分批买卖；单边大涨大跌时容易失效。", ja: "グリッドは横ばい相場での分割売買に向き、一方向の大きな上昇・下落では機能しにくくなります。", ko: "그리드는 횡보장에서 분할 매매에 적합하며 일방향 급등락에서는 잘 맞지 않을 수 있습니다.")
                )
            }

            if let warning = report.risk.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

struct AdvancedStrategyHeader: View {
    let title: String
    let strategy: String
    let tint: Color

    var body: some View {
        HStack {
            Label(title, systemImage: "waveform.path.ecg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            Text(strategy)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(tint.opacity(0.14))
            }
        }
    }
}

// MARK: - 市场上下文卡片

struct MarketContextCard: View {
    let context: GoldMarketContext?
    let isLoading: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        switch context?.tone ?? .neutral {
        case .bullish: AppTheme.marketUp
        case .neutral: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .bearish: AppTheme.marketDown
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(context?.tone.title ?? LocalizedString.gold("macro_news_analysis"), systemImage: "newspaper")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 6)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(context?.overallScore.signedShortNumber ?? "--")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
            }

            if let context {
                if context.isFromCache || context.isPartial {
                    Label(contextStatusText(context), systemImage: context.isFromCache ? "clock.badge.checkmark" : "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(context.isFromCache ? tint : AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    StrategyMetric(
                        title: LocalizedString.gold("macro"),
                        value: context.macroScore.signedShortNumber,
                        detail: macroDetail(context.macro),
                        help: LocalizedString.l(AppSettings.shared.language, en: "Uses U.S. 10-year Treasury yield changes. Falling yields usually support gold; rising yields usually pressure it.", zh: "当前先使用美国 10 年期国债收益率变化。收益率下行通常利好黄金，上行通常压制黄金。", ja: "米10年債利回りの変化を使用します。利回り低下は通常金に追い風、上昇は逆風です。", ko: "미국 10년물 국채 금리 변화를 사용합니다. 금리 하락은 보통 금에 우호적이고 상승은 압박 요인입니다.")
                    )
                    StrategyMetric(
                        title: LocalizedString.gold("news"),
                        value: context.newsScore.signedShortNumber,
                        detail: String(format: LocalizedString.gold("items_count_format"), context.newsItems.count),
                        help: LocalizedString.l(AppSettings.shared.language, en: "Reads RSS headlines about gold, USD, the Fed and yields, then scores sentiment with keywords.", zh: "读取黄金、美元、美联储、收益率相关 RSS 标题，用关键词做轻量情绪评分。", ja: "金、ドル、FRB、利回りに関するRSS見出しを読み、キーワードで軽量なセンチメント評価を行います。", ko: "금, 달러, 연준, 금리 관련 RSS 제목을 읽고 키워드로 간단한 심리를 점수화합니다.")
                    )
                }

                ForEach(Array(context.reasons.prefix(3)), id: \.self) { reason in
                    Label(reason, systemImage: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !context.newsItems.isEmpty {
                    Divider()
                        .opacity(0.45)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(context.newsItems.prefix(6))) { item in
                            newsRow(item)
                        }
                    }
                }
            } else {
                Text(isLoading ? LocalizedString.gold("macro_loading") : LocalizedString.gold("macro_unavailable"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private func macroDetail(_ macro: GoldMacroSnapshot?) -> String {
        guard let macro, let yield = macro.tenYearYield else { return LocalizedString.gold("treasury_10y") }
        if let change = macro.tenYearYieldChangeBps {
            return "\(yield.shortNumber)% \(change.signedShortNumber)bp"
        }
        return "\(yield.shortNumber)%"
    }

    @ViewBuilder
    private func newsRow(_ item: GoldNewsItem) -> some View {
        let content = HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(newsTint(item))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    if let source = item.source, !source.isEmpty {
                        Text(source)
                    }
                    if let publishedAt = item.publishedAt {
                        Text(publishedAt, style: .relative)
                    }
                    Text(newsImpactText(item))
                        .foregroundStyle(newsTint(item))
                }
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }

            Spacer(minLength: 0)

            if item.link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }

        if let link = item.link {
            Link(destination: link) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func newsTint(_ item: GoldNewsItem) -> Color {
        if item.sentimentScore > 0 { return AppTheme.marketUp }
        if item.sentimentScore < 0 { return AppTheme.marketDown }
        return AppTheme.textSecondary(colorScheme)
    }

    private func newsImpactText(_ item: GoldNewsItem) -> String {
        if item.sentimentScore > 0 {
            return LocalizedString.l(AppSettings.shared.language, en: "Bullish", zh: "利多", ja: "強気", ko: "호재")
        }
        if item.sentimentScore < 0 {
            return LocalizedString.l(AppSettings.shared.language, en: "Bearish", zh: "利空", ja: "弱気", ko: "악재")
        }
        return LocalizedString.l(AppSettings.shared.language, en: "Neutral", zh: "中性", ja: "中立", ko: "중립")
    }

    private func contextStatusText(_ context: GoldMarketContext) -> String {
        if let missing = context.missingDataDescription {
            return String(format: context.isFromCache ? LocalizedString.gold("cached_data_format") : LocalizedString.gold("partial_data_format"), missing)
        }
        return context.isFromCache ? LocalizedString.gold("cached_15min") : LocalizedString.gold("macro_partial")
    }
}

// MARK: - 事件影响

/// 事件影响卡片的纯文案映射：只做展示文本转换，不做任何推断或加权。
struct GoldEventImpactPresentation: Equatable {
    let directionText: String
    let confidenceText: String
    let dataStateText: String
    let riskText: String

    nonisolated init(impact: GoldEventImpact, language: AppLanguage) {
        directionText = Self.directionText(for: impact.direction, dataState: impact.dataState, language: language)
        confidenceText = LocalizedString.l(
            language,
            en: "Evidence strength: \(Self.confidenceWord(impact.confidence, language: .english))",
            zh: "证据强度：\(Self.confidenceWord(impact.confidence, language: .chinese))",
            ja: "証拠強度：\(Self.confidenceWord(impact.confidence, language: .japanese))",
            ko: "증거 강도: \(Self.confidenceWord(impact.confidence, language: .korean))"
        )
        dataStateText = Self.dataStateText(for: impact.dataState, language: language)
        riskText = LocalizedString.l(
            language,
            en: "Volatility risk: \(Self.riskWord(impact.volatilityRisk, language: .english))",
            zh: "波动风险：\(Self.riskWord(impact.volatilityRisk, language: .chinese))",
            ja: "ボラティリティリスク：\(Self.riskWord(impact.volatilityRisk, language: .japanese))",
            ko: "변동성 리스크: \(Self.riskWord(impact.volatilityRisk, language: .korean))"
        )
    }

    nonisolated static func evidenceLabel(for state: GoldEvidenceState, language: AppLanguage) -> String {
        switch state {
        case .observed:
            return LocalizedString.l(
                language,
                en: "Confirmed",
                zh: "已确认",
                ja: "確認済み",
                ko: "확인됨"
            )
        case .inferred:
            return LocalizedString.l(
                language,
                en: "Inferred",
                zh: "推断",
                ja: "推論",
                ko: "추론"
            )
        }
    }

    nonisolated private static func directionText(
        for direction: GoldImpactDirection,
        dataState: GoldIntelligenceDataState,
        language: AppLanguage
    ) -> String {
        guard dataState != .unavailable else {
            return LocalizedString.l(
                language,
                en: "No direction yet",
                zh: "暂无方向",
                ja: "方向なし",
                ko: "방향 없음"
            )
        }
        switch direction {
        case .bullish:
            return LocalizedString.l(language, en: "Short-term bullish", zh: "短线偏多", ja: "短期強気", ko: "단기 강세")
        case .bearish:
            return LocalizedString.l(language, en: "Short-term bearish", zh: "短线偏空", ja: "短期弱気", ko: "단기 약세")
        case .neutral:
            return LocalizedString.l(language, en: "Short-term neutral", zh: "短线中性", ja: "短期中立", ko: "단기 중립")
        }
    }

    nonisolated private static func confidenceWord(
        _ confidence: GoldImpactConfidence,
        language: AppLanguage
    ) -> String {
        switch confidence {
        case .unavailable:
            return LocalizedString.l(language, en: "unavailable", zh: "不可用", ja: "利用不可", ko: "사용 불가")
        case .low:
            return LocalizedString.l(language, en: "low", zh: "低", ja: "低", ko: "낮음")
        case .medium:
            return LocalizedString.l(language, en: "medium", zh: "中", ja: "中", ko: "보통")
        case .high:
            return LocalizedString.l(language, en: "high", zh: "高", ja: "高", ko: "높음")
        }
    }

    nonisolated private static func dataStateText(
        for dataState: GoldIntelligenceDataState,
        language: AppLanguage
    ) -> String {
        switch dataState {
        case .live:
            return LocalizedString.l(language, en: "Live data", zh: "实时数据", ja: "リアルタイムデータ", ko: "실시간 데이터")
        case .partial:
            return LocalizedString.l(language, en: "Incomplete data", zh: "数据不完整", ja: "不完全なデータ", ko: "불완전한 데이터")
        case .stale:
            return LocalizedString.l(language, en: "Cached data", zh: "缓存数据", ja: "キャッシュデータ", ko: "캐시 데이터")
        case .unavailable:
            return LocalizedString.l(language, en: "Data unavailable", zh: "数据不可用", ja: "データ利用不可", ko: "데이터 사용 불가")
        }
    }

    nonisolated private static func riskWord(
        _ risk: GoldVolatilityRisk,
        language: AppLanguage
    ) -> String {
        switch risk {
        case .normal:
            return LocalizedString.l(language, en: "normal", zh: "正常", ja: "通常", ko: "보통")
        case .elevated:
            return LocalizedString.l(language, en: "elevated", zh: "升高", ja: "上昇", ko: "높아짐")
        case .high:
            return LocalizedString.l(language, en: "high", zh: "高", ja: "高い", ko: "높음")
        }
    }
}

// MARK: - 事件影响卡片

/// 展示事件影响引擎的方向、置信度、波动风险、证据链与反方风险。
/// 只负责解释，不生成任何交易动作（买入/卖出/减仓等），也不参与策略加权。
struct EventImpactCard: View {
    let impact: GoldEventImpact?
    let isLoading: Bool

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var language: AppLanguage { settings.language }

    private var presentation: GoldEventImpactPresentation? {
        guard let impact else { return nil }
        return GoldEventImpactPresentation(impact: impact, language: language)
    }

    private var directionTint: Color {
        switch impact?.direction ?? .neutral {
        case .bullish: AppTheme.marketUp
        case .neutral: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .bearish: AppTheme.marketDown
        }
    }

    /// 默认展开的 observed / inferred 条数上限，其余折叠进 DisclosureGroup。
    private static let maxExpandedObserved = 3
    private static let maxExpandedInferred = 2

    private var observedEvidence: [GoldEventEvidence] {
        (impact?.evidence ?? []).filter { $0.state == .observed }
    }

    private var inferredEvidence: [GoldEventEvidence] {
        (impact?.evidence ?? []).filter { $0.state == .inferred }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let impact, let presentation {
                metricRow(presentation)

                stateBadge(impact)

                Text(impact.headline)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if !observedEvidence.isEmpty {
                    Divider().opacity(0.45)
                    evidenceSection(
                        state: .observed,
                        items: observedEvidence,
                        expandedLimit: Self.maxExpandedObserved
                    )
                }

                if !inferredEvidence.isEmpty {
                    if observedEvidence.isEmpty { Divider().opacity(0.45) }
                    evidenceSection(
                        state: .inferred,
                        items: inferredEvidence,
                        expandedLimit: Self.maxExpandedInferred
                    )
                }

                if !impact.counterRisks.isEmpty {
                    Divider().opacity(0.45)
                    counterRiskSection(impact.counterRisks)
                }
            } else {
                Text(
                    isLoading
                        ? LocalizedString.l(language, en: "Loading event impact…", zh: "正在获取事件影响…", ja: "イベント影響を取得中…", ko: "이벤트 영향을 가져오는 중…")
                        : LocalizedString.l(language, en: "Event impact is unavailable", zh: "事件影响数据暂不可用", ja: "イベント影響データを利用できません", ko: "이벤트 영향 데이터를 사용할 수 없습니다")
                )
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(LocalizedString.l(
                language,
                en: "Event impact is a logical analysis of public data, not investment advice.",
                zh: "事件影响为基于公开数据的逻辑分析，不构成投资建议。",
                ja: "イベント影響は公開データに基づく論理分析であり、投資助言ではありません。",
                ko: "이벤트 영향은 공개 데이터 기반의 논리적 분석이며, 투자 조언이 아닙니다."
            ))
            .font(.system(size: 8))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(directionTint.opacity(0.18), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(
                LocalizedString.l(language, en: "Event impact", zh: "事件影响", ja: "イベント影響", ko: "이벤트 영향"),
                systemImage: "bolt.horizontal"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(directionTint)

            Spacer(minLength: 6)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let updatedAt = impact?.updatedAt {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(LocalizedString.l(language, en: "As of ", zh: "数据截至 ", ja: "データ時点 ", ko: "데이터 기준 "))
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Text(updatedAt, style: .time)
                        .font(.system(size: 8.5))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }
        }
    }

    private func metricRow(_ presentation: GoldEventImpactPresentation) -> some View {
        HStack(spacing: 6) {
            metricChip(text: presentation.directionText, tint: directionTint)
            Spacer(minLength: 0)
            metricChip(text: presentation.confidenceText, tint: AppTheme.textPrimary(colorScheme))
            Spacer(minLength: 0)
            metricChip(text: presentation.riskText, tint: riskTint)
        }
    }

    private func metricChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            }
    }

    private var riskTint: Color {
        switch impact?.volatilityRisk ?? .normal {
        case .normal: AppTheme.textSecondary(colorScheme)
        case .elevated: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .high: AppTheme.critical
        }
    }

    /// 数据状态用文字 + 图标表达，不只靠颜色。
    @ViewBuilder
    private func stateBadge(_ impact: GoldEventImpact) -> some View {
        let (text, icon, tint): (String, String, Color) = {
            switch impact.dataState {
            case .live:
                return (LocalizedString.l(language, en: "Live data", zh: "实时数据", ja: "リアルタイムデータ", ko: "실시간 데이터"), "checkmark.circle", AppTheme.healthy)
            case .partial:
                return (LocalizedString.l(language, en: "Incomplete data", zh: "数据不完整", ja: "不完全なデータ", ko: "불완전한 데이터"), "exclamationmark.triangle", AppTheme.warning)
            case .stale:
                return (LocalizedString.l(language, en: "Cached data", zh: "缓存数据", ja: "キャッシュデータ", ko: "캐시 데이터"), "clock.badge.checkmark", Color(red: 0.88, green: 0.57, blue: 0.16))
            case .unavailable:
                return (LocalizedString.l(language, en: "Data unavailable", zh: "数据不可用", ja: "データ利用不可", ko: "데이터 사용 불가"), "wifi.slash", AppTheme.critical)
            }
        }()
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func evidenceSection(
        state: GoldEvidenceState,
        items: [GoldEventEvidence],
        expandedLimit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(GoldEventImpactPresentation.evidenceLabel(for: state, language: language))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            ForEach(items.prefix(expandedLimit)) { evidence in
                evidenceRow(evidence)
            }

            if items.count > expandedLimit {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(items.dropFirst(expandedLimit)) { evidence in
                            evidenceRow(evidence)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text(LocalizedString.l(
                        language,
                        en: "Show \(items.count - expandedLimit) more",
                        zh: "展开其余 \(items.count - expandedLimit) 条",
                        ja: "残り \(items.count - expandedLimit) 件を表示",
                        ko: "나머지 \(items.count - expandedLimit)개 보기"
                    ))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }
        }
    }

    @ViewBuilder
    private func evidenceRow(_ evidence: GoldEventEvidence) -> some View {
        let content = HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(evidenceTint(evidence.direction))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(evidence.summary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    if let source = evidence.source, !source.isEmpty {
                        Text(source)
                    }
                    if let observedAt = evidence.observedAt {
                        Text(observedAt, style: .relative)
                    }
                }
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }

            Spacer(minLength: 0)

            if evidence.link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }

        // 新闻链接只挂在对应 observed 证据上，推断不提供跳转
        if let link = evidence.link, evidence.state == .observed {
            Link(destination: link) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func evidenceTint(_ direction: GoldImpactDirection) -> Color {
        switch direction {
        case .bullish: AppTheme.marketUp
        case .neutral: AppTheme.textSecondary(colorScheme)
        case .bearish: AppTheme.marketDown
        }
    }

    private func counterRiskSection(_ risks: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                LocalizedString.l(language, en: "Counter risks", zh: "反方风险", ja: "反対リスク", ko: "반대 리스크"),
                systemImage: "exclamationmark.circle"
            )
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Color(red: 0.88, green: 0.57, blue: 0.16))

            ForEach(Array(risks.prefix(3).enumerated()), id: \.offset) { _, risk in
                Label(risk, systemImage: "circle.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 预测学习卡片

struct PredictionLearningCard: View {
    let summary: GoldPredictionLearningSummary
    let records: [GoldPredictionLearningRecord]
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var calibration: GoldStrategyCalibration {
        summary.strategyCalibration
    }

    // 基于已验证样本解释本次校准的依据
    private var calibrationReason: String? {
        guard summary.validatedCount >= 8, let hitRate = summary.hitRate else { return nil }
        return String(
            format: LocalizedString.gold("calibration_reason_format"),
            summary.validatedCount,
            hitRate.percentNumber,
            summary.averagePredictionBias?.signedPercentNumber ?? "--"
        )
    }

    private var recentRecords: [GoldPredictionLearningRecord] {
        Array(records.sorted { $0.createdAt > $1.createdAt }.prefix(3))
    }

    private var tint: Color {
        guard let hitRate = summary.hitRate, summary.validatedCount >= 8 else {
            return Color(red: 0.88, green: 0.57, blue: 0.16)
        }

        if hitRate >= 0.62 { return AppTheme.healthy }
        if hitRate <= 0.42 { return AppTheme.critical }
        return Color(red: 0.88, green: 0.57, blue: 0.16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(LocalizedString.gold("prediction_learning"), systemImage: "target")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 6)

                Text(summary.hitRate?.percentNumber ?? "--")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            HStack(spacing: 6) {
                StrategyMetric(
                    title: LocalizedString.gold("validated"),
                    value: "\(summary.validatedCount)",
                    detail: String(format: LocalizedString.gold("pending_count_format"), summary.pendingCount),
                    help: LocalizedString.l(AppSettings.shared.language, en: "Each strategy sample is recorded and checked against the real gold price about 30 minutes later.", zh: "每次策略形成后会记录一个样本，约 30 分钟后用真实金价验证方向和误差。", ja: "戦略が形成されるたびにサンプルを記録し、約30分後に実際の金価格で方向と誤差を検証します。", ko: "전략이 만들어질 때마다 샘플을 기록하고 약 30분 뒤 실제 금 가격으로 방향과 오차를 검증합니다.")
                )
                StrategyMetric(
                    title: LocalizedString.gold("average_error"),
                    value: summary.averageAbsoluteError?.percentNumber ?? "--",
                    detail: LocalizedString.gold("minutes_30"),
                    help: LocalizedString.l(AppSettings.shared.language, en: "Average gap between predicted and actual return. Lower means the short-term forecast is closer to reality.", zh: "预测收益率和实际收益率之间的平均差距，越低说明短线预测越贴近现实。", ja: "予測リターンと実績リターンの平均差です。低いほど短期予測が現実に近いことを示します。", ko: "예측 수익률과 실제 수익률의 평균 차이입니다. 낮을수록 단기 예측이 현실에 가깝습니다.")
                )
                StrategyMetric(
                    title: LocalizedString.gold("bias"),
                    value: summary.averagePredictionBias?.signedPercentNumber ?? "--",
                    detail: LocalizedString.gold("prediction_minus_actual"),
                    help: LocalizedString.l(AppSettings.shared.language, en: "Positive means the model is optimistic; negative means conservative. With few samples it is only observed, not auto-tuned.", zh: "正数表示模型偏乐观，负数表示偏保守。样本少时只做观察，不自动调参。", ja: "正の値は楽観寄り、負の値は保守寄りです。サンプルが少ない間は観察のみで自動調整しません。", ko: "양수는 모델이 낙관적, 음수는 보수적임을 뜻합니다. 샘플이 적을 때는 관찰만 하고 자동 조정하지 않습니다.")
                )
            }

            Text(summary.calibrationText)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if !appSettings.goldAutoCalibrationEnabled {
                VStack(alignment: .leading, spacing: 3) {
                    Label(LocalizedString.gold("calibration_off_note"), systemImage: "pause.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    if !calibration.isNeutral {
                        Text(String(
                            format: LocalizedString.gold("calibration_observed_format"),
                            calibration.confidenceMultiplier.twoDigitNumber,
                            calibration.exposureMultiplier.twoDigitNumber
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if !calibration.isNeutral {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        String(
                            format: LocalizedString.gold("calibration_applied_format"),
                            calibration.confidenceMultiplier.twoDigitNumber,
                            calibration.exposureMultiplier.twoDigitNumber
                        ),
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)

                    // 解释为什么本次建议被调低/调高
                    if let calibrationReason {
                        Text("\(calibration.note) · \(calibrationReason)")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !recentRecords.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label(LocalizedString.gold("recent_prediction_review"), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))

                    ForEach(recentRecords) { record in
                        PredictionRecordRow(record: record)
                    }
                }
                .padding(8)
                .background(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.34))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

struct PredictionRecordRow: View {
    let record: GoldPredictionLearningRecord
    @Environment(\.colorScheme) private var colorScheme

    private var directionText: String {
        switch record.predictedDirection {
        case "buy": return LocalizedString.gold("buy")
        case "sell": return LocalizedString.gold("sell")
        default: return LocalizedString.gold("hold")
        }
    }

    private var statusText: String {
        switch record.status {
        case .pending:
            return LocalizedString.gold("pending")
        case .validated:
            if record.wasDirectionalHit == true { return LocalizedString.gold("hit") }
            if record.wasDirectionalHit == false { return LocalizedString.gold("miss") }
            return LocalizedString.gold("validated")
        }
    }

    private var tint: Color {
        if record.status == .pending {
            return Color(red: 0.88, green: 0.57, blue: 0.16)
        }
        return record.wasDirectionalHit == true ? AppTheme.healthy : AppTheme.critical
    }

    private var detailText: String {
        if let actualReturn = record.actualReturn {
            return "\(String(format: LocalizedString.gold("actual_return_format"), actualReturn.signedPercentNumber)) · \(record.strategyVersion)"
        }
        return String(format: LocalizedString.gold("waiting_result_format"), record.strategyVersion)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(directionText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    Text(record.createdAt, style: .time)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }

                Text(detailText)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 策略指标

struct StrategyMetric: View {
    let title: String
    let value: String
    let detail: String
    let help: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.75))
                    .help(help)
            }

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Text(detail)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .help(help)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(AppTheme.progressBg(colorScheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct StrategyRow: View {
    let title: String
    let value: String
    let detail: String
    let help: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.8))
                        .help(help)
                }

                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .help(help)
    }
}

// MARK: - 术语表

struct BeginnerGlossaryCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 7) {
                GlossaryLine(term: "RSI", explanation: LocalizedString.l(AppSettings.shared.language, en: "Shows whether price may have risen or fallen too quickly. Above 70 is expensive; below 30 is cheap.", zh: "看价格是不是涨太快或跌太快。70 以上偏贵，30 以下偏便宜。", ja: "価格が上がり過ぎ・下がり過ぎかを見る指標です。70以上は割高、30以下は割安寄りです。", ko: "가격이 너무 빨리 오르거나 내렸는지 봅니다. 70 이상은 비싼 편, 30 이하는 싼 편입니다."))
                GlossaryLine(term: "MACD", explanation: LocalizedString.l(AppSettings.shared.language, en: "Compares short-term and medium-term momentum. Positive is stronger; negative is weaker.", zh: "看短期和中期力量谁更强。为正偏强，为负偏弱。", ja: "短期と中期の勢いを比べます。プラスは強め、マイナスは弱めです。", ko: "단기와 중기 힘을 비교합니다. 양수는 강하고 음수는 약합니다."))
                GlossaryLine(term: LocalizedString.gold("trend_strength"), explanation: LocalizedString.l(AppSettings.shared.language, en: "Higher values mean price is moving more like a trend.", zh: "数值越高，说明价格越像在沿一个方向走。", ja: "数値が高いほど、価格が一方向に動く傾向が強いことを示します。", ko: "값이 높을수록 가격이 한 방향으로 움직이는 추세가 강합니다."))
                GlossaryLine(term: LocalizedString.gold("mean_reversion_label"), explanation: LocalizedString.l(AppSettings.shared.language, en: "When price is far from its average, it may slowly move back toward it.", zh: "价格离平均价太远时，可能会慢慢靠回去。", ja: "価格が平均から離れすぎると、ゆっくり平均へ戻る可能性があります。", ko: "가격이 평균에서 너무 멀면 천천히 평균으로 돌아갈 수 있습니다."))
                GlossaryLine(term: LocalizedString.l(AppSettings.shared.language, en: "Grid", zh: "网格", ja: "グリッド", ko: "그리드"), explanation: LocalizedString.l(AppSettings.shared.language, en: "Works better in sideways markets by splitting trades into small levels: buy lower, sell higher.", zh: "适合震荡行情，分成很多小格，低一点买、高一点卖。", ja: "横ばい相場向きで、細かい水準に分けて安く買い、高く売る考え方です。", ko: "횡보장에 적합하며 여러 작은 구간으로 나누어 낮게 사고 높게 파는 방식입니다."))
                GlossaryLine(term: LocalizedString.gold("suggested_position"), explanation: LocalizedString.l(AppSettings.shared.language, en: "Suggested capital share if you participate. It is not a must-buy signal.", zh: "如果要参与，建议用多少比例资金；不是一定要买。", ja: "参加する場合の資金比率の目安です。必ず買うという意味ではありません。", ko: "참여한다면 어느 정도 비중이 좋은지 제안합니다. 반드시 사라는 뜻은 아닙니다."))
                GlossaryLine(term: LocalizedString.gold("average_cost"), explanation: LocalizedString.l(AppSettings.shared.language, en: "How much you paid per gram on average. It is the basis for profit and break-even.", zh: "你每克黄金平均花了多少钱。它是判断赚亏和回本价的基础。", ja: "1グラムあたり平均でいくら払ったかです。損益と損益分岐点の基準になります。", ko: "그램당 평균 얼마에 샀는지입니다. 손익과 본전 가격 판단의 기준입니다."))
                GlossaryLine(term: "\(LocalizedString.gold("floating_profit"))/\(LocalizedString.gold("floating_loss"))", explanation: LocalizedString.l(AppSettings.shared.language, en: "Temporary profit or loss calculated from current price. It can change before you sell.", zh: "按当前金价临时算出来的赚亏；没卖出前还会变化。", ja: "現在価格で一時的に計算した損益です。売却前は変動します。", ko: "현재 금 가격으로 임시 계산한 손익입니다. 팔기 전까지 계속 변할 수 있습니다."))
            }
            .padding(.top, 6)
        } label: {
            Label(LocalizedString.l(AppSettings.shared.language, en: "Need help with these terms?", zh: "看不懂这些词？", ja: "用語がわかりにくいですか？", ko: "이 용어들이 어렵나요?"), systemImage: "book")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct GlossaryLine: View {
    let term: String
    let explanation: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            Text(explanation)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 指标胶囊

struct IndicatorPill: View {
    let title: String
    let value: String
    let detail: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.8))
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(colorScheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 黄金指标

struct GoldMetric: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 多平台价格卡片

struct MultiSourcePriceCard: View {
    let sources: [GoldMultiSourcePrice]
    let validation: DataValidationResult
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    LocalizedString.l(
                        settings.language,
                        en: "Cross-platform prices",
                        zh: "多平台金价",
                        ja: "プラットフォーム比較",
                        ko: "플랫폼별 금가"
                    ),
                    systemImage: "building.columns"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Spacer()
                if let updatedAt = sources.compactMap(\.updatedAt).max() {
                    Text(updatedAt, style: .time)
                        .font(.system(size: 8))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }

            VStack(spacing: 3) {
                ForEach(sortedSources) { source in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sourceTint(for: source))
                            .frame(width: 4, height: 4)
                        Text(localizedName(source.name))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("¥" + source.price.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textPrimary(colorScheme))
                            .frame(width: 62, alignment: .trailing)
                        changeText(for: source)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
                    }
                }
            }

            HStack {
                validationFooter
                Spacer(minLength: 6)
                if let spread = priceSpread {
                    Text(LocalizedString.l(
                        settings.language,
                        en: "Spread ¥\(spread.formatted(.number.precision(.fractionLength(2))))",
                        zh: "价差 ¥\(spread.formatted(.number.precision(.fractionLength(2))))",
                        ja: "価格差 ¥\(spread.formatted(.number.precision(.fractionLength(2))))",
                        ko: "가격차 ¥\(spread.formatted(.number.precision(.fractionLength(2))))"
                    ))
                    .font(.system(size: 8.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // 按价格从高到低排列，便于比价
    private var sortedSources: [GoldMultiSourcePrice] {
        sources.sorted { $0.price > $1.price }
    }

    // 各平台最高与最低报价之差
    private var priceSpread: Double? {
        guard let high = sources.map(\.price).max(),
              let low = sources.map(\.price).min(),
              sources.count > 1 else { return nil }
        return high - low
    }

    // 最高价标红、最低价标绿，其余中性色
    private func sourceTint(for source: GoldMultiSourcePrice) -> Color {
        if source.price == sources.map(\.price).max() { return AppTheme.marketUp.opacity(0.7) }
        if source.price == sources.map(\.price).min() { return AppTheme.marketDown.opacity(0.7) }
        return AppTheme.textSecondary(colorScheme).opacity(0.5)
    }

    // 接口返回中文平台名（如"新浪-股票|基金API"），映射为四语名称
    private func localizedName(_ name: String) -> String {
        let lang = settings.language
        if name.contains("新浪") {
            return LocalizedString.l(lang, en: "Sina Finance", zh: "新浪财经", ja: "新浪財経", ko: "시나 파이낸스")
        }
        if name.contains("民生") {
            return LocalizedString.l(lang, en: "Minsheng Bank", zh: "民生银行", ja: "民生銀行", ko: "민생은행")
        }
        if name.contains("浙商") {
            return LocalizedString.l(lang, en: "CZBank", zh: "浙商银行", ja: "浙商銀行", ko: "저상은행")
        }
        if name.contains("工商") {
            return LocalizedString.l(lang, en: "ICBC", zh: "工商银行", ja: "工商銀行", ko: "공상은행")
        }
        return name.split(separator: "-").first.map(String.init) ?? name
    }

    @ViewBuilder
    private func changeText(for source: GoldMultiSourcePrice) -> some View {
        if let rate = source.changeRatePercent {
            Text(rate.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.marketColor(for: rate))
        } else {
            Text("--")
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
    }

    @ViewBuilder
    private var validationFooter: some View {
        switch validation {
        case .valid:
            footerLabel(
                icon: "checkmark.seal",
                color: AppTheme.healthy,
                text: LocalizedString.l(
                    settings.language,
                    en: "Price cross-validated",
                    zh: "与各平台报价一致",
                    ja: "価格検証済み",
                    ko: "가격 교차 검증됨"
                )
            )
        case .multiSourceMismatch(let price, let median):
            footerLabel(
                icon: "exclamationmark.triangle",
                color: Color.orange,
                text: LocalizedString.l(
                    settings.language,
                    en: String(format: "Deviation %.2f%% from median", abs(price - median) / median * 100),
                    zh: String(format: "与多源中位数偏差 %.2f%%", abs(price - median) / median * 100),
                    ja: String(format: "中央値との乖離 %.2f%%", abs(price - median) / median * 100),
                    ko: String(format: "중앙값 대비 편차 %.2f%%", abs(price - median) / median * 100)
                )
            )
        default:
            EmptyView()
        }
    }

    private func footerLabel(icon: String, color: Color, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(color)
    }
}

// MARK: - 国际市场参考

struct GlobalMarketCard: View {
    let snapshot: GoldGlobalSnapshot
    let domesticPrice: Double
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    // 国内现价相对国际折算克价的溢价（%）
    private var premiumPercent: Double? {
        let converted = snapshot.convertedCnyPerGram
        guard converted > 0, domesticPrice > 0 else { return nil }
        return (domesticPrice - converted) / converted * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    LocalizedString.l(
                        settings.language,
                        en: "Global market",
                        zh: "国际市场",
                        ja: "国際市場",
                        ko: "국제 시장"
                    ),
                    systemImage: "globe"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
                Spacer()
                Text(snapshot.updatedAt, style: .time)
                    .font(.system(size: 8))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }

            VStack(spacing: 3) {
                metricRow(
                    title: "XAU/USD",
                    value: "$" + snapshot.xauUsd.formatted(.number.precision(.fractionLength(2))),
                    change: snapshot.xauChangePercent
                )
                if let dollarIndex = snapshot.dollarIndex {
                    metricRow(
                        title: LocalizedString.l(settings.language, en: "Dollar index", zh: "美元指数", ja: "ドル指数", ko: "달러 지수"),
                        value: dollarIndex.formatted(.number.precision(.fractionLength(2))),
                        change: nil
                    )
                }
                metricRow(
                    title: "USD/CNY",
                    value: snapshot.usdCny.formatted(.number.precision(.fractionLength(4))),
                    change: nil
                )
                metricRow(
                    title: LocalizedString.l(settings.language, en: "Converted ¥/g", zh: "折合克价", ja: "換算グラム単価", ko: "환산 그램당 가격"),
                    value: "¥" + snapshot.convertedCnyPerGram.formatted(.number.precision(.fractionLength(2))),
                    change: nil
                )
            }

            if let premium = premiumPercent {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Text(LocalizedString.l(
                        settings.language,
                        en: "Domestic premium vs global",
                        zh: "国内现价相对国际溢价",
                        ja: "国内価格の対国際プレミアム",
                        ko: "국내 가격의 국제 대비 프리미엄"
                    ))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    Spacer(minLength: 4)
                    Text(premium.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.marketColor(for: premium))
                }
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.black.opacity(0.30) : Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func metricRow(title: String, value: String, change: Double?) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.textSecondary(colorScheme).opacity(0.5))
                .frame(width: 4, height: 4)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            if let change {
                Text(change.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.marketColor(for: change))
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
        }
    }
}

// MARK: - 涨跌徽章

struct ChangeBadge: View {
    let change: Double
    let percent: Double

    private var tint: Color {
        AppTheme.marketColor(for: change)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(change.signedPriceText)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
            Text(percent.signedPercentText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .monospacedDigit()
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Double 扩展

extension Double {
    var goldPriceNumber: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var shortNumber: String {
        formatted(.number.precision(.fractionLength(1)))
    }

    var twoDigitNumber: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var threeDigitNumber: String {
        formatted(.number.precision(.fractionLength(3)))
    }

    var signedShortNumber: String {
        formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)))
    }

    var signedPriceText: String {
        formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)))
    }

    var signedPercentText: String {
        formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%"
    }

    var percentNumber: String {
        formatted(.percent.precision(.fractionLength(1)))
    }

    var signedPercentNumber: String {
        formatted(.percent.sign(strategy: .always()).precision(.fractionLength(1)))
    }

    var moneyNumber: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var signedMoneyNumber: String {
        "¥" + formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)))
    }

    var signedCompactPercentText: String {
        formatted(.percent.sign(strategy: .always()).precision(.fractionLength(1)))
    }

    var singleDigitNumber: String {
        formatted(.number.precision(.fractionLength(0)))
    }
}
