#!/bin/sh
# Renders the app icon (godot/icon.png), the launch logo (godot/ui/brand/launch_logo.png) and review copies
# (docs/style/godot-ui-icon-1024.png, -icon-60.png, -launch.png) with godot/tests/brand_shots.gd.
# Needs a real renderer (opens a window for a moment): the headless dummy renderer cannot draw.
#   sh tools/shoot-godot-brand.sh
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$PWD/docs/style"
mkdir -p "$OUT"
timeout 120 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
timeout 300 "$GODOT" --path godot --resolution 640x480 --script res://tests/brand_shots.gd -- --no-save --out "$OUT" 2>&1 | grep -E '^SHOT|SCRIPT ERROR' || { echo "FAIL"; exit 1; }
timeout 120 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
