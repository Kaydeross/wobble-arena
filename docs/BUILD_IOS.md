# Building Wobble Arena for iOS

`tools/build-ios.sh` does everything from the command line: Godot export → Xcode project → signed archive → App Store `.ipa`. It does **not** upload.

## Requirements

- macOS with Xcode (tested with Xcode 27.2).
- Godot **4.7.2.stable** at `/Applications/Godot.app` (or set `GODOT=`), with export templates installed (`~/Library/Application Support/Godot/export_templates/4.7.2.stable/ios.zip`).
- For signing: the keychain needs the team's certificates ("Apple Development" and "Apple Distribution: … (663Q47AS93)"), and Xcode needs a way to create provisioning profiles. See [One-time setup](#one-time-setup).

## Usage

```sh
tools/build-ios.sh                 # export + archive + .ipa  -> build/ios/ipa/WobbleArena.ipa
tools/build-ios.sh --simulator     # export + unsigned build, install/launch in a simulator, screenshot -> build/ios/simulator.png
tools/build-ios.sh --export-only   # only the Godot export      -> build/ios/xcode/WobbleArena.xcodeproj
tools/build-ios.sh --skip-export   # reuse the last export (e.g. after fixing signing)
BUILD_NUMBER=60 tools/build-ios.sh # override the build number (default: git commit count)
SIM_DEVICE="iPhone 17e" tools/build-ios.sh --simulator
```

Each stage overwrites its own output under `build/ios/` (gitignored), so you can rerun any step. Logs go to `build/ios/logs/`.

### What the stages do

1. **Checks:** Godot version, iOS template, and `xcodebuild`.
2. **Build info:** writes `godot/build_info.cfg` (version, build number, commit; gitignored). The main scene shows it as `v0.1.0  build N (commit)`, so you can tell which build is on a device.
3. **Import + export:** `godot --headless --import`, then `--export-release "iOS"` using the committed `godot/export_presets.cfg`.
4. **Archive:** `xcodebuild archive` with automatic signing for team `663Q47AS93` and `-allowProvisioningUpdates`. It archives with the Apple Development identity, which automatic signing requires. Version and build number are passed as `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
5. **IPA:** `xcodebuild -exportArchive` with `method = app-store-connect`. This re-signs with **Apple Distribution** and the "iOS Team Store Provisioning Profile" (with `beta-reports-active`, so the build is TestFlight-ready). The script prints the signing summary.

### Upload (manual for now)

```sh
xcrun altool --upload-app -f build/ios/ipa/WobbleArena.ipa -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

`altool` looks for the key in `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`. You can also drag the `.ipa` into Transporter.app. **Each upload needs a higher build number**: commit, or set `BUILD_NUMBER`.

## One-time setup

Already done on this Mac: Xcode is signed in to the team, and the first run registered the App ID `com.kedrosng.wobblearena` and created the profiles automatically. Still to do before TestFlight:

1. **App Store Connect app record.** Go to appstoreconnect.apple.com → Apps → "+" → New App: platform iOS, name "Wobble Arena", bundle ID `com.kedrosng.wobblearena` (it should already be in the list), and a SKU of your choice.
2. **App Store Connect API key** (for uploads, and for CI signing without an Xcode login). Go to Users and Access → Integrations → App Store Connect API → generate a key with the **App Manager** role (Admin if CI should also create profiles). Save `AuthKey_<KEY_ID>.p8` to `~/.appstoreconnect/private_keys/` and note the Key ID and Issuer ID. To sign with it instead of the Xcode account:
   `ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXX.p8 ASC_KEY_ID=XXX ASC_ISSUER_ID=YYY tools/build-ios.sh`
3. **Export compliance** is pre-answered: Godot's Info.plist sets `ITSAppUsesNonExemptEncryption = false`. Revisit this if we add custom encryption. Standard HTTPS/WSS is exempt.
4. In TestFlight, add yourself as an internal tester once the first build has processed.

If signing ever fails, the script prints what is missing. Usually you need one of these: an Xcode account login (Xcode → Settings → Accounts), an API key (step 2), or a manually created App ID plus an "App Store Connect" distribution profile at developer.apple.com → Certificates, IDs & Profiles.

## Gotchas found while setting this up

- **Empty "configuration errors" from the iOS export.** Godot refuses the iOS export without listing a reason when `rendering/textures/vram_compression/import_etc2_astc` is off. It is now set in `project.godot`.
- **Presets need the full key set.** Hand-written presets must include every `[preset.N]` key Godot writes (`include_filter`, `exclude_filter`, `export_path`, `patches`, `encryption_*`, `seed`, …), or Godot prints `Couldn't find the given section … key "include_filter"`. Missing *options* (`[preset.N.options]`) fall back to defaults. All four presets (iOS, Web, macOS, Windows Desktop) export headless.
- **Orientation:** `display/window/handheld/orientation` was `1` (portrait). It is now `4` (sensor landscape), so the Info.plist allows landscape left and right only.
- **Simulator limits.** The official 4.7.2 template has only an **x86_64** simulator library, and iOS 26+ simulators no longer run x86_64 apps. `--simulator` therefore builds the arm64 device binary, retags it as an iOS Simulator binary (`vtool`) and ad-hoc signs it. The app installs, launches and runs its scripts. However, the simulator's Metal GPU lacks image cube arrays, so the Mobile renderer stops with an "Apple GPU does not support…" alert. The Compatibility renderer (`--rendering-method gl_compatibility`) crashes there too, because the simulator's GLES framebuffer is incomplete. **Use a real device to look at the game.** In Xcode, open `build/ios/xcode/WobbleArena.xcodeproj` with the device plugged in and press Run, or install the TestFlight build. A full simulator build would need custom Godot templates compiled with an arm64 simulator slice.
- **iCloud Desktop:** the repository lives in an iCloud-synced folder, which adds extended attributes that `codesign` rejects. The simulator app is therefore staged in `$TMPDIR`.
- The camera, microphone and photo usage strings are filled in. Godot links those frameworks, and App Store validation flags empty purpose strings.
