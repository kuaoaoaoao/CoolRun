import SwiftUI
import AppKit

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

