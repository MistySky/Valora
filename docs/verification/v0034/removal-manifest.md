# V0034 removal manifest

Removed from production/package:

- Download: `Sources/Valora/Download*`, `DownloadEngineAdapter.swift`,
  `DownloadMenu*`, `DownloadRingIcon.swift`, `DownloadPopoverView.swift`,
  `DownloadRowView.swift`, `DownloadSegmentBar.swift`, `DownloadNewView.swift`,
  `DownloadConflictSheet.swift`, `DownloadDeleteConfirmation.swift`.
- Codex/AI usage: `Sources/Valora/Codex*`, `CodexUsage*`,
  `CodexRefreshScheduling.swift`, `CodexUsageLiveProbe.swift`.
- Composite/combined: `Sources/Valora/Composite*`,
  `MonitorCodexCombinedView.swift`.
- Chrome bridge: `Sources/ChromeBridgeKit`, `Sources/ValoraNativeHost`,
  `Sources/Valora/ChromeBridgeController.swift`,
  `Sources/Valora/ChromeBridgeSettings.swift`, `Resources/ChromeExtension`.
- Packaging/deps: `Vendor/Convoy`, `Package.resolved`,
  `scripts/verify_convoy_vendor.py`, NativeHost/Chrome/Convoy fields and copy
  steps in `scripts/build.sh`/`scripts/package.py`, `Package.swift` external
  dependency and NativeHost/ChromeBridgeKit targets.
- Licenses for removed features: `Resources/Licenses` (Convoy/AgentHUD/
  StatusTrio/ChromeBridge/Sparkle/swift-log files); no longer bundled.
- Dedicated tests: BrowserExtension tests, ChromeBridge/Codex/Download/
  Composite tests and their fixtures. Mixed calendar/monitor/settings tests
  were retained and updated, not deleted.

Retained:

- `MenuBarModuleController`, `MonitoringView`, `CalmonCalendarView`,
  `SystemMonitor`, calendar EventKit/authorization/holiday/event code.
- Music/notch/lyrics/device/lock screen/software Outline-v7/app icon/settings
  surface and MediaRemote adapter + its license/provenance.
- Historical docs/pi-tasks/reports/verification and user icon resources.

Production now starts two independent Calmon status items (monitor and
calendar), no manager/socket/extension/host initialization. No real Chrome
registration or user download/cache files were touched.
