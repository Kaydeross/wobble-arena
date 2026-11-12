# Building Wobblers Arena for Android

`tools/build-android.sh` does everything from the command line: Godot import → Android export → optional `adb install`. It does **not** upload to Play Console.

The Godot project is the same one used for iOS (`godot/`). Touch controls, the Mobile render tier, and landscape orientation already apply on Android via `Tier` (`OS.has_feature("android")`).

## Requirements

- Godot **4.7.2.stable** (same as iOS), with Android export templates installed.
- JDK 17+ (OpenJDK is fine). Set `JAVA_HOME` so the build script can fill Godot Editor Settings if needed.
- Android SDK with `platform-tools` and `build-tools` (Godot needs `adb` and `apksigner`). Set `ANDROID_HOME` (or `ANDROID_SDK_ROOT`).
- Optional: `adb` on `PATH` for `--install`.
- For Play Store `.aab` only: install the Gradle Android build template once (**Project → Install Android Build Template…**, or `godot --headless --path godot --install-android-build-template`). That creates `godot/android/` (gitignored).

On macOS, Godot defaults to `/Applications/Godot.app`. On Linux, put `godot` on `PATH` or set `GODOT=`. Templates live in:

- macOS: `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
- Linux: `~/.local/share/godot/export_templates/4.7.2.stable/`

You need at least `android_release.apk` (and `android_debug.apk` for `--debug`). Godot 4.7 also ships `android_source.zip` for Gradle / `.aab` builds.

## Usage

```sh
tools/build-android.sh --debug         # debug .apk (Godot debug keystore) — usual local path
tools/build-android.sh --debug --install  # export debug .apk and adb install -r
tools/build-android.sh                 # release .apk (needs GODOT_ANDROID_KEYSTORE_RELEASE_*)
tools/build-android.sh --aab           # Play Store .aab (needs Gradle template + release keystore)
BUILD_NUMBER=60 tools/build-android.sh --debug  # override versionCode (default: git commit count)
GODOT=/path/to/Godot tools/build-android.sh --debug
```

Each run overwrites `build/android/` (gitignored). Logs go to `build/android/logs/`.

### What the stages do

1. **Checks:** Godot version and Android export templates.
2. **Build info:** writes `godot/build_info.cfg` (version, build number, commit; gitignored), same as iOS.
3. **Version stamp:** temporarily sets `version/code` and `version/name` on the Android preset, then restores `export_presets.cfg` after the export (so the committed file stays at the placeholder `1` / `0.1.0`).
4. **Import + export:** `godot --headless --import`, then `--export-release "Android"` (or `--export-debug`).
5. **Optional install:** `adb install -r` and a launcher monkey start.

### Signing

- **Debug:** Godot's built-in debug keystore (fine for local devices). Override with `GODOT_ANDROID_KEYSTORE_DEBUG_PATH` / `_USER` / `_PASSWORD` if you need to.
- **Release / Play:** set the release keystore via env vars (Godot reads these itself; they are **not** committed):

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/keys/wobble-arena-upload.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="upload"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="…"
tools/build-android.sh          # .apk
tools/build-android.sh --aab    # .aab for Play Console
```

Create an upload keystore once (keep the file and passwords out of git):

```sh
keytool -genkey -v -keystore wobble-arena-upload.keystore -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

**Each Play upload needs a higher `versionCode`:** commit, or set `BUILD_NUMBER`.

## One-time setup

1. **Package name.** Preset uses `com.kedrosng.wobblearena` (same reverse-DNS id as the iOS bundle). Create the app in [Google Play Console](https://play.google.com/console) with that package name before the first upload.
2. **Export templates.** Godot → Editor → Manage Export Templates → Download for 4.7.2.
3. **JDK 17** on the machine that runs the script (`java -version`).
4. **Release keystore** (step above) before any Play upload. Prefer a dedicated upload key; Play App Signing holds the app signing key.
5. **Gradle template** only if you need `.aab` or Android plugins: Project → Install Android Build Template…. Re-install after upgrading Godot.

## Gotchas

- **ETC2/ASTC.** Same as iOS: `rendering/textures/vram_compression/import_etc2_astc` must stay on in `project.godot`, or mobile exports fail.
- **Presets need the structural keys.** Hand-written `[preset.N]` blocks must include every key Godot writes (`include_filter`, `patches`, `seed`, …). Missing *options* fall back to defaults. See `docs/BUILD_IOS.md`.
- **arm64 only.** The preset enables `architectures/arm64-v8a` only. That covers phones that can run the Mobile/Vulkan path; add `armeabi-v7a` only if you deliberately need old 32-bit devices.
- **`.aab` needs Gradle.** `--aab` flips `gradle_build/use_gradle_build` for that run and requires `godot/android/build` from the editor install step. Day-to-day device testing should use the default `.apk` path (no Gradle template).
- **Keystore secrets stay out of git.** Do not put passwords in `export_presets.cfg`. Godot keeps secrets in `.godot/export_credentials.cfg` (already under `godot/.godot/`, gitignored) or in the `GODOT_ANDROID_KEYSTORE_*` env vars.
- **Orientation.** `display/window/handheld/orientation=4` (sensor landscape) applies on Android the same as iOS.
- **Internet permission.** The preset enables `INTERNET` and `ACCESS_NETWORK_STATE` so online rooms work; `VIBRATE` is on for future haptics.
