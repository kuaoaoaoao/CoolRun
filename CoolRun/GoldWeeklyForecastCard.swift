import SwiftUI
import AppKit

// MARK: - 纯文案映射（可测试）

/// 一周预测卡片的展示文本转换：只做文案，不做推断。
/// 任何状态都不输出交易操作指令，只做统计预测展示。
struct GoldWeeklyForecastPresentation: Equatable {
    let title: String
    let directionText: String?
    let confidenceText: String?
    let statusText: String
    let targetText: String?
    let sourceText: String?

    nonisolated init(snapshot: GoldWeeklyForecastSnapshot, language: AppLanguage) {
        title = LocalizedString.l(
            language,
            en: "Weekly gold outlook",
            zh: "一周方向预测",
            ja: "週間金相場見通し",
            ko: "주간 금 전망"
        )

        guard snapshot.status == .ready, let forecast = snapshot.forecast else {
            directionText = nil
            confidenceText = nil
            statusText = snapshot.message
            targetText = nil
            sourceText = nil
            return
        }

        directionText = Self.directionText(for: forecast.direction, language: language)
        confidenceText = LocalizedString.l(
            language,
            en: "Confidence: \(Self.confidenceWord(forecast.confidence, language: .english))",
            zh: "信心：\(Self.confidenceWord(forecast.confidence, language: .chinese))",
            ja: "信頼度：\(Self.confidenceWord(forecast.confidence, language: .japanese))",
            ko: "신뢰도: \(Self.confidenceWord(forecast.confidence, language: .korean))"
        )

        if let backtest = snapshot.backtest {
            let template = LocalizedString.l(
                language,
                en: "Backtest samples: %d",
                zh: "回测样本：%d",
                ja: "バックテストサンプル：%d",
                ko: "백테스트 샘플: %d"
            )
            statusText = String(format: template, backtest.resolvedCount)
        } else {
            statusText = snapshot.message
        }

        let formatter = Self.dayFormatter
        let targetTemplate = LocalizedString.l(
            language,
            en: "Target date: %@",
            zh: "目标日期：%@",
            ja: "目標日：%@",
            ko: "목표일: %@"
        )
        targetText = String(format: targetTemplate, formatter.string(from: forecast.targetDate))

        sourceText = forecast.sourceCompatibility == .proxy
            ? LocalizedString.l(
                language,
                en: "The weekly model uses domestic gold reference daily closes",
                zh: "历史模型使用国内黄金参考日线",
                ja: "週次モデルは国内金の参考日足を使用しています",
                ko: "주간 모델은 국내 금 참고 일봉을 사용합니다"
            )
            : nil
    }

    /// 与语言无关的固定日期格式，避免测试环境地区差异。
    nonisolated private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    nonisolated private static func directionText(
        for direction: GoldWeeklyForecastDirection,
        language: AppLanguage
    ) -> String {
        switch direction {
        case .up:
            return LocalizedString.l(language, en: "Up", zh: "上涨", ja: "上昇", ko: "상승")
        case .flat:
            return LocalizedString.l(language, en: "Flat", zh: "持平", ja: "横ばい", ko: "보합")
        case .down:
            return LocalizedString.l(language, en: "Down", zh: "下跌", ja: "下落", ko: "하락")
        }
    }

    nonisolated private static func confidenceWord(
        _ confidence: GoldWeeklyForecastConfidence,
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
}

// MARK: - 分析页卡片

/// 一周方向预测卡片：非 ready 状态也保持可见并说明原因。
/// 方向使用文字 + SF Symbol + 颜色，不只靠颜色区分。
struct GoldWeeklyForecastCard: View {
    let snapshot: GoldWeeklyForecastSnapshot?
    let isLoading: Bool

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var language: AppLanguage { settings.language }

    private var presentation: GoldWeeklyForecastPresentation? {
        guard let snapshot else { return nil }
        return GoldWeeklyForecastPresentation(snapshot: snapshot, language: language)
    }

    private var directionTint: Color {
        switch snapshot?.forecast?.direction {
        case .up: AppTheme.healthy
        case .flat: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .down: AppTheme.critical
        case nil: AppTheme.textSecondary(colorScheme)
        }
    }

    private var directionSymbol: String {
        switch snapshot?.forecast?.direction {
        case .up: "arrow.up.circle.fill"
        case .flat: "arrow.left.arrow.right.circle.fill"
        case .down: "arrow.down.circle.fill"
        case nil: "questionmark.circle"
        }
    }

    /// 展示的 reasons / counterRisks 条数上限
    private static let maxReasons = 4
    private static let maxCounterRisks = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let snapshot, let presentation, let forecast = snapshot.forecast, snapshot.status == .ready {
                directionRow(presentation)

                metricChips(presentation, forecast: forecast)

                priceGrid(forecast)

                if !forecast.reasons.isEmpty {
                    Divider().opacity(0.45)
                    reasonSection(forecast.reasons, isCounterRisk: false)
                }

                if !forecast.counterRisks.isEmpty {
                    Divider().opacity(0.45)
                    reasonSection(forecast.counterRisks, isCounterRisk: true)
                }

                if let backtest = snapshot.backtest {
                    Divider().opacity(0.45)
                    backtestSection(backtest)
                }
            } else if let presentation {
                Text(presentation.statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    isLoading
                        ? LocalizedString.l(language, en: "Loading weekly forecast…", zh: "正在生成一周预测…", ja: "週間予測を生成中…", ko: "주간 예측 생성 중…")
                        : LocalizedString.l(language, en: "Weekly forecast is unavailable", zh: "一周预测暂不可用", ja: "週間予測を利用できません", ko: "주간 예측을 사용할 수 없습니다")
                )
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(LocalizedString.l(
                language,
                en: "The weekly outlook is a statistical estimate for information only and is not investment advice.",
                zh: "一周展望为统计估算，仅供参考，不构成投资建议。",
                ja: "週間見通しは統計的推定であり、参考情報であり投資助言ではありません。",
                ko: "주간 전망은 통계적 추정으로 참고용이며 투자 조언이 아닙니다."
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
                presentation?.title
                    ?? LocalizedString.l(language, en: "Weekly gold outlook", zh: "一周方向预测", ja: "週間金相場見通し", ko: "주간 금 전망"),
                systemImage: "calendar.badge.clock"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.gold)

            Spacer(minLength: 6)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let updatedAt = snapshot?.updatedAt {
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

    /// 方向 = 文字 + SF Symbol + 颜色，三重表达。
    private func directionRow(_ presentation: GoldWeeklyForecastPresentation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: directionSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(directionTint)

            Text(LocalizedString.l(
                language,
                en: "Next 7 days",
                zh: "未来一周",
                ja: "今後7日間",
                ko: "향후 7일"
            ))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary(colorScheme))

            Text(presentation.directionText ?? "--")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(directionTint)

            Spacer(minLength: 0)
        }
    }

    private func metricChips(
        _ presentation: GoldWeeklyForecastPresentation,
        forecast: GoldWeeklyForecast
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                metricChip(text: presentation.confidenceText ?? "", tint: AppTheme.textPrimary(colorScheme))
                Spacer(minLength: 0)
                metricChip(text: presentation.targetText ?? "", tint: AppTheme.textPrimary(colorScheme))
            }
            HStack(spacing: 6) {
                metricChip(text: presentation.statusText, tint: AppTheme.textSecondary(colorScheme))
                Spacer(minLength: 0)
                if let sourceText = presentation.sourceText {
                    metricChip(text: sourceText, tint: Color(red: 0.88, green: 0.57, blue: 0.16))
                }
            }
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

    private func priceGrid(_ forecast: GoldWeeklyForecast) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            priceRow(
                label: LocalizedString.l(language, en: "Current", zh: "当前价", ja: "現在価格", ko: "현재가"),
                value: forecast.startPrice.twoDigitNumber
            )
            priceRow(
                label: LocalizedString.l(language, en: "Expected", zh: "预期价", ja: "予想価格", ko: "예상가"),
                value: forecast.expectedPrice.twoDigitNumber
            )
            priceRow(
                label: LocalizedString.l(language, en: "Range (P10–P90)", zh: "区间（P10–P90）", ja: "レンジ（P10–P90）", ko: "범위(P10–P90)"),
                value: "\(forecast.p10.twoDigitNumber) – \(forecast.p90.twoDigitNumber)"
            )
            priceRow(
                label: LocalizedString.l(language, en: "Expected change", zh: "预期涨跌幅", ja: "予想変化率", ko: "예상 변동폭"),
                value: forecast.expectedReturn.signedPercentNumber
            )
        }
    }

    private func priceRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
        }
    }

    private func reasonSection(_ reasons: [String], isCounterRisk: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedString.l(
                language,
                en: isCounterRisk ? "Counter risks" : "Reasons",
                zh: isCounterRisk ? "对冲风险" : "依据",
                ja: isCounterRisk ? "対抗リスク" : "根拠",
                ko: isCounterRisk ? "반대 위험" : "근거"
            ))
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))

            ForEach(Array(reasons.prefix(isCounterRisk ? Self.maxCounterRisks : Self.maxReasons).enumerated()), id: \.offset) { _, reason in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: isCounterRisk ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.system(size: 8))
                        .foregroundStyle(isCounterRisk ? AppTheme.warning : AppTheme.healthy)
                        .padding(.top, 1.5)
                    Text(reason)
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func backtestSection(_ backtest: GoldWeeklyForecastBacktestSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedString.l(
                language,
                en: "Walk-forward backtest",
                zh: "走步回测",
                ja: "ウォークフォワード検証",
                ko: "워크포워드 백테스트"
            ))
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))

            HStack(spacing: 6) {
                if let balanced = backtest.balancedAccuracy {
                    statChip(
                        label: LocalizedString.l(language, en: "Balanced acc.", zh: "平衡准确率", ja: "バランス精度", ko: "균형 정확도"),
                        value: balanced.twoDigitNumber
                    )
                }
                if let error = backtest.meanAbsoluteReturnError {
                    statChip(
                        label: LocalizedString.l(language, en: "Mean error", zh: "平均误差", ja: "平均誤差", ko: "평균 오차"),
                        value: error.signedPercentNumber
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func statChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
        }
    }
}

// MARK: - 私有数字格式化

private extension Double {
    var twoDigitNumber: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var signedPercentNumber: String {
        formatted(.percent.sign(strategy: .always()).precision(.fractionLength(1)))
    }
}
