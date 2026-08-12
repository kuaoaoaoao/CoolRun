import Foundation

enum MenuBarCompositionFormatter {
    static func activeMode(
        style: MenuBarCompositionStyle,
        primary: MenuBarDisplayMode,
        secondary: MenuBarDisplayMode,
        rotationUsesSecondary: Bool
    ) -> MenuBarDisplayMode {
        guard style == .rotation,
              rotationUsesSecondary,
              primary != secondary else {
            return primary
        }
        return secondary
    }

    static func render(
        style: MenuBarCompositionStyle,
        primary: MenuBarDisplayMode,
        secondary: MenuBarDisplayMode,
        rotationUsesSecondary: Bool,
        value: (MenuBarDisplayMode, Bool) -> String
    ) -> String {
        switch style {
        case .single:
            return value(primary, false)
        case .pair:
            guard primary != secondary else { return value(primary, false) }
            return value(primary, true) + " · " + value(secondary, true)
        case .rotation:
            return value(
                activeMode(
                    style: style,
                    primary: primary,
                    secondary: secondary,
                    rotationUsesSecondary: rotationUsesSecondary
                ),
                false
            )
        }
    }
}
