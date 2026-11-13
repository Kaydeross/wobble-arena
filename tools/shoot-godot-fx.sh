#!/bin/sh
# Renders the combat effects in a real match (godot/tests/fx_shots.gd) to docs/style/godot-fx-<name>.png.
# Needs a real renderer (opens a window for a moment): the headless dummy renderer cannot draw.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$PWD/docs/style"
mkdir -p "$OUT"
timeout 120 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
for s in explosion confetti dash melee impact dust; do
	timeout 90 "$GODOT" --path godot --resolution 1280x720 --script res://tests/fx_shots.gd -- --no-save --shot "$s" --out "$OUT/godot-fx-$s.png" 2>&1 | grep '^SHOT' || { echo "FAIL $s"; exit 1; }
done
