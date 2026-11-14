# Wobblers Arena: improvement and store-readiness plan

_Written 2026-11-14 against `main` at `4ca46bf` (0.3.0). Section 0 and the first part of stages A and B are now built (melee bosses, the stuck FIRE fix, haptics and audio, frame cap and render scale, the launch-service policy, account safety and CI); the execution order, exit criteria and a live status table are in [STORE_READINESS_PLAN.md](STORE_READINESS_PLAN.md). Pick a work package, check the cited files still match, and keep each change in its own pull request._

## Context

You asked for a plan covering four things: what to improve (VFX, sound, combat, weapons), how to future-proof the game for the App Store and purchases, optimisation and an onward roadmap, and how to make the game more attractive.

**Your decisions so far**

- **Money model:** free with ads at launch, a paid option with no ads, and later a subscription or paid content (DLC, coin packs).
- **Audience:** general audience, in the normal Games category.
- **Next:** the two fixes in section 0 (melee bosses, stuck FIRE button) came first and are built; `docs/STORE_READINESS_PLAN.md` tracks the rest.

**What was audited.** The latest `main`, commit `4ca46bf` (2026-11-14), version 0.3.0 in `godot/project.godot:8`, which is 24 commits past the 0.3.0 release commit. Audits covered VFX and audio, monetisation and store readiness, and performance and code health; I read the combat and weapon code and data myself. `npm run test:godot-perf` passes on this code with Godot 4.7.2. The graphics benchmark was not re-run.

**What is stale.** The code is 0.3.0, but these are not:

- Every benchmark number in `docs/GRAPHICS.md:79-99` and `:270-282` predates the #105 / #107 / #110 VFX changes and names no build. Treat them as unverified.
- `docs/ROADMAP.md:21` and the README badge still describe the 0.2.0 and 0.1.0 TestFlight trains.
- `godot/export_presets.cfg:204` has Android `version/name="0.1.0"`, and `tools/build-ios.sh:58` and `tools/build-android.sh:119` default `VERSION` to 0.1.0.

**The four findings that shape the plan**

1. **Big moments are silent and unfelt.** No haptics anywhere, and no sound for K.O., ring-out, respawn, countdown, or win and lose. 30 weapons share about 5 fire sounds, 2 hit sounds and one impact effect.
2. **Combat has no defensive move and classes are stat blocks.** There is no block, parry, combo or charged melee, and the 11 classes differ only by multipliers.
3. **The economy is client-authoritative.** Coins and owned items live in an unsigned `user://profile.json` that the server stores unchecked. That is acceptable for an ads-only launch and must change before coins or DLC are sold.
4. **Nothing has been measured on a phone.** GPU time, heat and load hitches on an iPhone are unknown, and there is no frame-rate cap or render-scale setting.

The Phase 5 to 7 outline in `docs/ROADMAP.md` still stands. This plan fills it in and re-orders it around the ads-first model.

---

## 0. Two fixes requested by the owner (first in line)

### Construction Arcade: bosses fight with melee tools and can only pick guns up

What the code does today (`godot/data/extra/construction/stages.json`, `godot/dlc/construction/arcade_manager.gd`):

| Boss | Starts with | Type |
|---|---|---|
| Engineer | Nail Gun | gun |
| Designer | Spirit Level | melee |
| Supervisor | Angle Grinder | gun (flame style) |
| Project Manager | Cone Launcher | thrown |
| The Client | Jackhammer | gun (punch style) |

Why the Supervisor is too strong:

- The Angle Grinder deals 2.2 damage every 0.06 s, about 37 a second before multipliers, out to 6.5 m. It hits the whole body, so there is no leg or arm reduction, and it adds a burn.
- The Supervisor's damage is x1.2, and each of the two boss phases multiplies it by 1.2 again (`PHASE_DMG`, `arcade_manager.gd:31`).
- `keep_kit` refills every enemy's tool ammo every 0.5 s (`arcade_manager.gd:412-423`), so the stream never stops and there is no reload window to punish.

Changes:

| Change | Files |
|---|---|
| Every boss starts with a melee tool (set you approved): Engineer Cordless Drill, Designer Spirit Level (unchanged), Supervisor Pipe Wrench, Project Manager Tape Measure, The Client Giant Mallet | `data/extra/construction/stages.json` (`weapon` per boss) |
| Guns and thrown tools (Nail Gun, Angle Grinder, Jackhammer, Cone Launcher, Cement Bucket) arrive only in crates on boss stages, for you and the boss alike | `dlc/construction/stage_events.gd`, `godot/logic/pickups.gd` (`bot_wants`), `godot/data/drops.json` overlay for the DLC |
| A boss may walk to a gun crate while holding its melee tool. Bots only take weapon crates when empty-handed today (`godot/logic/bot_brain.gd:13`) | `logic/pickups.gd`, `logic/bot_brain.gd:235-250` |
| `keep_kit` keeps only the melee tool topped up. A picked-up gun runs dry and the boss goes back to melee | `arcade_manager.gd:412-423` |
| The Client's "change request" swap picks from melee tools only. Its pool includes guns today | `stage_events.gd:48-50,281-289` |
| Tone down the Angle Grinder as a pickup (lower damage per tick, shorter reach, limited fuel) | `data/extra/construction/weapons.json` |
| Re-run the Arcade balance test and retune boss health and speed, since melee bosses are easier to keep away from | `godot/tests/arcade_balance.gd`, `stages.json` `difficulties` |
| Update the tests and the DLC doc that name the old boss weapons, and add a test that no boss starts with a non-melee tool and that a boss can take a gun crate | `godot/tests/arcade_test.gd:222,436,489`, `docs/CONSTRUCTION_DLC.md:27-31` |

### The attack button that keeps firing after release

You see this on the iPhone's on-screen FIRE button. I have not reproduced it, but `godot/input/touch_controls.gd` has three ways for FIRE to stay held, and one of them makes it permanent:

1. **A missed release can never be cleared by tapping FIRE again.** `_touch_down` skips any button already marked as down (`:238-239`), so once FIRE is stuck, pressing it again does nothing. Only pausing clears it (`release_all`, `:351`).
2. **A finger number that is reused overwrites the old touch without releasing it.** `_touch[i] = …` at `:240`, `:255`, `:261` and `:265` replaces whatever that finger held. If iOS drops or recycles a touch while FIRE is held, the FIRE hold is orphaned.
3. **Nothing lets go of the buttons when the app loses focus.** Only a full background (`NOTIFICATION_APPLICATION_PAUSED`) is handled, in `godot/world/world.gd:1047-1049`. Pulling down Control Centre or a notification banner takes the touches away without that event.

Fix:

| Change | Files |
|---|---|
| In `_touch_down`, release whatever the same finger was holding before taking the new touch | `input/touch_controls.gd:225` |
| A press on a button that is already down takes it over, and each frame any held button whose finger is gone is released | `touch_controls.gd:238`, `_process` at `:384` |
| Call `release_all()` on focus loss and on cancelled touches (`InputEventScreenTouch.canceled`) | `touch_controls.gd:155`, new `_notification` |
| A regression test that replays the three cases with scripted touches and checks FIRE is not held afterwards | new `godot/tests/touch_test.gd`, `tools/` runner beside `test-godot-flow.js` |
| A line in the performance readout listing the actions held per input source, to catch it on device if it happens again | `godot/ui/perf_overlay.gd`, `input/input_state.gd` |

The mouse path (`input/player_input.gd:108-122`) polls the button every frame, so it cannot stay stuck in the same way.

---

## 1. What to improve

### VFX

| Item | Why | Size | Files |
|---|---|---|---|
| Per-element switches for the disputed #105 look (hit vignette, polygon rings, bright ribbon cores, hit sway), then decide each on device | #105 was reverted because it "was not liked on device", then restored in #110 with no stated fix. Deciding per element ends the revert and restore cycle | S | `godot/world/fx.gd`, `trails.gd`, `godot/actors/fighter_juice.gd`, `godot/shaders/hit_vignette.gdshader`, `fx_ring.gdshader`, `godot/autoload/settings.gd` |
| Effects for moments that have none: respawn, pickup collect, ring-out and fall, match start countdown, win celebration | `respawn` is emitted at `logic/combat.gd:390` with no handler. The K.O. effect returns early for falls at `fx.gd:433`. Crates vanish with only a toast | M | `fx.gd:356-391`, `godot/world/world.gd` |
| Impact look per weapon family (blunt, sharp, bullet, explosive, elemental) | `impact()` and `sparks()` only take colour, damage and force, so a hammer, a spatula and a bullet look the same | M | `godot/data/extra/weapon_tuning.json` (new `impact` field), `fx.gd:203,234` |
| Fighter state readouts: low health, burn, stun, wind-up warning | Only the HUD bar shows low health, and status effects have no visual on the fighter | M | `fx.gd`, `godot/actors/wobbler.gd` |
| Camera punch on heavy hits and K.O.s | The camera only shakes | S | `godot/world/follow_camera.gd` |
| Chaos events and hazards get a visual, not only a banner | `world.gd:87-93` shows text and a toast | M | `fx.gd`, `world.gd`, `godot/logic/arena_dyn.gd` |
| Depth sorting for see-through particles | Open in the roadmap. Smoke is spawned before fire as a workaround | M | `fx.gd:508-634` |

### Sound and haptics

| Item | Why | Size | Files |
|---|---|---|---|
| **Haptics**: light on hit, medium on being hit, heavy on K.O. and explosions, with a Settings switch | None exist. On a phone this is the cheapest large gain in impact feel | S | new helper called from the `fx.gd` hit and K.O. handlers, `settings.gd`, `godot/ui/settings_screen.gd` |
| Pitch and volume variation on every play, and priority so long sounds are not cut | Every play is the same sample at full volume. A 1.67 s boom can be cut by rapid fire in the 12-voice pool | S | `godot/autoload/audio.gd:43-51` |
| Render the sounds the synth already defines: jump, step, land, dash, hover, tick | Only the `NAMES` list needs extending | S | `tools/render-sfx.js:22-26`, `audio.gd:8-9` |
| UI sounds everywhere, using the unused `pop` | Only 5 `Sfx.play` calls exist outside a match | S | `godot/ui/juicy_button.gd` |
| Big-moment audio: K.O. sting, fall whistle, respawn, 3-2-1 countdown, win and lose stingers, results music, low-health pulse | All silent, and match end also stops the music (`music.gd:145`) | M | `tools/render-sfx.js`, `tools/render-music.js`, `audio.gd:56-89`, `godot/autoload/music.gd` |
| Distance and left-right cues | All audio is 2D. Compute volume and pan from the camera in `Sfx.play` | M | `audio.gd` |
| Fire and hit sounds per weapon family | 10 guns share `shot`. Melee uses only `clink` or `whack` | M | `hitSfx` in the weapon data, `audio.gd` |
| Character voice: short goofy squeaks and grunts per class | The biggest missing piece of personality for a party brawler | M | new synth recipes, `audio.gd` |
| Music ducking on K.O.s and explosions, and a second match music family | One menu track and one match family for 34 arenas | M | `music.gd`, `tools/render-music.js` |

All audio is synthesised by `tools/render-*.js`. That carries no licensing risk but caps quality. If the synth cannot make impacts land, a small recorded pack for impacts and voice is where to spend money.

### Combat

What exists: move, jump, sprint, crouch, fire, aim, kick, shove, dash (with dash gear), air recovery, weapon swap, reload, emote. Health is 200 with knockback, body-zone damage offline, and shield and rage pick-ups. A K.O. comes from zero health or a ring-out.

| Item | Why | Size | Files |
|---|---|---|---|
| **A timed defence on the existing shove**: a shove within a short window of an incoming melee hit deflects it and staggers the attacker | No block, parry or dodge exists (no match in `logic/combat.gd`). Reusing shove needs no fifth touch button | M | `logic/combat.gd:606` (`shove`), `:736` (`melee_sweep`), `logic/bot_brain.gd` |
| **One signature move per class** on a cooldown (for example a Bruiser ground pound, a Scamp roll, a Zorp hover) | Classes are multipliers only (`data/classes.json`). Paid classes then become sidegrades instead of better stats. The charge-pool system already exists | L | `logic/skills.gd` (`skill_n`, `skill_cd`), `logic/class_stats.gd`, `godot/input/touch_controls.gd` context button |
| **Melee variety**: tap for a light swing, hold for a heavy one, and a swing shape per weapon (overhead, thrust, wide sweep) | All 7 melee weapons use one swing model with different numbers | M | `combat.gd:644-736`, `data/weapons.json` fields via the content export |
| **Status effects** that weapons apply: burn from the Flamethrower, chill from the Snowball Cannon, shock from Live Wire | Only the net trap changes a fighter's state today | M | `combat.gd:188` (`hit`), `:319` (`timers`), `logic/fighter_state.gd` |
| **Touch aiming help**: an aim-assist strength setting and optional auto-fire when the crosshair is on a target | Precise weapons (Sniper, bow) are hard on a phone. Player assist is a fixed 0.8 (`Weapons.PLAYER_ASSIST`) and the toggle is an open roadmap item | S-M | `logic/weapons.gd`, `settings.gd`, `touch_controls.gd` |
| **Same rules online and offline** | Online rooms use the old web numbers; offline uses the tuned overlay and body zones (`docs/DAMAGE.md:33-43`). Players get two different games | S once web guests are gone | `Combat.net_zones`, `net/host_session.gd`, protocol version |
| Throwable props and more arena interaction | Fits the ragdoll comedy and gives new K.O. stories | L | `logic/pickups.gd`, `logic/weapons.gd`, `world/map_builder.gd` |

**Parity note.** New mechanics should sit behind `Combat.tuning_active()` like the existing overlay, so the JS parity tests keep passing until the three.js game is retired.

### Weapons

30 weapons: 10 guns, 7 melee, 13 others (launchers, thrown, bow, net, blower), plus Construction-only tools.

| Item | Why | Size | Files |
|---|---|---|---|
| **A balance table from bots-only matches**: K.O.s, damage and pick rate per weapon over a few hundred simulated matches | Tuning is hand-done per complaint (`docs/DAMAGE.md:47-63`). The bots-only match harness and an Arcade balance test already exist | S-M | `godot/tests/bots_smoke_test.gd`, `godot/tests/arcade_balance.gd` as the pattern |
| Review the outliers the table will confirm | Meteor Launcher (115 damage, 8.5 radius), Sniper head hits (84 of 200 health), and the utility weapons with 0 damage (Spring Glove, Net Gun, Air Blower) that need a clear job | S | `data/extra/weapon_tuning.json` |
| Weapon mastery and skins | A progression track per weapon that is cosmetic only, so it can be sold later without affecting balance | M | `autoload/save.gd`, `ui/locker.gd`, `actors/weapon_models.gd` |
| A starting weapon pick before the match | Weapons only come from crates and racks today. One chosen starter adds a decision and a reason to learn weapons | M | `ui/setup_wizard.gd`, `logic/match_sim.gd` |
| A content-pack format based on the Construction DLC | Its weapons, stages and modes already live apart (`data/extra/construction/`, `godot/dlc/construction/`). A manifest per pack makes each future DLC the same shape | M | `autoload/content.gd`, `logic/extra_weapons.gd`, `dlc/construction/dlc_unlock.gd` |

---

## 2. Future-proofing for the App Store and purchases

The plan follows your model in three steps. Each step lists only what it needs, so launch is not blocked by work that only matters for later purchases.

### Step 1: launch, free with ads

| Change | Why | Size |
|---|---|---|
| **An `Ads` autoload** with one policy function for "may this ad show now?", and no ads on PC and web | Keeps the ad SDK swappable and the rules in one place | M |
| **AdMob through the Poing Studios Godot plugin**, tested on a real iPhone first | It covers iOS and Android and includes Google's consent form. One developer reported an App Review rejection because the tracking prompt did not appear, so prove it on device before building on it | M |
| **Placements:** rewarded ads on the results screen (double coins), on the daily bonus and for an Arcade continue; a capped ad between matches. No banners | Rewarded ads are chosen by the player. An ad between matches is what gives "Remove ads" something to remove | S |
| **Caps:** none in the first session, none in an online lobby or rematch with friends, never during a match, and a minimum gap between them | Forced ads early are the main cause of day-one uninstalls | S |
| **Consent and privacy:** tracking prompt, consent form for Europe and the UK, SKAdNetwork entries, privacy manifest, privacy labels, privacy policy link, ad content rating capped at family-safe | Required by App Review and by Google's ad policies | M |
| **Pause the match and audio around an ad** | `audio.gd:132-150` already handles interruptions; the match needs the same | S |
| **Analytics and crash reporting** with consent | Ad income depends on retention and sessions per day, and none of it is measured today | S-M |
| **Remote config** over HTTPS with a bundled fallback: ad caps, featured mode, news, minimum version, kill switches | Lets you tune ad frequency without an app release | M |
| **Account and server fixes that apply even without purchases** | See the list below | S-M |
| **App Review items:** report and block, name filter, age rating answers | Online play with free-text names needs them | S-M |

Account and server fixes for launch:

- Revoke all tokens on delete, password change and reset. Today only the current token is revoked (`accounts.js:109,228-233`), so old tokens can log into a new owner of a freed name.
- Stop erasing accounts idle for 30 days (`accounts.js:112-120`), and move off the in-memory `db.json`. `render.yaml` sets no data directory, so a redeploy wipes every account.
- Store the token in the Keychain (`godot/net/account_api.gd:23` TODO) and fix the 32-bit timestamp bug at `accounts.js:194`.
- Bake in a server address you own. `data/extra/server.json:3` points at a Tailscale Funnel host on the home NAS, so the server cannot move without an app release.
- Remove the dev code from release builds. Its hash ships in the client (`dlc_unlock.gd:10-11`) and unlocks everything.

### Step 2: paid, no ads

| Change | Why | Size |
|---|---|---|
| **One in-app "Remove ads" purchase inside the same app** | One store listing, one set of reviews and one player base. Apple tends to reject near-duplicate free and paid apps | S |
| **StoreKit 2 through a Godot plugin, with an `Entitlements` autoload in front of it** | A one-off unlock is held by Apple against the player's Apple ID, so it needs no server wallet and no game account | M |
| **Restore purchases button** | Required by App Review | S |
| **What it removes:** ads between matches, and rewarded bonuses are granted without watching | Makes the purchase clearly worth it | S |

Run a two-day test on TestFlight sandbox of the two StoreKit 2 options for Godot 4 (`godot-iap`, and the community RevenueCat plugin) before choosing. Both are community-maintained.

### Step 3: later, DLC, coin packs and a subscription

These must be in place before anything is sold for coins or with coins:

| # | Change | What goes wrong if skipped | Size |
|---|---|---|---|
| 1 | **Server-side wallet and entitlements** (`/api/wallet`, `/api/buy`, `/api/entitlements` in `accounts.js`). `godot/autoload/save.gd` keeps preferences and what is equipped, and stops being the truth for coins and owned items | Any purchase can be faked by editing `profile.json` or sending a made-up `PUT /api/save` (`accounts.js:188-198`) | L |
| 2 | **Server verification of purchases**, plus Apple's server notifications for renewals and refunds | Subscriptions that never expire, and refunded coins that stay spent | M |
| 3 | **Server-decided rewards with caps and server time** | Coins that can be bought can also be minted by clock changes (`logic/quests.gd:55-57`) or a friendly host | M |
| 4 | **Ownership checks online** | A host accepts any class id (`net/host_match.gd:101-104`), so paid classes are free online | S |
| 5 | **A recoverable login before buying coins** (Sign in with Apple or Game Center) | A name-only account loses its purchases with the device | M |
| 6 | **Save versioning with migrations and per-field merge** | "Keep this device" can drop items bought on another device (`account_api.gd:360-428`) | M |

Design rules to keep from now on, so step 3 does not need rework:

- **Paid items are cosmetic or sidegrades.** The three paid classes change stats today (`data/extra/classes.json`), which reads as pay-to-win once money is involved. Keep classes earnable by play.
- **No random paid items.** `docs/IOS_PLAN.md:84` already says no loot boxes, which avoids odds disclosure and loot-box law.
- **DLC code ships inside the app** and is switched on by an entitlement. Apple does not allow downloading new code, so only data and config should come from the server.
- **Decide the coin economy before selling coins.** Free coins earned from ads before coin packs exist will otherwise devalue the packs. Move balances to the server wallet at that point.
- **A subscription needs a content rhythm.** Plan it only once a new arena, mode or cosmetic set can ship every few weeks.

Also worth doing along the way: a staging server and environment per build (S), CI export and TestFlight upload with an App Store Connect key (M), one version source for both build scripts and the Android preset (S), and API and protocol versioning with a clear "Update the game" message (S).

---

## 3. Optimisation and roadmap

### Measure first

1. Re-run the graphics benchmark on 0.3.0 and update `docs/GRAPHICS.md`. (S)
2. Run the existing 15-minute soak (`godot/world/soak_run.gd`) on an iPhone 12, with Low Power Mode on and off. (S, needs your phone)
3. Add what the soak lacks: a heat-state plugin (`godot/ui/perf_probe.gd:64-69` shows "n/a"), a load-hitch log, and a way to get the CSV off the phone. (M)

### Safe to do now

| Change | Why | Size | Files |
|---|---|---|---|
| Frame-rate cap (30 / 60 / 120) and render-scale settings | Neither exists. They are the main battery and heat controls | S | `settings.gd`, `autoload/tier.gd`, `ui/settings_screen.gd` |
| Check melee hits on the fixed step, not once per drawn frame | `actors/fighter.gd:73-97` and `world.gd:346` tie hit detection to frame rate, which is unfair across devices and blocks a 30 fps cap | M | `actors/fighter.gd`, `world.gd`, `logic/combat.gd` |
| Keep parsed JSON between matches | `logic/match_sim.gd:50-120` and `combat.gd:83-92` re-read seven files every match | S | `autoload/content.gd`, `match_sim.gd` |
| A loading screen with the match built over several frames, plus a shader warm-up | Match load runs in one go (`world.gd:152-242`) and decodes up to 90k scenery vertices in script | M | `world.gd`, `scripts/main.gd:563-589`, `world/map_builder.gd:661-713` |
| Shared materials and merged static parts per fighter | About 35 separate meshes per fighter, each with its own material, so 10 fighters cost about 350 draws before shadows | M | `actors/wobbler.gd:129-156`, `wobbler_looks.gd` |
| HUD and radar update only on change | `ui/hud.gd:245-380` formats text and rebuilds dictionaries every frame; the radar loops over every solid every frame | S | `ui/hud.gd`, `ui/hud_radar.gd`, `ui/hud_nameplates.gd` |
| CI: cache Godot, run the 26 suites not in CI, add export smoke builds | 14 of about 40 suites run in CI, with no export job | S | `.github/workflows/ci.yml` |
| Netcode: smaller snapshots and an interpolation buffer | 30 Hz JSON at an estimated 60 KB/s per player, and the 400 messages per second cap is a wall near 12 players | M | `logic/net_snapshot.gd`, `net/net_match.gd`, `server.js` |
| Retire the three.js game once content is re-pointed | 15 test scripts and 5 reference slicers exist to keep parity with it. `godot/data/extra` must become the source of truth first | L | `tools/export-content.js`, `shared/`, `public/` |

### Roadmap order

Times are rough and assume the current way of working; device testing and your review time are the real limits.

| Stage | Contents | Rough time |
|---|---|---|
| 0. Fixes | Melee bosses in the Construction Arcade, and the stuck FIRE button | first |
| A. Feel and measure | Haptics, audio quick wins, big-moment audio and effects, the #105 look decision, device soak, frame cap and render scale, version clean-up | 2 to 3 weeks |
| B. Launch essentials | Ads, Remove ads, consent and privacy, account and server fixes, analytics and crash reporting, remote config, App Review items, Game Center | 5 to 7 weeks |
| C. Charm and depth | Title screen, playable first fight, faces, results moment, timed defence, class signature moves, weapon identity. Overlaps B | 5 to 7 weeks |
| D. Soft launch | 2 or 3 small markets, tune ad caps, retention and balance, then global | 4 to 8 weeks |
| E. Paid content | Server wallet, purchase verification, DLC purchase, coin packs, then a subscription once content ships on a rhythm | 6 to 10 weeks |

---

## 4. Making the game more attractive

Judged from the reference screenshots in `docs/style/` and the audits.

- **Put the fighter on the title screen.** The title is text buttons on a dark background. Reuse `godot/ui/character_stage.gd` to show your Wobbler in its outfit, idling and emoting in front of an arena.
- **Replace the three intro cards with a playable first fight.** A guided 60-second match the player wins, then a reward and an outfit pick.
- **Give faces expressions.** Fighters have two black rectangles for eyes. Blinks, a hurt wince and X eyes on a K.O. are cheap and carry most of the charm.
- **Make the win a moment.** Results are a text panel over a frozen match. Use a podium with the winners emoting, a coin count-up and a bar towards the next unlock. This is also where the "double coins" rewarded ad fits naturally.
- **Sell silhouettes, not recolours.** Shop outfits read as one body in different colours. Hats, backpacks, big heads and trails show at match distance.
- **Dress the most-played arenas.** Flat single-colour floors and plain boxes look like a prototype next to the sky and scenery. Start with the five arenas new players see first.
- **Curate the choice.** 20 modes and 34 arenas on day one is a lot. Start with a handful, unlock the rest through play, and feature one rotating mode each day.
- **Add a long-term track.** Daily and weekly goals exist. A level road with a steady unlock rhythm, plus class and weapon mastery, gives a reason to return in week two.
- **Make inviting a friend one tap.** Share a room link through the iOS share sheet that opens the app in the lobby, and add a Quick play button that fills empty slots with bots.
- **Make K.O.s shareable.** The kill cam exists offline. A share button on a slow-motion K.O. is the natural marketing loop for a ragdoll game.
- **Lean on the Construction arcade.** Boss stages are a strong solo anchor, and co-op against bosses would suit the game. It is also the template for paid DLC.
- **Store page.** A 15 to 30 second preview video of ragdoll K.O.s, captioned screenshots, and localised listings for the five languages already in the game.

---

## Assumptions to confirm

1. "Paid with no ads" is one in-app purchase inside the free app, not a second paid app.
2. Ads are rewarded plus one capped ad between matches, with no banners.
3. You can do a phone session for the 15-minute soak, the #105 look decisions, and checking the two fixes.
4. Recorded audio is only bought if the synth falls short.

## How to work from this plan

- Work in small pull requests, one work package each. Section 0 first: the stuck FIRE button, then the melee bosses.
- For the FIRE fix, write the test first and confirm it fails on the three cases before changing `touch_controls.gd`.
- Boss and pickup changes apply only during an Arcade run (`ArcadeManager.running`), so other modes and the bot parity tests are untouched.
- Follow `docs/WRITING.md` for any player-facing text.
- Still to do from this plan's audit: fix the stale version references listed under Context (the Android preset and build-script defaults, `docs/ROADMAP.md:21`, the README badge).

## Verification

Use Godot 4.7.2 (the CI version) and set the `GODOT` environment variable to its binary.

- `npm test` passes (content drift check).
- **FIRE button:** the new touch test fails before the fix and passes after. `npm run test:godot-ui` and `npm run test:godot-flow` still pass.
- **Bosses:** `npm run test:godot-arcade`, `npm run test:godot-construction` and `npm run test:godot-construction-data` pass. The Arcade balance run (`godot/tests/arcade_balance.gd`) is used to retune boss health and speed, and its before and after numbers go in the pull request.
- **Nothing else moved:** `npm run test:godot-bots` (bot parity) passes unchanged.
- **Docs:** every file path cited in `docs/ROADMAP.md` exists.
- **On device (you):** the stuck button and the boss feel can only be confirmed on your iPhone. The pull request should say so, with the steps to try: hold FIRE and pull down Control Centre, hold FIRE and tap with a second finger, and fight the Supervisor on Normal.
