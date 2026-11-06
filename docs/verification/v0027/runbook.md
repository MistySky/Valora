# V0027 native preview / QA commands

Candidate only (user `dist` is not touched):

```sh
/private/tmp/valora-v0027-candidate/Valora.app/Contents/MacOS/Valora --preview-menu-modules
```

This is a separate QA process with the same Valora bundle identity for resource/signing
matching. It does **not** start media, Bluetooth, EventKit, permissions, login items or
production preferences (QA defaults suite). It shows:

- Outline-v7 application item with the existing left/right music menu (rightmost,
  independent and always present);
- system monitor item (`CPU`/`MEM`) with independent left popover and the shared
  version/Settings/Divider/Quit right-click menu;
- calendar item (`M月d日 周X`) with independent left popover and the same basic
  right-click menu. Calendar events are explicitly injected samples.

Left-click each module to open its own popover; clicking it again closes it; opening
the other closes the first. Right-clicking either module does not open a module panel.
The application Outline item is not a module fallback and keeps the existing music menu.

For an isolated native window/status-item capture without UI interaction:

```sh
/private/tmp/valora-v0027-candidate/Valora.app/Contents/MacOS/Valora \
  --verify-menu-modules /tmp/valora-v0027-native
```

The verifier creates real `NSStatusItem`s and real `NSPopover` windows, injects a
fixed monitor snapshot and sample calendar events, then exits. It never queries the
real calendar or reads media. Screenshot files are content-window captures; native
material/backdrop is not claimed as a screen capture.
