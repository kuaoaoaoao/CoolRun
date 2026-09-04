#if os(macOS)
import AppKit
import Carbon
import CoreGraphics
import Observation

/// Registers ⌃⌘1…9 global hotkeys that paste the nth clipboard-history entry.
/// Off by default; users opt in via Settings.
@MainActor
@Observable
final class ClipboardQuickPasteController {
    static let shared = ClipboardQuickPasteController()

    nonisolated static let enabledDefaultsKey = "clipboard_quick_paste_enabled"
    nonisolated static let slotCount = 9

    /// Slots whose hotkey could not be registered because another app owns the combo.
    private(set) var conflictedSlots: Set<Int> = []

    @ObservationIgnored private var hotKeyRefs: [EventHotKeyRef?] = []
    @ObservationIgnored private var isHandlerInstalled = false
    @ObservationIgnored private var enabled: Bool
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    /// Suppresses the accessibility prompt after the first one in a session.
    @ObservationIgnored private static var didPromptForAccessibility = false
    /// Hot keys repeat while held down; ignore presses within this window.
    @ObservationIgnored private static var lastPasteAt = Date.distantPast
    @ObservationIgnored private static let pasteThrottleInterval: TimeInterval = 0.4

    private enum EventID {
        static let signature: FourCharCode = {
            let scalars = Array("CBQP".unicodeScalars)
            return FourCharCode(scalars[0].value) << 24
                | FourCharCode(scalars[1].value) << 16
                | FourCharCode(scalars[2].value) << 8
                | FourCharCode(scalars[3].value)
        }()
        /// The event id must be the bare slot index: handlers decode it with a
        /// range guard, so it cannot carry bits of the four-char signature.
        static func slot(_ index: Int) -> UInt32 {
            UInt32(index)
        }
    }

    private init(userDefaults: UserDefaults = .standard) {
        self.enabled = userDefaults.bool(forKey: Self.enabledDefaultsKey)
    }

    func start() {
        observeDefaults()
        if enabled { registerAll() }
    }

    func stop() {
        unregisterAll()
    }

    private func observeDefaults() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncEnabledState()
            }
        }
    }

    private func syncEnabledState() {
        let newValue = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        guard newValue != enabled else { return }
        enabled = newValue
        if enabled {
            registerAll()
        } else {
            unregisterAll()
        }
    }

    private func registerAll() {
        guard hotKeyRefs.isEmpty else { return }
        conflictedSlots = []
        // ANSI keycodes for digits 1-9: 18,19,20,21,23,22,26,28,25.
        let keyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for slot in 0..<Self.slotCount {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: EventID.signature, id: EventID.slot(slot))
            let status = RegisterEventHotKey(
                keyCodes[slot],
                UInt32(cmdKey | controlKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr {
                hotKeyRefs.append(hotKeyRef)
            } else {
                conflictedSlots.insert(slot)
            }
        }
        if !isHandlerInstalled {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let handler: EventHandlerUPP = { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let slot = hotKeyID.id
                Task { @MainActor in
                    ClipboardQuickPasteController.handleHotKey(slot: Int(slot))
                }
                return noErr
            }
            InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, nil)
            isHandlerInstalled = true
        }
    }

    private func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        conflictedSlots = []
    }

    fileprivate static func handleHotKey(slot: Int) {
        guard slot >= 0, slot < slotCount else { return }
        guard Date().timeIntervalSince(lastPasteAt) > pasteThrottleInterval else { return }
        lastPasteAt = Date()
        guard AXIsProcessTrusted() else {
            promptForAccessibilityIfNeeded()
            return
        }
        let store = ClipboardHistoryStore.shared
        guard let entry = store.entries[safe: slot] else { return }
        // writeToPasteboard (not copyToPasteboard) keeps the history order stable.
        store.writeToPasteboard(id: entry.id)
        // Give the pasteboard write a moment to settle before synthesizing ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.postPasteKeystroke()
        }
    }

    private static func promptForAccessibilityIfNeeded() {
        guard !didPromptForAccessibility else { return }
        didPromptForAccessibility = true
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    private static func postPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9 /* v */, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
