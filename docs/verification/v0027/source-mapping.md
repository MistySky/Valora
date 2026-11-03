# Calmon → Valora source mapping (V0027)

- Repository: `https://github.com/MistySky/Calmon`
- Fixed commit: `72235116e1420fa081e8f694991a32809f81498d`
- Commit subject: `Fix aggregated row icons and release popover view trees on close; release 2.0`
- License: **no LICENSE/COPYING file exists at this commit**. No MIT or other license is invented. The user explicitly authorized migrating this own-repository source. File-level source comments and SolarTerms metadata are retained.

## Migrated files

| Calmon source | Valora destination | Minimum adaptation |
|---|---|---|
| `CalMon/App/MenuBarController.swift` | `Sources/Valora/MenuBarModuleController.swift` | Independent status items/popovers, left/right routing, shared basic menu; removed hotkey panel/settings/debug hooks. |
| `CalMon/App/UIStyle.swift` | `Sources/Valora/CalmonMenuBarStyle.swift` | Verbatim constants; `NSFont` statics made MainActor computed for Swift 6. |
| `CalMon/App/InsetTextFieldCell.swift` | `Sources/Valora/InsetTextFieldCell.swift` | Verbatim search-field support. |
| `CalMon/Calendar/CalendarView.swift` | `Sources/Valora/CalmonCalendarView.swift` | Calmon layout/material; authorized system-event rows added; hotkey panel exits not migrated. |
| `CalMon/Calendar/CalendarComponents.swift` | `Sources/Valora/MenuBarCalendarComponents.swift` | Popover metrics/day cells retained; panel-scale path removed. |
| `CalMon/Calendar/CalendarModel.swift` | `Sources/Valora/CalmonCalendarModel.swift` | Injected clock/timezone/event provider; fixed display defaults; panel-visible event gate and one-in-flight latest-request lifecycle. |
| `CalMon/Calendar/HolidayProvider.swift` | `Sources/Valora/CalmonHolidayProvider.swift` | Solar-term/lunar data retained; Calmon EventKit auto-discovery/authorization/range fetch removed. |
| `CalMon/Monitoring/SystemMonitor.swift` | `Sources/Valora/SystemMonitor.swift` | Public metrics/lifecycle retained; QA snapshot injection and explicit sleep/wake lifecycle. |
| `CalMon/Monitoring/AppMemoryReader.swift` | `Sources/Valora/AppMemoryReader.swift` | Public libproc/NSWorkspace reads retained. |
| `CalMon/Monitoring/MonitoringView.swift` | `Sources/Valora/MonitoringView.swift` | Calmon native popover UI; injected-sample footer only. |
| `CalMon/Resources/SolarTerms/*.json` | `Sources/Valora/Resources/SolarTerms/*.json` | Versioned solar-term JSON copied unchanged and packaged as a plain resource directory. |

## Deliberately not migrated

- `GlobalHotKeyController`, `CalendarPanelController`, `CalendarPanelView`, large hot-key panel and panel scaling.
- Calmon `Preferences`, app settings window, login-item management and app identity.
- Calmon holiday-calendar source discovery/automatic EventKit authorization. Valora retains `CalendarAuthorization`/`AppPermissions`/the Alcove switch and only reads after explicit panel visibility + consent + fullAccess.
- Calmon app icon, app bundle, test history and any unrelated personal data.

## Valora-specific integration

- `CalendarEvents.swift` provides a read-only EventKit selected-day adapter and a clearly-labelled isolated sample provider.
- `MenuBarModuleController` owns only monitor/calendar status items and native popovers. AppDelegate owns the always-present Outline-v7 application item and its existing music menu.
- Calendar status date and monitor CPU/MEM use Calmon's exact fonts/metrics. No single long panel, no three-region unified item, no AI/download status item.
