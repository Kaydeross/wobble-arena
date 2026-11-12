#!/bin/sh
# Renders the ragdoll overlay (docs/RAGDOLL.md) to docs/style/godot-ragdoll-{running,midstride,hit,down,getup}.png.
#   sh tools/shoot-godot-ragdoll.sh [classic]      (classic: the same scenes with the old pose, *-classic.png)
# Needs a real renderer (opens a window for a moment). OUT=dir overrides the output folder.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${OUT:-$PWD/docs/style}"
mkdir -p "$OUT"
timeout 120 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
timeout 120 "$GODOT" --path godot --resolution 1280x720 --script res://tests/ragdoll_shots.gd -- --no-save --out "$OUT" --mode "${1:-ragdoll}" 2>&1 | grep -E '^SHOT|SCRIPT ERROR' || { echo "FAIL"; exit 1; }
