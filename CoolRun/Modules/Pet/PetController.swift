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
    /// 按下那一刻的鼠标位置（屏幕坐标）。拖拽全程用它算位移。
    private var dragStartMouse = NSPoint.zero
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
    /// 点她的时候有没有那声「啾」。
    private(set) var soundEnabled = true
    private(set) var isVisible = false

    private var size: NSSize {
        NSSize(
            width: WhalePetView.baseSize.width * scale,
            height: WhalePetView.baseSize.height * scale
        )
    }

    private init() {}

    /// 关掉整棵图层树的隐式动画。
    nonisolated static func disableImplicitAnimations(on layer: CALayer?) {
        guard let layer else { return }
        layer.sublayers?.forEach { disableImplicitAnimations(on: $0) }
        layer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "contents": NSNull(),
            "opacity": NSNull(),
            "transform": NSNull(),
            "sublayers": NSNull(),
        ]
    }

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
        // 窗口自己别做任何「出现/移动」动画，位置只由我们逐帧写。
        panel.animationBehavior = .none

        let host = NSHostingView(rootView: PetRootView(scale: scale, animates: animates))
        host.frame = NSRect(origin: .zero, size: size)
        host.wantsLayer = true
        // 内容图层的隐式动画同样会「慢半拍」：窗口已经移到新位置，画面还在
        // 从旧位置补间过来，就成了残影。这里彻底关掉。
        Self.disableImplicitAnimations(on: host.layer)
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

    func setSoundEnabled(_ on: Bool) {
        guard on != soundEnabled else { return }
        soundEnabled = on
        defaults.set(on, forKey: "pet.sound")
        if !on { clickSound?.stop() }
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

    /// 开始拖。`initialTranslation` 是 SwiftUI 手势在「识别成功那一刻」已经走过的位移
    /// （`minimumDistance` 那 4 点）。不把它补回去，窗口会永远比鼠标落后 4 点，
    /// 拖远一点就能看出来——那也是一种「飘」。
    func beginDrag(initialTranslation: CGSize = .zero) {
        guard let panel else { return }
        stopGlide()
        stopPhysics()
        dragAnchor = panel.frame.origin
        // SwiftUI 的 y 轴向下，屏幕坐标向上，所以取负。
        dragStartMouse = Self.dragStartMouse(
            current: NSEvent.mouseLocation,
            initialTranslation: initialTranslation
        )
        samples = [(CACurrentMediaTime(), panel.frame.origin)]
        velocity = .zero
        PetModel.shared.setDragging(true)
        NSCursor.closedHand.set()
    }

    /// 只保留最近 `window` 秒的位移样本（默认 140ms）。
    ///
    /// 松手时的速度只该反映「最后一甩」。拖到一半停住、或者拖完再停一会儿
    /// 才松手，旧样本必须剪掉，否则会莫名其妙被甩出去。
    nonisolated static func prunedSamples(
        _ samples: [(time: TimeInterval, point: NSPoint)],
        now: TimeInterval,
        window: TimeInterval = 0.14
    ) -> [(time: TimeInterval, point: NSPoint)] {
        samples.filter { now - $0.time <= window }
    }

    /// 拖动时窗口该在哪。
    ///
    /// 不看 SwiftUI 给的 `translation`：那是视图坐标系里的位移，视图被
    /// `scaleEffect` 缩过就跟着缩，窗口一移动坐标系又跟着跑——两笔误差叠起来
    /// 就是主人看到的「飘」。这里只认屏幕坐标的差值，位移永远等于鼠标位移。
    /// 手势起点的鼠标位置：当前鼠标位置减去手势已走过的位移。
    nonisolated static func dragStartMouse(current: NSPoint, initialTranslation: CGSize) -> NSPoint {
        NSPoint(x: current.x - initialTranslation.width, y: current.y + initialTranslation.height)
    }

    nonisolated static func draggedOrigin(anchor: NSPoint, start: NSPoint, current: NSPoint) -> NSPoint {
        NSPoint(x: anchor.x + (current.x - start.x), y: anchor.y + (current.y - start.y))
    }

    func drag(translation _: CGSize) {
        drag(toScreenPoint: NSEvent.mouseLocation)
    }

    /// 拖到鼠标所在的屏幕坐标（测试里可以喂假坐标）。
    func drag(toScreenPoint point: NSPoint) {
        guard dragAnchor != nil else { return }
        let origin = Self.draggedOrigin(anchor: dragAnchor!, start: dragStartMouse, current: point)
        movePanel(to: origin)

        let now = CACurrentMediaTime()
        samples.append((now, origin))
        // 只留最近 140ms 的样本，松手时的速度才反映「最后一甩」。
        samples = Self.prunedSamples(samples, now: now)
        if samples.count > 32 {
            samples.removeFirst(samples.count - 32)
        }
    }

    /// 移动窗口。必须关掉隐式动画——快速拖动时窗口框会「慢慢追上来」，
    /// 画面就拖在窗口后面，看起来像残影。
    private func movePanel(to origin: NSPoint) {
        guard let panel else { return }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        panel.setFrameOrigin(origin)
        NSAnimationContext.endGrouping()
    }

    func endDrag() {
        guard let panel else { return }
        PetModel.shared.setDragging(false)
        NSCursor.openHand.set()
        dragAnchor = nil

        // 拖到一半停住再松手时，`samples` 里还留着刚才那段高速位移——
        // 不剪掉的话她会被「甩」出去。松手这一刻只认最后 140ms。
        samples = Self.prunedSamples(samples, now: CACurrentMediaTime())
        let thrown = throwVelocity()
        samples = []

        if thrown.speed > 60 {
            velocity = thrown
            startPhysics()
        } else {
            let origin = PetPhysics.clamp(panel.frame.origin, size: size, bounds: activeBounds(for: panel.frame))
            movePanel(to: origin)
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
                self?.movePanel(
                    to: NSPoint(x: start.x + (targetX - start.x) * CGFloat(eased), y: start.y)
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
                self.movePanel(to: body.origin)
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
        soundEnabled = defaults.object(forKey: "pet.sound") as? Bool ?? true
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
        playClickSound()
        PetModel.shared.poke()
    }

    /// 点一下的音效。素材是插件里那只小黄鸭的「啾」，音量压得很低——
    /// 菜单栏软件在后台突然大声叫是很讨厌的事。
    func playClickSound() {
        guard soundEnabled, let sound = clickSound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    private lazy var clickSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "click", withExtension: "wav") else { return nil }
        let sound = NSSound(contentsOf: url, byReference: true)
        sound?.volume = 0.3
        return sound
    }()

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
    @ObservedObject private var settings = AppSettings.shared

    private var lang: AppLanguage { settings.language }

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
                            PetController.shared.beginDrag(initialTranslation: value.translation)
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
                Button(LocalizedString.l(lang, en: "Open Agent", zh: "打开 Agent", ja: "Agent を開く", ko: "Agent 열기")) {
                    PetController.shared.openAgent()
                }
                Button(LocalizedString.l(lang, en: "Say hi to her", zh: "跟她说句话", ja: "声をかける", ko: "말 걸기")) {
                    PetController.shared.speak()
                }
                Button(
                    model.isSleeping
                        ? LocalizedString.l(lang, en: "Wake her up", zh: "叫醒她", ja: "起こす", ko: "깨우기")
                        : LocalizedString.l(lang, en: "Let her nap", zh: "让她睡会儿", ja: "少し寝かせる", ko: "재우기")
                ) {
                    if model.isSleeping {
                        PetController.shared.speak()
                    } else {
                        PetController.shared.nap()
                    }
                }
                Divider()
                Picker(
                    LocalizedString.l(lang, en: "Size", zh: "大小", ja: "サイズ", ko: "크기"),
                    selection: Binding(
                        get: { PetController.shared.scale },
                        set: { PetController.shared.setScale($0) }
                    )
                ) {
                    Text(LocalizedString.l(lang, en: "Small", zh: "小", ja: "小", ko: "작게")).tag(CGFloat(0.8))
                    Text(LocalizedString.l(lang, en: "Medium", zh: "中", ja: "中", ko: "보통")).tag(CGFloat(1.0))
                    Text(LocalizedString.l(lang, en: "Large", zh: "大", ja: "大", ko: "크게")).tag(CGFloat(1.25))
                }
                Divider()
                Button(LocalizedString.l(lang, en: "Hide Pet", zh: "隐藏桌宠", ja: "ペットを隠す", ko: "펫 숨기기")) {
                    PetController.shared.hide()
                }
            }
            .help(
                LocalizedString.l(
                    lang,
                    en: "Click to poke her, double-click to open Agent, hold to drag, throw her and she'll fly",
                    zh: "点一下逗她，双击打开 Agent，按住可以拖来拖去，甩出去她会飞",
                    ja: "クリックでつつく、ダブルクリックで Agent を開く、長押しでドラッグ、投げると飛びます",
                    ko: "클릭하면 콕 찌르고, 더블클릭하면 Agent 열기, 길게 누르면 드래그, 던지면 날아가요"
                )
            )
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
