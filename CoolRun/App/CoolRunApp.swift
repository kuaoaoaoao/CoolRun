//
//  CoolRunApp.swift
//  CoolRun
//
//  Created by kuao on 2026/5/21.
//

import SwiftUI

private enum RuntimeConfiguration {
    static let defaultPostHogHost = "https://us.i.posthog.com"

    static var postHogProjectToken: String {
        if ProcessInfo.processInfo.environment["POSTHOG_DISABLED"] == "1" {
            return ""
        }
        return value(environmentKey: "POSTHOG_API_KEY", infoKey: "POSTHOG_API_KEY") ?? ""
    }

    static var postHogHost: String {
        value(environmentKey: "POSTHOG_HOST", infoKey: "POSTHOG_HOST") ?? defaultPostHogHost
    }

    private static func value(environmentKey: String, infoKey: String) -> String? {
        let environmentValue = ProcessInfo.processInfo.environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty {
            return environmentValue
        }

        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bundleValue?.isEmpty == false ? bundleValue : nil
    }
}

@main
struct CoolRunApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    init() {
        CloudSyncStore.shared.start()
        CloudSyncStore.shared.pushBirthdaysFromLocalDefaults()
        LocalReminderCenter.shared.start()
        let projectToken = RuntimeConfiguration.postHogProjectToken
        if projectToken.isEmpty {
            // fork / 本地构建没有令牌时强制保持关闭，之后配置令牌也需要用户重新主动开启。
            AppSettings.shared.analyticsEnabled = false
        }
        Analytics.configure(
            projectToken: projectToken,
            host: RuntimeConfiguration.postHogHost,
            enabled: AppSettings.shared.analyticsEnabled
        )
    }

    var body: some Scene {
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
