#if os(macOS)
import AppKit
import Carbon
import Observation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.coolrun.search", category: "quickSearch")

// MARK: - 状态

/// 搜索面板的状态。视图只负责画，选中/执行都在这里。
@MainActor
@Observable
final class QuickSearchModel {
    var query = "" {
        didSet { recompute() }
    }

    private(set) var results: [QuickSearchItem] = []
    private(set) var selection = 0

    @ObservationIgnored private var allItems: [QuickSearchItem] = []

    /// 面板打开时重建索引：数据变了（新笔记、新剪贴）下次打开就能搜到。
    func reload() {
        let lang = AppSettings.shared.language
        allItems = QuickSearchIndex.build(lang: lang)
        query = ""
        recompute()
    }

    private func recompute() {
        results = QuickSearchIndex.rank(allItems, query: query)
        selection = 0
    }

    func move(by delta: Int) {
        guard !results.isEmpty else { return }
        let next = selection + delta
        selection = min(results.count - 1, max(0, next))
    }

    func select(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selection = index
    }

    var selectedItem: QuickSearchItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    /// 执行结果。返回后调用方负责把面板关掉。
    func perform(_ item: QuickSearchItem) {
        switch item.action {
        case .openModule(let mode):
            AppNavigationRouter.shared.open(mode)

        case .openNote(let id):
            NotesStore.shared.pendingOpenNoteID = id
            AppNavigationRouter.shared.open(.notes)

        case .copyText(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

        case .runRecipe(let id):
            guard let recipe = AgentRecipeStore.shared.recipe(id: id) else { return }
            AppNavigationRouter.shared.open(.aiAssistant)
            if recipe.needsInput {
                // 需要用户补一句话的场景卡：只把提示词填进输入框，别替他按回车。
                AgentCoordinator.shared.draft = recipe.prompt + " "
            } else {
                AgentCoordinator.shared.send(recipe.prompt)
            }

        case .runTool(let name):
            AppNavigationRouter.shared.open(.aiAssistant)
            AgentCoordinator.shared.runToolDirectly(name: name, arguments: .object([:]))
        }
    }
}

// MARK: - 窗口

/// 无边框但要能输入，所以自己声明 `canBecomeKey`。
final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 控制器

@MainActor
final class QuickSearchController {
    static let shared = QuickSearchController()

    private(set) var isVisible = false
    /// 面板是不是当前接收键盘的窗口（调试和自动化检查用）。
    var isKey: Bool { panel?.isKeyWindow ?? false }

    @ObservationIgnored private var panel: QuickSearchPanel?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerInstalled = false

    let model = QuickSearchModel()

    private enum EventID {
        static let signature: FourCharCode = {
            let scalars = Array("CQSR".unicodeScalars)
            return FourCharCode(scalars[0].value) << 24
                | FourCharCode(scalars[1].value) << 16
                | FourCharCode(scalars[2].value) << 8
                | FourCharCode(scalars[3].value)
        }()
        static let hotKey: UInt32 = 1
    }

    private static let panelSize = NSSize(width: 480, height: 420)

    private init() {}

    // MARK: 热键

    func start() {
        registerHotKey()
    }

    private func registerHotKey() {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(cmdKey | optionKey),
            EventHotKeyID(signature: EventID.signature, id: EventID.hotKey),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            logger.info("quick search hotkey unavailable: \(status, privacy: .public)")
            return
        }
        hotKeyRef = ref
        installHandlerIfNeeded()
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
                return noErr
            }
            Task { @MainActor in
                QuickSearchController.shared.toggle()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    // MARK: 显示

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.reload()

        let panel = panel ?? makePanel()
        self.panel = panel

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(
                x: frame.midX - Self.panelSize.width / 2,
                y: frame.maxY - Self.panelSize.height - 120
            )
            panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: false)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        installKeyMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        removeKeyMonitor()
    }

    private func makePanel() -> QuickSearchPanel {
        let panel = QuickSearchPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: QuickSearchView(model: model, controller: self))

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                QuickSearchController.shared.hide()
            }
        }

        return panel
    }

    // MARK: 键盘

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            var swallow = false
            MainActor.assumeIsolated {
                swallow = QuickSearchController.shared.handle(event)
            }
            return swallow ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// 上下键选、回车执行、esc 关。文本框自己会用左右键，别抢。
    private func handle(_ event: NSEvent) -> Bool {
        guard let panel, panel.isKeyWindow else { return false }
        switch Int(event.keyCode) {
        case 53:  // esc
            hide()
            return true
        case 125:  // ↓
            model.move(by: 1)
            return true
        case 126:  // ↑
            model.move(by: -1)
            return true
        case 36, 76:  // return / enter
            if let item = model.selectedItem {
                hide()
                model.perform(item)
            }
            return true
        default:
            return false
        }
    }
}

// MARK: - 视图

struct QuickSearchView: View {
    @Bindable var model: QuickSearchModel
    let controller: QuickSearchController

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var appSettings = AppSettings.shared

    private var lang: AppLanguage { appSettings.language }

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider().opacity(0.6)

            if model.results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                                row(item, isSelected: index == model.selection)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        controller.hide()
                                        model.perform(item)
                                    }
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .onChange(of: model.selection) { _, _ in
                        if let item = model.selectedItem {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        }
                    }
                }
            }

            footer
        }
        .frame(width: 480, height: 420)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onAppear { fieldFocused = true }
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.55))
        }
    }

    private var searchRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(
                LocalizedString.l(
                    lang,
                    en: "Search notes, clipboard, actions…",
                    zh: "搜笔记、剪贴板、动作…",
                    ja: "メモ・クリップボード・アクションを検索…",
                    ko: "메모, 클립보드, 액션 검색…"
                ),
                text: $model.query
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($fieldFocused)
            .onSubmit {
                if let item = model.selectedItem {
                    controller.hide()
                    model.perform(item)
                }
            }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    private func row(_ item: QuickSearchItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !item.hint.isEmpty {
                Text(item.hint)
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.75))
            }

            Text(item.category.title(lang))
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? Color.white.opacity(0.65) : Color.secondary.opacity(0.7))
                .frame(width: 34, alignment: .trailing)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(LocalizedString.l(
                lang,
                en: "Nothing matches",
                zh: "没找到相关的东西",
                ja: "見つかりません",
                ko: "결과 없음"
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            keyHint("↑↓", LocalizedString.l(lang, en: "choose", zh: "选择", ja: "選択", ko: "선택"))
            keyHint("⏎", LocalizedString.l(lang, en: "run", zh: "执行", ja: "実行", ko: "실행"))
            keyHint("esc", LocalizedString.l(lang, en: "close", zh: "关闭", ja: "閉じる", ko: "닫기"))
            Spacer()
            Text("\(model.results.count)")
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
