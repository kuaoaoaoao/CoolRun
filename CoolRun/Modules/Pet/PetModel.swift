import Foundation
import SwiftUI

// MARK: - 心情

/// 她在想什么。比「忙 / 不忙」多几档，才看得出她在干活。
enum PetMood: Equatable, Sendable {
    case idle
    case thinking
    case working(String)
    case waiting
    case success
    case error
    case sleeping

    /// 呼吸与摇摆的周期（秒）。越急的档位晃得越快。
    nonisolated var breathPeriod: Double {
        switch self {
        case .idle: 2.4
        case .thinking: 1.6
        case .working: 2.0
        case .waiting: 0.9
        case .success: 1.5
        case .error: 3.2
        case .sleeping: 4.6
        }
    }

    nonisolated var swayPeriod: Double {
        switch self {
        case .idle: 3.1
        case .thinking: 1.8
        case .working: 2.2
        case .waiting: 1.1
        case .success: 1.6
        case .error: 4.0
        case .sleeping: 6.0
        }
    }

    /// 摇摆幅度（度）。
    nonisolated var swayDegrees: Double {
        switch self {
        case .idle: 1.5
        case .thinking: 2.2
        case .working: 1.8
        case .waiting: 3.0
        case .success: 2.6
        case .error: 1.0
        case .sleeping: 0.8
        }
    }

    /// 整体微微倾斜，用来区分「歪着头想」和「站直了等」。
    nonisolated var leanDegrees: Double {
        switch self {
        case .idle: 0
        case .thinking: -2.2
        case .working: -1.2
        case .waiting: 1.8
        case .success: 0
        case .error: 2.4
        case .sleeping: 3.0
        }
    }
}

// MARK: - 一次小动作

/// 手边没有骨骼，动作只能靠整只身体做：歪一下头、蹦一下、缩一下、转一圈。
///
/// 每个动作对应的关键帧在 `PetMotionLibrary` 里，这里只负责「叫什么、多久」。
enum PetAction: Equatable, Sendable {
    case none
    case lookLeft
    case lookRight
    case crouch
    case hop(CGFloat)
    /// 原地转一圈。
    case spin
    /// 向一侧冲（正数向右）。
    case dash(CGFloat)
    /// 扭一扭。
    case wiggle
    /// 伸懒腰。
    case stretch
    /// 抖一抖。
    case shake
    /// 蹦两下庆祝。
    case celebrate
    /// 瘫掉。
    case faint
    /// 打哈欠。
    case yawn
    /// 点头。
    case nod
    /// 探头。
    case peek

    nonisolated var duration: TimeInterval {
        switch self {
        case .none: 0
        case .lookLeft, .lookRight: 1.8
        case .crouch: 1.4
        case .hop: 0.62
        case .spin: 0.9
        case .dash: 0.78
        case .wiggle: 1.5
        case .stretch: 1.9
        case .shake: 0.7
        case .celebrate: 1.15
        case .faint: 2.6
        case .yawn: 1.7
        case .nod: 1.1
        case .peek: 2.2
        }
    }

    /// 这个动作怎么画。`none` 没有。
    nonisolated var motion: PetMotion? {
        switch self {
        case .none: nil
        case .lookLeft: PetMotionLibrary.lookLeft
        case .lookRight: PetMotionLibrary.lookRight
        case .crouch: PetMotionLibrary.crouch
        case .hop(let height): PetMotionLibrary.hopMotion(height: height)
        case .spin: PetMotionLibrary.spin
        case .dash(let direction): PetMotionLibrary.dash(direction)
        case .wiggle: PetMotionLibrary.wiggle
        case .stretch: PetMotionLibrary.stretch
        case .shake: PetMotionLibrary.shake
        case .celebrate: PetMotionLibrary.celebrate
        case .faint: PetMotionLibrary.faint
        case .yawn: PetMotionLibrary.yawn
        case .nod: PetMotionLibrary.nod
        case .peek: PetMotionLibrary.peek
        }
    }

    /// 进度 0→1；`sin(πp)` 让动作自己回去，不用写回落逻辑。
    nonisolated func progress(at elapsed: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}

// MARK: - 模型

/// 桌宠的表现状态：心情、气泡、压扁、空中姿态、正在做的小动作。
///
/// 窗口移动是 `PetController` 的事，这里只管「看起来怎么样」。
/// 所有动效都记时间戳、由视图按时钟算，不走 SwiftUI 的 `withAnimation`——
/// 视图那边是 `TimelineView` 逐帧重算的，隐式动画在那儿不生效。
@MainActor
@Observable
final class PetModel {
    static let shared = PetModel()

    /// 多久没动就睡着（秒）。
    nonisolated static let sleepAfter: TimeInterval = 240

    private(set) var mood: PetMood = .idle
    private(set) var bubble: String?
    private(set) var bubbleStartedAt = Date.distantPast

    /// 落地压扁的起点与力度。
    private(set) var squashStartedAt = Date.distantPast
    private(set) var squashStrength: CGFloat = 0

    /// 空中：影子要藏起来，身体顺着飞行方向倒。
    private(set) var airborne = false
    private(set) var flightLean: Double = 0

    private(set) var action: PetAction = .none
    private(set) var actionStartedAt = Date.distantPast

    private(set) var isSleeping = false

    /// 正在被搬着走（屏幕上溜达）。走的时候要满帧，不然看着像漂移。
    private(set) var isGliding = false

    /// 飘在头顶的小符号。视图按时钟画，这里只管生成和回收。
    private(set) var effects: [PetEffect] = []

    /// 渲染时钟：视图读它触发重绘。
    ///
    /// 没用 `TimelineView(.periodic(by:))`——它的间隔只是「最早什么时候可以更新」，
    /// 视图一有变化 SwiftUI 照样按屏幕刷新率（这台 120Hz）重算；换成
    /// `.animation(minimumInterval:)` 更糟，它本来就跟着显示刷新率跑。
    /// 自己按 `frameInterval` 发 tick，才真的能把重绘压到 6fps，动作时升到 24fps。
    private(set) var frameTick = 0
    private(set) var frameTime = Date.timeIntervalSinceReferenceDate

    /// 关掉动效时停掉渲染时钟，画面定格（点击、拖动照常）。
    var animating = true

    private var renderTask: Task<Void, Never>?

    /// 「去那边逛逛」的请求：参数是往哪边、走多远（点）。由 `PetController` 搬窗口。
    @ObservationIgnored var onWander: ((CGFloat) -> Void)?

    /// 渲染帧率（秒/帧）。
    ///
    /// 菜单栏常驻程序不该为了一个装饰动画一直满帧重绘——那样即使什么都不做，
    /// 也会把 CPU 从睡眠里叫醒。所以按状态分档：睡着 3fps、待机 12fps、
    /// 在干活 20fps，只有真的飞起来或者正在做动作才用满帧 24fps。
    var frameInterval: TimeInterval {
        if isGliding { return 1.0 / 24.0 }
        if airborne { return 1.0 / 24.0 }
        if action != .none { return 1.0 / 24.0 }
        if isSleeping { return 1.0 / 2.0 }
        switch mood {
        case .sleeping:
            return 1.0 / 2.0
        case .thinking, .working, .waiting, .success, .error:
            return 1.0 / 15.0
        case .idle:
            // 呼吸一个周期四秒多，6fps 已经看不出顿；再快只是白烧电。
            return 1.0 / 6.0
        }
    }

    private var isDragging = false
    private var lastInteraction = Date()
    private var wasRunning = false
    private var transientMood: (mood: PetMood, until: Date)?
    private var bubbleToken = 0
    private var lastZzz = Date.distantPast
    private var loopTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    private init() {}

    // MARK: 生命周期

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.syncMood()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        renderTask?.cancel()
        renderTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.animating {
                    self.frameTime = Date.timeIntervalSinceReferenceDate
                    self.frameTick &+= 1
                    try? await Task.sleep(for: .seconds(self.frameInterval))
                } else {
                    // 定格时低频转一圈，别把任务停死，重新开动效要能立刻接上。
                    try? await Task.sleep(for: .seconds(0.5))
                }
            }
        }

        idleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 9...22)))
                guard !Task.isCancelled, let self else { return }
                self.playIdleAction()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        idleTask?.cancel()
        renderTask?.cancel()
        loopTask = nil
        idleTask = nil
        renderTask = nil
    }

    // MARK: 外部事件

    /// 窗口正在被搬着走。只影响帧率。
    func setGliding(_ gliding: Bool) {
        guard gliding != isGliding else { return }
        isGliding = gliding
    }

    /// 冒一个小符号出来。
    func spawn(_ kind: PetEffectKind, count: Int = 1, at origin: CGPoint = CGPoint(x: 0.5, y: 0.3)) {
        effects.append(contentsOf: PetEffectBurst.make(kind, count: count, at: origin))
        if effects.count > 18 {
            effects.removeFirst(effects.count - 18)
        }
    }

    func setDragging(_ dragging: Bool) {
        isDragging = dragging
        lastInteraction = Date()
        if dragging {
            isSleeping = false
            action = .none
        }
    }

    /// 被抛出去了：影子藏起来，身体顺着飞行方向倒一点。
    func setAirborne(_ flying: Bool, horizontalVelocity: CGFloat = 0) {
        airborne = flying
        flightLean = flying ? Double(max(-14, min(14, horizontalVelocity / 90))) : 0
    }

    /// 落地。strength 0~1，越大压得越扁。
    func land(strength: CGFloat) {
        squashStrength = max(0.2, min(1, strength))
        squashStartedAt = Date()
        if strength > 0.55 {
            spawn(.sweat, count: 2, at: CGPoint(x: 0.5, y: 0.36))
        }
    }

    /// 被戳了一下。
    func poke() {
        lastInteraction = Date()
        if isSleeping {
            isSleeping = false
            say("唔…醒了醒了", seconds: 2.2)
        } else {
            say(Self.pokeLines.randomElement() ?? "嗯？", seconds: 2.2)
        }
        spawn(.heart, count: 2, at: CGPoint(x: 0.5, y: 0.26))
        play(.hop(7))
    }

    /// 点气泡、双击之类的「正经事」也算互动。
    func touch() {
        lastInteraction = Date()
        isSleeping = false
    }

    /// 右键菜单里的「让她睡会儿」。
    func nap() {
        lastInteraction = Date().addingTimeInterval(Self.sleepAfter)
        isSleeping = true
        apply(.sleeping)
    }

    // MARK: 心情同步

    private func syncMood() {
        let coordinator = AgentCoordinator.shared
        let now = Date()

        pruneEffects(at: now)
        if isSleeping || mood == .sleeping, now.timeIntervalSince(lastZzz) > 1.9 {
            lastZzz = now
            spawn(.zzz, count: 1, at: CGPoint(x: 0.66, y: 0.24))
        }

        if coordinator.isRunning {
            wasRunning = true
            transientMood = nil
            if coordinator.pendingApproval != nil {
                apply(.waiting)
            } else if let last = coordinator.activities.last, !last.isFinished {
                apply(.working(Self.friendlyTool(last.name)))
            } else {
                apply(.thinking)
            }
            return
        }

        if wasRunning {
            wasRunning = false
            let failed = !(coordinator.errorMessage ?? "").isEmpty
            let mood: PetMood = failed ? .error : .success
            transientMood = (mood, now.addingTimeInterval(failed ? 4 : 2.6))
            apply(mood)
            return
        }

        if let transient = transientMood, now < transient.until {
            apply(transient.mood)
            return
        }
        transientMood = nil

        if !isSleeping, now.timeIntervalSince(lastInteraction) > Self.sleepAfter {
            isSleeping = true
        }
        apply(isSleeping ? .sleeping : .idle)
    }

    private func apply(_ next: PetMood) {
        guard next != mood else { return }
        mood = next
        say(Self.bubbleText(for: next), seconds: nil)
        react(to: next)
    }

    /// 换心情时顺手给个动作和小符号，别只是换张脸。
    private func react(to mood: PetMood) {
        switch mood {
        case .success:
            play(.celebrate)
            spawn(.sparkle, count: 4, at: CGPoint(x: 0.5, y: 0.3))
        case .error:
            play(.faint)
            spawn(.anger, count: 2, at: CGPoint(x: 0.5, y: 0.24))
        case .waiting:
            spawn(.question, count: 1, at: CGPoint(x: 0.72, y: 0.22))
        case .thinking:
            spawn(.note, count: 1, at: CGPoint(x: 0.28, y: 0.24))
        case .working:
            spawn(.sparkle, count: 1, at: CGPoint(x: 0.3, y: 0.3))
        case .sleeping:
            spawn(.zzz, count: 1, at: CGPoint(x: 0.66, y: 0.24))
        case .idle:
            break
        }
    }

    private func say(_ text: String?, seconds: Double?) {
        bubbleToken += 1
        let token = bubbleToken
        bubble = text
        bubbleStartedAt = Date()
        guard let seconds else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, token == self.bubbleToken else { return }
            self.bubble = nil
        }
    }

    // MARK: 空闲小动作

    /// 没人管的时候自己找点事做。
    ///
    /// 权重是调出来的：左右看、扭一扭这类小动作占大头（安静），
    /// 溜达、转圈这类大动作占小头（不然一直在动，吵）。
    private func playIdleAction() {
        guard mood == .idle, !isDragging, !isSleeping, !airborne, !isGliding, action == .none else { return }

        switch Int.random(in: 0..<100) {
        case ..<16: play(.lookLeft)
        case ..<32: play(.lookRight)
        case ..<42: play(.hop(9))
        case ..<50: play(.crouch)
        case ..<58: play(.wiggle)
        case ..<66: play(.stretch)
        case ..<72: play(.nod)
        case ..<77: play(.peek)
        case ..<82: play(.yawn)
        case ..<88: play(.spin)
        case ..<94: wander()
        default: play(.dash(CGFloat.random(in: -1...1)))
        }
    }

    /// 在屏幕上溜达一段：动作交给窗口，身体顺带做个前冲。
    private func wander() {
        guard let onWander else { return }
        let direction: CGFloat = Bool.random() ? 1 : -1
        play(.dash(direction))
        onWander(direction * CGFloat.random(in: 60...180))
    }

    private func pruneEffects(at now: Date) {
        guard !effects.isEmpty else { return }
        effects.removeAll { !$0.isAlive(at: now) }
    }

    /// 当前动作的姿态。视图和模型用同一个时钟，掉帧只是跳一下，不会跑偏。
    func actionPose(at time: TimeInterval) -> PetPose {
        guard let motion = action.motion else { return .rest }
        return motion.pose(elapsed: time - actionStartedAt.timeIntervalSinceReferenceDate)
    }

    private func play(_ next: PetAction) {
        guard next != .none else { return }
        action = next
        actionStartedAt = Date()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(next.duration))
            guard let self, self.action == next else { return }
            self.action = .none
        }
    }

    // MARK: 文案

    nonisolated static func bubbleText(for mood: PetMood) -> String? {
        switch mood {
        case .idle: nil
        case .sleeping: "z Z"
        case .thinking: "本鱼在想…"
        case .working(let tool): "在用「\(tool)」"
        case .waiting: "等你点一下下～"
        case .success: "想好啦！"
        case .error: "哎呀，卡住了"
        }
    }

    /// 工具名太长，气泡里放不下，翻成人话。
    nonisolated static func friendlyTool(_ name: String) -> String {
        switch name {
        case "system_snapshot": "看系统"
        case "system_processes": "翻进程"
        case "system_battery": "看电池"
        case "system_network": "看网速"
        case "gold_price": "查金价"
        case "gold_history": "翻金价历史"
        case "gold_signals", "gold_technical": "算指标"
        case "gold_forecast", "gold_strategy": "想策略"
        case "calendar_upcoming": "翻日程"
        case "english_daily": "备今日英语"
        case "quota_status": "查额度"
        case "notes_search": "翻笔记"
        case "notes_create": "记笔记"
        case "notes_toggle_pin": "钉笔记"
        case "clipboard_search": "翻剪贴板"
        case "clipboard_copy": "复制"
        case "ui_switch_panel": "换面板"
        case "notify": "提醒你"
        case "reminder_create": "设提醒"
        case "screenshot": "截图"
        default:
            name.hasPrefix("plugin_") ? "用插件" : name
        }
    }

    nonisolated static let pokeLines = [
        "诶？",
        "摸鱼中…",
        "干嘛呀～",
        "本鱼在呢",
        "有事说事，没事摸鱼",
        "别戳啦，痒",
        "再戳就要收费了",
    ]
}
