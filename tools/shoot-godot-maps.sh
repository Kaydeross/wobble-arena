#!/bin/sh
# Renders Godot maps for visual review (needs a real renderer: opens a window for a moment).
#   sh tools/shoot-godot-maps.sh [map ...]     the web game's level preview of each map -> docs/style/godot-maps-<id>.png
#   sh tools/shoot-godot-maps.sh play [map ...]  the in-match camera instead -> docs/style/godot-maps-<id>-play.png
#   sh tools/shoot-godot-maps.sh thumbs        the wizard's arena card art -> godot/ui/map_thumbs/<id>.jpg (every map)
# Compare with the web game: node tools/shoot-maps.js DIR [map ...]. Default maps: a representative eight.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$PWD/docs/style"
mkdir -p "$OUT"
timeout 180 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
case "${1:-}" in
	thumbs) timeout 900 "$GODOT" --path godot --resolution 852x393 --script res://tests/map_shots.gd -- --no-save --thumbs | grep -E '^SHOT|SCRIPT ERROR'
		timeout 180 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true; exit 0 ;;
	play) shift; FLAG=--play ;;
	*) FLAG= ;;
esac
timeout 600 "$GODOT" --path godot --resolution 852x393 --script res://tests/map_shots.gd -- --no-save --out "$OUT" $FLAG ${@:-arena candy volcano moonbase dojo craterdome farm rooftops} | grep -E '^SHOT|SCRIPT ERROR'
