#if os(macOS)
import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let contextPopover = NSPopover()
    private let viewModel = SystemMonitorViewModel()
    private let codexViewModel = CodexMonitorViewModel.shared
    private let claudeViewModel = ClaudeMonitorViewModel.shared
    private let goldPriceService = GoldPriceService()
    private let settings = AppSettings.shared
    private let englishLearning = EnglishLearningManager.shared
    private var windowCloseObserver: NSObjectProtocol?
    private var textbookWindowController: NSWindowController?
    private var iconTimer: Timer?
    private var goldPriceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var coinPhase = 0.0
    private var goldPriceText = "--"
    private let popoverPinState = PopoverPinState()
    private var allowsPopoverClose = false
    private var activeAnimationFramesPerSecond: Double?
    private var rotationUsesSecondary = false
    private var lastMenuBarRotationAt = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.image = settings.showMenuBarCoinIcon
                ? CoinIconRenderer.image(
                    phase: coinPhase,
                    motion: settings.menuBarCoinMotion,
                    appearance: settings.menuBarCoinAppearance
                )
                : nil
            button.font = Self.statusTitleFont
            button.lineBreakMode = .byTruncatingTail
            button.title = settings.showMenuBarCoinIcon ? " \(goldPriceText)" : goldPriceText
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.toolTip = LocalizedString.menuBar("open_coolrun")
        }
        updateStatusItemLength()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 336, height: 528)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarMonitorView(
                viewModel: viewModel,
                pinState: popoverPinState,
                onPinChange: { [weak self] pinned in
                    self?.setPopoverPinned(pinned)
                }
            )
        )

        contextPopover.behavior = .transient
        contextPopover.animates = false
        contextPopover.contentSize = NSSize(width: 216, height: 296)
        contextPopover.contentViewController = NSHostingController(
            rootView: StatusContextMenuView(
                showToday: { [weak self] in
                    self?.performContextQuickAction(mode: .today)
                },
                addCountdown: { [weak self] in
                    self?.performContextQuickAction(mode: .calendar, quickAction: .addCountdown)
                },
                recordGoldTrade: { [weak self] in
                    self?.performContextQuickAction(mode: .gold, quickAction: .recordGoldTrade)
                },
                refreshAll: { [weak self] in
                    self?.contextPopover.performClose(nil)
                    Task { @MainActor in
                        await self?.refreshGoldPriceNow()
                        await self?.codexViewModel.refresh()
                        await self?.claudeViewModel.refresh()
                    }
                },
                toggleEnglishPlayback: { [weak self] in
                    self?.toggleEnglishPlaybackFromContextMenu()
                },
                previousEnglishItem: { [weak self] in
                    self?.englishLearning.previous()
                },
                nextEnglishItem: { [weak self] in
                    self?.englishLearning.next()
                },
                stopEnglishPlayback: { [weak self] in
                    self?.englishLearning.stop()
                },
                selectDisplayMode: { [weak self] mode in
                    self?.selectDisplayModeFromContextMenu(mode)
                },
                openSettings: { [weak self] in
                    self?.openSettingsFromContextMenu()
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
        )

        observeSettingsWindowLifecycle()
        observeNavigationRequests()
        observeSettingsChanges()
        viewModel.start()
        ClipboardHistoryStore.shared.startMonitoring()
        startIconAnimation()
        startGoldPriceUpdates()

        Analytics.capture(.appLaunched, properties: AnalyticsDeviceProperties.launchProperties)

        // 启动后台自动检查更新
        UpdateChecker.shared.startAutoCheck()
    }

    private func observeNavigationRequests() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationRequestNotification),
            name: .coolRunPresentNavigationRequest,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGoldRefreshNotification),
            name: .coolRunRefreshGold,
            object: nil
        )
    }

    @objc private func handleNavigationRequestNotification() {
        presentRequestedNavigation()
    }

    @objc private func handleGoldRefreshNotification() {
        Task { @MainActor [weak self] in await self?.refreshGoldPriceNow() }
    }

    // 监听设置变化
    private func observeSettingsChanges() {
        settings.$menuBarDisplayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemLength()
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        settings.$menuBarCompositionStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rotationUsesSecondary = false
                self?.lastMenuBarRotationAt = Date()
                self?.updateStatusItemLength()
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        settings.$menuBarSecondaryDisplayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        settings.$menuBarRotationSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.lastMenuBarRotationAt = Date() }
            .store(in: &cancellables)

        settings.$language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusItem?.button?.toolTip = LocalizedString.menuBar("open_coolrun")
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        settings.$menuBarAnimationRate
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.startIconAnimation()
            }
            .store(in: &cancellables)

        settings.$showMenuBarCoinIcon
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coinPhase = 0
                self?.startIconAnimation()
            }
            .store(in: &cancellables)

        settings.$menuBarCoinMotion
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coinPhase = 0
                self?.startIconAnimation()
            }
            .store(in: &cancellables)

        settings.$menuBarCoinAppearance
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coinPhase = 0
                self?.startIconAnimation()
            }
            .store(in: &cancellables)

        settings.$goldRefreshRate
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.startGoldPriceUpdates()
            }
            .store(in: &cancellables)

        settings.$englishMenuTextStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        englishLearning.$currentItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        englishLearning.$currentSpokenText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        englishLearning.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconTimer?.invalidate()
        goldPriceTask?.cancel()
        englishLearning.stop()
        GoldPriceStore.shared.flushToDisk()
        ClipboardHistoryStore.shared.stopMonitoring()
        UpdateChecker.shared.stopAutoCheck()
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
        NotificationCenter.default.removeObserver(self, name: .coolRunPresentNavigationRequest, object: nil)
        NotificationCenter.default.removeObserver(self, name: .coolRunRefreshGold, object: nil)
        viewModel.stop()
        codexViewModel.stop()
        claudeViewModel.stop()
    }

    @objc private func handleStatusItemClick() {
        switch NSApp.currentEvent?.type {
        case .rightMouseUp, .rightMouseDown:
            showContextMenu()
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if contextPopover.isShown {
            contextPopover.performClose(nil)
        }
        if popover.isShown {
            if popoverPinState.isPinned {
                // pin 状态下点图标也给反馈：解除 pin 并收起弹窗，而不是无响应
                closeMonitorPopover(unpin: true)
                return
            }
            closeMonitorPopover()
        } else {
            presentMonitorPopover(relativeTo: button)
        }
    }

    private func presentRequestedNavigation() {
        contextPopover.performClose(nil)
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            presentMonitorPopover(relativeTo: button)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentMonitorPopover(relativeTo button: NSStatusBarButton) {
        if AppNavigationRouter.shared.request?.mode == .codex || settings.lastViewModeRaw == ViewMode.codex.rawValue {
            codexViewModel.start()
            claudeViewModel.start()
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        Analytics.capture(.popoverOpened)
    }

    private func setPopoverPinned(_ pinned: Bool) {
        popoverPinState.isPinned = pinned
        popover.behavior = pinned ? .applicationDefined : .transient
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }

        // pin 状态下也先关掉主弹窗（临时解除 pin），避免两个弹窗重叠
        if popover.isShown {
            closeMonitorPopover(unpin: true)
        }
        if contextPopover.isShown {
            contextPopover.performClose(nil)
        } else {
            contextPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func prepareToOpenSettings() {
        closeMonitorPopover(unpin: true)
        contextPopover.performClose(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeMonitorPopover(unpin: Bool = false) {
        guard popover.isShown else {
            if unpin {
                setPopoverPinned(false)
            }
            return
        }

        if unpin {
            setPopoverPinned(false)
        }

        allowsPopoverClose = true
        popover.performClose(nil)
        allowsPopoverClose = false
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard popover === self.popover else { return true }
        return allowsPopoverClose || !popoverPinState.isPinned
    }

    func popoverDidClose(_ notification: Notification) {
        guard
            let closedPopover = notification.object as? NSPopover
        else { return }

        guard closedPopover === popover else { return }

        // NSPopover 会保留 hosting controller；显式停止，避免关闭后仍轮询 AI 接口。
        codexViewModel.stop()
        claudeViewModel.stop()

        if popoverPinState.isPinned {
            setPopoverPinned(false)
        }
    }

    private func openSettingsFromContextMenu() {
        prepareToOpenSettings()
        Analytics.capture(.settingsOpened)
    }

    // 课本管理面板 660x520，不能在 320pt 弹窗里用 sheet 弹出，改用独立窗口。
    func openEnglishTextbookManagerWindow() {
        prepareToOpenSettings()

        if let window = textbookWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: EnglishTextbookManagementView(onRequestClose: { [weak self] in
            self?.textbookWindowController?.window?.close()
        }))
        let window = NSWindow(contentViewController: hostingController)
        window.title = LocalizedString.english("textbook_management")
        window.setContentSize(NSSize(width: 660, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        textbookWindowController = controller
        controller.showWindow(nil)
    }

    private func toggleEnglishPlaybackFromContextMenu() {
        contextPopover.performClose(nil)
        englishLearning.toggleContinuousPlayback()
    }

    private func selectDisplayModeFromContextMenu(_ mode: MenuBarDisplayMode) {
        settings.menuBarDisplayMode = mode
        refreshIcon()
        Analytics.capture(.menuBarDisplayModeChanged, properties: [
            "mode": mode.rawValue,
            "source": "context_menu",
        ])
    }

    private func performContextQuickAction(mode: ViewMode, quickAction: CoolRunQuickAction? = nil) {
        contextPopover.performClose(nil)
        AppNavigationRouter.shared.open(mode, quickAction: quickAction)
    }

    private func observeSettingsWindowLifecycle() {
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.hideDockIconIfNoWindowsRemain()
            }
        }
    }

    private func hideDockIconIfNoWindowsRemain() {
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { window in
                window.isVisible && window.canBecomeKey
            }

            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func startIconAnimation() {
        iconTimer?.invalidate()
        iconTimer = nil
        activeAnimationFramesPerSecond = settings.showMenuBarCoinIcon
            ? settings.menuBarAnimationRate.framesPerSecond
            : nil

        if !settings.showMenuBarCoinIcon {
            coinPhase = 0
            statusItem?.button?.image = nil
        } else if activeAnimationFramesPerSecond == nil {
            coinPhase = 0
            statusItem?.button?.image = CoinIconRenderer.image(
                phase: coinPhase,
                motion: settings.menuBarCoinMotion,
                appearance: settings.menuBarCoinAppearance
            )
        }

        // 动画关闭时仍以 1Hz 更新日期、CPU、内存和网速文本。
        let timerFrequency = activeAnimationFramesPerSecond ?? 1
        let timer = Timer(timeInterval: 1 / timerFrequency, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshIcon()
            }
        }
        timer.tolerance = min(0.05, 0.25 / timerFrequency)
        // Picker/Menu tracking 会切换 RunLoop mode；注册到 common modes，避免切换动画后
        // 新计时器停留在默认 mode，直到其它设置再次触发重建才恢复。
        RunLoop.main.add(timer, forMode: .common)
        iconTimer = timer
        refreshIcon()
    }

    @MainActor
    private func refreshIcon() {
        if !settings.showMenuBarCoinIcon {
            statusItem?.button?.image = nil
        } else if let framesPerSecond = activeAnimationFramesPerSecond {
            let cpuUsage = min(max(viewModel.snapshot.cpu.usage, 0), 1)
            let revolutionsPerSecond = (0.35 + cpuUsage * 2.15) * settings.menuBarCoinMotion.speedMultiplier
            coinPhase = (coinPhase + (.pi * 2 * revolutionsPerSecond / framesPerSecond))
                .truncatingRemainder(dividingBy: .pi * 2)
            statusItem?.button?.image = CoinIconRenderer.image(
                phase: coinPhase,
                motion: settings.menuBarCoinMotion,
                appearance: settings.menuBarCoinAppearance
            )
        }

        if settings.menuBarCompositionStyle == .rotation,
           Date().timeIntervalSince(lastMenuBarRotationAt) >= TimeInterval(settings.menuBarRotationSeconds) {
            rotationUsesSecondary.toggle()
            lastMenuBarRotationAt = Date()
        }

        // 组合只改变展示，不改变任何模块的采样与轮询频率。
        let rendered = MenuBarCompositionFormatter.render(
            style: settings.menuBarCompositionStyle,
            primary: settings.menuBarDisplayMode,
            secondary: settings.menuBarSecondaryDisplayMode,
            rotationUsesSecondary: rotationUsesSecondary,
            value: { [weak self] mode, compact in
                self?.menuBarValue(for: mode, compact: compact) ?? "--"
            }
        )
        let nextTitle = settings.showMenuBarCoinIcon ? " \(rendered)" : rendered
        let activeMode = MenuBarCompositionFormatter.activeMode(
            style: settings.menuBarCompositionStyle,
            primary: settings.menuBarDisplayMode,
            secondary: settings.menuBarSecondaryDisplayMode,
            rotationUsesSecondary: rotationUsesSecondary
        )

        let compactTitle = compactStatusText(nextTitle, limit: statusTitleLimit(for: activeMode))
        if statusItem?.button?.title != compactTitle {
            statusItem?.button?.title = compactTitle
        }
        updateStatusItemLength(for: compactTitle, activeMode: activeMode)
    }

    private func menuBarValue(for mode: MenuBarDisplayMode, compact: Bool) -> String {
        switch mode {
        case .goldPrice:
            return compact ? "Au \(goldPriceText)" : goldPriceText
        case .date:
            return menuBarDateText
        case .cpu:
            return "\(compact ? "C" : "CPU") \(percentageText(viewModel.snapshot.cpu.usage))"
        case .memory:
            return "\(compact ? "M" : "MEM") \(percentageText(viewModel.snapshot.memory.usage))"
        case .network:
            let network = viewModel.snapshot.network
            return "↓\(compactNetworkSpeedText(network.downloadSpeed)) ↑\(compactNetworkSpeedText(network.uploadSpeed))"
        case .english:
            let playback = englishLearning.state == .playing ? " ▶" : ""
            return compactStatusText(englishLearning.menuBarText, limit: compact ? 8 : 12) + playback
        case .codex:
            return compact ? compactStatusText(codexMenuBarText.replacingOccurrences(of: "Codex", with: "Cx"), limit: 10) : codexMenuBarText
        case .claude:
            return compact ? compactStatusText(claudeMenuBarText.replacingOccurrences(of: "Claude", with: "Cl"), limit: 10) : claudeMenuBarText
        case .countdown:
            return compactStatusText(countdownMenuBarText, limit: compact ? 8 : 14)
        }
    }

    // 菜单栏日期文本
    private var menuBarDateText: String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        switch settings.language {
        case .chinese:
            formatter.dateFormat = "M/d E"
        case .japanese:
            formatter.dateFormat = "M/d E"
        case .korean:
            formatter.dateFormat = "M/d E"
        case .english:
            formatter.dateFormat = "MMM d E"
        }
        return formatter.string(from: Date())
    }

    private func percentageText(_ value: Double) -> String {
        String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }

    private func networkSpeedText(_ bytesPerSecond: UInt64) -> String {
        Self.networkSpeedFormatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    private func compactNetworkSpeedText(_ bytesPerSecond: UInt64) -> String {
        let value = Double(bytesPerSecond)
        if value >= 1024 * 1024 {
            return String(format: "%.1fM", value / 1024 / 1024)
        }
        if value >= 1024 {
            return String(format: "%.0fK", value / 1024)
        }
        return "\(bytesPerSecond)B"
    }

    private func compactStatusText(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = text.prefix(max(limit - 1, 1))
        return "\(prefix)…"
    }

    private func statusTitleLimit(for mode: MenuBarDisplayMode) -> Int {
        if settings.menuBarCompositionStyle == .pair { return 24 }
        switch mode {
        case .goldPrice: return 18
        case .date: return 12
        case .cpu, .memory: return 8
        case .network: return 14
        case .english: return 14
        case .codex, .claude: return 18
        case .countdown: return 14
        }
    }

    private func updateStatusItemLength(
        for title: String? = nil,
        activeMode: MenuBarDisplayMode? = nil
    ) {
        guard let button = statusItem?.button else { return }
        let displayTitle = title ?? button.title
        let mode = activeMode ?? MenuBarCompositionFormatter.activeMode(
            style: settings.menuBarCompositionStyle,
            primary: settings.menuBarDisplayMode,
            secondary: settings.menuBarSecondaryDisplayMode,
            rotationUsesSecondary: rotationUsesSecondary
        )
        let titleWidth = displayTitle.size(withAttributes: [.font: button.font ?? Self.statusTitleFont]).width
        let imageWidth = button.image.map { $0.size.width + 4 } ?? 0
        let measuredLength = ceil(titleWidth + imageWidth + 14)
        let length = min(
            max(measuredLength, minimumStatusItemLength(for: mode)),
            maximumStatusItemLength(for: mode)
        )
        statusItem?.length = length
    }

    private func minimumStatusItemLength(for mode: MenuBarDisplayMode) -> CGFloat {
        if settings.menuBarCompositionStyle == .pair { return 118 }
        switch mode {
        case .goldPrice: return 76
        case .date: return 82
        case .cpu, .memory: return 72
        case .network: return 116
        case .english: return 92
        case .codex, .claude: return 76
        case .countdown: return 76
        }
    }

    private func maximumStatusItemLength(for mode: MenuBarDisplayMode) -> CGFloat {
        if settings.menuBarCompositionStyle == .pair { return 184 }
        switch mode {
        case .goldPrice: return 132
        case .date: return 124
        case .cpu, .memory: return 84
        case .network: return 136
        case .english: return 142
        case .codex, .claude: return 150
        case .countdown: return 132
        }
    }

    private var codexMenuBarText: String {
        guard case let .ready(snapshot) = codexViewModel.state,
              let window = snapshot.limits.first?.windows.first,
              let remaining = window.remainingPercent else {
            return "Codex"
        }
        return "Codex \(quotaMeterText(remaining)) \(remaining)%"
    }

    private var claudeMenuBarText: String {
        guard case let .ready(snapshot) = claudeViewModel.state,
              let window = snapshot.windows.first,
              let remaining = window.remainingPercent else {
            return "Claude"
        }
        return "Claude \(quotaMeterText(remaining)) \(remaining)%"
    }

    // 字符版迷你用量条，例如 ▰▰▰▱▱
    private func quotaMeterText(_ remainingPercent: Int) -> String {
        let segments = 5
        let filled = max(0, min(segments, Int((Double(remainingPercent) / 100 * Double(segments)).rounded())))
        return String(repeating: "▰", count: filled) + String(repeating: "▱", count: segments - filled)
    }

    private var countdownMenuBarText: String {
        guard let nearest = CountdownManager.shared.nearestUpcoming() else {
            return MenuBarDisplayMode.countdown.displayName(lang: settings.language)
        }
        if nearest.days == 0 {
            return "\(nearest.event.name) \(LocalizedString.countdown("today", lang: settings.language))"
        }
        return LocalizedString.l(
            settings.language,
            en: "\(nearest.event.name) \(nearest.days)d",
            zh: "\(nearest.event.name) \(nearest.days)天",
            ja: "\(nearest.event.name) \(nearest.days)日",
            ko: "\(nearest.event.name) \(nearest.days)일"
        )
    }

    private static let statusTitleFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize(for: .small),
        weight: .regular
    )

    private static let networkSpeedFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private func startGoldPriceUpdates() {
        goldPriceTask?.cancel()
        goldPriceTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshGoldPrice()
                let refreshInterval = self?.settings.goldRefreshRate.duration ?? .seconds(60)
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    private func refreshGoldPrice() async {
        do {
            let quote = try await goldPriceService.fetchCNYPerGram()
            goldPriceText = Self.menuBarGoldText(for: quote)
            GoldPriceStore.shared.latestQuote = quote
            GoldPriceStore.shared.addPrice(quote.cnyPerGram, timestamp: quote.updatedAt, source: quote.source)
            GoldPriceStore.shared.checkFreshness()
            GoldPriceStore.shared.lastFetchFailed = false
            GoldPriceAlertManager.shared.handle(quote: quote)
            Analytics.capture(.goldPriceFetched, minimumInterval: 60 * 60)
        } catch {
            if goldPriceText == "--" {
                goldPriceText = goldPriceFallbackText(for: error)
            }
            // 失败路径也要刷新数据健康状态，避免旧数据一直显示"健康"
            GoldPriceStore.shared.checkFreshness()
            GoldPriceStore.shared.lastFetchFailed = true
            Analytics.capture(.goldPriceFetchFailed, properties: [
                "error_type": String(describing: type(of: error)),
            ])
        }
        refreshIcon()
    }

    // 分析页手动刷新入口（金价模块头部按钮调用）
    func refreshGoldPriceNow() async {
        await refreshGoldPrice()
    }

    private func goldPriceFallbackText(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("frequency") || message.contains("rate") || message.contains("call") {
            return LocalizedString.goldPrice("rate_limited")
        }
        if message.contains("internet") || message.contains("network") || message.contains("offline") {
            return LocalizedString.goldPrice("network_error")
        }
        return LocalizedString.goldPrice("parse_error")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            LocalReminderCenter.shared.handle(response)
            completionHandler()
        }
    }
}

private struct StatusContextMenuView: View {
    let showToday: () -> Void
    let addCountdown: () -> Void
    let recordGoldTrade: () -> Void
    let refreshAll: () -> Void
    let toggleEnglishPlayback: () -> Void
    let previousEnglishItem: () -> Void
    let nextEnglishItem: () -> Void
    let stopEnglishPlayback: () -> Void
    let selectDisplayMode: (MenuBarDisplayMode) -> Void
    let openSettings: () -> Void
    let quit: () -> Void
    @ObservedObject private var englishLearning = EnglishLearningManager.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            quickActions

            Divider()

            displayModePicker

            Divider()

            Button(action: toggleEnglishPlayback) {
                Label(
                    englishPlaybackTitle,
                    systemImage: englishLearning.state == .playing ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 32)

            Divider()

            HStack(spacing: 0) {
                contextButton(LocalizedString.common("previous", lang: settings.language), systemImage: "backward.end.fill", action: previousEnglishItem)
                contextButton(LocalizedString.common("next", lang: settings.language), systemImage: "forward.end.fill", action: nextEnglishItem)
                contextButton(LocalizedString.common("stop", lang: settings.language), systemImage: "stop.fill", action: stopEnglishPlayback)
            }
            .frame(height: 32)

            Divider()

            SettingsLink()
                .simultaneousGesture(TapGesture().onEnded(openSettings))
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)

            Divider()

            Button(action: quit) {
                Label(LocalizedString.menuBar("quit"), systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .padding(.vertical, 4)
        .frame(width: 216)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedString.l(settings.language, en: "Quick actions", zh: "快捷操作", ja: "クイック操作", ko: "빠른 작업"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            HStack(spacing: 4) {
                quickActionButton(icon: "sun.max.fill", help: LocalizedString.l(settings.language, en: "Show Today", zh: "查看今天", ja: "今日を表示", ko: "오늘 보기"), action: showToday)
                quickActionButton(icon: "calendar.badge.plus", help: LocalizedString.l(settings.language, en: "Add countdown", zh: "添加倒数日", ja: "追加", ko: "카운트다운 추가"), action: addCountdown)
                quickActionButton(icon: "plus.forwardslash.minus", help: LocalizedString.l(settings.language, en: "Record trade", zh: "记录交易", ja: "取引を記録", ko: "거래 기록"), action: recordGoldTrade)
                quickActionButton(icon: "arrow.clockwise", help: LocalizedString.l(settings.language, en: "Refresh", zh: "全部刷新", ja: "更新", ko: "새로고침"), action: refreshAll)
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 6)
    }

    private func quickActionButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var displayModePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedString.menuBar("display_mode", lang: settings.language))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            LazyVGrid(columns: displayModeColumns, alignment: .leading, spacing: 4) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Button {
                        selectDisplayMode(mode)
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(settings.menuBarDisplayMode == mode ? Color.accentColor : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(settings.menuBarDisplayMode == mode ? Color.accentColor.opacity(0.14) : Color.clear)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(mode.displayName(lang: settings.language))
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 6)
    }

    private var displayModeColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 28), spacing: 4), count: 5)
    }

    private var englishPlaybackTitle: String {
        switch englishLearning.state {
        case .idle: return LocalizedString.menuBar("start_english", lang: settings.language)
        case .playing: return LocalizedString.menuBar("pause_english", lang: settings.language)
        case .paused: return LocalizedString.menuBar("resume_english", lang: settings.language)
        }
    }

    private func contextButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

enum CoinIconRenderer {
    private struct MotionState {
        var centerX: CGFloat = 12
        var centerY: CGFloat = 9
        var width: CGFloat = 17
        var height: CGFloat = 13.2
        var symbolRotation: CGFloat = 0
        var shinePhase: CGFloat = 0
        var sparkleAmount: CGFloat = 0
        var shadowWidth: CGFloat = 0
        var shadowAlpha: CGFloat = 0
    }

    private struct Palette {
        var face: NSColor
        var rim: NSColor
        var detail: NSColor
        var symbol: String?
        var symbolColor: NSColor
        var drawsSquareHole = false
    }

    static func image(
        phase: Double,
        motion: MenuBarCoinMotion,
        appearance: MenuBarCoinAppearance
    ) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let state = motionState(phase: CGFloat(phase), motion: motion)
        let palette = palette(appearance: appearance)

        if state.shadowAlpha > 0 {
            let shadowRect = NSRect(
                x: state.centerX - state.shadowWidth / 2,
                y: 1.1,
                width: state.shadowWidth,
                height: 2.2
            )
            NSColor.black.withAlphaComponent(state.shadowAlpha).setFill()
            NSBezierPath(ovalIn: shadowRect).fill()
        }

        let coinRect = NSRect(
            x: state.centerX - state.width / 2,
            y: state.centerY - state.height / 2,
            width: state.width,
            height: state.height
        )

        let coin = NSBezierPath(ovalIn: coinRect)
        palette.face.setFill()
        coin.fill()

        palette.rim.setStroke()
        coin.lineWidth = 1.4
        coin.stroke()

        if state.width > 6.6 {
            let inner = NSBezierPath(ovalIn: coinRect.insetBy(dx: 2.1, dy: 2.1))
            palette.detail.withAlphaComponent(0.62).setStroke()
            inner.lineWidth = 0.9
            inner.stroke()

            let shine = NSBezierPath()
            shine.lineWidth = 1.0
            shine.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.75).setStroke()
            let shineOffset = sin(state.shinePhase) * state.width * 0.18
            shine.move(to: NSPoint(x: coinRect.midX - state.width * 0.20 + shineOffset, y: coinRect.midY + 3.1))
            shine.line(to: NSPoint(x: coinRect.midX + state.width * 0.10 + shineOffset, y: coinRect.midY + 3.8))
            shine.stroke()

            if palette.drawsSquareHole {
                drawSquareHole(in: coinRect, palette: palette)
            } else if let symbolText = palette.symbol {
                drawSymbol(
                    symbolText,
                    color: palette.symbolColor,
                    center: NSPoint(x: coinRect.midX, y: coinRect.midY),
                    rotation: state.symbolRotation,
                    compact: symbolText == "福"
                )
            }
        } else {
            let edge = NSBezierPath()
            edge.lineWidth = 1.8
            edge.lineCapStyle = .round
            palette.detail.setStroke()
            edge.move(to: NSPoint(x: coinRect.midX, y: coinRect.minY + 1.4))
            edge.line(to: NSPoint(x: coinRect.midX, y: coinRect.maxY - 1.4))
            edge.stroke()
        }

        let appearanceSparkle: CGFloat = appearance == .starlight ? 0.55 : 0
        drawSparkle(
            amount: max(state.sparkleAmount, appearanceSparkle),
            at: NSPoint(x: min(size.width - 2.1, coinRect.maxX + 1.2), y: min(size.height - 2.1, coinRect.maxY + 0.2)),
            color: appearance == .rising ? NSColor.systemGreen : NSColor.systemYellow
        )

        image.isTemplate = false
        return image
    }

    private static func motionState(phase: CGFloat, motion: MenuBarCoinMotion) -> MotionState {
        switch motion {
        case .classicFlip:
            let faceAmount = abs(cos(phase))
            return MotionState(
                width: 2.8 + 14.2 * faceAmount,
                shinePhase: phase
            )
        case .luckyBounce:
            let bounce = abs(sin(phase))
            return MotionState(
                centerY: 8.6 + 2.5 * bounce,
                width: 16.4 - 1.2 * bounce,
                height: 12.8 + 0.9 * bounce,
                symbolRotation: sin(phase) * 0.12,
                shinePhase: phase * 1.4,
                sparkleAmount: max(0, sin(phase - 0.35)) * 0.75,
                shadowWidth: 13 - 4 * bounce,
                shadowAlpha: 0.16 - 0.08 * bounce
            )
        case .coinToss:
            let lift = abs(sin(phase))
            let faceAmount = abs(cos(phase * 2))
            return MotionState(
                centerY: 8.3 + 3.3 * lift,
                width: 2.9 + 13.6 * faceAmount,
                symbolRotation: phase,
                shinePhase: phase * 2,
                sparkleAmount: max(0, sin(phase)) * 0.6,
                shadowWidth: 14 - 6 * lift,
                shadowAlpha: 0.18 - 0.1 * lift
            )
        case .rolling:
            return MotionState(
                centerX: 12 + sin(phase) * 3.2,
                centerY: 8.8 + abs(cos(phase)) * 0.7,
                width: 16.2,
                symbolRotation: -phase,
                shinePhase: phase * 1.8,
                shadowWidth: 13.5,
                shadowAlpha: 0.14
            )
        case .shimmer:
            let pulse = 1 + sin(phase) * 0.035
            return MotionState(
                width: 16.6 * pulse,
                height: 13.2 * pulse,
                shinePhase: phase * 2.4,
                sparkleAmount: max(0, sin(phase)) * 0.95
            )
        }
    }

    private static func palette(appearance: MenuBarCoinAppearance) -> Palette {
        switch appearance {
        case .yuan:
            return Palette(
                face: NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.18, alpha: 1),
                rim: NSColor(calibratedRed: 0.86, green: 0.48, blue: 0.05, alpha: 1),
                detail: NSColor(calibratedRed: 0.82, green: 0.42, blue: 0.02, alpha: 1),
                symbol: "¥",
                symbolColor: NSColor(calibratedRed: 0.78, green: 0.36, blue: 0.01, alpha: 1)
            )
        case .lucky:
            return Palette(
                face: NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.12, alpha: 1),
                rim: NSColor(calibratedRed: 0.78, green: 0.22, blue: 0.08, alpha: 1),
                detail: NSColor(calibratedRed: 0.86, green: 0.34, blue: 0.04, alpha: 1),
                symbol: "福",
                symbolColor: NSColor(calibratedRed: 0.72, green: 0.08, blue: 0.04, alpha: 1)
            )
        case .rising:
            return Palette(
                face: NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.24, alpha: 1),
                rim: NSColor(calibratedRed: 0.24, green: 0.58, blue: 0.28, alpha: 1),
                detail: NSColor(calibratedRed: 0.19, green: 0.50, blue: 0.24, alpha: 1),
                symbol: "↗",
                symbolColor: NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.19, alpha: 1)
            )
        case .ancient:
            return Palette(
                face: NSColor(calibratedRed: 0.88, green: 0.58, blue: 0.15, alpha: 1),
                rim: NSColor(calibratedRed: 0.48, green: 0.27, blue: 0.08, alpha: 1),
                detail: NSColor(calibratedRed: 0.40, green: 0.22, blue: 0.06, alpha: 1),
                symbol: nil,
                symbolColor: .clear,
                drawsSquareHole: true
            )
        case .starlight:
            return Palette(
                face: NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.38, alpha: 1),
                rim: NSColor(calibratedRed: 0.73, green: 0.48, blue: 0.12, alpha: 1),
                detail: NSColor(calibratedRed: 0.68, green: 0.42, blue: 0.08, alpha: 1),
                symbol: "✦",
                symbolColor: NSColor(calibratedRed: 0.46, green: 0.26, blue: 0.04, alpha: 1)
            )
        }
    }

    private static func drawSymbol(
        _ text: String,
        color: NSColor,
        center: NSPoint,
        rotation: CGFloat,
        compact: Bool
    ) {
        let symbol = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: compact ? 7.1 : 8.5, weight: .bold),
            .foregroundColor: color
        ]
        let symbolSize = symbol.size(withAttributes: attributes)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: rotation)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()
        symbol.draw(
            at: NSPoint(x: center.x - symbolSize.width / 2, y: center.y - symbolSize.height / 2),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawSquareHole(in coinRect: NSRect, palette: Palette) {
        let side = min(4.5, coinRect.width * 0.34)
        let holeRect = NSRect(
            x: coinRect.midX - side / 2,
            y: coinRect.midY - side / 2,
            width: side,
            height: side
        )
        palette.detail.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: holeRect, xRadius: 0.6, yRadius: 0.6).fill()
        NSColor.white.withAlphaComponent(0.32).setStroke()
        let rim = NSBezierPath(roundedRect: holeRect.insetBy(dx: 0.7, dy: 0.7), xRadius: 0.3, yRadius: 0.3)
        rim.lineWidth = 0.6
        rim.stroke()
    }

    private static func drawSparkle(amount: CGFloat, at point: NSPoint, color: NSColor) {
        guard amount > 0.05 else { return }
        let radius = 1 + amount * 1.5
        let sparkle = NSBezierPath()
        sparkle.lineCapStyle = .round
        sparkle.lineWidth = 0.8 + amount * 0.45
        sparkle.move(to: NSPoint(x: point.x - radius, y: point.y))
        sparkle.line(to: NSPoint(x: point.x + radius, y: point.y))
        sparkle.move(to: NSPoint(x: point.x, y: point.y - radius))
        sparkle.line(to: NSPoint(x: point.x, y: point.y + radius))
        color.withAlphaComponent(0.45 + amount * 0.5).setStroke()
        sparkle.stroke()
    }
}

private extension Double {
    var goldPriceText: String {
        "¥" + formatted(.number.precision(.fractionLength(2))) + "/g"
    }
}

private extension MacAppDelegate {
    // 金价模式菜单栏文本：有官方涨跌幅时附带展示，如 "¥886.16 -0.25%"
    static func menuBarGoldText(for quote: GoldPriceQuote) -> String {
        guard let rate = quote.changeRatePercent else {
            return quote.cnyPerGram.goldPriceText
        }
        let price = "¥" + quote.cnyPerGram.formatted(.number.precision(.fractionLength(2)))
        let percent = rate.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%"
        return "\(price) \(percent)"
    }
}
#endif
