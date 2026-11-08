import AppKit
import SwiftUI

// MARK: - 桌宠

/// 桌面上的鲸鱼娘。
///
/// 用的是角色立绘（`Assets.xcassets/PetWhale`），动效全部由 SwiftUI 合成。
///
/// 动作一律「记时间戳 + 按当前时刻算」，不用 `withAnimation`：
/// 这里是 `TimelineView` 逐帧重绘的，隐式动画在这种结构下不会插值，
/// 而按时钟算反而更稳——掉帧也只是跳一下，不会失控。
struct WhalePetView: View {
    /// 立绘原始尺寸下画布多大。外框会按缩放放大。
    nonisolated static let baseSize = CGSize(width: 168, height: 190)

    private let model = PetModel.shared
    @State private var hover = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            stage(at: context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: Self.baseSize.width, height: Self.baseSize.height)
        .contentShape(Rectangle())
        .onHover { inside in
            hover = inside
            (inside ? NSCursor.openHand : NSCursor.arrow).set()
        }
    }

    // MARK: 舞台

    private func stage(at time: TimeInterval) -> some View {
        let mood = model.mood
        let breath = sin(2 * .pi * time / mood.breathPeriod)
        let sway = sin(2 * .pi * time / mood.swayPeriod)
        let squash = squashAmount(at: time)
        let extra = actionTransform(at: time)

        let rotation = mood.leanDegrees + sway * mood.swayDegrees + model.flightLean + extra.tilt
        let lift = breath * -1.6 + extra.lift

        return ZStack(alignment: .top) {
            if !model.airborne {
                groundShadow(breath: breath, squash: squash)
            }

            character(
                scaleX: (hover ? 1.04 : 1) * (1 + squash * 0.16),
                scaleY: (1 + 0.012 * breath) * (1 - squash * 0.14),
                rotation: rotation,
                lift: lift
            )

            if let bubble = model.bubble {
                bubbleView(bubble, at: time)
                    .zIndex(1)
            }
        }
    }

    // MARK: 影子

    private func groundShadow(breath: Double, squash: CGFloat) -> some View {
        Ellipse()
            .fill(.black.opacity(0.22))
            .frame(width: 104, height: 14)
            .blur(radius: 5)
            .scaleEffect(x: 1 - squash * 0.12, y: 1)
            .opacity(0.75 + 0.25 * (1 - abs(breath)))
            .offset(y: 166)
    }

    // MARK: 角色

    private func character(scaleX: CGFloat, scaleY: CGFloat, rotation: Double, lift: Double) -> some View {
        Image("PetWhale")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: 152)
            // 呼吸：横向几乎不动、纵向轻微拉伸，比整体缩放自然
            .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
            // 摇摆：锚点在脚底，看起来像重心在晃
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .offset(y: 4 + lift)
            .shadow(color: Color(red: 0.1, green: 0.25, blue: 0.5).opacity(0.28), radius: 8, y: 4)
    }

    // MARK: 气泡

    private func bubbleView(_ text: String, at time: TimeInterval) -> some View {
        let age = time - model.bubbleStartedAt.timeIntervalSinceReferenceDate
        let pop = age < 0.24 ? easeOutBack(min(1, max(0, age / 0.24))) : 1

        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 0.6)
                    )
            )
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .scaleEffect(pop, anchor: .bottom)
            .opacity(min(1, age / 0.12))
            .offset(y: -2)
            .onTapGesture {
                // 气泡比身体更像「有话要说」，点它直接开面板。
                PetController.shared.openAgent()
            }
    }

    // MARK: 动效

    /// 落地压扁：先快速压下去，再慢慢弹回来。
    private func squashAmount(at time: TimeInterval) -> CGFloat {
        let age = time - model.squashStartedAt.timeIntervalSinceReferenceDate
        guard age >= 0, age < 0.42 else { return 0 }
        let compress = min(1, age / 0.07)
        let release = max(0, 1 - (age - 0.07) / 0.35)
        return model.squashStrength * CGFloat(compress * release)
    }

    /// 空闲小动作：用 `sin(πp)` 让它自己回到原位。
    private func actionTransform(at time: TimeInterval) -> (lift: Double, tilt: Double) {
        let progress = model.action.progress(at: time - model.actionStartedAt.timeIntervalSinceReferenceDate)
        guard progress > 0, progress < 1 else { return (0, 0) }
        let pulse = sin(.pi * progress)
        return switch model.action {
        case .lookLeft: (0, -4.5 * pulse)
        case .lookRight: (0, 4.5 * pulse)
        case .crouch: (-3 * pulse, 0)
        case .hop(let height): (-Double(height) * pulse, 0)
        case .none: (0, 0)
        }
    }

    private func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        let p = x - 1
        return 1 + c3 * p * p * p + c1 * p * p
    }
}
