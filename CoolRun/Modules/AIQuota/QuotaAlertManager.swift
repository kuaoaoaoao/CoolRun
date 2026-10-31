#if os(macOS)
import Foundation
import UserNotifications

// MARK: - AI 额度通知

/// 额度提醒管理器：Codex / Claude 轮询成功后检查各额度窗口，
/// 剩余额度跌破阈值时发一次系统通知；额度重置回升后再发一次恢复通知并重新武装。
@MainActor
final class QuotaAlertManager {
    static let shared = QuotaAlertManager()

    /// 剩余额度低于该值时提醒
    static let lowThreshold = 10
    /// 回升到该值以上视为额度已重置/恢复
    static let rearmThreshold = 30

    struct WindowInfo: Equatable, Sendable {
        let id: String
        let title: String
        let remainingPercent: Int
    }

    enum Kind {
        case low
        case recovered
    }

    /// 已触发低额度提醒的窗口（等待额度回升后重新武装）
    private var lowFired: Set<String> = []
    private var hasRequestedAuthorization = false

    private init() {}

    /// 轮询成功后调用：检查每个额度窗口并按需发通知。
    func handle(provider: String, windows: [WindowInfo]) {
        guard AppSettings.shared.aiQuotaAlertEnabled else { return }
        for window in windows {
            let key = "\(provider)-\(window.id)"
            if lowFired.contains(key) {
                if window.remainingPercent >= Self.rearmThreshold {
                    lowFired.remove(key)
                    sendNotification(provider: provider, window: window, kind: .recovered)
                }
            } else if window.remainingPercent <= Self.lowThreshold {
                lowFired.insert(key)
                sendNotification(provider: provider, window: window, kind: .low)
            }
        }
    }

    func requestAuthorizationIfNeeded(completion: (@MainActor () -> Void)? = nil) {
        guard !hasRequestedAuthorization else {
            completion?()
            return
        }
        hasRequestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            guard let completion else { return }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func sendNotification(provider: String, window: WindowInfo, kind: Kind) {
        requestAuthorizationIfNeeded()
        let lang = AppSettings.shared.language

        let content = UNMutableNotificationContent()
        switch kind {
        case .low:
            content.title = LocalizedString.l(
                lang,
                en: "\(provider) Quota Low",
                zh: "\(provider) 额度告急",
                ja: "\(provider) クォータ残りわずか",
                ko: "\(provider) 할당량 부족"
            )
            content.body = LocalizedString.l(
                lang,
                en: "\(window.title): only \(window.remainingPercent)% left",
                zh: "\(window.title)：仅剩 \(window.remainingPercent)%",
                ja: "\(window.title)：残り \(window.remainingPercent)%",
                ko: "\(window.title): \(window.remainingPercent)% 남음"
            )
        case .recovered:
            content.title = LocalizedString.l(
                lang,
                en: "\(provider) Quota Restored",
                zh: "\(provider) 额度已恢复",
                ja: "\(provider) クォータ回復",
                ko: "\(provider) 할당량 복구"
            )
            content.body = LocalizedString.l(
                lang,
                en: "\(window.title): back to \(window.remainingPercent)%",
                zh: "\(window.title)：已恢复至 \(window.remainingPercent)%",
                ja: "\(window.title)：\(window.remainingPercent)% に回復",
                ko: "\(window.title): \(window.remainingPercent)%로 복구"
            )
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quota-alert-\(provider)-\(window.id)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
#endif
