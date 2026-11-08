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

/// 手边没有骨骼，动作只能靠整只身体做：歪一下头、蹦一下、缩一下。
enum PetAction: Equatable, Sendable {
    case none
    case lookLeft
    case lookRight
    case crouch
    case hop(CGFloat)

    nonisolated var duration: TimeInterval {
        switch self {
        case .none: 0
        case .lookLeft, .lookRight: 1.8
        case .crouch: 1.4
        case .hop: 0.62
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

    private var isDragging = false
    private var lastInteraction = Date()
    private var wasRunning = false
    private var transientMood: (mood: PetMood, until: Date)?
    private var bubbleToken = 0
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
        idleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 16...34)))
                guard !Task.isCancelled, let self else { return }
                self.playIdleAction()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        idleTask?.cancel()
        loopTask = nil
        idleTask = nil
    }

    // MARK: 外部事件

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

    private func playIdleAction() {
        guard mood == .idle, !isDragging, !isSleeping, !airborne, action == .none else { return }
        let picked: PetAction = switch Int.random(in: 0..<4) {
        case 0: .lookLeft
        case 1: .lookRight
        case 2: .hop(9)
        default: .crouch
        }
        play(picked)
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
