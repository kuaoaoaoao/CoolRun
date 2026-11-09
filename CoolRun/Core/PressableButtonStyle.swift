import SwiftUI

/// 按下即缩、松开弹回。
///
/// 菜单栏面板只有 380pt 宽，按钮之间挨得紧，用户点下去如果毫无反馈，
/// 第一反应是「是不是没点到」然后连点两下——这比慢一点更让人烦。
/// 这里统一给按钮一个 0.12s 的按下反馈，和 macOS 原生控件的手感对齐。
///
/// `reduceMotion` 由调用方从环境里取：ButtonStyle 不是 View，
/// 自己声明 `@Environment` 拿不到注入值。
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    var pressedOpacity: Double = 0.72
    var reduceMotion: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

/// 列表行专用：按下时整行淡淡高亮，不做缩放——文字跟着缩放会糊。
struct RowHighlightButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 7
    var tint: Color = AppTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.13 : 0))
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    /// 把命中区域撑到至少 `width × height`，视觉尺寸保持不变。
    /// 图标本身只有 11pt，直接点命中率太低。
    func hitTarget(width: CGFloat = 30, height: CGFloat = 30) -> some View {
        frame(minWidth: width, minHeight: height)
            .contentShape(Rectangle())
    }

    /// 给整行可点区域加圆角命中形状，避免只有文字能点、空白处点不动。
    func rowHitTarget(cornerRadius: CGFloat = 8) -> some View {
        contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
