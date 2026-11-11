import CoreGraphics
import Foundation

// MARK: - 情绪符号

/// 飘在头顶的小符号：睡觉的 z、开心的心、出错的黑线。
///
/// 这些不用图片，全部走 SF Symbols——矢量、便宜、跟系统风格一致，
/// 也不用为了几个小图标往包里塞 PNG。
enum PetEffectKind: String, Sendable, CaseIterable {
    case zzz
    case heart
    case star
    case sweat
    case question
    case exclamation
    case note
    case sparkle
    case confetti
    case anger

    nonisolated var symbol: String {
        switch self {
        case .zzz: "zzz"
        case .heart: "heart.fill"
        case .star: "star.fill"
        case .sweat: "drop.fill"
        case .question: "questionmark"
        case .exclamation: "exclamationmark"
        case .note: "music.note"
        case .sparkle: "sparkles"
        case .confetti: "party.popper.fill"
        case .anger: "flame.fill"
        }
    }

    nonisolated var life: TimeInterval {
        switch self {
        case .zzz: 2.6
        case .heart: 1.5
        case .star: 1.1
        case .sweat: 1.2
        case .question: 1.6
        case .exclamation: 1.2
        case .note: 2.0
        case .sparkle: 1.0
        case .confetti: 1.8
        case .anger: 1.0
        }
    }

    /// 画出来多大（按画布 168×190 的比例，视图里再乘缩放）。
    nonisolated var size: CGFloat {
        switch self {
        case .zzz: 15
        case .heart: 13
        case .star: 11
        case .sweat: 10
        case .question: 13
        case .exclamation: 14
        case .note: 12
        case .sparkle: 12
        case .confetti: 14
        case .anger: 13
        }
    }

    /// 飘多高（负值向上）。
    nonisolated var rise: CGFloat {
        switch self {
        case .zzz: -34
        case .heart: -40
        case .star: -26
        case .sweat: 14
        case .question: -30
        case .exclamation: -26
        case .note: -36
        case .sparkle: -20
        case .confetti: -44
        case .anger: -22
        }
    }

    /// 同一批里要不要左右散开（彩带、星星散开更好看）。
    nonisolated var spread: CGFloat {
        switch self {
        case .confetti, .sparkle, .star: 26
        case .heart: 16
        default: 8
        }
    }
}

// MARK: - 一个符号实例

struct PetEffect: Identifiable, Sendable {
    let id: UUID
    let kind: PetEffectKind
    let bornAt: Date
    let life: TimeInterval
    /// 出生位置，归一化到画布（0…1，y 向下）。
    let origin: CGPoint
    /// 整段生命里的总位移（归一化）。
    let drift: CGSize
    /// 期间转多少度。
    let spin: Double
    /// 相对基准大小的倍数。
    let scale: CGFloat
    /// 起飞延迟，让同一批错开。
    let delay: TimeInterval

    nonisolated func progress(at now: Date) -> Double {
        let age = now.timeIntervalSince(bornAt) - delay
        guard life > 0 else { return 1 }
        return min(max(age / life, 0), 1)
    }

    nonisolated func isAlive(at now: Date) -> Bool {
        now.timeIntervalSince(bornAt) - delay < life
    }
}

// MARK: - 生成

/// 造符号的小工厂：一次吐出一批，位置、方向、转速都带点随机，
/// 不然每次看到的花样都一模一样，反而假。
enum PetEffectBurst {
    nonisolated static func make(
        _ kind: PetEffectKind,
        count: Int = 1,
        at origin: CGPoint = CGPoint(x: 0.5, y: 0.28),
        now: Date = Date()
    ) -> [PetEffect] {
        let total = max(1, min(count, 12))
        return (0..<total).map { index in
            let offsetX = CGFloat.random(in: -0.5...0.5) * kind.spread / 168
            let spread = Double.random(in: 0.6...1.15)
            return PetEffect(
                id: UUID(),
                kind: kind,
                bornAt: now,
                life: kind.life * Double.random(in: 0.85...1.2),
                origin: CGPoint(
                    x: origin.x + offsetX,
                    y: origin.y + CGFloat.random(in: -0.02...0.02)
                ),
                drift: CGSize(
                    width: kind.spread / 168 * CGFloat.random(in: -1...1) * 0.8,
                    height: kind.rise / 190 * CGFloat(spread)
                ),
                spin: Double.random(in: -28...28),
                scale: CGFloat.random(in: 0.8...1.2),
                delay: total > 1 ? Double(index) * 0.09 : 0
            )
        }
    }
}
