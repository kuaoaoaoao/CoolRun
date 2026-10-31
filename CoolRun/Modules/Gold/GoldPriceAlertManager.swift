#if os(macOS)
import Foundation
import UserNotifications

// MARK: - 金价到价提醒

/// 到价提醒管理器：金价轮询成功后检查是否触达用户设定的上/下限，
/// 触达时发一次系统通知；价格回到阈值内侧后重新武装，避免反复轰炸。
@MainActor
final class GoldPriceAlertManager {
    static let shared = GoldPriceAlertManager()

    /// 触发方向。
    enum Direction: String, Sendable {
        case upper
        case lower
    }

    /// 触发状态（纯值类型，便于单测）。
    struct State: Equatable, Sendable {
        /// 上限已触发（等待价格回落重新武装）
        var upperFired = false
        /// 下限已触发（等待价格回升重新武装）
        var lowerFired = false
        /// 各方向最近一次触发时间
        var lastUpperFiredAt: Date?
        var lastLowerFiredAt: Date?
    }

    /// 同方向两次通知的最短间隔。
    nonisolated static let minimumInterval: TimeInterval = 30 * 60
    /// 重新武装需要回到阈值内侧的比例（0.5%）。
    nonisolated static let rearmMargin = 0.005

    private var state = State()
    private var hasRequestedAuthorization = false

    private init() {}

    /// 纯函数：根据当前价、阈值和上次状态判断是否触发。
    nonisolated static func evaluate(
        price: Double,
        upper: Double?,
        lower: Double?,
        state: State,
        now: Date = Date()
    ) -> (alert: Direction?, newState: State) {
        var newState = state
        var alert: Direction?

        // 上限：上穿触发一次，回落到 upper*(1-0.5%) 以下重新武装
        if let upper, upper > 0 {
            if state.upperFired {
                if price <= upper * (1 - rearmMargin) {
                    newState.upperFired = false
                }
            } else if price >= upper {
                let intervalOK = state.lastUpperFiredAt.map {
                    now.timeIntervalSince($0) >= minimumInterval
                } ?? true
                if intervalOK {
                    alert = .upper
                    newState.upperFired = true
                    newState.lastUpperFiredAt = now
                } else {
                    // 间隔不足：仍然锁定，避免下轮重复判定
                    newState.upperFired = true
                }
            }
        } else {
            newState.upperFired = false
        }

        // 下限：下穿触发一次，回升到 lower*(1+0.5%) 以上重新武装
        if let lower, lower > 0 {
            if state.lowerFired {
                if price >= lower * (1 + rearmMargin) {
                    newState.lowerFired = false
                }
            } else if price <= lower {
                let intervalOK = state.lastLowerFiredAt.map {
                    now.timeIntervalSince($0) >= minimumInterval
                } ?? true
                if intervalOK {
                    // 上下限同轮都满足时优先报下限（跌破风险更高）
                    alert = .lower
                    newState.lowerFired = true
                    newState.lastLowerFiredAt = now
                } else {
                    newState.lowerFired = true
                }
            }
        } else {
            newState.lowerFired = false
        }

        return (alert, newState)
    }

    /// 轮询成功后调用：检查阈值并按需发通知。
    func handle(quote: GoldPriceQuote) {
        let settings = AppSettings.shared
        guard settings.goldAlertEnabled else { return }

        let upper = Self.parseThreshold(settings.goldAlertUpperText)
        let lower = Self.parseThreshold(settings.goldAlertLowerText)
        guard upper != nil || lower != nil else { return }

        let result = Self.evaluate(
            price: quote.cnyPerGram,
            upper: upper,
            lower: lower,
            state: state
        )
        state = result.newState

        if let direction = result.alert {
            let threshold = direction == .upper ? upper : lower
            sendNotification(direction: direction, price: quote.cnyPerGram, threshold: threshold ?? 0)
        }
    }

    /// 开关打开时请求通知授权（拒绝时静默，不发通知）；回调在授权结果返回后主线程执行。
    func requestAuthorizationIfNeeded(completion: (@MainActor () -> Void)? = nil) {
        guard !hasRequestedAuthorization else {
            completion?()
            return
        }
        hasRequestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            guard let completion else { return }
            Task { @MainActor in
                completion()
            }
        }
    }

    nonisolated static func parseThreshold(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    private func sendNotification(direction: Direction, price: Double, threshold: Double) {
        let lang = AppSettings.shared.language
        let priceText = price.formatted(.number.precision(.fractionLength(2)))
        let thresholdText = threshold.formatted(.number.precision(.fractionLength(2)))

        let content = UNMutableNotificationContent()
        content.title = LocalizedString.l(
            lang,
            en: "Gold Price Alert",
            zh: "金价到价提醒",
            ja: "金価格アラート",
            ko: "금 가격 알림"
        )
        content.body = direction == .upper
            ? LocalizedString.l(
                lang,
                en: "Gold reached ¥\(priceText)/g, above your upper limit ¥\(thresholdText)",
                zh: "金价已达 ¥\(priceText)/克，高于你设定的上限 ¥\(thresholdText)",
                ja: "金価格が ¥\(priceText)/g に達し、上限 ¥\(thresholdText) を上回りました",
                ko: "금 가격이 ¥\(priceText)/g에 도달해 상한 ¥\(thresholdText)을 넘었습니다"
            )
            : LocalizedString.l(
                lang,
                en: "Gold fell to ¥\(priceText)/g, below your lower limit ¥\(thresholdText)",
                zh: "金价已跌至 ¥\(priceText)/克，低于你设定的下限 ¥\(thresholdText)",
                ja: "金価格が ¥\(priceText)/g まで下落し、下限 ¥\(thresholdText) を下回りました",
                ko: "금 가격이 ¥\(priceText)/g로 하락해 하한 ¥\(thresholdText) 아래로 내려갔습니다"
            )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "gold-price-alert-\(direction.rawValue)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
#endif
