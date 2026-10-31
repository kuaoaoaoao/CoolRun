#if os(macOS)
import AppKit
import Combine
import Foundation

@MainActor
final class MenuBarShelfStore: NSObject, ObservableObject {
    static let shared = MenuBarShelfStore()

    @Published private(set) var items = [MenuBarItemSnapshot]()
    @Published private(set) var backgroundApplications = [MenuBarBackgroundApplicationSnapshot]()
    @Published private(set) var discoveryMode: MenuBarDiscoveryMode = .full
    @Published private(set) var operationState: MenuBarShelfOperationState = .idle
    @Published var searchText = ""
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            onEnabledChange?(isEnabled)
            if !isEnabled {
                operationState = .idle
            }
        }
    }
    @Published private(set) var isShelfPresented = false

    private let defaults: UserDefaults
    private let discovery: () -> MenuBarWindowBridge.WindowListResult
    private let runningApplicationDiscovery: () -> [MenuBarRunningApplicationSnapshot]
    private var groupAssignments: [String: MenuBarShelfGroup]
    private var refreshTimer: AnyCancellable?
    private var hasStarted = false
    var onEnabledChange: ((Bool) -> Void)?
    var onGroupChange: ((MenuBarItemSnapshot, MenuBarShelfGroup, MenuBarShelfGroup) -> Void)?
    var onPresentationChange: ((Bool) -> Void)?
    var onActivate: ((MenuBarItemSnapshot, Bool) -> Void)?
    var onActivateBackgroundApplication: ((MenuBarBackgroundApplicationSnapshot) -> Void)?
    var onItemsRefresh: (([MenuBarItemSnapshot]) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        bridge: MenuBarWindowBridge? = nil,
        discovery: (() -> MenuBarWindowBridge.WindowListResult)? = nil,
        runningApplicationDiscovery: (() -> [MenuBarRunningApplicationSnapshot])? = nil
    ) {
        let bridge = bridge ?? MenuBarWindowBridge()
        self.defaults = defaults
        self.discovery = discovery ?? { bridge.statusWindows() }
        self.runningApplicationDiscovery = runningApplicationDiscovery ?? {
            NSWorkspace.shared.runningApplications.map(MenuBarRunningApplicationSnapshot.init)
        }
        self.isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        if let data = defaults.data(forKey: Keys.groups),
           let decoded = try? JSONDecoder().decode([String: MenuBarShelfGroup].self, from: data) {
            self.groupAssignments = decoded
        } else {
            self.groupAssignments = [:]
        }
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(handleLifecycleRefresh), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(handleLifecycleRefresh), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(handleLifecycleRefresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLifecycleRefresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
    }

    func stop() {
        refreshTimer?.cancel()
        refreshTimer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        hasStarted = false
    }

    func setShelfPresented(_ presented: Bool) {
        isShelfPresented = presented
        onPresentationChange?(presented)
        refreshTimer?.cancel()
        refreshTimer = nil
        if presented {
            refresh()
            refreshTimer = Timer.publish(every: 3, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
        }
    }

    func refresh() {
        operationState = .refreshing
        let result = discovery()
        items = MenuBarItemReconciler.items(from: result.windows)
        backgroundApplications = MenuBarBackgroundApplicationCatalog.applications(
            from: runningApplicationDiscovery(),
            excluding: items
        )
        discoveryMode = result.usedPrivateDiscovery
            ? .full
            : .limited(reason: result.limitationReason ?? "Limited discovery")
        operationState = .idle
        onItemsRefresh?(items)
    }

    func group(for item: MenuBarItemSnapshot) -> MenuBarShelfGroup {
        groupAssignments[item.identity.id] ?? .pinned
    }

    func setGroup(_ group: MenuBarShelfGroup, for item: MenuBarItemSnapshot) {
        let previousGroup = self.group(for: item)
        guard previousGroup != group else { return }
        groupAssignments[item.identity.id] = group
        persistGroups()
        objectWillChange.send()
        onGroupChange?(item, group, previousGroup)
    }

    func restoreGroup(_ group: MenuBarShelfGroup, for item: MenuBarItemSnapshot) {
        groupAssignments[item.identity.id] = group
        persistGroups()
        objectWillChange.send()
    }

    func filteredItems(query: String? = nil, includeAlwaysHidden: Bool = false) -> [MenuBarItemSnapshot] {
        let term = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let group = group(for: item)
            let groupMatches = includeAlwaysHidden || !term.isEmpty || group != .alwaysHidden
            guard groupMatches else { return false }
            guard !term.isEmpty else { return group != .pinned }
            return item.displayName.localizedCaseInsensitiveContains(term) ||
                item.ownerName.localizedCaseInsensitiveContains(term) ||
                item.title.localizedCaseInsensitiveContains(term) ||
                (item.ownerBundleIdentifier?.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    func filteredBackgroundApplications(query: String? = nil) -> [MenuBarBackgroundApplicationSnapshot] {
        let term = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return backgroundApplications }
        return backgroundApplications.filter {
            $0.displayName.localizedCaseInsensitiveContains(term)
        }
    }

    func items(in group: MenuBarShelfGroup) -> [MenuBarItemSnapshot] {
        items.filter { self.group(for: $0) == group }
    }

    func setOperationState(_ state: MenuBarShelfOperationState) {
        operationState = state
    }

    func activate(_ item: MenuBarItemSnapshot, rightClick: Bool = false) {
        onActivate?(item, rightClick)
    }

    func activate(_ application: MenuBarBackgroundApplicationSnapshot) {
        if let onActivateBackgroundApplication {
            onActivateBackgroundApplication(application)
            return
        }
        guard let runningApplication = NSRunningApplication(processIdentifier: application.processIdentifier),
              !runningApplication.isTerminated,
              runningApplication.activate(options: [.activateAllWindows]) else {
            operationState = .failed(message: LocalizedString.l(
                AppSettings.shared.language,
                en: "This application is no longer running. Refresh and try again.",
                zh: "这个软件已不在运行，请刷新后重试。",
                ja: "このアプリは実行されていません。更新して再試行してください。",
                ko: "이 앱은 더 이상 실행 중이 아닙니다. 새로 고친 후 다시 시도하세요."
            ))
            scheduleRefresh()
            return
        }
    }

    private func scheduleRefresh() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.refresh()
        }
    }

    @objc private func handleLifecycleRefresh() {
        scheduleRefresh()
    }

    private func persistGroups() {
        guard let data = try? JSONEncoder().encode(groupAssignments) else { return }
        defaults.set(data, forKey: Keys.groups)
    }

    private enum Keys {
        static let enabled = "menu_bar_shelf_enabled"
        static let groups = "menu_bar_shelf_groups_v1"
    }
}
#endif
