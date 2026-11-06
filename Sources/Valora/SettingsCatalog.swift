import SwiftUI

// Settings pages requested for this candidate. Names/order follow
// reference-ui/settings-ax.json (Alcove 1.7.9); the archived page inventory is
// not migrated.
enum SettingsPage: String, CaseIterable, Identifiable {
    // Stored identity/raw values stay stable; the sidebar groups are the
    // single source of presentation order.
    case general = "General"
    case nowPlaying = "Now Playing"
    case lockScreen = "Lock Screen"
    case connectivity = "Connectivity"
    case systemMonitor = "System Monitor"
    case codexUsage = "Codex Usage"
    case calendar = "Calendar"
    case about = "About"
    var id: String { rawValue }
    var displayTitle: String { SettingsText.localized(rawValue) }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .nowPlaying: return "play.fill"
        case .lockScreen: return "lock.fill"
        case .connectivity: return "headphones"
        case .systemMonitor: return "chart.bar.xaxis"
        case .codexUsage: return "sparkles"
        case .calendar: return "calendar"
        case .about: return "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: return .gray
        case .nowPlaying, .calendar: return Color(red: 0.98, green: 0.22, blue: 0.40)
        case .lockScreen: return Color(white: 0.16)
        case .connectivity: return Color(red: 0, green: 0.75, blue: 0.54)
        case .systemMonitor: return Color(red: 0.25, green: 0.55, blue: 1)
        case .codexUsage: return Color(white: 0.28)
        case .about: return .gray
        }
    }
    var scrolls: Bool { self != .connectivity }
    /// Flat order is derived from the sidebar groups, not duplicated here.
    static var allCases: [SettingsPage] { SettingsSidebar.orderedPages }
}

/// A sidebar group title is presentation-only and never a clickable parent
/// page. Every group heading, including Valora, uses the archived sectionTitle
/// spacing; no extra standalone topSpacing is layered on About.
struct SettingsSidebarGroup: Identifiable {
    let title: String?
    let pages: [SettingsPage]
    var id: String { title ?? pages.map(\.rawValue).joined(separator: "|") }
}

enum SettingsSidebar {
    static let groups: [SettingsSidebarGroup] = [
        SettingsSidebarGroup(title: nil, pages: [.general]),
        SettingsSidebarGroup(title: "刘海屏", pages: [.nowPlaying, .lockScreen, .connectivity]),
        SettingsSidebarGroup(title: "菜单栏", pages: [.calendar, .systemMonitor, .codexUsage]),
        SettingsSidebarGroup(title: "Valora", pages: [.about])
    ]
    static var orderedPages: [SettingsPage] { groups.flatMap(\.pages) }
}

/// Shared native-layout constants. The content scrolls under the 53 pt title
/// mask; starting the first card 13 pt below the title keeps a visible gap
/// without changing the existing window or scroll container.
enum SettingsLayout {
    static let headerHeight: CGFloat = 53
    static let contentTopPadding: CGFloat = 66
    static let titleContentGap: CGFloat = contentTopPadding - headerHeight
}


/// UI preferences are persisted in the same archived dictionary. A visible
/// option whose backend is not part of this slice is disabled in SettingsView
/// and listed in the delivery report instead of pretending to work.
@MainActor
final class SettingsDraft: ObservableObject {
    let defaults: UserDefaults
    @Published private var values: [String: Any]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
    }
    func value<T>(_ key: String, _ fallback: T) -> T { values[key] as? T ?? fallback }
    var snapshot: [String: Any] { values }
    func binding<T>(_ key: String, _ fallback: T) -> Binding<T> {
        Binding(get: { self.value(key, fallback) }, set: { self.values[key] = $0; self.defaults.set(self.values, forKey: "referenceSettingsUI"); NotificationCenter.default.post(name:Notification.Name("ValoraSettingsDraftChanged"),object:self.defaults) })
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .general
    @Published var revealBottom = false
}
