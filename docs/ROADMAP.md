# Wobblers Arena roadmap

_Approved 2026-11-12. Supersedes the plan and decisions in docs/IOS_PLAN.md (sections 1-4 of that file remain a useful review of build b76)._


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
  - *Progress (batch 1, offline):* `godot/logic/mode_rules.gd` (`ModeRules`): K.O. limit + `endMatch` with an end banner and offline results panel, lives/stock + `eliminate`, teams (duel, 2v2, 3v3, 4v4: team colours, no friendly fire, team score), Weapon Ladder (`ggGive/ggAdvance`), ninja dash (`doDash/dashTick`, player + bots), shrinking arenas (Mega Damage on shrink/squeeze: `updateShrink`, shrink respawn spot). Playable offline: classic, melee, guns, ninja, giant, duel, t2, t3, t4, mega, gungame (`ModeRules.PLAYABLE`; Settings `mode` / `limit`). Parity + headless matches: `npm run test:godot-modes`. Left: Pillars (bot hops, `pillarGive`, 3-minute clock), Explosive and Moon Drift (need launchers), online `limit`/`pend`, Sandbox/Construction (other tracks). Hot Potato is gone from the web game (no mode sets `potato`), so nothing to port. Ladder rungs bow / shuriken / grenade launcher and the Ninja start shuriken work since weapons batch 2 (every weapon type is ported).
  - *Progress (Godot-only modes):* four modes the web game does not have, defined in `godot/data/extra/modes.json` (merged into `modes` by `ModeRules.merge_extra`; `shared/` stays the web export): **Team Deathmatch** (`tdm`, two teams sized by the Players page with odd bot counts only, first team to 30), **Death Match** (`deathmatch`, free for all, first to 20), **Sudden Death** (`sudden`, one life: a K.O. or a fall eliminates at once; the player then spectates a survivor, tap to switch, until one stands) and **Chaos** (`chaos`, 5 v 5 on the big arenas, first team to 50, a CombatRng-timed event every 15-25 s: crate rain, low gravity, knockback storm, a temporary giant, speed surge, a forced floor quake / wobble; announced with a countdown banner, never the same twice in a row, rules restored after). Headless matches for all four in `npm run test:godot-modes` (Chaos prints its step time with 10 fighters). Offline only: online rooms still use the web modes.
- **Bots track:** AI and 4 difficulties ported from the JS bot code; needed for offline play and for hosting.
- **Host role:** slot assignment, bot ownership, relay + `netGuard` rules, rematch voting, host migration. Extend `tools/wa-client.js` tests so a Godot host serves web and Godot guests.
  - *Progress:* Godot hosts rooms (`net/host_session.gd`, `net/host_match.gd`): create, lobby (Host a room sheet + lobby with Start / Leave), slots, bots run by the host, `start` rules incl. `dyn`/`dseed`/`dt0`, 30 Hz `S`, `h`/`ko`/`take`/`crate`/`pend`, `netGuard`, mid-match joiners, leavers back to bots, rematch voting. `npm run test:godot-host` covers a web-protocol guest and a Godot guest. Open: host migration to a Godot guest, Pillars and team modes online.
- **Maps track:** all 33 from data, plus special mechanics (ice grip, shrink/squeeze, moving parts, domes, custom generator, sandbox blocks). Extend `export-maps.js` for decor and backdrops so levels look right, not just collide right.
- **Audio:** port the synthesized SFX (pre-render to samples at build time).
- **Exit:** every mode playable in mixed web/Godot rooms with either side hosting; `check-maps` and parity suites green.

### Phase 3 — Interface and meta (5–7 weeks, overlaps Phase 2) → TestFlight build 5
- Godot `Theme` (your Stage 3 spec): main menu, play setup, lobby, room browser, pause/controls, results; button micro-interactions; safe areas on every aspect ratio.
- HUD (your Stage 4 spec): hotbar with keybind badges, KO/timer pill, health bar with damage trail, radar, nameplates, touch buttons with icons and left-handed/size/opacity options.
- Locker, shop, class picker, emotes; accounts and cloud save against the existing `/api/*`; kill-cam.
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
