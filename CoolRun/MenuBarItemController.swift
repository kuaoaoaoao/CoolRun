#if os(macOS)
import AppKit
import CoreGraphics
import Foundation

private final class MenuBarEventRelayContext: @unchecked Sendable {
    nonisolated(unsafe) let event: CGEvent
    nonisolated let targetPID: pid_t
    nonisolated(unsafe) var wasRelayed = false

    nonisolated init(event: CGEvent, targetPID: pid_t) {
        self.event = event
        self.targetPID = targetPID
    }
}

@MainActor
final class MenuBarItemController {
    enum ControllerError: LocalizedError {
        case accessibilityRequired(AppLanguage)
        case shelfDisabled(AppLanguage)
        case dividerUnavailable(AppLanguage)
        case itemUnavailable(AppLanguage)
        case itemNotMovable(AppLanguage)
        case noSafeSpace(AppLanguage)
        case eventCreationFailed(AppLanguage)
        case moveFailed(AppLanguage)

        nonisolated var errorDescription: String? {
            switch self {
            case .accessibilityRequired(let language):
                LocalizedString.l(language, en: "Allow Accessibility access to move or open menu bar items.", zh: "请允许辅助功能权限，才能移动或打开菜单栏图标。", ja: "メニューバー項目を移動・操作するにはアクセシビリティを許可してください。", ko: "메뉴 막대 항목을 이동하거나 열려면 손쉬운 사용 권한을 허용하세요.")
            case .shelfDisabled(let language):
                LocalizedString.l(language, en: "Enable Menu Bar Shelf before opening a managed item.", zh: "请先启用“菜单栏抽屉”，再打开受管理的图标。", ja: "管理項目を開く前にメニューバーシェルフを有効にしてください。", ko: "관리 항목을 열기 전에 메뉴 막대 보관함을 켜세요.")
            case .dividerUnavailable(let language):
                LocalizedString.l(language, en: "The shelf divider is not available.", zh: "菜单栏收纳分隔线当前不可用。", ja: "シェルフ区切りを利用できません。", ko: "보관함 구분선을 사용할 수 없습니다.")
            case .itemUnavailable(let language):
                LocalizedString.l(language, en: "This menu bar item is no longer available.", zh: "这个菜单栏图标已经不可用。", ja: "このメニューバー項目は利用できません。", ko: "이 메뉴 막대 항목은 더 이상 사용할 수 없습니다.")
            case .itemNotMovable(let language):
                LocalizedString.l(language, en: "macOS does not allow this item to be moved.", zh: "macOS 不允许移动这个图标。", ja: "macOS はこの項目の移動を許可していません。", ko: "macOS에서 이 항목을 이동할 수 없습니다.")
            case .noSafeSpace(let language):
                LocalizedString.l(language, en: "There is not enough safe menu bar space to reveal this item on the current display.", zh: "当前显示器没有足够的安全菜单栏空间来临时显示这个图标。", ja: "現在のディスプレイには、この項目を表示する安全な空き領域がありません。", ko: "현재 디스플레이의 메뉴 막대에 이 항목을 표시할 안전한 공간이 부족합니다.")
            case .eventCreationFailed(let language):
                LocalizedString.l(language, en: "CoolRun could not create the menu bar action.", zh: "CoolRun 无法创建菜单栏操作。", ja: "メニューバー操作を作成できませんでした。", ko: "메뉴 막대 동작을 만들 수 없습니다.")
            case .moveFailed(let language):
                LocalizedString.l(language, en: "The item did not move to the requested section.", zh: "图标没有移动到指定分组。", ja: "項目を指定したセクションへ移動できませんでした。", ko: "항목을 지정한 구역으로 이동하지 못했습니다.")
            }
        }
    }

    private enum MoveSide { case left, right }

    private struct ReturnDestination {
        let anchorIdentity: MenuBarItemIdentity
        let side: MoveSide
    }

    private let bridge: MenuBarWindowBridge
    private let permissions: MenuBarShelfPermissions
    private weak var store: MenuBarShelfStore?
    private var divider: NSStatusItem?
    private var operationTask: Task<Void, Never>?
    private var isShelfPresented = false
    private var isTemporarilyActivating = false
    private var cachedDividerWindowID: CGWindowID?
    private var knownWindowIDs = Set<CGWindowID>()
    var beforeActivation: (() -> Void)?

    init(
        store: MenuBarShelfStore,
        bridge: MenuBarWindowBridge? = nil,
        permissions: MenuBarShelfPermissions? = nil
    ) {
        self.store = store
        self.bridge = bridge ?? MenuBarWindowBridge()
        self.permissions = permissions ?? .shared
    }

    deinit {
        operationTask?.cancel()
        if let divider {
            NSStatusBar.system.removeStatusItem(divider)
        }
    }

    var dividerWindowID: CGWindowID? {
        if let cachedDividerWindowID,
           bridge.currentFrame(for: cachedDividerWindowID) != nil {
            return cachedDividerWindowID
        }
        guard let window = divider?.button?.window else { return nil }
        if let directID = MenuBarWindowBridge.windowID(
            fromAppKitWindowNumber: window.windowNumber
        ), bridge.currentFrame(for: directID) != nil {
            cachedDividerWindowID = directID
            return directID
        }
        let resolvedID = bridge.statusWindowID(
            matchingQuartzFrame: quartzFrame(for: window.frame),
            preferredTitle: "CoolRun.MenuBarShelfDivider"
        )
        cachedDividerWindowID = resolvedID
        return resolvedID
    }

    func start() {
        store?.onEnabledChange = { [weak self] enabled in self?.setEnabled(enabled) }
        store?.onGroupChange = { [weak self] item, group, previousGroup in
            self?.changeGroup(of: item, to: group, previousGroup: previousGroup)
        }
        store?.onPresentationChange = { [weak self] presented in self?.setShelfPresented(presented) }
        store?.onActivate = { [weak self] item, rightClick in self?.activate(item, rightClick: rightClick) }
        store?.onItemsRefresh = { [weak self] items in self?.reconcileNewItems(items) }
        permissions.onAccessibilityChange = { [weak self] granted in
            if granted {
                self?.applySavedGroups()
            } else {
                self?.updateDividerLength()
            }
        }
        if let items = store?.items {
            knownWindowIDs = Set(items.map(\.windowID))
        }
        if store?.isEnabled == true {
            setEnabled(true)
        }
    }

    func stop() {
        operationTask?.cancel()
        operationTask = nil
        store?.onEnabledChange = nil
        store?.onGroupChange = nil
        store?.onPresentationChange = nil
        store?.onActivate = nil
        store?.onItemsRefresh = nil
        permissions.onAccessibilityChange = nil
        knownWindowIDs.removeAll()
        setEnabled(false)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            ensureDivider()
            applySavedGroups()
        } else {
            divider?.length = 1
            if let divider {
                NSStatusBar.system.removeStatusItem(divider)
            }
            divider = nil
            cachedDividerWindowID = nil
        }
    }

    func setShelfPresented(_ presented: Bool) {
        isShelfPresented = presented
        updateDividerLength()
    }

    func changeGroup(
        of item: MenuBarItemSnapshot,
        to group: MenuBarShelfGroup,
        previousGroup: MenuBarShelfGroup
    ) {
        guard store?.isEnabled == true else { return }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await move(item: item, to: group == .pinned ? .right : .left)
                store?.refresh()
                updateDividerLength()
            } catch {
                if let controllerError = error as? ControllerError {
                    switch controllerError {
                    case .accessibilityRequired:
                        break
                    default:
                        store?.restoreGroup(previousGroup, for: item)
                    }
                }
                store?.setOperationState(.failed(message: error.localizedDescription))
            }
        }
    }

    func activate(_ item: MenuBarItemSnapshot, rightClick: Bool = false) {
        guard store?.isEnabled == true else {
            store?.setOperationState(.failed(message: ControllerError.shelfDisabled(currentLanguage).localizedDescription))
            return
        }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await activateItem(item, rightClick: rightClick)
                store?.setOperationState(.idle)
            } catch {
                store?.setOperationState(.failed(message: error.localizedDescription))
            }
        }
    }

    func applySavedGroups(to candidates: [MenuBarItemSnapshot]? = nil) {
        guard permissions.hasAccessibility, let store, store.isEnabled else {
            updateDividerLength()
            return
        }
        ensureDivider()
        let currentItems = candidates ?? store.items
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            for item in currentItems where item.canMove {
                guard !Task.isCancelled else { return }
                let group = store.group(for: item)
                try? await move(item: item, to: group == .pinned ? .right : .left, onlyIfNeeded: true)
            }
            store.refresh()
            updateDividerLength()
        }
    }

    private func reconcileNewItems(_ items: [MenuBarItemSnapshot]) {
        if store?.isEnabled == true {
            ensureDivider()
            updateDividerLength()
        }
        let currentWindowIDs = Set(items.map(\.windowID))
        let introducedWindowIDs = currentWindowIDs.subtracting(knownWindowIDs)
        knownWindowIDs = currentWindowIDs
        guard !introducedWindowIDs.isEmpty else { return }
        applySavedGroups(to: items.filter { introducedWindowIDs.contains($0.windowID) })
    }

    private func ensureDivider() {
        if let divider, divider.isVisible, divider.button?.window != nil {
            return
        }
        if let divider {
            NSStatusBar.system.removeStatusItem(divider)
            self.divider = nil
            cachedDividerWindowID = nil
        }
        let item = NSStatusBar.system.statusItem(withLength: 1)
        item.autosaveName = "CoolRun.MenuBarShelfDivider"
        item.behavior = [.removalAllowed]
        item.isVisible = true
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: nil)
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = LocalizedString.l(AppSettings.shared.language, en: "Menu bar shelf divider", zh: "菜单栏收纳分隔线", ja: "メニューバーシェルフ区切り", ko: "메뉴 막대 보관함 구분선")
        }
        divider = item
        updateDividerLength()
    }

    private func updateDividerLength() {
        guard let divider, let store, store.isEnabled else { return }
        guard permissions.hasAccessibility else {
            divider.length = NSStatusItem.variableLength
            return
        }
        guard dividerWindowID != nil else {
            // Keep the menu bar usable when this macOS release does not expose
            // a WindowServer counterpart for the AppKit status item.
            divider.length = NSStatusItem.variableLength
            return
        }
        let hasHidden = store.items.contains { store.group(for: $0) != .pinned }
        divider.length = hasHidden && !isShelfPresented && !isTemporarilyActivating
            ? 10_000
            : NSStatusItem.variableLength
    }

    private func move(
        item: MenuBarItemSnapshot,
        to side: MoveSide,
        relativeTo targetWindowID: CGWindowID? = nil,
        onlyIfNeeded: Bool = false
    ) async throws {
        guard permissions.hasAccessibility else { throw ControllerError.accessibilityRequired(currentLanguage) }
        guard item.canMove else { throw ControllerError.itemNotMovable(currentLanguage) }
        ensureDivider()
        guard let dividerWindowID else {
            throw ControllerError.dividerUnavailable(currentLanguage)
        }
        let effectiveTargetWindowID = targetWindowID ?? dividerWindowID
        guard let targetFrame = bridge.currentFrame(for: effectiveTargetWindowID) else {
            throw ControllerError.dividerUnavailable(currentLanguage)
        }
        guard let itemFrame = bridge.currentFrame(for: item.windowID) else {
            throw ControllerError.itemUnavailable(currentLanguage)
        }

        if onlyIfNeeded {
            switch side {
            case .left where itemFrame.maxX <= targetFrame.minX: return
            case .right where itemFrame.minX >= targetFrame.maxX: return
            default: break
            }
        }

        store?.setOperationState(.moving(itemID: item.identity.id))
        let targetPoint = CGPoint(x: side == .left ? targetFrame.minX : targetFrame.maxX, y: targetFrame.midY)
        let initialFrame = itemFrame
        for _ in 0..<3 {
            try await postMoveEvents(
                item: item,
                itemFrame: itemFrame,
                targetWindowID: effectiveTargetWindowID,
                targetPoint: targetPoint
            )

            for _ in 0..<20 {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(50))
                guard let newFrame = bridge.currentFrame(for: item.windowID) else { continue }
                if newFrame != initialFrame {
                    let latestTarget = bridge.currentFrame(for: effectiveTargetWindowID) ?? targetFrame
                    let correctSide = side == .left
                        ? newFrame.maxX <= latestTarget.minX + 1
                        : newFrame.minX >= latestTarget.maxX - 1
                    if correctSide {
                        store?.setOperationState(.idle)
                        return
                    }
                }
            }
        }
        throw ControllerError.moveFailed(currentLanguage)
    }

    private func activateItem(_ item: MenuBarItemSnapshot, rightClick: Bool) async throws {
        guard permissions.hasAccessibility else { throw ControllerError.accessibilityRequired(currentLanguage) }
        store?.setOperationState(.activating(itemID: item.identity.id))
        ensureDivider()

        isTemporarilyActivating = true
        defer {
            isTemporarilyActivating = false
            updateDividerLength()
        }

        divider?.length = NSStatusItem.variableLength
        try await Task.sleep(for: .milliseconds(120))
        guard let currentFrame = bridge.currentFrame(for: item.windowID) else {
            throw ControllerError.itemUnavailable(currentLanguage)
        }

        let screen = screenContainingQuartzFrame(currentFrame)
        let operable = screen.map { screen in
            let screenFrame = quartzFrame(for: screen.frame)
            let auxiliaryArea = screen.auxiliaryTopRightArea
            let rightSafeArea = auxiliaryArea.flatMap { area in
                area.isEmpty ? nil : quartzFrame(for: area)
            }
            return MenuBarShelfGeometry.isOperable(currentFrame, on: screenFrame, rightSafeArea: rightSafeArea)
        } ?? false
        let originalGroup = store?.group(for: item) ?? .pinned
        let mustRestore = !operable && originalGroup != .pinned
        let returnDestination = mustRestore ? returnDestination(for: item) : nil

        if !operable {
            let revealScreen = screen ?? dividerWindowID.flatMap { windowID in
                bridge.currentFrame(for: windowID).flatMap(screenContainingQuartzFrame)
            }
            guard let revealScreen, hasSafeTemporarySpace(for: item, on: revealScreen) else {
                throw ControllerError.noSafeSpace(currentLanguage)
            }
            try await move(item: item, to: .right)
        }
        guard let clickableFrame = bridge.currentFrame(for: item.windowID) else {
            throw ControllerError.itemUnavailable(currentLanguage)
        }

        let interfaceOwnerPIDs = Set([
            item.ownerPID,
            MenuBarHostedStatusItemResolver.applicationProcessIdentifier(
                for: item.ownerBundleIdentifier
            ),
        ].compactMap { $0 })
        let beforeWindows = Set(bridge.onScreenWindows().filter {
            interfaceOwnerPIDs.contains($0.ownerPID)
        }.map(\.windowID))
        beforeActivation?()
        try await postClickEvents(item: item, frame: clickableFrame, rightClick: rightClick)
        await waitForPresentedInterface(ownerPIDs: interfaceOwnerPIDs, existingWindows: beforeWindows)

        if mustRestore {
            let latest = store?.items.first(where: { $0.identity == item.identity }) ?? item
            if
                let returnDestination,
                let anchor = store?.items.first(where: { $0.identity == returnDestination.anchorIdentity })
            {
                try? await move(
                    item: latest,
                    to: returnDestination.side,
                    relativeTo: anchor.windowID
                )
            } else {
                try? await move(item: latest, to: .left)
            }
        }
    }

    private func waitForPresentedInterface(ownerPIDs: Set<pid_t>, existingWindows: Set<CGWindowID>) async {
        var observedInterface = false
        for attempt in 0..<60 {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(250))
            let newWindows = bridge.onScreenWindows().filter {
                ownerPIDs.contains($0.ownerPID) && !existingWindows.contains($0.windowID) &&
                    $0.layer != Int(CGWindowLevelForKey(.statusWindow))
            }
            if !newWindows.isEmpty {
                observedInterface = true
            } else if observedInterface || attempt >= 4 {
                return
            }
        }
    }

    private func returnDestination(for item: MenuBarItemSnapshot) -> ReturnDestination? {
        guard let store else { return nil }
        let hiddenItems = store.items
            .filter { store.group(for: $0) != .pinned && $0.identity != item.identity }
            .sorted { $0.frame.maxX < $1.frame.maxX }

        if let rightNeighbor = hiddenItems.first(where: { $0.frame.minX >= item.frame.maxX }) {
            return ReturnDestination(anchorIdentity: rightNeighbor.identity, side: .left)
        }
        if let leftNeighbor = hiddenItems.last(where: { $0.frame.maxX <= item.frame.minX }) {
            return ReturnDestination(anchorIdentity: leftNeighbor.identity, side: .right)
        }
        return nil
    }

    private func postMoveEvents(
        item: MenuBarItemSnapshot,
        itemFrame: CGRect,
        targetWindowID: CGWindowID,
        targetPoint: CGPoint
    ) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ControllerError.eventCreationFailed(currentLanguage)
        }
        configureEventSource(source)
        if let combinedSessionSource = CGEventSource(stateID: .combinedSessionState) {
            configureEventSource(combinedSessionSource)
        }
        let originalPointerLocation = CGEvent(source: nil)?.location
        let fallbackPoint = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
        guard
            let down = targetedEvent(type: .leftMouseDown, button: .left, location: CGPoint(x: 20_000, y: 20_000), targetPID: item.ownerPID, windowID: item.windowID, source: source, commandDown: true),
            let up = targetedEvent(type: .leftMouseUp, button: .left, location: targetPoint, targetPID: item.ownerPID, windowID: targetWindowID, source: source),
            let fallback = targetedEvent(type: .leftMouseUp, button: .left, location: fallbackPoint, targetPID: item.ownerPID, windowID: item.windowID, source: source)
        else {
            throw ControllerError.eventCreationFailed(currentLanguage)
        }

        NSCursor.hide()
        defer {
            restorePointer(to: originalPointerLocation, source: source)
            NSCursor.unhide()
        }

        do {
            try await relayMenuBarEvent(down, targetPID: item.ownerPID)
            try await waitForFrameChange(
                windowID: item.windowID,
                initialFrame: itemFrame,
                timeout: .milliseconds(80)
            )
            try await relayMenuBarEvent(up, targetPID: item.ownerPID)
            try await waitForFrameChange(
                windowID: item.windowID,
                initialFrame: itemFrame,
                timeout: .milliseconds(80)
            )
        } catch {
            try? await relayMenuBarEvent(fallback, targetPID: item.ownerPID)
            throw error
        }
    }

    private func relayMenuBarEvent(_ event: CGEvent, targetPID: pid_t) async throws {
        let context = MenuBarEventRelayContext(event: event, targetPID: targetPID)
        let retainedContext = Unmanaged.passRetained(context)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << event.type.rawValue,
            callback: { _, type, receivedEvent, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(receivedEvent)
                }
                let context = Unmanaged<MenuBarEventRelayContext>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    return Unmanaged.passUnretained(receivedEvent)
                }
                guard !context.wasRelayed,
                      receivedEvent.type == context.event.type,
                      receivedEvent.getIntegerValueField(.eventSourceUserData) ==
                        context.event.getIntegerValueField(.eventSourceUserData) else {
                    return Unmanaged.passUnretained(receivedEvent)
                }
                context.wasRelayed = true
                context.event.postToPid(context.targetPID)
                return Unmanaged.passUnretained(receivedEvent)
            },
            userInfo: retainedContext.toOpaque()
        ) else {
            retainedContext.release()
            // Accessibility can be revoked between the permission check and
            // this operation. Preserve a best-effort fallback without leaving
            // a synthetic mouse button held down.
            event.post(tap: .cgSessionEventTap)
            try await Task.sleep(for: .milliseconds(12))
            event.postToPid(targetPID)
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        defer {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            retainedContext.release()
        }

        event.post(tap: .cgSessionEventTap)
        for _ in 0..<20 {
            if context.wasRelayed { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ControllerError.eventCreationFailed(currentLanguage)
    }

    private func waitForFrameChange(
        windowID: CGWindowID,
        initialFrame: CGRect,
        timeout: Duration
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            try Task.checkCancellation()
            if bridge.currentFrame(for: windowID) != initialFrame { return }
            try await Task.sleep(for: .milliseconds(5))
        } while clock.now < deadline
        // Some hosted items update their frame after the event pair, not after
        // each half. The caller's final position check remains authoritative.
    }

    private func postClickEvents(item: MenuBarItemSnapshot, frame: CGRect, rightClick: Bool) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ControllerError.eventCreationFailed(currentLanguage)
        }
        configureEventSource(source)
        let originalPointerLocation = CGEvent(source: nil)?.location
        let downType: CGEventType = rightClick ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightClick ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = rightClick ? .right : .left
        let location = CGPoint(x: frame.midX, y: frame.midY)
        guard
            let down = targetedEvent(type: downType, button: button, location: location, targetPID: item.ownerPID, windowID: item.windowID, source: source),
            let up = targetedEvent(type: upType, button: button, location: location, targetPID: item.ownerPID, windowID: item.windowID, source: source)
        else {
            throw ControllerError.eventCreationFailed(currentLanguage)
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        try await relayMenuBarEvent(down, targetPID: item.ownerPID)
        try await relayMenuBarEvent(up, targetPID: item.ownerPID)
        restorePointer(to: originalPointerLocation, source: source)
    }

    private func targetedEvent(
        type: CGEventType,
        button: CGMouseButton,
        location: CGPoint,
        targetPID: pid_t,
        windowID: CGWindowID,
        source: CGEventSource,
        commandDown: Bool = false
    ) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else {
            return nil
        }
        event.flags = commandDown ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
        event.setIntegerValueField(.eventSourceUserData, value: Int64.random(in: 1...Int64.max))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        if let privateWindowField = CGEventField(rawValue: 0x33) {
            event.setIntegerValueField(privateWindowField, value: Int64(windowID))
        }
        return event
    }

    private var currentLanguage: AppLanguage {
        AppSettings.shared.language
    }

    private func restorePointer(to location: CGPoint?, source: CGEventSource) {
        guard
            let location,
            let event = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: location,
                mouseButton: .left
            )
        else { return }
        event.post(tap: .cgSessionEventTap)
    }

    private func configureEventSource(_ source: CGEventSource) {
        let permitAllEvents: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents,
        ]
        source.setLocalEventsFilterDuringSuppressionState(
            permitAllEvents,
            state: .eventSuppressionStateRemoteMouseDrag
        )
        source.setLocalEventsFilterDuringSuppressionState(
            permitAllEvents,
            state: .eventSuppressionStateSuppressionInterval
        )
        source.localEventsSuppressionInterval = 0
    }

    private func screenContainingQuartzFrame(_ frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            let converted = quartzFrame(for: screen.frame)
            return converted.minY <= frame.midY && frame.midY <= converted.maxY
        }
    }

    private func hasSafeTemporarySpace(for item: MenuBarItemSnapshot, on screen: NSScreen) -> Bool {
        guard let store else { return false }
        let screenFrame = quartzFrame(for: screen.frame)
        let safeFrame: CGRect
        if let auxiliaryArea = screen.auxiliaryTopRightArea, !auxiliaryArea.isEmpty {
            safeFrame = quartzFrame(for: auxiliaryArea)
        } else {
            let applicationMenuReserve = min(320, screenFrame.width * 0.25)
            safeFrame = CGRect(
                x: screenFrame.minX + applicationMenuReserve,
                y: screenFrame.minY,
                width: max(screenFrame.width - applicationMenuReserve, 0),
                height: max(item.frame.height, 24)
            )
        }

        let occupiedWidth = store.items.reduce(CGFloat.zero) { total, candidate in
            guard
                candidate.identity != item.identity,
                store.group(for: candidate) == .pinned,
                safeFrame.intersects(candidate.frame)
            else { return total }
            return total + candidate.frame.width
        }
        return item.frame.width > 0 && occupiedWidth + item.frame.width <= safeFrame.width
    }

    private func quartzFrame(for cocoaFrame: CGRect) -> CGRect {
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? cocoaFrame.height
        return CGRect(
            x: cocoaFrame.minX,
            y: mainScreenHeight - cocoaFrame.maxY,
            width: cocoaFrame.width,
            height: cocoaFrame.height
        )
    }
}
#endif
