import SwiftUI
import Observation

/// 一周预测独立复盘页。
/// 汇总只来自 GoldWeeklyForecastStore，不得与 30 分钟预测学习 Store 相加。
@MainActor
struct GoldWeeklyForecastReviewView: View {
    @State private var store = GoldWeeklyForecastStore.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var language: AppLanguage { appSettings.language }

    private var tint: Color {
        switch store.records.last?.forecast.direction {
        case .up: AppTheme.healthy
        case .down: AppTheme.critical
        default: AppTheme.gold
        }
    }

    private var panelBg: some ShapeStyle {
        colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.48)
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                summaryCard

                if store.records.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    LocalizedString.l(language, en: "Weekly forecast review", zh: "一周预测复盘", ja: "週間予測レビュー", ko: "주간 예측 리뷰"),
                    systemImage: "calendar.badge.clock"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                Spacer()
                Text(store.summary.hitRate?.percentNumber ?? "--")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            HStack(spacing: 8) {
                WeeklyStatPill(
                    title: LocalizedString.l(language, en: "Total", zh: "总数", ja: "合計", ko: "총계"),
                    value: "\(store.summary.totalCount)",
                    detail: ""
                )
                WeeklyStatPill(
                    title: LocalizedString.gold("pending", lang: language),
                    value: "\(store.summary.pendingCount)",
                    detail: ""
                )
                WeeklyStatPill(
                    title: LocalizedString.gold("validated", lang: language),
                    value: "\(store.summary.validatedCount)",
                    detail: ""
                )
                WeeklyStatPill(
                    title: LocalizedString.l(language, en: "Expired", zh: "过期", ja: "期限切れ", ko: "만료"),
                    value: "\(store.summary.expiredCount)",
                    detail: ""
                )
            }

            HStack(spacing: 8) {
                WeeklyStatPill(
                    title: LocalizedString.l(language, en: "Balanced acc.", zh: "平衡准确率", ja: "バランス精度", ko: "균형 정확도"),
                    value: store.summary.balancedAccuracy?.twoDigitNumber ?? "--",
                    detail: ""
                )
                WeeklyStatPill(
                    title: LocalizedString.l(language, en: "Avg. error", zh: "平均误差", ja: "平均誤差", ko: "평균 오차"),
                    value: store.summary.averageAbsoluteReturnError?.signedPercentNumber ?? "--",
                    detail: LocalizedString.l(language, en: "7 days", zh: "7 天", ja: "7日間", ko: "7일")
                )
            }

            Text(LocalizedString.l(
                language,
                en: "Weekly forecasts are validated independently and never feed the 30-minute auto calibration.",
                zh: "一周预测独立验证，不参与 30 分钟自动校准。",
                ja: "週間予測は独立に検証され、30分自動キャリブレーションには関与しません。",
                ko: "주간 예측은 독립적으로 검증되며 30분 자동 캘리브레이션에 사용되지 않습니다."
            ))
            .font(.system(size: 10))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.15), lineWidth: 1)
        }
    }

    // MARK: - Records

    private var recordList: some View {
        VStack(spacing: 8) {
            ForEach(store.records.reversed()) { record in
                recordRow(record)
            }
        }
    }

    private func recordRow(_ record: GoldWeeklyForecastRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayFormatter.string(from: record.forecast.targetDate))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))

                Spacer(minLength: 6)

                statusBadge(record)
            }

            HStack(spacing: 8) {
                directionPair(
                    label: LocalizedString.l(language, en: "Predicted", zh: "预测", ja: "予測", ko: "예측"),
                    direction: record.forecast.direction
                )
                if let actual = record.actualDirection {
                    directionPair(
                        label: LocalizedString.l(language, en: "Actual", zh: "实际", ja: "実際", ko: "실제"),
                        direction: actual
                    )
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(LocalizedString.l(
                    language,
                    en: "Model: %@",
                    zh: "模型：%@",
                    ja: "モデル：%@",
                    ko: "모델: %@"
                ).replacingOccurrences(of: "%@", with: record.forecast.modelVersion))
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))

                Text(record.forecast.currentPriceSource)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(AppTheme.progressBg(colorScheme))
                    }

                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
    }

    private func statusBadge(_ record: GoldWeeklyForecastRecord) -> some View {
        let (text, icon, color): (String, String, Color) = {
            switch record.status {
            case .pending:
                return (
                    LocalizedString.l(language, en: "Pending", zh: "待验证", ja: "検証待ち", ko: "검증 대기"),
                    "clock", AppTheme.warning
                )
            case .validated:
                return (
                    LocalizedString.l(language, en: "Validated", zh: "已验证", ja: "検証済み", ko: "검증됨"),
                    "checkmark.circle", AppTheme.healthy
                )
            case .expired:
                return (
                    LocalizedString.l(language, en: "Expired", zh: "已过期", ja: "期限切れ", ko: "만료됨"),
                    "exclamationmark.circle", AppTheme.critical
                )
            }
        }()
        return Label(text, systemImage: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
    }

    private func directionPair(label: String, direction: GoldWeeklyForecastDirection) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(Self.directionLabel(direction, language: language))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Self.directionColor(direction))
        }
    }

    private static func directionLabel(
        _ direction: GoldWeeklyForecastDirection,
        language: AppLanguage
    ) -> String {
        switch direction {
        case .up: LocalizedString.l(language, en: "Up", zh: "上涨", ja: "上昇", ko: "상승")
        case .flat: LocalizedString.l(language, en: "Flat", zh: "持平", ja: "横ばい", ko: "보합")
        case .down: LocalizedString.l(language, en: "Down", zh: "下跌", ja: "下落", ko: "하락")
        }
    }

    private static func directionColor(_ direction: GoldWeeklyForecastDirection) -> Color {
        switch direction {
        case .up: AppTheme.healthy
        case .flat: Color(red: 0.88, green: 0.57, blue: 0.16)
        case .down: AppTheme.critical
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 24))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(LocalizedString.l(
                language,
                en: "No weekly forecasts yet",
                zh: "暂无一周预测记录",
                ja: "週間予測の記録はまだありません",
                ko: "주간 예측 기록이 아직 없습니다"
            ))
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(LocalizedString.l(
                language,
                en: "Forecasts are recorded once the walk-forward backtest passes the release gate.",
                zh: "走步回测通过发布门槛后才会记录预测。",
                ja: "ウォークフォワード検証が公開ゲートを通過すると予測が記録されます。",
                ko: "워크포워드 백테스트가 공개 게이트를 통과하면 예측이 기록됩니다."
            ))
            .font(.system(size: 9.5))
            .foregroundStyle(AppTheme.textSecondary(colorScheme))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

// MARK: - 私有辅助

private struct WeeklyStatPill: View {
    let title: String
    let value: String
    let detail: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension Double {
    var twoDigitNumber: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var percentNumber: String {
        formatted(.percent.precision(.fractionLength(1)))
    }

    var signedPercentNumber: String {
        formatted(.percent.sign(strategy: .always()).precision(.fractionLength(1)))
    }
}
