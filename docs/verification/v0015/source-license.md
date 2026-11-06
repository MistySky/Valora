# V0015 connectivity payload provenance

The AirPods movie files and low-battery sound were copied, one narrow payload
at a time, from the user-authorized local Alcove archive:

`/Users/wangqing/code/alcove-revival-archive/Sources/AlcoveRevival/Resources/`

The archive describes itself as a local Swift reconstruction of the user's
Alcove 1.7.9 ARM64 distribution. No separate per-asset open-source license was
found in the archive. The assets are retained only for this private local
migration and are not installed, published, or redistributed by this task. They
are not claimed to be MIT/GPL-licensed separately.

- `AirPods/*.mp4` (15 files): decorative connection movies.
- `Sounds/low-battery.caf`: low-battery alert sound.

Exact SHA-256 values and byte sizes are in `assets.json`. The source archive was
read only; no archive file was modified. Code types were adapted from the
archive paths named in `docs/reports/v0015.md`; the original media-remote adapter,
brand icon, and Outline-v7 menu-bar resources are untouched.
