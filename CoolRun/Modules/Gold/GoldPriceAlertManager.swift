#if os(macOS)
import Foundation
import UserNotifications

// MARK: - 金价到价提醒

/// 到价提醒管理器：金价轮询成功后检查是否触达用户设定的上/下限。
///
/// 触发规则：**每个方向、每个自然日最多提醒一次。**
/// 早先的实现是「价格回落 0.5% 就重新武装 + 同方向最短间隔 30 分钟」，
/// 金价在阈值附近震荡时一天能响几十次；而且触发状态只存在内存里，
/// 重启 App 会清零，导致当天已经提醒过的那次又被补一遍。
///
/// 现在的语义：
/// - 同一自然日内，某个方向提醒过一次就不再提醒（跨日自动重新武装）；
/// - 用户改动阈值视为重新武装，改完立刻按新阈值判断，不用等到第二天；
/// - 触发记录落 UserDefaults，重启 App 不会重复提醒。
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
        /// 各方向最近一次触发时间。与 `now` 落在同一自然日内则不再触发。
        var lastUpperFiredAt: Date?
        var lastLowerFiredAt: Date?
        /// 触发时使用的阈值。用户改了阈值视为重新武装。
        var upperThreshold: Double?
        var lowerThreshold: Double?
    }

    private enum Keys {
        static let lastUpperFiredAt = "gold_alert_last_upper_fired_at"
        static let lastLowerFiredAt = "gold_alert_last_lower_fired_at"
        static let upperThreshold = "gold_alert_upper_threshold"
        static let lowerThreshold = "gold_alert_lower_threshold"
    }

    private var state: State
    private var hasRequestedAuthorization = false

    private init() {
        let defaults = UserDefaults.standard
        func storedDate(_ key: String) -> Date? {
            guard let raw = defaults.object(forKey: key) as? Double, raw > 0 else { return nil }
            return Date(timeIntervalSince1970: raw)
        }
        func storedThreshold(_ key: String) -> Double? {
            guard let raw = defaults.object(forKey: key) as? Double, raw > 0 else { return nil }
            return raw
        }
        state = State(
            lastUpperFiredAt: storedDate(Keys.lastUpperFiredAt),
            lastLowerFiredAt: storedDate(Keys.lastLowerFiredAt),
            upperThreshold: storedThreshold(Keys.upperThreshold),
            lowerThreshold: storedThreshold(Keys.lowerThreshold)
        )
    }

    /// 纯函数：根据当前价、阈值和上次状态判断是否触发。
    ///
    /// 上下限同轮都满足时优先报下限（跌破风险更高），与旧行为保持一致。
    nonisolated static func evaluate(
        price: Double,
        upper: Double?,
        lower: Double?,
        state: State,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (alert: Direction?, newState: State) {
        var newState = state
        var alert: Direction?

        if let upper, upper > 0 {
            if price >= upper, shouldFire(
                now: now,
                lastFiredAt: state.lastUpperFiredAt,
                armedThreshold: state.upperThreshold,
                threshold: upper,
                calendar: calendar
            ) {
                alert = .upper
                newState.lastUpperFiredAt = now
            }
            newState.upperThreshold = upper
        } else {
            // 阈值被清空：连同记录一起清掉，下次填回来能正常触发
            newState.lastUpperFiredAt = nil
            newState.upperThreshold = nil
        }

        if let lower, lower > 0 {
            if price <= lower, shouldFire(
                now: now,
                lastFiredAt: state.lastLowerFiredAt,
                armedThreshold: state.lowerThreshold,
                threshold: lower,
                calendar: calendar
            ) {
                alert = .lower
                newState.lastLowerFiredAt = now
            }
            newState.lowerThreshold = lower
        } else {
            newState.lastLowerFiredAt = nil
            newState.lowerThreshold = nil
        }

        return (alert, newState)
    }

    /// 这一轮是否该发提醒。
    ///
    /// - 阈值和上次触发时不一致 → 用户改过设置，视为重新武装，立刻按新阈值判断；
    /// - 上次触发和现在不在同一个自然日 → 新的一天，重新武装；
    /// - 其余情况（当天已经提醒过）→ 静默。
    nonisolated static func shouldFire(
        now: Date,
        lastFiredAt: Date?,
        armedThreshold: Double?,
        threshold: Double,
        calendar: Calendar = .current
    ) -> Bool {
        if armedThreshold != threshold { return true }
        guard let lastFiredAt else { return true }
        return !calendar.isDate(now, inSameDayAs: lastFiredAt)
    }

    /// 轮询成功后调用：检查阈值并按需发通知。
    func handle(quote: GoldPriceQuote) {
        let settings = AppSettings.shared
        guard settings.goldAlertEnabled else { return }

        let upper = Self.parseThreshold(settings.goldAlertUpperText)
        let lower = Self.parseThreshold(settings.goldAlertLowerText)
        guard upper != nil || lower != nil else {
            // 阈值都清空了：重置状态，避免残留记录压制以后重新填写的阈值
            if state != State() {
                state = State()
                persist()
            }
            return
        }

        let previous = state
        let result = Self.evaluate(
            price: quote.cnyPerGram,
            upper: upper,
            lower: lower,
            state: state
        )
        state = result.newState
        if state != previous {
            persist()
        }

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

    private func persist() {
        let defaults = UserDefaults.standard
        if let value = state.lastUpperFiredAt?.timeIntervalSince1970 {
            defaults.set(value, forKey: Keys.lastUpperFiredAt)
        } else {
            defaults.removeObject(forKey: Keys.lastUpperFiredAt)
        }
        if let value = state.lastLowerFiredAt?.timeIntervalSince1970 {
            defaults.set(value, forKey: Keys.lastLowerFiredAt)
        } else {
            defaults.removeObject(forKey: Keys.lastLowerFiredAt)
        }
        if let value = state.upperThreshold {
            defaults.set(value, forKey: Keys.upperThreshold)
        } else {
            defaults.removeObject(forKey: Keys.upperThreshold)
        }
        if let value = state.lowerThreshold {
            defaults.set(value, forKey: Keys.lowerThreshold)
        } else {
            defaults.removeObject(forKey: Keys.lowerThreshold)
        }
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

        // 每个方向固定一个 identifier：新提醒直接替换旧的，
        // 避免每天一条在通知中心越堆越多。
        let request = UNNotificationRequest(
            identifier: "gold-price-alert-\(direction.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
#endif
