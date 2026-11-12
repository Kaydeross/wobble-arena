#!/bin/sh
# Renders the Godot UI for visual review (needs a real renderer: opens a window for a moment).
#   sh tools/shoot-godot-ui.sh [suffix] [shot ...]     shots: title title-online title-settings wizard-arena wizard-mode
#     wizard-players wizard-class wizard-go match touch touch-lefty fps pause (default: these), title-construction construction
# Writes docs/style/godot-ui-<shot>[-suffix].png (wizard pages: godot-wizard-<page>[-suffix].png) at the iPhone landscape
# size (852x393 pt; RES=WxH overrides).
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$PWD/docs/style"
SUFFIX="${1:-}"
[ $# -gt 0 ] && shift
RES="${RES:-852x393}"
mkdir -p "$OUT"
timeout 120 "$GODOT" --headless --path godot --import >/dev/null 2>&1 || true
for s in ${@:-title title-online title-settings wizard-arena wizard-mode wizard-players wizard-class wizard-go match touch touch-lefty fps pause}; do
	case "$s" in wizard-*) name="godot-$s${SUFFIX:+-$SUFFIX}.png" ;; *) name="godot-ui-$s${SUFFIX:+-$SUFFIX}.png" ;; esac
	timeout 120 "$GODOT" --path godot --resolution "$RES" --script res://tests/ui_shots.gd -- --no-save --shot "$s" --out "$OUT/$name" 2>&1 | grep -E '^SHOT|SCRIPT ERROR' || { echo "FAIL $s"; exit 1; }
done
