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
## The DLC front end (Unit C: unlock, hub, title banner)

- **Entry**: a wide hazard-tape banner on the title (below Walldrobe / Shop / Goals, drawn in code, `dlc/construction/construction_style.gd`) opens the hub (`construction_hub.gd`). Construction is no longer a game type card in the setup wizard; the mode id and `ModeRules.OFFLINE_ONLY` are unchanged.
- **Unlock** (`dlc_unlock.gd`, state in `dlc_save.gd`): 1500 coins (`DlcUnlock.PRICE`) or the developer code. Save blob key `dlc` = `{owned, arcade_best{easy,normal,nightmare}, arcade_clears{easy,normal,nightmare}, bonus}`, written only once the DLC is touched (old saves load as locked; the web game ignores the key). The code is never stored or logged: only `sha256("wobblers-arena-dlc-v1:" + code)` is compared with `DEV_HASH`. A right code unlocks the DLC, every outfit, emote and class (secret ones too), pays 5000 coins once and adds `dev` to the wallet codes; three wrong tries start a 1.5 s cooldown. The code field is on the hub (Enter code) and in Settings > About (tap the version line 7 times).
- **Hub**: Classic (pre-match card: bots 1..7 default 7, bot skill, site seed Random / Re-roll, Start) and Arcade ("Coming soon" until `res://dlc/construction/arcade_manager.gd` exists; the hub emits `arcade_requested` for the arcade manager to hook). Start writes the Settings keys `mode = construction`, `bots`, `difficulty`, `offline_map` (`sitegen` when that map is registered, else `siteyard`) and `site_seed` (0 = a new random site every match), then calls `main.play_offline({...})`.
- Tests: `npm run test:godot-dlc-ui` (`godot/tests/dlc_ui_test.gd`), plus the `dlc-*` screens in `ui_layout_test.gd`.

## Unit D: the Arcade boss rush

**Flow.** Title > Construction > Arcade card (enabled once `dlc/construction/arcade_manager.gd` exists and the DLC is owned) > **class step** (the Character page of the setup wizard, `SetupWizard.class_only`: only owned classes, the last class preselected, six stat bars, scrolls with DragScroll) > **difficulty step** (Easy / Normal / Nightmare cards, green / amber / red, best result per difficulty, Start) > `main.play_arcade()` >
`ArcadeManager.launch()` builds a World with `world.arcade` set. `start_run(seed)` picks the run seed (the stage sites are `base + map_seed_offset`, +1009 per retry)
and the difficulty's lives (5 / 4 / 3). Per stage: **intro card** (stage no., name, tagline, the boss portrait in its table colour, Start; the match is frozen behind it) > fight > **stage clear
card** (name, time, K.O.s, coins, Next stage / Quit run) or **stage failed card** (lives left, Retry stage / Quit run) > after the sixth stage the **victory card**.
Dying (or falling out) ends the attempt after 1.8 s, costs a life and retries the SAME stage on a fresh site; no lives left = **run over** card. Stage clear = the boss is
down (stages with `boss: true`; the crew that is left gives up) or every enemy is (stage 1). Enemies that go down never respawn. Quit run = back to the title.

**Rewards.** `coin_reward + first_clear_bonus` is paid ONCE per stage, the first time it is cleared (`Save.dlc.arcade_clears`); a replay pays only the normal K.O. coins.
`arcade_best` = furthest stage cleared. The victory (after The Client) pays 2000 bonus coins once and unlocks the exclusive **Site Foreman Hard Hat** (`foreman`, rare;
`locker.json` `extra_hats` + `exclusive_hats`, listed by `LockerData.hats()` only after the victory; remembered as the pseudo stage id `_victory` in `arcade_clears`).

**Class and difficulty pick.** The class step writes the Settings key `class` exactly like the setup wizard does (so the pick also becomes the normal class), the difficulty step writes `arcade_diff` (default `normal`). `main.play_arcade` reads both and calls `ArcadeManager.launch(0, diff, class)`: `World.player_class` keeps the class for every stage and retry of the run. The Classic card is unchanged. The run strip of the HUD names the difficulty ("Normal - Stage 2 / 6 - Lives 4"), the intro card shows it too.

**Difficulties** (`stages.json` top-level `difficulties`; Nightmare is the table exactly as it was before the difficulties existed). `ArcadeManager._dress` / `enemy_hp` apply them to every enemy (summoned and creeping tradies too), `StageEvents.setup` scales every `every` / hold time, `start_run` sets the lives, `scaled()` the coins:

| | hp x | hp floor (crew / boss) | damage x | speed x | events x slower | lives | coins x |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Easy | 0.4 | 0.8 / 1.5 | 0.35 | 0.85 | 1.5 | 5 | 0.6 |
| Normal | 0.7 | 0.9 / 1.5 | 0.65 | 1.0 | 1.15 | 4 | 1.0 |
| Nightmare | 1.0 | none | 1.0 | 1.0 | 1.0 | 3 | 1.5 |

The result is x the table's hp, never below the floor and never above the table's own value; boss phases (66 / 33 %) are unchanged. Saves: `dlc.arcade_best` and `dlc.arcade_clears` are dictionaries keyed `easy` / `normal` / `nightmare`; an older save with the single int / Array is moved under `nightmare` (it was played at the old balance), nothing is lost. The first-clear coins of a stage are paid once PER difficulty; the victory bonus (2000 x coin multiplier) once per difficulty. The Site Foreman hat comes with the first victory on Normal or Nightmare (an Easy victory pays coins only and its card says "Win on Normal or Nightmare for the Site Foreman hat").

**Difficulty tuning.** `godot/tests/arcade_balance.gd` (not in `npm test`, about 5 minutes per 8 seeds of two difficulties; run the difficulties in parallel processes): `godot --headless --path godot --script res://tests/arcade_balance.gd -- --no-save --seeds=8 --diffs=easy --stages=1,2,3`. The scripted melee player of `arcade_test.gd` (the starting Wobbler, normal damage, no healing, one life, 100 s limit) fights each stage once per seed against the table's own bot skills. Wins out of the seeds, and the player's average health left on a win:

| Stage | Easy (8 seeds) | Normal (8 seeds) | Nightmare (6 seeds) |
| --- | --- | --- | --- |
| 1 Tradies | 7/8, 75 % hp left | 6/8, 51 % | 3/6, 22 % |
| 2 Engineer | 8/8, 69 % | 4/8, 14 % | 2/6, 37 % |
| 3 Designer | 7/8, 91 % | 8/8, 67 % | 6/6, 46 % |
| 4 Supervisor | 6/8, 39 % | 5/8, 36 % | 2/6, 52 % |
| 5 Project Manager | 6/8, 57 % | 6/8, 46 % | 3/6, 60 % |
| 6 The Client | 6/8, 54 % | 3/8, 69 % | 1/6, 100 % |
| All stages | 40/48 (83 %) | 32/48 (67 %) | 17/36 (47 %) |

Easy is beatable on every stage including the final boss (6/8), Normal is a fair fight (about two wins in three, the Engineer and the final boss the hardest), Nightmare is the old balance (the final boss 1/6). Before tuning (Easy damage 0.6 / Normal 0.85) the same player won only 2/6 on Easy stage 2 and 0/6 on Normal stage 2, hence the lower damage multipliers. The first Easy / Normal pass used the lead's starting numbers (Easy 0.6, Normal 0.85 damage); the Easy speed went from 0.9 to 0.85.

The scripted player is a crude yardstick (it only walks at the nearest enemy and swings, never dodges, and is weak against several attackers and the Engineer's nail gun, strong against slow bosses), so use the numbers for the ordering Easy > Normal > Nightmare and not as absolute difficulty. The deterministic checks are in `arcade_test.gd`: the tuned multipliers, Easy < Normal < Nightmare health for every enemy and boss, lives, per-difficulty coins and the hat rule.

**Health Packs and the early bosses (balance pass 2).** Enemies that grab a Health Pack used to heal 60 % of their max health, which made the bosses almost unkillable on Easy. Arcade enemies now heal `boss_heal` of their max health per pack: 5 % Easy, 8 % Normal, 10 % Nightmare (`FighterState.heal_frac`, set in `ArcadeManager._dress`; the player's pack is still 60 %). The ladder was also uneven: the Engineer (stage 2) was the hardest early fight and the Designer (stage 3) the easiest, so the Engineer went from hp 2.5 / damage 1.1 to 2.0 / 1.0, the Designer from hp 2.8 / damage 1.15 to 3.2 / 1.45, and the boss health floors from 1.5 to 1.2 (Easy) and 1.4 (Normal). Scripted player, 6 seeds, before to after: Engineer Normal 4/8 with 14 % health left to 6/6 with 52 %, Engineer Easy 8/8 with 69 % to 6/6 with 68 %; Designer Normal 8/8 with 67 % to 6/6 with 70 %. The scripted player never dodges, so the Designer still reads easier than it will for a person; boss health now climbs Engineer < Designer < Supervisor at every difficulty (checked in `arcade_test.gd`).

**What the stage table drives** (`ArcadeManager._dress`): each bot's name, skin, hat, colour, tool (`give_weapon`, topped up every 0.5 s so tools never run dry), `hp` (x the
Health setting, via `cls_hp`), `dmg_scale` (x the skill's damage), `speed` (x the skill's speed) and `difficulty` (its own `BotBrain`; `bot_brain.gd` itself is untouched).
Bots are not hostile to each other (`combat.ffa = false`). The Client's `giant_scale` makes him a Giant (`big_t`, 1.5 x model; health and damage are divided back so the
table's numbers hold). Boss phases at 66 % and 33 % health: speed x1.1, damage x1.2 each, a toast; stages with `change_request` also swap tools.

**Events** (`stage_events.gd`, driven by `ArcadeManager.step` after each sim step; own RNG = the run's, never the combat RNG):

| Type | Stage | Behaviour |
| --- | --- | --- |
| `load_test` | Engineer | every `every` s, `crate_count` crates drop (one near you); a red ring warns `warning_time` s ahead; the landing hurts everyone within 2.8 m (30 dmg) |
| `revision_pads` | Designer | every `every` s, 3 boost pads (bounce power x `boost_mul`) for `duration` s |
| `backup_call` | Supervisor | once, at `hp_threshold` of the boss' health: `summon_count` tradies (`summon_bots` names) join in |
| `deadline_shrink` | Project Manager | `ModeRules.shrink` on the site floor (the Mega / Shrink machinery): holds `every` s, closes in at `rate` m/s to `min_floor`, breathes back out and repeats; crate spots stay the map's own (`shrink["spots"]`) |
| `scope_creep` | Project Manager | every `every` s, `spawn_extra` more tradies, at most `max_extra` alive |
| `change_request` | The Client | at the boss phases: the boss (and you) get a random different tool; `giant_scale` |

`whistle shove` and `red-tape net` are not in `stages.json`, so they are not built (only types present in the table are implemented).

**HUD.** `arcade_boss_hud.gd`: a run strip ("Stage 3 / 6   Lives 2") and, while a boss stands, its bar in the stage's `hp_bar_color` (name inside, ticks at 66 / 33 %). It hangs in
the `MatchHud.TOP_STACK` slot under the toast, between the K.O. panel and the radar (and the kill feed); `World._update_mode_ui` starts the mode line under it. `hud_test.gd`
checks it at every phone / tablet size, both handedness settings (`npm run test:godot-ui`).

**World hooks** (all `if arcade != null`): `begin_stage` (top of `load_map`), `setup_sim` (after `MatchSim.setup`), `stage_ready` (end of `load_map`), `step` (after each sim step),
`show_panel` / `close_panel` / `add_view`; the kill cam is off in a run. Every other mode is byte-identical.

**How to add a stage.** Append an entry to `godot/data/extra/construction/stages.json` (`id`, `name`, `tagline`, `boss`, `hp_bar_color`, `map_seed_offset`, `coin_reward`,
`first_clear_bonus`, `bots[]`, `events[]`; see its `_readme`). Skins and hats must exist in `cosmetics.json`, tools in `weapons.json`. Add the name and tagline to a
`godot/i18n/src/*.json` file (5 languages) and run `node tools/i18n.js`. A new event type: a `case` in `StageEvents.update` plus its `_xxx` method. Extend
`godot/tests/arcade_test.gd` (the full run walks the whole table) and run `npm run test:godot-arcade`.

Tests: `npm run test:godot-arcade` (`godot/tests/arcade_test.gd`: all six stages with a boosted hammer, lives / retry / run over, events, phases, once-only coins, saved
records and the hat, a Classic match afterwards). Screenshots: `godot --path godot --resolution 852x393 --script res://tests/ui_shots.gd -- --no-save --shot arcade-<intro|fight|engineer|client|clear|victory> --out FILE.png`.
