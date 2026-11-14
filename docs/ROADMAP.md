# Wobblers Arena roadmap

_Approved 2026-11-12. Supersedes the plan and decisions in docs/IOS_PLAN.md (sections 1-4 of that file remain a useful review of build b76)._

> **2026-11-14 update:** the plan (fixes, VFX/audio/combat, ads-first money model, store readiness, optimisation) is in [IMPROVEMENT_PLAN.md](IMPROVEMENT_PLAN.md); the execution order, exit criteria and current status are in [STORE_READINESS_PLAN.md](STORE_READINESS_PLAN.md). Together they supersede the "Next" list below.


## Status (2026-11-14)

Honest state of the Godot port after the unattended build-out. "Done" means ported, parity/behaviour tests passing in the repo and merged to main; it does **not** mean verified on a real iPhone (nobody has measured phone GPU time or thermals yet, and the TestFlight builds have only been played briefly by one person).

| Phase | State | What is in | What is open |
|---|---|---|---|
| 0 Clean up and unblock | Done | export pipeline, signing, TestFlight upload (`tools/build-ios.sh`, 0.3.0), App Store Connect record "Wobblers Arena", one version source enforced by `npm run check:version` | API key for CI uploads; Keychain use is a launch item |
| 1 Vertical slice | Done | map builder, Wobbler rig, combat core, input, net guest, look baseline | none |
| 2 Gameplay parity | Done for offline; online mostly | all weapons (batch 1 and 2), 20 offline modes in `ModeRules.PLAYABLE` plus Construction, incl. Godot-only ones (Team Deathmatch, Death Match, Sudden Death, Chaos 5v5, Pillars + Lava Pillars, Explosive, Moon Drift, Practice Range, Sandbox), full bot AI at 4 difficulties, all 34 maps with decor, body-part damage zones, Godot host role (web and app guests, host migration, rules sheet), Godot-only balance overlay with weapon cooldowns and shot charges, and the air-recovery move (#72), offline and `net_zones` rooms only | web guests only play Classic online; host cannot change rules from the lobby; no wstate editor; mixed web/Godot rooms need a manual phone-to-browser check (docs/CROSSPLAY_TEST.md section 5) |
| 3 Interface and meta | Done | theme, wizard (game type, arena, players, character, start; refined with sections, an Arena floor row and class stat bars), title, HUD, 4-button touch layout, locker (plus 3 paid and 3 secret Godot-only classes, data/extra/classes.json), Walldrobe (owned items only), shop (outfits, emotes, classes), Goals (daily / weekly coin goals, milestones, play streak), What's new card, 5 languages (繁體中文, 简体中文, 日本語, Français, Español) with bundled CJK fonts, emotes, results with coins, accounts + cloud sync + in-app deletion, kill cam, room browser, Settings screen, pause menu + controls help, first-run how-to, UI scale (44 pt targets) | aim-assist toggle; big-emote props; Keychain token storage; daily gift / redeem codes; full UI clean-up pass (in progress) |
| 4 Graphics | Done in code | tone mapping + grade, sky/clouds, tiered shadows, stylised materials, tree wind, animated scenery, ragdoll wobble rig, pooled particles, trails, squash and stretch, hitstop, shake; per-tier budgets in `docs/GRAPHICS.md` (CPU under 4 ms in the benchmark) | **phone GPU time and 15-minute thermal run not measured**; particle depth sorting; some far-scenery gaps (birds) |
| 5 Store platforms | In progress | haptics (autoload `Haptics`, Settings switch), frame-rate cap and render scale (Settings > Graphics, autoload `Perf`) | Game Center, Keychain token storage, orientation lock, privacy manifest, Android/PC/web exports |
| 6 Store readiness | In progress | provider-neutral `Ads` / `Entitlements` / `RemoteConfig` / `Safety` policy with tests, session revocation and retention safety, name filter and report/block, remote config, CI export smoke build | native AdMob and StoreKit plugins, consent forms, analytics and crash reporting, server wallet, production server host, App Review items |
| Online infra | In progress | NAS self-hosting runbook (`docs/SERVER_PLAN.md`), `deploy/nas` compose, `TRUST_PROXY` and production server URL config (#70) | production server URL not yet set, so TestFlight builds cannot play online yet |

Release tracking: the checked-in native version is 0.3.0. Historical TestFlight builds are not a substitute for testing the current commit. The Phase 3 and 4 exit criteria ("a new player can install and reach a match with no dead ends", "60 fps on iPhone 12 for 15 minutes without thermal throttling") need device play and cannot be signed off from tests alone.

## Money model and execution order (approved 2026-11-14)

**Free with ads at launch.** One free app: rewarded ads the player chooses (double coins on the results screen, the
daily bonus, an Arcade continue) plus one capped ad between matches, and no banners. A single non-consumable "Remove
ads" purchase sits inside the same app. Coins, DLC and a subscription come only after the server owns the wallet and
the entitlements. Paid playable content stays a sidegrade or cosmetic (classes remain earnable) and there are no
random paid items.

The plan with exit criteria for every stage is in `docs/STORE_READINESS_PLAN.md`. Order:

0. Fixes: melee Construction bosses, the stuck FIRE touch button.
1. **A. Feel and measure:** haptics, audio quick wins and big-moment sound, the #105 look decision, frame cap and
   render scale, device soak, benchmark re-run.
2. **B. Launch essentials:** ads and consent, Remove ads, account and server safety, analytics and crash reporting,
   remote config, App Review items, CI.
3. **C. Charm and depth:** title screen, a playable first fight, faces, results moment, timed defence, class
   signature moves, weapon identity.
4. **D. Soft launch:** 2-3 small markets, tune ad caps, retention and balance, then global.
5. **E. Paid content:** server wallet and purchase verification, then coin packs, DLC and a subscription once content
   ships on a rhythm.

The previous next list (online on the NAS, perf overlay and soak, UI clean-up, Phase 5 iOS essentials, online parity)
folds into A and B; the online items remain launch blockers.

## Context

Decisions made in this session, which replace the earlier "Godot for iOS + web game for browsers" plan:

- **One codebase: Godot 4 everywhere.** The final product is a single Godot project exported to **iOS, Android, PC (desktop app, Steam-ready) and web**, all cross-playing because they are the same code. The three.js game (`public/index.html`) becomes the **reference implementation** and is retired when Godot reaches parity.
- **1.0 contains everything:** all 14 modes, 33 maps, 28 weapons, 5 classes, bots, cosmetics, accounts, online rooms.
- **Order of work: playable on iPhone soonest.**
- Kept from before: cosmetics + pass + gems, friends/private rooms + bots at launch, quick-chat and emotes only, iPhone 12 minimum, bundle ID `com.kedrosng.wobblearena`.

What exists today (main, PRs #1–#13 merged):
- Web game with classes, 4 new arenas, phone menus, touch controls; `docs/PROTOCOL.md`; hardened netcode; `shared/*.json` (weapons, modes, classes, cosmetics, map collision geometry) exported by `tools/export-content.js` / `tools/export-maps.js`.
- Godot skeleton in `godot/`: `scripts/net_client.gd` (joins a room), `logic/fighter_physics.gd` (movement + collision, **exact parity** with the web code via `tools/physics-reference.js` + `tools/test-physics.js`).
- Tests: `npm test` (content drift, map checker, server), `test:browser`, `test:touch`, `test:godot`, `test:godot-physics`.

Loose ends right now:
- Draft PR #14 (Locker phone fix): tested, not merged.
- Branch `claude/visual-overhaul`: uncommitted Stage 1 web look pass (soft shadows, warm/cool lights, prototype-grid Practice Range, tree wind) + `tools/shoot-scenes.js`.
- Branch `claude/ios-export`: iOS export preset fails validation with an empty error list.
- GitHub Actions blocked by account billing; no App Store Connect API key or app record yet.

## Guiding rules

1. **The web game is the spec.** Every Godot system is ported from the JS and checked against it, the way movement already is: slice the real JS function, run a scripted input, compare. No re-guessing numbers; all tunables come from `shared/*.json`.
2. **Web game is frozen** except bug fixes. No more features or polish there (the graphics/UI overhaul moves to Godot). It stays live and cross-play compatible (protocol `proto: 1`) until Godot's web export replaces it.
3. **Three render tiers, one art direction:** PC = Forward+ (SSAO, SDFGI/SSIL, volumetric fog, glow); iOS = Mobile renderer (glow, depth fog, soft shadows, no SDFGI); Web = Compatibility (baked-look fallbacks). Shaders and materials are written once with tier switches.
4. **A device build every milestone.** Each phase ends with a TestFlight build you play on a real iPhone; your feedback gates the next phase.
5. **Process:** parallel sessions per track in separate worktrees; draft PRs; anything visual waits for your screenshot approval; non-visual PRs merge when tests pass.

## Team and model allocation (token efficiency)

| Role | Model | Does | Does not |
|---|---|---|---|
| **Lead / decision maker** | **Fable** (this session) | Architecture and design decisions, splitting work into briefs, reviewing every PR diff and screenshot, merge decisions, resolving conflicts between tracks, talking to you | Bulk coding or long file reading |
| **Complex work** | **Opus** subagents | Systems that need judgment: wobbler animation and physics ports, combat and hit math, bot AI, host netcode and migration, shaders and the render tiers, iOS export pipeline, anything where the JS must be understood before porting | Mechanical ports |
| **Repetitive work** | **Sonnet** subagents | Pattern work once an Opus example exists: the remaining weapons of a type, the remaining modes and maps, UI screens from the theme, test scaffolding, screenshot capture, content export updates, docs | Design decisions; they stop and report if the pattern doesn't fit |

How this saves tokens and keeps quality:
- **Pattern first, then fan out.** For each system, one Opus agent builds the first instance with its parity test (e.g. one gun). I review it. Then Sonnet agents repeat the pattern for the rest (the other 27 weapons), each with the same test harness as its pass/fail gate.
- **Tests are the reviewer for repetitive work.** Sonnet output merges on green parity tests plus a short diff review by me; only failures or visual changes get deeper review.
- **Tight briefs.** Each agent gets: goal, exact files and line ranges to read, the example to copy, the test command, the report format. No agent reads all of `public/index.html` (10k lines); the lead keeps an index of where each system lives (`docs/CODEMAP.md`, written once in Phase 0 by a Sonnet agent).
- **Short reports.** Agents return a fixed short report (what changed, test output, open issues, screenshot paths), not narratives.
- **Few agents at a time.** At most 3 running in parallel, on non-overlapping files, each in its own worktree; no speculative or duplicate work.
- **Escalation rule.** Sonnet escalates to Opus (via me) after one failed attempt at a problem instead of looping; Opus escalates design questions to me; I bring product questions to you.

## Roadmap

Durations assume the current way of working (several parallel sessions, you reviewing). They are estimates, not commitments; the real bottleneck is device testing and your review time.

### Phase 0 — Clean up and unblock (about 1 week)
- Merge PR #14. Commit the Stage 1 web look pass as the **art reference** (screenshots into `docs/style/`), then stop web visual work.
- Rewrite `docs/IOS_PLAN.md` into `docs/ROADMAP.md` with the decisions above.
- Fix the export pipeline: create export presets from the Godot editor UI once (iOS, Android, macOS, Windows, Web), commit `export_presets.cfg`, then script `godot --headless --export-*` + `xcodebuild archive` in `tools/build-ios.sh` and APK/AAB export in `tools/build-android.sh`.
- **Exit:** an empty-scene Godot app installs on your iPhone via TestFlight (and an Android APK via `adb`). This proves signing, upload and the whole pipeline before any game work depends on it.
- Needs from you: App Store Connect app record + API key (`.p8`), GitHub billing fix, one editor session to create presets.

### Phase 1 — Foundation and vertical slice (5–7 weeks) → TestFlight build 1
Goal: one map, one mode, on your iPhone, in a room with web players.
- **Core architecture** (`godot/`): autoloads `Content` (loads `shared/*.json`), `Net` (extends `net_client.gd`), `Settings`, `Save`; `MapBuilder` (boxes, ladders, bounce pads from `maps.json`); render-tier switch.
- **Wobbler:** blocky model built in code like the JS `Fighter` constructor; spring animation (`Spring2`, lean/head/arm) ported from `Fighter.animate`; class looks from `shared/classes.json`; outfits/hats for the slice set.
- **Combat core:** `Fighter.hit` (damage, knockback, stun), spatula melee sweep, one gun, one thrown weapon, KO/respawn, pickups. Parity tests for hit/knockback math.
- **Input:** one action map feeding touch (port the web touch layout), keyboard+mouse, gamepad.
- **Net guest role:** `S` snapshots at 30 Hz with the same interpolation, `sw/f/k/h/ko/take`, lobby `roster/start/slot`.
- **Look baseline:** WorldEnvironment, sun/sky, character shader with rim light and hit flash (Stages 1–2 of your overhaul spec, slice-sized).
- **Exit:** you and a browser player finish a Classic match on Sunny Arena at 60 fps on iPhone 12-class hardware.

### Phase 2 — Gameplay parity (10–14 weeks, parallel tracks) → TestFlight builds 2–4
- **Weapons track:** all 28, grouped by type (melee, gun, bow, rocket/launcher, boomerang, thrown, net, flame, special). Each group: port + parity test + visual/audio.
- **Modes track:** all 14 (`shared/modes.json`), including lives, teams, pillars, gun game, hot potato, ladder modes; match rules, scoring, `pend`.
  - *Progress (batch 1, offline):* `godot/logic/mode_rules.gd` (`ModeRules`): K.O. limit + `endMatch` with an end banner and offline results panel, lives/stock + `eliminate`, teams (duel, 2v2, 3v3, 4v4: team colours, no friendly fire, team score), Weapon Ladder (`ggGive/ggAdvance`), ninja dash (`doDash/dashTick`, player + bots), shrinking arenas (Mega Damage on shrink/squeeze: `updateShrink`, shrink respawn spot). Playable offline: classic, melee, guns, ninja, giant, duel, t2, t3, t4, mega, gungame (`ModeRules.PLAYABLE`; Settings `mode` / `limit`). Parity + headless matches: `npm run test:godot-modes`. Left: online `limit`/`pend`, Sandbox/Construction (other tracks); Pillars, Explosive and Moon Drift are done in batch 2 below. Hot Potato is gone from the web game (no mode sets `potato`), so nothing to port. Ladder rungs bow / shuriken / grenade launcher and the Ninja start shuriken work since weapons batch 2 (every weapon type is ported).
  - *Progress (batch 2, offline: the rest of the web modes):* **Pillars** (the level built by `logic/pillars_map.gd` since the web export has no boxes for it, checked box for box against the web build(); random start pillar, 7 bots, one life, dashes with any weapon, `pillarGive` every 10 s, the 3-minute clock: most K.O.s / fewest deaths, else last one standing; HUD clock and next weapon), **Explosive** (launchers, 300 health), **Moon Drift** (`lowg`, added to `godot/data/extra/modes.json` because the web export misses `MODES.lowg`; gravity 0.15 on every fighter's physics, `projG`), **Practice Range** (`practice`: the practice / test maps with their 10 dummies that stand, slide on their paths, take damage and pop back up at home, plus the weapon racks that refill; `logic/practice_range.gd`; any mode on a range map gets the dummies, like the web). All in `ModeRules.PLAYABLE` and the wizard (BLURB card text, fixed bot counts on the Players page, only their own arenas). Tests: `npm run test:godot-modes` (Pillars handout + clock parity with the real JS, Moon Drift gravity physics parity on both domes, headless matches to the end: Pillars by last one standing and by the clock, Explosive and Moon Drift to 5), `npm run test:godot-range` (rangeBot parity, the range in play). Left: Lava Pillars (`pillars2`, not in the web export), Sandbox (needs the block building UI), online `limit`/`pend` (host track).
  - *Progress (Godot-only modes):* four modes the web game does not have, defined in `godot/data/extra/modes.json` (merged into `modes` by `ModeRules.merge_extra`; `shared/` stays the web export): **Team Deathmatch** (`tdm`, two teams sized by the Players page with odd bot counts only, first team to 30), **Death Match** (`deathmatch`, free for all, first to 20), **Sudden Death** (`sudden`, one life: a K.O. or a fall eliminates at once; the player then spectates a survivor, tap to switch, until one stands) and **Chaos** (`chaos`, 5 v 5 on the big arenas, first team to 50, a CombatRng-timed event every 15-25 s: crate rain, low gravity, knockback storm, a temporary giant, speed surge, a forced floor quake / wobble; announced with a countdown banner, never the same twice in a row, rules restored after). Headless matches for all four in `npm run test:godot-modes` (Chaos prints its step time with 10 fighters). Offline only: online rooms still use the web modes.
- **Bots track:** AI and 4 difficulties ported from the JS bot code; needed for offline play and for hosting.
  - *Progress (AI parity):* `godot/logic/bot_brain.gd` is now the whole web `botThink` (target choice, aim error, reaction time, range keeping and strafing, line of sight, gun bursts / reloads / launcher rules / bow draw, kicks and swings, crates and heals, edge and void awareness incl. shrinking floors, the stuck watchdog and escape, jump-ups, ninja dashes, Pillars edge guard and pillar hops, dummies) at all four difficulties, with combat.rng in the web call order. `npm run test:godot-bots`: decision parity against the real JS (`tools/bots-reference.js`, exact to ~1e-15) and 12-minute bots-only matches per difficulty on three maps (self ring-outs and stuck spells under thresholds, AI cost with 10 bots). Batch-2 weapons (shuriken, typhoon, boomerang, snake, snowball) are in `BotBrain.BOT_FIRE` and the parity scenario. Godot-only fixes: `BotBrain.unstick` (a bot whose escape fails backs off instead of re-rolling into a corner) `hold_busy` (no wasted throws while a boomerang / typhoon is out) and `shrink_guard` (bots step back from the edge of a shrinking floor). Practice-range dummies (`rangeBot`) and Pillars as a playable mode are done (modes batch 2). Left: bot ownership online (host track).
- **Host role:** slot assignment, bot ownership, relay + `netGuard` rules, rematch voting, host migration. Extend `tools/wa-client.js` tests so a Godot host serves web and Godot guests.
  - *Progress:* Godot hosts rooms (`net/host_session.gd`, `net/host_match.gd`): create, lobby (Host a room sheet + lobby with Start / Leave), slots, bots run by the host, `start` rules incl. `dyn`/`dseed`/`dt0`, 30 Hz `S`, `h`/`ko`/`take`/`crate`/`pend`, `netGuard`, mid-match joiners, leavers back to bots, rematch voting. `npm run test:godot-host` covers a web-protocol guest and a Godot guest. Open: host migration to a Godot guest, Pillars and team modes online.
- **Maps track:** all 33 from data, plus special mechanics (ice grip, shrink/squeeze, moving parts, domes, custom generator, sandbox blocks). Extend `export-maps.js` for decor and backdrops so levels look right, not just collide right.
- **Audio:** port the synthesized SFX (pre-render to samples at build time).
- **Exit:** every mode playable in mixed web/Godot rooms with either side hosting; `check-maps` and parity suites green.

### Phase 3 — Interface and meta (5–7 weeks, overlaps Phase 2) → TestFlight build 5
- Godot `Theme` (your Stage 3 spec): main menu, play setup, lobby, room browser, pause/controls, results; button micro-interactions; safe areas on every aspect ratio.
- HUD (your Stage 4 spec): hotbar with keybind badges, KO/timer pill, health bar with damage trail, radar, nameplates, touch buttons with icons and left-handed/size/opacity options.
- Walldrobe (what you own), Shop (all buying, incl. classes), Goals (daily / weekly coin goals, milestones, play streak; Godot-only `quests` save key), class picker, emotes; accounts and cloud save against the existing `/api/*`; kill-cam.
- **Exit:** a new player can install, pick a class, play offline, log in, and join a friend's room with no dead ends.

### Phase 4 — Graphics overhaul, full (3–4 weeks, after gameplay is stable)
Your four-stage spec, applied across all maps with the three tiers: tonemapping and post, sky and fog, soft shadows, stylized materials, Practice Range grid shader, tree wind, mountain depth; melee/projectile trails, squash-and-stretch, GPU particles (dust, dash, shockwave, KO confetti). Performance budget enforced per tier (iPhone 12: 60 fps, no thermal throttle in 15 min).

### Phase 5 — Store platforms (3–4 weeks)
- **iOS:** Game Center, haptics, Keychain token storage, orientation lock, privacy manifest.
- **Android:** Play signing, haptics, credential storage, immersive landscape (export pipeline already in `tools/build-android.sh` / `docs/BUILD_ANDROID.md`).
- **PC:** macOS + Windows exports, controller support, settings for the Forward+ tier, Steam-ready packaging (store page is a separate decision).
- **Web:** Godot web export served by `server.js` (adds the COOP/COEP headers it needs). Goes live at `/`; the three.js game moves to `/classic`.
- Protocol: bump to `proto: 2` only if a Godot-only change needs it; version gate replaces the build-number check on the server.
- **Exit:** iPhone, Android, PC app and browser in one room.

### Phase 6 — Store readiness and monetization (4–6 weeks)
- Server-side wallet and inventory; remove `coins_####`; StoreKit 2 with server receipt validation; gems, Wobble Pass, quests, trophy road.
- App Review items: report/block on names, account deletion in-app, age rating, privacy labels.
- Always-on paid server host, regions, monitoring; WebSocket relay only (no PeerJS/TURN).

### Phase 7 — Soft launch → 1.0 → live ops
Soft launch in 2–3 small markets, tune economy and balance (classes especially), crash-free ≥ 99.5%, then global. Retire `/classic`. Six-week season cadence; public matchmaking and free-text chat are post-launch decisions.

**Rough total:** 8–11 months to global launch. First TestFlight (empty shell) in about a week; first *playable* TestFlight in about 6–8 weeks.

## Main risks

| Risk | Mitigation |
|---|---|
| Rewriting everything stalls before parity | Web game stays live and playable the whole time; vertical slice first; parity tests per system; scope cut line is modes/maps, not quality |
| iOS export/signing pipeline (currently broken) | Phase 0 exit criterion; nothing else starts until an empty app is on TestFlight |
| Godot web export: large download, weaker on phone browsers | Phone players use the app; web tier uses Compatibility renderer; keep `/classic` until the web export is good enough |
| Host-client netcode with two engines during transition | Protocol spec + cross-client tests (`test:godot`, extended); retire three.js to end the dual-engine period |
| Visual wish list vs phone performance | Three tiers; heavy effects PC-only; device perf test each milestone |
| Verification depends on real devices | A TestFlight build per milestone; I can't test on hardware myself |

## What I need from you

1. App Store Connect: create the app record for `com.kedrosng.wobblearena`, and an API key (`.p8`, key ID, issuer ID).
2. Google Play Console: create the app with package `com.kedrosng.wobblearena`, and keep an upload keystore (path + alias + passwords for `GODOT_ANDROID_KEYSTORE_RELEASE_*`).
3. Fix GitHub billing so CI runs.
4. One short session at the Mac to confirm export presets in the Godot editor if a headless export complains about a missing key.
5. Play each TestFlight / sideloaded APK build and tell me what feels wrong.

## Verification

- Per PR: `npm test`; relevant parity suite (`test:godot-physics`, new `test:godot-combat`, `test:godot-bots`); `test:godot` cross-client room tests; screenshot review for anything visual.
- Per phase: the exit criterion above, on a real iPhone via TestFlight.
- Before 1.0: every mode × a sample of maps played in a mixed-platform room; 15-minute thermal run on iPhone 12; App Review checklist.

## First steps after approval

1. Merge PR #14; commit Stage 1 web look as the art reference; write `docs/ROADMAP.md`.
2. Phase 0 export pipeline (with your editor session and Apple key).
3. Start Phase 1 in three parallel sessions: architecture + MapBuilder, wobbler + animation, combat core + net guest.
