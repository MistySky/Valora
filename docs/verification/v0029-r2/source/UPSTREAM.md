# Upstream and local compatibility

- Upstream: https://github.com/TheDynamicPunk/Convoy
- Fixed revision: `007a20973923fcd69c42a3571fc299f5b8582dc6`
- License: GPL-3.0 (upstream LICENSE retained; see THIRD_PARTY_NOTICES.md).
- Local package: only `Sources/DownloadEngine/**` is included. The Convoy app,
  Sparkle, NativeMessagingHost, IPCKit, extensions, resources and app UI are not
  included and are not imported.
- Local modifications: `V0029-R2-COMPAT.patch`; see `patches/` and
  `SOURCE-MANIFEST.json`. The patch adds explicit environment/manager/lock
  ownership, path propagation and non-owner rejection; download algorithms,
  status names and user interactions are retained.

Upgrade check: `scripts/verify_convoy_vendor.py` validates the upstream
revision/hash manifest and refuses a silently replaced tree. The local package is
not a GitHub fork and is not pushed anywhere.
