import SwiftUI
import AppKit

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
        if name.contains("新浪") {  // i18n-allow: 数据源中文名匹配（后端返回的原始名称）
            return LocalizedString.l(lang, en: "Sina Finance", zh: "新浪财经", ja: "新浪財経", ko: "시나 파이낸스")
        }
        if name.contains("民生") {  // i18n-allow: 数据源中文名匹配（后端返回的原始名称）
            return LocalizedString.l(lang, en: "Minsheng Bank", zh: "民生银行", ja: "民生銀行", ko: "민생은행")
        }
        if name.contains("浙商") {  // i18n-allow: 数据源中文名匹配（后端返回的原始名称）
            return LocalizedString.l(lang, en: "CZBank", zh: "浙商银行", ja: "浙商銀行", ko: "저상은행")
        }
        if name.contains("工商") {  // i18n-allow: 数据源中文名匹配（后端返回的原始名称）
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

