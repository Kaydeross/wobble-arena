# Reset game

The deliberate "start from scratch" switch. **Settings › About › Reset game…**, the last row of the About section on the
title screen (`godot/ui/settings_screen.gd`). It is not offered in a match: a reset leaves the room / match, so it lives
on the title's Settings only. The row is bright red (the shared danger red `UiTheme.BAD`, white bold text) with a red
caption, *Deletes all progress and settings. Cannot be undone.*, so nobody tags it by accident.

Pressing it opens **"Reset everything?"** (`godot/ui/reset_dialog.gd`), a dimmed modal that says exactly what goes. The
safe answer, **Cancel**, is focused by default; Esc, controller B, the Android back gesture and a tap on the dark backdrop
all cancel. Nothing is deleted until the red **Reset everything** button is pressed. Then `ResetGame.wipe_all()`
(`godot/logic/reset_game.gd`) wipes the device and reloads the title scene as a new install.

This is irreversible **on this device**. Support may ask a player to use it to clear a broken local profile, a bad
setting or a stuck sign-in and start again.

## What it deletes

- **Profile** (`user://profile.json`, plus its `.bak` / `.tmp`): back to 500 coins, the free outfits and Wobble Dance,
  zeroed stats and records, fresh daily goals, a locked Construction DLC (Arcade bests / clears / Site Foreman hat gone),
  empty codes, no custom classes, the default look. `Save.wipe()` in `godot/autoload/save.gd`.
- **Preferences** (`user://settings.cfg`): every key back to its `DEFAULTS` value and the file removed, so the next run
  starts fresh (`Settings.wipe_all()` in `godot/autoload/settings.gd`). That includes the language, volumes, Kids mode,
  touch layout / button size / opacity, camera, graphics, game server address, the name, and the ads / store-cache keys
  (`entitlement_remove_ads`, `ads_matches_since`, `ads_last_shown_unix`, `session_start`).
- **Local sign-in**: the account session is signed out (`token`, `user`, `email`, `cloud_t`, `cloud_dirty`,
  `cloud_user`, any pending cloud push / conflict). The device is a guest again.
- **In-memory caches** that a scene reload would otherwise keep: the store entitlement cache (`Entitlements`), ad
  consent (`Ads`), the blocked-players list (`Safety`) and the remote launch config (`RemoteConfig` goes back to its
  bundled defaults; it keeps nothing on disk).
- Known game files only: `ResetGame` enumerates `user://` and removes the exact known profile file names. It never
  touches another file or a folder. The diagnostic soak-test CSVs in `user://soak/` are not progress and stay.

## What it does not delete

- **A cloud save on the account.** The account itself, its username / password / recovery code and the save stored on
  the server are not touched. The prompt says so: signing in again on this device can bring the cloud save back
  (a new install would do the same). Deleting the account is a separate action on the Account sheet.
- **Leaderboard entries** already submitted to the server.
- **Store purchases.** Clearing the local entitlement cache does not revoke a purchase; the store's restore path can
  grant it again. The account token lives in `settings.cfg` today (docs/ROADMAP.md Phase 5 moves it to the iOS
  Keychain); a future Keychain copy would have to be deleted by this reset too.
- **Engine / OS files** in `user://` (logs, shader caches, other apps' files).

## Tests and test-mode safety

`godot/tests/reset_test.gd` (runner `tools/test-reset-game.js`; add `"test:godot-reset": "node tools/test-reset-game.js"`
to the `package.json` scripts to get the usual `npm run test:godot-reset`) covers the wipe (DEFAULTS, fresh profile,
signed out, caches), the confirmation gate (row → prompt, nothing until the red button, Cancel / Back leave everything,
confirm wipes and records the title reload through `ResetGame.reload_hook`), the file removal on throwaway `user://`
names, and the guard below.

Every `tools/test-*.js` run passes `--no-save`. `Settings.persist`, `Save.persist` and `ResetGame.persist` are then all
false: the wipe resets memory and deletes **no file**, so a test can never destroy the developer's real save. Tests that
need the file removal set `ResetGame.persist = true` only with `ResetGame.files` replaced by throwaway names (never the
real profile paths), and the real `settings.cfg` / `profile.json` are only read before and after to prove they were not
touched. The scene reload is replaced by `ResetGame.reload_hook` in tests.

## Files

- `godot/logic/reset_game.gd` — the wipe itself (`ResetGame`).
- `godot/ui/reset_dialog.gd` — the "Reset everything?" prompt (`ResetDialog`).
- `godot/ui/settings_screen.gd` — the About row and the dialog wiring.
- `godot/autoload/settings.gd` (`wipe_all`), `godot/autoload/save.gd` (`wipe`) — the in-memory reset helpers.
- `godot/tests/reset_test.gd`, `tools/test-reset-game.js` — the tests.
