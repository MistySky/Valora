import Foundation
import ServiceManagement

/// 1.7.9 links ServiceManagement and references SMAppService. The app has no
/// LoginItems helper bundle, so the main-app registration path is the match.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
