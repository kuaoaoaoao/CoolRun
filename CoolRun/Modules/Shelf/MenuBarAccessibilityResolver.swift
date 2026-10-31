#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct MenuBarAccessibilityHit: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let label: String?
}

/// Resolves the real application behind menu bar windows hosted by Control Center.
///
/// macOS 26 can expose third-party status items as anonymous Control Center windows.
/// Accessibility hit testing still reports the represented menu-extra element, so
/// the result is cached by WindowServer window ID and used to enrich those windows.
final class MenuBarAccessibilityResolver {
    typealias HitTest = (CGPoint) -> MenuBarAccessibilityHit?

    private let isTrusted: () -> Bool
    private let hitTest: HitTest
    private var cachedHits = [CGWindowID: MenuBarAccessibilityHit]()

    init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        hitTest: HitTest? = nil
    ) {
        self.isTrusted = isTrusted
        self.hitTest = hitTest ?? Self.makeLiveHitTest()
    }

    func enrich(
        _ windows: [MenuBarWindowSnapshot],
        excludingPID: pid_t,
        currentBundleIdentifier: String?
    ) -> [MenuBarWindowSnapshot] {
        let liveWindowIDs = Set(windows.map(\.windowID))
        cachedHits = cachedHits.filter { liveWindowIDs.contains($0.key) }

        let normalizedCurrentBundleID = currentBundleIdentifier?.lowercased()
        return windows.map { window in
            guard Self.isHostedSystemStatusWindow(window) else { return window }

            if let representedBundleID = MenuBarHostedStatusItemResolver
                .thirdPartyBundleIdentifier(from: window.title) {
                let hit = MenuBarAccessibilityHit(
                    processIdentifier: MenuBarHostedStatusItemResolver
                        .applicationProcessIdentifier(for: representedBundleID) ?? 0,
                    bundleIdentifier: representedBundleID,
                    label: nil
                )
                cachedHits[window.windowID] = hit
                return window
            }

            if let cached = cachedHits[window.windowID],
               Self.isUsable(
                   cached,
                   excludingPID: excludingPID,
                   currentBundleIdentifier: normalizedCurrentBundleID
               ) {
                return Self.enrich(window, with: cached)
            }

            guard isTrusted(), window.isOnScreen else { return window }
            let hits = Self.samplePoints(in: window.frame).compactMap(hitTest)
                .filter {
                    Self.isUsable(
                        $0,
                        excludingPID: excludingPID,
                        currentBundleIdentifier: normalizedCurrentBundleID
                    )
                }
            guard let resolved = Self.mostFrequentUnambiguousHit(in: hits) else {
                return window
            }

            cachedHits[window.windowID] = resolved
            return Self.enrich(window, with: resolved)
        }
    }

    private static func enrich(
        _ window: MenuBarWindowSnapshot,
        with hit: MenuBarAccessibilityHit
    ) -> MenuBarWindowSnapshot {
        MenuBarWindowSnapshot(
            windowID: window.windowID,
            ownerPID: window.ownerPID,
            ownerBundleIdentifier: window.ownerBundleIdentifier,
            ownerName: window.ownerName,
            title: hit.bundleIdentifier,
            frame: window.frame,
            isOnScreen: window.isOnScreen,
            layer: window.layer
        )
    }

    private static func isHostedSystemStatusWindow(_ window: MenuBarWindowSnapshot) -> Bool {
        guard window.layer == Int(CGWindowLevelForKey(.statusWindow)) else { return false }
        let bundleID = (window.ownerBundleIdentifier ?? "").lowercased()
        if bundleID == "com.apple.controlcenter" || bundleID == "com.apple.systemuiserver" {
            return true
        }
        let ownerKey = window.ownerName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return ownerKey == "controlcenter" || ownerKey == "controlcentre" || ownerKey == "systemuiserver"
    }

    private static func isUsable(
        _ hit: MenuBarAccessibilityHit,
        excludingPID: pid_t,
        currentBundleIdentifier: String?
    ) -> Bool {
        let bundleID = hit.bundleIdentifier.lowercased()
        return hit.processIdentifier != excludingPID &&
            !bundleID.isEmpty &&
            bundleID != currentBundleIdentifier &&
            !bundleID.hasPrefix("com.apple.") &&
            bundleID != "apple" &&
            bundleID != "unknown"
    }

    private static func samplePoints(in frame: CGRect) -> [CGPoint] {
        guard frame.width > 0, frame.height > 0 else { return [] }
        let inset = min(CGFloat(3), frame.width / 2)
        let startX = frame.minX + inset
        let endX = frame.maxX - inset
        let step = frame.width <= 44 ? CGFloat(4) : CGFloat(6)
        var points = [CGPoint]()
        var x = startX
        while x <= endX {
            points.append(CGPoint(x: x, y: frame.midY))
            x += step
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if !points.contains(where: { abs($0.x - center.x) < 1 }) {
            points.append(center)
        }
        return points
    }

    private static func mostFrequentUnambiguousHit(
        in hits: [MenuBarAccessibilityHit]
    ) -> MenuBarAccessibilityHit? {
        guard !hits.isEmpty else { return nil }
        let groups = Dictionary(grouping: hits) { $0.bundleIdentifier.lowercased() }
            .values
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs[0].bundleIdentifier < rhs[0].bundleIdentifier
                }
                return lhs.count > rhs.count
            }
        guard let first = groups.first,
              groups.count == 1 || first.count > groups[1].count else {
            return nil
        }
        return first[0]
    }

    private static func makeLiveHitTest() -> HitTest {
        let systemWideElement = AXUIElementCreateSystemWide()
        return { point in
            var element: AXUIElement?
            let error = AXUIElementCopyElementAtPosition(
                systemWideElement,
                Float(point.x),
                Float(point.y),
                &element
            )
            guard error == .success,
                  let element,
                  let menuExtra = menuExtraElement(startingAt: element) else {
                return nil
            }

            var processIdentifier: pid_t = 0
            guard AXUIElementGetPid(menuExtra, &processIdentifier) == .success,
                  processIdentifier > 0,
                  let application = NSRunningApplication(processIdentifier: processIdentifier),
                  !application.isTerminated else {
                return nil
            }

            let identifier = stringAttribute(kAXIdentifierAttribute as CFString, from: menuExtra)
            let title = stringAttribute(kAXTitleAttribute as CFString, from: menuExtra)
            let description = stringAttribute(kAXDescriptionAttribute as CFString, from: menuExtra)
            let representedBundleID = [identifier, title, description]
                .compactMap { $0 }
                .compactMap(MenuBarHostedStatusItemResolver.thirdPartyBundleIdentifier)
                .first

            let outerApplicationURL = application.bundleURL
                .flatMap(MenuBarApplicationMetadata.outermostApplicationURL)
            let applicationBundleID = outerApplicationURL
                .flatMap(Bundle.init(url:))?
                .bundleIdentifier ?? application.bundleIdentifier
            guard let bundleIdentifier = representedBundleID ?? applicationBundleID else {
                return nil
            }

            let label = [title, description]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return MenuBarAccessibilityHit(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                label: label
            )
        }
    }

    private static func menuExtraElement(startingAt element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<5 {
            guard let candidate = current else { return nil }
            let role = stringAttribute(kAXRoleAttribute as CFString, from: candidate)
            let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: candidate)
            let isMenuExtra = subrole == "AXMenuExtra" || subrole == nil || subrole?.isEmpty == true
            if role == (kAXMenuBarItemRole as String),
               isMenuExtra {
                return candidate
            }
            current = elementAttribute(kAXParentAttribute as CFString, from: candidate)
        }
        return nil
    }

    private static func stringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        if let string = value as? String { return string }
        if let attributedString = value as? NSAttributedString { return attributedString.string }
        return nil
    }

    private static func elementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}
#endif
