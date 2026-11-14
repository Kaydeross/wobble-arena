#!/usr/bin/env bash
# Build Wobblers Arena for Android from the command line. See docs/BUILD_ANDROID.md.
#
#   tools/build-android.sh              export a signed release .apk  -> build/android/WobbleArena.apk
#   tools/build-android.sh --debug      export a debug .apk (Godot debug keystore)
#   tools/build-android.sh --aab        export a Play Store .aab (needs Gradle Android build template)
#   tools/build-android.sh --install    after export, adb install -r on a connected device
#   tools/build-android.sh --export-only  alias for the default export (kept for parity with build-ios.sh)
#
# Environment overrides:
#   GODOT          Godot 4.7.2 binary (default: /Applications/Godot.app/... on macOS, or `godot` on PATH)
#   BUILD_NUMBER   version/code (default: git commit count; must increase for every Play upload)
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
#                  release signing (also read by Godot itself). Debug uses Godot's built-in debug keystore
#                  unless GODOT_ANDROID_KEYSTORE_DEBUG_* are set.
# Each stage overwrites its own output under build/android/ (gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${GODOT:-}" ]; then
  if [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
  elif command -v godot >/dev/null 2>&1; then
    GODOT="$(command -v godot)"
  else
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
  fi
fi
GODOT_VERSION_WANTED="4.7.2.stable"
PACKAGE_ID="com.kedrosng.wobblearena"
OUT="$ROOT/build/android"
LOGS="$OUT/logs"
PRESETS="$ROOT/godot/export_presets.cfg"
APK="$OUT/WobbleArena.apk"
AAB="$OUT/WobbleArena.aab"

MODE=release; DO_INSTALL=0; USE_AAB=0
for arg in "$@"; do
  case "$arg" in
    --debug) MODE=debug ;;
    --aab) USE_AAB=1 ;;
    --install) DO_INSTALL=1 ;;
    --export-only) ;; # default path already stops after export
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

command -v timeout >/dev/null || timeout() { shift; "$@"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
mkdir -p "$LOGS" "$OUT"

# --- 0. Preconditions --------------------------------------------------------
step "Checking tools"
[ -x "$GODOT" ] || fail "Godot not found at $GODOT (set GODOT=/path/to/Godot)."
GV="$(timeout 60 "$GODOT" --headless --version 2>/dev/null | tail -1)"
case "$GV" in "$GODOT_VERSION_WANTED"*) ;; *) fail "Godot $GODOT_VERSION_WANTED needed, found '$GV'." ;; esac

# Export templates live in different places on macOS vs Linux.
if [ "$(uname -s)" = Darwin ]; then
  TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION_WANTED"
else
  TEMPLATES="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$GODOT_VERSION_WANTED"
fi
# Godot 4.7 templates ship as android_{debug,release}.apk (plus android_source.zip for Gradle builds).
[ -f "$TEMPLATES/android_release.apk" ] || [ -f "$TEMPLATES/android_release.zip" ] \
  || fail "Android export templates missing under $TEMPLATES (need android_release.apk; Godot > Editor > Manage Export Templates > Download)."

# Headless export reads Editor Settings for Java + Android SDK paths (not env vars alone).
# Fill empty values from JAVA_HOME / ANDROID_HOME / ANDROID_SDK_ROOT when possible.
ensure_editor_sdk_paths() {
  local settings gv_short java_home sdk_home
  gv_short="$(printf '%s' "$GODOT_VERSION_WANTED" | cut -d. -f1,2)" # 4.7
  if [ "$(uname -s)" = Darwin ]; then
    settings="$HOME/Library/Application Support/Godot/editor_settings-${gv_short}.tres"
  else
    settings="${XDG_CONFIG_HOME:-$HOME/.config}/godot/editor_settings-${gv_short}.tres"
  fi
  [ -f "$settings" ] || {
    # First headless run creates the file; ignore failure.
    timeout 30 "$GODOT" --headless --quit-after 1 >/dev/null 2>&1 || true
  }
  [ -f "$settings" ] || return 0
  java_home="${JAVA_HOME:-}"
  if [ -z "$java_home" ] && command -v java >/dev/null; then
    java_home="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  fi
  sdk_home="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  python3 - "$settings" "$java_home" "$sdk_home" <<'PY' || true
import pathlib, re, sys
path, java, sdk = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
changed = False

def fill(key, value):
    global text, changed
    if not value:
        return
    pat = re.compile(rf'(?m)^({re.escape(key)}\s*=\s*)"(.*)"\s*$')
    m = pat.search(text)
    if not m:
        return
    if m.group(2).strip():
        return
    text = pat.sub(rf'\1"{value}"', text, count=1)
    changed = True

fill("export/android/java_sdk_path", java)
fill("export/android/android_sdk_path", sdk)
if changed:
    path.write_text(text)
    print(f"Filled empty Android export paths in {path}")
PY
}
ensure_editor_sdk_paths

VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/godot/project.godot")"
[ -n "$VERSION" ] || fail "godot/project.godot has no application/config/version."
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
echo "Godot $GV, version $VERSION, code $BUILD_NUMBER ($COMMIT)"

if [ "$USE_AAB" = 1 ]; then
  [ -d "$ROOT/godot/android/build" ] \
    || fail "Play .aab needs the Gradle Android build template. In Godot: Project > Install Android Build Template… (creates godot/android/, gitignored)."
fi

if [ "$MODE" = release ] || [ "$USE_AAB" = 1 ]; then
  if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
    fail "Release export needs a keystore. Set GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD, or use --debug for a local sideload APK (docs/BUILD_ANDROID.md)."
  fi
  [ -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ] \
    || fail "Release keystore not found: $GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
  [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" ] && [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ] \
    || fail "Set GODOT_ANDROID_KEYSTORE_RELEASE_USER and GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD too."
fi

# --- 1. build_info + version stamp in the Android preset --------------------
step "Writing godot/build_info.cfg"
printf '[build]\nversion="%s"\nnumber="%s"\ncommit="%s"\n' "$VERSION" "$BUILD_NUMBER" "$COMMIT" > "$ROOT/godot/build_info.cfg"

step "Stamping Android version/code=$BUILD_NUMBER version/name=$VERSION in export_presets.cfg"
# Patch only the Android preset options block (preset.4). Restored after export.
PRESETS_BAK="$(mktemp)"
cp "$PRESETS" "$PRESETS_BAK"
restore_presets() { cp "$PRESETS_BAK" "$PRESETS"; rm -f "$PRESETS_BAK"; }
trap restore_presets EXIT

python3 - "$PRESETS" "$BUILD_NUMBER" "$VERSION" "$USE_AAB" <<'PY'
import pathlib, sys
path, code, name, use_aab = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4] == "1"
text = path.read_text()
marker = '[preset.4.options]'
i = text.find(marker)
if i < 0:
    sys.exit("Android preset [preset.4.options] missing from export_presets.cfg")
j = text.find("\n[preset.", i + 1)
block = text[i:] if j < 0 else text[i:j]
rest = "" if j < 0 else text[j:]

def set_opt(block: str, key: str, value: str) -> str:
    import re
    pat = re.compile(rf'(?m)^{re.escape(key)}=.*$')
    if not pat.search(block):
        sys.exit(f"missing option {key} in Android preset")
    return pat.sub(f"{key}={value}", block, count=1)

block = set_opt(block, "version/code", code)
block = set_opt(block, "version/name", f'"{name}"')
if use_aab:
    block = set_opt(block, "gradle_build/use_gradle_build", "true")
    block = set_opt(block, "gradle_build/export_format", "1")  # 1 = AAB
    # export_path is on the preset header, not options — patched below
path.write_text(text[:i] + block + rest)

if use_aab:
    text = path.read_text()
    text = text.replace(
        'export_path="../build/android/WobbleArena.apk"',
        'export_path="../build/android/WobbleArena.aab"',
        1,
    )
    path.write_text(text)
PY

# --- 2. Import + export ------------------------------------------------------
step "Importing Godot project (log: $LOGS/import.log)"
timeout 600 "$GODOT" --headless --path "$ROOT/godot" --import > "$LOGS/import.log" 2>&1 \
  || fail "Godot import failed, see $LOGS/import.log"

EXPORT_FLAG="--export-release"
TARGET="$APK"
PRESET_NAME="Android"
if [ "$MODE" = debug ]; then
  EXPORT_FLAG="--export-debug"
fi
if [ "$USE_AAB" = 1 ]; then
  TARGET="$AAB"
  [ "$MODE" = debug ] && fail "--aab is for Play Store release builds; omit --debug."
fi

step "Exporting $PRESET_NAME ($MODE) to $TARGET (log: $LOGS/export.log)"
rm -f "$APK" "$AAB"
set +e
timeout 1200 "$GODOT" --headless --path "$ROOT/godot" $EXPORT_FLAG "$PRESET_NAME" "$TARGET" > "$LOGS/export.log" 2>&1
code=$?
set -e
if [ $code -ne 0 ] || grep -qE "ERROR: Cannot export|ERROR: Project export|Failed to export" "$LOGS/export.log" || [ ! -f "$TARGET" ]; then
  grep -A8 "ERROR" "$LOGS/export.log" | head -40 >&2 || true
  fail "Godot Android export failed (exit $code). Check $LOGS/export.log. Missing templates or JDK/SDK are the usual causes (docs/BUILD_ANDROID.md)."
fi
echo "Exported $TARGET ($(du -h "$TARGET" | awk '{print $1}'))"

# Restore presets before optional install so a failed adb doesn't leave them dirty longer than needed.
restore_presets
trap - EXIT

# --- 3. Optional device install ---------------------------------------------
if [ "$DO_INSTALL" = 1 ]; then
  [ "$USE_AAB" = 0 ] || fail "--install works with .apk only (not .aab). Use bundletool or Play internal testing for AABs."
  step "Installing on a connected device via adb"
  command -v adb >/dev/null || fail "adb not found. Install Android platform-tools and put adb on PATH."
  adb devices | awk 'NR>1 && $2=="device"{found=1} END{exit !found}' \
    || fail "No adb device in 'device' state. Plug in a phone with USB debugging, or start an emulator."
  adb install -r "$APK" || fail "adb install failed"
  echo "Launching $PACKAGE_ID"
  adb shell monkey -p "$PACKAGE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
fi

echo
echo "Done: $TARGET"
echo "Package: $PACKAGE_ID  versionName=$VERSION  versionCode=$BUILD_NUMBER"
if [ "$USE_AAB" = 1 ]; then
  echo "Upload to Play Console (internal testing) with the Play release keystore."
else
  echo "Install: adb install -r \"$TARGET\"   (or rerun with --install)"
fi
