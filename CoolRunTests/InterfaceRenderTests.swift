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

    // MARK: - 事件影响卡片文案

    private func makeEventEvidence(state: GoldEvidenceState, direction: GoldImpactDirection) -> GoldEventEvidence {
        GoldEventEvidence(
            id: "\(state.rawValue)-\(UUID().uuidString)",
            kind: state == .observed ? .centralBankStatement : .policyExpectation,
            state: state,
            direction: direction,
            summary: "美联储讲话强调通胀目标",
            source: "证券时报",
            link: state == .observed ? URL(string: "https://stcn.com/example") : nil,
            observedAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
    }

    private func makeEventImpact(
        direction: GoldImpactDirection,
        confidence: GoldImpactConfidence,
        risk: GoldVolatilityRisk,
        dataState: GoldIntelligenceDataState
    ) -> GoldEventImpact {
        GoldEventImpact.make(
            direction: direction,
            confidence: confidence,
            volatilityRisk: risk,
            headline: "美联储抗通胀立场与收益率、黄金价格反应相互印证",
            evidence: [
                makeEventEvidence(state: .observed, direction: direction),
                makeEventEvidence(state: .inferred, direction: direction)
            ],
            counterRisks: ["市场已快速定价，后续数据转弱可能逆转走势"],
            updatedAt: Date(timeIntervalSince1970: 1_788_000_000),
            dataState: dataState,
            language: .chinese
        )
    }

    func testEventImpactPresentationUnavailableShowsNoTradeAction() {
        let impact = GoldEventImpact.unavailable(now: Date(), language: .chinese)
        let presentation = GoldEventImpactPresentation(impact: impact, language: .chinese)

        XCTAssertTrue(presentation.dataStateText.contains("不可用"))
        for text in [presentation.directionText, presentation.confidenceText, presentation.dataStateText, presentation.riskText] {
            XCTAssertFalse(text.contains("卖出"))
            XCTAssertFalse(text.contains("减仓"))
            XCTAssertFalse(text.contains("持有"))
        }
    }

    func testEventImpactPresentationPartialShowsIncompleteData() {
        let impact = makeEventImpact(direction: .bearish, confidence: .low, risk: .elevated, dataState: .partial)
        let presentation = GoldEventImpactPresentation(impact: impact, language: .chinese)

        XCTAssertTrue(presentation.dataStateText.contains("不完整"))
        XCTAssertFalse(presentation.confidenceText.contains("高"))
    }

    func testEventImpactPresentationStaleShowsCacheLabel() {
        let impact = makeEventImpact(direction: .bearish, confidence: .low, risk: .elevated, dataState: .stale)
        let presentation = GoldEventImpactPresentation(impact: impact, language: .chinese)

        XCTAssertTrue(presentation.dataStateText.contains("缓存"))
    }

    func testEventImpactPresentationBearishHighShowsDirectionalLabels() {
        let impact = makeEventImpact(direction: .bearish, confidence: .high, risk: .elevated, dataState: .live)
        let presentation = GoldEventImpactPresentation(impact: impact, language: .chinese)

        XCTAssertEqual(presentation.directionText, "短线偏空")
        XCTAssertTrue(presentation.confidenceText.contains("高"))
        XCTAssertTrue(presentation.riskText.contains("升高"))
    }

    func testEventImpactPresentationBullishHighRiskKeepsHighRiskVisible() {
        let highRisk = makeEventImpact(direction: .bullish, confidence: .high, risk: .high, dataState: .live)
        let normalRisk = makeEventImpact(direction: .bullish, confidence: .high, risk: .normal, dataState: .live)

        let highPresentation = GoldEventImpactPresentation(impact: highRisk, language: .chinese)
        let normalPresentation = GoldEventImpactPresentation(impact: normalRisk, language: .chinese)

        XCTAssertEqual(highPresentation.directionText, "短线偏多")
        XCTAssertNotEqual(highPresentation.riskText, normalPresentation.riskText)
        XCTAssertFalse(highPresentation.riskText.contains("低"))
        XCTAssertFalse(highPresentation.riskText.contains("正常"))
    }

    func testEventImpactEvidenceStatesHaveDistinctLabels() {
        let observedLabel = GoldEventImpactPresentation.evidenceLabel(for: .observed, language: .chinese)
        let inferredLabel = GoldEventImpactPresentation.evidenceLabel(for: .inferred, language: .chinese)

        XCTAssertNotEqual(observedLabel, inferredLabel)
        XCTAssertTrue(observedLabel.contains("确认"))
        XCTAssertTrue(inferredLabel.contains("推断"))
    }

    func testEventImpactCardRendersAtMenuBarWidth() throws {
        let impact = GoldEventImpact.make(
            direction: .bearish,
            confidence: .high,
            volatilityRisk: .elevated,
            headline: "美联储抗通胀立场与收益率、黄金价格反应相互印证",
            evidence: [
                makeEventEvidence(state: .observed, direction: .bearish),
                makeEventEvidence(state: .observed, direction: .bearish),
                makeEventEvidence(state: .observed, direction: .bearish),
                makeEventEvidence(state: .observed, direction: .bearish),
                makeEventEvidence(state: .inferred, direction: .bearish),
                makeEventEvidence(state: .inferred, direction: .bearish)
            ],
            counterRisks: ["市场已快速定价，后续数据转弱可能逆转走势"],
            updatedAt: Date(),
            dataState: .live,
            language: .chinese
        )

        try render(
            EventImpactCard(impact: impact, isLoading: false)
                .padding(10)
                .frame(width: 304)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 460),
            filename: "coolrun-event-impact-preview.png"
        )
    }

    // MARK: - 一周方向预测卡片

    private func makeWeeklyForecast(
        direction: GoldWeeklyForecastDirection = .up,
        compatibility: GoldForecastSourceCompatibility = .verified,
        generatedAt: Date = Date(timeIntervalSince1970: 1_788_000_000)
    ) -> GoldWeeklyForecast {
        let target = Calendar.goldShanghai.date(byAdding: .day, value: 7, to: generatedAt)!
        return GoldWeeklyForecast(
            direction: direction,
            confidence: .medium,
            startPrice: 600,
            expectedPrice: 606,
            expectedReturn: 0.01,
            p10: 594,
            p50: 606,
            p90: 618,
            generatedAt: generatedAt,
            targetDate: target,
            dataUpdatedAt: generatedAt,
            currentPriceSource: compatibility == .proxy ? "CZB-JCJ" : "JD-MS",
            historySource: GoldMarketDataService.historySourceID,
            sourceCompatibility: compatibility,
            components: GoldWeeklyForecastComponents(
                trend: 0.4, momentum: 0.3, meanReversion: -0.1, bootstrap: 0.3, composite: 0.275
            ),
            reasons: ["fixture reason"],
            counterRisks: ["fixture risk"],
            modelVersion: GoldWeeklyForecastPolicy.modelVersion
        )
    }

    private func makeWeeklyBacktest() -> GoldWeeklyForecastBacktestSummary {
        GoldWeeklyForecastBacktestSummary(
            resolvedCount: 40,
            classCounts: [.up: 15, .flat: 12, .down: 13],
            overallAccuracy: 0.55,
            balancedAccuracy: 0.46,
            majorityBaselineAccuracy: 0.40,
            meanAbsoluteReturnError: 0.012,
            confusionMatrix: [:],
            passedReleaseGate: true,
            failureReasons: []
        )
    }

    private func makeWeeklySnapshot(
        status: GoldWeeklyForecastStatus = .ready,
        direction: GoldWeeklyForecastDirection = .up,
        compatibility: GoldForecastSourceCompatibility = .verified,
        message: String = "fixture"
    ) -> GoldWeeklyForecastSnapshot {
        GoldWeeklyForecastSnapshot(
            status: status,
            forecast: status == .ready
                ? makeWeeklyForecast(direction: direction, compatibility: compatibility)
                : nil,
            backtest: status == .ready ? makeWeeklyBacktest() : nil,
            message: message,
            updatedAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
    }

    func testWeeklyForecastPresentationReadyUpAcrossLanguages() {
        let snapshot = makeWeeklySnapshot(direction: .up)
        let expectations: [(AppLanguage, String, String)] = [
            (.chinese, "上涨", "信心：中"),
            (.english, "Up", "Confidence: medium"),
            (.japanese, "上昇", "信頼度：中"),
            (.korean, "상승", "신뢰도: 보통")
        ]
        for (language, directionWord, confidenceWord) in expectations {
            let presentation = GoldWeeklyForecastPresentation(snapshot: snapshot, language: language)
            XCTAssertEqual(presentation.directionText, directionWord)
            XCTAssertEqual(presentation.confidenceText, confidenceWord)
            XCTAssertTrue(presentation.targetText?.contains("2026") ?? false, language.rawValue)
            XCTAssertTrue(presentation.statusText.contains("40"), language.rawValue)
            XCTAssertNil(presentation.sourceText)
        }
    }

    func testWeeklyForecastPresentationReadyFlatAndDown() {
        let flat = GoldWeeklyForecastPresentation(
            snapshot: makeWeeklySnapshot(direction: .flat), language: .chinese
        )
        XCTAssertEqual(flat.directionText, "持平")
        let down = GoldWeeklyForecastPresentation(
            snapshot: makeWeeklySnapshot(direction: .down), language: .chinese
        )
        XCTAssertEqual(down.directionText, "下跌")
    }

    func testWeeklyForecastPresentationNonReadyStatusesShowMessage() {
        let statuses: [GoldWeeklyForecastStatus] = [
            .staleData, .sourceMismatch, .validationFailed, .sourceUnavailable
        ]
        for status in statuses {
            let presentation = GoldWeeklyForecastPresentation(
                snapshot: makeWeeklySnapshot(status: status), language: .chinese
            )
            XCTAssertEqual(presentation.statusText, "fixture")
            XCTAssertNil(presentation.directionText)
            XCTAssertNil(presentation.confidenceText)
            XCTAssertNil(presentation.targetText)
            XCTAssertNil(presentation.sourceText)
        }
    }

    func testWeeklyForecastPresentationInsufficientHistoryShowsCounts() {
        let snapshot = GoldWeeklyForecastSnapshot(
            status: .insufficientHistory,
            forecast: nil,
            backtest: nil,
            message: "历史数据不足：当前 96 个日线收盘点，至少需要 120 个",
            updatedAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
        let presentation = GoldWeeklyForecastPresentation(snapshot: snapshot, language: .chinese)
        XCTAssertTrue(presentation.statusText.contains("96"))
        XCTAssertTrue(presentation.statusText.contains("120"))
    }

    func testWeeklyForecastPresentationProxyShowsReferenceDailyClosesNote() {
        let snapshot = makeWeeklySnapshot(compatibility: .proxy)
        let presentation = GoldWeeklyForecastPresentation(snapshot: snapshot, language: .chinese)
        XCTAssertEqual(presentation.sourceText, "历史模型使用国内黄金参考日线")
    }

    func testWeeklyForecastPresentationNeverContainsTradingActions() {
        let snapshots = [
            makeWeeklySnapshot(direction: .up),
            makeWeeklySnapshot(direction: .flat),
            makeWeeklySnapshot(direction: .down),
            makeWeeklySnapshot(compatibility: .proxy),
            makeWeeklySnapshot(status: .insufficientHistory),
            makeWeeklySnapshot(status: .staleData),
            makeWeeklySnapshot(status: .sourceMismatch),
            makeWeeklySnapshot(status: .validationFailed),
            makeWeeklySnapshot(status: .sourceUnavailable)
        ]
        let forbidden = ["买入", "卖出", "加仓", "减仓"]
        for language in [AppLanguage.chinese, .english, .japanese, .korean] {
            for snapshot in snapshots {
                let presentation = GoldWeeklyForecastPresentation(snapshot: snapshot, language: language)
                let texts = [
                    presentation.title, presentation.directionText, presentation.confidenceText,
                    presentation.statusText, presentation.targetText, presentation.sourceText
                ].compactMap { $0 }
                for text in texts {
                    for word in forbidden {
                        XCTAssertFalse(text.contains(word), "\(language.rawValue): \(text)")
                    }
                }
            }
        }
    }

    func testWeeklyForecastCardRendersAtMenuBarWidth() throws {
        try render(
            GoldWeeklyForecastCard(
                snapshot: makeWeeklySnapshot(direction: .up),
                isLoading: false
            )
            .padding(10)
            .frame(width: 304)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light),
            size: NSSize(width: 304, height: 420),
            filename: "coolrun-weekly-forecast-preview.png"
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
