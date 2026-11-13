#!/usr/bin/env bash
# Build Wobblers Arena for iOS from the command line. See docs/BUILD_IOS.md.
#
#   tools/build-ios.sh              export Xcode project -> signed archive -> App Store .ipa
#   tools/build-ios.sh --simulator  export -> unsigned build -> install, launch and screenshot in the iOS Simulator
#   tools/build-ios.sh --export-only    stop after the Godot export (build/ios/xcode)
#   tools/build-ios.sh --skip-export    reuse build/ios/xcode from an earlier run
#
# Environment overrides:
#   GODOT          Godot 4.7.2 binary (default: /Applications/Godot.app/Contents/MacOS/Godot)
#   TEAM_ID        Apple team ID (default: 663Q47AS93)
#   BUILD_NUMBER   CFBundleVersion (default: number of commits on HEAD; must increase for every upload)
#   SIM_DEVICE     simulator name or UDID for --simulator (default: first available iPhone)
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID
#                  optional App Store Connect API key for provisioning without an Xcode account login (CI)
# Each stage overwrites its own output, so the script can be rerun at any point.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_VERSION_WANTED="4.7.2.stable"
TEAM_ID="${TEAM_ID:-663Q47AS93}"
BUNDLE_ID="com.kedrosng.wobblearena"
SCHEME="WobbleArena"
OUT="$ROOT/build/ios"
XCODE_DIR="$OUT/xcode"
PROJECT="$XCODE_DIR/$SCHEME.xcodeproj"
LOGS="$OUT/logs"

MODE=device; SKIP_EXPORT=0; EXPORT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --simulator) MODE=simulator ;;
    --skip-export) SKIP_EXPORT=1 ;;
    --export-only) EXPORT_ONLY=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

# macOS has no timeout(1) unless coreutils is installed; fall back to running without one.
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
[ -f "$TEMPLATES/ios.zip" ] || fail "iOS export template missing: $TEMPLATES/ios.zip (Godot > Editor > Manage Export Templates > Download)."
command -v xcodebuild >/dev/null || fail "xcodebuild not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app"
echo "Godot $GV, $(xcodebuild -version | head -1), team $TEAM_ID"

VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/godot/project.godot")"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
echo "Version $VERSION, build $BUILD_NUMBER ($COMMIT)"

# --- 1. Godot import + export to an Xcode project ----------------------------
if [ "$SKIP_EXPORT" = 0 ]; then
  step "Writing godot/build_info.cfg"
  printf '[build]\nversion="%s"\nnumber="%s"\ncommit="%s"\n' "$VERSION" "$BUILD_NUMBER" "$COMMIT" > "$ROOT/godot/build_info.cfg"

  step "Importing Godot project (log: $LOGS/import.log)"
  timeout 600 "$GODOT" --headless --path "$ROOT/godot" --import > "$LOGS/import.log" 2>&1 \
    || fail "Godot import failed, see $LOGS/import.log"

  step "Exporting Xcode project to $XCODE_DIR (log: $LOGS/export.log)"
  rm -rf "$XCODE_DIR"; mkdir -p "$XCODE_DIR"
  set +e
  timeout 900 "$GODOT" --headless --path "$ROOT/godot" --export-release "iOS" "$PROJECT" > "$LOGS/export.log" 2>&1
  code=$?
  set -e
  if [ $code -ne 0 ] || grep -q "ERROR: Cannot export\|ERROR: Project export" "$LOGS/export.log" || [ ! -f "$PROJECT/project.pbxproj" ]; then
    grep -A8 "ERROR" "$LOGS/export.log" | head -30 >&2 || true
    fail "Godot iOS export failed (exit $code). An empty error list usually means ETC2/ASTC import is off in project.godot."
  fi
  echo "Exported $PROJECT"
else
  [ -f "$PROJECT/project.pbxproj" ] || fail "--skip-export given but $PROJECT does not exist. Run without it first."
fi
[ "$EXPORT_ONLY" = 1 ] && { echo; echo "Done (export only): $PROJECT"; exit 0; }

AUTH_ARGS=()
if [ -n "${ASC_KEY_PATH:-}" ]; then
  [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] || fail "ASC_KEY_PATH needs ASC_KEY_ID and ASC_ISSUER_ID too."
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# --- Simulator path ----------------------------------------------------------
if [ "$MODE" = simulator ]; then
  # The official Godot 4.7.2 template's simulator slice is x86_64 only, and iOS 26+ simulators no longer
  # run x86_64 apps. So we build the arm64 *device* binary unsigned, retag its Mach-O platform to
  # iOS Simulator with vtool, and ad-hoc sign it. Good enough to check that the app installs and boots.
  step "Building unsigned arm64 app (log: $LOGS/sim-build.log)"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug -sdk iphoneos \
    -destination 'generic/platform=iOS' -derivedDataPath "$OUT/derived-sim" \
    CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="$VERSION" \
    build > "$LOGS/sim-build.log" 2>&1 \
    || { grep -E "error:" "$LOGS/sim-build.log" | head -20 >&2; fail "xcodebuild failed, see $LOGS/sim-build.log"; }

  step "Retagging binary for the iOS Simulator"
  # Staged outside the repo: iCloud-synced folders (e.g. ~/Desktop) keep re-adding xattrs that codesign rejects.
  STAGE="${TMPDIR:-/tmp}/wobble-arena-ios-sim"
  APP="$STAGE/$SCHEME.app"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  ditto --norsrc --noextattr "$OUT/derived-sim/Build/Products/Debug-iphoneos/$SCHEME.app" "$APP"
  SDKV="$(xcrun --sdk iphonesimulator --show-sdk-version)"
  xcrun vtool -arch arm64 -set-build-version 7 15.0 "$SDKV" -replace -output "$APP/$SCHEME.sim" "$APP/$SCHEME"
  mv "$APP/$SCHEME.sim" "$APP/$SCHEME"
  codesign -f -s - "$APP" > "$LOGS/sim-codesign.log" 2>&1 || fail "ad-hoc codesign of $APP failed, see $LOGS/sim-codesign.log"

  step "Choosing a simulator"
  LIST="$(xcrun simctl list devices available)"
  if [ -n "${SIM_DEVICE:-}" ]; then
    UDID="$(printf '%s\n' "$LIST" | grep -F -- "$SIM_DEVICE" | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
  else
    UDID="$(printf '%s\n' "$LIST" | grep -E '^\s+iPhone' | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
  fi
  [ -n "$UDID" ] || fail "No matching simulator. List them with: xcrun simctl list devices available"
  printf '%s\n' "$LIST" | grep "$UDID"
  xcrun simctl boot "$UDID" 2>/dev/null || true   # already booted is fine
  timeout 180 xcrun simctl bootstatus "$UDID" -b > /dev/null || fail "Simulator $UDID did not boot"

  step "Installing and launching $BUNDLE_ID"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP" || fail "simctl install failed"
  xcrun simctl launch "$UDID" "$BUNDLE_ID" || fail "simctl launch failed"
  sleep 8
  SHOT="$OUT/simulator.png"
  xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null 2>&1 || fail "screenshot failed"
  if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "App is running."
  else
    echo "WARNING: app is no longer running (crashed?). Crash reports: ~/Library/Logs/DiagnosticReports/$SCHEME-*.ips" >&2
  fi
  echo
  echo "Screenshot: $SHOT"
  echo "Note: the simulator's Metal GPU lacks image cube arrays, so Godot's Mobile renderer shows an"
  echo "'Apple GPU does not support...' alert there. Use a real device to check rendering (docs/BUILD_IOS.md)."
  exit 0
fi

# --- 2. Signed archive -------------------------------------------------------
ARCHIVE="$OUT/$SCHEME.xcarchive"
step "Archiving (signed, team $TEAM_ID; log: $LOGS/archive.log)"
rm -rf "$ARCHIVE"
# Automatic signing archives with the Development identity; exportArchive re-signs for distribution.
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$OUT/derived" \
    -allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="$VERSION" \
    archive > "$LOGS/archive.log" 2>&1; then
  grep -E "error:" "$LOGS/archive.log" | sort -u | head -20 >&2
  if grep -qiE "No Accounts|No profiles for|provisioning profile|signing certificate|Failed Registering|requires a development team" "$LOGS/archive.log"; then
    cat >&2 <<EOF

Signing/provisioning problem. Do one of these, then rerun with --skip-export:
  a) Xcode > Settings > Accounts: sign in with an Apple ID in team $TEAM_ID (Admin or App Manager role),
     so -allowProvisioningUpdates can register $BUNDLE_ID and create profiles itself; or
  b) set ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID to an App Store Connect API key (Admin role); or
  c) in developer.apple.com > Certificates, IDs & Profiles: create the App ID $BUNDLE_ID and an
     "App Store Connect" distribution profile for it, and download it in Xcode > Settings > Accounts.
EOF
  fi
  fail "xcodebuild archive failed, see $LOGS/archive.log"
fi
echo "Archive: $ARCHIVE"

# --- 3. Export the .ipa for App Store Connect --------------------------------
step "Exporting .ipa for App Store Connect (log: $LOGS/export-ipa.log)"
IPA_DIR="$OUT/ipa"
rm -rf "$IPA_DIR"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>export</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$IPA_DIR" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
  > "$LOGS/export-ipa.log" 2>&1 \
  || { grep -E "error" "$LOGS/export-ipa.log" | head -20 >&2; fail "exportArchive failed, see $LOGS/export-ipa.log"; }
IPA="$IPA_DIR/$SCHEME.ipa"
[ -f "$IPA" ] || fail "exportArchive reported success but $IPA is missing"

step "Checking the signature"
plutil -p "$IPA_DIR/DistributionSummary.plist" | grep -E '"(type|name|buildNumber|versionNumber|get-task-allow|beta-reports-active)"' || true
echo
echo "Ready to upload: $IPA"
echo "Upload (not done by this script):"
echo "  xcrun altool --upload-app -f \"$IPA\" -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
echo "  or drag it into Transporter.app."
