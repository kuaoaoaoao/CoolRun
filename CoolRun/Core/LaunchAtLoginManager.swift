#if os(macOS)
import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    private let service = SMAppService.mainApp

    private init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            refresh()
        } catch {
            refresh()
            statusMessage = error.localizedDescription
        }
    }

    func refresh() {
        switch service.status {
        case .enabled:
            isEnabled = true
            statusMessage = nil
        case .requiresApproval:
            isEnabled = true
            statusMessage = "需要在系统设置的登录项中允许 CoolRun"
        case .notFound:
            isEnabled = false
            statusMessage = "当前应用位置不支持注册登录项"
        case .notRegistered:
            isEnabled = false
            statusMessage = nil
        @unknown default:
            isEnabled = false
            statusMessage = "无法读取登录项状态"
        }
    }
}
#else
import Combine
import Foundation

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String? = "当前平台不支持登录时启动"

    private init() {}

    func setEnabled(_ enabled: Bool) {}
    func refresh() {}
}
#endif
