# Agent HUD reference points (read-only)

Upstream: `/private/tmp/agent-hud-v0028`, commit `f1ebd1b7d609fe77e5f328974decdb800ddea995`.
Only design/scheduling ideas were studied; no HUD account/session/token/auth-file reader or UI was copied.

- `Sources/AgentHUDCore/Providers/Codex/CodexRateLimits.swift:11` — official window exposes `remainingPct` derived from protocol `usedPercent`.
- `Sources/AgentHUDCore/Store/UsageStore.swift:8-11` — observable report, `lastError`, `isRefreshing`; the previous report is not replaced by a loading placeholder.
- `Sources/AgentHUDCore/Store/UsageCollector.swift:44-58,95-114` — one serial pass loop with a scheduled wake timer and cancellation; reads happen without a panel click.
- `Sources/AgentHUDCore/Providers/Codex/CodexUsageProvider.swift:100-128` — successful `readings` and `failures` are stored separately, so a later failure does not discard the last successful reading.

Valora keeps only an in-memory `CodexUsageSnapshot`; it does not copy HUD history, credentials, identity caches, transcripts or sessions.
