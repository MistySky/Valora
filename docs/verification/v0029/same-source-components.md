# Convoy same-source component map

Fixed revision: `007a20973923fcd69c42a3571fc299f5b8582dc6`.

| Component | Paths at revision | Status |
|---|---|---|
| DownloadEngine | `Sources/DownloadEngine/**` | SPM dependency, only product linked |
| Convoy app | `Sources/Convoy/**` | not imported or launched |
| NativeMessagingHost | `Sources/NativeMessagingHost/**`, `Sources/IPCKit/**` | protocol inspected only; not installed/staged |
| Chromium extension | `Extensions/Chromium/Background`, `ContentScripts`, `Popup`, `manifest.json` | not installed |
| Firefox extension | `Extensions/Firefox/Background`, `manifest.json`, `README.md` | not installed |
| Sparkle | package-level dependency `2.10.1` | resolved, **not linked** into Valora |
| swift-log | `DownloadEngine` dependency `1.16.2` | statically linked (no dylib) |

Host protocol observed read-only: `NativeMessagingHost` uses a 4-byte
little-endian length prefix + UTF-8 JSON, socket IPC peer verification, and
Convoy URL-scheme activation. No host manifest, extension, browser profile or
IPC socket was written or installed.

Future engine/extension/host changes must update this same revision and this map
together; do not mix independently versioned extension/host sources.
