#if os(macOS)
import AppKit
import CoreGraphics
import Darwin
import Foundation

struct MenuBarWindowBridge {
    struct WindowListResult: Sendable {
        let windows: [MenuBarWindowSnapshot]
        let usedPrivateDiscovery: Bool
        let limitationReason: String?
    }

    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias MenuBarListFunction = @convention(c) (
        Int32,
        Int32,
        Int32,
        UnsafeMutablePointer<CGWindowID>,
        UnsafeMutablePointer<Int32>
    ) -> Int32
    private typealias WindowFrameFunction = @convention(c) (
        Int32,
        CGWindowID,
        UnsafeMutablePointer<CGRect>
    ) -> Int32

    private let libraryHandle: UnsafeMutableRawPointer?
    private let mainConnection: MainConnectionFunction?
    private let menuBarList: MenuBarListFunction?
    private let windowFrame: WindowFrameFunction?
    private let accessibilityResolver: MenuBarAccessibilityResolver

    init(accessibilityResolver: MenuBarAccessibilityResolver = MenuBarAccessibilityResolver()) {
        let handle = dlopen(nil, RTLD_LAZY | RTLD_LOCAL)
        self.libraryHandle = handle
        self.mainConnection = Self.function(named: "CGSMainConnectionID", handle: handle)
        self.menuBarList = Self.function(named: "CGSGetProcessMenuBarWindowList", handle: handle)
        self.windowFrame = Self.function(named: "CGSGetScreenRectForWindow", handle: handle)
        self.accessibilityResolver = accessibilityResolver
    }

    func statusWindows(excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> WindowListResult {
        if let privateIDs = privateMenuBarWindowIDs(), !privateIDs.isEmpty {
            let rawWindows = descriptions(for: privateIDs).filter { $0.ownerPID != excludingPID }
            let windows = accessibilityResolver.enrich(
                rawWindows,
                excludingPID: excludingPID,
                currentBundleIdentifier: Bundle.main.bundleIdentifier
            )
            if !windows.isEmpty {
                return WindowListResult(windows: windows, usedPrivateDiscovery: true, limitationReason: nil)
            }
        }

        let publicWindows = publicOnScreenStatusWindows().filter { $0.ownerPID != excludingPID }
        return WindowListResult(
            windows: publicWindows,
            usedPrivateDiscovery: false,
            limitationReason: LocalizedString.l(
                AppSettings.shared.language,
                en: "Only currently visible menu bar items can be discovered on this macOS version.",
                zh: "当前 macOS 版本只能发现屏幕上可见的菜单栏图标。",
                ja: "この macOS では、現在表示中のメニューバー項目のみ検出できます。",
                ko: "이 macOS에서는 현재 표시된 메뉴 막대 항목만 찾을 수 있습니다."
            )
        )
    }

    func currentFrame(for windowID: CGWindowID) -> CGRect? {
        if let mainConnection, let windowFrame {
            var frame = CGRect.zero
            if windowFrame(mainConnection(), windowID, &frame) == 0, !frame.isNull, !frame.isEmpty {
                return frame
            }
        }
        return descriptions(for: [windowID]).first?.frame
    }

    func onScreenWindows() -> [MenuBarWindowSnapshot] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }
        return info.compactMap(Self.window(from:))
    }

    func statusWindowID(
        matchingQuartzFrame frame: CGRect,
        preferredTitle: String? = nil
    ) -> CGWindowID? {
        let windows: [MenuBarWindowSnapshot]
        if let privateIDs = privateMenuBarWindowIDs(), !privateIDs.isEmpty {
            windows = descriptions(for: privateIDs)
        } else {
            windows = publicOnScreenStatusWindows()
        }
        return Self.statusWindowID(
            matchingQuartzFrame: frame,
            preferredTitle: preferredTitle,
            in: windows
        )
    }

    /// AppKit can return a synthetic `NSWindow.windowNumber` for status items on
    /// newer macOS releases. Those values do not necessarily fit in the UInt32
    /// range used by WindowServer, so a checked conversion is required.
    nonisolated static func windowID(fromAppKitWindowNumber windowNumber: Int) -> CGWindowID? {
        guard windowNumber > 0 else { return nil }
        return CGWindowID(exactly: windowNumber)
    }

    nonisolated static func statusWindowID(
        matchingQuartzFrame frame: CGRect,
        preferredTitle: String?,
        in windows: [MenuBarWindowSnapshot]
    ) -> CGWindowID? {
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let candidates = windows.filter { $0.layer == statusLayer }
        if let preferredTitle {
            let titled = candidates.filter {
                $0.title.localizedCaseInsensitiveCompare(preferredTitle) == .orderedSame
            }
            if let match = closestWindow(to: frame, in: titled, requireFrameMatch: false) {
                return match.windowID
            }
        }
        return closestWindow(to: frame, in: candidates, requireFrameMatch: true)?.windowID
    }

    private nonisolated static func closestWindow(
        to frame: CGRect,
        in windows: [MenuBarWindowSnapshot],
        requireFrameMatch: Bool
    ) -> MenuBarWindowSnapshot? {
        let scored = windows.map { window in
            let centerDistance = abs(window.frame.midX - frame.midX) + abs(window.frame.midY - frame.midY)
            let sizeDistance = abs(window.frame.width - frame.width) + abs(window.frame.height - frame.height)
            return (window: window, score: centerDistance + sizeDistance)
        }.sorted {
            if $0.score == $1.score { return $0.window.windowID < $1.window.windowID }
            return $0.score < $1.score
        }
        guard let closest = scored.first else { return nil }
        if requireFrameMatch {
            let centerTolerance: CGFloat = 3
            let sizeTolerance: CGFloat = 3
            guard abs(closest.window.frame.midX - frame.midX) <= centerTolerance,
                  abs(closest.window.frame.midY - frame.midY) <= centerTolerance,
                  abs(closest.window.frame.width - frame.width) <= sizeTolerance,
                  abs(closest.window.frame.height - frame.height) <= sizeTolerance else {
                return nil
            }
        }
        return closest.window
    }

    private func privateMenuBarWindowIDs() -> [CGWindowID]? {
        guard let mainConnection, let menuBarList else { return nil }
        var ids = [CGWindowID](repeating: 0, count: 4_096)
        var realCount: Int32 = 0
        let result = menuBarList(mainConnection(), 0, Int32(ids.count), &ids, &realCount)
        guard result == 0, realCount > 0, realCount <= ids.count else { return nil }
        return Array(ids.prefix(Int(realCount)))
    }

    private func publicOnScreenStatusWindows() -> [MenuBarWindowSnapshot] {
        onScreenWindows().filter { $0.layer == Int(CGWindowLevelForKey(.statusWindow)) }
    }

    private func descriptions(for windowIDs: [CGWindowID]) -> [MenuBarWindowSnapshot] {
        guard !windowIDs.isEmpty else { return [] }
        var values = windowIDs.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        return values.withUnsafeMutableBufferPointer { buffer in
            guard let array = CFArrayCreate(
                kCFAllocatorDefault,
                buffer.baseAddress,
                buffer.count,
                nil
            ), let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[CFString: Any]] else {
                return []
            }
            return descriptions.compactMap(Self.window(from:))
        }
    }

    private nonisolated static func window(from info: [CFString: Any]) -> MenuBarWindowSnapshot? {
        guard
            let windowID = number(info[kCGWindowNumber]).map({ CGWindowID($0.uint32Value) }),
            let ownerPID = number(info[kCGWindowOwnerPID]).map({ pid_t($0.int32Value) }),
            let bounds = info[kCGWindowBounds] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds),
            let layer = number(info[kCGWindowLayer])?.intValue
        else {
            return nil
        }

        let app = NSRunningApplication(processIdentifier: ownerPID)
        return MenuBarWindowSnapshot(
            windowID: windowID,
            ownerPID: ownerPID,
            ownerBundleIdentifier: app?.bundleIdentifier,
            ownerName: (info[kCGWindowOwnerName] as? String) ?? app?.localizedName ?? "Unknown",
            title: (info[kCGWindowName] as? String) ?? "",
            frame: frame,
            isOnScreen: number(info[kCGWindowIsOnscreen])?.boolValue ?? false,
            layer: layer
        )
    }

    private nonisolated static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private nonisolated static func function<T>(named name: String, handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}
#endif
