# Real callback crash: independent live verification failed

Two Valora ips reports (2026-10-27 16:17:16 and16:20:51) show SIGTRAP/EXC_BREAKPOINT on com.apple.bluetooth.iobluetooth.coordinatorQueue. Top frames: dispatch_assert_queue, swift_task_isCurrentExecutorWithFlagsImpl, @objc ConnectivitySystemEvents.bluetoothConnected(_:device:). The @MainActor NSObject selector was incorrectly called directly by IOBluetooth on a background queue. Fake onConnect tests did not exercise the native selector thunk.

Direct minimal correction: make only the native selector nonisolated, copy normalized address and notification ObjectIdentifier on its callback queue, then Task @MainActor to validate registration identity and process events. No IOBluetooth object is sent across actors; old queued notification identity is rejected after stop/re-registration. Sampling window now begins at first active-AirPods record, not a built-in speaker result.

No raw crash log, personal names or addresses copied. Prior29 fake tests and signature remain valid only for their scope, NOT evidence the live callback is safe. Need a fresh candidate launch with current connected headphones to exercise this native entry.
