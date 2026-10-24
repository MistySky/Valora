import SwiftUI

/// Static settings surfaces recovered from the original light screenshot:
/// window/sidebar #EAEAEA, content #F5F6F6, cards #F2F3F3, selected row #DADADA.
/// Dark keeps the existing adaptive surfaces.
enum SettingsPalette {
    static let accent = Color(red: 43/255, green: 205/255, blue: 185/255)

    static func windowBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(red: 234/255, green: 234/255, blue: 234/255)
    }
    static func contentBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .underPageBackgroundColor) : Color(red: 245/255, green: 246/255, blue: 246/255)
    }
    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .controlBackgroundColor).opacity(0.50) : Color(red: 242/255, green: 243/255, blue: 243/255)
    }
    static func selectedRow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.primary.opacity(0.10) : Color(red: 218/255, green: 218/255, blue: 218/255)
    }
}
