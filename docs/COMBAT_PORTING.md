# Porting combat and weapons to Godot

How the combat logic in `godot/logic/` maps to the web game (`public/index.html`), and how to port the remaining weapons. Line numbers are approximate (b76); grep the symbol if they drift.

## Files

| Godot | Web game | What |
|---|---|---|
| `logic/fighter_state.gd` `FighterState` | `Fighter` fields (constructor ~4880) | gameplay state of one fighter; links its `FighterPhysics` (`phys`: pos/vel/grounded) |
| `logic/combat.gd` `Combat` | `Fighter.hit/topple/timers/respawn/placeAt/pickup/...` (~4950-5560), `addKo`, `shove`, `doKick`, `useAmmo` | damage, knockback, K.O., inventory, reload, kick, shove, melee swing + sweep |
| `logic/weapons.gd` `Weapons` | `fireGun` (~6300, incl. the flame branch), `PROJ` (~9735), `throwKnife/releaseKnife/updateKnives`, `launchRocket` (~6633), `explode/updateRockets` (~7314), `launchGrenade/updateGrenades` (~6721, ~7402), `shootArrow/updateArrows` (~6777), `shootNet/landNet/updateNets` (~7188), the bow lines of `playerControl` (~9811); batch 2: `throwShuriken/releaseShuriken`, `throwTyphoon/releaseTyphoon/tyInFlight` + the `ty` branch of `updateKnives` (~6984-7088), `throwBoomerang/releaseBoomerang/endBoomerang/updateBoomerangs` (~6856-6942), `shootSnake/updateSnakes` (~7090), `shootBall/updateBalls` (~7172, ~7265), `tridentLet/throwTrident/releaseTrident` (~6658) + the `w.throwable` lines of `playerControl` (~9855), `enemyInReach` (~10103) | ranged weapons and projectiles (`step_all` runs every list) |
| `logic/combat_rng.gd` `CombatRng` | `Math.random` | seeded random source (see Determinism) |
| `logic/net_snapshot.gd` `NetSnapshot` | `netStep` `S` entry (~8984), `h`/`ko` sends, `netCleanHit`/`netGuard` (~8703) | protocol encode/decode (docs/PROTOCOL.md 3.1) |
| `tests/combat_test.gd` + `tools/combat-reference.js` + `tools/test-combat.js` | | parity test (`npm run test:godot-combat`) |
| `tests/net_snapshot_test.gd` | | NetSnapshot round trip and junk rejection |
| `world/projectile_views.gd` `ProjectileViews` | `rocketGeo`, `makeArrowMesh`, `landNet` sheet, `explode` fireballs, `flameFx`, `makeShurikenMesh`, `makeTyphoonMesh`, `makeBoomerangMesh`, the snake segments, the snowball | visuals: reads `Weapons.Shot` (and its `Boom`/`Snake`/`Ball`), `Proj`, `TrapNet` positions every frame, draws blasts and flames from the `explode` / `flame` events (shared low-poly meshes, scale-only fades, capped) |
| `tests/weapons_shots.gd` | | batch-1 + batch-2 smoke match (`--smoke`, headless) and the `docs/style/godot-weapons-batch1-*.png` / `godot-weapons-batch2-*.png` screenshots (`--shot rocket|net|throw|roll --out FILE`, needs a window) |
| `logic/mode_rules.gd` `ModeRules` (`Combat.rules`) | `addKo` limit, `endMatch`, `eliminate`, `teamKo`, `TEAM_COL`, `GG`/`ggGive`/`ggAdvance`/`initLadder`, `doDash`/`dashTick`, `updateShrink` + shrink spot in `respawn`, `setBotCfg` team split | game modes; parity `tools/modes-reference.js` + `tests/modes_parity_test.gd`, matches `tests/modes_test.gd` (`npm run test:godot-modes`) |

## Conventions

- **Pure logic.** No nodes. Functions take `FighterState`s; `Combat.fighters` is the list of everyone in the match, `Combat.solids` the map boxes (`FighterPhysics.solids_from_map`).
- **Effects are events.** Anything visual (lean/head spring kicks, arm shoves, sounds, puffs, tracers, K.O. burst, toasts, net messages) is appended to `Combat.events` as a Dictionary (`{"type": "lean", "f": fighter, "a", "b"}`, `"head"`, `"arm"`, `"sfx"`, `"hit"`, `"ko"`, `"net"`, `"tracer"`, `"projectile"`, ...). The world drains it every frame. `Combat.hit()` also returns `{applied, dmg, ko, light, sent?}`.
- **Animation points are inputs.** The web game reads `handPos`, `armDir`, `shoulderPos`, `headPos`, `chestPos`, `legPos` and `aimTarget` back from its meshes. In Godot the visual layer writes `hand_*`, `arm_*`, `shoulder_*`, `head_*`, `chest_*` and calls `update_leg()` before combat runs (after the sim step, like `applyPose`), and reads `aim_*` (where the arm should point; melee and throws set it).
- **Content** comes from `Combat.load_content(dir)`: a folder with `weapons.json`, `classes.json`, `modes.json` (default `res://data`, which the foundation track's sync fills; tests pass the repo's `shared/`). Never hard-code a weapon number.
- **Rules** (`cfg` + `MODES[cfg.mode]` in JS) are fields on `Combat`: `hp_setting`, `kb_setting`, `set_mode(id)`, `teams`, `ffa`, `brawl`, `lives_mode`, `inf`, `giant`, `spawns`, `spawn_y`, `time` (= `simTime`).
- **Float order matters.** Write expressions in the same order as the JS (`-dF * force * 0.22`, three.js `normalize()` = multiply by `1/length`: use `Combat.norm3`). Use `Combat.js_round` for `Math.round`, `NetSnapshot.fixed` for `+v.toFixed(n)`.

## Call order per sim step (from `simStep` / `frame`)

1. input: `Combat.try_melee`, `Weapons.try_fire`, `Combat.do_kick`, `Combat.shove`, `Combat.pickup` ...
2. `Combat.timers(f, dt)` for every fighter (cooldowns, reload, burn, trap, down/getup, death timer -> `respawn`, kick, thrown-weapon release)
3. `Combat.melee_tick` for swinging fighters (then `after_swing` when it returns true)
4. `FighterPhysics.step(dt, solids, f)` (in the web game `timers` and `physics` run per fighter in one loop; `MatchSim.step` does the same, after the input/bot step that holds the melee ticks)
5. `Weapons.step_all(dt)` = `step_rockets` (delayed meteor bomblets first), `step_grenades`, `step_projectiles` (knives, shuriken, typhoon blades, thrown tridents), `step_boomerangs`, `step_arrows`, `step_snakes`, `step_balls`, `step_nets` (flying nets, then nets on the ground), the order of `updateRockets ... updateNets` in `simStep`; `Combat.time += dt`. `MatchSim` then pins trapped fighters to `trap_x/trap_z` after `separate()` and ticks the bow's arrow grab (`Weapons.grab_tick`, from `animate`)
6. after the animation wrote the points: `Combat.melee_sweep(f)` for every fighter

## Determinism

The web game calls `Math.random` for gameplay (fall side, topple chances, gun spread, recoil, respawn spot) and also for many visual effects. The port takes all gameplay randomness from `Combat.rng` (`CombatRng`, Park-Miller: `state = state * 48271 % 2147483647`, exact in JS doubles), consumed in exactly the order the JS consumes it with visuals stubbed. `tools/combat-reference.js` installs the same generator as `Math.random` and stubs every visual function with a no-op, so both sides draw the same numbers. In a real match the RNG is unseeded; its order only matters for the test.

Visual-only randomness that sits in the middle of gameplay code is drawn and thrown away so the order stays the same: `explode` draws 117 numbers (smoke 9 x 7, debris 9 x 6) before the damage, `landNet` 120 (24 rim stones x 5) after the victims; the flame puffs' numbers (`fireGun` flame, burn) are sent with the `flame` events. The reference stubs three.js with a proxy (`ANY`) so that code runs unchanged.

Gotcha: Godot's `JSON.parse_string` (and `String.to_float`) are **not exact** for doubles (up to hundreds of ulps). The reference therefore writes non-integer numbers as `"#<hex bits>"` and the test revives them. Content loaded from `shared/*.json` goes through the inexact parser; the error is ~1e-16 relative and the parity test tolerance is 1e-9.

## Body-part damage (Godot only)

`Combat.hit()` takes an optional `zone` (`Combat.zone_info(part, mul, x, y, z)`) after the attacker. Hitscan guns, knives, arrows and melee sweeps decide the part from the struck point (`Combat.body_part`) and multiply the damage by `Combat.part_mul(part, weapon_head)` before calling `hit()`; the `dmg_number` event gains `part` and `pct`, the `hit` event `part` and the struck point. The rule is `Combat.damage_rule`: a bare `Combat` (the parity tests) and any online match use `classic`, which is the web game's head-only bonus bit for bit; `MatchSim` sets `zones` for offline play. Table, zone rules and net compatibility: `docs/DAMAGE.md`; tests: `npm run test:godot-damage`.

## What is ported

| Area | Status |
|---|---|
| `hit`: mode `dmgMul`, Giant Mammoth 0.65, class `dmg`, rage x1.5, shield x0.5, knocked-down x0.5 (not when trapped), friendly fire, stats, light (<8) vs heavy knockback with `kb` setting x 0.8 x mode `kbMul` x class `kb`, stun, lean/head/arm kicks, death (deathT 1.2 / 3 / `BOT_RESPAWN` 5, pop up 6.5, drop inventory), `addKo` streak/multi/weps, ghost victims -> `h`, own K.O. online -> `ko` | ported, parity tested |
| `topple` + getup immunity, `timers` (cooldowns x class `rate`, invuln, flash, trap struggle, burn ticks, down/getup, death timer, player regen), `respawn` (spawn pick, invuln 2.5 / dummies 0.3, lives), `placeAt` (mode start weapon) | ported, parity tested (lives-mode elimination is an event only) |
| inventory: `pickup` (ammo x class `ammo`, swap rules), `equipSlot`, `dropSlot`, `clearInventory`, `useAmmo`, reload (`startReload/tickReload/finishReload/cancelReload/autoReload`, `reload` x class `reload`, shell reloads) | ported, parity tested (shell reload covered by the shotgun block) |
| kick (`doKick`, `kickStep`), `shove` | ported, parity tested |
| melee: `meleeBegin` (lunge, slam in the air, katana target/stab, typhoon cyclone, trident jab), `meleeTick`, `meleeSweep` (8 points, 3 sub-steps, `swingHit`), `afterSwing` (breaking) | ported; spatula, bat, katana (incl. slam, giant), mallet, hammer, wirewhip, trident (jab, slam, giant, breaking, interrupted) parity tested (blocks `melee`, `melee2`). Typhoon cyclone path ported but untested (the thrown typhoon is batch 2). The melee code is fully data driven: no weapon-specific code beyond katana/typhoon/trident |
| guns: `fireGun` plain hitscan (spread, assist/aim point, climb, falloff, head multiplier, victim merge, `maxForce`, Mammoth headshot, topple chance, recoil, kickback/hop, `hipD`) | ported; smg, ak (incl. ADS), sniper, revolver, mammoth (head snap, Giant), shotgun (`shotSpread` + pellet circle, ADS, falloff, hop; the on-screen circle in `frame` ~10031 is HUD only and stays with the HUD), dual Uzi (`uziSide`, right axis of the arm = `Weapons.arm_right`, a port of the `arm.quaternion` maths in `animate` ~6029), minigun spin-up (`Weapons.gun_tick`, mirrors the `playerControl` gun lines; bots skip spin-up like the JS), Spring Glove (`style: 'punch'`, `Weapons._punch`) parity tested (blocks `guns`, `uziMinigun`, `shotgun`, `glove`) |
| knife: `throwKnife`, `releaseKnife`, `updateKnives` (4 sub-steps, gravity, wall stick, hits, homing, pierce, the typhoon `ty` return) | ported, parity tested (blocks `knife`, `shuriken`, `typhoon`, `tridentThrow`) |
| shuriken: `throwShuriken`, `releaseShuriken` (two stars, lock-on within 0.16 rad, swing-out by distance, homing turn 5.5, no gravity). The off-hand star starts at `armL.localToWorld(0,-0.8,0)`: the visual layer writes `hand2_*` (`Fighter.present`); without it (the parity harness, which has no `armL.localToWorld` either) it is the JS fallback `shoulder - side` | ported, parity tested (block `shuriken`) |
| typhoon: `throwTyphoon` (not while `tyInFlight`), `releaseTyphoon` (three blades, lock-on 0.18, pierce), the `ty` branch (turn back at the target / 0.75 s / a wall, fly home at 48, caught within 1.1 of the chest, lost when the thrower dies, fresh set twirls in) | ported, parity tested (block `typhoon`) |
| boomerang: `throwBoomerang` (not while `p.boom`), `releaseBoomerang` (pre-aim lead from a pretend flight, ammo per throw, last one `noReturn` + drop), `endBoomerang`, `updateBoomerangs` (phase 0 curve, 1 return with the speed/turn rules, 2 drop; 3 sub-steps, wall turns it back, 0.5/0.7 hit pad, head x1.5) | ported, parity tested (block `boomerang`). The player path spends no `useAmmo` (release counts it), bots go through `LAUNCH` + `use_ammo` like `botThink` |
| snake: `shootSnake`, `updateSnakes` (gravity 24, `moveGrenadeAxis`, chase the nearest within 14, wiggle, back off, hop, bites with topple chance, K.O. -> `ignore` + 3 more bites, second K.O. ends it) | ported, parity tested (block `snake`). The body trail (`hist`) is visual only (`ProjectileViews._snake`) |
| snowball (`type: ball`, key `snow`): `shootBall` (off the arm, no assist), `updateBalls` (`projG`, lands -> rolls, grows to 1.7, speeds up to 10.5, smashes on walls, bowls people over + topple 1.5) | ported, parity tested (block `snow`, incl. Moon Drift `grav` 0.2) |
| trident throw: `tridentLet`, `throwTrident` (hold), `releaseTrident` (charge -> dmg/force/speed/gravity), the `w.throwable` lines of `playerControl` (`tCharge`/`tPend`: charge 0.9 s, a tap jabs when `enemyInReach(6.5, 0.45)`, holding 0.16 s turns it into a throw) | ported as `Weapons.trident_tick` (PlayerControl), parity tested (block `tridentThrow`, op `trident`). Bots never throw it (the JS bot only swings it) |
| rocket, meteor: `assistDir`, `launchRocket`, `updateRockets` (walls, fighters, 4 s, void), `explode` (Giant radius x1.4, chest falloff, self half, topple > 0.4), meteor `bomblets` + `delayedBooms` (`BOMBLET`) | ported, parity tested (block `rockets`: player, wall, floor/self, sky timeout, meteor ring, Giant, bot) |
| glauncher, cluster: `launchGrenade` (cluster fan, side fuse +0.1), `updateGrenades` (`projG`, `moveGrenadeAxis` bounces, land -> short fuse, touch) | ported, parity tested (block `glauncher`). `predictLanding` / the aim ring is HUD only, not ported |
| bow: `shootArrow` (Twin Fang, draw charge, `draw || 0.85`), `updateArrows`, `playerControl` draw/release + full-draw shake, `grabT` -> `nocked` (animate), bot draw to 0.85 | ported, parity tested (block `bow`, op `bow`) |
| net: `shootNet`, `updateNets` (catch within 1.4 of a chest, land on walls/after 1.5 s, void), `landNet` (`netGround`, radius, invuln/friends/owner skipped, `trapT`, `lieSide`, hits stat, empty net), trap nets (`trapNet`, release) | ported, parity tested (block `netgun`); pinning to `trapX/Z` is in `MatchSim.step` |
| gun style `flame`: cone (0.5 inside 2.5 m, else 0.88), LOS, hit + `burn`/`burner`, arm push, sound every 3rd; burn ticks in `timers` | ported, parity tested (block `flame`) |
| net: `S` entry, `h`, `ko`, `netCleanHit`, `netGuard` rules | ported; rounding/cleaning parity tested against JS, round-trip test |

| Air Blower (`type: blower`): the blower branch of `playerControl` ~9827 (cone push along the arm, lift, stun 0.12, blame, head kicks, recoil, drain, drop when empty) | ported as `Weapons.blower_tick` (PlayerControl calls it while fire is held; bots never use it, like the JS), parity tested (block `blower`, op `blow`) |

Game modes (`ModeRules`, called from `Combat.add_ko` / `respawn` / `place_at` / `timers` and `MatchSim.step`): K.O. limit and `endMatch` (events `match_over`, then `match_finished` after `END_TIME`), lives + `eliminate`, teams, Weapon Ladder, ninja dash, shrinking arenas: ported, parity tested (`npm run test:godot-modes`, worst error ~1e-16).

Godot-only modes (no web counterpart, so no parity test; `godot/data/extra/modes.json`, merged into `Combat.modes` / `Content.modes` by `ModeRules.merge_extra`, `dropsAs` / `allowFrom` borrow Classic's crate pool and weapons):
- **Team Deathmatch** `tdm`: the team machinery (`teams`, `TEAM_COL`, `is_friend`, `team_ko`) with `flexTeams`: `bot_count` rounds the bot count up to odd, `start_match` sets `teams` = (bots + 1) / 2. Team limit 30 via `check_limit`.
- **Death Match** `deathmatch`: free for all, limit 20 via `check_limit`.
- **Sudden Death** `sudden` (`lives: 1`, `spectate`): `Combat.hit` calls `rules.eliminate` straight after a K.O. (`ModeRules.one_life`); a fall goes through `MatchSim._ring_out` -> `respawn` -> `eliminate` (a knock-off still credits the K.O. to the last attacker within 10 s, a plain fall credits nobody). `eliminate` does not end the match when the player is out in a `spectate` mode; the world spectates (`world.gd` `spectate` / `spectate_next` / `cam_target`, `TouchControls.spectate_mode`). Last one standing wins.
- **Chaos** `chaos` (teams 5, limit 50, `ModeRules.CHAOS_MAPS`): `ModeRules.update_chaos` (from `update`) picks an event with `combat.rng` every 15-25 s (never the last one), emits `chaos_warn` 3 s ahead, then `chaos` / `chaos_end`. Events: crate rain (`Pickups.spawn_drop` x5), low gravity (`phys.grav_scale` 0.4), knockback storm (`kb_setting` x2.5), giant (`FighterState.big_t`: 1.5x hit spheres, double max health, x1.5 damage dealt, half knockback taken; the world scales the view), speed surge (`spd_t`), floor event (`ArenaDyn.force`: a quake or wobble blended over the tile floor, eased in/out over 1 s; skipped when the floor has no tiles).

Not ported yet (TODO in code): emotes in `timers`, hot potato in `hit` (dead code in the web game: no mode sets `potato`), Pillars (`updatePillars`, `pillarGive`, bot pillar hops), dev god mode, kill cam, the snake K.O. kill-feed icon (an event `snake_ko` is sent), the boomerang catch pop (`catchT`, visual: event `boomerang_catch`). Every weapon type in `shared/weapons.json` is now ported. Crates/drops are in `logic/pickups.gd`: heal (+60%), speed/rage/shield (12 s) are done; the web game's permanent-crate respawn queue (`permQ`, sandbox spots) is not.

`FighterPhysics.step(dt, solids, st)` (now `logic/fighter_physics.gd`) applies `stun`, `down_t`, `trap_t`, `spd_t` and `dash_air_t` from the FighterState, parity tested; `MatchSim` (`logic/match_sim.gd`) runs the whole step order below for an offline match.

## Where each weapon type lives (JS)

All types are ported (batch 1: guns, shotgun, dual Uzi, minigun, glove, flamethrower, Air Blower, melee, knife, rocket/meteor, grenade/cluster, bow, net gun; batch 2: shuriken, typhoon, boomerang, snake, snowball, trident throw). Crates drop every weapon (`Pickups.usable` is true for every type in `Weapons.LAUNCH` plus melee/gun/blower). Use the file map above for the JS line numbers. A new type in the web game goes through the steps below.

| `type` (weapons.json) | Keys | Godot |
|---|---|---|
| `shuriken` | shuriken | `LAUNCH`/`RELEASE` -> `throw_shuriken`/`release_shuriken`; flight `step_projectiles` |
| `typhoon` | typhoon | `throw_typhoon`/`release_typhoon` (+ `ty_in_flight`); flight and return `step_projectiles` |
| `boomerang` | boomerang | `throw_boomerang`/`release_boomerang`, `step_boomerangs` (`Weapons.Boom`, `FighterState.boom`) |
| `snake` | snake | `shoot_snake`, `step_snakes` (`Weapons.Snake`) |
| `ball` | snow | `shoot_ball`, `step_balls` (`Weapons.Ball`) |
| `melee` + `throwable` | trident | `trident_tick` (PlayerControl), `throw_trident`/`release_trident`; `release()` dispatches throwable melee keys |
| `heal` / power-ups | heal, speed, rage, shield | `Pickups._take` |

## How to add a weapon type

1. Read the JS for the type (table above). Port the launcher into `Weapons` as `throw_<type>(f, key)` / `launch_<type>(f, key)` and register it in `LAUNCH` (and `RELEASE` if it has a wind-up: `Combat.timers` calls `release` when the throw lands). Hitscan variants go into `fire_gun`.
2. Projectiles: reuse `Proj` + `step_projectiles` when the flight is the `knives` loop; otherwise add a list (or reuse `Shot`) and a `step_<type>s(dt)` called from `Weapons.step_all` at its place in `simStep`'s order, mirroring the JS loop (same sub-steps, same order of gravity / move / wall test / hit test). Add the list to `Weapons.clear()` and give `world/projectile_views.gd` a mesh for it (`_spawn`).
3. Keep every `Math.random`/`rand` call in the same place and order (`combat.rng.next()`, `combat.rng.range_f(a, b)`), including ones whose result is only visual if they sit between gameplay calls.
4. Emit events for visuals; never touch nodes.
5. Add a block to `scenario()` in `tools/combat-reference.js` (`blocks.<name>() { ... }`): place fighters, `pickup` the weapon, `pose` the aim, `fire`, `step`. `placeAt` clears the inventory: move a shooter that must keep its weapon with `place` (see `reset(first)` in the batch-1 blocks). If the JS needs a new global or function, add it to `FUNCS` / `LINES` / the stub list in `makeContext` (visual stubs must not call `Math.random`). If a new op is needed, add it to `apply()` in the reference **and** in `godot/tests/combat_test.gd`, with the same meaning. If the type keeps its own projectile list, add it to `dump()` in both.
6. `npm run test:godot-combat` must stay at worst_error <= 1e-9. Check the block really hits something (a quick look at `st.hits` in the reference output), and that a deliberate change in your port makes the test fail.
7. Let crates drop it (`Pickups.usable` follows `Weapons.LAUNCH`) and check bots fire it (`BotBrain` uses `LAUNCH`; aim/range rules per type are in `botThink`).

## Running the tests

- `npm run test:godot-combat`: the parity test (JS reference vs Godot, worst_error must stay <= 1e-9) and the NetSnapshot test.
- `npm run test:godot-damage`: body-part zones and multipliers on every hit path, classic vs zones, net fallback (`godot/tests/damage_test.gd`).
- `godot --headless --path godot --script res://tests/weapons_shots.gd -- --no-save --smoke`: a 60 s offline match with bots armed with the batch-1 and batch-2 weapons, the player cycling through all of them (explosions, nets, flames, every batch-2 projectile in flight, views in sync, no script errors).
- The rest of the Godot suites a weapons change can touch: `npm run test:godot-physics`, `test:godot-world`, `test:godot-integration`, `test:godot-netguest`, `test:godot-weapons`, `test:godot-ui`, `test:godot-dynamics`, and `npm test`.
- Screenshots (window needed): `godot --path godot --resolution 1280x720 --script res://tests/weapons_shots.gd -- --no-save --shot rocket --out docs/style/godot-weapons-batch1-rocket.png` (and `--shot net`; batch 2: `--shot throw` / `--shot roll` -> `docs/style/godot-weapons-batch2-throw.png` / `-roll.png`).
