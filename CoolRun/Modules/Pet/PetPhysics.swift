import CoreGraphics
import Foundation

// MARK: - 刚体

/// 桌宠的位置与速度。
///
/// 坐标用窗口原点（屏幕坐标，y 轴向上），速度单位 px/s。
/// 这一层是纯值类型，可以脱离窗口单独测。
struct PetBody: Equatable, Sendable {
    var origin: CGPoint
    var velocity: CGVector

    nonisolated init(origin: CGPoint, velocity: CGVector = .zero) {
        self.origin = origin
        self.velocity = velocity
    }

    nonisolated var speed: CGFloat {
        (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
    }
}

extension CGVector {
    /// 速度大小（px/s）。
    nonisolated var speed: CGFloat {
        (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - 参数

/// 抛掷手感。默认值取自「拖着甩一把」这个场景：甩得出去、弹两下、自己停下。
struct PetPhysicsConfig: Equatable, Sendable {
    /// 重力（px/s²）。y 向上，所以程序里是减。
    var gravity: CGFloat = 1400
    /// 碰壁反弹恢复系数，0 撞上即停、1 完全弹性。
    var restitution: CGFloat = 0.78
    /// 落地后水平速度的衰减率（/s）。
    var groundFriction: CGFloat = 2.5
    /// 空气阻力（/s），只作用在水平方向，否则下落会变成拖尾的抛物线。
    var airDrag: CGFloat = 0.2
    /// 低于这个落地速度就不弹了，直接停住。
    var minBounceSpeed: CGFloat = 100
    /// 速度硬上限，防止一帧跨过整个屏幕。
    var maxSpeed: CGFloat = 4200

    nonisolated init() {}
}

/// 一帧的结果。
struct PetStepResult: Equatable, Sendable {
    /// 还在动，需要继续跑。
    var isMoving: Bool
    /// 这一帧撞到什么了（px/s，0 = 没撞）。用来决定要不要压扁、要不要震一下。
    var impact: CGFloat

    nonisolated init(isMoving: Bool, impact: CGFloat) {
        self.isMoving = isMoving
        self.impact = impact
    }
}

// MARK: - 积分

/// 一维刚体的显式欧拉积分，带边界约束。
enum PetPhysics {
    /// 低于这个速度就认为静止了，否则永远停不下来。
    nonisolated static let restingSpeed: CGFloat = 12

    /// 单帧最大步长。掉帧时 dt 会变大，不夹住就会一帧穿墙。
    nonisolated static let maxStep: CGFloat = 1.0 / 30.0

    /// 推进一帧。`bounds` 是可活动区域（通常取 `screen.visibleFrame`），`size` 是窗口尺寸。
    @discardableResult
    nonisolated static func step(
        _ body: inout PetBody,
        size: CGSize,
        bounds: CGRect,
        dt: TimeInterval,
        config: PetPhysicsConfig = PetPhysicsConfig()
    ) -> PetStepResult {
        let step = min(max(CGFloat(dt), 0), maxStep)
        guard step > 0 else {
            return PetStepResult(isMoving: body.speed > restingSpeed, impact: 0)
        }

        var impact: CGFloat = 0

        // 重力（y 向上 → 减）
        body.velocity.dy -= config.gravity * step

        // 水平空气阻力
        body.velocity.dx -= body.velocity.dx * config.airDrag * step

        let speed = body.speed
        if speed > config.maxSpeed {
            let k = config.maxSpeed / speed
            body.velocity.dx *= k
            body.velocity.dy *= k
        }

        body.origin.x += body.velocity.dx * step
        body.origin.y += body.velocity.dy * step

        // 左右墙
        if body.origin.x < bounds.minX {
            body.origin.x = bounds.minX
            body.velocity.dx = abs(body.velocity.dx) * config.restitution
            impact = max(impact, abs(body.velocity.dx) * 0.4)
        } else if body.origin.x + size.width > bounds.maxX {
            body.origin.x = bounds.maxX - size.width
            body.velocity.dx = -abs(body.velocity.dx) * config.restitution
            impact = max(impact, abs(body.velocity.dx) * 0.4)
        }

        // 天花板
        if body.origin.y + size.height > bounds.maxY {
            body.origin.y = bounds.maxY - size.height
            body.velocity.dy = -abs(body.velocity.dy) * config.restitution
        }

        // 地面
        if body.origin.y < bounds.minY {
            let landing = body.velocity.dy
            body.origin.y = bounds.minY
            if abs(landing) > config.minBounceSpeed {
                body.velocity.dy = -landing * config.restitution
                impact = max(impact, abs(landing))
            } else {
                body.velocity.dy = 0
                if abs(landing) > 30 {
                    impact = max(impact, abs(landing))
                }
            }
            // 落地摩擦
            body.velocity.dx -= body.velocity.dx * config.groundFriction * step
            if abs(body.velocity.dx) < restingSpeed {
                body.velocity.dx = 0
            }
        }

        let moving = body.speed > restingSpeed
        if !moving {
            body.velocity = .zero
        }
        return PetStepResult(isMoving: moving, impact: impact)
    }

    /// 把一帧的位置夹回可活动区域。窗口被拖到屏幕外、或换屏之后尺寸变了，用它兜底。
    nonisolated static func clamp(_ origin: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        )
    }
}
