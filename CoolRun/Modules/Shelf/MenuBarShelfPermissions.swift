#if os(macOS)
import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Security

struct MenuBarShelfApplicationIdentity: Equatable {
    let bundlePath: String
    let usesAdHocSignature: Bool

    nonisolated static var current: Self {
        Self(
            bundlePath: Bundle.main.bundleURL.standardizedFileURL.path,
            usesAdHocSignature: currentCodeUsesAdHocSignature()
        )
    }

    nonisolated private static func currentCodeUsesAdHocSignature() -> Bool {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &dynamicCode) == errSecSuccess,
              let dynamicCode else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let dictionary = signingInformation as NSDictionary?,
        let flags = dictionary[kSecCodeInfoFlags] as? NSNumber else {
            return false
        }

        // Security.framework does not currently import kSecCodeSignatureAdhoc into Swift.
        let adHocSignatureFlag: UInt32 = 0x0002
        return flags.uint32Value & adHocSignatureFlag != 0
    }
}

struct MenuBarShelfPermissionState: Equatable {
    let hasAccessibility: Bool
    let hasScreenCapture: Bool
}

@MainActor
final class MenuBarShelfPermissions: NSObject, ObservableObject {
    static let shared = MenuBarShelfPermissions()

    private static let authorizationPollingLimit = 120
    private static let visibilityLeaseWaitInterval: Duration = .seconds(3_600)

    @Published private(set) var state: MenuBarShelfPermissionState

    var hasAccessibility: Bool { state.hasAccessibility }
    var hasScreenCapture: Bool { state.hasScreenCapture }

    let applicationIdentity: MenuBarShelfApplicationIdentity

    private let accessibilityProbe: () -> Bool
    private let screenCaptureProbe: () -> Bool
    private let notificationCenter: NotificationCenter
    private let monitoringInterval: Duration
    private var pollingTask: Task<Void, Never>?
    private var visibleMonitorIDs = Set<UUID>()
    private var authorizationPollsRemaining = 0
    var onAccessibilityChange: ((Bool) -> Void)?

#if DEBUG
    var activeVisibleMonitorCount: Int { visibleMonitorIDs.count }
    var isActivelyPolling: Bool { pollingTask != nil }
#endif

    init(
        accessibilityProbe: @escaping () -> Bool = { AXIsProcessTrusted() },
        screenCaptureProbe: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        applicationIdentity: MenuBarShelfApplicationIdentity = .current,
        notificationCenter: NotificationCenter = .default,
        monitoringInterval: Duration = .seconds(1)
    ) {
        self.accessibilityProbe = accessibilityProbe
        self.screenCaptureProbe = screenCaptureProbe
        self.applicationIdentity = applicationIdentity
        self.notificationCenter = notificationCenter
        self.monitoringInterval = monitoringInterval
        self.state = MenuBarShelfPermissionState(
            hasAccessibility: accessibilityProbe(),
            hasScreenCapture: screenCaptureProbe()
        )
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        pollingTask?.cancel()
        notificationCenter.removeObserver(self)
    }

    /// Each visible surface owns a lease. All leases share one system-permission
    /// polling loop, and cancelling one surface releases only that surface's lease.
    func monitorWhileVisible() async {
        let monitorID = UUID()
        beginVisibleMonitoring(monitorID)
        defer { endVisibleMonitoring(monitorID) }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.visibilityLeaseWaitInterval)
            } catch {
                return
            }
        }
    }

    func refresh() {
        let nextState = MenuBarShelfPermissionState(
            hasAccessibility: accessibilityProbe(),
            hasScreenCapture: screenCaptureProbe()
        )

        if nextState.hasAccessibility {
            authorizationPollsRemaining = 0
        }

        guard nextState != state else {
            stopPollingIfUnused()
            return
        }

        let accessibilityChanged = nextState.hasAccessibility != state.hasAccessibility
        state = nextState
        if accessibilityChanged {
            onAccessibilityChange?(nextState.hasAccessibility)
        }
        stopPollingIfUnused()
    }

    func requestAccessibility() {
        startAuthorizationPolling()
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        refresh()
        openAccessibilitySettings()
    }

    func requestScreenCapture() {
        Task {
            if #available(macOS 15.0, *) {
                _ = try? await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
            } else {
                _ = CGRequestScreenCaptureAccess()
            }
            refresh()
        }
    }

    func openAccessibilitySettings() {
        openSettingsPane("Privacy_Accessibility")
    }

    func openScreenCaptureSettings() {
        openSettingsPane("Privacy_ScreenCapture")
    }

    @objc private func applicationDidBecomeActive() {
        refresh()
    }

    private func startAuthorizationPolling() {
        authorizationPollsRemaining = Self.authorizationPollingLimit
        ensurePolling()
    }

    private func beginVisibleMonitoring(_ monitorID: UUID) {
        visibleMonitorIDs.insert(monitorID)
        refresh()
        ensurePolling()
    }

    private func endVisibleMonitoring(_ monitorID: UUID) {
        visibleMonitorIDs.remove(monitorID)
        stopPollingIfUnused()
    }

    private var hasPollingDemand: Bool {
        !visibleMonitorIDs.isEmpty || authorizationPollsRemaining > 0
    }

    private func ensurePolling() {
        guard pollingTask == nil, hasPollingDemand else { return }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, hasPollingDemand else { break }
                do {
                    try await Task.sleep(for: monitoringInterval)
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                if authorizationPollsRemaining > 0 {
                    authorizationPollsRemaining -= 1
                }
                refresh()
            }
            self?.pollingTask = nil
        }
    }

    private func stopPollingIfUnused() {
        guard !hasPollingDemand else { return }
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func openSettingsPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
