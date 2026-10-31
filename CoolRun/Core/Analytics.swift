import Foundation
import OSLog
import PostHog

enum AnalyticsEvent: String, CaseIterable {
    case appLaunched = "app_launched"
    case popoverOpened = "popover_opened"
    case settingsOpened = "settings_opened"
    case goldPriceFetched = "gold_price_fetched"
    case goldPriceFetchFailed = "gold_price_fetch_failed"
    case viewTabSwitched = "view_tab_switched"
    case languageChanged = "language_changed"
    case menuBarDisplayModeChanged = "menu_bar_display_mode_changed"
    case holidayDataUpdated = "holiday_data_updated"
    case goldPositionAnalyzed = "gold_position_analyzed"
}

enum Analytics {
    private static let logger = Logger(subsystem: "CoolRun", category: "Analytics")
    private static let state = AnalyticsState()
    private static let disabledEnvironmentKey = "POSTHOG_DISABLED"
    private static let allowedCustomPropertyKeys: Set<String> = [
        "app_version",
        "app_build",
        "os_name",
        "os_version",
        "cpu_arch",
        "chip_model",
        "device_model",
        "tab",
        "language",
        "mode",
        "source",
        "success",
        "error_type",
        "profit_state",
        "profit_percent_bucket",
        "tone",
    ]
    private static let allowedSDKPropertyKeys: Set<String> = [
        "$app_name",
        "$app_version",
        "$app_build",
        "$app_namespace",
        "$device_manufacturer",
        "$device_model",
        "$device_type",
        "$os_name",
        "$os_version",
        "$lib",
        "$lib_version",
        "$is_testflight",
        "$is_sideloaded",
        "$is_emulator",
        "$is_ios_running_on_mac",
        "$is_mac_catalyst_app",
        "$is_identified",
        "$session_id",
    ]
    private static let sensitivePropertyKeys: Set<String> = [
        "email",
        "error_message",
        "file_path",
        "name",
        "profit_loss",
        "profit_percent",
        "token",
    ]

    static var isConfigured: Bool {
        isEnvironmentEnabled && state.isConfigured
    }

    static func configure(projectToken: String, host: String, enabled: Bool) {
        guard isEnvironmentEnabled else {
            logger.info("PostHog analytics disabled by environment")
            return
        }

        let trimmedProjectToken = projectToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectToken.isEmpty else {
            logger.info("PostHog analytics not configured for this build")
            return
        }
        guard trimmedProjectToken.hasPrefix("phc_") else {
            logger.error("PostHog setup skipped because the project token format is invalid")
            return
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hostURL = URL(string: trimmedHost),
              let scheme = hostURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              hostURL.host?.isEmpty == false else {
            logger.error("PostHog setup skipped because the host URL is invalid")
            return
        }

        let config = makePostHogConfiguration(
            projectToken: trimmedProjectToken,
            host: trimmedHost,
            enabled: enabled
        )
        PostHogSDK.shared.setup(config)
        state.markConfigured()

        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    static func setEnabled(_ enabled: Bool) {
        guard isConfigured else { return }
        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    static func capture(
        _ event: AnalyticsEvent,
        properties: [String: Any] = [:],
        minimumInterval: TimeInterval? = nil
    ) {
        guard isEnvironmentEnabled,
              AppSettings.shared.analyticsEnabled,
              state.isConfigured else { return }
        guard state.shouldCapture(event, minimumInterval: minimumInterval) else { return }

        PostHogSDK.shared.capture(event.rawValue, properties: sanitized(properties))
    }

    static func makePostHogConfiguration(
        projectToken: String,
        host: String,
        enabled: Bool
    ) -> PostHogConfig {
        let config = PostHogConfig(projectToken: projectToken, host: host)

        // CoolRun only uses explicit, allowlisted events. Keep every SDK-side automatic
        // collection path disabled so future PostHog defaults cannot widen collection.
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.errorTrackingConfig.autoCapture = false
        config.logs.setBeforeSend { _ in nil }
        config.optOut = !enabled

        // This is a second boundary after call-site sanitization: unknown SDK events are
        // dropped and automatic properties are reduced to the documented safe subset.
        config.setBeforeSend { event in
            guard AnalyticsEvent(rawValue: event.event) != nil else { return nil }
            event.properties = privacySafeEventProperties(event.properties)
            return event
        }

        return config
    }

    private static var isEnvironmentEnabled: Bool {
        ProcessInfo.processInfo.environment[disabledEnvironmentKey] != "1"
    }

    private static func sanitized(_ properties: [String: Any]) -> [String: Any] {
        properties.reduce(into: [:]) { result, pair in
            guard allowedCustomPropertyKeys.contains(pair.key),
                  !sensitivePropertyKeys.contains(pair.key),
                  let value = sanitizedValue(pair.value) else { return }
            result[pair.key] = value
        }
    }

    static func privacySafeEventProperties(_ properties: [String: Any]) -> [String: Any] {
        let allowedKeys = allowedCustomPropertyKeys.union(allowedSDKPropertyKeys)
        var result = properties.reduce(into: [String: Any]()) { sanitized, pair in
            guard allowedKeys.contains(pair.key),
                  !sensitivePropertyKeys.contains(pair.key),
                  let value = sanitizedValue(pair.value) else { return }
            sanitized[pair.key] = value
        }

        // PostHog still receives the request's source IP as transport metadata, but these
        // flags prevent GeoIP enrichment and person-profile creation during ingestion.
        result["$geoip_disable"] = true
        result["$process_person_profile"] = false
        return result
    }

    private static func sanitizedValue(_ value: Any) -> Any? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double.isFinite ? double : nil
        case let float as Float:
            return float.isFinite ? float : nil
        default:
            return nil
        }
    }
}

private final class AnalyticsState: @unchecked Sendable {
    private let lock = NSLock()
    private var configured = false
    private var lastCapturedAt: [AnalyticsEvent: Date] = [:]

    var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return configured
    }

    func markConfigured() {
        lock.lock()
        configured = true
        lock.unlock()
    }

    func shouldCapture(_ event: AnalyticsEvent, minimumInterval: TimeInterval?) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if let minimumInterval,
           let lastCaptured = lastCapturedAt[event],
           now.timeIntervalSince(lastCaptured) < minimumInterval {
            return false
        }

        lastCapturedAt[event] = now
        return true
    }
}
