# V0032 source inspection notes

## Monitor first-expand scrollbar path

Source only; no real app/popover was opened for this round.

- `MenuBarModuleController.showCombinedPanel` calls `appSearch.beginPresentation()`,
  builds `MonitorCodexCombinedView`, and only calls `monitor.setPanelVisible(true)`
  after `present`.
- The first hosting layout therefore sees `SystemMonitor.applicationState == .idle`.
  `MonitoringContentView` renders the application loading row at 36 pt.
- `SystemMonitor.setPanelVisible(true)` sets `.loading` and starts an immediate
  tick; application rows (up to the 8-row collapsed list) arrive asynchronously.
- `NSHostingController` is configured with `.preferredContentSize`; the outer
  `ScrollView` plus the application card's expanded/searching inner `ScrollView`
  can produce a provisional indicator while the first preferred-size/layout
  pass settles.
- Mitigation in this task:
  - pre-prime the hosting controller's preferred size after one
    `layoutSubtreeIfNeeded()` before showing, only when the measured height is
    less than `maxHeight`;
  - suppress the outer indicator only while the first monitor/Codex snapshot is
    idle/loading, then return to `.automatic`;
  - do not remove scrolling, fix a permanent height, clip content, or remove
    the application list's original inner scrolling.
- Visual confirmation of the transient is still pending a user single view; this
  note does not claim the flash was reproduced or visually eliminated.

## Material

`DownloadPopoverView` had `.background(.regularMaterial)` in addition to the
native `NSPopover` material used by calendar and the shared monitor/Codex panel.
That extra layer was removed; no self-drawn frame, opacity reduction or separate
color palette was added.

## Settings source

- General "显示菜单栏图标" is now a plain `SettingsToggleRow` (text + switch).
- Downloads page contains only the download switch in its `SettingsCard`.
- Chrome card defaults to two 41 pt rows; install steps and extension-directory
  buttons appear only after the explicit "安装…" action.
