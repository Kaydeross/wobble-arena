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

## The DLC front end (Unit C: unlock, hub, title banner)

- **Entry**: a wide hazard-tape banner on the title (below Walldrobe / Shop / Goals, drawn in code, `dlc/construction/construction_style.gd`) opens the hub (`construction_hub.gd`). Construction is no longer a game type card in the setup wizard; the mode id and `ModeRules.OFFLINE_ONLY` are unchanged.
- **Unlock** (`dlc_unlock.gd`, state in `dlc_save.gd`): 1500 coins (`DlcUnlock.PRICE`) or the developer code. Save blob key `dlc` = `{owned, arcade_best, arcade_clears, bonus}`, written only once the DLC is touched (old saves load as locked; the web game ignores the key). The code is never stored or logged: only `sha256("wobblers-arena-dlc-v1:" + code)` is compared with `DEV_HASH`. A right code unlocks the DLC, every outfit, emote and class (secret ones too), pays 5000 coins once and adds `dev` to the wallet codes; three wrong tries start a 1.5 s cooldown. The code field is on the hub (Enter code) and in Settings > About (tap the version line 7 times).
- **Hub**: Classic (pre-match card: bots 1..7 default 7, bot skill, site seed Random / Re-roll, Start) and Arcade ("Coming soon" until `res://dlc/construction/arcade_manager.gd` exists; the hub emits `arcade_requested` for the arcade manager to hook). Start writes the Settings keys `mode = construction`, `bots`, `difficulty`, `offline_map` (`sitegen` when that map is registered, else `siteyard`) and `site_seed` (0 = a new random site every match), then calls `main.play_offline({...})`.
- Tests: `npm run test:godot-dlc-ui` (`godot/tests/dlc_ui_test.gd`), plus the `dlc-*` screens in `ui_layout_test.gd`.
