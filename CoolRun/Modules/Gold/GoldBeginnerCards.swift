import SwiftUI
import AppKit

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

