#if os(macOS)
import AppKit
import Carbon
import CoreGraphics
import Observation
import os.log

private let logger = Logger(subsystem: "com.coolrun.clipboard", category: "quickPaste")

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
        let conflictList = conflictedSlots.map(String.init).joined(separator: ",")
        logger.info("registered \(self.hotKeyRefs.count, privacy: .public)/\(Self.slotCount, privacy: .public) hotkeys; conflicted slots: \(conflictList, privacy: .public)")
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
        logger.debug("hotkey fired for slot \(slot, privacy: .public)")
        guard slot >= 0, slot < slotCount else { return }
        guard Date().timeIntervalSince(lastPasteAt) > pasteThrottleInterval else {
            logger.debug("hotkey slot \(slot, privacy: .public) throttled")
            return
        }
        lastPasteAt = Date()
        guard AXIsProcessTrusted() else {
            logger.error("hotkey slot \(slot, privacy: .public) ignored: accessibility not granted to this running process")
            promptForAccessibilityIfNeeded()
            return
        }
        let store = ClipboardHistoryStore.shared
        guard let entry = store.entries[safe: slot] else {
            logger.debug("hotkey slot \(slot, privacy: .public) ignored: no entry at index (history count \(store.entries.count, privacy: .public))")
            return
        }
        store.copyToPasteboard(id: entry.id)
        logger.debug("hotkey slot \(slot, privacy: .public) wrote entry, posting ⌘V")
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
        else {
            logger.error("failed to create ⌘V key events")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        logger.debug("posted ⌘V key events")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
