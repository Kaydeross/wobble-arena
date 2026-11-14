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
| `anglegrinder` | Angle Grinder | `gun` (flame) | 1.5 | 1.2 | 0.08s | 30 | Short-range (5m) spark shower, burn 1.5s, limited fuel |
| `drill` | Cordless Drill | `melee` | 12 | 6 | 0.28s | 18 | Very fast stab-like melee, swingTime 0.18s, tip 1.35m |

## Boss Rush Stages Table

| Stage | ID | Name | Boss | HP Bar Color | Bots | Events | Rewards (Clear / First) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `tradies` | Tradies | No | `#ffa500` (16753920) | Dazza (Claw Hammer), Bluey (Pipe Wrench), Sparky (Live Wire), Chippy (Tape Measure) | None | 100 / 250 coins |
| 2 | `engineer` | Engineer | Mini-boss | `#4aa3d8` (4891608) | Engineer (Cordless Drill, 2.8x HP, damage 1.6x, speed 1.2x, hard) | Falling load test crates every 12s; tool crates | 150 / 350 coins |
| 3 | `designer` | Designer | Boss | `#e53935` (15022389) | Lead Designer (Spirit Level, 3.4x HP, damage 1.8x, speed 1.3x) | Revision boost pads every 15s; tool crates | 200 / 450 coins |
| 4 | `supervisor` | Supervisor | Boss | `#ff8000` (16744448) | Supervisor (Pipe Wrench, 3.6x HP, damage 0.6x, speed 0.9x) | Backup call at 50% HP (1 tradie); tool crates | 250 / 600 coins |
| 5 | `project_manager` | Project Manager | Boss | `#8ec27a` (9356410) | Project Manager (Tape Measure, 4x HP, damage 1.4x, speed 1.08x) | Deadline floor shrink; Scope creep; tool crates | 350 / 800 coins |
| 6 | `the_client` | The Client | Final Boss | `#ffd700` (16766720) | The Client (Giant Mallet, 4.8x HP, damage 1.35x, speed 1.05x, insane) | Giant 1.5x scale; melee change requests at 66% & 33% HP; tool crates | 500 / 1500 coins |

Bosses start with melee tools. Nail Guns, Angle Grinders, Jackhammers, Cone Launchers and Cement Buckets arrive only in
boss-stage weapon crates. A boss may claim a ranged crate while carrying melee, then returns to melee when its limited
ammo runs out; the periodic kit refill applies only to the melee tool.

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

**Co-op friendly fire (two seats).** A seat's weapon, projectile or explosion never hurts the other seat: `Combat.seat_mates()` blocks it in `Combat.hit` before both the local damage and the online `h` relay, so offline two-seat play and an online co-op room behave the same. The stage's crew, enemy fire and unowned hazards have no seat as attacker, so they are unaffected and still hurt every seat. Friendly fire is **off on every difficulty by default**; the difficulty step has a small **Friendly fire** toggle (owner decision) that writes `Settings arcade_ff`, `HostSession.arcade_ff` reads it for an Arcade room (`opts.arcade_ff` wins when given), and it travels in `start.arc.ff` so the host and every guest apply the same rule (online included; crew still hurts both). `ArcadeManager.friendly_fire` feeds `Combat` in `setup_sim` / `_bind_guest_seats`. Tested in `arcade_test.gd`: off by default, seat-to-seat hit ignored (local and ghost relay), crew and hazards still hurt both, the option on really hurts, and the arc snapshot/stage_arc/online managers adopt it. The public `start.arc` field is Godot-only, like `gm`.

**Difficulties** (`stages.json` top-level `difficulties`; Nightmare is the table exactly as it was before the difficulties existed). `ArcadeManager._dress` / `enemy_hp` apply them to every enemy (summoned and creeping tradies too), `StageEvents.setup` scales every `every` / hold time, `start_run` sets the lives, `scaled()` the coins:

| | hp x | hp floor (crew / boss) | damage x | speed x | events x slower | lives | coins x |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Easy | 0.4 | 0.8 / 1.2 | 0.35 | 0.85 | 1.5 | 5 | 0.6 |
| Normal | 0.7 | 0.9 / 1.4 | 0.65 | 1.0 | 1.15 | 4 | 1.0 |
| Nightmare | 1.0 | none | 1.0 | 1.0 | 1.0 | 3 | 1.5 |

The result is x the table's hp, never below the floor and never above the table's own value; boss phases (66 / 33 %) are unchanged. Saves: `dlc.arcade_best` and `dlc.arcade_clears` are dictionaries keyed `easy` / `normal` / `nightmare`; an older save with the single int / Array is moved under `nightmare` (it was played at the old balance), nothing is lost. The first-clear coins of a stage are paid once PER difficulty; the victory bonus (2000 x coin multiplier) once per difficulty. The Site Foreman hat comes with the first victory on Normal or Nightmare (an Easy victory pays coins only and its card says "Win on Normal or Nightmare for the Site Foreman hat").

**Difficulty tuning.** `godot/tests/arcade_balance.gd` (not in `npm test`, about 25 minutes for the full 3 difficulties x 6 stages x 8 seeds; run the difficulties in parallel processes): `godot --headless --path godot --script res://tests/arcade_balance.gd -- --no-save --seeds=8`. The scripted melee player of `arcade_test.gd` (the starting Wobbler, normal damage, no healing, one life, 100 s limit) fights each stage once per seed against the table's own bot skills. Wins out of the seeds, and the player's average health left on a win. These are the numbers for the table as it stands after the melee retune (below):

| Stage | Easy (8 seeds) | Normal (8 seeds) | Nightmare (8 seeds) |
| --- | --- | --- | --- |
| 1 Tradies | 7/8, 76 % hp left | 6/8, 42 % | 3/8, 32 % |
| 2 Engineer | 8/8, 95 % | 8/8, 75 % | 7/8, 47 % |
| 3 Designer | 8/8, 85 % | 7/8, 54 % | 3/8, 33 % |
| 4 Supervisor | 7/8, 71 % | 2/8, 24 % | 0/8 |
| 5 Project Manager | 8/8, 85 % | 3/8, 28 % | 0/8 |
| 6 The Client | 7/8, 55 % | 3/8, 27 % | 0/8 |
| All stages | 45/48 (94 %) | 29/48 (60 %) | 13/48 (27 %) |

The scripted player is a crude yardstick (it only walks at the nearest enemy and swings, never dodges, and is weak against several attackers), so use the numbers for the ordering Easy > Normal > Nightmare and not as absolute difficulty: a real player who keeps away from a melee boss fares much better than the probe, which stands in the Pipe Wrench / Giant Mallet. The deterministic checks are in `arcade_test.gd`: the tuned multipliers, Easy < Normal < Nightmare health for every enemy and boss, the boss health ladder Engineer < Designer < Supervisor at every difficulty, lives, per-difficulty coins and the hat rule. Before this pass the same probe read (8 seeds): Engineer Normal 8/8 with 90 % health left, Designer Normal 8/8 with 78 %, Supervisor Normal 1/8 and Nightmare 0/8 (the two ends of "trivial" and "unfair"); the melee retune below fixes both.

**Health Packs and the early bosses (balance pass 2).** Enemies that grab a Health Pack used to heal 60 % of their max health, which made the bosses almost unkillable on Easy. Arcade enemies now heal `boss_heal` of their max health per pack: 5 % Easy, 8 % Normal, 10 % Nightmare (`FighterState.heal_frac`, set in `ArcadeManager._dress`; the player's pack is still 60 %). The boss health floors are 1.2 (Easy) and 1.4 (Normal); Nightmare keeps the table's health as written.

**Melee retune (balance pass 3).** With the bosses on melee tools the scripted player's hammer could stunlock the low-force early bosses (Engineer 8/8 with 90 % health left on Normal, 8/8 with 75 % on Nightmare) while the Supervisor's Pipe Wrench (force 24, not scaled by `dmg_scale`) stunlocked the player (1/8 Normal, 0/8 Nightmare). The early bosses take the biggest buffs: Engineer hp 2.0 / damage 1.0 / speed 1.05 -> 2.8 / 1.6 / 1.2, Designer 3.0 / 1.45 / 1.2 -> 3.4 / 1.8 / 1.3. The Supervisor becomes a tanky, low-damage summoner: hp 3.0 -> 3.6, damage 0.9 -> 0.6 (the data floor), speed 0.95 -> 0.9; it keeps its one-tradie backup call at 50 % health. The Project Manager moves to 4.0 / 1.4 / 1.08 and The Client stays at 4.8 / 1.35 / 1.05 (the giant mallet already hurts). Boss health now climbs Engineer 2.8 < Designer 3.4 < Supervisor 3.6 < Project Manager 4.0 < The Client 4.8 at every difficulty (the floors keep the same order on Easy), checked in `arcade_test.gd`. The Supervisor is still the hardest stage for the non-dodging probe (2/8 Normal, 0/8 Nightmare): its damage is already at the `dmg_scale` floor of 0.6, so the rest of its sting is the pipe wrench's knockback; a human who keeps away, as the melee change intends, has a much better time than the probe.

**Ring-out rule (owner report: "boss drop off from edge = stage clear").** `MatchSim._ring_out` leaves a bot that falls off
the site `dead` with its health intact and `fell_t` set. A fall is **never a K.O.**: `ArcadeManager._fight` now decides by
health, not by the transient `fell_t` flag, so only `hp <= 0` marks an enemy down — no flag, respawn or clear path can turn
a ring-out into a stage clear. A fallen enemy (boss or crew, boss stages and Tradies alike) is put back **on the floor**
(the bot spot farthest from the nearest living player, via `_safe_spot()`), with the **health fraction it had**, its trade
tool in hand and 1.5 s of invulnerability; the fight continues. One fall is exactly one revive (`ArcadeManager.revived`
counts them; no fall/revive churn), a ring-out pays nothing and records no clear, and a later real K.O. still pays and
records the stage exactly once. Checked in `arcade_test.gd` (`_boss_ring_out`: every boss stage, a `fell_t`-lost case,
two falls in a row, crew on a boss stage, Tradies, the clear flow after a fall). On this build the plain shove was already
revived by the M2 `fell_t` path; the `fell_t`-lost case reproduces the owner's clear on the old decider (`dead && !fell_t`
called `_down` -> `_cleared` -> paid and recorded), and now revives. The AFTER balance table above is measured with the fix;
the BEFORE one included free ring-outs.

**Last-two-stage fixes.** (1) The Client (and any Giant: Chaos mode too) was drawn away from his own body. `World.present` scaled the Fighter node by 1.5 about the world origin, but the wobbler places itself in world space, so the model sat at 1.5 x his position (about 15 m off near the arena edge) and the hand / shoulder points his swings read back from the rig were off too: he looked like he walked through things and his hits missed (about a quarter of a normal boss's damage with the same swings). The view now scales about his feet (node position = feet x (1 - k)). (2) The Project Manager's deadline closed the collision floor while the visible ground (`FloorPad`, a flat 58 m plane) stayed full size, so everyone dropped off ground that still looked solid; the pad now shrinks with the floor. (3) Scope-creep / backup workers could spawn on a spot the shrunk floor no longer covers and fall straight off; they now spawn on the remaining floor. Checked in `arcade_test.gd`.

**What the stage table drives** (`ArcadeManager._dress`): each bot's name, skin, hat, colour, tool (`give_weapon`, topped up every 0.5 s so tools never run dry), `hp` (x the
Health setting, via `cls_hp`), `dmg_scale` (x the skill's damage), `speed` (see "Boss movement speeds" below) and `difficulty` (its own `BotBrain`; `bot_brain.gd` itself is untouched).
The stage table is the ONLY stat authority: `_arcade_line()` neutralises every multiplier the placeholder fighter class
carries (`cls_dmg`, `cls_kb`, `cls_rate`, `cls_reload`, `cls_ammo`, `speed_mul`, `accel_mul`, `air_mul`, `jump_mul`), because
the placeholder class is a bit of `BOT_CLASS_ORDER` slot bookkeeping, not a design stat. Bots are not hostile to each other
(`combat.ffa = false`). The Client's `giant_scale` makes him a Giant (`big_t`, 1.5 x model; health and damage are divided
back so the table's numbers hold). Boss phases at 66 % and 33 % health: damage x1.2 each and a small additive speed step
(+5 %, then +10 % of the base in total, never compounding), with a toast; stages with `change_request` also swap tools.

**Boss movement speeds (owner report: "the Designer is too fast with its speed buff").** Measured against the player's
7.5 m/s base (`FighterPhysics.speed`), every boss now walks in a band: slow melee tank 5.0-6.0, normal 6.0-7.2, fast
6.8-7.4. The base is the table's bot-skill speed x the entry's `speed` multiplier, clamped into the band, then x the
difficulty's `speed_mul` (Easy 0.85). The permanent boss cap is **7.4** (base + phase steps, a player can always outrun
it); a temporary Speed Boost pickup may reach **8.5** and is a short 2 s burst (the player's boost is still 12 s), and a
burst that would pass the cap is cancelled instead of making a near-cap boss slower. The phase speed steps are additive
(+5 %, then +10 %, never the old x1.1 per phase = x1.21) and capped. No melee lunge multiplier exists in the port: a
weapon's `dash` is a fixed impulse, identical for the player and every boss.

| Boss | Before: solo base / phase 2 | Before: co-op base / phase 2 | After: base -> phase 2 | Band |
| --- | --- | --- | --- | --- |
| Engineer | 5.70 / 6.90 | 7.91 / 9.57 | 6.48 -> 7.13 | normal |
| Designer | 6.18 / 7.48 | 8.56 / 10.36 | 7.02 -> 7.40 | fast |
| Supervisor | 4.28 / 5.18 | 5.93 / 7.17 | 5.00 -> 5.50 | slow |
| Project Manager | 5.13 / 6.21 | 7.12 / 8.61 | 6.00 -> 6.60 | normal |
| The Client | 5.91 / 7.15 | 8.20 / 9.92 | 6.72 -> 7.39 | normal |

The co-op column is the root cause of the report: `_dress` overrode HP/speed but left the placeholder **class** multipliers
on the fighter, and the class comes from the bot's slot (`BOT_CLASS_ORDER`): a solo boss was a Bruiser (`spd 0.88`, `kb
0.65`, `dmg 1.12`) and a two-seat co-op boss a Scamp (`spd 1.22` = **39 % faster**, `kb 1.3` = 2x the knockback taken,
`dmg 0.92`, `air 1.3`). The class line is neutralised now, so a boss (and the crew) has exactly the same walk speed,
knockback, damage, attack rate, reload, ammo, acceleration, air control and jump in solo and co-op. Tests:
`arcade_test.gd` `_boss_speeds` asserts each boss' band, the stage cap, the additive phase steps, the burst cap and
duration, and identical solo/co-op stat lines for a boss and the Tradies crew; `_phases` checks the +5/+10 % steps.
The "Difficulty tuning" probe table above predates the Arcade stat line (solo bosses dealt x1.12 damage and took x0.65
knockback through the Bruiser class), so re-run `godot/tests/arcade_balance.gd` before the next tuning pass; a 2-seed
Normal sanity run after the change stayed in the same range (no free ring-out wins, 20-40 s fights).

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
records and the hat, two-seat co-op (seats, auto-revive, shared lives, per-seat pay) and co-op friendly fire (off by default, the option, crew unaffected), the
ring-out rule (a fall never clears/pays/records, one revive per fall, the boss back on the floor with its health and tool, a later real K.O. still clears and pays,
crew and Tradies falls too) and the speed audit (boss bands, permanent cap, additive phase steps, the short burst cap, and identical solo/co-op stat lines), a
Classic match afterwards). Screenshots: `godot --path godot --resolution 852x393 --script res://tests/ui_shots.gd -- --no-save --shot arcade-<intro|fight|engineer|client|clear|victory> --out FILE.png`.
