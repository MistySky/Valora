# V0033 reference read

Repository: https://github.com/lingyired/status-trio
Commit: 57828a41960eccae5b62d0f66e90fca9b74ad8c1

Read-only source files used for design organization:

- Sources/StatusTrioCore/UI/StatusBarController.swift
- Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift
- Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift
- Sources/StatusTrioCore/Presentation/Icon/IconPresentationViewModel.swift

Only the single-item organization, fixed drawing geometry and measured
status-item raster approach informed this task. No status-trio WiFi,
Bluetooth, battery, volume, update or helper code or bitmap artwork was used.
The Valora composite glyph is drawn by Swift/AppKit in
Sources/Valora/CompositeStatusIcon.swift.

User reference image:
`/var/folders/v4/p69cfn4n5tz_4084mv6516fc0000gn/T/codex-clipboard-93bd84b8-f6c7-4ca1-81d4-1d8decb52474.png`
It was used for the gauge/download/Codex information hierarchy; the actual
Valora panel uses Calmon's existing type, card fill, native popover material,
radii and spacing.
