import Foundation

// MARK: - 历史质量

/// 一年日线归并后的数据质量快照。
struct GoldDailyHistoryQuality: Sendable, Equatable {
    let closes: [GoldDailyClose]
    let rejectedCount: Int
    let maximumGapDays: Int
    let latestAge: TimeInterval?
    let isStale: Bool
}

// MARK: - 标准化

/// 上海日历归并、异常过滤和历史质量判断。
/// 五步：有效价过滤 → 同日取最后一笔 → 相邻 8% 异常剔除（异常不成为比较基准）→ 升序排序 → 质量汇总。
enum GoldDailyCloseNormalizer {
    nonisolated static func normalize(
        points: [GoldRemotePricePoint],
        now: Date,
        calendar: Calendar = .goldShanghai
    ) -> GoldDailyHistoryQuality {
        let valid = points.filter { $0.price.isFinite && (100...2_000).contains($0.price) }
        let grouped = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.timestamp) }
        let candidates = grouped.compactMap { day, values -> GoldDailyClose? in
            guard let latest = values.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return GoldDailyClose(date: day, close: latest.price)
        }.sorted { $0.date < $1.date }

        var accepted: [GoldDailyClose] = []
        var rejected = points.count - valid.count
        for candidate in candidates {
            if let previous = accepted.last,
               abs(candidate.close / previous.close - 1) > 0.08 {
                rejected += 1
                continue
            }
            accepted.append(candidate)
        }

        let gaps = zip(accepted, accepted.dropFirst()).map {
            calendar.dateComponents([.day], from: $0.0.date, to: $0.1.date).day ?? 0
        }
        let latestAge = accepted.last.map { max(0, now.timeIntervalSince($0.date)) }
        return GoldDailyHistoryQuality(
            closes: accepted,
            rejectedCount: rejected,
            maximumGapDays: gaps.max() ?? 0,
            latestAge: latestAge,
            isStale: (latestAge ?? .infinity) > GoldWeeklyForecastPolicy.maximumLatestAge
        )
    }
}
