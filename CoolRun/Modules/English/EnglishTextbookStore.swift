import Combine
import CoreFoundation
import Foundation

enum EnglishTextbookSource: String, Codable {
    case builtin
    case imported
}

struct EnglishTextbook: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var stage: EnglishStage
    var source: EnglishTextbookSource
    var summary: String
    var importedAt: Date?
    var items: [EnglishLearningItem]

    var wordCount: Int { items.count }
    var isImported: Bool { source == .imported }
}

struct EnglishTextbookProgressSummary: Equatable {
    let viewedCount: Int
    let masteredCount: Int
    let familiarOrBetterCount: Int

    func studiedRatio(total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(Double(viewedCount) / Double(total), 1)
    }
}

private struct EnglishTextbookArchive: Codable {
    var version = 1
    var selectedTextbookID: String?
    var customTextbooks: [EnglishTextbook] = []
}

@MainActor
final class EnglishTextbookStore: ObservableObject {
    static let shared = EnglishTextbookStore()

    @Published private(set) var customTextbooks: [EnglishTextbook]
    @Published var selectedTextbookID: String {
        didSet {
            guard oldValue != selectedTextbookID else { return }
            syncSelectedStage()
            save()
        }
    }

    private let persistenceURL: URL?
    private let settings: AppSettings

    var builtinTextbooks: [EnglishTextbook] {
        EnglishStage.allCases.map { stage in
            EnglishTextbook(
                id: Self.builtinID(for: stage),
                title: stage.title,
                stage: stage,
                source: .builtin,
                summary: stage.summary,
                importedAt: nil,
                items: EnglishVocabulary.words(for: stage)
            )
        }
    }

    var textbooks: [EnglishTextbook] {
        builtinTextbooks + customTextbooks
    }

    var selectedTextbook: EnglishTextbook {
        textbooks.first { $0.id == selectedTextbookID }
            ?? builtinTextbooks.first { $0.stage == settings.englishStage }
            ?? builtinTextbooks[0]
    }

    convenience init() {
        self.init(persistenceURL: Self.defaultPersistenceURL, settings: .shared)
    }

    init(persistenceURL: URL?, settings: AppSettings) {
        self.persistenceURL = persistenceURL
        self.settings = settings
        let archive = Self.load(from: persistenceURL) ?? EnglishTextbookArchive()
        self.customTextbooks = archive.customTextbooks
        self.selectedTextbookID = archive.selectedTextbookID ?? Self.builtinID(for: settings.englishStage)
        syncSelectedStage()
    }

    func selectTextbook(_ textbook: EnglishTextbook) {
        selectedTextbookID = textbook.id
    }

    func selectBuiltin(stage: EnglishStage) {
        selectedTextbookID = Self.builtinID(for: stage)
    }

    func removeTextbook(_ textbook: EnglishTextbook) {
        guard textbook.isImported else { return }
        customTextbooks.removeAll { $0.id == textbook.id }
        if selectedTextbookID == textbook.id {
            selectedTextbookID = Self.builtinID(for: textbook.stage)
        }
        save()
    }

    func importTextbook(from url: URL, stage: EnglishStage) throws -> EnglishTextbook {
        let didStartScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScope { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let text = try Self.decodeText(data)
        let title = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookID = "custom.\(UUID().uuidString)"
        let items = try Self.parseWords(
            from: text,
            bookID: bookID,
            bookTitle: title.isEmpty ? LocalizedString.english("imported_textbook") : title,
            stage: stage
        )

        let textbook = EnglishTextbook(
            id: bookID,
            title: title.isEmpty ? LocalizedString.english("imported_textbook") : title,
            stage: stage,
            source: .imported,
            summary: LocalizedString.english("imported_textbook_summary"),
            importedAt: Date(),
            items: items
        )
        customTextbooks.insert(textbook, at: 0)
        selectedTextbookID = textbook.id
        save()
        return textbook
    }

    func orderedWords(
        progress: [String: EnglishItemProgress],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [EnglishLearningItem] {
        buildOrderedItems(source: selectedTextbook.items, progress: progress, on: date, calendar: calendar)
    }

    func dailyWord(on date: Date = Date(), calendar: Calendar = .current) -> EnglishLearningItem {
        let items = selectedTextbook.items
        precondition(!items.isEmpty, "English textbook must not be empty")
        return items[stableIndex(count: items.count, on: date, calendar: calendar)]
    }

    func progressSummary(for textbook: EnglishTextbook, progress: [String: EnglishItemProgress]) -> EnglishTextbookProgressSummary {
        let ids = Set(textbook.items.map(\.id))
        let records = progress.filter { ids.contains($0.key) }.values
        return EnglishTextbookProgressSummary(
            viewedCount: records.filter { $0.viewCount > 0 || $0.listenCount > 0 }.count,
            masteredCount: records.filter { $0.mastery == .mastered }.count,
            familiarOrBetterCount: records.filter { $0.mastery >= .familiar }.count
        )
    }

    static func builtinID(for stage: EnglishStage) -> String {
        "builtin.\(stage.rawValue)"
    }

    private func stableIndex(count: Int, on date: Date, calendar: Calendar) -> Int {
        guard count > 0 else { return 0 }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return abs(day) % count
    }

    private func buildOrderedItems(
        source: [EnglishLearningItem],
        progress: [String: EnglishItemProgress],
        on date: Date,
        calendar: Calendar
    ) -> [EnglishLearningItem] {
        guard !source.isEmpty else { return [] }
        let start = stableIndex(count: source.count, on: date, calendar: calendar)
        let rotated = Array(source[start...] + source[..<start])
        return rotated.sorted { lhs, rhs in
            let left = progress[lhs.id]
            let right = progress[rhs.id]
            let leftDue = left?.nextReviewAt.map { $0 <= date } ?? true
            let rightDue = right?.nextReviewAt.map { $0 <= date } ?? true
            if leftDue != rightDue { return leftDue && !rightDue }
            let leftMastery = left?.mastery ?? .new
            let rightMastery = right?.mastery ?? .new
            return leftMastery < rightMastery
        }
    }

    private func syncSelectedStage() {
        guard let stage = textbooks.first(where: { $0.id == selectedTextbookID })?.stage else { return }
        if settings.englishStage != stage {
            settings.englishStage = stage
        }
    }

    private func save() {
        guard let persistenceURL else { return }
        let archive = EnglishTextbookArchive(
            selectedTextbookID: selectedTextbookID,
            customTextbooks: customTextbooks
        )
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(archive)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            #if DEBUG
            print("Failed to save English textbooks: \(error)")
            #endif
        }
    }

    private static func load(from url: URL?) -> EnglishTextbookArchive? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(EnglishTextbookArchive.self, from: data)
    }

    private static var defaultPersistenceURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(GoldDataStorage.directoryName, isDirectory: true)
            .appendingPathComponent("english-textbooks.json")
    }
}

private extension EnglishTextbookStore {
    static func decodeText(_ data: Data) throws -> String {
        let encodings: [String.Encoding] = [
            .utf8,
            .unicode,
            .utf16LittleEndian,
            .utf16BigEndian,
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
            .isoLatin1
        ]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text
            }
        }
        throw EnglishTextbookImportError.unreadableText
    }

    static func parseWords(
        from text: String,
        bookID: String,
        bookTitle: String,
        stage: EnglishStage
    ) throws -> [EnglishLearningItem] {
        var rows = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !rows.isEmpty else { throw EnglishTextbookImportError.noWords }

        var headerMap: [String: Int] = [:]
        let firstColumns = parseColumns(rows[0])
        if firstColumns.contains(where: { normalizedHeader($0) != nil }) {
            for (index, value) in firstColumns.enumerated() {
                if let key = normalizedHeader(value) {
                    headerMap[key] = index
                }
            }
            rows.removeFirst()
        }

        var usedWords = Set<String>()
        var items: [EnglishLearningItem] = []
        for (index, row) in rows.enumerated() {
            let columns = parseColumns(row)
            let word = value(for: "word", in: columns, headerMap: headerMap, fallbackIndex: 0)
            let title = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let uniqueKey = title.lowercased()
            guard usedWords.insert(uniqueKey).inserted else { continue }

            let translation = value(for: "translation", in: columns, headerMap: headerMap, fallbackIndex: 1)
            let pronunciation = value(for: "pronunciation", in: columns, headerMap: headerMap, fallbackIndex: 2).nilIfEmpty
            let part = value(for: "part", in: columns, headerMap: headerMap, fallbackIndex: 3).nilIfEmpty
            let example = value(for: "example", in: columns, headerMap: headerMap, fallbackIndex: 4).nilIfEmpty
            let exampleTranslation = value(for: "exampleTranslation", in: columns, headerMap: headerMap, fallbackIndex: 5).nilIfEmpty
            let slug = slugify(title, fallback: "\(index + 1)")

            items.append(EnglishLearningItem(
                id: "\(bookID).word.\(slug).\(index + 1)",
                category: .words,
                difficulty: .beginner,
                stage: stage,
                title: title,
                pronunciation: pronunciation,
                partOfSpeech: part,
                translation: translation.isEmpty ? LocalizedString.english("translation_missing") : translation,
                example: example,
                exampleTranslation: exampleTranslation,
                source: bookTitle
            ))
        }

        guard !items.isEmpty else { throw EnglishTextbookImportError.noWords }
        return items
    }

    static func parseColumns(_ line: String) -> [String] {
        let delimiter: Character
        if line.contains("\t") {
            delimiter = "\t"
        } else if line.contains(",") {
            delimiter = ","
        } else {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            return parts.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        var columns: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                if isQuoted, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        isQuoted.toggle()
                        if next == delimiter {
                            columns.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                            current = ""
                        } else {
                            current.append(next)
                        }
                    }
                } else {
                    isQuoted.toggle()
                }
            } else if character == delimiter, !isQuoted {
                columns.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }
        columns.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return columns
    }

    static func normalizedHeader(_ value: String) -> String? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "word", "title", "english", "单词", "英文": return "word"
        case "translation", "meaning", "chinese", "释义", "中文", "意思": return "translation"
        case "pronunciation", "phonetic", "音标", "发音": return "pronunciation"
        case "part", "partofspeech", "pos", "词性": return "part"
        case "example", "sentence", "例句": return "example"
        case "exampletranslation", "example_translation", "例句翻译": return "exampleTranslation"
        default: return nil
        }
    }

    static func value(for key: String, in columns: [String], headerMap: [String: Int], fallbackIndex: Int) -> String {
        if let index = headerMap[key], columns.indices.contains(index) {
            return columns[index]
        }
        if columns.indices.contains(fallbackIndex) {
            return columns[fallbackIndex]
        }
        return ""
    }

    static func slugify(_ text: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let slug = text.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let compact = String(slug)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return compact.isEmpty ? fallback : compact
    }
}

enum EnglishTextbookImportError: LocalizedError {
    case unreadableText
    case noWords

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return LocalizedString.english("textbook_import_unreadable")
        case .noWords:
            return LocalizedString.english("textbook_import_no_words")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
