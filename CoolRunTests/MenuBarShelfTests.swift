#if os(macOS)
import Combine
import CoreGraphics
import XCTest
@testable import CoolRun

@MainActor
final class MenuBarShelfTests: XCTestCase {
    func testAppKitWindowNumberConversionRejectsSyntheticOutOfRangeValues() {
        XCTAssertEqual(
            MenuBarWindowBridge.windowID(fromAppKitWindowNumber: 321),
            CGWindowID(321)
        )
        XCTAssertNil(MenuBarWindowBridge.windowID(fromAppKitWindowNumber: -1))
        XCTAssertNil(
            MenuBarWindowBridge.windowID(
                fromAppKitWindowNumber: Int(UInt64(UInt32.max) + 1)
            )
        )
    }

    func testDividerWindowFallsBackToPreferredWindowServerStatusItem() {
        let windows = [
            window(id: 90, x: 120, title: "Other"),
            window(id: 91, x: 900, title: "CoolRun.MenuBarShelfDivider"),
        ]

        let resolved = MenuBarWindowBridge.statusWindowID(
            matchingQuartzFrame: CGRect(x: 120, y: 0, width: 24, height: 24),
            preferredTitle: "CoolRun.MenuBarShelfDivider",
            in: windows
        )

        XCTAssertEqual(resolved, 91)
    }

    func testDividerWindowFallsBackToMatchingFrameWhenTitleIsAnonymous() {
        let windows = [
            window(id: 90, x: 120, title: ""),
            window(id: 91, x: 180, title: ""),
        ]

        let resolved = MenuBarWindowBridge.statusWindowID(
            matchingQuartzFrame: CGRect(x: 180, y: 0, width: 24, height: 24),
            preferredTitle: "CoolRun.MenuBarShelfDivider",
            in: windows
        )

        XCTAssertEqual(resolved, 91)
    }

    func testIdentityNormalizesNamesAndSurvivesWindowRecreation() {
        let first = MenuBarItemIdentity(ownerKey: "  COM.Example.App ", itemKey: " Sync   State ")
        let recreated = MenuBarItemIdentity(ownerKey: "com.example.app", itemKey: "sync state")

        XCTAssertEqual(first, recreated)
        XCTAssertEqual(first.id, "com.example.app|sync state|0")
    }

    func testReconcilerAssignsStableOccurrencesToDuplicateItems() {
        let windows = [
            window(id: 20, x: 220, title: "Status"),
            window(id: 10, x: 120, title: "Status"),
        ]

        let items = MenuBarItemReconciler.items(from: windows)

        XCTAssertEqual(items.map(\.windowID), [10, 20])
        XCTAssertEqual(items.map(\.identity.occurrence), [0, 1])
        XCTAssertNotEqual(items[0].identity, items[1].identity)
    }

    func testReconcilerExcludesSystemHostsAndDuplicateWindowIDs() {
        let controlCenter = window(
            id: 1,
            x: 100,
            title: "",
            ownerName: "Control Center",
            bundleIdentifier: "com.apple.controlcenter"
        )
        let weChat = window(
            id: 2,
            x: 140,
            title: "Messages",
            ownerName: "WeChat",
            bundleIdentifier: "com.tencent.xinWeChat"
        )

        let items = MenuBarItemReconciler.items(from: [controlCenter, weChat, weChat])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.ownerBundleIdentifier, "com.tencent.xinWeChat")
        XCTAssertEqual(items.first?.displayName, "WeChat")
    }

    func testReconcilerPreservesThirdPartyItemsHostedByControlCenter() {
        let windows = [
            window(id: 1, x: 100, title: "Battery", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
            window(id: 2, x: 130, title: "Clock", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
            window(id: 3, x: 160, title: "com.tencent.xinWeChat", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
            window(id: 4, x: 190, title: "com.tencent.qq", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
            window(id: 5, x: 220, title: "kuao.CoolRun", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
            window(id: 6, x: 250, title: "CoolRun.MenuBarShelfDivider", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
        ]

        let items = MenuBarItemReconciler.items(from: windows)

        XCTAssertEqual(items.map(\.ownerBundleIdentifier), ["com.tencent.xinWeChat", "com.tencent.qq"])
        XCTAssertEqual(items.map(\.ownerPID), [678, 678], "Native events must still target the Control Center host")
        XCTAssertTrue(items.allSatisfy { $0.ownerName != "Control Centre" })
        XCTAssertTrue(items.allSatisfy { !$0.displayName.contains("com.") })
    }

    func testAccessibilityResolverIdentifiesAnonymousControlCenterItem() throws {
        let hostPID: pid_t = 678
        let hostedWindow = window(
            id: 91,
            x: 160,
            title: "",
            ownerName: "Control Centre",
            bundleIdentifier: "com.apple.controlcenter",
            ownerPID: hostPID
        )
        let resolver = MenuBarAccessibilityResolver(
            isTrusted: { true },
            hitTest: { _ in
                MenuBarAccessibilityHit(
                    processIdentifier: 912,
                    bundleIdentifier: "com.tencent.xinWeChat",
                    label: "WeChat"
                )
            }
        )

        let enriched = resolver.enrich(
            [hostedWindow],
            excludingPID: 999,
            currentBundleIdentifier: "kuao.CoolRun"
        )
        let item = try XCTUnwrap(MenuBarItemReconciler.items(from: enriched).first)

        XCTAssertEqual(item.ownerBundleIdentifier, "com.tencent.xinWeChat")
        XCTAssertEqual(item.ownerPID, hostPID, "Native events must keep targeting the Control Center host")
        XCTAssertEqual(item.displayName, "WeChat")
    }

    func testAccessibilityResolverRejectsCurrentAndSystemItems() {
        let windows = [
            window(id: 92, x: 160, title: "", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
            window(id: 93, x: 200, title: "", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
        ]
        let resolver = MenuBarAccessibilityResolver(
            isTrusted: { true },
            hitTest: { point in
                point.x < 190
                    ? MenuBarAccessibilityHit(processIdentifier: 999, bundleIdentifier: "kuao.CoolRun", label: nil)
                    : MenuBarAccessibilityHit(processIdentifier: 688, bundleIdentifier: "com.apple.controlcenter", label: nil)
            }
        )

        let enriched = resolver.enrich(
            windows,
            excludingPID: 999,
            currentBundleIdentifier: "kuao.CoolRun"
        )

        XCTAssertTrue(MenuBarItemReconciler.items(from: enriched).isEmpty)
    }

    func testAccessibilityResolverKeepsCachedIdentityWhenItemMovesOffscreen() {
        var shouldReturnHit = true
        let resolver = MenuBarAccessibilityResolver(
            isTrusted: { true },
            hitTest: { _ in
                guard shouldReturnHit else { return nil }
                return MenuBarAccessibilityHit(
                    processIdentifier: 912,
                    bundleIdentifier: "com.tencent.xinWeChat",
                    label: nil
                )
            }
        )
        let visible = window(
            id: 94,
            x: 160,
            title: "",
            ownerName: "Control Centre",
            bundleIdentifier: "com.apple.controlcenter",
            ownerPID: 678
        )
        _ = resolver.enrich(
            [visible],
            excludingPID: 999,
            currentBundleIdentifier: "kuao.CoolRun"
        )

        shouldReturnHit = false
        let offscreen = MenuBarWindowSnapshot(
            windowID: visible.windowID,
            ownerPID: visible.ownerPID,
            ownerBundleIdentifier: visible.ownerBundleIdentifier,
            ownerName: visible.ownerName,
            title: "",
            frame: CGRect(x: -100, y: 0, width: 24, height: 24),
            isOnScreen: false,
            layer: visible.layer
        )
        let enriched = resolver.enrich(
            [offscreen],
            excludingPID: 999,
            currentBundleIdentifier: "kuao.CoolRun"
        )

        XCTAssertEqual(enriched.first?.title, "com.tencent.xinWeChat")
    }

    func testHostedStatusItemsAreSubtractedFromBackgroundApplications() {
        let hostedWindows = [
            window(id: 10, x: 160, title: "com.tencent.xinWeChat", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
            window(id: 11, x: 190, title: "com.tencent.qq", ownerName: "Control Centre", bundleIdentifier: "com.apple.controlcenter", ownerPID: 678),
        ]
        let items = MenuBarItemReconciler.items(from: hostedWindows)
        let runningApplications = [
            runningApp(pid: 658, bundleID: "com.tencent.xinWeChat", name: "WeChat", path: "/Applications/CoolRunFixtures/WeChat.app"),
            runningApp(pid: 664, bundleID: "com.tencent.qq", name: "QQ", path: "/Applications/CoolRunFixtures/QQ.app"),
        ]

        let backgroundApplications = MenuBarBackgroundApplicationCatalog.applications(
            from: runningApplications,
            excluding: items,
            currentProcessIdentifier: 999,
            currentBundleIdentifier: "kuao.CoolRun"
        )

        XCTAssertTrue(backgroundApplications.isEmpty)
    }

    func testFriendlyApplicationNameIsPrimaryAndBundleIDIsNotPresentationCopy() throws {
        let snapshot = window(
            id: 8,
            x: 180,
            title: "Unread messages",
            ownerName: "WeChat",
            bundleIdentifier: "com.example.fixture.wechat"
        )

        let item = try XCTUnwrap(MenuBarItemReconciler.items(from: [snapshot]).first)

        XCTAssertEqual(item.displayName, "WeChat")
        XCTAssertEqual(item.detailName(lang: .chinese), "Unread messages")
        XCTAssertFalse(item.displayName.contains("com."))
        XCTAssertFalse(MenuBarApplicationMetadata.isUsefulUserFacingName("com.tencent.xinWeChat"))
    }

    func testBackgroundCatalogShowsFriendlyRunningAppsAndFiltersSystemProcesses() {
        let runningApplications = [
            runningApp(pid: 101, bundleID: "com.tencent.xinWeChat", name: "WeChat", path: "/Applications/CoolRunFixtures/WeChat.app"),
            runningApp(pid: 102, bundleID: "com.tencent.qq", name: "QQ", path: "/Applications/CoolRunFixtures/QQ.app"),
            runningApp(pid: 103, bundleID: "com.apple.finder", name: "Finder", path: "/System/Library/CoreServices/Finder.app"),
            runningApp(pid: 104, bundleID: "com.example.dead", name: "Dead App", path: "/Applications/Dead App.app", isTerminated: true),
            runningApp(pid: 105, bundleID: "com.example.agent", name: "Invisible Agent", path: "/Applications/Invisible Agent.app", kind: .prohibited),
        ]

        let applications = MenuBarBackgroundApplicationCatalog.applications(
            from: runningApplications,
            excluding: [],
            currentProcessIdentifier: 999,
            currentBundleIdentifier: "com.example.coolrun"
        )

        XCTAssertEqual(applications.map(\.displayName), ["QQ", "WeChat"])
        XCTAssertTrue(applications.allSatisfy { !$0.displayName.contains("com.") })
    }

    func testBackgroundCatalogDeduplicatesHelpersAndSubtractsStatusItemOwners() {
        let weChatStatusItem = MenuBarItemSnapshot(
            identity: MenuBarItemIdentity(ownerKey: "com.tencent.xinWeChat", itemKey: "Messages"),
            windowID: 50,
            ownerPID: 201,
            ownerBundleIdentifier: "com.tencent.xinWeChat",
            ownerName: "WeChat",
            title: "Messages",
            displayName: "WeChat",
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            isOnScreen: true,
            canMove: true
        )
        let runningApplications = [
            runningApp(pid: 201, bundleID: "com.tencent.xinWeChat", name: "WeChat", path: "/Applications/CoolRunFixtures/WeChat.app"),
            runningApp(pid: 202, bundleID: "com.example.qq.helper", name: "QQ", path: "/Applications/CoolRunFixtures/QQ.app/Contents/Frameworks/QQ Helper.app", kind: .accessory),
            runningApp(pid: 203, bundleID: "com.tencent.qq", name: "QQ", path: "/Applications/CoolRunFixtures/QQ.app"),
        ]

        let applications = MenuBarBackgroundApplicationCatalog.applications(
            from: runningApplications,
            excluding: [weChatStatusItem],
            currentProcessIdentifier: 999,
            currentBundleIdentifier: "com.example.coolrun"
        )

        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications.first?.displayName, "QQ")
        XCTAssertEqual(applications.first?.processIdentifier, 203)
    }

    func testGroupAssignmentPersistsByLogicalIdentity() {
        let suiteName = "MenuBarShelfTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = item(id: 10, title: "Sync")

        let firstStore = makeStore(defaults: defaults, windows: [])
        firstStore.setGroup(.alwaysHidden, for: original)

        let recreated = item(id: 999, title: "Sync")
        let secondStore = makeStore(defaults: defaults, windows: [])
        XCTAssertEqual(secondStore.group(for: recreated), .alwaysHidden)
    }

    func testFilteringShowsShelfItemsAndSearchIncludesAlwaysHidden() {
        let pinnedWindow = window(id: 1, x: 100, title: "Pinned")
        let hiddenWindow = window(id: 2, x: 150, title: "Cloud Sync")
        let alwaysWindow = window(id: 3, x: 200, title: "Quiet Backup")
        let defaults = UserDefaults(suiteName: "MenuBarShelfTests.\(UUID().uuidString)")!
        let store = makeStore(defaults: defaults, windows: [pinnedWindow, hiddenWindow, alwaysWindow])
        store.refresh()

        let pinned = store.items.first { $0.title == "Pinned" }!
        let hidden = store.items.first { $0.title == "Cloud Sync" }!
        let always = store.items.first { $0.title == "Quiet Backup" }!
        store.setGroup(.pinned, for: pinned)
        store.setGroup(.hidden, for: hidden)
        store.setGroup(.alwaysHidden, for: always)

        XCTAssertEqual(store.filteredItems().map(\.title), ["Cloud Sync"])
        XCTAssertEqual(store.filteredItems(query: "backup").map(\.title), ["Quiet Backup"])
    }

    func testStoreSearchesAndActivatesBackgroundOnlyApplications() throws {
        let defaults = UserDefaults(suiteName: "MenuBarShelfTests.\(UUID().uuidString)")!
        let store = makeStore(
            defaults: defaults,
            windows: [],
            runningApplications: [
                runningApp(pid: 301, bundleID: "com.tencent.xinWeChat", name: "WeChat", path: "/Applications/CoolRunFixtures/WeChat.app"),
                runningApp(pid: 302, bundleID: "com.tencent.qq", name: "QQ", path: "/Applications/CoolRunFixtures/QQ.app"),
            ]
        )
        store.refresh()

        XCTAssertEqual(store.filteredBackgroundApplications(query: "wechat").map(\.displayName), ["WeChat"])
        XCTAssertEqual(store.filteredBackgroundApplications(query: "com.tencent").count, 0)

        var activatedApplication: MenuBarBackgroundApplicationSnapshot?
        store.onActivateBackgroundApplication = { activatedApplication = $0 }
        let qq = try XCTUnwrap(store.backgroundApplications.first { $0.displayName == "QQ" })
        store.activate(qq)
        XCTAssertEqual(activatedApplication, qq)
    }

    func testRevealGeometryFindsFirstSafeGapAndRejectsFullBar() {
        let menuBar = CGRect(x: 0, y: 0, width: 300, height: 24)
        let gap = MenuBarShelfGeometry.revealPoint(
            itemWidth: 30,
            menuBarFrame: menuBar,
            occupiedFrames: [CGRect(x: 40, y: 0, width: 40, height: 24)],
            minimumX: 90
        )
        XCTAssertEqual(gap, CGPoint(x: 90, y: 12))

        let noGap = MenuBarShelfGeometry.revealPoint(
            itemWidth: 40,
            menuBarFrame: CGRect(x: 0, y: 0, width: 100, height: 24),
            occupiedFrames: [CGRect(x: 0, y: 0, width: 100, height: 24)],
            minimumX: 0
        )
        XCTAssertNil(noGap)
    }

    func testPermissionRefreshesWhenApplicationBecomesActive() {
        var accessibilityGranted = false
        var screenCaptureGranted = false
        let notificationCenter = NotificationCenter()
        let permissions = MenuBarShelfPermissions(
            accessibilityProbe: { accessibilityGranted },
            screenCaptureProbe: { screenCaptureGranted },
            applicationIdentity: MenuBarShelfApplicationIdentity(
                bundlePath: "/Applications/CoolRun.app",
                usesAdHocSignature: true
            ),
            notificationCenter: notificationCenter
        )
        var observedAccessibilityChanges = [Bool]()
        permissions.onAccessibilityChange = { observedAccessibilityChanges.append($0) }

        XCTAssertFalse(permissions.hasAccessibility)
        XCTAssertFalse(permissions.hasScreenCapture)

        accessibilityGranted = true
        screenCaptureGranted = true
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(permissions.hasAccessibility)
        XCTAssertTrue(permissions.hasScreenCapture)
        XCTAssertEqual(observedAccessibilityChanges, [true])
    }

    func testPermissionRefreshPublishesOnlyWhenStateChanges() {
        var accessibilityGranted = false
        var screenCaptureGranted = false
        let permissions = MenuBarShelfPermissions(
            accessibilityProbe: { accessibilityGranted },
            screenCaptureProbe: { screenCaptureGranted },
            applicationIdentity: MenuBarShelfApplicationIdentity(
                bundlePath: "/Applications/CoolRun.app",
                usesAdHocSignature: true
            ),
            notificationCenter: NotificationCenter()
        )
        var publicationCount = 0
        let observation = permissions.objectWillChange.sink { publicationCount += 1 }

        permissions.refresh()
        permissions.refresh()
        XCTAssertEqual(publicationCount, 0)

        screenCaptureGranted = true
        permissions.refresh()
        XCTAssertEqual(publicationCount, 1)

        permissions.refresh()
        XCTAssertEqual(publicationCount, 1)
        withExtendedLifetime(observation) {}
    }

    func testVisiblePermissionMonitorsAreIndependent() async {
        var accessibilityGranted = false
        let permissions = MenuBarShelfPermissions(
            accessibilityProbe: { accessibilityGranted },
            screenCaptureProbe: { false },
            applicationIdentity: MenuBarShelfApplicationIdentity(
                bundlePath: "/Applications/CoolRun.app",
                usesAdHocSignature: true
            ),
            notificationCenter: NotificationCenter(),
            monitoringInterval: .milliseconds(10)
        )

        let firstSurface = Task { await permissions.monitorWhileVisible() }
        let secondSurface = Task { await permissions.monitorWhileVisible() }
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(permissions.activeVisibleMonitorCount, 2)
        XCTAssertTrue(permissions.isActivelyPolling)

        firstSurface.cancel()
        await firstSurface.value
        XCTAssertEqual(permissions.activeVisibleMonitorCount, 1)
        XCTAssertTrue(permissions.isActivelyPolling)

        accessibilityGranted = true
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(
            permissions.hasAccessibility,
            "Closing one surface must not stop another visible surface from observing the grant"
        )
        secondSurface.cancel()
        await secondSurface.value
        XCTAssertEqual(permissions.activeVisibleMonitorCount, 0)
        XCTAssertFalse(permissions.isActivelyPolling)
    }

    func testAdHocApplicationIdentityRetainsCurrentBundlePathForGuidance() {
        let identity = MenuBarShelfApplicationIdentity(
            bundlePath: "/Applications/CoolRun.app",
            usesAdHocSignature: true
        )

        XCTAssertTrue(identity.usesAdHocSignature)
        XCTAssertEqual(identity.bundlePath, "/Applications/CoolRun.app")
    }

    private func makeStore(
        defaults: UserDefaults,
        windows: [MenuBarWindowSnapshot],
        runningApplications: [MenuBarRunningApplicationSnapshot] = []
    ) -> MenuBarShelfStore {
        MenuBarShelfStore(defaults: defaults, discovery: {
            MenuBarWindowBridge.WindowListResult(
                windows: windows,
                usedPrivateDiscovery: true,
                limitationReason: nil
            )
        }, runningApplicationDiscovery: { runningApplications })
    }

    private func runningApp(
        pid: pid_t,
        bundleID: String?,
        name: String?,
        path: String?,
        kind: MenuBarRunningApplicationKind = .regular,
        isTerminated: Bool = false
    ) -> MenuBarRunningApplicationSnapshot {
        MenuBarRunningApplicationSnapshot(
            processIdentifier: pid,
            bundleIdentifier: bundleID,
            localizedName: name,
            bundleURL: path.map { URL(fileURLWithPath: $0) },
            kind: kind,
            isTerminated: isTerminated
        )
    }

    private func item(id: CGWindowID, title: String) -> MenuBarItemSnapshot {
        MenuBarItemSnapshot(
            identity: MenuBarItemIdentity(ownerKey: "com.example.sync", itemKey: title),
            windowID: id,
            ownerPID: 42,
            ownerBundleIdentifier: "com.example.sync",
            ownerName: "Example",
            title: title,
            displayName: title,
            frame: CGRect(x: 100, y: 0, width: 24, height: 24),
            isOnScreen: true,
            canMove: true
        )
    }

    private func window(
        id: CGWindowID,
        x: CGFloat,
        title: String,
        ownerName: String = "Example",
        bundleIdentifier: String? = "com.example.sync",
        ownerPID: pid_t = 42
    ) -> MenuBarWindowSnapshot {
        MenuBarWindowSnapshot(
            windowID: id,
            ownerPID: ownerPID,
            ownerBundleIdentifier: bundleIdentifier,
            ownerName: ownerName,
            title: title,
            frame: CGRect(x: x, y: 0, width: 24, height: 24),
            isOnScreen: true,
            layer: Int(CGWindowLevelForKey(.statusWindow))
        )
    }
}
#endif
