import SwiftUI
import AppKit

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

