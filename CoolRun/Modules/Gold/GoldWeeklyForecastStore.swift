import Foundation

// MARK: - 持久化记录

/// 一周预测正式记录：每个上海自然日 + 模型版本最多一条。
struct GoldWeeklyForecastRecord: Codable, Identifiable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case pending, validated, expired
    }

    let id: UUID
    let forecast: GoldWeeklyForecast
    let backtest: GoldWeeklyForecastBacktestSummary
    var status: Status
    var resolvedAt: Date?
    var endPrice: Double?
    var actualReturn: Double?
    var actualDirection: GoldWeeklyForecastDirection?
    var wasDirectionalHit: Bool?
    var absoluteReturnError: Double?
}

extension GoldWeeklyForecastRecord {
    /// 把持久化记录还原为 ready 快照；updatedAt 固定为生成时间，不得伪装为新预测。
    nonisolated func frozenSnapshot(message: String) -> GoldWeeklyForecastSnapshot {
        GoldWeeklyForecastSnapshot(
            status: .ready,
            forecast: forecast,
            backtest: backtest,
            message: message,
            updatedAt: forecast.generatedAt
        )
    }
}

// MARK: - 独立复盘汇总

/// 周预测汇总独立于 30 分钟自动校准，不得与 GoldPredictionLearningStore 相加。
struct GoldWeeklyForecastSummary: Sendable, Equatable {
    let totalCount: Int
    let pendingCount: Int
    let validatedCount: Int
    let expiredCount: Int
    let hitRate: Double?
    let balancedAccuracy: Double?
    let averageAbsoluteReturnError: Double?
}

// MARK: - Store

/// 每日冻结正式预测、第 7 天验证和本地持久化。
/// 不进入 GoldPredictionLearningStore.summary，避免污染 30 分钟自动校准。
@MainActor
@Observable
final class GoldWeeklyForecastStore {
    static let shared = GoldWeeklyForecastStore()

    private(set) var records: [GoldWeeklyForecastRecord]
    private(set) var summary: GoldWeeklyForecastSummary
    private let fileURL: URL
    private let calendar: Calendar

    init(fileURL: URL = GoldDataStorage.fileURL(named: "gold_weekly_forecasts.json"),
         calendar: Calendar = .goldShanghai) {
        let loaded = Self.load(from: fileURL)
        self.fileURL = fileURL
        self.calendar = calendar
        self.records = loaded
        self.summary = Self.makeSummary(records: loaded)
    }

    func record(forShanghaiDay date: Date, modelVersion: String) -> GoldWeeklyForecastRecord? {
        let key = calendar.startOfDay(for: date)
        return records.first {
            calendar.startOfDay(for: $0.forecast.generatedAt) == key &&
            $0.forecast.modelVersion == modelVersion
        }
    }

    /// 只接受 ready + forecast + passed backtest；同 day key + modelVersion 已存在时保持第一条不变。
    func observe(snapshot: GoldWeeklyForecastSnapshot) {
        guard snapshot.status == .ready,
              let forecast = snapshot.forecast,
              let backtest = snapshot.backtest,
              backtest.passedReleaseGate,
              record(forShanghaiDay: forecast.generatedAt, modelVersion: forecast.modelVersion) == nil else { return }
        records.append(GoldWeeklyForecastRecord(
            id: UUID(), forecast: forecast, backtest: backtest, status: .pending,
            resolvedAt: nil, endPrice: nil, actualReturn: nil,
            actualDirection: nil, wasDirectionalHit: nil, absoluteReturnError: nil
        ))
        summary = Self.makeSummary(records: records)
        save()
    }

    func validate(with priceRecords: [GoldPriceRecord], now: Date) {
        records = records.map { Self.validated($0, with: priceRecords, now: now, calendar: calendar) }
        summary = Self.makeSummary(records: records)
        save()
    }

    /// 按 id 去重合并；已有记录保持不变。
    func merge(_ incoming: [GoldWeeklyForecastRecord]) {
        var byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for record in incoming where byID[record.id] == nil {
            byID[record.id] = record
        }
        records = byID.values.sorted { $0.forecast.generatedAt < $1.forecast.generatedAt }
        summary = Self.makeSummary(records: records)
        save()
    }

    // MARK: - 持久化

    nonisolated private static func load(from url: URL) -> [GoldWeeklyForecastRecord] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([GoldWeeklyForecastRecord].self, from: data) else { return [] }
        return records.sorted { $0.forecast.generatedAt < $1.forecast.generatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 汇总

    nonisolated private static func makeSummary(
        records: [GoldWeeklyForecastRecord]
    ) -> GoldWeeklyForecastSummary {
        let validated = records.filter { $0.status == .validated }
        let hits = validated.compactMap(\.wasDirectionalHit)
        let recalls = [GoldWeeklyForecastDirection.up, .flat, .down].compactMap { actual -> Double? in
            let group = validated.filter { $0.actualDirection == actual }
            guard !group.isEmpty else { return nil }
            return Double(group.filter { $0.forecast.direction == actual }.count) / Double(group.count)
        }
        let errors = validated.compactMap(\.absoluteReturnError)
        return GoldWeeklyForecastSummary(
            totalCount: records.count,
            pendingCount: records.filter { $0.status == .pending }.count,
            validatedCount: validated.count,
            expiredCount: records.filter { $0.status == .expired }.count,
            hitRate: hits.isEmpty ? nil : Double(hits.filter { $0 }.count) / Double(hits.count),
            balancedAccuracy: recalls.count == 3 ? recalls.reduce(0, +) / 3 : nil,
            averageAbsoluteReturnError: errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count)
        )
    }

    // MARK: - 7 天验证（纯函数）

    /// 目标日之后 3 天宽限期内，取第一笔来源兼容的价格；
    /// JD-MS 与 JD-official 视为同一固定来源族，CZB-JCJ 只能用 CZB-JCJ 验证。
    nonisolated private static func validated(
        _ record: GoldWeeklyForecastRecord,
        with priceRecords: [GoldPriceRecord],
        now: Date,
        calendar: Calendar
    ) -> GoldWeeklyForecastRecord {
        guard record.status == .pending else { return record }
        let target = record.forecast.targetDate
        let deadline = calendar.date(byAdding: .day, value: 3, to: target)!
        let compatible = priceRecords
            .filter {
                $0.timestamp >= target && $0.timestamp <= deadline &&
                GoldForecastSourceCompatibilityResolver.canValidate(
                    forecastSource: record.forecast.currentPriceSource,
                    outcomeSource: $0.source
                )
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard let outcome = compatible.first else {
            guard now > deadline else { return record }
            var expired = record
            expired.status = .expired
            return expired
        }

        let actualReturn = outcome.price / record.forecast.startPrice - 1
        let actualDirection = GoldWeeklyForecastDirection.classify(actualReturn: actualReturn)
        var result = record
        result.status = .validated
        result.resolvedAt = outcome.timestamp
        result.endPrice = outcome.price
        result.actualReturn = actualReturn
        result.actualDirection = actualDirection
        result.wasDirectionalHit = actualDirection == record.forecast.direction
        result.absoluteReturnError = abs(record.forecast.expectedReturn - actualReturn)
        return result
    }
}
