# Construction DLC (Unit A: Data & Assets)

Design documentation for Unit A of the Construction DLC in Wobblers Arena.

## Overview
Unit A introduces 9 new construction-themed tools, a 6-stage Arcade boss rush configuration, full 5-language localization, and Godot-exclusive additive data loader hooks.

## Tools Table

| ID | Name | Type | Dmg | Force | Cooldown | Ammo | Key Stats / Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pipewrench` | Pipe Wrench | `melee` | 38 | 24 | 1.1s | 6 | Heavy melee, swingTime 0.52s, tip 1.8m, topple 0.65, slow whack |
| `nailgun` | Nail Gun | `gun` | 5 | 2.5 | 0.16s | 48 (mag 24) | Rapid short-range (20m) nailgun, 2 pellets/shot, reload 1.4s |
| `jackhammer` | Jackhammer | `gun` (punch) | 10 | 10 | 0.22s | 20 | Rapid close-range (5.5m) punch style, topple 0.5, steady knockback |
| `spiritlevel` | Spirit Level | `melee` | 16 | 8 | 0.45s | 12 | Fast, light melee with long reach (tip 2.85m), swingTime 0.22s |
| `tapemeasure` | Tape Measure | `melee` | 20 | 10 | 0.6s | 10 | Long whip-like melee (tip 3.3m), high lift 0.75 |
| `cementbucket` | Cement Bucket | `ball` | 26 | 28 | 1.3s | 3 | Thrown ball projectile with slow lob, throwSpeed 9.5m/s |
| `conelauncher` | Cone Launcher | `knife` | 34 | 14 | 0.75s | 6 | Thrown traffic cone projectile, speed 30m/s |
| `anglegrinder` | Angle Grinder | `gun` (flame) | 2.2 | 1.4 | 0.06s | 60 | Close-range (6.5m) spark shower, burn 2.5s DPS |
| `drill` | Cordless Drill | `melee` | 12 | 6 | 0.28s | 18 | Very fast stab-like melee, swingTime 0.18s, tip 1.35m |

## Boss Rush Stages Table

| Stage | ID | Name | Boss | HP Bar Color | Bots | Events | Rewards (Clear / First) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `tradies` | Tradies | No | `#ffa500` (16753920) | Dazza (Claw Hammer), Bluey (Pipe Wrench), Sparky (Live Wire), Chippy (Tape Measure) | None | 100 / 250 coins |
| 2 | `engineer` | Engineer | Mini-boss | `#4aa3d8` (4891608) | Chief Engineer (Nail Gun, 2.5x HP, hard) | Falling load test crates every 12s | 150 / 350 coins |
| 3 | `designer` | Designer | Boss | `#e53935` (15022389) | Lead Designer (Spirit Level, 2.8x HP, speed 1.25x) | Revision boost pads every 15s | 200 / 450 coins |
| 4 | `supervisor` | Supervisor | Boss | `#ff8000` (16744448) | Site Supervisor (Angle Grinder, 3.5x HP) | Backup call at 50% HP (2 tradies) | 250 / 600 coins |
| 5 | `project_manager` | Project Manager | Boss | `#8ec27a` (9356410) | Project Manager (Cone Launcher, 4.2x HP) | Deadline floor shrink; Scope creep extra bot spawns | 350 / 800 coins |
| 6 | `the_client` | The Client | Final Boss | `#ffd700` (16766720) | The Client (Jackhammer, 5.5x HP, insane) | Giant 1.5x scale; Change request weapon swaps at 66% & 33% HP | 500 / 1500 coins |

## Data Files & Merge Pipeline

1. **Weapons (`godot/data/extra/construction/weapons.json`)**:
   - Modelled on `ExtraClasses`, loaded through `ExtraWeapons`.
   - `ExtraWeapons.merge(weapons)` merges missing keys into `Content.weapons` and `Combat.weapons_data`.
   - Does not mutate or overwrite any shared weapons from `shared/weapons.json`.

2. **Modes (`godot/data/extra/construction/modes.json`)**:
   - Extends the `allowWeapons` list of the `construction` mode only.
   - `ModeRules.merge_extra()` includes an additive hook that extends existing modes' `allowWeapons` without modifying other modes.

3. **Stages (`godot/data/extra/construction/stages.json`)**:
   - Self-contained arcade boss rush table.
   - Validates all referenced cosmetics (skins and hats) against `godot/data/cosmetics.json`.

4. **Translations (`godot/i18n/src/92-construction-data.json`)**:
   - Contains 5 language translations (`zh_TW`, `zh_CN`, `ja`, `fr`, `es`) for all weapon names, stage names, taglines, and event announcements.
   - Integrated via `tools/i18n.js` into `godot/i18n/strings.json` and `public/i18n-data.js`.

## Parity Guarantees

- **Untouched Shared Data**: `shared/*.json`, `godot/data/weapons.json`, and `godot/data/modes.json` are completely unmodified, preserving bit-exact parity with the web reference.
- **Combat Math & Sim Integrity**: No new weapon simulation code is introduced; all tools leverage proven existing combat types (`melee`, `gun` with punch/flame styles, `ball`, `knife`).
- **No RNG Drift**: Crate draws and bot decisions in existing modes remain unchanged in sequence and frequency.
- **Mode Isolation**: DLC weapons are flagged `constructionOnly: true` and are restricted to Construction mode.

## How to Add a Tool

1. Add the tool entry to `godot/data/extra/construction/weapons.json` following the `shared/weapons.json` schema, marking `"constructionOnly": true`.
2. Add its id to the `allowWeapons` list in `godot/data/extra/construction/modes.json`.
3. Add localized display names to `godot/i18n/src/92-construction-data.json`.
4. Run `node tools/i18n.js` to build strings.
5. Add test coverage in `godot/tests/construction_data_test.gd` and run `npm run test:godot-construction-data`.

## Unit B: the generated Building Site, props and PPE

**Map `sitegen` ("Building Site")**, Construction mode only (`ModeRules.MODE_MAPS["construction"] = ["siteyard", "sitegen"]`; `siteyard` is untouched).
`SiteMap.generate(seed)` (godot/dlc/construction/site_map.gd) returns a full maps.json-shaped level made of boxes, ladders and bounce pads only, so physics
and collision need no change. `SiteMap.current_seed` / `set_seed(s)` pick the seed; `MapBuilder.build("sitegen")` calls `generate(current_seed)` the way it
completes Pillars, and `Content` only registers `SiteMap.header()`. The layout uses its own mulberry32 generator seeded from the seed: no combat RNG draws.
The same seed always gives the same level (cached per seed); `SiteMap.layout(seed)` also returns the machine rectangles and fence box indices for tests.

Layout: a 64 x 64 m slab (first box = the floor), a site fence (2.8 m panels and posts, 1-2 six metre gates per side, hazard stripes inside each gate),
then props placed as rectangles 3 m apart (big machines 6 m apart, 3.5 m inside the fence), each turned by a random multiple of 90 degrees:
excavator, bulldozer, tower crane (each present with 80 % chance, at least two), 2-4 spoil heaps, 1-3 pipe stacks, 2-4 containers (30 % stacked),
2-3 scaffold towers, a trench with a bounce pad (70 %), a concrete mixer (60 %), cone clusters, jersey barriers, hazard-stripe and dirt decals.
Typically 260-400 boxes (hard limit 690, the batching budget). Colours stay in the construction palette (`SiteProps.palette()`).

Props (godot/dlc/construction/site_props.gd): `excavator`, `bulldozer`, `crane`, `spoil_heap`, `pipe_stack`, `container`, `scaffold` (the siteyard
piece with rails, steps or a ladder), `trench`, `mixer`, `cones`, `barriers`, `hazard_strip`, `fence_run`. Each returns boxes, ladders, pads and a
free-space rectangle; `place(prop, x, z, rot)` turns and moves it.

Playability rules (verified for seeds 1..200 by `npm run test:godot-site-map`, using `SiteNav`, a walk / jump / ladder / pad graph over a 1 m grid):
spawns, player and bot spots are on floor at least 2 m from any prop (8 spawns, 14 bot spots, 12+ crate drops, a few raised on heap summits, scaffold decks
and machine roofs); every top above 1.5 m is a 0.55 m step, a jump of 2.0 m or less (jump 9.2 m/s at GRAV 24 lifts 1.76 m, a landing steps 0.55 more), a ladder,
a set of steps or a bounce pad away (the crane load is reached by its pad); the fence is 2.8 m, taller than anyone can jump, so it is never a platform.
Bots do not use ladders (only the local player does), so ladder-only tops (crane jib, tall scaffolds, containers) are player spots.

**PPE.** `WobblerLooks`: the Builder outfit now builds a hi-vis vest (silver reflective bands and braces front and back over the orange torso); hats
`hardhat` (yellow), `hardhat_white` and `hardhat_orange` are added to the Wobbler hats via `locker.json` `extra_hats` (merged into `cosmetics.hats` by
`WobblerLooks.data`; labels in `hat_label`, rarity `common` in `hat_rarity`, no icon). In Construction every bot is a tradie: `MatchSim._dress_tradies`
sets skin `builder`, a hard-hat variant and a trade name (Dazza, Bluey, Sparky, Chippy, Spud, Tradie Tom, Foreman Fred); presentation only.

**Tool models.** `WeaponModels.DLC_KEYS` (pipewrench, nailgun, jackhammer, spiritlevel, tapemeasure, cementbucket, conelauncher, anglegrinder, drill) are
built by `WeaponModels.build` from LowPoly primitives; `KEYS` still mirrors shared/weapons.json.

Screenshots: `godot --path godot --resolution 1280x720 --script res://tests/site_shots.gd -- --no-save --out DIR [--seeds 1,2,3] [--what sites|tools|ppe]`.
