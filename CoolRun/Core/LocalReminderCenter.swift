import Combine
import Foundation
import UserNotifications

enum LocalReminderKind: String, Codable, CaseIterable, Sendable {
    case countdown
    case birthday
    case english
    case systemCPU
    case systemMemory
    case systemStorage
    case systemTemperature

    var destination: ViewMode {
        switch self {
        case .countdown, .birthday: .calendar
        case .english: .english
        case .systemCPU, .systemMemory, .systemStorage, .systemTemperature: .monitor
        }
    }
}

private struct ReminderDeliveryState: Codable {
    var lastDeliveredAt: [String: Date] = [:]
}

@MainActor
final class LocalReminderCenter: ObservableObject {
    static let shared = LocalReminderCenter(
        center: .current(),
        settings: .shared
    )

    static let categoryIdentifier = "coolrun.local-reminder"
    static let snoozeActionIdentifier = "coolrun.reminder.snooze"
    static let identifierPrefix = "coolrun.local."

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter
    private let settings: AppSettings
    private let stateURL: URL
    private var deliveryState: ReminderDeliveryState

    private init(
        center: UNUserNotificationCenter,
        settings: AppSettings
    ) {
        self.center = center
        self.settings = settings
        stateURL = GoldDataStorage.fileURL(named: "local_reminder_state.json")
        deliveryState = Self.loadState(from: stateURL)
    }

    func start() {
        registerCategories()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await loadAuthorizationStatus()
            await rescheduleAll()
        }
    }

    func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: LocalizedString.l(settings.language, en: "Remind later", zh: "稍后提醒", ja: "あとで通知", ko: "나중에 알림"),
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [snooze],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    func requestAuthorizationIfNeeded(completion: (@MainActor () -> Void)? = nil) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var notificationSettings = await center.notificationSettings()
            if notificationSettings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                notificationSettings = await center.notificationSettings()
            }
            authorizationStatus = notificationSettings.authorizationStatus
            completion?()
            await rescheduleAll()
        }
    }

    func refreshAuthorizationStatus(completion: (@MainActor () -> Void)? = nil) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await loadAuthorizationStatus()
            completion?()
        }
    }

    func rescheduleAll() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        if settings.countdownRemindersEnabled { scheduleCountdowns() }
        if settings.birthdayRemindersEnabled { scheduleBirthdays() }
        if settings.englishRemindersEnabled { scheduleEnglishReminder() }
    }

    func handle(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        if response.actionIdentifier == Self.snoozeActionIdentifier {
            let copy = content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
            copy.title = content.title
            copy.body = content.body
            copy.sound = .default
            copy.categoryIdentifier = Self.categoryIdentifier
            copy.userInfo = content.userInfo
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(settings.reminderSnoozeMinutes, 1) * 60),
                repeats: false
            )
            center.add(UNNotificationRequest(
                identifier: Self.identifierPrefix + "snooze." + UUID().uuidString,
                content: copy,
                trigger: trigger
            ))
            return
        }

        guard let rawKind = content.userInfo["kind"] as? String,
              let kind = LocalReminderKind(rawValue: rawKind) else { return }
        AppNavigationRouter.shared.open(kind.destination)
    }

    func notifySystemAnomaly(kind: LocalReminderKind, title: String, body: String, now: Date = Date()) {
        guard settings.systemAnomalyRemindersEnabled,
              authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        let key = kind.rawValue
        if let last = deliveryState.lastDeliveredAt[key], now.timeIntervalSince(last) < 60 * 60 { return }
        deliveryState.lastDeliveredAt[key] = now
        saveState()

        let content = makeContent(title: title, body: body, kind: kind)
        let delivery = Self.adjustedDeliveryDate(
            now,
            quietHoursEnabled: settings.reminderQuietHoursEnabled,
            quietStartHour: settings.reminderQuietStartHour,
            quietEndHour: settings.reminderQuietEndHour
        )
        let interval = max(delivery.timeIntervalSince(now), 1)
        center.add(UNNotificationRequest(
            identifier: Self.identifierPrefix + "system." + kind.rawValue,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        ))
    }

    nonisolated static func adjustedDeliveryDate(
        _ date: Date,
        quietHoursEnabled: Bool,
        quietStartHour: Int,
        quietEndHour: Int,
        calendar: Calendar = .current
    ) -> Date {
        guard quietHoursEnabled else { return date }
        let start = min(max(quietStartHour, 0), 23)
        let end = min(max(quietEndHour, 0), 23)
        let hour = calendar.component(.hour, from: date)
        let isQuiet: Bool
        if start == end {
            isQuiet = false
        } else if start < end {
            isQuiet = hour >= start && hour < end
        } else {
            isQuiet = hour >= start || hour < end
        }
        guard isQuiet else { return date }

        var target = calendar.date(bySettingHour: end, minute: 0, second: 0, of: date) ?? date
        if target <= date {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? date
        }
        return target
    }

    private func scheduleCountdowns(now: Date = Date()) {
        for event in CountdownManager.shared.getAllEvents() {
            guard let occurrence = event.nextOccurrence(after: now),
                  let requested = Calendar.current.date(byAdding: .day, value: -settings.reminderDaysBefore, to: occurrence),
                  let atHour = Calendar.current.date(bySettingHour: settings.reminderHour, minute: 0, second: 0, of: requested),
                  atHour > now else { continue }
            let delivery = adjusted(atHour)
            let body = LocalizedString.l(
                settings.language,
                en: "\(event.name) is in \(settings.reminderDaysBefore) days.",
                zh: "\(event.name) 还有 \(settings.reminderDaysBefore) 天。",
                ja: "\(event.name)まであと\(settings.reminderDaysBefore)日です。",
                ko: "\(event.name)까지 \(settings.reminderDaysBefore)일 남았습니다."
            )
            addCalendarRequest(
                identifier: Self.identifierPrefix + "countdown." + event.id.uuidString,
                title: LocalizedString.l(settings.language, en: "Countdown reminder", zh: "倒数日提醒", ja: "カウントダウン通知", ko: "카운트다운 알림"),
                body: body,
                kind: .countdown,
                date: delivery
            )
        }
    }

    private func scheduleBirthdays(now: Date = Date()) {
        let lunarYear = LunarCalendar.convertSolarToLunar(date: now).year
        let today = Calendar.current.startOfDay(for: now)
        for birthday in BirthdayManager.shared.getAllBirthdays() {
            let occurrence = (0...3).compactMap { birthday.solarDate(for: lunarYear + $0) }
                .first { Calendar.current.startOfDay(for: $0) >= today }
            guard let occurrence,
                  let requested = Calendar.current.date(byAdding: .day, value: -settings.reminderDaysBefore, to: occurrence),
                  let atHour = Calendar.current.date(bySettingHour: settings.reminderHour, minute: 0, second: 0, of: requested),
                  atHour > now else { continue }
            addCalendarRequest(
                identifier: Self.identifierPrefix + "birthday." + birthday.id.uuidString,
                title: LocalizedString.l(settings.language, en: "Birthday reminder", zh: "生日提醒", ja: "誕生日通知", ko: "생일 알림"),
                body: LocalizedString.l(settings.language, en: "\(birthday.name)'s birthday is coming up.", zh: "\(birthday.name) 的生日快到了。", ja: "\(birthday.name)さんの誕生日が近づいています。", ko: "\(birthday.name)님의 생일이 다가옵니다."),
                kind: .birthday,
                date: adjusted(atHour)
            )
        }
    }

    private func scheduleEnglishReminder(now: Date = Date()) {
        let calendar = Calendar.current
        let requested = calendar.date(
            bySettingHour: settings.reminderHour,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
        let delivery = adjusted(requested)
        var components = DateComponents()
        components.hour = calendar.component(.hour, from: delivery)
        components.minute = calendar.component(.minute, from: delivery)
        let content = makeContent(
            title: LocalizedString.l(settings.language, en: "English check-in", zh: "英语打卡", ja: "英語チェックイン", ko: "영어 학습"),
            body: LocalizedString.l(settings.language, en: "A few minutes is enough to keep your streak.", zh: "学几分钟，也能保持连续记录。", ja: "数分でも継続記録を保てます。", ko: "몇 분만 학습해도 연속 기록을 유지할 수 있습니다."),
            kind: .english
        )
        center.add(UNNotificationRequest(
            identifier: Self.identifierPrefix + "english.daily",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }

    private func addCalendarRequest(identifier: String, title: String, body: String, kind: LocalReminderKind, date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(
            identifier: identifier,
            content: makeContent(title: title, body: body, kind: kind),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        ))
    }

    private func makeContent(title: String, body: String, kind: LocalReminderKind) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["kind": kind.rawValue]
        return content
    }

    private func adjusted(_ date: Date) -> Date {
        Self.adjustedDeliveryDate(
            date,
            quietHoursEnabled: settings.reminderQuietHoursEnabled,
            quietStartHour: settings.reminderQuietStartHour,
            quietEndHour: settings.reminderQuietEndHour
        )
    }

    private func loadAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    private func saveState() {
        guard let data = try? JSONEncoder.reminderEncoder.encode(deliveryState) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private static func loadState(from url: URL) -> ReminderDeliveryState {
        guard let data = try? Data(contentsOf: url) else { return ReminderDeliveryState() }
        return (try? JSONDecoder.reminderDecoder.decode(ReminderDeliveryState.self, from: data)) ?? ReminderDeliveryState()
    }
}

private extension JSONEncoder {
    static var reminderEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var reminderDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
