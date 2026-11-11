import CoreGraphics
import Foundation

// MARK: - 姿态

/// 一次动作最终都归到这七个通道上。
///
/// 立绘只有一张 PNG，没有骨骼，所以「动作」只能是整只身体的变换：
/// 平移、旋转、非等比缩放、斜切、透明度。把这些通道拼起来，
/// 一只平图也能做出跳、转、冲、抖、瘫、伸懒腰这些看得出来的动作。
struct PetPose: Equatable, Sendable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var rotation: Double = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    /// 斜切角度（度）。尾巴摆、身体扭全靠它。
    var skew: Double = 0
    var opacity: Double = 1

    nonisolated init(
        dx: CGFloat = 0,
        dy: CGFloat = 0,
        rotation: Double = 0,
        scaleX: CGFloat = 1,
        scaleY: CGFloat = 1,
        skew: Double = 0,
        opacity: Double = 1
    ) {
        self.dx = dx
        self.dy = dy
        self.rotation = rotation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.skew = skew
        self.opacity = opacity
    }

    nonisolated static let rest = PetPose()
}

// MARK: - 缓动

enum PetEasing: String, Sendable, CaseIterable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    /// 冲过头再回来，落地的「弹」感。
    case easeOutBack

    nonisolated func apply(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear:
            return x
        case .easeIn:
            return x * x
        case .easeOut:
            return 1 - (1 - x) * (1 - x)
        case .easeInOut:
            return x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x)
        case .easeOutBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            let p = x - 1
            return 1 + c3 * p * p * p + c1 * p * p
        }
    }
}

// MARK: - 关键帧

enum PetChannel: String, Sendable, CaseIterable {
    case dx
    case dy
    case rotation
    case scaleX
    case scaleY
    case skew
    case opacity
}

struct PetKeyframe: Sendable {
    /// 归一化时间 0…1。
    let at: Double
    let value: Double
    /// 从上一帧过渡到本帧用的缓动。
    let easing: PetEasing

    nonisolated init(_ at: Double, _ value: Double, _ easing: PetEasing = .easeInOut) {
        self.at = at
        self.value = value
        self.easing = easing
    }
}

/// 一个通道的关键帧表。
struct PetTrack: Sendable {
    let channel: PetChannel
    let frames: [PetKeyframe]

    nonisolated init(_ channel: PetChannel, _ frames: [PetKeyframe]) {
        self.channel = channel
        self.frames = frames.sorted { $0.at < $1.at }
    }

    /// 按归一化进度取值。落在区间外就夹到首尾帧。
    nonisolated func value(at progress: Double) -> Double {
        guard let first = frames.first else { return 0 }
        guard frames.count > 1 else { return first.value }
        let p = min(max(progress, 0), 1)

        if p <= first.at { return first.value }
        guard let last = frames.last else { return first.value }
        if p >= last.at { return last.value }

        for index in 1..<frames.count {
            let next = frames[index]
            guard p <= next.at else { continue }
            let previous = frames[index - 1]
            let span = next.at - previous.at
            guard span > 0 else { return next.value }
            let t = next.easing.apply((p - previous.at) / span)
            return previous.value + (next.value - previous.value) * t
        }
        return last.value
    }
}

// MARK: - 一段动作

/// 一条完整的动作：若干通道的关键帧表 + 时长。
struct PetMotion: Sendable, Identifiable {
    let name: String
    let duration: TimeInterval
    let tracks: [PetTrack]

    nonisolated var id: String { name }

    nonisolated init(_ name: String, duration: TimeInterval, tracks: [PetTrack]) {
        self.name = name
        self.duration = duration
        self.tracks = tracks
    }

    nonisolated func pose(at progress: Double) -> PetPose {
        var pose = PetPose.rest
        for track in tracks {
            let value = track.value(at: progress)
            switch track.channel {
            case .dx: pose.dx = CGFloat(value)
            case .dy: pose.dy = CGFloat(value)
            case .rotation: pose.rotation = value
            case .scaleX: pose.scaleX = CGFloat(value)
            case .scaleY: pose.scaleY = CGFloat(value)
            case .skew: pose.skew = value
            case .opacity: pose.opacity = value
            }
        }
        return pose
    }

    /// 按已经过去的秒数取值；超出时长就停在最后一帧。
    nonisolated func pose(elapsed: TimeInterval) -> PetPose {
        guard duration > 0 else { return .rest }
        return pose(at: min(max(elapsed / duration, 0), 1))
    }
}

// MARK: - 动作库

/// 桌宠的动作库。全部是纯数据，可单测。
///
/// 约定：动作从「原样」出发、回到「原样」，这样叠加在呼吸/摇摆上不会漂移。
enum PetMotionLibrary {
    /// 原地小跳，`height` 决定跳多高（点一下是小跳，高兴时跳得高）。
    nonisolated static func hopMotion(height: CGFloat) -> PetMotion {
        PetMotion("hop", duration: 0.62, tracks: [
            PetTrack(.dy, [PetKeyframe(0, 0, .linear), PetKeyframe(0.35, -Double(height), .easeOut), PetKeyframe(1, 0, .easeIn)]),
            PetTrack(.scaleY, [PetKeyframe(0, 1, .linear), PetKeyframe(0.12, 0.9, .easeOut), PetKeyframe(0.35, 1.08), PetKeyframe(0.72, 0.94, .easeIn), PetKeyframe(1, 1, .easeOutBack)]),
            PetTrack(.scaleX, [PetKeyframe(0, 1, .linear), PetKeyframe(0.12, 1.06, .easeOut), PetKeyframe(0.35, 0.96), PetKeyframe(0.72, 1.04, .easeIn), PetKeyframe(1, 1, .easeOutBack)]),
        ])
    }

    nonisolated static let hop = hopMotion(height: 18)

    /// 往一侧看。
    nonisolated static let lookLeft = PetMotion("lookLeft", duration: 1.8, tracks: [
        PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(0.18, -5, .easeOut), PetKeyframe(0.78, -5), PetKeyframe(1, 0, .easeInOut)]),
        PetTrack(.skew, [PetKeyframe(0, 0, .linear), PetKeyframe(0.18, -3, .easeOut), PetKeyframe(0.78, -3), PetKeyframe(1, 0, .easeInOut)]),
    ])

    nonisolated static let lookRight = PetMotion("lookRight", duration: 1.8, tracks: [
        PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(0.18, 5, .easeOut), PetKeyframe(0.78, 5), PetKeyframe(1, 0, .easeInOut)]),
        PetTrack(.skew, [PetKeyframe(0, 0, .linear), PetKeyframe(0.18, 3, .easeOut), PetKeyframe(0.78, 3), PetKeyframe(1, 0, .easeInOut)]),
    ])

    /// 缩一下（被点到、害羞）。
    nonisolated static let crouch = PetMotion("crouch", duration: 1.4, tracks: [
        PetTrack(.dy, [PetKeyframe(0, 0, .linear), PetKeyframe(0.16, 4, .easeOut), PetKeyframe(0.82, 4), PetKeyframe(1, 0, .easeInOut)]),
        PetTrack(.scaleY, [PetKeyframe(0, 1, .linear), PetKeyframe(0.16, 0.9, .easeOut), PetKeyframe(0.82, 0.92), PetKeyframe(1, 1, .easeOutBack)]),
        PetTrack(.scaleX, [PetKeyframe(0, 1, .linear), PetKeyframe(0.16, 1.07, .easeOut), PetKeyframe(0.82, 1.05), PetKeyframe(1, 1, .easeOutBack)]),
    ])

    /// 原地转一圈。
    nonisolated static let spin = PetMotion("spin", duration: 0.9, tracks: [
        PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(1, 360, .easeInOut)]),
        PetTrack(.dy, [PetKeyframe(0, 0, .linear), PetKeyframe(0.45, -12, .easeOut), PetKeyframe(1, 0, .easeIn)]),
        PetTrack(.scaleX, [PetKeyframe(0, 1, .linear), PetKeyframe(0.45, 0.9), PetKeyframe(1, 1, .easeOutBack)]),
    ])

    /// 向一侧冲出去再回来（画布内的位移，不搬窗口）。
    nonisolated static func dash(_ direction: CGFloat) -> PetMotion {
        let sign = direction >= 0 ? 1.0 : -1.0
        return PetMotion("dash", duration: 0.78, tracks: [
            PetTrack(.dx, [PetKeyframe(0, 0, .linear), PetKeyframe(0.4, 26 * sign, .easeOut), PetKeyframe(1, 0, .easeInOut)]),
            PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(0.4, 9 * sign, .easeOut), PetKeyframe(1, 0, .easeInOut)]),
            PetTrack(.scaleX, [PetKeyframe(0, 1, .linear), PetKeyframe(0.4, 1.1, .easeOut), PetKeyframe(1, 1, .easeOutBack)]),
        ])
    }

    /// 扭一扭（摆尾巴）。
    nonisolated static let wiggle = PetMotion("wiggle", duration: 1.5, tracks: [
        PetTrack(.skew, wave(amplitude: 7, cycles: 2.5)),
        PetTrack(.rotation, wave(amplitude: 3, cycles: 2.5)),
    ])

    /// 伸懒腰：拉长 + 轻微后仰。
    nonisolated static let stretch = PetMotion("stretch", duration: 1.9, tracks: [
        PetTrack(.scaleY, [PetKeyframe(0, 1, .linear), PetKeyframe(0.3, 1.12, .easeOut), PetKeyframe(0.62, 1.12), PetKeyframe(1, 1, .easeInOut)]),
        PetTrack(.scaleX, [PetKeyframe(0, 1, .linear), PetKeyframe(0.3, 0.93, .easeOut), PetKeyframe(0.62, 0.94), PetKeyframe(1, 1, .easeInOut)]),
        PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(0.3, -4, .easeOut), PetKeyframe(0.62, -4), PetKeyframe(1, 0, .easeInOut)]),
    ])

    /// 抖一抖（甩水、生气）。
    nonisolated static let shake = PetMotion("shake", duration: 0.7, tracks: [
        PetTrack(.dx, wave(amplitude: 5, cycles: 4)),
        PetTrack(.rotation, wave(amplitude: 4, cycles: 4)),
    ])

    /// 探头：往下钻一点再冒出来。
    nonisolated static let peek = PetMotion("peek", duration: 2.2, tracks: [
        PetTrack(.dy, [PetKeyframe(0, 0, .linear), PetKeyframe(0.22, 14, .easeIn), PetKeyframe(0.42, -4, .easeOutBack), PetKeyframe(0.78, -4), PetKeyframe(1, 0, .easeInOut)]),
        PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(0.42, 6, .easeOut), PetKeyframe(0.78, 6), PetKeyframe(1, 0, .easeInOut)]),
    ])

    /// 蹦两下庆祝。
    nonisolated static let celebrate = PetMotion("celebrate", duration: 1.15, tracks: [
        PetTrack(.dy, [
            PetKeyframe(0, 0, .linear),
            PetKeyframe(0.22, -22, .easeOut), PetKeyframe(0.4, 0, .easeIn),
            PetKeyframe(0.62, -15, .easeOut), PetKeyframe(0.8, 0, .easeIn),
            PetKeyframe(1, 0),
        ]),
        PetTrack(.scaleY, [PetKeyframe(0, 1, .linear), PetKeyframe(0.1, 0.92, .easeOut), PetKeyframe(0.22, 1.06), PetKeyframe(1, 1, .easeOutBack)]),
        PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(0.3, -6, .easeOut), PetKeyframe(0.7, 6, .easeInOut), PetKeyframe(1, 0)]),
    ])

    /// 瘫掉（出错、被打击）。
    nonisolated static let faint = PetMotion("faint", duration: 2.6, tracks: [
        PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(0.25, 12, .easeIn), PetKeyframe(0.8, 12), PetKeyframe(1, 0, .easeInOut)]),
        PetTrack(.dy, [PetKeyframe(0, 0, .linear), PetKeyframe(0.25, 8, .easeIn), PetKeyframe(0.8, 8), PetKeyframe(1, 0, .easeInOut)]),
        PetTrack(.scaleY, [PetKeyframe(0, 1, .linear), PetKeyframe(0.25, 0.9, .easeIn), PetKeyframe(0.8, 0.9), PetKeyframe(1, 1, .easeInOut)]),
        PetTrack(.opacity, [PetKeyframe(0, 1, .linear), PetKeyframe(0.25, 0.75), PetKeyframe(0.8, 0.75), PetKeyframe(1, 1)]),
    ])

    /// 打哈欠。
    nonisolated static let yawn = PetMotion("yawn", duration: 1.7, tracks: [
        PetTrack(.scaleY, [PetKeyframe(0, 1, .linear), PetKeyframe(0.35, 1.07, .easeOut), PetKeyframe(0.75, 1.05), PetKeyframe(1, 1, .easeInOut)]),
        PetTrack(.rotation, [PetKeyframe(0, 0, .linear), PetKeyframe(0.35, -5, .easeOut), PetKeyframe(0.75, -4), PetKeyframe(1, 0, .easeInOut)]),
        PetTrack(.dy, [PetKeyframe(0, 0, .linear), PetKeyframe(0.35, -3, .easeOut), PetKeyframe(1, 0, .easeInOut)]),
    ])

    /// 点头。
    nonisolated static let nod = PetMotion("nod", duration: 1.1, tracks: [
        PetTrack(.dy, wave(amplitude: 4, cycles: 2)),
        PetTrack(.rotation, wave(amplitude: 2.5, cycles: 2)),
    ])

    /// 被拎起来：身体往下坠、轻轻晃。
    nonisolated static let dangle = PetMotion("dangle", duration: 1.4, tracks: [
        PetTrack(.dy, [PetKeyframe(0, 0, .linear), PetKeyframe(0.2, 5, .easeOut), PetKeyframe(1, 5)]),
        PetTrack(.rotation, wave(amplitude: 5, cycles: 1.5)),
        PetTrack(.scaleY, [PetKeyframe(0, 1, .linear), PetKeyframe(0.2, 1.06, .easeOut), PetKeyframe(1, 1.04)]),
    ])

    /// 正弦摆动生成的关键帧表：`cycles` 个完整周期，回到原位。
    nonisolated static func wave(amplitude: Double, cycles: Double, samples: Int = 16) -> [PetKeyframe] {
        let count = max(2, samples)
        return (0...count).map { index in
            let t = Double(index) / Double(count)
            return PetKeyframe(t, amplitude * sin(2 * .pi * cycles * t), .linear)
        }
    }
}
