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

    /// 关掉动效时画面定格（省电用），点击、拖动照常。
    var animated: Bool = true

    private let model = PetModel.shared
    @State private var hover = false

    var body: some View {
        // 关掉动效时把间隔拉到一分钟：画面定格，只剩点击和拖动。
        TimelineView(.periodic(from: .now, by: animated ? model.frameInterval : 60)) { context in
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

    /// 影子用径向渐变画，不用 `blur`。
    ///
    /// 高斯模糊会让每一帧都走一次离屏渲染，而这个窗口是常驻的、每秒要重绘十几次——
    /// 实测把待机 CPU 从 ~2.9% 压到 1% 以内。渐变边缘在 14pt 高的椭圆上看不出差别。
    private func groundShadow(breath: Double, squash: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [.black.opacity(0.26), .black.opacity(0.06), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 52
                )
            )
            .frame(width: 104, height: 14)
            .scaleEffect(x: 1 - squash * 0.12, y: 1)
            .opacity(0.75 + 0.25 * (1 - abs(breath)))
            .offset(y: 166)
    }

    // MARK: 角色

    private func character(scaleX: CGFloat, scaleY: CGFloat, rotation: Double, lift: Double) -> some View {
        ZStack(alignment: .bottom) {
            // 立绘背后垫一层压暗、下移的同一张图当投影。
            //
            // 这里原本是 `.shadow(radius: 8)`：模糊要离屏渲染，而这个窗口每秒重绘
            // 十几次，实测光这一条就吃掉约 2.5% CPU。用「叠一张暗图」代替后，
            // 只剩一次纹理绘制，肉眼几乎看不出区别，但待机功耗回到基线。
            Image("PetWhale")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 152)
                .saturation(0)
                .brightness(-0.28)
                .opacity(0.22)
                .offset(y: 3)

            Image("PetWhale")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 152)
        }
        // 呼吸：横向几乎不动、纵向轻微拉伸，比整体缩放自然
        .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
        // 摇摆：锚点在脚底，看起来像重心在晃
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(y: 4 + lift)
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
