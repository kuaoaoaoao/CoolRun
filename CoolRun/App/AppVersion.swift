import Foundation

struct AppVersion: Equatable {
    var marketingVersion: String
    var buildVersion: String

    static var current: AppVersion {
        let info = Bundle.main.infoDictionary
        return AppVersion(
            marketingVersion: info?["CFBundleShortVersionString"] as? String ?? "1.0",
            buildVersion: info?["CFBundleVersion"] as? String ?? "1"
        )
    }

    var displayText: String {
        marketingVersion
    }
}
