import AppKit
import QuartzCore
import SwiftUI

// MARK: - 桌宠窗口

/// 桌面上的鲸鱼娘：一个无边框、不抢焦点、跟着所有 Space 走的浮动面板。
///
/// 用 `NSPanel` 而不是窗口，是因为它不该出现在程序坞和窗口列表里；
/// `.nonactivatingPanel` 保证点它不会把当前 app 的焦点抢走。
///
/// 拖拽是「跟手 + 松手算速度」，之后再交给 `PetPhysics` 跑抛掷、重力、撞墙。
@MainActor
final class PetController {
    static let shared = PetController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<PetRootView>?

    private var dragAnchor: NSPoint?
    private var samples: [(time: TimeInterval, point: NSPoint)] = []
    private var velocity = CGVector.zero
    private var physicsTask: Task<Void, Never>?
    private var glideTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard

    /// 立绘缩放，0.7~1.5。
    private(set) var scale: CGFloat = 1
    /// 是否播放待机动效。关掉能省一点电（实测约 2% CPU），代价是画面定格。
    private(set) var animates = true
    /// 用视频动作（插件那套逐帧动画）还是立绘合成。视频更像真动画，但也更费电。
    private(set) var videoEnabled = true
    private(set) var isVisible = false

    private var size: NSSize {
        NSSize(
            width: WhalePetView.baseSize.width * scale,
            height: WhalePetView.baseSize.height * scale
        )
    }

    private init() {}

    // MARK: 显示

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            isVisible = true
            PetModel.shared.start()
            return
        }

        let frame = NSRect(origin: originForShow(), size: size)
        let panel = NSPanel(
            contentRect: frame,
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

        let host = NSHostingView(rootView: PetRootView(scale: scale, animates: animates))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = host
        isVisible = true
        PetModel.shared.onWander = { [weak self] dx in
            self?.glide(dx: dx)
        }
        PetModel.shared.animating = animates
        PetModel.shared.videoEnabled = videoEnabled
        PetModel.shared.videoPaused = false
        PetModel.shared.start()

        #if DEBUG
        // 调试用：`COOLRUN_PET_GLIDE_DEMO=1` 启动后自己走一趟，
        // 省得等那个 9~22 秒的随机空闲动作才看得到效果。
        if ProcessInfo.processInfo.environment["COOLRUN_PET_GLIDE_DEMO"] != nil {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.glide(dx: 220)
            }
        }

        // 调试用：`COOLRUN_PET_CLIP_DEMO=1` 挨个放一遍片段，
        // 方便截图核对每个动作到底有没有真的播出来。
        if ProcessInfo.processInfo.environment["COOLRUN_PET_CLIP_DEMO"] != nil {
            Task { @MainActor in
                let script: [(PetClip, Double)] = [
                    (.idle, 3), (.eatRice, 3), (.clickHappy, 3),
                    (.workBusy, 3), (.sleepStart, 3), (.sleepLoop, 3), (.wake, 3),
                ]
                try? await Task.sleep(for: .seconds(1))
                for (clip, seconds) in script {
                    PetModel.shared.debugPlayClip(clip, seconds: seconds)
                    try? await Task.sleep(for: .seconds(seconds))
                }
            }
        }
        #endif
    }

    func hide() {
        PetModel.shared.videoPaused = true
        stopGlide()
        stopPhysics()
        panel?.orderOut(nil)
        isVisible = false
        PetModel.shared.stop()
    }

    func close() {
        stopGlide()
        stopPhysics()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        isVisible = false
        PetModel.shared.stop()
    }

    // MARK: 尺寸

    func setAnimates(_ on: Bool) {
        guard on != animates else { return }
        animates = on
        defaults.set(on, forKey: "pet.animate")
        PetModel.shared.animating = on
        hostingView?.rootView = PetRootView(scale: scale, animates: on)
    }

    func setVideoEnabled(_ on: Bool) {
        guard on != videoEnabled else { return }
        videoEnabled = on
        defaults.set(on, forKey: "pet.video")
        PetModel.shared.videoEnabled = on
        hostingView?.rootView = PetRootView(scale: scale, animates: animates)
    }

    func setScale(_ newScale: CGFloat) {
        let clamped = min(1.5, max(0.7, (newScale * 100).rounded() / 100))
        guard clamped != scale else { return }
        scale = clamped
        defaults.set(Double(clamped), forKey: "pet.scale")

        guard let panel else { return }
        let origin = panel.frame.origin
        let newSize = size
        panel.setFrame(NSRect(origin: origin, size: newSize), display: true)
        hostingView?.frame = NSRect(origin: .zero, size: newSize)
        hostingView?.rootView = PetRootView(scale: clamped, animates: animates)
        saveOrigin(PetPhysics.clamp(origin, size: newSize, bounds: activeBounds(for: panel.frame)))
    }

    // MARK: 拖动

    func beginDrag() {
        guard let panel else { return }
        stopGlide()
        stopPhysics()
        dragAnchor = panel.frame.origin
        samples = [(CACurrentMediaTime(), panel.frame.origin)]
        velocity = .zero
        PetModel.shared.setDragging(true)
        NSCursor.closedHand.set()
    }

    func drag(translation: CGSize) {
        guard let panel, let anchor = dragAnchor else { return }
        // SwiftUI 的 y 轴向下，窗口的向上，所以要取负。
        let origin = NSPoint(x: anchor.x + translation.width, y: anchor.y - translation.height)
        panel.setFrameOrigin(origin)

        let now = CACurrentMediaTime()
        samples.append((now, origin))
        // 只留最近 140ms 的样本，松手时的速度才反映「最后一甩」。
        samples.removeAll { now - $0.time > 0.14 }
        if samples.count > 32 {
            samples.removeFirst(samples.count - 32)
        }
    }

    func endDrag() {
        guard let panel else { return }
        PetModel.shared.setDragging(false)
        NSCursor.openHand.set()
        dragAnchor = nil

        let thrown = throwVelocity()
        samples = []

        if thrown.speed > 60 {
            velocity = thrown
            startPhysics()
        } else {
            let origin = PetPhysics.clamp(panel.frame.origin, size: size, bounds: activeBounds(for: panel.frame))
            panel.setFrameOrigin(origin)
            saveOrigin(origin)
        }
    }

    /// 用最后一段位移估速度（px/s）。样本太少或时间跨度太小时按「没甩」处理。
    private func throwVelocity() -> CGVector {
        guard let last = samples.last, let first = samples.first, samples.count >= 2 else {
            return .zero
        }
        let dt = last.time - first.time
        guard dt > 0.008 else { return .zero }

        var dx = (last.point.x - first.point.x) / dt
        var dy = (last.point.y - first.point.y) / dt
        let speed = (dx * dx + dy * dy).squareRoot()
        let cap: CGFloat = 2600
        if speed > cap {
            let k = cap / speed
            dx *= k
            dy *= k
        }
        return CGVector(dx: dx, dy: dy)
    }

    // MARK: 溜达

    /// 把窗口平移到旁边一段距离。
    ///
    /// 这是「她自己走动」的唯一实现方式：窗口是固定的画布，
    /// 想让一只平图宠物真的换位置，只能搬窗口。拖动、飞行、隐藏都会打断它。
    func glide(dx: CGFloat, duration: TimeInterval = 1.15) {
        guard let panel, dragAnchor == nil, physicsTask == nil else { return }

        let start = panel.frame.origin
        let targetX = Self.glideTargetX(
            start: start.x,
            dx: dx,
            size: size,
            bounds: activeBounds(for: panel.frame)
        )
        guard abs(targetX - start.x) > 6 else { return }

        stopGlide()
        PetModel.shared.setGliding(true)

        glideTask = Task { @MainActor [weak self] in
            let began = CACurrentMediaTime()
            while !Task.isCancelled {
                let progress = min(1, (CACurrentMediaTime() - began) / duration)
                // 起止都慢一点，看着像游过去而不是被推过去。
                let eased = progress < 0.5
                    ? 2 * progress * progress
                    : 1 - 2 * (1 - progress) * (1 - progress)
                panel.setFrameOrigin(
                    NSPoint(x: start.x + (targetX - start.x) * CGFloat(eased), y: start.y)
                )
                if progress >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let self, !Task.isCancelled else { return }
            self.saveOrigin(panel.frame.origin)
            PetModel.shared.setGliding(false)
            self.glideTask = nil
        }
    }

    /// 溜达的落点：夹在屏幕可活动区域内，别撞出边界。
    nonisolated static func glideTargetX(start: CGFloat, dx: CGFloat, size: CGSize, bounds: CGRect) -> CGFloat {
        let maxX = max(bounds.minX, bounds.maxX - size.width)
        return min(max(start + dx, bounds.minX), maxX)
    }

    private func stopGlide() {
        guard glideTask != nil else { return }
        glideTask?.cancel()
        glideTask = nil
        PetModel.shared.setGliding(false)
    }

    // MARK: 物理

    private func startPhysics() {
        physicsTask?.cancel()
        PetModel.shared.setAirborne(true, horizontalVelocity: velocity.dx)

        physicsTask = Task { @MainActor [weak self] in
            var last = CACurrentMediaTime()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let self, let panel = self.panel else { return }

                let now = CACurrentMediaTime()
                let dt = now - last
                last = now

                var body = PetBody(origin: panel.frame.origin, velocity: self.velocity)
                let bounds = self.activeBounds(for: panel.frame)
                let result = PetPhysics.step(&body, size: self.size, bounds: bounds, dt: dt)
                panel.setFrameOrigin(body.origin)
                self.velocity = body.velocity

                if result.impact > 320 {
                    PetModel.shared.land(strength: min(1, result.impact / 900))
                    if result.impact > 700 {
                        self.haptic()
                    }
                }
                PetModel.shared.setAirborne(true, horizontalVelocity: body.velocity.dx)

                if !result.isMoving {
                    self.saveOrigin(body.origin)
                    self.velocity = .zero
                    PetModel.shared.setAirborne(false)
                    return
                }
            }
        }
    }

    private func stopPhysics() {
        physicsTask?.cancel()
        physicsTask = nil
        velocity = .zero
        PetModel.shared.setAirborne(false)
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// 宠物所在的那块屏幕的可活动区域。跨屏飞行时按当前所在的屏算。
    private func activeBounds(for frame: NSRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    // MARK: 位置

    private func originForShow() -> NSPoint {
        scale = CGFloat(defaults.object(forKey: "pet.scale") as? Double ?? 1)
        animates = defaults.object(forKey: "pet.animate") as? Bool ?? true
        videoEnabled = defaults.object(forKey: "pet.video") as? Bool ?? true
        if let saved = defaults.string(forKey: "pet.origin") {
            let point = NSPointFromString(saved)
            if isOnScreen(point) {
                return PetPhysics.clamp(point, size: size, bounds: activeBounds(for: NSRect(origin: point, size: size)))
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

    private func saveOrigin(_ point: NSPoint) {
        defaults.set(NSStringFromPoint(point), forKey: "pet.origin")
    }

    private func isOnScreen(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            screen.visibleFrame.insetBy(dx: -40, dy: -40).contains(point)
        }
    }

    // MARK: 动作

    func openAgent() {
        PetModel.shared.touch()
        AppNavigationRouter.shared.open(.aiAssistant)
    }

    func speak() {
        PetModel.shared.poke()
    }

    func nap() {
        PetModel.shared.nap()
    }
}

// MARK: - 根视图

/// 负责把 SwiftUI 的手势翻译成窗口移动、抛掷和互动。
///
/// 点一下是「戳她」，点两下是「开面板」，按住拖动是「搬家」——
/// 三者共用同一个手势区，靠 `DragGesture` 的最小距离把点击和拖动分开。
struct PetRootView: View {
    var scale: CGFloat = 1
    var animates: Bool = true

    private var model: PetModel { PetModel.shared }

    var body: some View {
        WhalePetView(animated: animates)
            .scaleEffect(scale, anchor: .bottom)
            .frame(
                width: WhalePetView.baseSize.width * scale,
                height: WhalePetView.baseSize.height * scale,
                alignment: .bottom
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            PetController.shared.beginDrag()
                        }
                        PetController.shared.drag(translation: value.translation)
                    }
                    .onEnded { _ in
                        dragging = false
                        PetController.shared.endDrag()
                    }
            )
            .onTapGesture {
                handleTap()
            }
            .contextMenu {
                Button("打开 Agent") { PetController.shared.openAgent() }
                Button("跟她说句话") { PetController.shared.speak() }
                Button(model.isSleeping ? "叫醒她" : "让她睡会儿") {
                    if model.isSleeping {
                        PetController.shared.speak()
                    } else {
                        PetController.shared.nap()
                    }
                }
                Divider()
                Picker("大小", selection: Binding(
                    get: { PetController.shared.scale },
                    set: { PetController.shared.setScale($0) }
                )) {
                    Text("小").tag(CGFloat(0.8))
                    Text("中").tag(CGFloat(1.0))
                    Text("大").tag(CGFloat(1.25))
                }
                Divider()
                Button("隐藏桌宠") { PetController.shared.hide() }
            }
            .help("点一下逗她，双击打开 Agent，按住可以拖来拖去，甩出去她会飞")
    }

    @State private var dragging = false
    @State private var tapCount = 0
    @State private var tapTask: Task<Void, Never>?

    /// 单击和双击要自己分：两个 `onTapGesture` 叠在一起时，单击会先吃掉事件，
    /// 双击永远等不到第二下。所以先等 260ms，看到第二下就当双击。
    private func handleTap() {
        tapCount += 1
        tapTask?.cancel()
        let count = tapCount
        tapTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            tapCount = 0
            if count >= 2 {
                PetController.shared.openAgent()
            } else {
                PetController.shared.speak()
            }
        }
    }
}
