import AppKit
import EventKit
import Foundation

enum CalendarAccess: Equatable, Sendable {
    case fullAccess
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case unknown

    var canReadEvents: Bool { self == .fullAccess }
}

struct CalendarAuthorizationFailure: Equatable, Sendable {
    let domain: String
    let code: Int
}

@MainActor
protocol CalendarAuthorizationProviding: AnyObject {
    var status: CalendarAccess { get }
    func requestFullAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void)
    func requestFullAccessWithFailure(
        _ completion: @escaping @MainActor (CalendarAccess, CalendarAuthorizationFailure?) -> Void
    )
}

extension CalendarAuthorizationProviding {
    /// Failure-aware entry point with a default for existing test doubles.
    func requestFullAccessWithFailure(
        _ completion: @escaping @MainActor (CalendarAccess, CalendarAuthorizationFailure?) -> Void
    ) {
        requestFullAccess { completion($0, nil) }
    }
}

/// EventKit public authorization adapter. EventKit's store is created only on
/// the explicit request path; status reads use the class method and never fetch
/// events. No write/event query is performed.
@MainActor
final class EventKitCalendarAuthorization: CalendarAuthorizationProviding {
    private var store: EKEventStore?

    var status: CalendarAccess {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    func requestFullAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        requestFullAccessWithFailure { status, _ in completion(status) }
    }

    func requestFullAccessWithFailure(
        _ completion: @escaping @MainActor (CalendarAccess, CalendarAuthorizationFailure?) -> Void
    ) {
        let store = self.store ?? EKEventStore()
        self.store = store
        store.requestFullAccessToEvents { _, error in
            // EKEventStore's completion is not MainActor-isolated; the public
            // class status method can be read without touching event data.
            let status = Self.map(EKEventStore.authorizationStatus(for: .event))
            let nsError = error as NSError?
            let failure = nsError.map {
                CalendarAuthorizationFailure(domain: $0.domain, code: $0.code)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(status, failure) }
            }
        }
    }

    nonisolated static func map(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: return .fullAccess
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .writeOnly
        @unknown default: return .unknown
        }
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
