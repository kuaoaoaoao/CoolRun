import AppKit
import SwiftUI

// MARK: - 桌宠窗口

/// 桌面上的鲸鱼娘：一个无边框、不抢焦点、跟着所有 Space 走的浮动面板。
///
/// 用 `NSPanel` 而不是窗口，是因为它不该出现在程序坞和窗口列表里；
/// `.nonactivatingPanel` 保证点它不会把当前 app 的焦点抢走。
@MainActor
final class PetController {
    static let shared = PetController()

    private var panel: NSPanel?
    private var dragStart: NSPoint?
    private var hostingView: NSHostingView<PetRootView>?

    private let size = NSSize(width: 168, height: 190)
    private let defaults = UserDefaults.standard

    private(set) var isVisible = false

    private init() {}

    // MARK: 显示

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            isVisible = true
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: originForShow(), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false

        let host = NSHostingView(rootView: PetRootView())
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = host
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        isVisible = false
    }

    // MARK: 拖动

    func beginDrag() {
        dragStart = panel?.frame.origin
    }

    func drag(translation: CGSize) {
        guard let panel, let start = dragStart else { return }
        // SwiftUI 的 y 轴向下，窗口的向上，所以要取负。
        panel.setFrameOrigin(NSPoint(x: start.x + translation.width, y: start.y - translation.height))
    }

    func endDrag() {
        guard let panel else { return }
        dragStart = nil
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "pet.origin")
    }

    // MARK: 位置

    private func originForShow() -> NSPoint {
        if let saved = defaults.string(forKey: "pet.origin") {
            let point = NSPointFromString(saved)
            if isOnScreen(point) {
                return point
            }
        }
        // 默认右下角，避开程序坞。
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.maxX - size.width - 28,
            y: visible.minY + 28
        )
    }

    private func isOnScreen(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            screen.visibleFrame.insetBy(dx: -40, dy: -40).contains(point)
        }
    }

    // MARK: 动作

    func openAgent() {
        AppNavigationRouter.shared.open(.aiAssistant)
    }
}

// MARK: - 根视图

/// 负责把 SwiftUI 的手势翻译成窗口移动。
struct PetRootView: View {
    @State private var isDragging = false

    var body: some View {
        WhalePetView(isDragging: isDragging)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        PetController.shared.beginDrag()
                    }
                    PetController.shared.drag(translation: value.translation)
                }
                .onEnded { _ in
                    isDragging = false
                    PetController.shared.endDrag()
                }
        )
        .onTapGesture(count: 2) {
            PetController.shared.openAgent()
        }
        .contextMenu {
            Button("打开 Agent") {
                PetController.shared.openAgent()
            }
            Button("隐藏桌宠") {
                PetController.shared.hide()
            }
        }
        .help("双击打开 Agent，拖动换个位置")
    }
}
