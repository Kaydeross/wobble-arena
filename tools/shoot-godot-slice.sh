#!/bin/sh
# Renders three frames of a scripted offline match (godot/tests/slice_shots.gd) to docs/style/godot-slice-*.png for visual review.
# Needs a real renderer (opens a window for a while): the headless dummy renderer cannot draw.
#   sh tools/shoot-godot-slice.sh
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$PWD/docs/style"
mkdir -p "$OUT"
timeout 120 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
timeout 180 "$GODOT" --path godot --resolution 1600x900 --script res://tests/slice_shots.gd -- --no-save --out "$OUT" 2>&1 | grep -E '^SHOT|ERROR' || { echo "FAIL"; exit 1; }
