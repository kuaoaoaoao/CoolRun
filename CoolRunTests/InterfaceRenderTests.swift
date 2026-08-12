import XCTest
import SwiftUI
import AppKit
@testable import CoolRun

@MainActor
final class InterfaceRenderTests: XCTestCase {
    func testGoldSummaryCardRendersAtMenuBarWidth() throws {
        let updateDate = Date().addingTimeInterval(-1_205)
        let statistics = PriceStatistics(
            currentPrice: 881.64,
            periodHigh: 895.75,
            periodLow: 875.23,
            periodAverage: 883.18,
            change: 0,
            changePercent: 0,
            maxDrawdown: -0.02,
            recordCount: 256,
            firstRecordDate: updateDate.addingTimeInterval(-86_400),
            lastUpdateDate: updateDate
        )
        let quote = GoldPriceQuote(
            cnyPerGram: 881.64,
            updatedAt: updateDate,
            yesterdayPrice: 881.88,
            changeAmount: 0,
            changeRatePercent: 0,
            isMarketClosed: true
        )

        try render(
            GoldPriceSummaryCard(
                statistics: statistics,
                quote: quote,
                health: .stale(116_459),
                lastUpdateDate: updateDate,
                updateInterval: 30,
                language: .chinese
            )
            .padding(10)
            .frame(width: 304)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 152),
            filename: "coolrun-gold-summary-preview.png"
        )
    }

    func testGoldDecisionCardRendersAtMenuBarWidth() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let records = (0..<96).map { index in
            let trend = Double(index) * 0.16
            let rhythm = sin(Double(index) / 5) * 2.4
            return GoldPriceRecord(
                price: 682 + trend + rhythm,
                timestamp: start.addingTimeInterval(Double(index) * 300),
                source: "Preview"
            )
        }
        let snapshot = try XCTUnwrap(GoldAnalysisEngine.makeSnapshot(records: records))
        let report = try XCTUnwrap(
            GoldAdvancedStrategy.analyze(
                records: records,
                snapshot: snapshot,
                signal: nil
            )
        )

        try render(
            GoldDecisionSummaryCard(report: report)
                .padding(10)
                .frame(width: 304),
            size: NSSize(width: 304, height: 180),
            filename: "coolrun-gold-decision-preview.png"
        )
    }

    func testEnglishLearningRendersAtMenuBarSize() throws {
        try render(
            EnglishLearningView()
                .frame(width: 304, height: 464)
                .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 464),
            filename: "coolrun-english-preview.png"
        )
    }

    func testCalendarRendersAtMenuBarSize() throws {
        try render(
            CalendarView()
                .frame(width: 304, height: 464)
                .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 464),
            filename: "coolrun-calendar-preview.png"
        )
    }

    func testProcessMonitorRendersAtMenuBarSize() throws {
        let settings = AppSettings.shared
        let previousModules = (
            cpu: settings.showCPU,
            memory: settings.showMemory,
            storage: settings.showStorage,
            battery: settings.showBattery,
            network: settings.showNetwork,
            uptime: settings.showUptime,
            temperature: settings.showTemperature,
            processes: settings.showProcesses
        )
        let defaults = UserDefaults.standard
        let previousExpanded = defaults.object(forKey: "monitor_process_list_expanded")

        settings.showCPU = false
        settings.showMemory = false
        settings.showStorage = false
        settings.showBattery = false
        settings.showNetwork = false
        settings.showUptime = false
        settings.showTemperature = false
        settings.showProcesses = true
        defaults.set(true, forKey: "monitor_process_list_expanded")

        defer {
            settings.showCPU = previousModules.cpu
            settings.showMemory = previousModules.memory
            settings.showStorage = previousModules.storage
            settings.showBattery = previousModules.battery
            settings.showNetwork = previousModules.network
            settings.showUptime = previousModules.uptime
            settings.showTemperature = previousModules.temperature
            settings.showProcesses = previousModules.processes
            if let previousExpanded {
                defaults.set(previousExpanded, forKey: "monitor_process_list_expanded")
            } else {
                defaults.removeObject(forKey: "monitor_process_list_expanded")
            }
        }

        let snapshot = SystemSnapshot(
            processes: ProcessListMetrics(
                processes: [
                    ProcessMetrics(pid: 101, name: "Google Chrome Helper", cpuUsage: 0.824, memoryBytes: 1_842_000_000, instanceCount: 6, pids: [101]),
                    ProcessMetrics(
                        pid: 102,
                        name: "Xcode",
                        cpuUsage: 0.438,
                        memoryBytes: 2_730_000_000,
                        pids: [102],
                        executablePath: "/Applications/Xcode.app/Contents/MacOS/Xcode"
                    ),
                    ProcessMetrics(pid: 103, name: "Spotify", cpuUsage: 0.127, memoryBytes: 684_000_000, pids: [103]),
                    ProcessMetrics(pid: 104, name: "networkservice", cpuUsage: 0.061, memoryBytes: 126_000_000, pids: [104]),
                    ProcessMetrics(pid: 105, name: "WindowServer", cpuUsage: 0.044, memoryBytes: 508_000_000, pids: [105])
                ],
                totalCount: 427
            )
        )

        try render(
            MonitorPanel(snapshot: snapshot)
                .frame(width: 304, height: 464)
                .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 464),
            filename: "coolrun-process-monitor-preview.png"
        )
    }

    func testCoinStylesRenderAtMenuBarSize() throws {
        let motions = MenuBarCoinMotion.allCases
        let appearances = MenuBarCoinAppearance.allCases
        let cellSize = NSSize(width: 52, height: 38)
        let canvasSize = NSSize(
            width: cellSize.width * CGFloat(motions.count),
            height: cellSize.height * CGFloat(appearances.count)
        )
        let canvas = NSImage(size: canvasSize)

        canvas.lockFocus()
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

        for (row, appearance) in appearances.enumerated() {
            for (column, motion) in motions.enumerated() {
                let cellRect = NSRect(
                    x: CGFloat(column) * cellSize.width,
                    y: canvasSize.height - CGFloat(row + 1) * cellSize.height,
                    width: cellSize.width,
                    height: cellSize.height
                )
                NSColor(calibratedWhite: row.isMultiple(of: 2) ? 0.98 : 0.86, alpha: 1).setFill()
                NSBezierPath(rect: cellRect.insetBy(dx: 1, dy: 1)).fill()

                let icon = CoinIconRenderer.image(
                    phase: .pi / 3,
                    motion: motion,
                    appearance: appearance
                )
                icon.draw(
                    at: NSPoint(
                        x: cellRect.midX - icon.size.width / 2,
                        y: cellRect.midY - icon.size.height / 2
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
        }
        canvas.unlockFocus()

        let representation = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(canvasSize.width * 2),
                pixelsHigh: Int(canvasSize.height * 2),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        representation.size = canvasSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        canvas.draw(in: NSRect(origin: .zero, size: canvasSize))
        NSGraphicsContext.restoreGraphicsState()

        let pngData = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("coolrun-coin-styles-preview.png")
        try pngData.write(to: output)

        XCTAssertEqual(motions.count * appearances.count, 25)
        XCTAssertFalse(pngData.isEmpty)
    }

    func testNotesRendersAtMenuBarSize() throws {
        let store = NotesStore(fileURL: nil)
        let work = try XCTUnwrap(store.addGroup(name: "工作"))
        _ = store.addGroup(name: "生活")
        _ = store.saveNote(
            title: "发布前检查",
            body: "确认构建、更新说明和下载页都已准备好。",
            groupID: work.id,
            now: Date().addingTimeInterval(-180)
        )
        let pinned = try XCTUnwrap(store.saveNote(
            title: "周末采购",
            body: "咖啡豆、牛奶、充电线",
            groupID: nil,
            now: Date().addingTimeInterval(-60)
        ))
        store.togglePin(id: pinned.id)

        try render(
            NotesView(store: store)
                .frame(width: 304, height: 464)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 464),
            filename: "coolrun-notes-preview.png"
        )
    }

    func testClipboardHistoryRendersAtMenuBarSize() throws {
        let suiteName = "CoolRun.InterfaceRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("\(suiteName).pasteboard"))
        let store = ClipboardHistoryStore(fileURL: nil, userDefaults: defaults, pasteboard: pasteboard)
        store.ingest("https://github.com/example/coolrun", at: Date().addingTimeInterval(-20))
        store.ingest("给设置页面补一张深色模式截图", at: Date().addingTimeInterval(-45))
        store.ingest("xcodebuild -project CoolRun.xcodeproj -scheme CoolRun build", at: Date().addingTimeInterval(-90))
        let command = try XCTUnwrap(store.entries.first(where: { $0.text.hasPrefix("xcodebuild") }))
        store.togglePin(id: command.id)

        try render(
            ClipboardHistoryView(store: store)
                .frame(width: 304, height: 464)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 464),
            filename: "coolrun-clipboard-preview.png"
        )
    }

    func testPersonalToolsNavigationRendersAtMenuBarWidth() throws {
        try render(
            ModuleNavigationRail(selection: .constant(.clipboard)) {
                Image(systemName: "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor)),
            size: NSSize(width: 336, height: 52),
            filename: "coolrun-personal-tools-navigation-preview.png"
        )
    }

    func testMenuBarShelfCompactRendersAtPopoverSize() throws {
        try render(
            MenuBarShelfView(layout: .compact)
                .frame(width: 420, height: 236)
                .environment(\.colorScheme, .light),
            size: NSSize(width: 420, height: 236),
            filename: "coolrun-menu-bar-shelf-preview.png"
        )
    }

    func testMenuBarShelfManagementRendersFriendlyApplicationNames() throws {
        let suiteName = "CoolRun.MenuBarShelfRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let windows = [
            MenuBarWindowSnapshot(
                windowID: 1,
                ownerPID: 42,
                ownerBundleIdentifier: "com.apple.controlcenter",
                ownerName: "Control Center",
                title: "Battery",
                frame: CGRect(x: 100, y: 0, width: 24, height: 24),
                isOnScreen: true,
                layer: Int(CGWindowLevelForKey(.statusWindow))
            ),
            MenuBarWindowSnapshot(
                windowID: 2,
                ownerPID: 42,
                ownerBundleIdentifier: "com.apple.controlcenter",
                ownerName: "Control Center",
                title: "com.tencent.xinWeChat",
                frame: CGRect(x: 140, y: 0, width: 24, height: 24),
                isOnScreen: true,
                layer: Int(CGWindowLevelForKey(.statusWindow))
            ),
            MenuBarWindowSnapshot(
                windowID: 3,
                ownerPID: 42,
                ownerBundleIdentifier: "com.apple.controlcenter",
                ownerName: "Control Center",
                title: "com.tencent.qq",
                frame: CGRect(x: 180, y: 0, width: 24, height: 24),
                isOnScreen: true,
                layer: Int(CGWindowLevelForKey(.statusWindow))
            ),
        ]
        let store = MenuBarShelfStore(defaults: defaults, discovery: {
            MenuBarWindowBridge.WindowListResult(
                windows: windows,
                usedPrivateDiscovery: true,
                limitationReason: nil
            )
        }, runningApplicationDiscovery: {
            [
                MenuBarRunningApplicationSnapshot(
                    processIdentifier: 44,
                    bundleIdentifier: "com.tencent.xinWeChat",
                    localizedName: "WeChat",
                    bundleURL: URL(fileURLWithPath: "/Applications/WeChat.app"),
                    kind: .regular
                ),
                MenuBarRunningApplicationSnapshot(
                    processIdentifier: 45,
                    bundleIdentifier: "com.tencent.qq",
                    localizedName: "QQ",
                    bundleURL: URL(fileURLWithPath: "/Applications/QQ.app"),
                    kind: .regular
                ),
            ]
        })
        store.refresh()

        try render(
            MenuBarShelfView(layout: .management, store: store)
                .frame(width: 304, height: 464)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 464),
            filename: "coolrun-menu-bar-shelf-management-preview.png"
        )
    }

    func testMenuBarPermissionMismatchGuidanceRendersAtSettingsWidth() throws {
        let suiteName = "CoolRun.MenuBarPermissionRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MenuBarShelfStore(
            defaults: defaults,
            discovery: {
                MenuBarWindowBridge.WindowListResult(
                    windows: [],
                    usedPrivateDiscovery: true,
                    limitationReason: nil
                )
            },
            runningApplicationDiscovery: { [] }
        )
        let permissions = MenuBarShelfPermissions(
            accessibilityProbe: { false },
            screenCaptureProbe: { true },
            applicationIdentity: MenuBarShelfApplicationIdentity(
                bundlePath: "/Applications/CoolRun.app",
                usesAdHocSignature: true
            ),
            notificationCenter: NotificationCenter()
        )

        try render(
            MenuBarShelfSettingsPanel(store: store, permissions: permissions)
                .frame(width: 520, height: 300, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light),
            size: NSSize(width: 520, height: 300),
            filename: "coolrun-menu-bar-permission-settings-preview.png"
        )
    }

    private func render<Content: View>(
        _ content: Content,
        size: NSSize,
        filename: String
    ) throws {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let pngData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(filename)
        try pngData.write(to: output)

        XCTAssertEqual(representation.size.width, size.width)
        XCTAssertEqual(representation.size.height, size.height)
    }
}
