#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: scripts/run_qq_lyrics_probe.sh OUTPUT_DIR [INPUT_JSON]}"
INPUT="${2:-$ROOT/scripts/qq_lyrics_sample.json}"
BIN="${TMPDIR:-/tmp}/valora-qq-lyrics-probe"
mkdir -p "$OUT"

# Compile the pure parser together with the standalone probe. This does not
# start or link the Valora app, and the probe is not part of normal app startup.
swiftc -swift-version 6 -DQQ_LYRICS_PROBE_MAIN -O -parse-as-library \
  "$ROOT/Sources/ReferenceCore/QQMusicLyrics.swift" \
  "$ROOT/scripts/qq_lyrics_probe.swift" \
  -o "$BIN"
"$BIN" --input "$INPUT" --out "$OUT"
echo "$OUT/network-summary.json"
