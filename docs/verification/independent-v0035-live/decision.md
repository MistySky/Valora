# V0035 real-device review after native callback fix

## Accepted evidence
- Current live AirPods3 read within Valora: left67, right77, single0, derived battery67, activeAirPods1/modelGeneration2. Data sanitization excludes name/MAC/other devices. One sample obtained, not claimed3; max3/10second budget uses existing normal reads only. This directly reproduces the historical inapplicable single0 field and proves current aggregation no longer masks valid earbuds with that zero. It does not claim independent system-UI battery comparison or actual low-battery measurement.
- Actual prior candidate crashed twice at16:17:16 and16:20:51 on com.apple.bluetooth.iobluetooth.coordinatorQueue in @objc ConnectivitySystemEvents.bluetoothConnected(_:device:) / Swift actor assertion. Real crash superseded prior fake-only acceptance.
- Codex directly corrected only this native selector to nonisolated; normalized address and notification identity copied on callback queue, Task@MainActor then validates registration identity and delivers. No native device/notification object crosses actors, late old registration dropped.
- Added native-entry regression uses actual Objective-C selector invoked from background with inert NSObject stubs, no actual Bluetooth. Passed1case. Existing29 device/media fake tests passed again. No popup automation/performance loops.
- Release build and signed callback-fixed candidate passed. It successfully launched with connected headphones; verified running approximately9minutes, newest Valora crash remained16:20:51 (before this build). Not a performance stress test; these are one-shot process/crash-time checks.
- Current candidate /private/tmp/valora-v0035-callback-fixed-candidate/Valora.app. Binary SHA256 c29a2e77ee5396fb7f76e130ce0ffeafd4e170a8513be56d8bf1783cb3ff66f4. Current runtime updated under user authorization for the test; dist untouched. User granted Bluetooth UI themselves. No media command/volume/seek/output/device connection was operated by Codex; output selected by user.

## Boundaries
Normal AirPods3 battery reading/aggregation and native callback startup are accepted for this live device. Not a blanket all-model/full-feature pass: low battery/haptic or sound edge, other devices/Pro3, physical multiple displays, repeated real rapid reconnect and subjective music-control responsiveness are not physically certified. Existing isolated event/coalescing/late-result/media callback regressions are the evidence for those logic paths, not human experience. System native AirPods notification suppression is not implemented or claimed.

An explicit Info.plist flag enables sanitized diagnostics only in the current acceptance bundle; ordinary package has no such key and cannot write them. Budget now begins at first active AirPods so waiting for authorization/output does not consume it. No timer/automation was created.

Earphones-first order retained. Next authorized investigation is lock screen after this device fix; no lock-screen production work was started in this review. Do not resurrect removed downloads/Codex or pre-fix callback code.
