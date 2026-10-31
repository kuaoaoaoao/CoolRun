import Combine
import Foundation

enum CoolRunQuickAction: String, Sendable {
    case addCountdown
    case recordGoldTrade
    case showSystemHistory
}

struct CoolRunNavigationRequest: Equatable, Sendable {
    let id: UUID
    let mode: ViewMode
    let quickAction: CoolRunQuickAction?

    init(mode: ViewMode, quickAction: CoolRunQuickAction? = nil) {
        id = UUID()
        self.mode = mode
        self.quickAction = quickAction
    }
}

extension Notification.Name {
    static let coolRunPresentNavigationRequest = Notification.Name("CoolRunPresentNavigationRequest")
    static let coolRunRefreshGold = Notification.Name("CoolRunRefreshGold")
}

@MainActor
final class AppNavigationRouter: ObservableObject {
    static let shared = AppNavigationRouter()

    @Published private(set) var request: CoolRunNavigationRequest?

    private init() {}

    func open(_ mode: ViewMode, quickAction: CoolRunQuickAction? = nil) {
        request = CoolRunNavigationRequest(mode: mode, quickAction: quickAction)
        NotificationCenter.default.post(name: .coolRunPresentNavigationRequest, object: nil)
    }

    func consumeQuickAction(_ id: UUID) {
        guard request?.id == id, request?.quickAction != nil else { return }
        request = CoolRunNavigationRequest(mode: request?.mode ?? .today)
    }
}
