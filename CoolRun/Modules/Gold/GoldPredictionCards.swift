import SwiftUI
import AppKit

struct PredictionLearningCard: View {
    let summary: GoldPredictionLearningSummary
    let records: [GoldPredictionLearningRecord]
    @ObservedObject private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var calibration: GoldStrategyCalibration {
        summary.strategyCalibration(lang: appSettings.language)
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

            Text(summary.calibrationText(lang: appSettings.language))
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
                        Text("\(calibration.note(lang: appSettings.language)) · \(calibrationReason)")
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

