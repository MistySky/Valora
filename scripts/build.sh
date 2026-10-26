#!/bin/zsh
# Reproducible local build for the Valora music candidate.
# No network access, no install, no publishing, no preference/player writes.
set -eu
project_root="$(cd "$(dirname "$0")/.." && pwd)"

python3 "$project_root/scripts/build_media_adapter.py"
swift build --package-path "$project_root" --scratch-path "$project_root/.build" -c release \
  --product Valora
swift build --package-path "$project_root" --scratch-path "$project_root/.build" -c release \
  --product ValoraNativeHost
binary_directory="$(swift build --package-path "$project_root" --scratch-path "$project_root/.build" -c release --show-bin-path)"
python3 "$project_root/scripts/package.py" --binary "$binary_directory/Valora" \
  --native-host "$binary_directory/ValoraNativeHost" "$@"
