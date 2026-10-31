import Foundation

enum SpeechState: Equatable {
    case idle
    case playing
    case paused
}

enum EnglishLearningCategory: String, CaseIterable, Codable, Identifiable {
    case words
    case sentences
    case passages
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .words: return LocalizedString.english("words")
        case .sentences: return LocalizedString.english("sentences")
        case .passages: return LocalizedString.english("passages")
        case .daily: return LocalizedString.english("daily")
        }
    }

    var icon: String {
        switch self {
        case .words: return "character.book.closed"
        case .sentences: return "text.bubble"
        case .passages: return "doc.text"
        case .daily: return "sun.max.fill"
        }
    }
}

enum EnglishDifficulty: String, CaseIterable, Codable, Identifiable {
    case beginner
    case elementary
    case intermediate

    var id: String { rawValue }
}

enum EnglishAccent: String, CaseIterable, Codable, Identifiable {
    case american = "en-US"
    case british = "en-GB"

    var id: String { rawValue }
    var title: String { self == .american ? LocalizedString.english("american") : LocalizedString.english("british") }
    var shortTitle: String { self == .american ? LocalizedString.english("american_short") : LocalizedString.english("british_short") }
}

enum EnglishStage: String, CaseIterable, Codable, Identifiable {
    case daily
    case primarySchool = "primary_school"
    case middleSchool = "middle_school"
    case highSchool = "high_school"
    case cet4
    case cet6
    case ielts
    case toefl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return LocalizedString.english("stage_daily")
        case .primarySchool: return LocalizedString.english("stage_primary")
        case .middleSchool: return LocalizedString.english("stage_middle")
        case .highSchool: return LocalizedString.english("stage_high")
        case .cet4: return LocalizedString.english("stage_cet4")
        case .cet6: return LocalizedString.english("stage_cet6")
        case .ielts: return LocalizedString.english("stage_ielts")
        case .toefl: return LocalizedString.english("stage_toefl")
        }
    }

    var shortTitle: String {
        switch self {
        case .daily: return LocalizedString.english("stage_daily_short")
        case .primarySchool: return LocalizedString.english("stage_primary_short")
        case .middleSchool: return LocalizedString.english("stage_middle_short")
        case .highSchool: return LocalizedString.english("stage_high_short")
        case .cet4: return LocalizedString.english("stage_cet4_short")
        case .cet6: return LocalizedString.english("stage_cet6_short")
        case .ielts: return LocalizedString.english("stage_ielts_short")
        case .toefl: return LocalizedString.english("stage_toefl_short")
        }
    }

    var icon: String {
        switch self {
        case .daily: return "sun.max"
        case .primarySchool: return "backpack"
        case .middleSchool: return "graduationcap"
        case .highSchool: return "book.closed"
        case .cet4: return "medal"
        case .cet6: return "rosette"
        case .ielts: return "globe.europe.africa"
        case .toefl: return "airplane"
        }
    }

    var summary: String {
        switch self {
        case .daily: return LocalizedString.english("stage_daily_desc")
        case .primarySchool: return LocalizedString.english("stage_primary_desc")
        case .middleSchool: return LocalizedString.english("stage_middle_desc")
        case .highSchool: return LocalizedString.english("stage_high_desc")
        case .cet4: return LocalizedString.english("stage_cet4_desc")
        case .cet6: return LocalizedString.english("stage_cet6_desc")
        case .ielts: return LocalizedString.english("stage_ielts_desc")
        case .toefl: return LocalizedString.english("stage_toefl_desc")
        }
    }
}

enum EnglishMenuTextStyle: String, CaseIterable, Codable, Identifiable {
    case englishOnly
    case englishAndChinese

    var id: String { rawValue }
    var title: String { self == .englishOnly ? LocalizedString.english("english_only") : LocalizedString.english("english_and_chinese") }
}

enum EnglishTTSBackend: String, CaseIterable, Codable, Identifiable {
    case system
    case kokoro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return LocalizedString.english("system_voice")
        case .kokoro: return LocalizedString.english("kokoro_experimental")
        }
    }
}

enum EnglishMasteryLevel: Int, CaseIterable, Codable, Comparable {
    case new = 0
    case unfamiliar = 1
    case learning = 2
    case familiar = 3
    case mastered = 4

    static func < (lhs: EnglishMasteryLevel, rhs: EnglishMasteryLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .new: return LocalizedString.english("mastery_new")
        case .unfamiliar: return LocalizedString.english("mastery_unfamiliar")
        case .learning: return LocalizedString.english("mastery_learning")
        case .familiar: return LocalizedString.english("mastery_familiar")
        case .mastered: return LocalizedString.english("mastery_mastered")
        }
    }

    var nextReviewDays: Int {
        switch self {
        case .new, .unfamiliar: return 1
        case .learning: return 3
        case .familiar: return 7
        case .mastered: return 30
        }
    }
}

struct EnglishLearningItem: Identifiable, Codable, Equatable {
    let id: String
    let category: EnglishLearningCategory
    let difficulty: EnglishDifficulty
    let stage: EnglishStage
    let title: String
    let pronunciation: String?
    let partOfSpeech: String?
    let translation: String
    let example: String?
    let exampleTranslation: String?
    let source: String?
    let passageSentences: [String]

    init(
        id: String,
        category: EnglishLearningCategory,
        difficulty: EnglishDifficulty = .beginner,
        stage: EnglishStage = .daily,
        title: String,
        pronunciation: String? = nil,
        partOfSpeech: String? = nil,
        translation: String,
        example: String? = nil,
        exampleTranslation: String? = nil,
        source: String? = nil,
        passageSentences: [String] = []
    ) {
        self.id = id
        self.category = category
        self.difficulty = difficulty
        self.stage = stage
        self.title = title
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.translation = translation
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.source = source
        self.passageSentences = passageSentences
    }

    var speechSegments: [String] {
        passageSentences.isEmpty ? [title] : passageSentences
    }

    func menuBarText(style: EnglishMenuTextStyle, activeSegment: String? = nil, limit: Int = 26) -> String {
        let english = activeSegment?.isEmpty == false ? activeSegment! : title
        let combined: String
        if style == .englishAndChinese, category == .words {
            combined = "\(english) · \(translation)"
        } else {
            combined = english
        }
        return Self.compact(combined, limit: limit)
    }

    static func compact(_ text: String, limit: Int) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 1, normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

struct EnglishItemProgress: Codable, Equatable {
    var viewCount = 0
    var listenCount = 0
    var mastery = EnglishMasteryLevel.new
    var isFavorite = false
    var lastStudiedAt: Date?
    var nextReviewAt: Date?
}

struct EnglishDailySummary: Equatable {
    let learnedCount: Int
    let dailyTarget: Int
    let masteredCount: Int
    let streak: Int

    var progress: Double {
        guard dailyTarget > 0 else { return 1 }
        return min(Double(learnedCount) / Double(dailyTarget), 1)
    }

    var isGoalComplete: Bool { learnedCount >= dailyTarget }
}
