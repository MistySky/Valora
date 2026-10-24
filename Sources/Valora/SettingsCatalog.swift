import SwiftUI

// Only the two pages requested for this candidate. Names/order follow
// reference-ui/settings-ax.json (Alcove 1.7.9); the archived page inventory is
// not migrated.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case connectivity = "Connectivity"
    case nowPlaying = "Now Playing"
    var id: String { rawValue }
    var displayTitle: String { SettingsText.localized(rawValue) }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .connectivity: return "headphones"
        case .nowPlaying: return "play.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: return .gray
        case .connectivity: return Color(red: 0, green: 0.75, blue: 0.54)
        case .nowPlaying: return Color(red: 0.98, green: 0.22, blue: 0.40)
        }
    }
    var scrolls: Bool { self != .connectivity }
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
