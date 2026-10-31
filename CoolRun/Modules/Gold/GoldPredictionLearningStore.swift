import Foundation
import Observation

struct GoldPredictionLearningRecord: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case validated
    }

    let id: UUID
    let createdAt: Date
    let horizonSeconds: TimeInterval
    let startPrice: Double
    let predictedDirection: String
    let predictedReturn: Double
    let confidence: Double
    let suggestedExposure: Double
    let technicalOpportunity: Double
    let marketContextScore: Double?
    let macroScore: Double?
    let newsScore: Double?
    let strategyVersion: String
    let regime: String
    let sourceSummary: String
    var status: Status
    var resolvedAt: Date?
    var endPrice: Double?
    var actualReturn: Double?
    var wasDirectionalHit: Bool?
    var absoluteError: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case horizonSeconds
        case startPrice
        case predictedDirection
        case predictedReturn
        case confidence
        case suggestedExposure
        case technicalOpportunity
        case marketContextScore
        case macroScore
        case newsScore
        case strategyVersion
        case regime
        case sourceSummary
        case status
        case resolvedAt
        case endPrice
        case actualReturn
        case wasDirectionalHit
        case absoluteError
    }

    nonisolated init(
        id: UUID = UUID(),
        createdAt: Date,
        horizonSeconds: TimeInterval,
        startPrice: Double,
        predictedDirection: String,
        predictedReturn: Double,
        confidence: Double,
        suggestedExposure: Double,
        technicalOpportunity: Double,
        marketContextScore: Double?,
        macroScore: Double?,
        newsScore: Double?,
        strategyVersion: String = GoldStrategyVersion.current,
        regime: String,
        sourceSummary: String,
        status: Status = .pending,
        resolvedAt: Date? = nil,
        endPrice: Double? = nil,
        actualReturn: Double? = nil,
        wasDirectionalHit: Bool? = nil,
        absoluteError: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.horizonSeconds = horizonSeconds
        self.startPrice = startPrice
        self.predictedDirection = predictedDirection
        self.predictedReturn = predictedReturn
        self.confidence = confidence
        self.suggestedExposure = suggestedExposure
        self.technicalOpportunity = technicalOpportunity
        self.marketContextScore = marketContextScore
        self.macroScore = macroScore
        self.newsScore = newsScore
        self.strategyVersion = strategyVersion
        self.regime = regime
        self.sourceSummary = sourceSummary
        self.status = status
        self.resolvedAt = resolvedAt
        self.endPrice = endPrice
        self.actualReturn = actualReturn
        self.wasDirectionalHit = wasDirectionalHit
        self.absoluteError = absoluteError
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        horizonSeconds = try container.decode(TimeInterval.self, forKey: .horizonSeconds)
        startPrice = try container.decode(Double.self, forKey: .startPrice)
        predictedDirection = try container.decode(String.self, forKey: .predictedDirection)
        predictedReturn = try container.decode(Double.self, forKey: .predictedReturn)
        confidence = try container.decode(Double.self, forKey: .confidence)
        suggestedExposure = try container.decode(Double.self, forKey: .suggestedExposure)
        technicalOpportunity = try container.decode(Double.self, forKey: .technicalOpportunity)
        marketContextScore = try container.decodeIfPresent(Double.self, forKey: .marketContextScore)
        macroScore = try container.decodeIfPresent(Double.self, forKey: .macroScore)
        newsScore = try container.decodeIfPresent(Double.self, forKey: .newsScore)
        strategyVersion = try container.decodeIfPresent(String.self, forKey: .strategyVersion) ?? "legacy"
        regime = try container.decode(String.self, forKey: .regime)
        sourceSummary = try container.decode(String.self, forKey: .sourceSummary)
        status = try container.decode(Status.self, forKey: .status)
        resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        endPrice = try container.decodeIfPresent(Double.self, forKey: .endPrice)
        actualReturn = try container.decodeIfPresent(Double.self, forKey: .actualReturn)
        wasDirectionalHit = try container.decodeIfPresent(Bool.self, forKey: .wasDirectionalHit)
        absoluteError = try container.decodeIfPresent(Double.self, forKey: .absoluteError)
    }
}

struct GoldPredictionLearningSummary: Equatable, Sendable {
    let totalCount: Int
    let pendingCount: Int
    let validatedCount: Int
    let hitRate: Double?
    let averageAbsoluteError: Double?
    let averagePredictionBias: Double?
    let latestValidatedAt: Date?

    var calibrationText: String {
        guard validatedCount >= 8, let hitRate else {
            return "样本积累中，先记录不自动调参"
        }

        if hitRate >= 0.62 {
            return "近期方向命中率较好，可继续观察"
        }

        if hitRate <= 0.42 {
            return "近期方向偏差较大，后续应降低信心权重"
        }

        if let averagePredictionBias {
            if averagePredictionBias > 0.002 {
                return "预测略偏乐观，买入建议需更保守"
            }
            if averagePredictionBias < -0.002 {
                return "预测略偏保守，可观察是否漏掉上行"
            }
        }

        return "预测表现接近中性，继续积累样本"
    }

    var strategyCalibration: GoldStrategyCalibration {
        guard validatedCount >= 8, let hitRate else {
            return .neutral
        }

        if hitRate <= 0.42 {
            return GoldStrategyCalibration(
                confidenceMultiplier: 0.82,
                exposureMultiplier: 0.72,
                note: "近期方向命中率偏低，已自动降低信心和仓位"
            )
        }

        if let averagePredictionBias, averagePredictionBias > 0.002 {
            return GoldStrategyCalibration(
                confidenceMultiplier: 0.90,
                exposureMultiplier: 0.82,
                note: "近期预测偏乐观，买入建议已自动保守"
            )
        }

        if hitRate >= 0.62, abs(averagePredictionBias ?? 0) <= 0.002 {
            return GoldStrategyCalibration(
                confidenceMultiplier: 1.05,
                exposureMultiplier: 1.03,
                note: "近期方向命中率较好，维持略积极校准"
            )
        }

        return GoldStrategyCalibration(
            confidenceMultiplier: 1,
            exposureMultiplier: 0.94,
            note: "近期表现中性，仓位略保守"
        )
    }
}

enum GoldPredictionLearningEngine {
    nonisolated static let defaultHorizonSeconds: TimeInterval = 30 * 60
    nonisolated static let directionTolerance: Double = 0.0005

    nonisolated static func makeRecord(
        report: GoldAdvancedStrategyReport,
        currentPrice: Double,
        createdAt: Date
    ) -> GoldPredictionLearningRecord? {
        guard currentPrice > 0 else { return nil }

        if case .hold = report.compositeDirection {
            return nil
        }

        let predictedReturn = report.forecast?.expectedReturn ?? fallbackPredictedReturn(
            direction: report.compositeDirection,
            confidence: report.confidence
        )

        return GoldPredictionLearningRecord(
            createdAt: createdAt,
            horizonSeconds: defaultHorizonSeconds,
            startPrice: currentPrice,
            predictedDirection: directionKey(report.compositeDirection),
            predictedReturn: predictedReturn,
            confidence: report.confidence,
            suggestedExposure: report.risk.suggestedExposure,
            technicalOpportunity: report.technicalOpportunity,
            marketContextScore: report.marketContext?.overallScore,
            macroScore: report.marketContext?.macroScore,
            newsScore: report.marketContext?.newsScore,
            strategyVersion: report.strategyVersion,
            regime: report.regime.regime.rawValue,
            sourceSummary: report.summary
        )
    }

    nonisolated static func validate(
        records: [GoldPriceRecord],
        prediction: GoldPredictionLearningRecord
    ) -> GoldPredictionLearningRecord {
        guard prediction.status == .pending else { return prediction }
        let targetDate = prediction.createdAt.addingTimeInterval(prediction.horizonSeconds)
        guard let outcome = records.first(where: { $0.timestamp >= targetDate }) else {
            return prediction
        }

        let actualReturn = (outcome.price - prediction.startPrice) / prediction.startPrice
        var validated = prediction
        validated.status = .validated
        validated.resolvedAt = outcome.timestamp
        validated.endPrice = outcome.price
        validated.actualReturn = actualReturn
        validated.wasDirectionalHit = isDirectionalHit(
            predictedDirection: prediction.predictedDirection,
            actualReturn: actualReturn
        )
        validated.absoluteError = abs(prediction.predictedReturn - actualReturn)
        return validated
    }

    nonisolated static func makeSummary(records: [GoldPredictionLearningRecord]) -> GoldPredictionLearningSummary {
        let validated = records.filter { $0.status == .validated }
        let pendingCount = records.count - validated.count
        let hitValues = validated.compactMap(\.wasDirectionalHit)
        let errorValues = validated.compactMap(\.absoluteError)
        let biasValues = validated.compactMap { record -> Double? in
            guard let actualReturn = record.actualReturn else { return nil }
            return record.predictedReturn - actualReturn
        }

        return GoldPredictionLearningSummary(
            totalCount: records.count,
            pendingCount: pendingCount,
            validatedCount: validated.count,
            hitRate: hitValues.isEmpty ? nil : Double(hitValues.filter { $0 }.count) / Double(hitValues.count),
            averageAbsoluteError: errorValues.isEmpty ? nil : errorValues.reduce(0, +) / Double(errorValues.count),
            averagePredictionBias: biasValues.isEmpty ? nil : biasValues.reduce(0, +) / Double(biasValues.count),
            latestValidatedAt: validated.compactMap(\.resolvedAt).max()
        )
    }

    private nonisolated static func fallbackPredictedReturn(direction: SignalDirection, confidence: Double) -> Double {
        let magnitude = min(max(confidence, 0.12), 0.75) * 0.004
        switch direction {
        case .buy: return magnitude
        case .sell: return -magnitude
        case .hold: return 0
        }
    }

    private nonisolated static func directionKey(_ direction: SignalDirection) -> String {
        switch direction {
        case .buy: "buy"
        case .sell: "sell"
        case .hold: "hold"
        }
    }

    private nonisolated static func isDirectionalHit(predictedDirection: String, actualReturn: Double) -> Bool {
        switch predictedDirection {
        case "buy":
            return actualReturn > directionTolerance
        case "sell":
            return actualReturn < -directionTolerance
        default:
            return abs(actualReturn) <= directionTolerance
        }
    }
}

@MainActor
@Observable
final class GoldPredictionLearningStore {
    static let shared = GoldPredictionLearningStore()

    // 所有预测记录（公开只读，用于复盘页展示）
    private(set) var allRecords: [GoldPredictionLearningRecord] = []
    // 当前筛选后的记录
    private(set) var filteredRecords: [GoldPredictionLearningRecord] = []
    // 筛选条件
    var filterStrategyVersion: String? = nil {
        didSet { applyFilter() }
    }
    var filterRegime: String? = nil {
        didSet { applyFilter() }
    }
    var filterDirection: String? = nil {
        didSet { applyFilter() }
    }
    var filterStatus: GoldPredictionLearningRecord.Status? = nil {
        didSet { applyFilter() }
    }
    // 统计摘要（基于筛选后的记录）
    private(set) var summary = GoldPredictionLearningEngine.makeSummary(records: [])
    // 按策略版本分组统计
    private(set) var summaryByStrategyVersion: [String: GoldPredictionLearningSummary] = [:]
    // 按市场状态分组统计
    private(set) var summaryByRegime: [String: GoldPredictionLearningSummary] = [:]
    // 按预测方向分组统计
    private(set) var summaryByDirection: [String: GoldPredictionLearningSummary] = [:]

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private let maxRecords = 5_000
    @ObservationIgnored private let minimumRecordInterval: TimeInterval = 10 * 60

    private init() {
        fileURL = GoldDataStorage.fileURL(named: "gold_prediction_learning.json")

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
        applyFilter()
    }

    func observe(report: GoldAdvancedStrategyReport?, currentPrice: Double?, timestamp: Date?, priceRecords: [GoldPriceRecord]) {
        validate(with: priceRecords)

        guard let report,
              let currentPrice,
              let timestamp,
              shouldRecord(report: report, currentPrice: currentPrice, timestamp: timestamp),
              let record = GoldPredictionLearningEngine.makeRecord(
                  report: report,
                  currentPrice: currentPrice,
                  createdAt: timestamp
              ) else {
            return
        }

        allRecords.append(record)
        if allRecords.count > maxRecords {
            allRecords.removeFirst(allRecords.count - maxRecords)
        }

        applyFilter()
        saveToDisk()
    }

    private func shouldRecord(
        report: GoldAdvancedStrategyReport,
        currentPrice: Double,
        timestamp: Date
    ) -> Bool {
        guard let latest = allRecords.last else { return true }
        guard timestamp.timeIntervalSince(latest.createdAt) >= minimumRecordInterval else { return false }

        return latest.strategyVersion != report.strategyVersion
            || latest.regime != report.regime.regime.rawValue
            || abs(latest.startPrice - currentPrice) >= 0.01
    }

    func validate(with priceRecords: [GoldPriceRecord]) {
        guard !priceRecords.isEmpty, records.contains(where: { $0.status == .pending }) else { return }

        let sortedRecords = priceRecords.sorted { $0.timestamp < $1.timestamp }
        var changed = false
        allRecords = allRecords.map { record in
            let validated = GoldPredictionLearningEngine.validate(records: sortedRecords, prediction: record)
            if validated != record { changed = true }
            return validated
        }

        guard changed else { return }
        applyFilter()
        saveToDisk()
    }

    // MARK: - Filtering

    private func applyFilter() {
        filteredRecords = allRecords.filter { record in
            if let version = filterStrategyVersion, record.strategyVersion != version {
                return false
            }
            if let regime = filterRegime, record.regime != regime {
                return false
            }
            if let direction = filterDirection, record.predictedDirection != direction {
                return false
            }
            if let status = filterStatus, record.status != status {
                return false
            }
            return true
        }
        refreshSummaries()
    }

    private func refreshSummaries() {
        summary = GoldPredictionLearningEngine.makeSummary(records: filteredRecords)
        summaryByStrategyVersion = groupSummaries(by: \.strategyVersion, from: allRecords)
        summaryByRegime = groupSummaries(by: \.regime, from: allRecords)
        summaryByDirection = groupSummaries(by: \.predictedDirection, from: allRecords)
    }

    private func groupSummaries<Key: Hashable>(
        by keyPath: KeyPath<GoldPredictionLearningRecord, Key>,
        from records: [GoldPredictionLearningRecord]
    ) -> [Key: GoldPredictionLearningSummary] {
        let grouped = Dictionary(grouping: records) { $0[keyPath: keyPath] }
        return Dictionary(uniqueKeysWithValues: grouped.map { key, records in
            (key, GoldPredictionLearningEngine.makeSummary(records: records))
        })
    }

    // MARK: - Public Access

    var records: [GoldPredictionLearningRecord] {
        get { filteredRecords }
        set {
            allRecords = newValue
            applyFilter()
        }
    }

    func clearFilter() {
        filterStrategyVersion = nil
        filterRegime = nil
        filterDirection = nil
        filterStatus = nil
    }

    // Available filter options（每次访问实时计算，避免新记录进入后选项不刷新）
    static var availableStrategyVersions: [String] {
        Set(GoldPredictionLearningStore.shared.allRecords.map(\.strategyVersion)).sorted()
    }

    static var availableRegimes: [String] {
        Set(GoldPredictionLearningStore.shared.allRecords.map(\.regime)).sorted()
    }

    static let availableDirections: [String] = ["buy", "sell"]

    // MARK: - Disk Persistence

    func refreshSummary() {
        summary = GoldPredictionLearningEngine.makeSummary(records: records)
    }

    private func loadFromDisk() {
        let sources = GoldDataStorage.readableFileURLs(named: fileURL.lastPathComponent)
        var recordsByID: [UUID: GoldPredictionLearningRecord] = [:]
        for source in sources {
            guard let data = try? Data(contentsOf: source),
                  let sourceRecords = try? decoder.decode([GoldPredictionLearningRecord].self, from: data) else { continue }
            for record in sourceRecords {
                recordsByID[record.id] = record
            }
        }

        allRecords = recordsByID.values.sorted { $0.createdAt < $1.createdAt }
        if allRecords.count > maxRecords {
            allRecords.removeFirst(allRecords.count - maxRecords)
        }
        if !allRecords.isEmpty, sources.contains(where: { $0.standardizedFileURL != fileURL.standardizedFileURL }) {
            saveToDisk()
        }
    }

    func saveToDisk() {
        guard let data = try? encoder.encode(allRecords) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
