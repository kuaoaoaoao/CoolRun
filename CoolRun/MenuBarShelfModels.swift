#if os(macOS)
import AppKit
import CoreGraphics
import Foundation

enum MenuBarShelfGroup: String, CaseIterable, Codable, Identifiable, Sendable {
    case pinned
    case hidden
    case alwaysHidden = "always_hidden"

    var id: String { rawValue }

    func displayName(lang: AppLanguage = AppSettings.shared.language) -> String {
        switch self {
        case .pinned:
            LocalizedString.l(lang, en: "Pinned", zh: "常驻", ja: "常に表示", ko: "항상 표시")
        case .hidden:
            LocalizedString.l(lang, en: "Shelf", zh: "收纳", ja: "シェルフ", ko: "보관함")
        case .alwaysHidden:
            LocalizedString.l(lang, en: "Search only", zh: "深度隐藏", ja: "検索のみ", ko: "검색 전용")
        }
    }

    var symbolName: String {
        switch self {
        case .pinned: "pin.fill"
        case .hidden: "rectangle.bottomhalf.inset.filled"
        case .alwaysHidden: "eye.slash.fill"
        }
    }
}

struct MenuBarItemIdentity: Hashable, Codable, Identifiable, Sendable {
    let ownerKey: String
    let itemKey: String
    let occurrence: Int

    var id: String {
        [ownerKey, itemKey, String(occurrence)]
            .map(Self.normalized)
            .joined(separator: "|")
    }

    init(ownerKey: String, itemKey: String, occurrence: Int = 0) {
        self.ownerKey = Self.normalized(ownerKey)
        self.itemKey = Self.normalized(itemKey)
        self.occurrence = max(occurrence, 0)
    }

    nonisolated static func normalized(_ value: String) -> String {
        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? "unknown" : collapsed
    }
}

struct MenuBarWindowSnapshot: Hashable, Sendable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerBundleIdentifier: String?
    let ownerName: String
    let title: String
    let frame: CGRect
    let isOnScreen: Bool
    let layer: Int

    var ownerKey: String {
        ownerBundleIdentifier?.isEmpty == false ? ownerBundleIdentifier! : ownerName
    }

    var itemKey: String {
        title.isEmpty ? "status-item" : title
    }
}

struct MenuBarItemSnapshot: Identifiable, Hashable, Sendable {
    let identity: MenuBarItemIdentity
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerBundleIdentifier: String?
    let ownerName: String
    let title: String
    let displayName: String
    let frame: CGRect
    let isOnScreen: Bool
    let canMove: Bool

    var id: String { identity.id }

    func detailName(lang: AppLanguage = AppSettings.shared.language) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if MenuBarApplicationMetadata.isUsefulUserFacingName(trimmedTitle),
           trimmedTitle.localizedCaseInsensitiveCompare(displayName) != .orderedSame,
           trimmedTitle.localizedCaseInsensitiveCompare(ownerName) != .orderedSame {
            return trimmedTitle
        }

        let generic = LocalizedString.l(
            lang,
            en: "Menu bar item",
            zh: "菜单栏图标",
            ja: "メニューバー項目",
            ko: "메뉴 막대 항목"
        )
        return identity.occurrence > 0 ? "\(generic) \(identity.occurrence + 1)" : generic
    }

    func replacingFrame(_ newFrame: CGRect, isOnScreen: Bool) -> MenuBarItemSnapshot {
        MenuBarItemSnapshot(
            identity: identity,
            windowID: windowID,
            ownerPID: ownerPID,
            ownerBundleIdentifier: ownerBundleIdentifier,
            ownerName: ownerName,
            title: title,
            displayName: displayName,
            frame: newFrame,
            isOnScreen: isOnScreen,
            canMove: canMove
        )
    }
}

enum MenuBarRunningApplicationKind: Int, Hashable, Sendable {
    case regular
    case accessory
    case prohibited
}

struct MenuBarRunningApplicationSnapshot: Hashable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let bundleURL: URL?
    let kind: MenuBarRunningApplicationKind
    let isTerminated: Bool

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        localizedName: String?,
        bundleURL: URL?,
        kind: MenuBarRunningApplicationKind,
        isTerminated: Bool = false
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.bundleURL = bundleURL
        self.kind = kind
        self.isTerminated = isTerminated
    }

    init(_ application: NSRunningApplication) {
        processIdentifier = application.processIdentifier
        bundleIdentifier = application.bundleIdentifier
        localizedName = application.localizedName
        bundleURL = application.bundleURL
        kind = switch application.activationPolicy {
        case .regular: .regular
        case .accessory: .accessory
        default: .prohibited
        }
        isTerminated = application.isTerminated
    }
}

struct MenuBarBackgroundApplicationSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let displayName: String
    let bundleURL: URL?
}

enum MenuBarBackgroundApplicationCatalog {
    @MainActor
    static func applications(
        from runningApplications: [MenuBarRunningApplicationSnapshot],
        excluding statusItems: [MenuBarItemSnapshot],
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        currentBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> [MenuBarBackgroundApplicationSnapshot] {
        let representedKeys = Set(statusItems.flatMap(applicationKeys(for:)))
        var resultByID = [String: MenuBarBackgroundApplicationSnapshot]()
        var selectedKindByID = [String: MenuBarRunningApplicationKind]()

        for application in runningApplications {
            guard application.processIdentifier > 0,
                  application.processIdentifier != currentProcessIdentifier,
                  !application.isTerminated,
                  application.kind != .prohibited else {
                continue
            }

            let outerURL = application.bundleURL.flatMap(MenuBarApplicationMetadata.outermostApplicationURL)
            let outerBundleIdentifier = outerURL
                .flatMap(Bundle.init(url:))?
                .bundleIdentifier
            let bundleIdentifier = outerBundleIdentifier ?? application.bundleIdentifier
            let normalizedBundleIdentifier = bundleIdentifier?.lowercased()
            guard normalizedBundleIdentifier != currentBundleIdentifier?.lowercased(),
                  !(normalizedBundleIdentifier?.hasPrefix("com.apple.") ?? false),
                  !isSystemApplication(outerURL ?? application.bundleURL) else {
                continue
            }

            let keys = applicationKeys(bundleIdentifier: bundleIdentifier, bundleURL: outerURL)
            guard representedKeys.isDisjoint(with: keys) else { continue }

            let displayName = MenuBarApplicationMetadata.displayName(
                localizedName: application.localizedName,
                bundleIdentifier: bundleIdentifier,
                applicationURL: outerURL ?? application.bundleURL
            )
            guard MenuBarApplicationMetadata.isUsefulUserFacingName(displayName),
                  !isTechnicalHelperName(displayName) else {
                continue
            }

            let id = outerURL.map { "path:\($0.standardizedFileURL.path.lowercased())" }
                ?? normalizedBundleIdentifier.map { "bundle:\($0)" }
                ?? "pid:\(application.processIdentifier)"
            let snapshot = MenuBarBackgroundApplicationSnapshot(
                id: id,
                processIdentifier: application.processIdentifier,
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                bundleURL: outerURL ?? application.bundleURL
            )
            if resultByID[id] != nil {
                if application.kind == .regular, selectedKindByID[id] != .regular {
                    resultByID[id] = snapshot
                    selectedKindByID[id] = application.kind
                }
            } else {
                resultByID[id] = snapshot
                selectedKindByID[id] = application.kind
            }
        }

        return resultByID.values.sorted {
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private static func applicationKeys(for item: MenuBarItemSnapshot) -> [String] {
        let url = MenuBarApplicationMetadata.applicationURL(
            ownerPID: item.ownerPID,
            bundleIdentifier: item.ownerBundleIdentifier
        )
        return Array(applicationKeys(bundleIdentifier: item.ownerBundleIdentifier, bundleURL: url))
    }

    private static func applicationKeys(bundleIdentifier: String?, bundleURL: URL?) -> Set<String> {
        var keys = Set<String>()
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            keys.insert("bundle:\(bundleIdentifier.lowercased())")
        }
        if let path = bundleURL?.standardizedFileURL.path.lowercased(), !path.isEmpty {
            keys.insert("path:\(path)")
        }
        return keys
    }

    private static func isSystemApplication(_ url: URL?) -> Bool {
        guard let path = url?.standardizedFileURL.path.lowercased() else { return false }
        return path.hasPrefix("/system/") || path.hasPrefix("/usr/")
    }

    private static func isTechnicalHelperName(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.hasSuffix(" helper") ||
            value.hasSuffix(" renderer") ||
            value.hasSuffix(" gpu") ||
            value.contains("helper (renderer)") ||
            value.contains("helper (gpu)")
    }
}

enum MenuBarDiscoveryMode: Equatable, Sendable {
    case full
    case limited(reason: String)
}

struct MenuBarDiscoverySnapshot: Equatable, Sendable {
    let items: [MenuBarItemSnapshot]
    let mode: MenuBarDiscoveryMode
    let refreshedAt: Date
}

enum MenuBarShelfOperationState: Equatable, Sendable {
    case idle
    case refreshing
    case moving(itemID: String)
    case activating(itemID: String)
    case failed(message: String)
}

enum MenuBarItemReconciler {
    @MainActor
    static func items(from windows: [MenuBarWindowSnapshot]) -> [MenuBarItemSnapshot] {
        var seenWindowIDs = Set<CGWindowID>()
        let ordered = windows
            .filter(MenuBarItemPolicy.shouldInclude)
            .filter { seenWindowIDs.insert($0.windowID).inserted }
            .sorted {
                if $0.frame.maxX == $1.frame.maxX {
                    return $0.windowID < $1.windowID
                }
                return $0.frame.maxX < $1.frame.maxX
            }
        var occurrences = [String: Int]()

        return ordered.map { window in
            let baseOwner = MenuBarItemIdentity.normalized(window.ownerKey)
            let baseItem = MenuBarItemIdentity.normalized(window.itemKey)
            let base = "\(baseOwner)|\(baseItem)"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1

            let hostApplication = NSRunningApplication(processIdentifier: window.ownerPID)
            let representedBundleID = MenuBarHostedStatusItemResolver.representedBundleIdentifier(for: window)
            let bundleID = representedBundleID ?? window.ownerBundleIdentifier ?? hostApplication?.bundleIdentifier
            let representedApplication = bundleID.flatMap(MenuBarHostedStatusItemResolver.runningApplication)
            let displayName = MenuBarApplicationMetadata.displayName(
                for: window,
                representedBundleIdentifier: representedBundleID,
                runningApplication: representedApplication ?? hostApplication
            )

            return MenuBarItemSnapshot(
                identity: MenuBarItemIdentity(
                    ownerKey: bundleID ?? window.ownerName,
                    itemKey: window.itemKey,
                    occurrence: occurrence
                ),
                windowID: window.windowID,
                ownerPID: window.ownerPID,
                ownerBundleIdentifier: bundleID,
                ownerName: representedBundleID == nil ? window.ownerName : displayName,
                title: window.title,
                displayName: displayName,
                frame: window.frame,
                isOnScreen: window.isOnScreen,
                canMove: window.ownerPID > 0
            )
        }
    }
}

enum MenuBarHostedStatusItemResolver {
    nonisolated private static let hostedBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
    ]

    nonisolated static func representedBundleIdentifier(for window: MenuBarWindowSnapshot) -> String? {
        let hostBundleIdentifier = (window.ownerBundleIdentifier ?? "").lowercased()
        let ownerKey = window.ownerName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        guard hostedBundleIdentifiers.contains(hostBundleIdentifier) ||
                ownerKey == "controlcenter" || ownerKey == "controlcentre" else {
            return nil
        }
        return thirdPartyBundleIdentifier(from: window.title)
    }

    nonisolated static func thirdPartyBundleIdentifier(from value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              parts.allSatisfy({
                  !$0.isEmpty && $0.allSatisfy {
                      $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
                  }
              }) else {
            return nil
        }

        let normalized = candidate.lowercased()
        guard !normalized.hasPrefix("com.apple."),
              !normalized.hasPrefix("apple."),
              normalized != "kuao.coolrun",
              !normalized.hasPrefix("coolrun.menubarshelf") else {
            return nil
        }
        return candidate
    }

    static func runningApplication(for bundleIdentifier: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .sorted { lhs, rhs in
                if lhs.activationPolicy == rhs.activationPolicy {
                    return lhs.processIdentifier < rhs.processIdentifier
                }
                return lhs.activationPolicy == .regular
            }
            .first
    }

    static func applicationProcessIdentifier(for bundleIdentifier: String?) -> pid_t? {
        guard let bundleIdentifier else { return nil }
        return runningApplication(for: bundleIdentifier)?.processIdentifier
    }
}

enum MenuBarItemPolicy {
    nonisolated private static let excludedBundlePrefixes = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.windowserver",
    ]

    nonisolated private static let excludedOwnerKeys: Set<String> = [
        "controlcenter",
        "systemuiserver",
        "windowserver",
        "notificationcenter",
    ]

    nonisolated static func shouldInclude(_ window: MenuBarWindowSnapshot) -> Bool {
        guard window.ownerPID > 0, window.frame.width > 0, window.frame.height > 0 else {
            return false
        }

        if MenuBarHostedStatusItemResolver.representedBundleIdentifier(for: window) != nil {
            return true
        }

        let bundleID = (window.ownerBundleIdentifier ?? "").lowercased()
        if excludedBundlePrefixes.contains(where: bundleID.hasPrefix) {
            return false
        }

        let ownerKey = window.ownerName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        if excludedOwnerKeys.contains(ownerKey) {
            return false
        }

        if bundleID.hasPrefix("com.apple."),
           let bundlePath = NSRunningApplication(processIdentifier: window.ownerPID)?.bundleURL?
            .standardizedFileURL.path.lowercased(),
           bundlePath.hasPrefix("/system/") {
            return false
        }

        return true
    }
}

enum MenuBarApplicationMetadata {
    static func displayName(
        for window: MenuBarWindowSnapshot,
        representedBundleIdentifier: String? = nil,
        runningApplication: NSRunningApplication? = nil
    ) -> String {
        let app = runningApplication ?? NSRunningApplication(processIdentifier: window.ownerPID)
        let bundleID = representedBundleIdentifier ?? window.ownerBundleIdentifier ?? app?.bundleIdentifier
        let applicationURL = applicationURL(ownerPID: window.ownerPID, bundleIdentifier: bundleID)
        let applicationName = app?.bundleIdentifier?.localizedCaseInsensitiveCompare(bundleID ?? "") == .orderedSame
            ? app?.localizedName
            : nil
        let ownerName = representedBundleIdentifier == nil ? window.ownerName : nil

        let candidates: [String?] = [
            localizedBundleName(at: applicationURL),
            applicationName,
            applicationURL.map { FileManager.default.displayName(atPath: $0.path) },
            ownerName,
        ]
        if let resolved = candidates
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: isUsefulUserFacingName) {
            return resolved.removingApplicationExtension
        }

        if let bundleID {
            let normalizedBundleID = bundleID.lowercased()
            if normalizedBundleID.contains("xinwechat") {
                return "WeChat"
            }
            if normalizedBundleID == "com.tencent.qq" || normalizedBundleID.contains("qqmac") {
                return "QQ"
            }
        }
        if let bundleID, let lastComponent = bundleID.split(separator: ".").last, !lastComponent.isEmpty {
            return String(lastComponent)
        }
        return LocalizedString.l(
            AppSettings.shared.language,
            en: "Unknown application",
            zh: "未知应用",
            ja: "不明なアプリ",
            ko: "알 수 없는 앱"
        )
    }

    static func displayName(
        localizedName: String?,
        bundleIdentifier: String?,
        applicationURL: URL?
    ) -> String {
        let candidates: [String?] = [
            localizedBundleName(at: applicationURL),
            localizedName,
            applicationURL.map { FileManager.default.displayName(atPath: $0.path) },
        ]
        if let resolved = candidates
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: isUsefulUserFacingName) {
            return resolved.removingApplicationExtension
        }

        if let bundleIdentifier {
            let normalized = bundleIdentifier.lowercased()
            if normalized.contains("xinwechat") { return "WeChat" }
            if normalized == "com.tencent.qq" || normalized.contains("qqmac") { return "QQ" }
            if let component = bundleIdentifier.split(separator: ".").last, !component.isEmpty {
                return String(component)
            }
        }
        return LocalizedString.l(
            AppSettings.shared.language,
            en: "Unknown application",
            zh: "未知应用",
            ja: "不明なアプリ",
            ko: "알 수 없는 앱"
        )
    }

    static func applicationURL(ownerPID: pid_t, bundleIdentifier: String?) -> URL? {
        let app = NSRunningApplication(processIdentifier: ownerPID)
        if let bundleIdentifier {
            if app?.bundleIdentifier?.localizedCaseInsensitiveCompare(bundleIdentifier) == .orderedSame,
               let outermost = app?.bundleURL.flatMap(outermostApplicationURL) {
                return outermost
            }
            if let running = MenuBarHostedStatusItemResolver.runningApplication(for: bundleIdentifier),
               let outermost = running.bundleURL.flatMap(outermostApplicationURL) {
                return outermost
            }
            if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return outermostApplicationURL(startingAt: installed) ?? installed
            }
        }
        if let outermost = app?.bundleURL.flatMap(outermostApplicationURL) {
            return outermost
        }
        return nil
    }

    nonisolated static func isUsefulUserFacingName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowercased = trimmed.lowercased()
        if lowercased == "unknown" || lowercased == "status-item" || lowercased == "status item" {
            return false
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count >= 3,
           parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }) {
            return false
        }
        return true
    }

    private static func localizedBundleName(at url: URL?) -> String? {
        guard let url, let bundle = Bundle(url: url) else { return nil }
        let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
    }

    nonisolated static func outermostApplicationURL(startingAt url: URL) -> URL? {
        var current = url.standardizedFileURL
        var outermost: URL?
        while current.path != "/" {
            if current.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame {
                outermost = current
            }
            current.deleteLastPathComponent()
        }
        return outermost
    }
}

enum MenuBarShelfGeometry {
    static func isOperable(_ frame: CGRect, on screen: CGRect, rightSafeArea: CGRect? = nil) -> Bool {
        guard frame.width > 0, frame.height > 0, screen.intersects(frame) else { return false }
        if let rightSafeArea {
            return rightSafeArea.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        return frame.minX >= screen.minX && frame.maxX <= screen.maxX
    }

    static func revealPoint(
        itemWidth: CGFloat,
        menuBarFrame: CGRect,
        occupiedFrames: [CGRect],
        minimumX: CGFloat
    ) -> CGPoint? {
        guard itemWidth > 0, menuBarFrame.width >= itemWidth else { return nil }
        let sorted = occupiedFrames
            .filter { $0.intersects(menuBarFrame) }
            .sorted { $0.minX < $1.minX }

        var candidateX = max(minimumX, menuBarFrame.minX)
        for frame in sorted {
            if candidateX + itemWidth <= frame.minX {
                return CGPoint(x: candidateX, y: menuBarFrame.midY)
            }
            candidateX = max(candidateX, frame.maxX)
        }
        guard candidateX + itemWidth <= menuBarFrame.maxX else { return nil }
        return CGPoint(x: candidateX, y: menuBarFrame.midY)
    }
}

private extension ComparisonResult {
    var isOrderedSame: Bool { self == .orderedSame }
}

private extension String {
    var removingApplicationExtension: String {
        hasSuffix(".app") ? String(dropLast(4)) : self
    }
}
#endif
