import Foundation

// MARK: - 观察值（internal，仅供回测与测试）

/// 单个 anchor 的走步样本；不是 UI 或持久化模型。
struct GoldWeeklyForecastBacktestObservation: Sendable, Equatable {
    let anchorDate: Date
    let inputLastDate: Date
    let predicted: GoldWeeklyForecastDirection
    let actual: GoldWeeklyForecastDirection
    let predictedReturn: Double
    let actualReturn: Double
}

struct GoldWeeklyForecastBacktestTrace: Sendable, Equatable {
    let anchorDate: Date
    let inputLastDate: Date
}

// MARK: - 回测器

/// 无泄漏走步回测：每个 anchor 只使用当日及以前的数据，真实标签取 anchor + 7 天后的
/// 第一笔有效价格（宽限 3 天）。anchor 之间至少间隔 7 个自然日。
enum GoldWeeklyForecastBacktester {
    nonisolated static func evaluate(
        closes: [GoldDailyClose],
        seed: UInt64
    ) -> GoldWeeklyForecastBacktestSummary {
        makeSummary(observations: observations(closes: closes, seed: seed))
    }

    /// 仅为 internal 测试接口：暴露每个 anchor 的输入边界，验证无未来数据泄漏。
    nonisolated static func debugTrace(closes: [GoldDailyClose], seed: UInt64) -> [GoldWeeklyForecastBacktestTrace] {
        observations(closes: closes, seed: seed).map {
            GoldWeeklyForecastBacktestTrace(anchorDate: $0.anchorDate, inputLastDate: $0.inputLastDate)
        }
    }

    // MARK: - 走步样本生成

    nonisolated private static func observations(
        closes: [GoldDailyClose],
        seed: UInt64
    ) -> [GoldWeeklyForecastBacktestObservation] {
        let shanghaiCalendar = Calendar.goldShanghai
        var results: [GoldWeeklyForecastBacktestObservation] = []
        guard closes.count > GoldWeeklyForecastPolicy.minimumDailyCloses else { return results }

        // 第一个 anchor 必须已经拥有 120 个历史收盘点。
        var anchorIndex = GoldWeeklyForecastPolicy.minimumDailyCloses - 1
        while anchorIndex < closes.count {
            let anchor = closes[anchorIndex]
            let prefix = Array(closes[...anchorIndex])
            let targetDate = shanghaiCalendar.date(byAdding: .day, value: 7, to: anchor.date)!
            let deadline = shanghaiCalendar.date(byAdding: .day, value: 3, to: targetDate)!
            guard let outcome = closes.first(where: { $0.date >= targetDate && $0.date <= deadline }) else {
                anchorIndex = nextAnchorIndex(
                    after: anchorIndex,
                    closes: closes,
                    calendar: shanghaiCalendar
                ) ?? closes.count
                continue
            }
            if let draft = GoldWeeklyForecastEngine.makeDraft(
                GoldWeeklyForecastEngineInput(
                    closes: prefix,
                    startPrice: anchor.close,
                    generatedAt: anchor.date,
                    targetDate: targetDate,
                    seed: seed ^ UInt64(max(0, Int(anchor.date.timeIntervalSince1970)))
                )
            ) {
                let actualReturn = outcome.close / anchor.close - 1
                results.append(GoldWeeklyForecastBacktestObservation(
                    anchorDate: anchor.date,
                    inputLastDate: anchor.date,
                    predicted: draft.direction,
                    actual: GoldWeeklyForecastDirection.classify(actualReturn: actualReturn),
                    predictedReturn: draft.expectedReturn,
                    actualReturn: actualReturn
                ))
            }
            anchorIndex = nextAnchorIndex(
                after: anchorIndex,
                closes: closes,
                calendar: shanghaiCalendar
            ) ?? closes.count
        }
        return results
    }

    /// 下一个 anchor：至少在当前 anchor 7 个自然日之后。
    nonisolated private static func nextAnchorIndex(
        after index: Int,
        closes: [GoldDailyClose],
        calendar: Calendar
    ) -> Int? {
        let anchorDate = closes[index].date
        let minimumNext = calendar.date(
            byAdding: .day,
            value: GoldWeeklyForecastPolicy.horizonDays,
            to: anchorDate
        )!
        guard let nextIndex = closes.firstIndex(where: { $0.date >= minimumNext }) else { return nil }
        return nextIndex > index ? nextIndex : nil
    }

    // MARK: - 指标和发布门槛

    nonisolated static func makeSummary(
        observations: [GoldWeeklyForecastBacktestObservation]
    ) -> GoldWeeklyForecastBacktestSummary {
        let resolvedCount = observations.count
        var classCounts: [GoldWeeklyForecastDirection: Int] = [:]
        var confusionMatrix: [GoldWeeklyForecastDirection: [GoldWeeklyForecastDirection: Int]] = [:]
        for direction in [GoldWeeklyForecastDirection.up, .flat, .down] {
            classCounts[direction] = 0
            confusionMatrix[direction] = [:]
        }
        for observation in observations {
            classCounts[observation.actual, default: 0] += 1
            confusionMatrix[observation.actual]![observation.predicted, default: 0] += 1
        }

        let correct = observations.filter { $0.predicted == $0.actual }.count
        let overallAccuracy = resolvedCount > 0 ? Double(correct) / Double(resolvedCount) : nil

        // 每类 recall 的平均值（只统计出现的类别）
        let recalls = [GoldWeeklyForecastDirection.up, .flat, .down].compactMap { actual -> Double? in
            let group = observations.filter { $0.actual == actual }
            guard !group.isEmpty else { return nil }
            return Double(group.filter { $0.predicted == actual }.count) / Double(group.count)
        }
        let balancedAccuracy = recalls.isEmpty ? nil : recalls.reduce(0, +) / Double(recalls.count)

        let majorityBaselineAccuracy = resolvedCount > 0
            ? Double(classCounts.values.max() ?? 0) / Double(resolvedCount)
            : nil

        let meanAbsoluteReturnError = resolvedCount > 0
            ? observations.map { abs($0.predictedReturn - $0.actualReturn) }.reduce(0, +) / Double(resolvedCount)
            : nil

        var reasons: [String] = []
        if resolvedCount < 24 { reasons.append("resolved_samples") }
        if classCounts.values.filter({ $0 >= 3 }).count < 3 { reasons.append("class_coverage") }
        if (balancedAccuracy ?? 0) < 0.38 { reasons.append("balanced_accuracy") }
        if (overallAccuracy ?? 0) < (majorityBaselineAccuracy ?? 1) { reasons.append("majority_baseline") }

        let allMetricsAreFinite: Bool
        if resolvedCount == 0 {
            allMetricsAreFinite = true
        } else {
            allMetricsAreFinite = [overallAccuracy, balancedAccuracy, majorityBaselineAccuracy, meanAbsoluteReturnError]
                .allSatisfy { $0?.isFinite == true }
        }
        if !allMetricsAreFinite { reasons.append("non_finite_metric") }

        return GoldWeeklyForecastBacktestSummary(
            resolvedCount: resolvedCount,
            classCounts: classCounts,
            overallAccuracy: overallAccuracy,
            balancedAccuracy: balancedAccuracy,
            majorityBaselineAccuracy: majorityBaselineAccuracy,
            meanAbsoluteReturnError: meanAbsoluteReturnError,
            confusionMatrix: confusionMatrix,
            passedReleaseGate: reasons.isEmpty,
            failureReasons: reasons
        )
    }
}
