# V0035-R3 trigger evidence scope

Read-only archive searches covered Sources, the available connection-appearance
decompilation and detail-audit evidence. No in-ear/wear-selector or wear
notification path was found.

The mature revival's `BluetoothController` only polls `ARConnectedAudioDevices`
and compares device IDs; its arrival path is a connected-device fresh-ID path,
not a documented in-ear event. This is implementation evidence, not proof that
the original lacks a private wear source.

The user's observed original behavior (on wear: show; remove: brief retention;
reinsert: show again) therefore remains a behavioral target. Valora R3 uses
the active default-output transition as the smallest available observable
proxy, not a claimed in-ear sensor:

- active AirPods baseline: no replay;
- AirPods active -> inactive: no new arrival;
- inactive -> active: one arrival; same active route does not replay;
- raw metadata missing: does not consume a pending AirPods intent;
- same stable id transient missing model: retain per-id display metadata;
- different id: no metadata inheritance.

No automatic play/pause state is used as a wear signal, and no real Bluetooth,
output, media or system permission was operated by this investigation.
