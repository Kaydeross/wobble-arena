#!/bin/sh
# Renders the Godot UI for visual review (needs a real renderer: opens a window for a moment).
#   sh tools/shoot-godot-ui.sh [suffix] [shot ...]     shots: title title-online title-settings wizard-mode wizard-arena
#     wizard-players wizard-character wizard-start match touch touch-lefty fps pause (default: these, plus title and
#     wizard-character in iPhone portrait 390x844 as *-portrait.png), title-construction construction
# Walldrobe / Shop set (internally "locker"): locker-skin locker-hat locker-color locker-emote locker-class shop
# shop-class shop-confirm emote-wheel results (written as docs/style/godot-locker-*.png); goals (docs/style/godot-ui-goals.png). Accounts: account-guest account-signed killcam (docs/style/godot-account-*.png).
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
for s in ${@:-title title-online title-settings wizard-mode wizard-team wizard-arena wizard-players wizard-character wizard-start match touch touch-lefty fps pause}; do
	case "$s" in wizard-*|locker-*) name="godot-$s${SUFFIX:+-$SUFFIX}.png" ;; shop*|emote-wheel|results) name="godot-locker-$s${SUFFIX:+-$SUFFIX}.png" ;;
		account-*) name="godot-$s${SUFFIX:+-$SUFFIX}.png" ;; killcam) name="godot-account-killcam${SUFFIX:+-$SUFFIX}.png" ;; *) name="godot-ui-$s${SUFFIX:+-$SUFFIX}.png" ;; esac
	timeout 120 "$GODOT" --path godot --resolution "$RES" --script res://tests/ui_shots.gd -- --no-save --shot "$s" --out "$OUT/$name" 2>&1 | grep -E '^SHOT|SCRIPT ERROR' || { echo "FAIL $s"; exit 1; }
done
if [ $# -eq 0 ] && [ -z "$SUFFIX" ]; then   # portrait (iPhone 390x844 pt)
	for s in title wizard-character; do
		case "$s" in wizard-*) name="godot-$s-portrait.png" ;; *) name="godot-ui-$s-portrait.png" ;; esac
		timeout 120 "$GODOT" --path godot --resolution 390x844 --script res://tests/ui_shots.gd -- --no-save --shot "$s" --out "$OUT/$name" 2>&1 | grep -E '^SHOT|SCRIPT ERROR' || { echo "FAIL $s portrait"; exit 1; }
	done
fi
