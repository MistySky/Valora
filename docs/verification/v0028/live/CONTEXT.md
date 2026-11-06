# Codex live read probe context

- Probe binary: `/private/tmp/valora-v0028-candidate` at SHA256 `e6552660bb971131d47161b9444e12833181b974f308ead470f31bd0e8040d59` (first V0028 candidate).
- Probe command: `Valora --verify-codex-usage-live docs/verification/v0028/live`
- Result: `status=ok`, duration about 2.44s; engine found; 5H present, weekly present, reset count present, no reset-credit entries; no account/read, no raw RPC/account fields stored.
- One bounded real read only. The final candidate changes only UI copy/QA scaffolding from that probe build; the transport/locator/parser were not retried.
- It read no auth.json/token/refresh token directly; the installed Codex engine owned sign-in. No media, device, browser, TCC or login write was performed.
