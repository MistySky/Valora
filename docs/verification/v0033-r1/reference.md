# V0033-R1 reference

Repository: https://github.com/lingyired/status-trio
Commit: 57828a41960eccae5b62d0f66e90fca9b74ad8c1

Read directly:

- status-menubar.svg
- Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift
- Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift
- Sources/StatusTrioCore/UI/StatusBarController.swift

The single-ring geometry in `CompositeStatusIcon.swift` is adapted from the
SVG/geometry source: canvas 120, center (59.5, 61.487), radius 51.5, start
148.690°, sweep 242.620°, stroke 8, four footer dot centers (33,104.2),
(50.5,111.2), (68.5,111.7), (86,105.8), dot radius 5.5, and 32 canvas-unit
date text. It is rendered at a 22 pt menu-bar square with 1x/2x/3x reps.
StatusTrio is Apache-2.0; its license and notice are bundled under
Resources/Licenses. No status-trio application, WiFi/Bluetooth/battery/volume
service, helper, or bitmap artwork was copied.
