import SwiftUI
import AppKit

// MARK: - 主题

enum AppTheme {
    // 交互色与状态色分离，避免“选中”和“健康”语义混用。
    static let accent = Color.accentColor
    static let gold = Color(red: 0.86, green: 0.58, blue: 0.18)
    static let healthy = Color(red: 0.2, green: 0.78, blue: 0.4)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.15)
    static let critical = Color(red: 0.95, green: 0.3, blue: 0.3)

    // MARK: - 行情涨跌色

    /// 中国市场惯例：涨红、跌绿。
    ///
    /// 这套颜色和 `healthy`/`critical`（系统健康度，绿=好、红=坏）**语义相反**，
    /// 所以必须单独定义，不能复用。否则「金价上涨」会被画成绿色，中文用户第一眼就会读反，
    /// 这是行情类界面最忌讳的错误。
    nonisolated static let marketUp = Color(red: 0.95, green: 0.32, blue: 0.32)
    nonisolated static let marketDown = Color(red: 0.18, green: 0.76, blue: 0.42)
    /// 平盘用中性灰，不要硬塞一个方向色，否则「没涨没跌」看起来像有结论。
    nonisolated static let marketFlat = Color(red: 0.55, green: 0.56, blue: 0.60)

    /// 按涨跌数值取色：正涨红、负跌绿、零平盘灰。
    nonisolated static func marketColor(for change: Double) -> Color {
        if change > 0 { return marketUp }
        if change < 0 { return marketDown }
        return marketFlat
    }

    /// 按方向取色，供 `.up` / `.down` / `.bullish` / `.bearish` 这类枚举复用。
    nonisolated static func marketColor(isUp: Bool) -> Color {
        isUp ? marketUp : marketDown
    }

    static func healthColor(for usage: Double) -> Color {
        switch usage {
        case ..<0.6: return healthy
        case ..<0.85: return warning
        default: return critical
        }
    }

    static func temperatureColor(for celsius: Double) -> Color {
        switch celsius {
        case ..<80: return healthy
        case ..<95: return warning
        default: return critical
        }
    }

    // 根据 colorScheme 返回对应颜色
    static func icon(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7)
    }

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color.black.opacity(0.9)
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }

    static func progressBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.24)
    }

    static func chromeSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.62)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.58)
    }

    static func elevatedSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.78)
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.075)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.20) : Color.black.opacity(0.065)
    }
}

struct AppCardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let showsShadow: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.surface(colorScheme))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
            }
            .shadow(
                color: showsShadow ? AppTheme.shadow(colorScheme) : .clear,
                radius: showsShadow ? 8 : 0,
                y: showsShadow ? 3 : 0
            )
    }
}

extension View {
    func appCardSurface(cornerRadius: CGFloat = 12, showsShadow: Bool = true) -> some View {
        modifier(AppCardSurface(cornerRadius: cornerRadius, showsShadow: showsShadow))
    }
}
