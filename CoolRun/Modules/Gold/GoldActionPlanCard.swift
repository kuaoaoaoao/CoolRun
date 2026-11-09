import SwiftUI

/// 「现在怎么办」卡片：动作、仓位、三个价位、理由与失效条件。
/// 放在金价页最上面，因为用户打开这个面板 90% 的时间只想问这一件事。
struct GoldActionPlanCard: View {
    let plan: GoldActionPlan?
    /// 周预测还没算完时显示骨架，避免「先空一下再跳出来」
    var isLoading: Bool = false

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var language: AppLanguage { settings.language }

    private var tint: Color {
        guard let plan else { return AppTheme.textSecondary(colorScheme) }
        switch plan.verb {
        case .buy: return AppTheme.marketUp
        case .accumulate: return AppTheme.gold
        case .hold: return AppTheme.marketFlat
        case .reduce: return AppTheme.warning
        case .sell: return AppTheme.marketDown
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let plan {
                actionRow(plan)
                priceGrid(plan)
                Divider().opacity(0.4)
                reasonList(plan)
                if !plan.risks.isEmpty {
                    riskList(plan)
                }
                invalidationRow(plan)
                disclaimer
            } else if isLoading {
                loadingRows
            } else {
                Text(LocalizedString.l(
                    language,
                    en: "Not enough data for a plan yet. Keep the app running so history builds up.",
                    zh: "数据还不够生成计划。让 app 多跑一会儿，历史攒起来就有了。",
                    ja: "計画に必要なデータがまだ足りません。履歴が溜まるまで起動したままに。",
                    ko: "계획을 만들 데이터가 아직 부족합니다. 기록이 쌓일 때까지 실행해 두세요."
                ))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(GoldLayout.cardPadding)
        .background {
            ZStack {
                AppTheme.elevatedSurface(colorScheme)
                LinearGradient(
                    colors: [tint.opacity(colorScheme == .dark ? 0.12 : 0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: GoldLayout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoldLayout.cardRadius, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 0.5)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, GoldLayout.cardPadding)
                .padding(.leading, 6)
        }
    }

    // MARK: - 头

    private var header: some View {
        HStack(spacing: 6) {
            Label(
                LocalizedString.l(
                    language,
                    en: "What to do now",
                    zh: "现在怎么办",
                    ja: "今どうする",
                    ko: "지금 어떻게"
                ),
                systemImage: "target"
            )
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(AppTheme.gold)

            Spacer(minLength: 4)

            if let plan {
                Text(LocalizedString.l(
                    language,
                    en: "\(plan.horizonDays)-day view",
                    zh: "\(plan.horizonDays) 天视角",
                    ja: "\(plan.horizonDays) 日視点",
                    ko: "\(plan.horizonDays)일 관점"
                ))
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
        }
    }

    // MARK: - 动作

    private func actionRow(_ plan: GoldActionPlan) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: plan.verb.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)

                Text(plan.verb.title(language))
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .fixedSize()

                Spacer(minLength: 4)

                confidenceBadge(plan)
            }

            Text(plan.verb.detail(language))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                chip(
                    LocalizedString.l(
                        language,
                        en: "Suggested size \(percent(plan.exposurePercent))",
                        zh: "建议仓位 \(percent(plan.exposurePercent))",
                        ja: "推奨比率 \(percent(plan.exposurePercent))",
                        ko: "권장 비중 \(percent(plan.exposurePercent))"
                    ),
                    icon: "chart.pie"
                )
                if let probability = plan.probabilityUp {
                    chip(
                        LocalizedString.l(
                            language,
                            en: "Up odds \(Int((probability * 100).rounded()))%",
                            zh: "上涨概率 \(Int((probability * 100).rounded()))%",
                            ja: "上昇確率 \(Int((probability * 100).rounded()))%",
                            ko: "상승 확률 \(Int((probability * 100).rounded()))%"
                        ),
                        icon: "dice"
                    )
                }
            }
        }
    }

    private func confidenceBadge(_ plan: GoldActionPlan) -> some View {
        HStack(spacing: 4) {
            Text("\(Int((plan.confidence * 100).rounded()))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(LocalizedString.gold("confidence", lang: language))
                .font(.system(size: 8))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.18), lineWidth: 0.5)
        }
    }

    private func chip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(AppTheme.progressBg(colorScheme).opacity(0.5), in: Capsule())
    }

    // MARK: - 价位

    private func priceGrid(_ plan: GoldActionPlan) -> some View {
        HStack(spacing: 6) {
            priceCell(
                title: LocalizedString.l(
                    language,
                    en: "Entry",
                    zh: plan.verb.isBearish ? "减仓区" : "买入区",
                    ja: plan.verb.isBearish ? "売却ゾーン" : "買いゾーン",
                    ko: plan.verb.isBearish ? "매도 구간" : "매수 구간"
                ),
                value: "\(price(plan.entryLow))–\(price(plan.entryHigh))",
                tint: tint
            )
            priceCell(
                title: LocalizedString.l(
                    language,
                    en: "Stop",
                    zh: "止损",
                    ja: "損切り",
                    ko: "손절"
                ),
                value: price(plan.stopLoss),
                tint: AppTheme.critical
            )
            priceCell(
                title: LocalizedString.l(
                    language,
                    en: "Target",
                    zh: "目标",
                    ja: "目標",
                    ko: "목표"
                ),
                value: price(plan.target),
                tint: AppTheme.healthy
            )
        }
    }

    private func priceCell(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(AppTheme.progressBg(colorScheme).opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - 理由与风险

    private func reasonList(_ plan: GoldActionPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(plan.reasons.enumerated()), id: \.offset) { _, reason in
                HStack(alignment: .top, spacing: 5) {
                    Circle()
                        .fill(tint.opacity(0.55))
                        .frame(width: 3.5, height: 3.5)
                        .padding(.top, 5)
                    Text(reason)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme).opacity(0.86))
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func riskList(_ plan: GoldActionPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(plan.risks.enumerated()), id: \.offset) { _, risk in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(AppTheme.warning)
                        .padding(.top, 1)
                    Text(risk)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.warning.opacity(0.92))
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func invalidationRow(_ plan: GoldActionPlan) -> some View {
        Text(plan.invalidation)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.9))
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.progressBg(colorScheme).opacity(0.4), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var disclaimer: some View {
        Text(LocalizedString.l(
            language,
            en: "Rule-based plan from price history and models, not investment advice.",
            zh: "计划由价格历史与规则模型算出，不构成投资建议。",
            ja: "価格履歴とモデルに基づく計画であり、投資助言ではありません。",
            ko: "가격 이력과 모델 기반 계획이며 투자 조언이 아닙니다."
        ))
        .font(.system(size: 8))
        .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.7))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var loadingRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(AppTheme.progressBg(colorScheme)).frame(width: 120, height: 16)
            RoundedRectangle(cornerRadius: 4).fill(AppTheme.progressBg(colorScheme)).frame(height: 28)
            RoundedRectangle(cornerRadius: 4).fill(AppTheme.progressBg(colorScheme)).frame(height: 28)
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - 格式化

    private func price(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
