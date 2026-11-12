#!/bin/sh
# Renders the wobbler showcase (godot/actors/showcase.tscn) to docs/style/godot-wobbler-<mode>.png for visual review.
# Needs a real renderer (opens a window for a moment): the headless dummy renderer cannot draw.
#   sh tools/shoot-godot-showcase.sh [mode ...]     modes: classes outfits hats poses (default: all)
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$PWD/docs/style"
mkdir -p "$OUT"
timeout 120 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
for mode in ${@:-classes outfits hats poses}; do
	timeout 60 "$GODOT" --path godot --resolution 1600x700 res://actors/showcase.tscn -- --mode "$mode" --shot "$OUT/godot-wobbler-$mode.png" 2>&1 | grep '^SHOT' || { echo "FAIL $mode"; exit 1; }
done
