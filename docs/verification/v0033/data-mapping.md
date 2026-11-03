# V0033 mapping

- Date: local `Calendar.current` day 1...31, ASCII two-character text; `01`...`09`.
- CPU arc: `SystemMonitor.snapshot.cpu.usage`; memory arc: `.memory.usedPercent`.
  Normal green, >80 red, unknown/off gray. GPU value is never called pressure.
- CPU/memory sparkline: controller keeps at most 40 existing monitor snapshots;
  no additional sampler. Empty history draws no invented line.
- Quota dots: first two dots share five-hour `remainingPercent`, next two share
  week `remainingPercent`; each dot is 50%, fill fraction is clamped. >25 green,
  1...25 yellow, 0/unknown gray.
- Download arrow priority: failed > paused > active > completed (within 2 s) >
  idle. Idle gray, active blue, completed green, paused yellow, failed red.
  Color change never changes date or arcs.
- Modules: disabled monitor/calendar/Codex/download keep their fixed positions
  but render gray and hide their panel content; all off removes the composite
  item. Underlying monitor/Codex/calendar/download lifecycles stop on off.
- Memory/disk rows: system monitor used and unused capacity; system volume disk;
  tabular values; hidden when monitor off.
- Calendar: existing `CalmonCalendarView` content, with `embedsScroll: false` in
  the unified outer scroller. Existing month/lunar/holiday/authorization/event
  logic unchanged; calendar off hides it and does not start EventKit reads.
- Download summary: first stable model item (creation-time order), real progress,
  bytes/speed, pause/resume; click opens side list. Side list reuses
  `DownloadPopoverView` and Convoy actions/confirmation semantics.
- Side geometry: right of 400 pt main first, then left, then clamp inside the
  screen visible frame if neither side is wide enough; height follows main
  window height and is updated on main resize.
