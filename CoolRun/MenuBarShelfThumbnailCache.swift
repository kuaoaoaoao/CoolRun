#if os(macOS)
import AppKit
import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class MenuBarShelfThumbnailCache: ObservableObject {
    static let shared = MenuBarShelfThumbnailCache()

    @Published private(set) var images = [String: NSImage]()

    private let permissions: MenuBarShelfPermissions
    private var captureTask: Task<Void, Never>?

    init() {
        self.permissions = .shared
    }

    init(permissions: MenuBarShelfPermissions) {
        self.permissions = permissions
    }

    func image(for item: MenuBarItemSnapshot) -> NSImage? {
        images[item.identity.id] ?? applicationIcon(for: item)
    }

    func image(for application: MenuBarBackgroundApplicationSnapshot) -> NSImage? {
        guard let bundleURL = application.bundleURL else { return nil }
        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        image.size = NSSize(width: 24, height: 24)
        return image
    }

    func refresh(items: [MenuBarItemSnapshot]) {
        captureTask?.cancel()
        guard permissions.hasScreenCapture else {
            images.removeAll()
            return
        }
        captureTask = Task { [weak self] in
            guard let self else { return }
            let captured = await Self.capture(items: items)
            guard !Task.isCancelled, permissions.hasScreenCapture else { return }
            images = captured
        }
    }

    func removeAll() {
        captureTask?.cancel()
        captureTask = nil
        images.removeAll()
    }

    private func applicationIcon(for item: MenuBarItemSnapshot) -> NSImage? {
        guard let bundleURL = MenuBarApplicationMetadata.applicationURL(
            ownerPID: item.ownerPID,
            bundleIdentifier: item.ownerBundleIdentifier
        ) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        image.size = NSSize(width: 24, height: 24)
        return image
    }

    private static func capture(items: [MenuBarItemSnapshot]) async -> [String: NSImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        ) else {
            return [:]
        }
        let itemsByWindow = Dictionary(uniqueKeysWithValues: items.map { ($0.windowID, $0) })
        var result = [String: NSImage]()
        for window in content.windows {
            guard !Task.isCancelled else { return result }
            guard let item = itemsByWindow[window.windowID], window.frame.width > 0, window.frame.height > 0 else {
                continue
            }
            let configuration = SCStreamConfiguration()
            configuration.width = max(Int(window.frame.width * 2), 1)
            configuration.height = max(Int(window.frame.height * 2), 1)
            configuration.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            guard let cgImage = try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) else {
                continue
            }
            result[item.identity.id] = NSImage(
                cgImage: cgImage,
                size: NSSize(width: window.frame.width, height: window.frame.height)
            )
        }
        return result
    }
}
#endif
