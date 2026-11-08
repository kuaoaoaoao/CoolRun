#if os(macOS)
import AppKit
import Carbon
import Observation
import os.log

private let logger = Logger(subsystem: "com.coolrun.agent", category: "quickAccess")

/// 全局热键：不管在哪个 app 里，按 ⌥⌘A 直接把 Agent 面板叫出来。
///
/// 用 Carbon 的 `RegisterEventHotKey` 而不是 `NSEvent` 全局监听 —— 后者需要
/// 辅助功能权限，对菜单栏小工具来说太重了。
@MainActor
@Observable
final class AgentQuickAccess {
    static let shared = AgentQuickAccess()

    private(set) var isRegistered = false
    /// 热键被别的 app 占了。
    private(set) var isConflicted = false

    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerInstalled = false

    private enum EventID {
        static let signature: FourCharCode = {
            let scalars = Array("CAGR".unicodeScalars)
            return FourCharCode(scalars[0].value) << 24
                | FourCharCode(scalars[1].value) << 16
                | FourCharCode(scalars[2].value) << 8
                | FourCharCode(scalars[3].value)
        }()
        static let hotKey: UInt32 = 1
    }

    private init() {}

    func start() {
        register()
    }

    func stop() {
        unregister()
    }

    func register() {
        unregister()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(cmdKey | optionKey),
            EventHotKeyID(signature: EventID.signature, id: EventID.hotKey),
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            isRegistered = false
            isConflicted = true
            logger.info("agent hotkey registration failed: \(status, privacy: .public)")
            return
        }

        hotKeyRef = ref
        isRegistered = true
        isConflicted = false
        installHandlerIfNeeded()
        logger.info("agent hotkey registered (⌥⌘A)")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        isRegistered = false
        isConflicted = false
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == EventID.signature,
                  hotKeyID.id == EventID.hotKey
            else {
                // 别的事件（比如剪贴板快捷粘贴）不归我们管。
                return noErr
            }
            Task { @MainActor in
                AgentQuickAccess.shared.activate()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    /// 唤出 Agent 面板。走现有的导航路由，复用 popover 的定位逻辑。
    func activate() {
        AppNavigationRouter.shared.open(.aiAssistant)
    }
}
#endif
