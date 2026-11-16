# Wobbler Arena — Revised Execution Plan (soft launch first)

## Context

The original plan (v0.5.0 → v0.6.0 → v1.0) puts "Soft Launch" at the end of Horizon 2, behind a 3D podium, unified online combat, ledge cling, throwable rubble and K.O. clip export. A code audit shows two problems with that:

1. **The real launch blockers are mostly not in the plan.** Production server (shipped URL is a home NAS behind Tailscale Funnel), analytics and crash visibility (none exist), a developer unlock code that ships in release builds, a never-run physical-device soak, and store-listing/review items.
2. **Several work packages rest on wrong facts** (listed under "Corrections" below), and the largest ones (clip export, ledge cling, net_zones) are greenfield with netcode and bot implications.

Decisions taken with the owner: **iOS first**, **no ads/IAP SDK in build 1 (ads arrive in 0.5.1)**, **online on, moved to a paid project-owned host**.

Outcome: v0.5.0 becomes the soft-launch build with a short critical path; monetization is a fast-follow; viral/clip mechanics wait for soft-launch data.

## Corrections to the original plan (verified against code)

| Original claim | Actual state |
|---|---|
| `PropDebris` visuals are missing; instantiate in `World.load_map()` | Implemented and tested. Created lazily in `world.gd:554-557`, `piece_count()` exists, asserted in `destruct_test.gd:937-941`. Destructibles only run **offline** and are off in practice/sandbox/construction/Arcade/online (`world.gd:244`) — a "missing debris" report is most likely gating, not a bug. |
| `Settings` "defaults" | Const is `DEFAULTS`; toggle helper is `settings_screen.gd:315 _toggle()`. |
| Toasts stack/overlap; control hints persist | `hud.gd:297 toast()` overwrites one label (no stacking). Only persistent hint is PC-only and already conditional. Short keys `"Crate incoming: %s!"` and `"The arena is growing!"` already exist in i18n. |
| Lock the name field to stop spoofing | Server never compares the hello name to `ws.user` (`server.js:202`); a UI lock is cosmetic. |
| Add ping loop to HostSession | `HostSession` extends `GuestSession` (which has `ping_ms`); server already answers `{"op":"ping"}` (`server.js:200`). Only a UI consumer is missing. |
| Room-code LineEdit in `main.gd` | It is in `godot/scenes/main.tscn:243-249` (`max_length = 16`). 4 digits with 300 rooms = ~3% hit rate per guess and there is **no join throttle**. |
| "Chaos 5v5" mode; CTF featured everywhere | Mode id is `chaos`; `ctf` is offline-only. |
| Default `net_zones = true` in host_session/net_match | `net_zones` exists only in `combat.gd:50,240` and is never set outside tests. No rule-snap flag, no mid-join handling; guests compute damage attacker-side, so a mismatch desyncs damage. |
| `Ads.maybe_show_interstitial()` | Does not exist. `Ads.show_interstitial()` already applies all gating (`ads.gd:34-62`). Nothing calls `Ads.set_consent`. |
| `Sfx.play_at` upgrade; `Audio` autoload | Autoload is `Sfx`; no `play_at`; 12 non-spatial players. New work, not an upgrade. |
| KillCam retains 5 s; add LAUNCHED badge | Buffer is 4 s @ 30 Hz, replays 1.4 s, offline only. Badge already exists (`hud.gd:480`). No capture/share code exists anywhere. |
| Thermal readout wiring | Returns "n/a" unless a native `WobbleThermal` plugin exists; none ships. |
| `i18n --check` covers CJK font subset | It does not check glyph coverage at all. |
| `npm test` as the gate | Runs no Godot test. Parity suites need Godot at `/Applications/Godot.app` (not CI-portable). |
| Dev hash in `dlc_unlock.gd`, `server_info.gd` | Only `dlc_unlock.gd`; reachable by 7 taps on the version line, ungated in release. `server_info.gd` is not a backdoor. |
| 12-player online Chaos | Relay room cap is 8 (`server.js:26`). |
| `arcade_best` per-field merge; `dlc_construction` entitlement | `arcade_best` is not in the save blob (lives in `/api/rank`); the DLC is bought with 1500 coins. |

## Standing rules (amended)

1. **Parity**: gate Godot-only mechanics behind `Combat.tuning_active()`. Never hand-edit `shared/*.json` or the synced `godot/data/*.json`; Godot-only content goes in `godot/data/extra/` or a pack.
2. **RNG**: unchanged — no `combat.rng.next()` in UI/visual/non-parity code.
3. **i18n**: all 5 languages in `godot/i18n/src/*.json`, `node tools/i18n.js`, `npm run i18n -- --check`. Reuse existing keys first. New CJK glyphs require rerunning `tools/subset-fonts.py` (WP L1 adds an automated coverage check).
4. **Test gate**: `npm test` **plus** each WP's listed `test:godot-*` suites, run by the lead in a clean state — never a worker's self-report.
5. **No dead buttons**: provider-dependent UI is hidden unless the provider is registered and `Ads.can_request(placement)` is true.
6. **Process**: each WP branches from freshly fetched `origin/main`, one draft PR each. Implementation goes to Sonnet subagents (no agy on this project); lead reviews diffs and runs gates. Screenshots are rendered fresh from the latest build.

---

## v0.5.0 — Soft-launch build 1 (iOS, no ad SDK, online on)

Order: **L1 → L2 → (L3 ∥ L4) → L5**. Track P runs in parallel from day 1 and does not block the build.

### WP L1 — Release hardening (small)
- `godot/dlc/construction/dlc_unlock.gd`: `redeem_with()` rejects the dev hash when `OS.has_feature("release")`; hide the 7-tap entry in `godot/ui/settings_screen.gd:515-521`. Keep a test seam so the existing unlock tests still run in debug.
- `godot/ui/fps_overlay.gd:86`: F3 overlay disabled in release.
- i18n glyph check: `tools/subset-fonts.py` writes a checked-in character list; `tools/i18n.js --check` fails if `strings.json` contains a CJK character outside it.
- Fix stale docs: `docs/ROADMAP.md:21,23`, `docs/BUILD_ANDROID.md` version note, `docs/I18N.md:37`.
- Release convention: `git tag v0.4.0 8962b9f` (owner confirms), then tag every release.
- **Verify**: `npm test && npm run test:godot-construction-data && npm run test:godot-settings && npm run test:godot-ui`

### WP L2 — Production server, verified names, room codes, ping badge (medium)
Owner actions (cannot be done by an agent): provision an always-on paid instance **in the region nearest the chosen soft-launch markets**, Upstash Redis, a project domain with TLS; set `UPSTASH_REDIS_REST_URL/TOKEN`; confirm the privacy page at the URL in `settings_screen.gd:28` is live and add a Terms link.
- `godot/data/extra/server.json` → new `wss://` URL; migrate existing accounts from the NAS `data/db.json` into Upstash (one-off script under `tools/`).
- **Server-enforced names** (`server.js`): attach `ws.user` to the `peer` event / relayed `hello`; `host_session.gd` (`_hello`, ~`:455-494`) prefers the server-stamped name over the client-sent one. `main.gd:531-539` name field becomes read-only while signed in. Servers running `REQUIRE_LOGIN=0` (headless tests, `join_test.gd`) send no stamp and fall back to the hello name.
- **Join throttle** (`server.js:215-221`): per-IP and per-account failed-join counter (e.g. 10 per minute → `nojoin: slow`).
- **4-digit codes** (only after the throttle lands): `newCode()` (`server.js:164`) returns a zero-padded 4-digit code for private rooms; public rooms keep their `r<n>` ids. Update `tools/test-server.js:16`, `tools/test-net-host.js:609`, `docs/PROTOCOL.md:84`, `godot/scenes/main.tscn:243-249` (`max_length = 4`, numeric keyboard), and the "5-letter code" copy in `public/index.html:1292,9893` (then `npm run content` + `node tools/i18n.js`). Trade-off accepted: even throttled, 4 digits is guessable in minutes; 6 digits is the safer variant if strangers entering private rooms matters.
- **Ping badge**: new small control modelled on `godot/ui/server_badge.gd`, shown top-left when `world.session != null`. Guests show `GuestSession.ping_ms`; the host measures relay RTT with `{"op":"ping"}` via `net_client.gd`. Green ≤ 60, amber 61–140, coral > 140. Kept out of `hud.gd` to avoid conflicts with L4.
- **Verify**: `npm test && npm run test:godot-host && npm run test:godot-account && npm run test:godot-ui && npm run test:crossplay-web`

### WP L3 — First-party analytics and crash visibility (medium)
No third-party SDK, so the privacy manifest and ATT status stay unchanged.
- New `godot/autoload/analytics.gd` (registered in `project.godot`): batched POST to a new `/api/event` (own module, e.g. `events.js`, mounted from `server.js`; rate-limited; anonymous random install id; no PII). Honour the existing but unused `analytics` flag in `remote_config.gd:26,110`.
- Events: `install`, `session_start`, `ftue_step` (intro cards, first match start/finish), `match_start`/`match_end` (mode, map, online, result, seconds), `coins_spent`, `online_join_result`, `error`. Hook beside the existing `Ads.on_match_*` calls at `world.gd:184,214,1149,1382` and in `main.gd:181`.
- Script errors: forward deduplicated errors through a custom logger (`OS.add_logger`, verify against the 4.7 docs). Native crashes for build 1 come from Xcode Organizer / TestFlight.
- `tools/report-metrics.js`: D1/D3/D7 retention, sessions per day, session length, matches per session, FTUE funnel.
- Update the privacy policy and the App Store privacy label to declare usage data not linked to identity.
- **Verify**: `npm test` (extend `tools/test-server.js`), `npm run test:godot-services && npm run test:godot-remote-config`

### WP L4 — First-five-minutes UX (medium)
- **Crosshair toggle**: `DEFAULTS["crosshair"] = true` (`settings.gd`), `_toggle("crosshair", …)` beside `settings_screen.gd:164-203`, gate `_draw_cross` (`hud.gd:557`) while still drawing the charge arc when `_charge_k > 0`.
- **Toasts**: switch `pickups.gd:102,135` and `mode_rules.gd:412` to the existing short keys; add one new key for `stage_events.gd:176` ("Load Test!"). Sweep remaining in-match toasts over ~24 characters. No queue work — overwrite is already non-overlapping. Drop the "auto-hide hints after 8 s" item.
- **Mode picker**: add a `featured` list to `godot/data/extra/wizard.json` (`classic`, `chaos`, `sudden`, `ctf`); `_build_mode` (`setup_wizard.gd:666-690`) renders featured cards first and a "More modes (%d)" expander with a computed count. Filter featured entries by availability (CTF is offline-only) and badge `RemoteConfig.featured_mode`.
- **Winnable first fight**: on the first-ever session, after `intro_cards.gd`, go straight into an easy offline bot match via `godot/ui/quick_play.gd` instead of the menu.
- **Results moment (2D)**: coin count-up tween and a next-unlock progress bar in `godot/ui/results_rewards.gd` (text line exists at `:73`); winner plays an emote via `wobbler.gd:1026 play_emote()`. The 3D podium is deferred.
- **Debris**: no code change. Reproduce on device in offline Classic with destructibles on; only if it fails there, debug `prop_debris.gd` tier budgets with a fresh screenshot.
- **Verify**: `npm test && npm run i18n -- --check && npm run test:godot-ui && npm run test:godot-settings && npm run test:godot-world && npm run test:godot-modes`

### WP L5 — Device gate and submission (owner-led)
- Bump to 0.5.0 through the single version source (`npm run check:version`), `godot/data/extra/news.json` entry in 6 languages, tag `v0.5.0`.
- iPhone 12: 15-minute `SoakRun`; pull `user://soak/*.csv` with Xcode's "Download Container"; read thermal state from Xcode (in-app readout stays "n/a"); record results in `docs/GRAPHICS.md`.
- Test matrix from `docs/STORE_READINESS_PLAN.md:117`: clean install, no network, lost session, forced update (`minimum_version`), sign-up, account deletion, report/block.
- App Store Connect: fresh screenshots, age rating, privacy label, support URL, export-compliance flag, and a **demo account for App Review** (online requires login).
- Release to 2–3 small markets near the relay region.
- Suggested gates before 0.5.1 spend: crash-free sessions ≥ 99%, first match finished ≥ 70% of installs, D1 ≥ 30%, D7 ≥ 8%.

### Track P — Native plugin spike (parallel, time-boxed, does not block build 1)
Throwaway branch proving on a real iPhone, with Godot 4.7.2: an AdMob plugin with UMP + ATT (candidate named in `docs/IMPROVEMENT_PLAN.md:158`) and a StoreKit 2 plugin. Output: a go/no-go note and the exact export/privacy-manifest changes needed.

---

## v0.5.1 — Monetization fast-follow (original WP 0.6-C, corrected)
- Register real providers behind `Ads.set_provider` / `Entitlements.set_provider`; drive `Ads.set_consent` from the UMP/ATT flow; add `NSUserTrackingUsageDescription`, SKAdNetwork ids, updated privacy manifest and store privacy label.
- Call `Ads.show_interstitial()` on match exit — do not re-implement session/online/cooldown gating.
- Placements in order: Double Coins on results, then 2x Daily Bonus (`goals_screen.gd`), then Arcade Continue (`arcade_panels.gd`). Turn on per market via `ads.enabled` / `rewarded_enabled` in remote config.
- Remove Ads + Restore Purchases in `locker.gd`/`settings_screen.gd`, verified on-device with StoreKit 2 (`Entitlements.grant_verified`); wire the unused `purchases` kill switch. Server receipt verification waits for 1.0-A.
- Pause `Sfx` and `World` during fullscreen ads. Mock provider in `godot/tests/services_test.gd`.
- Android track starts here: Gradle build template, keystore, `.aab`, Play internal testing, Android device soak.
- **Verify**: `npm test && npm run test:godot-services && npm run test:godot-ui`

## v0.6 — After soft-launch data (re-prioritise against the funnel)
- **Unified online combat**, respecified: host sets `combat.net_zones` at match start only when `HostSession.web_guests()` is empty; flag travels in `rule_snap`; a zones room refuses web joiners through the existing refusal path instead of falling back mid-match. Tests in `net_modes_host.gd` and `test:crossplay-web`.
- **3D winner podium**.
- **Share**: start with a shareable result-card image (viewport capture + share plugin); video clips only if the image share shows uptake.
- **Ledge cling / rubble**: each needs bot support (`bot_brain.gd` edge probe, `BOT_FIRE`), new snapshot fields, and rubble data in `godot/data/extra/`.
- **Spatial audio** (`Sfx.play_at`, new), **thermal plugin + CSV export**.

## v1.0 — Unchanged in intent, with these corrections
- Server wallet (1.0-A) must land **before any coin or premium-currency sale**; fix the merge spec per the corrections table.
- Compact netcode (1.0-B): raise the 8-player room cap as part of the work; today there is no interpolation buffer, only ≤ 0.2 s extrapolation. COOP/COEP headers are only needed if the Web export goes threaded (the preset is single-thread).
- Consider pulling legacy-web retirement earlier: it removes ~34 `tuning_active()` branches and the non-portable parity suites, the largest ongoing tax on every WP above.
- Pack #2 (1.0-C) as written.

## End-to-end verification for build 1
1. Lead runs every WP gate above from a clean checkout of `origin/main` after merges.
2. Two-device online session against the new host: create room (4-digit code), join, verify stamped names and ping badge, host drop → rehost.
3. Wrong-code join loop confirms the throttle; `tools/report-metrics.js` shows events from the TestFlight build.
4. Release-export check: 7-tap dev code and F3 overlay are inert.
5. iPhone 12 soak recorded in `docs/GRAPHICS.md`; TestFlight external build passes the L5 matrix.
