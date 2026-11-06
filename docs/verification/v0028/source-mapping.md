# V0028 source mapping

- Source: `https://github.com/jazzenchen/agent-hud-native-open`
- Commit: `f1ebd1b7d609fe77e5f328974decdb800ddea995`
- License: Apache License 2.0; repository `LICENSE` copied to
  `Resources/Licenses/AgentHUD-Apache-2.0.txt` and
  `docs/verification/v0028/source/AgentHUD-LICENSE.txt`.

## Reused

- `Sources/AgentHUDCore/System/ChildProcess.swift` → `CodexChildProcess.swift` (bounded stdout/stderr, process termination, cancellation cleanup; type renamed).
- `CodexAppServerClient.swift` / `CodexLocator.swift` / `CodexRateLimits.swift` / `ResetCreditsDetails.swift` informed the minimal Valora transport, locator, parser and reset-credit display semantics.

## Deliberately not migrated

Full Agent HUD UI/icons, sessions/transcripts/ledger/SQLite/history, hooks, MCP, login/account identity, `account/read`, email/account fields, reset/use-credit operations, model requests, threads/turns, database or personal data.

## Closed command allowlist

`initialize`, `initialized`, `account/rateLimits/read`.

No `account/read`, thread, turn, login, reset, model request or arbitrary RPC path exists in the production client.

## Adaptations

- Rate-limit map is authoritative when present, including empty map; only the global `codex` bucket contributes 5H/WEEK.
- Window recognition is by `windowDurationMins` 300 / 10080.
- Missing/invalid percentages stay nil; numeric zero is preserved.
- Reset `availableCount` is authoritative; credit details may be absent/fewer and expire dates are sorted, never inferred.
- Provider has one in-flight request, a bounded snapshot, finite 180s refresh/failure backoff, and no history DB.
- UI is newly composed in Valora's Calmon-style popover; no AgentHUD UI/view/icon was copied.
