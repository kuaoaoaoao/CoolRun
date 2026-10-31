import SwiftUI
import AppKit

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

