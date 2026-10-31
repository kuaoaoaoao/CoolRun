import Foundation
import Observation

// MARK: - 黄金交易流水

/// 单笔黄金买卖记录（grams 买入为正、卖出为负）。
struct GoldTradeRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var grams: Double
    var pricePerGram: Double
    var note: String = ""

    /// 成交金额（正=买入支出，负=卖出回款）。
    nonisolated var amount: Double { grams * pricePerGram }

    nonisolated var isBuy: Bool { grams >= 0 }
}

/// 交易流水存储：持久化到 gold_trades.json，并提供持仓汇总与 CSV 导出的纯函数。
@MainActor
@Observable
final class GoldTradeStore {
    static let shared = GoldTradeStore()

    private(set) var records: [GoldTradeRecord] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    private init() {
        fileURL = GoldDataStorage.fileURL(named: "gold_trades.json")

        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
    }

    func add(_ record: GoldTradeRecord) {
        records.append(record)
        records.sort { $0.date < $1.date }
        saveToDisk()
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        saveToDisk()
    }

    /// 归档恢复：按 id 去重合并。
    func merge(_ imported: [GoldTradeRecord]) {
        let existingIDs = Set(records.map(\.id))
        let newRecords = imported.filter { !existingIDs.contains($0.id) }
        guard !newRecords.isEmpty else { return }
        records.append(contentsOf: newRecords)
        records.sort { $0.date < $1.date }
        saveToDisk()
    }

    // MARK: - 纯函数（便于单测）

    /// 按时间顺序回放流水，计算当前持仓克数与加权平均成本。
    /// 卖出按当时均价减持（不摊薄剩余持仓成本），超卖部分按清仓处理。
    nonisolated static func holdingSummary(records: [GoldTradeRecord]) -> (grams: Double, averageCost: Double) {
        var grams = 0.0
        var totalCost = 0.0

        for record in records.sorted(by: { $0.date < $1.date }) {
            if record.grams >= 0 {
                grams += record.grams
                totalCost += record.grams * record.pricePerGram
            } else {
                let sellGrams = min(-record.grams, grams)
                guard sellGrams > 0, grams > 0 else { continue }
                let averageCost = totalCost / grams
                totalCost -= sellGrams * averageCost
                grams -= sellGrams
            }
        }

        guard grams > 0.000001 else { return (0, 0) }
        return (grams, totalCost / grams)
    }

    /// 生成 CSV 文本（表头 + 每行一笔，note 含逗号/引号时加引号转义）。
    nonisolated static func csvText(records: [GoldTradeRecord]) -> String {
        var lines = ["date,type,grams,price_per_gram,amount,note"]
        let formatter = ISO8601DateFormatter()

        for record in records.sorted(by: { $0.date < $1.date }) {
            let type = record.isBuy ? "buy" : "sell"
            let note = csvEscape(record.note)
            lines.append([
                formatter.string(from: record.date),
                type,
                String(format: "%.4f", abs(record.grams)),
                String(format: "%.2f", record.pricePerGram),
                String(format: "%.2f", abs(record.amount)),
                note
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func csvEscape(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        let sources = GoldDataStorage.readableFileURLs(named: fileURL.lastPathComponent)
        var recordsByID: [UUID: GoldTradeRecord] = [:]
        for source in sources {
            guard let data = try? Data(contentsOf: source),
                  let sourceRecords = try? decoder.decode([GoldTradeRecord].self, from: data) else { continue }
            for record in sourceRecords {
                recordsByID[record.id] = record
            }
        }
        records = recordsByID.values.sorted { $0.date < $1.date }
    }

    private func saveToDisk() {
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
