# V0035 independent review: NOT ACCEPTED

26 existing targeted device/media tests passed. Three independently added cases failed (five assertions), total29 cases. No live media/device control, windows, --verify entry points or performance pressure tests were used.

1. testConnectDuringReadSchedulesFreshReadWithoutWaitingForPoll: held fake source second read is pending, inject real onConnect closure through reflected event object, release read. Expected one coalesced fresh read=3, actual2; event refresh dropped at one-in-flight gate.
2. testFailedOldToggleCannotOverwriteNewTrackSnapshot: toggle old playing track, receive new paused authoritative snapshot, fail old completion. New track incorrectly restored to playing and stale error injected.
3. testFailedToggleAfterStopCannotMutateModel: toggle then stop, fail old completion. Stopped model modified from false totrue and error set.

Tests: Tests/ValoraTests/IndependentDeviceMediaReviewTests.swift. Fixes must preserve assertions; no fresh UI/hardware permission is needed to reproduce.

Signature of pi candidate /private/tmp/valora-v0035-device-response-candidate/Valora.app passed deep/strict. No additional release build is warranted while functional failures remain.

Battery method encoding C/type-safe invocation and earbud-priority selection are source improvements, not proof of actual AirPods3 battery correctness; report explicitly lacked live raw values, so real battery and notification reliability remain unaccepted. Do not claim the old ABI mismatch alone caused the user's incorrect battery.

Remaining scope: repair event coalescing/stale read lifecycle and media pending command lifecycle/authoritative snapshot reconciliation. No redesign, actual account reads, real play/seek/volume, device connection, notification suppression/system changes, popup loops or performance tests. Keep V0034 removed features absent and current user runtime untouched.
