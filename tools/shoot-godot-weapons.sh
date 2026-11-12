#!/bin/sh
# Renders the weapon showcase (godot/actors/weapons_showcase.tscn) to docs/style/godot-weapons-{1,2,held}.png.
# Needs a real renderer (opens a window for a moment): the headless dummy renderer cannot draw.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$PWD/docs/style"
mkdir -p "$OUT"
timeout 120 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
shoot() { # mode file resolution
	timeout 60 "$GODOT" --path godot --resolution "$3" res://actors/weapons_showcase.tscn -- --mode "$1" --shot "$OUT/$2" 2>&1 | grep '^SHOT' || { echo "FAIL $1"; exit 1; }
}
shoot grid1 godot-weapons-1.png 1900x780
shoot grid2 godot-weapons-2.png 1900x780
shoot held godot-weapons-held.png 1600x700
