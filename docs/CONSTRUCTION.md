# Construction Mode

Scaffold for a tradie-themed offline mode. Keeps the existing Claude / class / online flow intact: no new Locker classes, no `cls` protocol changes, and Construction stays offline like Sandbox.

## Standing product instructions (Claude flow)

These decisions stay in force for this branch and later Construction PRs (same answers as the Godot / iOS plan interview):

| # | Decision |
|---|---|
| Platforms | **Web + PC wrapper + iOS**, with **cross-play** between them |
| First TestFlight | Start from the **web client** (touch + phone layout already there) |
| Engine | **Godot everywhere** — one codebase for web / PC / iOS long-term; web three.js stays the live client until Godot parity |
| Priority | **Playable on iPhone soonest** — do not block the Godot / protocol path |
| App Store v1.0 | **Everything** in scope eventually; ship Construction as data-first content, unlock gameplay in follow-ups |

How this PR respects that:

- Content lands in `shared/*.json` so a Godot client can load the same mode / weapons / map later.
- Construction is **offline-only** until cross-play host parity exists (`netMode` → Classic).
- No protocol (`PROTO`) bump and no new `cls` values — parallel Claude class / mobile / Godot PRs keep merging.
- Boss rush and cosmetics stay documented follow-ups, not blockers for iPhone.

See also [`docs/IOS_PLAN.md`](IOS_PLAN.md) and [`docs/PROTOCOL.md`](PROTOCOL.md).

## Shipped in this PR (scaffold)

| Piece | Id / notes |
|---|---|
| Mode | `construction` — locked “Coming soon” in the mode list |
| Map | `siteyard` / Site Yard — exclusive stub worksite |
| Weapons | `hammer` (Claw Hammer), `wirewhip` (Live Wire), plus existing `blower` (Air Blower) |
| Online | `netMode` maps Construction → Classic; button hidden in host/create-room flow |
| Classes | None — loadouts are mode-only weapons, not new character classes |

Edit tables in `public/index.html`, then run `npm run content` so `shared/*.json` stays in sync.

## Godot / iOS: playable offline

Construction is playable offline in the Godot game (the web game still shows it as a scaffold).

| Piece | Where |
|---|---|
| Mode picker | Title screen, Offline tab: **Mode** (Classic / Construction) shares a row with **Floor**; Settings key `mode`, world `mode_id` / `--mode=construction`. `scripts/main.gd` `maps_for(mode)`: a mode with its own maps (`only` in maps.json) lists just those, so Construction offers **Site Yard** only and Classic keeps Sunny Arena / Practice Range |
| Rules | `Combat.set_mode("construction")`: everyone (player and bots) spawns and respawns with the Claw Hammer (`start`), crates only drop the mode's allow list from `drops.json` (heal, hammer, Live Wire, Air Blower, speed / rage / shield) |
| Site Yard | Built by `MapBuilder` like every map (88 boxes, 2 bounce pads, floor pad, no ladders). Dynamic floors: the hazard stripes anchor the floor, so only Drift (2 blocks) runs, same as the web (`node tools/test-dynamics.js --table`) |
| Claw Hammer, Live Wire | The data-driven melee path (`Combat.melee_begin/tick/sweep`, tip / thick / lift / topple / hitSfx / speedMul / ammo from weapons.json); parity tested in the `melee2` block. Bots swing the start hammer |
| Air Blower | `Weapons.blower_tick`, a line-by-line port of the blower branch of `playerControl` (same order of random calls); parity tested in the `blower` block of `npm run test:godot-combat`. Now also drops in Classic crates in Godot, as on the web. HUD shows its ammo in % |
| Test | `npm run test:godot-construction` (`godot/tests/construction_test.gd`): Mode picker, Site Yard build + floors, crate pool, a 30 s Construction match (hammer start, bot hammers, the blower pushes / stuns / drains) |
| Screenshots | `sh tools/shoot-godot-ui.sh "" title-construction construction` -> `docs/style/godot-ui-title-construction.png`, `docs/style/godot-ui-construction.png` |

Still follow-up in Godot: boss rush, the tradie extras below, online Construction (still offline-only; `NetMatch.apply_rules` maps it to Classic). As on the web, bots never pick up hammer / Live Wire / blower crates (`BOT_GUNS`) and never use the blower (with it in hand they swing the spatula); the blower's puff and whoosh are simplified visuals.

## Unlock follow-up (playable v1)

1. Remove the locked class / “Coming soon” blurb once combat + bots feel good offline.
2. Start weapon / crate pool already filter to hammer, Live Wire, blower.
3. Optional tradie tips on the home screen and a Builder-skin suggest in the locker.

## Boss rush follow-up (from brainstorm)

Offline ladder of site bosses, patterned after Weapon Ladder (`gungame`) / Pillars init:

1. Engineer  
2. Designer  
3. Supervisor  
4. Project Manager  
5. The Client (final)

Suggested rules: one life per boss wave, escalating HP / damage / knockback, each boss favours a tool (plans, red tape net, clipboard bat, contract rocket). Keep it offline until the mode is stable.

## Extra ideas worth a later PR

- **Hard-hat hats / hi-vis skins** — cosmetic only; Builder skin already exists.
- **Scaffold dash** — short climb boost on scaffold boxes (mode flag, not global movement change).
- **Cone traps / wet-cement pads** — slow or sticky floor pads on Site Yard only.
- **Toolbox crates** — Construction-only crate table (tools + rare “site plan” that marks rivals briefly).
- **Tradie callouts** — short KO lines per weapon (“That’s going in the variation!”) without touching netcode.
- **Wobble Workshop bridge** — later, unlock Sandbox block place/remove *inside* Construction for temporary cover (still offline).

## Merge notes

- Do not expand `PROTO` or require guests to understand Construction.
- Prefer additive edits near `MODES`, `WEAPONS`, `MAPS.siteyard`, and `netMode` so parallel Claude PRs on classes / mobile UI stay easy to merge.
- After merge conflicts in `public/index.html`, re-run `npm run content` and `npm test`.
