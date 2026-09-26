import SwiftUI

// Cool stone neutrals with one antique-gold accent.
// Error red is only for save and login failures.
enum Theme {
    static let radius: CGFloat = 12

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.102, green: 0.098, blue: 0.094)
            : Color(red: 0.953, green: 0.957, blue: 0.949)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.145, green: 0.137, blue: 0.122)
            : Color(red: 0.992, green: 0.992, blue: 0.984)
    }

    static func field(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.165, green: 0.157, blue: 0.141)
            : Color(red: 1, green: 1, blue: 1)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.886, green: 0.694, blue: 0.353)
            : Color(red: 0.541, green: 0.353, blue: 0.063)
    }

    static func onAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.102, green: 0.078, blue: 0.031)
            : Color(red: 1.0, green: 0.973, blue: 0.925)
    }

    static func quietFill(_ scheme: ColorScheme) -> Color {
        accent(scheme).opacity(scheme == .dark ? 0.16 : 0.10)
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.949, green: 0.937, blue: 0.910)
            : Color(red: 0.110, green: 0.106, blue: 0.098)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.733, green: 0.710, blue: 0.659)
            : Color(red: 0.369, green: 0.361, blue: 0.341)
    }

    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.278, green: 0.263, blue: 0.235)
            : Color(red: 0.835, green: 0.827, blue: 0.804)
    }

    static func disabledFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.227, green: 0.220, blue: 0.204)
            : Color(red: 0.851, green: 0.839, blue: 0.812)
    }

    static func disabledText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.784, green: 0.761, blue: 0.722)
            : Color(red: 0.247, green: 0.239, blue: 0.224)
    }

    static func error(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.941, green: 0.698, blue: 0.659)
            : Color(red: 0.557, green: 0.184, blue: 0.141)
    }
}
