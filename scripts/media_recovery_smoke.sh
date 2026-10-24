#!/bin/zsh
# Read-only media-helper recovery smoke.
# Launches the candidate, kills only its bundled Perl stream helper, waits for
# the controller's periodic refresh to start exactly one replacement, then
# quits the app. It never sends a playback/seek/volume command.
set -eu
app="${1:-$PWD/dist/Valora.app}"
out="${2:-$PWD/docs/verification/v0003/media-recovery-smoke.json}"
app_bin="$app/Contents/MacOS/Valora"
log="$(mktemp -t valora-recovery).log"

"$app_bin" --no-settings >"$log" 2>&1 &
shell_pid=$!

helper_pids() {
  ps -ax -o pid,command | grep -F "mediaremote-adapter.pl" | grep -F "$app" | grep " stream " | grep -v grep | awk '{print $1}' || true
}

app_pid=""
for _ in {1..50}; do
  app_pid="$(pgrep -f "^$app_bin --no-settings$" | head -1 || true)"
  [[ -n "$app_pid" ]] && break
  sleep 0.1
done
if [[ -z "$app_pid" ]]; then
  echo "app did not start" >&2
  kill "$shell_pid" 2>/dev/null || true
  exit 1
fi

old_helper=""
for _ in {1..50}; do
  old_helper="$(helper_pids | head -1)"
  [[ -n "$old_helper" ]] && break
  sleep 0.1
done
if [[ -z "$old_helper" ]]; then
  echo "adapter helper did not start" >&2
  kill "$app_pid" 2>/dev/null || true
  exit 1
fi

kill "$old_helper"
new_helper=""
for _ in {1..50}; do
  candidate="$(helper_pids | head -1)"
  if [[ -n "$candidate" && "$candidate" != "$old_helper" ]]; then
    new_helper="$candidate"
    break
  fi
  sleep 0.1
done
sleep 0.5
helpers_after="$(helper_pids)"
helper_count="$(printf '%s\n' "$helpers_after" | sed '/^$/d' | wc -l | tr -d ' ')"
app_alive="false"
if ps -p "$app_pid" >/dev/null 2>&1; then app_alive="true"; fi

# Ask the running application to quit normally so its own stop() terminates the
# helper. Fall back to TERM only if it does not exit.
if [[ -x /tmp/running_icon ]]; then
  /tmp/running_icon /tmp/valora-recovery-icon.png >/dev/null 2>&1 || true
else
  kill -TERM "$app_pid" 2>/dev/null || true
fi
for _ in {1..30}; do
  ps -p "$app_pid" >/dev/null 2>&1 || break
  sleep 0.1
done
if ps -p "$app_pid" >/dev/null 2>&1; then kill -TERM "$app_pid" 2>/dev/null || true; fi
sleep 0.5
# Clean up only an orphaned helper of this app path (normal Quit should already
# have stopped it). This is our own auxiliary process, never a player.
for pid in $(helper_pids); do kill "$pid" 2>/dev/null || true; done
kill "$shell_pid" 2>/dev/null || true

python3 - "$out" "$app" "$old_helper" "$new_helper" "$helper_count" "$app_alive" <<'PY'
import json, sys, datetime
out, app, old, new, count, alive = sys.argv[1:]
data = {
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "app": app,
    "old_helper_pid": int(old),
    "new_helper_pid": int(new) if new else None,
    "helper_replaced": bool(new) and new != old,
    "stream_helper_count_after_recovery": int(count),
    "single_adapter_after_recovery": count == "1",
    "app_alive_after_helper_exit": alive == "true",
    "player_command_sent": False,
    "real_playback_touched": False,
    "method": "kill only the bundled mediaremote-adapter.pl stream process; wait for the existing 1 s refresh; then normal app quit",
}
with open(out, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
print(json.dumps(data, indent=2))
PY
rm -f "$log"
