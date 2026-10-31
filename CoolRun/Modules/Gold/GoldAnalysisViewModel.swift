import Observation
import SwiftUI
import AppKit

// MARK: - 布局常量

enum GoldLayout {
    static let contentInset: CGFloat = 12
    static let sectionSpacing: CGFloat = 10
    static let cardPadding: CGFloat = 12
    static let cardRadius: CGFloat = 11
}

// MARK: - 面板表面修饰器

struct GoldPanelSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                AppTheme.elevatedSurface(colorScheme),
                in: RoundedRectangle(cornerRadius: GoldLayout.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: GoldLayout.cardRadius, style: .continuous)
                    .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
            }
    }
}

extension View {
    func goldPanelSurface() -> some View {
        modifier(GoldPanelSurface())
    }
}

// MARK: - 分析结果

struct GoldAnalysisResult: Sendable {
    let displayRecords: [GoldPriceRecord]
    let statistics: PriceStatistics?
    let snapshot: TechnicalSnapshot?
    let signal: TradingSignal?
    let advancedReport: GoldAdvancedStrategyReport?
    let candles: [GoldCandlestick]
}

// MARK: - 分析视图模型

@MainActor
@Observable
final class GoldAnalysisViewModel {
    private(set) var displayRecords: [GoldPriceRecord] = []
    private(set) var statistics: PriceStatistics?
    private(set) var snapshot: TechnicalSnapshot?
    private(set) var signal: TradingSignal?
    private(set) var advancedReport: GoldAdvancedStrategyReport?
    private(set) var marketContext: GoldMarketContext?
    private(set) var candles: [GoldCandlestick] = []
    private(set) var isLoading = false
    // 官方走势与多平台金价
    private(set) var remoteChartPoints: [GoldPriceRecord] = []
    private(set) var remoteChartRange: GoldChartRange?
    private(set) var isRemoteChartLoading = false
    private(set) var multiSourcePrices: [GoldMultiSourcePrice] = []
    // 统一宏观情报：单一快照写入 marketIntelligence / marketContext / globalSnapshot
    private(set) var globalSnapshot: GoldGlobalSnapshot?
    private(set) var marketIntelligence: GoldMarketIntelligenceSnapshot?
    private(set) var isMarketIntelligenceLoading = false
    // 一周方向预测：独立于 30 分钟预测学习和交易策略
    private(set) var weeklyForecastSnapshot: GoldWeeklyForecastSnapshot?
    private(set) var isWeeklyForecastLoading = false

    /// 事件影响解释，只用于展示，不参与策略加权
    var eventImpact: GoldEventImpact? {
        marketIntelligence?.eventImpact
    }

    private let marketIntelligenceService: any GoldMarketIntelligenceProviding
    private let weeklyForecastService: any GoldWeeklyForecastProviding
    private let weeklyForecastStore: GoldWeeklyForecastStore
    private let marketDataService = GoldMarketDataService.shared
    private let learningStore = GoldPredictionLearningStore.shared
    private var analysisTask: Task<Void, Never>?
    private var remoteChartTask: Task<Void, Never>?
    private var multiSourceTask: Task<Void, Never>?
    private var marketIntelligenceTask: Task<Void, Never>?
    private var weeklyForecastTask: Task<Void, Never>?
    private var lastRecordsSignature = ""

    /// 默认参数在非隔离上下文求值，无法直接写 `GoldMarketIntelligenceService()` 这类
    /// 主线程隔离的初始化表达式，因此改为可选参数、在 init 内部（已隔离）再兜底。
    init(
        marketIntelligenceService: (any GoldMarketIntelligenceProviding)? = nil,
        weeklyForecastService: (any GoldWeeklyForecastProviding)? = nil,
        weeklyForecastStore: GoldWeeklyForecastStore? = nil
    ) {
        self.marketIntelligenceService = marketIntelligenceService ?? GoldMarketIntelligenceService()
        self.weeklyForecastService = weeklyForecastService ?? GoldWeeklyForecastService()
        self.weeklyForecastStore = weeklyForecastStore ?? .shared
    }

    func refresh(records: [GoldPriceRecord], candlePeriod: CandlePeriod) {
        let contextSnapshot = marketContext
        // 关闭自动校准时只观察历史表现，策略按中性参数运行
        let autoCalibrationEnabled = AppSettings.shared.goldAutoCalibrationEnabled
        let calibration = autoCalibrationEnabled
            ? learningStore.summary.strategyCalibration
            : .neutral
        let signature = makeSignature(
            records: records,
            candlePeriod: candlePeriod,
            marketContext: contextSnapshot,
            calibration: calibration
        ) + "-cal:\(autoCalibrationEnabled)"
        guard signature != lastRecordsSignature else { return }

        lastRecordsSignature = signature
        analysisTask?.cancel()

        if statistics == nil {
            isLoading = true
        }

        let recordsSnapshot = Array(records)
        analysisTask = Task(priority: .userInitiated) { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.makeResult(
                    records: recordsSnapshot,
                    candlePeriod: candlePeriod,
                    marketContext: contextSnapshot,
                    calibration: calibration
                )
            }.value

            guard !Task.isCancelled else { return }
            self?.apply(result, sourceRecords: recordsSnapshot)
        }
    }

    /// 统一宏观刷新：一次请求写入 marketIntelligence / marketContext / globalSnapshot，
    /// eventImpact 只作为解释展示，不改变策略输入。
    func refreshMarketIntelligence(records: [GoldPriceRecord], candlePeriod: CandlePeriod) {
        marketIntelligenceTask?.cancel()
        isMarketIntelligenceLoading = true

        let service = marketIntelligenceService
        // 在 MainActor 捕获语言后再传入异步服务
        let language = AppSettings.shared.language
        marketIntelligenceTask = Task { [weak self] in
            let snapshot = await service.fetchSnapshot(now: Date(), language: language)
            guard !Task.isCancelled else { return }

            self?.marketIntelligence = snapshot
            self?.marketContext = snapshot.context
            self?.globalSnapshot = snapshot.globalSnapshot
            self?.isMarketIntelligenceLoading = false
            self?.lastRecordsSignature = ""
            self?.refresh(records: records, candlePeriod: candlePeriod)
            self?.refreshWeeklyForecast(records: records, eventImpact: snapshot.eventImpact)
        }
    }

    // 拉取官方走势（今日分时/历史日线），失败时保持本地数据回落
    func refreshRemoteChart(range: GoldChartRange) {
        remoteChartTask?.cancel()
        if remoteChartRange != range {
            isRemoteChartLoading = true
        }

        let service = marketDataService
        remoteChartTask = Task { [weak self] in
            // 无论成功/失败/提前 return，只要任务未被取消（新任务接管）就复位 loading
            defer {
                if !Task.isCancelled {
                    self?.isRemoteChartLoading = false
                }
            }
            do {
                let points: [GoldRemotePricePoint]
                if let historyRange = range.historyRange {
                    points = try await service.fetchHistoryPrices(range: historyRange)
                } else {
                    points = try await service.fetchTodayPrices()
                    // 官方分时回填本地库，填补 App 未运行时段的断档
                    GoldPriceStore.shared.mergeOfficialPrices(points)
                }
                guard !Task.isCancelled else { return }
                self?.remoteChartPoints = points.map {
                    GoldPriceRecord(price: $0.price, timestamp: $0.timestamp, source: "JD-official")
                }
                self?.remoteChartRange = range
            } catch {
                guard !Task.isCancelled else { return }
                if self?.remoteChartRange != range {
                    self?.remoteChartPoints = []
                    self?.remoteChartRange = nil
                }
            }
        }
    }

    // 多平台金价对比（个人站接口，失败时静默隐藏卡片）
    func refreshMultiSourcePrices() {
        multiSourceTask?.cancel()
        let service = marketDataService
        multiSourceTask = Task { [weak self] in
            let prices = (try? await service.fetchMultiSourcePrices()) ?? []
            guard !Task.isCancelled else { return }
            self?.multiSourcePrices = prices
        }
    }

    /// 一周方向预测刷新链路：
    /// 1. 先用本地记录做第 7 天验证；
    /// 2. 当天已有正式记录（Store 每日冻结）时直接还原，不发请求；
    /// 3. 否则取消旧任务并调用 service，ready 后写入 Store；
    /// 迟到的取消任务结果不得覆盖快照。
    func refreshWeeklyForecast(records: [GoldPriceRecord], eventImpact: GoldEventImpact?) {
        let language = AppSettings.shared.language
        let now = Date()

        // 本地价格记录到达后顺手验证待验证记录
        weeklyForecastStore.validate(with: records, now: now)

        // 当天已有同模型版本正式记录：冻结展示，不再请求
        if let frozen = weeklyForecastStore.record(
            forShanghaiDay: now,
            modelVersion: GoldWeeklyForecastPolicy.modelVersion
        ) {
            weeklyForecastTask?.cancel()
            weeklyForecastTask = nil
            weeklyForecastSnapshot = frozen.frozenSnapshot(
                message: LocalizedString.l(
                    language,
                    en: "Today's forecast was frozen at first publication",
                    zh: "今日预测已按当日首次发布冻结",
                    ja: "本日の予測は初回公開時点で固定されています",
                    ko: "오늘의 예측은 첫 게시 시점에 고정되었습니다"
                )
            )
            isWeeklyForecastLoading = false
            return
        }

        // 最后有效价格 + 来源作为当前价输入
        guard let lastRecord = records.last(where: { $0.price.isFinite && $0.price > 0 }) else {
            weeklyForecastTask?.cancel()
            weeklyForecastTask = nil
            weeklyForecastSnapshot = .unavailable(
                status: .sourceUnavailable,
                message: LocalizedString.l(
                    language,
                    en: "Current gold price is unavailable",
                    zh: "当前金价不可用",
                    ja: "現在の金価格を利用できません",
                    ko: "현재 금 가격을 사용할 수 없습니다"
                ),
                now: now
            )
            isWeeklyForecastLoading = false
            return
        }

        weeklyForecastTask?.cancel()
        isWeeklyForecastLoading = true

        let service = weeklyForecastService
        let request = GoldWeeklyForecastRequest(
            currentPrice: lastRecord.price,
            currentPriceSource: lastRecord.source,
            eventImpact: eventImpact,
            now: now
        )
        weeklyForecastTask = Task { [weak self] in
            let snapshot = await service.fetchSnapshot(request: request, language: language)
            guard !Task.isCancelled else { return }

            self?.weeklyForecastSnapshot = snapshot
            if snapshot.status == .ready {
                self?.weeklyForecastStore.observe(snapshot: snapshot)
            }
            self?.isWeeklyForecastLoading = false
        }
    }

    func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
        remoteChartTask?.cancel()
        remoteChartTask = nil
        multiSourceTask?.cancel()
        multiSourceTask = nil
        marketIntelligenceTask?.cancel()
        marketIntelligenceTask = nil
        weeklyForecastTask?.cancel()
        weeklyForecastTask = nil
        lastRecordsSignature = ""
        isLoading = false
        isMarketIntelligenceLoading = false
        isRemoteChartLoading = false
        isWeeklyForecastLoading = false
    }

    private func apply(_ result: GoldAnalysisResult, sourceRecords: [GoldPriceRecord]) {
        displayRecords = result.displayRecords
        statistics = result.statistics
        snapshot = result.snapshot
        signal = result.signal
        advancedReport = result.advancedReport
        candles = result.candles
        isLoading = false

        learningStore.observe(
            report: result.advancedReport,
            currentPrice: result.statistics?.currentPrice,
            timestamp: result.statistics?.lastUpdateDate,
            priceRecords: sourceRecords
        )
    }

    private func makeSignature(
        records: [GoldPriceRecord],
        candlePeriod: CandlePeriod,
        marketContext: GoldMarketContext?,
        calibration: GoldStrategyCalibration
    ) -> String {
        guard let last = records.last else {
            return "empty-\(candlePeriod.rawValue)-\(marketContext?.updatedAt.timeIntervalSince1970 ?? 0)-\(calibration.confidenceMultiplier)-\(calibration.exposureMultiplier)"
        }
        return "\(records.count)-\(last.timestamp.timeIntervalSince1970)-\(last.price)-\(candlePeriod.rawValue)-\(marketContext?.updatedAt.timeIntervalSince1970 ?? 0)-\(marketContext?.overallScore ?? 0)-\(calibration.confidenceMultiplier)-\(calibration.exposureMultiplier)"
    }

    private nonisolated static func makeResult(
        records: [GoldPriceRecord],
        candlePeriod: CandlePeriod,
        marketContext: GoldMarketContext?,
        calibration: GoldStrategyCalibration
    ) -> GoldAnalysisResult {
        let displayRecords = makeDisplayRecords(records: records)
        let statistics = GoldAnalysisEngine.makeStatistics(records: displayRecords)
        let snapshot = GoldAnalysisEngine.makeSnapshot(records: displayRecords)
        let signal: TradingSignal?

        if let snapshot, let currentPrice = displayRecords.last?.price {
            signal = TradingSignalEngine.generateSignal(
                prices: displayRecords.map(\.price),
                currentPrice: currentPrice,
                snapshot: snapshot
            )
        } else {
            signal = nil
        }

        let advancedReport: GoldAdvancedStrategyReport?
        if let snapshot {
            advancedReport = GoldAdvancedStrategy.analyze(
                records: displayRecords,
                snapshot: snapshot,
                signal: signal,
                marketContext: marketContext,
                calibration: calibration
            )
        } else {
            advancedReport = nil
        }

        return GoldAnalysisResult(
            displayRecords: displayRecords,
            statistics: statistics,
            snapshot: snapshot,
            signal: signal,
            advancedReport: advancedReport,
            candles: buildCandlesticks(records: records, period: candlePeriod)
        )
    }

    private nonisolated static func makeDisplayRecords(records: [GoldPriceRecord]) -> [GoldPriceRecord] {
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let recent = records.filter { $0.timestamp >= dayAgo }
        let source = recent.count >= 2 ? recent : records
        return Array(source.suffix(2_000))
    }

    private nonisolated static func buildCandlesticks(
        records: [GoldPriceRecord],
        period: CandlePeriod
    ) -> [GoldCandlestick] {
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let sourceRecords = records
            .filter { $0.timestamp >= dayAgo }
            .suffix(5_000)
        guard !sourceRecords.isEmpty else { return [] }

        let calendar = Calendar(identifier: .gregorian)
        let interval = period.intervalSeconds
        var buckets: [TimeInterval: (first: GoldPriceRecord, last: GoldPriceRecord, high: Double, low: Double, count: Int)] = [:]

        for record in sourceRecords {
            let seconds = record.timestamp.timeIntervalSince1970
            let bucketStart = floor(seconds / interval) * interval

            if var bucket = buckets[bucketStart] {
                if record.timestamp < bucket.first.timestamp {
                    bucket.first = record
                }
                if record.timestamp > bucket.last.timestamp {
                    bucket.last = record
                }
                bucket.high = max(bucket.high, record.price)
                bucket.low = min(bucket.low, record.price)
                bucket.count += 1
                buckets[bucketStart] = bucket
            } else {
                buckets[bucketStart] = (
                    first: record,
                    last: record,
                    high: record.price,
                    low: record.price,
                    count: 1
                )
            }
        }

        return buckets.keys.sorted().compactMap { start in
            guard let bucket = buckets[start] else { return nil }
            let startDate = Date(timeIntervalSince1970: start)
            let endDate = calendar.date(byAdding: .second, value: Int(interval), to: startDate) ?? bucket.last.timestamp

            return GoldCandlestick(
                open: bucket.first.price,
                close: bucket.last.price,
                high: bucket.high,
                low: bucket.low,
                volume: bucket.count,
                startDate: startDate,
                endDate: endDate,
                period: period
            )
        }
    }
}
