import AppKit
import SwiftUI

// MARK: - 斜切

/// 只在真需要斜切时才套 `projectionEffect`。
///
/// 零斜切也套的话，SwiftUI 每帧都要为这个视图建一次离屏合成层——
/// 而桌宠窗口是常驻的、每秒重绘十几帧，这笔开销会一直挂着。
private struct PetShearModifier: ViewModifier {
    let shear: CGFloat

    func body(content: Content) -> some View {
        if abs(shear) < 0.02 {
            content
        } else {
            content.projectionEffect(
                ProjectionTransform(CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: 0, ty: 0))
            )
        }
    }
}

// MARK: - 桌宠

/// 桌面上的鲸鱼娘。
///
/// 用的是角色立绘（`Assets.xcassets/PetWhale`），动效全部由 SwiftUI 合成。
///
/// 动作一律「记时间戳 + 按当前时刻算」，不用 `withAnimation`：
/// 这里是 `TimelineView` 逐帧重绘的，隐式动画在这种结构下不会插值，
/// 而按时钟算反而更稳——掉帧也只是跳一下，不会失控。
///
/// 姿态分成三层叠起来：
/// 1. 心情（呼吸、摇摆、倾斜）——一直有；
/// 2. 动作（`PetAction` 的关键帧）——做的时候有；
/// 3. 落地压扁——被扔下来的时候有。
/// 三层各算各的，最后加成一个 `PetPose` 交给身体。
struct WhalePetView: View {
    /// 立绘原始尺寸下画布多大。外框会按缩放放大。
    nonisolated static let baseSize = CGSize(width: 196, height: 200)

    /// 视频片段的原始画布（`scripts/pet-clips.sh` 里裁的尺寸）。
    nonisolated static let clipCanvas = CGSize(width: 336, height: 300)

    /// 把片段等比塞进画布后的显示尺寸。
    nonisolated static var clipDisplaySize: CGSize {
        let scale = min(baseSize.width / clipCanvas.width, baseSize.height / clipCanvas.height)
        return CGSize(width: clipCanvas.width * scale, height: clipCanvas.height * scale)
    }

    /// 关掉动效时画面定格（省电用），点击、拖动照常。
    var animated: Bool = true

    private let model = PetModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var hover = false

    var body: some View {
        // 重绘由 `PetModel.frameTick` 驱动，不用 `TimelineView`。
        //
        // `TimelineView(.periodic(by:))` 的间隔只是「最早什么时候可以更新」，
        // 视图一有变化 SwiftUI 照样按屏幕刷新率重算（这台 120Hz）；换成
        // `.animation(minimumInterval:)` 更糟——它本来就跟着显示刷新率跑，
        // 实测功耗从 8% 涨到 12%。自己按 `frameInterval` 发 tick 才能真压到 6fps。
        //
        // 读一下 `frameTick` 是为了让 SwiftUI 订阅这个属性：它一变，body 重算。
        let _ = model.frameTick

        return stage(at: model.frameTime, scheme: colorScheme)
            .frame(width: Self.baseSize.width, height: Self.baseSize.height)
            .contentShape(Rectangle())
            .onHover { inside in
                hover = inside
                (inside ? NSCursor.openHand : NSCursor.arrow).set()
            }
    }

    /// 播视频还是画立绘。
    ///
    /// 关掉动效时退回立绘（静态定格更省电，视频没法「暂停在某一帧还好看」）；
    /// 素材缺失或视频起不来时也退回立绘，不能白屏。
    private var showsClip: Bool {
        animated && model.videoEnabled && model.videoAvailable && model.clip.isBundled
    }

    // MARK: 舞台

    private func stage(at time: TimeInterval, scheme: ColorScheme) -> some View {
        let mood = model.mood
        let breath = sin(2 * .pi * time / mood.breathPeriod)
        let sway = sin(2 * .pi * time / mood.swayPeriod)
        let squash = squashAmount(at: time)
        let motion = model.actionPose(at: time)

        // 三层姿态合成：心情的呼吸摇摆 + 动作的关键帧 + 落地压扁。
        let pose = PetPose(
            dx: motion.dx,
            dy: breath * -1.6 + motion.dy,
            rotation: mood.leanDegrees + sway * mood.swayDegrees + model.flightLean + motion.rotation,
            scaleX: motion.scaleX * (hover ? 1.04 : 1) * (1 + squash * 0.16),
            scaleY: motion.scaleY * (1 + 0.012 * breath) * (1 - squash * 0.14),
            skew: motion.skew,
            opacity: motion.opacity
        )

        return ZStack(alignment: .top) {
            // 视频片段自带落地阴影，再画一个会叠成两层。
            if !model.airborne && !showsClip {
                groundShadow(breath: breath, squash: squash)
            }

            if showsClip {
                // 有素材就播插件那套视频——它本来就是这只鱼的逐帧动画，
                // 比在单张立绘上做姿态变换自然得多。
                PetVideoView(
                    clip: model.clip,
                    isPaused: !animated || model.videoPaused,
                    onFinished: { model.clipDidFinish() },
                    onUnavailable: { model.markVideoUnavailable() }
                )
                .frame(width: Self.clipDisplaySize.width, height: Self.clipDisplaySize.height)
                .offset(y: Self.baseSize.height - Self.clipDisplaySize.height)
                .allowsHitTesting(false)
            } else {
                character(pose: pose)
            }

            if !model.effects.isEmpty {
                effectsLayer(at: time, scheme: scheme)
            }

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
            .offset(y: 176)
    }

    // MARK: 角色

    private func character(pose: PetPose) -> some View {
        // 斜切（扭动、甩尾）：`projectionEffect` 的剪切是绕左上角做的，
        // 拿半高补一下，看上去才像绕身体中线在扭。
        let shear = tan(pose.skew * .pi / 180)
        let shearCompensation = -shear * 76

        return ZStack(alignment: .bottom) {
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
                // 剪影用 `colorMultiply(.black)`：一次混合就够。
                // 原来是 `.saturation(0).brightness(-0.28)`——两道颜色矩阵，
                // 每一帧都要重算一遍，实测这是待机功耗的大头。
                .colorMultiply(.black)
                .opacity(0.22)
                .offset(y: 3)

            Image("PetWhale")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 152)
        }
        // 呼吸与动作的缩放：锚点在脚底，像重心在脚下
        .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
        // 斜切只在真扭动时才挂上去：`projectionEffect` 会强制离屏合成，
        // 平时（skew 恒为 0）白付这笔钱，实测待机功耗翻倍。
        .modifier(PetShearModifier(shear: shear))
        // 摇摆：锚点在脚底，看起来像重心在晃
        .rotationEffect(.degrees(pose.rotation), anchor: .bottom)
        .offset(x: pose.dx + shearCompensation, y: 4 + pose.dy)
        .opacity(pose.opacity)
    }

    // MARK: 情绪符号

    /// 飘在头顶的符号层。全部是 SF Symbols，跟着动作一起漂、一起淡。
    private func effectsLayer(at time: TimeInterval, scheme: ColorScheme) -> some View {
        let now = Date(timeIntervalSinceReferenceDate: time)
        return ZStack(alignment: .topLeading) {
            ForEach(model.effects) { effect in
                effectBadge(effect, now: now, scheme: scheme)
            }
        }
        .frame(width: Self.baseSize.width, height: Self.baseSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func effectBadge(_ effect: PetEffect, now: Date, scheme: ColorScheme) -> some View {
        let progress = effect.progress(at: now)
        let x = effect.origin.x * Self.baseSize.width
            + effect.drift.width * Self.baseSize.width * CGFloat(progress)
        let y = effect.origin.y * Self.baseSize.height
            + effect.drift.height * Self.baseSize.height * CGFloat(progress)

        let fadeIn = min(1, progress / 0.12)
        let fadeOut = progress > 0.62 ? max(0, (1 - progress) / 0.38) : 1
        let scale = effect.kind.size * effect.scale * CGFloat(0.85 + 0.3 * progress)

        return Image(systemName: effect.kind.symbol)
            .font(.system(size: scale, weight: .semibold))
            .foregroundStyle(tint(for: effect.kind, scheme: scheme))
            .rotationEffect(.degrees(effect.spin * progress))
            .opacity(fadeIn * fadeOut * 0.95)
            .position(x: x, y: y)
    }

    private func tint(for kind: PetEffectKind, scheme: ColorScheme) -> Color {
        switch kind {
        case .zzz: AppTheme.textSecondary(scheme)
        case .heart: Color(red: 0.94, green: 0.36, blue: 0.52)
        case .star, .sparkle, .confetti, .note: AppTheme.gold
        case .sweat: Color(red: 0.32, green: 0.62, blue: 0.95)
        case .question, .exclamation: AppTheme.textPrimary(scheme)
        case .anger: AppTheme.critical
        }
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

    private func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        let p = x - 1
        return 1 + c3 * p * p * p + c1 * p * p
    }
}
