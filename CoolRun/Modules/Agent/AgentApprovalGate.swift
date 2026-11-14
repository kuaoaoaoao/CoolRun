import AppKit
import SwiftUI

// MARK: - 确认界面的可见性

/// 记录「AI 对话界面此刻是否在屏幕上」。
///
/// 需要它的原因：工具确认是弹在对话界面里的。面板关着的时候如果还有人在
/// 调 L2 工具（DSH 引擎走 MCP 回连就是这种情况），用户根本看不到确认条，
/// 只能干等 90 秒超时——模型那边还会先撞上 60 秒的工具超时，最后得到一句
/// 「工具超时」，完全不知道为什么。所以看不见确认界面时应当立刻拒绝，
/// 并把原因原样告诉模型。
@MainActor
final class AgentApprovalGate {
    static let shared = AgentApprovalGate()

    private(set) var isChatVisible = false

    private init() {}

    func setChatVisible(_ visible: Bool) {
        guard isChatVisible != visible else { return }
        isChatVisible = visible
    }
}

// MARK: - 视图是否在窗口里

/// 用 `viewDidMoveToWindow` 判断视图真的上屏了。
///
/// 不用 SwiftUI 的 `onAppear` / `onDisappear`：NSPopover 关闭时内容视图
/// 未必被销毁，`onDisappear` 不一定触发，拿它当可见性判断会留下「面板关了
/// 但以为还开着」的假阳性——那正是我们要避免的。
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityProbeView {
        let view = VisibilityProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: VisibilityProbeView, context: Context) {
        nsView.onChange = onChange
    }

    final class VisibilityProbeView: NSView {
        var onChange: ((Bool) -> Void)?
        private var lastVisible: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let visible = window != nil
            guard visible != lastVisible else { return }
            lastVisible = visible
            let callback = onChange
            Task { @MainActor in
                callback?(visible)
            }
        }
    }
}
