import Foundation
import Observation

@MainActor
@Observable
final class GoldPriceStore {
    static let shared = GoldPriceStore()

    private(set) var records: [GoldPriceRecord] = []
    // 官方最新行情（含昨收/涨跌/休市，由 MacAppDelegate 刷新时写入）
    var latestQuote: GoldPriceQuote?
    // 数据健康状态
    private(set) var dataHealth: DataHealthStatus = .healthy
    private(set) var lastPriceUpdate: Date?
    private(set) var priceUpdateInterval: TimeInterval?
    // 最近一次拉取是否失败（仅内存态，供空态区分"等待首次数据"与"网络失败"）
    var lastFetchFailed = false
    // 数据异常检测参数
    private let maxPriceJumpRatio: Double = 0.05  // 单次最大允许跳价幅度（5%）
    private let staleDataThreshold: TimeInterval = 300  // 5分钟未更新视为数据陈旧
    private let minPrice: Double = 100  // 合理价格下限（元/克）
    private let maxPrice: Double = 2000  // 合理价格上限（元/克）

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private let maxRecords = 100_000
    @ObservationIgnored private let saveDebounceInterval: Duration = .seconds(8)
    @ObservationIgnored private var historyLoadTask: Task<Void, Never>?
    @ObservationIgnored private var didBackUpThisLaunch = false
    /// 历史还在后台解码时为 true，供空态区分「正在读历史」与「真的没数据」。
    private(set) var isLoadingHistory = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var hasPendingSave = false
    @ObservationIgnored private var saveGeneration = 0

    private init() {
        fileURL = GoldDataStorage.fileURL(named: "gold_price_history.json")

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        startHistoryLoad()
    }

    func addPrice(_ price: Double, timestamp: Date = Date(), source: String = "CZB-JCJ") {
        // 1. 基本有效性检查
        guard price > minPrice, price < maxPrice else {
            dataHealth = .invalidPrice(price)
            return
        }

        // 2. 检查数据新鲜度
        let now = Date()
        if let last = records.last {
            let interval = timestamp.timeIntervalSince(last.timestamp)
            if interval < 0 {
                // 时间戳倒流（时钟回拨），使用当前时间
                dataHealth = .stale(now.timeIntervalSince(last.timestamp))
                return
            }
            priceUpdateInterval = interval
            
            // 3. 检查是否重复价格（10秒内价格变化小于 0.0001）
            if abs(last.price - price) < 0.0001,
               interval < 10 {
                return
            }
            
            // 4. 检查跳价幅度（基于历史波动率动态调整）
            let jumpRatio = abs(price - last.price) / last.price
            if jumpRatio > maxPriceJumpRatio {
                dataHealth = .priceJump(jumpRatio)
                // 仍然记录，但标记为异常
            } else {
                dataHealth = .healthy
            }
        } else {
            dataHealth = .healthy
        }
        
        lastPriceUpdate = timestamp

        records.append(GoldPriceRecord(price: price, timestamp: timestamp, source: source))

        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }

        scheduleSave()
    }

    // 检查数据新鲜度（供 UI 调用）
    func checkFreshness() {
        guard let lastUpdate = lastPriceUpdate ?? records.last?.timestamp else {
            dataHealth = .stale(TimeInterval.greatestFiniteMagnitude)
            return
        }
        let age = Date().timeIntervalSince(lastUpdate)
        if age > staleDataThreshold {
            dataHealth = .stale(age)
        }
    }

    // 获取最近价格年龄（秒）
    var lastPriceAge: TimeInterval? {
        guard let lastUpdate = lastPriceUpdate ?? records.last?.timestamp else { return nil }
        return Date().timeIntervalSince(lastUpdate)
    }
    
    // 多数据源交叉校验：与各平台价格中位数对比
    func crossValidatePrice(_ price: Double, from source: String) -> DataValidationResult {
        if price < minPrice || price > maxPrice {
            return .outOfRange
        }
        return .singleSourceOnly
    }

    // 基于多平台报价校验主源价格：偏离中位数超过 1% 视为异常
    func crossValidatePrice(_ price: Double, against sources: [GoldMultiSourcePrice]) -> DataValidationResult {
        if price < minPrice || price > maxPrice {
            return .outOfRange
        }
        let prices = sources.map(\.price).sorted()
        guard !prices.isEmpty else { return .singleSourceOnly }

        let median: Double
        if prices.count % 2 == 0 {
            median = (prices[prices.count / 2 - 1] + prices[prices.count / 2]) / 2
        } else {
            median = prices[prices.count / 2]
        }
        guard median > 0 else { return .singleSourceOnly }

        if abs(price - median) / median > 0.01 {
            return .multiSourceMismatch(price, median)
        }
        return .valid
    }

    // 将官方分时点补进本地库，仅插入与现有记录时间差超过 60 秒的点，填补 App 未运行造成的断档
    func mergeOfficialPrices(_ points: [GoldRemotePricePoint], source: String = "JD-official") {
        let inserted = Self.officialRecordsToInsert(
            points: points,
            existing: records,
            source: source,
            minPrice: minPrice,
            maxPrice: maxPrice
        )
        guard !inserted.isEmpty else { return }

        records.append(contentsOf: inserted)
        records.sort { $0.timestamp < $1.timestamp }
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        scheduleSave()
    }

    // 筛选需插入的官方点：过滤无效价格，跳过与现有记录 60 秒内的重叠点（纯函数，便于测试）
    nonisolated static func officialRecordsToInsert(
        points: [GoldRemotePricePoint],
        existing: [GoldPriceRecord],
        source: String = "JD-official",
        minPrice: Double = 100,
        maxPrice: Double = 2000
    ) -> [GoldPriceRecord] {
        guard !points.isEmpty else { return [] }

        var existingSeconds = existing.map { $0.timestamp.timeIntervalSince1970 }.sorted()
        var inserted: [GoldPriceRecord] = []

        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard point.price > minPrice, point.price < maxPrice else { continue }
            let seconds = point.timestamp.timeIntervalSince1970
            // 二分查找最近的现有记录，60 秒内已有数据则跳过
            var low = 0
            var high = existingSeconds.count
            while low < high {
                let mid = (low + high) / 2
                if existingSeconds[mid] < seconds { low = mid + 1 } else { high = mid }
            }
            let nearestGap = [low - 1, low]
                .filter { $0 >= 0 && $0 < existingSeconds.count }
                .map { abs(existingSeconds[$0] - seconds) }
                .min() ?? .greatestFiniteMagnitude
            guard nearestGap > 60 else { continue }

            inserted.append(GoldPriceRecord(price: point.price, timestamp: point.timestamp, source: source))
            existingSeconds.insert(seconds, at: low)
        }

        return inserted
    }

    func recordsSince(_ date: Date) -> [GoldPriceRecord] {
        records.filter { $0.timestamp >= date }
    }

    func buildCandlesticks(period: CandlePeriod, since date: Date? = nil) -> [GoldCandlestick] {
        let sourceRecords = date.map(recordsSince) ?? records
        guard !sourceRecords.isEmpty else { return [] }

        let calendar = Calendar(identifier: .gregorian)
        let interval = period.intervalSeconds
        var buckets: [TimeInterval: [GoldPriceRecord]] = [:]

        for record in sourceRecords {
            let seconds = record.timestamp.timeIntervalSince1970
            let bucketStart = floor(seconds / interval) * interval
            buckets[bucketStart, default: []].append(record)
        }

        return buckets.keys.sorted().compactMap { start in
            guard let bucketRecords = buckets[start]?.sorted(by: { $0.timestamp < $1.timestamp }),
                  let first = bucketRecords.first,
                  let last = bucketRecords.last else {
                return nil
            }

            let prices = bucketRecords.map(\.price)
            let startDate = Date(timeIntervalSince1970: start)
            let endDate = calendar.date(byAdding: .second, value: Int(interval), to: startDate) ?? last.timestamp

            return GoldCandlestick(
                open: first.price,
                close: last.price,
                high: prices.max() ?? last.price,
                low: prices.min() ?? last.price,
                volume: bucketRecords.count,
                startDate: startDate,
                endDate: endDate,
                period: period
            )
        }
    }

    /// 历史文件实测 7.8 MB / 7 万条，在主线程解码要 115 ms —— 正好卡在
    /// 首次打开金价面板的路径上。改成后台解码，解完再回主线程合并。
    private func startHistoryLoad() {
        let sources = GoldDataStorage.readableFileURLs(named: fileURL.lastPathComponent)
        guard !sources.isEmpty else { return }

        isLoadingHistory = true
        let limit = maxRecords
        historyLoadTask = Task { [weak self] in
            let loaded = await Self.decodeHistory(from: sources, limit: limit)
            guard !Task.isCancelled, let self else { return }
            self.applyLoadedHistory(loaded, sources: sources)
        }
    }

    private nonisolated static func decodeHistory(
        from sources: [URL],
        limit: Int
    ) async -> [GoldPriceRecord] {
        await Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var recordsByID: [UUID: GoldPriceRecord] = [:]
            for source in sources {
                guard let data = try? Data(contentsOf: source),
                      let sourceRecords = try? decoder.decode([GoldPriceRecord].self, from: data)
                else { continue }
                for record in sourceRecords {
                    recordsByID[record.id] = record
                }
            }

            var merged = recordsByID.values.sorted { $0.timestamp < $1.timestamp }
            if merged.count > limit {
                merged.removeFirst(merged.count - limit)
            }
            return merged
        }.value
    }

    private func applyLoadedHistory(_ loaded: [GoldPriceRecord], sources: [URL]) {
        isLoadingHistory = false
        historyLoadTask = nil
        guard !loaded.isEmpty else { return }

        // 解码期间可能已经抓到新行情：同 id 以内存里的为准，其余照旧合并。
        var recordsByID: [UUID: GoldPriceRecord] = [:]
        for record in loaded { recordsByID[record.id] = record }
        for record in records { recordsByID[record.id] = record }

        var merged = recordsByID.values.sorted { $0.timestamp < $1.timestamp }
        if merged.count > maxRecords {
            merged.removeFirst(merged.count - maxRecords)
        }
        records = merged
        lastPriceUpdate = merged.last?.timestamp

        // 把合并结果写回当前位置，以后启动就不再依赖旧的沙箱容器。
        if sources.contains(where: { $0.standardizedFileURL != fileURL.standardizedFileURL }) {
            saveToDisk(records: records, to: fileURL)
        }

        // 解码期间攒下的待保存请求，现在数据齐了再落。
        if hasPendingSave {
            scheduleSave()
        }
    }

    func flushToDisk() {
        saveTask?.cancel()
        saveTask = nil
        guard hasPendingSave else { return }
        saveToDisk(records: records, to: fileURL)
        hasPendingSave = false
    }

    private func scheduleSave() {
        // 历史还在后台解码时内存里只有刚抓到的几条。这时候落盘会把整个
        // 历史文件覆盖成「一条」——曾经真的这么丢过一次数据。
        guard !isLoadingHistory else {
            hasPendingSave = true
            return
        }

        hasPendingSave = true
        saveGeneration += 1
        let generation = saveGeneration
        let recordsSnapshot = records
        let targetURL = fileURL

        saveTask?.cancel()
        saveTask = Task { [saveDebounceInterval] in
            try? await Task.sleep(for: saveDebounceInterval)
            guard !Task.isCancelled else { return }

            await Self.writeToDisk(records: recordsSnapshot, fileURL: targetURL)

            await MainActor.run {
                guard !Task.isCancelled, generation == self.saveGeneration else { return }
                self.hasPendingSave = false
                self.saveTask = nil
            }
        }
    }

    private func saveToDisk() {
        saveToDisk(records: records, to: fileURL)
    }

    private func saveToDisk(records: [GoldPriceRecord], to fileURL: URL) {
        guard let data = try? encoder.encode(records) else { return }
        guard !Self.wouldShrinkTooMuch(existing: fileURL, newByteCount: data.count) else {
            // 宁可这次不写，也不要把历史覆盖成残片。
            return
        }
        backUpOnceBeforeOverwriting(fileURL)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 每次启动只备份一次，避免每 8 秒复制一个几 MB 的文件。
    private func backUpOnceBeforeOverwriting(_ url: URL) {
        guard !didBackUpThisLaunch else { return }
        didBackUpThisLaunch = true
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attributes[.size] as? Int,
              bytes > 256 * 1024 else { return }
        let backup = url.deletingPathExtension().appendingPathExtension("json.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
    }

    /// 已有文件明显更大时，说明这次要写的是一份不完整的快照。
    /// 用字节数比较（不解析），成本几乎为零。
    nonisolated static func wouldShrinkTooMuch(existing url: URL, newByteCount: Int) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              size > 64 * 1024 else { return false }
        return newByteCount * 3 < size
    }

    private nonisolated static func writeToDisk(records: [GoldPriceRecord], fileURL: URL) async {
        await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(records) else { return }
            guard !Self.wouldShrinkTooMuch(existing: fileURL, newByteCount: data.count) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }.value
    }
}

// MARK: - Data Health Status

enum DataHealthStatus: Equatable {
    case healthy
    case stale(TimeInterval)  // 数据陈旧，传入距上次更新的秒数
    case priceJump(Double)    // 价格跳变幅度
    case invalidPrice(Double) // 明显错误价格

    var description: String {
        switch self {
        case .healthy:
            return LocalizedString.gold("data_healthy")
        case .stale(let age):
            return String(format: LocalizedString.gold("data_stale_format"), Int(age))
        case .priceJump(let ratio):
            return String(format: LocalizedString.gold("data_jump_format"), String(format: "%.1f%%", ratio * 100))
        case .invalidPrice(let price):
            return String(format: LocalizedString.gold("data_invalid_format"), String(format: "%.2f", price))
        }
    }

    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }
}

enum DataValidationResult {
    case valid
    case outOfRange
    case stale
    case singleSourceOnly
    case multiSourceMismatch(Double, Double)  // 不同来源价格差异过大
}
