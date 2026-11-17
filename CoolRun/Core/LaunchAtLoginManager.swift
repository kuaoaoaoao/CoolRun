#if os(macOS)
import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled = false

    /// 登录项注册状态，文案在读取时才本地化，切换语言后无需重新采样。
    enum Status {
        case ok
        case requiresApproval
        case notFound
        case unknown
    }

    @Published private(set) var status: Status = .ok
    /// 系统返回的错误描述（已是当前系统语言，不再二次本地化）。
    @Published private(set) var errorMessage: String?

    var statusMessage: String? {
        let lang = AppSettings.shared.language
        switch status {
        case .ok:
            return errorMessage
        case .requiresApproval:
            return LocalizedString.l(
                lang,
                en: "Allow CoolRun in System Settings → Login Items",
                zh: "需要在系统设置的登录项中允许 CoolRun",
                ja: "システム設定 → ログイン項目で CoolRun を許可してください",
                ko: "시스템 설정 → 로그인 항목에서 CoolRun을 허용해 주세요"
            )
        case .notFound:
            return LocalizedString.l(
                lang,
                en: "Login items can't be registered from this app location",
                zh: "当前应用位置不支持注册登录项",
                ja: "このアプリの場所ではログイン項目を登録できません",
                ko: "현재 앱 위치에서는 로그인 항목을 등록할 수 없습니다"
            )
        case .unknown:
            return LocalizedString.l(
                lang,
                en: "Unable to read login item status",
                zh: "无法读取登录项状态",
                ja: "ログイン項目の状態を取得できません",
                ko: "로그인 항목 상태를 읽을 수 없습니다"
            )
        }
    }

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
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        switch service.status {
        case .enabled:
            isEnabled = true
            status = .ok
            errorMessage = nil
        case .requiresApproval:
            isEnabled = true
            status = .requiresApproval
            errorMessage = nil
        case .notFound:
            isEnabled = false
            status = .notFound
            errorMessage = nil
        case .notRegistered:
            isEnabled = false
            status = .ok
            errorMessage = nil
        @unknown default:
            isEnabled = false
            status = .unknown
            errorMessage = nil
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
    @Published private(set) var statusMessage: String? = LocalizedString.l(
        AppSettings.shared.language,
        en: "Launch at login isn't supported on this platform",
        zh: "当前平台不支持登录时启动",
        ja: "このプラットフォームではログイン時の起動に対応していません",
        ko: "이 플랫폼에서는 로그인 시 실행을 지원하지 않습니다"
    )

    private init() {}

    func setEnabled(_ enabled: Bool) {}
    func refresh() {}
}
#endif
