import Foundation

enum AnalyticsDeviceProperties {
    static var launchProperties: [String: Any] {
        let appVersion = AppVersion.current

        return [
            "app_version": appVersion.marketingVersion,
            "app_build": appVersion.buildVersion,
            "os_name": "macOS",
            "os_version": operatingSystemVersion,
            "cpu_arch": cpuArchitecture,
            "chip_model": chipModel,
            "device_model": sysctlString("hw.model") ?? "unknown",
        ]
    }

    private static var operatingSystemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var cpuArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static var chipModel: String {
        if let brand = sysctlString("machdep.cpu.brand_string"),
           !brand.isEmpty {
            return normalizedChipModel(from: brand)
        }

        return cpuArchitecture == "arm64" ? "Apple Silicon" : "unknown"
    }

    private static func normalizedChipModel(from brand: String) -> String {
        let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }

        if trimmed.hasPrefix("Apple ") {
            return trimmed
        }

        if trimmed.localizedCaseInsensitiveContains("Intel") {
            return "Intel"
        }

        return trimmed
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        return String(cString: buffer)
    }
}
