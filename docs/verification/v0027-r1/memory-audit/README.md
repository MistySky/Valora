# V0027 supplement: menu-bar lifecycle/memory audit

Command (isolated candidate):

```sh
/private/tmp/valora-v0027-candidate/Valora.app/Contents/MacOS/Valora \
  --audit-menubar-memory docs/verification/v0027/memory-audit
```

The run used fake calendar events and a deterministic fake application reader.
It did **not** query personal EventKit data, read media, request permissions or
touch the user `dist`. The two module popovers and status items were real; the
SystemMonitor CPU/MEM scheduler read only public system counters. The audit is
one process that exits after its own cleanup.

## Raw result

- `memory-audit.json`: 144 timestamped points, duration **454.2 s**.
- Status item identities: one monitor identity and one calendar identity after
  start (cold-baseline nil is excluded); one monitor popover identity.
- Deallocation after stop/nil-out: controller, monitor, calendar and fake reader
  all `true`.
- Calendar event requests: **31 starts / 31 completions** after first open + 30
  cycles; no requests after close. Continuous 3-minute segment kept the same
  event query count (no repeated event read).
- Necessary CPU/MEM sampling continued while panels were closed; application
  list/disk/calendar event work did not. Stale application samples were discarded
  by the existing generation guard.

## Observation, not a threshold conclusion

- First open produced a clear one-time hosting/font/icon warm-up spike
  (physical footprint jumps to ~68–76 MiB). After close + settle it fell back to
  ~46 MiB.
- During the 30-cycle sequence, immediate post-close physical values can remain
  high (autorelease/appearance caches), then settle around ~40 MiB after a longer
  idle. RSS remained around 85 MiB rather than stepping upward.
- Every 5 s sample in both continuous 180 s segments recorded the corresponding popover
  `isShown=true` (36/36 each); no false-focus run is counted as continuous.
- In the two continuous 180 s segments after 30 s of warm-up, physical footprint
  was effectively flat (the analysis records the measured slope; it is not used
  as an arbitrary MB pass threshold). No sustained staircase was observed.
- The raw values include the intentional CPU/MEM scheduler continuing after panel
  close. Those samples are not classified as a panel leak.

## Cache bound fix

`AppMemoryReader.iconCache` now has a hard limit of 128 entries. Reaching the
limit clears the cache before inserting a new root icon, and panel close/stop
still calls `trimCache`/`purge`. `SystemMonitorTests.testApplicationIconCacheIsBoundedAndTrimClearsIt`
covers the bound and trim. The audit's fake reader reports zero cache entries by
design; the real bounded cache is covered separately by that test.

## Limitations

The audit is a bounded local run, not a claim about every macOS appearance,
font cache, display, or future OS build. It does not prove that RSS must return
to the exact cold value. Native screen material was not captured; popover content
windows were the verified surfaces.
