#!/usr/bin/env bash
# Build Wobble Arena for Android from the command line. See docs/BUILD_ANDROID.md.
#
#   tools/build-android.sh             export debug APK -> build/android/WobbleArena.apk
#   tools/build-android.sh --install   export + install to connected device/emulator via adb
#   tools/build-android.sh --run       export + install + launch + screenshot to build/android/
#   tools/build-android.sh --export-only  stop after the Godot export (same as default)
#   tools/build-android.sh --skip-export  reuse build/android/WobbleArena.apk from an earlier run
#
# Environment overrides:
#   GODOT          Godot 4.7.2 binary (default: /Applications/Godot.app/Contents/MacOS/Godot)
#   ANDROID_HOME   Android SDK root (default: ~/Library/Android/sdk)
#   JAVA_HOME      Java 21 home (default: /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home or detected)
#   BUILD_NUMBER   versionCode (default: number of commits on HEAD)
#   ADB_DEVICE     adb device serial (default: first connected device or running emulator)
# Each stage overwrites its own output, so the script can be rerun at any point.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_VERSION_WANTED="4.7.2.stable"
PACKAGE="com.kedrosng.wobblearena"
ACTIVITY="com.godot.game.GodotApp"
OUT="$ROOT/build/android"
APK="$OUT/WobbleArena.apk"
LOGS="$OUT/logs"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

# Auto-detect JAVA_HOME if not provided
if [ -z "${JAVA_HOME:-}" ]; then
  if [ -d "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home" ]; then
    JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
  elif [ -d "/opt/homebrew/Cellar/openjdk@21/21.0.12.1/libexec/openjdk.jdk/Contents/Home" ]; then
    JAVA_HOME="/opt/homebrew/Cellar/openjdk@21/21.0.12.1/libexec/openjdk.jdk/Contents/Home"
  elif command -v /usr/libexec/java_home >/dev/null 2>&1; then
    JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
  fi
fi

MODE=export; SKIP_EXPORT=0; EXPORT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --install) MODE=install ;;
    --run) MODE=run ;;
    --skip-export) SKIP_EXPORT=1 ;;
    --export-only) EXPORT_ONLY=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

command -v timeout >/dev/null || timeout() { shift; "$@"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
mkdir -p "$LOGS"

# --- 0. Preconditions --------------------------------------------------------
step "Checking tools"
[ -x "$GODOT" ] || fail "Godot not found at $GODOT (set GODOT=/path/to/Godot)."
GV="$(timeout 60 "$GODOT" --headless --version 2>/dev/null | tail -1)"
case "$GV" in "$GODOT_VERSION_WANTED"*) ;; *) fail "Godot $GODOT_VERSION_WANTED needed, found '$GV'." ;; esac

TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION_WANTED"
[ -f "$TEMPLATES/android_debug.apk" ] || fail "Android export template missing: $TEMPLATES/android_debug.apk (Godot > Editor > Manage Export Templates > Download)."

[ -d "$ANDROID_HOME" ] || fail "Android SDK not found at $ANDROID_HOME (set ANDROID_HOME=/path/to/sdk)."

# Ensure adb is accessible
ADB=""
if command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
elif [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
  ADB="$ANDROID_HOME/platform-tools/adb"
fi
[ -n "$ADB" ] || fail "adb not found in PATH or at $ANDROID_HOME/platform-tools/adb."

# JDK check
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  export JAVA_HOME
  export PATH="$JAVA_HOME/bin:$PATH"
fi
command -v java >/dev/null 2>&1 || fail "Java runtime not found. Please install OpenJDK 21."
JV="$(java -version 2>&1 | head -1)"
case "$JV" in
  *21.*|*\"21\"*) ;;
  *) echo "WARNING: Recommended Java version is 21 (found '$JV')." ;;
esac

# Ensure debug keystore exists
KEYSTORE_DIR="$HOME/.android"
KEYSTORE_FILE="$KEYSTORE_DIR/debug.keystore"
if [ ! -f "$KEYSTORE_FILE" ]; then
  step "Generating debug keystore at $KEYSTORE_FILE"
  mkdir -p "$KEYSTORE_DIR"
  keytool -genkey -v -keystore "$KEYSTORE_FILE" -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1 || fail "Failed to generate debug keystore."
fi

# Ensure Godot's keystores folder and editor settings are configured
mkdir -p "$HOME/Library/Application Support/Godot/keystores"
ln -sf "$KEYSTORE_FILE" "$HOME/Library/Application Support/Godot/keystores/debug.keystore" 2>/dev/null || true

EDITOR_SETTINGS="$HOME/Library/Application Support/Godot/editor_settings-4.7.tres"
if [ -f "$EDITOR_SETTINGS" ]; then
  python3 -c "
path = '$EDITOR_SETTINGS'
sdk_path = '$ANDROID_HOME'
java_path = '${JAVA_HOME:-}'
try:
    content = open(path).read()
    changed = False
    if 'export/android/android_sdk_path' in content:
        import re
        content, c1 = re.subn(r'export/android/android_sdk_path = \".*?\"', f'export/android/android_sdk_path = \"{sdk_path}\"', content)
        if c1 > 0: changed = True
    if 'export/android/java_sdk_path' in content and java_path:
        import re
        content, c2 = re.subn(r'export/android/java_sdk_path = \".*?\"', f'export/android/java_sdk_path = \"{java_path}\"', content)
        if c2 > 0: changed = True
    if changed:
        open(path, 'w').write(content)
except Exception:
    pass
" 2>/dev/null || true
fi

# Keystore environment variables for Godot Android export
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE_FILE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"

echo "Godot $GV, Android SDK: $ANDROID_HOME, Java: $JV"

VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/godot/project.godot")"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
echo "Version $VERSION, build $BUILD_NUMBER ($COMMIT)"

# --- 1. Godot import + export debug APK ---------------------------------------
if [ "$SKIP_EXPORT" = 0 ]; then
  step "Writing godot/build_info.cfg"
  printf '[build]\nversion="%s"\nnumber="%s"\ncommit="%s"\n' "$VERSION" "$BUILD_NUMBER" "$COMMIT" > "$ROOT/godot/build_info.cfg"

  step "Importing Godot project (log: $LOGS/import.log)"
  timeout 600 "$GODOT" --headless --path "$ROOT/godot" --import > "$LOGS/import.log" 2>&1 \
    || fail "Godot import failed, see $LOGS/import.log"

  step "Exporting Android debug APK to $APK (log: $LOGS/export.log)"
  mkdir -p "$OUT"
  rm -f "$APK"
  set +e
  timeout 900 "$GODOT" --headless --path "$ROOT/godot" --export-debug "Android" "$APK" > "$LOGS/export.log" 2>&1
  code=$?
  set -e
  if [ $code -ne 0 ] || grep -q "ERROR: Cannot export\|ERROR: Project export" "$LOGS/export.log" || [ ! -f "$APK" ]; then
    grep -A8 "ERROR" "$LOGS/export.log" | head -30 >&2 || true
    fail "Godot Android export failed (exit $code), see $LOGS/export.log"
  fi
  echo "Exported $APK"
else
  [ -f "$APK" ] || fail "--skip-export given but $APK does not exist. Run without it first."
fi

if [ "$MODE" = export ] || [ "$EXPORT_ONLY" = 1 ]; then
  echo
  echo "Done: $APK"
  exit 0
fi

# --- 2. ADB Install & Run ----------------------------------------------------
step "Detecting Android device / emulator"
DEVICES="$("$ADB" devices | grep -E '\b(device|emulator)\b' | grep -v 'List of devices' || true)"
[ -n "$DEVICES" ] || fail "No Android device or emulator connected. Start an emulator or plug in a device with USB debugging enabled."

DEVICE_ID="${ADB_DEVICE:-}"
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(printf '%s\n' "$DEVICES" | head -1 | awk '{print $1}')"
fi
echo "Using target device: $DEVICE_ID"

step "Installing $APK to device $DEVICE_ID"
"$ADB" -s "$DEVICE_ID" install -r "$APK" || fail "adb install failed"

if [ "$MODE" = run ]; then
  step "Launching $PACKAGE"
  "$ADB" -s "$DEVICE_ID" shell am force-stop "$PACKAGE" 2>/dev/null || true
  "$ADB" -s "$DEVICE_ID" shell am start -n "$PACKAGE/$ACTIVITY" || fail "adb am start failed"
  sleep 6
  SHOT="$OUT/screenshot.png"
  step "Capturing screenshot to $SHOT"
  "$ADB" -s "$DEVICE_ID" exec-out screencap -p > "$SHOT" 2>/dev/null || true
  if [ -s "$SHOT" ]; then
    echo "Screenshot saved: $SHOT"
  fi

  if "$ADB" -s "$DEVICE_ID" shell pidof "$PACKAGE" >/dev/null 2>&1; then
    echo "App is running (PID: $("$ADB" -s "$DEVICE_ID" shell pidof "$PACKAGE"))."
  else
    echo "WARNING: App may not be running. Check adb logcat." >&2
  fi
fi

echo
echo "Done!"
