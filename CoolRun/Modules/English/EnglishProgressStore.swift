import Combine
import Foundation

private struct EnglishProgressArchive: Codable {
    var version = 1
    var records: [String: EnglishItemProgress] = [:]
    var activityDays: Set<String> = []
    var learnedItemIDsByDay: [String: Set<String>] = [:]
}

@MainActor
final class EnglishProgressStore: ObservableObject {
    static let shared = EnglishProgressStore()

    @Published private(set) var records: [String: EnglishItemProgress]
    @Published private(set) var activityDays: Set<String>
    @Published private(set) var learnedItemIDsByDay: [String: Set<String>]

    private let persistenceURL: URL?

    convenience init() {
        self.init(persistenceURL: Self.defaultPersistenceURL)
    }

    init(persistenceURL: URL?) {
        self.persistenceURL = persistenceURL
        let archive = Self.load(from: persistenceURL) ?? EnglishProgressArchive()
        records = archive.records
        activityDays = archive.activityDays
        learnedItemIDsByDay = archive.learnedItemIDsByDay
    }

    func progress(for itemID: String) -> EnglishItemProgress {
        records[itemID] ?? EnglishItemProgress()
    }

    func recordShown(_ itemID: String, at date: Date = Date(), calendar: Calendar = .current) {
        var item = progress(for: itemID)
        item.viewCount += 1
        item.lastStudiedAt = date
        records[itemID] = item
        recordActivity(itemID: itemID, at: date, calendar: calendar)
        save()
    }

    func recordListened(_ itemID: String, at date: Date = Date(), calendar: Calendar = .current) {
        var item = progress(for: itemID)
        item.listenCount += 1
        item.lastStudiedAt = date
        if item.mastery == .new { item.mastery = .learning }
        records[itemID] = item
        recordActivity(itemID: itemID, at: date, calendar: calendar)
        save()
    }

    func setMastery(
        _ mastery: EnglishMasteryLevel,
        for itemID: String,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        var item = progress(for: itemID)
        item.mastery = mastery
        item.lastStudiedAt = date
        item.nextReviewAt = calendar.date(byAdding: .day, value: mastery.nextReviewDays, to: date)
        records[itemID] = item
        recordActivity(itemID: itemID, at: date, calendar: calendar)
        save()
    }

    @discardableResult
    func toggleFavorite(_ itemID: String) -> Bool {
        var item = progress(for: itemID)
        item.isFavorite.toggle()
        records[itemID] = item
        save()
        return item.isFavorite
    }

    func summary(
        dailyTarget: Int,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> EnglishDailySummary {
        let key = Self.dayKey(for: date, calendar: calendar)
        return EnglishDailySummary(
            learnedCount: learnedItemIDsByDay[key]?.count ?? 0,
            dailyTarget: dailyTarget,
            masteredCount: records.values.filter { $0.mastery == .mastered }.count,
            streak: streak(through: date, calendar: calendar)
        )
    }

    func dueRecords(on date: Date = Date()) -> [String: EnglishItemProgress] {
        records.filter { _, progress in
            guard let nextReviewAt = progress.nextReviewAt else { return true }
            return nextReviewAt <= date
        }
    }

    func resetForTesting() {
        records = [:]
        activityDays = []
        learnedItemIDsByDay = [:]
        save()
    }

    private func recordActivity(itemID: String, at date: Date, calendar: Calendar) {
        let key = Self.dayKey(for: date, calendar: calendar)
        activityDays.insert(key)
        learnedItemIDsByDay[key, default: []].insert(itemID)
    }

    private func streak(through date: Date, calendar: Calendar) -> Int {
        var result = 0
        var cursor = calendar.startOfDay(for: date)
        while activityDays.contains(Self.dayKey(for: cursor, calendar: calendar)) {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return result
    }

    private func save() {
        guard let persistenceURL else { return }
        let archive = EnglishProgressArchive(
            records: records,
            activityDays: activityDays,
            learnedItemIDsByDay: learnedItemIDsByDay
        )
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.englishProgressEncoder.encode(archive)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            #if DEBUG
            print("Failed to save English progress: \(error)")
            #endif
        }
    }

    private static func load(from url: URL?) -> EnglishProgressArchive? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.englishProgressDecoder.decode(EnglishProgressArchive.self, from: data)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static var defaultPersistenceURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(GoldDataStorage.directoryName, isDirectory: true)
            .appendingPathComponent("english-learning-progress.json")
    }
}

private extension JSONEncoder {
    static var englishProgressEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var englishProgressDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
