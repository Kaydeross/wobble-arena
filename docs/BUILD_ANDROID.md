# Building Wobble Arena for Android

`tools/build-android.sh` builds the Android debug APK from the command line: Godot headless import → export debug APK → optional ADB install/run/screenshot.

## Requirements

- Godot **4.7.2.stable** at `/Applications/Godot.app` (or set `GODOT=`), with export templates installed (`~/Library/Application Support/Godot/export_templates/4.7.2.stable/android_debug.apk`).
- **Android SDK** at `~/Library/Android/sdk` (or set `ANDROID_HOME=`), with `platform-tools` (containing `adb`) and `build-tools` (containing `apksigner`).
- **OpenJDK 21** (e.g. Homebrew `openjdk@21`, or set `JAVA_HOME=`).
- A debug keystore at `~/.android/debug.keystore` (generated automatically if missing, user `androiddebugkey`, password `android`).

## Usage

```sh
tools/build-android.sh                 # export debug APK -> build/android/WobbleArena.apk
tools/build-android.sh --install       # export + install to connected device or emulator via adb
tools/build-android.sh --run           # export + install + launch + capture screenshot -> build/android/screenshot.png
tools/build-android.sh --export-only   # only the Godot export (default)
tools/build-android.sh --skip-export   # reuse the last APK (e.g. to test install/run on another device)
BUILD_NUMBER=60 tools/build-android.sh # override versionCode (default: git commit count)
ADB_DEVICE="emulator-5554" tools/build-android.sh --run
```

All outputs go under `build/android/` (gitignored). Logs are written to `build/android/logs/`.

### What the stages do

1. **Checks:** Godot version (`4.7.2.stable`), Android export template (`android_debug.apk`), Android SDK (`ANDROID_HOME`), `adb`, Java 21 runtime, and debug keystore. Auto-configures Godot editor settings if needed.
2. **Build info:** writes `godot/build_info.cfg` (version, build number, commit; gitignored). The main scene displays this via `build_label.gd`.
3. **Import + export:** `godot --headless --import`, then `--export-debug "Android"` using preset `[preset.4]` in `godot/export_presets.cfg`.
4. **Install & Run (optional):** targets the first active ADB device (or `$ADB_DEVICE`), runs `adb install -r`, launches `com.kedrosng.wobblearena/com.godot.game.GodotApp`, and takes a screenshot with `screencap`.

## Export Preset Configuration

The `Android` preset in `godot/export_presets.cfg`:
- **Package:** `com.kedrosng.wobblearena`
- **Architecture:** `arm64-v8a` only (64-bit ARM)
- **Min SDK:** 24, **Target SDK:** 35 / 36 (via prebuilt template)
- **Build system:** `gradle_build/use_gradle_build = false` (uses prebuilt Godot export templates)
- **Orientation & Screen:** sensor landscape, immersive mode
- **Permissions:** `android.permission.INTERNET` only
- **Signing:** No keystore secrets committed; signs debug builds with standard debug keystore via environment variables or Editor Settings.

## Android GDScript Features

- **Safe area & Display cutouts:** `godot/ui/safe_area.gd` queries `DisplayServer.get_display_safe_area()` and `DisplayServer.get_display_cutouts()`, scaling insets into 2D canvas coordinates for notches and camera punch holes.
- **Touch controls:** Enabled by default on Android (`Tier.detect()` recognizes `mobile` and `android`).
- **Back button navigation:** The Android system back button or gesture triggers `NOTIFICATION_WM_GO_BACK_REQUEST` in `godot/world/world.gd` to toggle the pause menu (or `KEY_BACK` in `player_input.gd`).
