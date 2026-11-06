# Calendar settings authorization (V0016)

## Scope

This batch implements only the Alcove-style Calendar settings page and the
EventKit full-access authorization state. It does not implement a notch
calendar, menu bar monitor, Codex flow, date grid, event list, notification, or
shortcut. The page has one switch; the basic calendar/month UI is not present in
this candidate and is not claimed.

## Defaults and semantics

- `enableCalendar` is a user preference and defaults to **false**.
- It is only a permission/consent switch for future event display; it is not a
  calendar module total switch and does not by itself read events.
- Existing EventKit authorization does not auto-enable the switch. A user must
  click the switch and complete the current intent.
- Closing the switch does not revoke system authorization or open Settings.
- No event query, save, delete, reminder, contact, or write API is invoked.

## Authorization mapping

`EKEventStore.authorizationStatus(for: .event)` is mapped without collapsing:

| EventKit | App state | Read events |
|---|---|---|
| `.fullAccess` | fullAccess | allowed after user intent |
| `.writeOnly` | writeOnly | **not allowed** |
| `.notDetermined` | notDetermined | needs user intent |
| `.denied` | denied | no |
| `.restricted` | restricted | no |
| unknown | unknown | no |

Request path: user clicks the switch; `EKEventStore.requestFullAccessToEvents`
is invoked only in that intent. `writeOnly` is not accepted as readable.
The EventKit store is created lazily on request; status reads use the public
class method and never fetch personal events. The completion is hop-safe back to
the MainActor. No EventKit object is passed across actors.

- Pending switch state is `@Published`; cancel immediately returns the actual
  switch to off.
- A successful full-access callback completes the same intent once; old callbacks
  are bound to an intent generation and cannot complete a newer intent.
- Denied/restricted opens the Calendar privacy settings; app activation refreshes
  the real status and only a still-valid pending intent may complete.
- Continuous clicks do not start multiple requests.

## Info.plist / entitlement

`scripts/package.py` writes:

```xml
<key>NSCalendarsFullAccessUsageDescription</key>
<string>用于在日历中显示你的日程。</string>
```

The candidate remains non-sandboxed, but it uses **Hardened Runtime**
(`codesign --options runtime`). macOS TCC requires the resource entitlement
`com.apple.security.personal-information.calendars` for EventKit access even
when App Sandbox is off. The earlier assumption that a non-sandboxed app needs
no entitlement was wrong.

`Resources/Valora.entitlements` contains only:

```xml
<key>com.apple.security.personal-information.calendars</key>
<true/>
```

`scripts/package.py` signs the final app with `--options runtime
--entitlements Resources/Valora.entitlements`, verifies the signature, and
parses `codesign -d --entitlements :-` from the signed app. No sandbox,
contacts, reminders, camera, or other resource entitlement is added.

`EventKitCalendarAuthorization` keeps `domain`/`code` from a request error in a
non-sensitive diagnostic; it does not turn an EventKit/configuration failure
into `.denied` or log event content. Real macOS permission prompts and the
denial/restriction path still require device verification.

## Apple references

- https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)
- https://developer.apple.com/documentation/eventkit/ekeventstore/authorizationstatus(for:)
- https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui
