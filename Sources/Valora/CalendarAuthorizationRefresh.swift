import Combine
import Foundation

/// Shared production wiring for calendar authorization refreshes.
///
/// `@Published` emits from `willSet`; reading `permissions.calendar` inside the
/// sink is therefore the *old* status. The production subscription and the
/// focused regression test both use this entry point. It defers exactly one
/// main-queue turn, then asks the calendar model to re-check its existing
/// panel/gate/visibility conditions against the committed status. It does not
/// request authorization, query EventKit itself, or bypass `CalmonCalendarModel`.
@MainActor
enum CalendarAuthorizationRefresh {
    static func subscribe(_ permissions: AppPermissions,
                          onRefresh: @escaping @MainActor () -> Void) -> AnyCancellable {
        permissions.$calendar.sink { _ in
            // The sink runs in willSet. Enqueue after this publication commits.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { onRefresh() }
            }
        }
    }
}
