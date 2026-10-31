import AppIntents
import Foundation

enum CoolRunModuleIntentValue: String, AppEnum, CaseIterable {
    case today
    case monitor
    case gold
    case calendar
    case english
    case ai

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "CoolRun Module")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .today: "Today",
        .monitor: "System Monitor",
        .gold: "Gold",
        .calendar: "Calendar",
        .english: "English",
        .ai: "AI Quota"
    ]

    var viewMode: ViewMode {
        switch self {
        case .today: .today
        case .monitor: .monitor
        case .gold: .gold
        case .calendar: .calendar
        case .english: .english
        case .ai: .codex
        }
    }
}

struct ShowCoolRunTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Show CoolRun Today"
    static var description = IntentDescription("Open CoolRun's prioritized Today overview.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationRouter.shared.open(.today)
        return .result()
    }
}

struct OpenCoolRunModuleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open CoolRun Module"
    static var description = IntentDescription("Open a specific CoolRun module.")
    static var openAppWhenRun = true

    @Parameter(title: "Module", default: .today)
    var module: CoolRunModuleIntentValue

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationRouter.shared.open(module.viewMode)
        return .result()
    }
}

struct ToggleCoolRunEnglishIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause CoolRun English"
    static var description = IntentDescription("Start, pause, or resume the current English learning queue.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        EnglishLearningManager.shared.toggleContinuousPlayback()
        return .result()
    }
}

struct RefreshCoolRunIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh CoolRun Data"
    static var description = IntentDescription("Refresh the current gold quote and open the Gold module.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationRouter.shared.open(.gold)
        NotificationCenter.default.post(name: .coolRunRefreshGold, object: nil)
        return .result()
    }
}

struct CoolRunShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowCoolRunTodayIntent(),
            phrases: ["Show \(.applicationName) today"],
            shortTitle: "CoolRun Today",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: ToggleCoolRunEnglishIntent(),
            phrases: ["Play English in \(.applicationName)"],
            shortTitle: "Play English",
            systemImageName: "character.book.closed.fill"
        )
        AppShortcut(
            intent: RefreshCoolRunIntent(),
            phrases: ["Refresh \(.applicationName)"],
            shortTitle: "Refresh CoolRun",
            systemImageName: "arrow.clockwise"
        )
    }
}
