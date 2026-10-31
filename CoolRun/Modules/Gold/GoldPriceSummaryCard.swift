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
