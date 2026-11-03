# V0035 source/runtime evidence

## Selector ABI

A read-only Objective-C runtime query (no device enumeration or read) shows:

- batteryPercentLeft/Right/Single/Case/Combined: return encoding `C`
  (unsigned char)
- colorID: `C`
- isConnected: `B`
- name/addressString: `@`

The previous `connectivityScalar` used an `unsigned int` function pointer for
all of these. That is not the declared ABI. The bridge now checks
`method_copyReturnType` for exactly `C`, reads `unsigned char`, and returns
`-1` for a missing/unsupported return type. No current device values were read
by this external check; no TCC prompt was intentionally triggered.

The actual current AirPods3 battery raw fields were not obtained in this
session because an external helper has a different TCC identity. The running
user candidate was not injected, replaced, or restarted. The real values/ring
remain a user-candidate check.

## System native notifications

Archive source uses its own `connectionToast` and NotchView notification
geometry. No `NSUserNotification`/`UNUserNotification` suppression or system
notification interception exists in the archived source. This is evidence that
the archived app added a contextual toast, but not proof that it suppresses
macOS's own AirPods notification. No system defaults/TCC/AX changes were made.
