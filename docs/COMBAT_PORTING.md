# Porting combat and weapons to Godot

How the combat logic in `godot/logic/` maps to the web game (`public/index.html`), and how to port the remaining weapons. Line numbers are approximate (b76); grep the symbol if they drift.

## Files

| Godot | Web game | What |
|---|---|---|
| `logic/fighter_state.gd` `FighterState` | `Fighter` fields (constructor ~4880) | gameplay state of one fighter; links its `FighterPhysics` (`phys`: pos/vel/grounded) |
| `logic/combat.gd` `Combat` | `Fighter.hit/topple/timers/respawn/placeAt/pickup/...` (~4950-5560), `addKo`, `shove`, `doKick`, `useAmmo` | damage, knockback, K.O., inventory, reload, kick, shove, melee swing + sweep |
| `logic/weapons.gd` `Weapons` | `fireGun` (~5942), `PROJ` (~9361), `throwKnife/releaseKnife/updateKnives` (~6464, ~6679) | ranged weapons and projectiles |
| `logic/combat_rng.gd` `CombatRng` | `Math.random` | seeded random source (see Determinism) |
| `logic/net_snapshot.gd` `NetSnapshot` | `netStep` `S` entry (~8984), `h`/`ko` sends, `netCleanHit`/`netGuard` (~8703) | protocol encode/decode (docs/PROTOCOL.md 3.1) |
| `tests/combat_test.gd` + `tools/combat-reference.js` + `tools/test-combat.js` | | parity test (`npm run test:godot-combat`) |
| `tests/net_snapshot_test.gd` | | NetSnapshot round trip and junk rejection |

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
5. `Weapons.step_projectiles(dt)`; `Combat.time += dt`
6. after the animation wrote the points: `Combat.melee_sweep(f)` for every fighter

## Determinism

The web game calls `Math.random` for gameplay (fall side, topple chances, gun spread, recoil, respawn spot) and also for many visual effects. The port takes all gameplay randomness from `Combat.rng` (`CombatRng`, Park-Miller: `state = state * 48271 % 2147483647`, exact in JS doubles), consumed in exactly the order the JS consumes it with visuals stubbed. `tools/combat-reference.js` installs the same generator as `Math.random` and stubs every visual function with a no-op, so both sides draw the same numbers. In a real match the RNG is unseeded; its order only matters for the test.

Gotcha: Godot's `JSON.parse_string` (and `String.to_float`) are **not exact** for doubles (up to hundreds of ulps). The reference therefore writes non-integer numbers as `"#<hex bits>"` and the test revives them. Content loaded from `shared/*.json` goes through the inexact parser; the error is ~1e-16 relative and the parity test tolerance is 1e-9.

## What is ported

| Area | Status |
|---|---|
| `hit`: mode `dmgMul`, Giant Mammoth 0.65, class `dmg`, rage x1.5, shield x0.5, knocked-down x0.5 (not when trapped), friendly fire, stats, light (<8) vs heavy knockback with `kb` setting x 0.8 x mode `kbMul` x class `kb`, stun, lean/head/arm kicks, death (deathT 1.2 / 3 / `BOT_RESPAWN` 5, pop up 6.5, drop inventory), `addKo` streak/multi/weps, ghost victims -> `h`, own K.O. online -> `ko` | ported, parity tested |
| `topple` + getup immunity, `timers` (cooldowns x class `rate`, invuln, flash, trap struggle, burn ticks, down/getup, death timer, player regen), `respawn` (spawn pick, invuln 2.5 / dummies 0.3, lives), `placeAt` (mode start weapon) | ported, parity tested (lives-mode elimination is an event only) |
| inventory: `pickup` (ammo x class `ammo`, swap rules), `equipSlot`, `dropSlot`, `clearInventory`, `useAmmo`, reload (`startReload/tickReload/finishReload/cancelReload/autoReload`, `reload` x class `reload`, shell reloads) | ported, parity tested (shell reload covered by the shotgun block) |
| kick (`doKick`, `kickStep`), `shove` | ported, parity tested |
| melee: `meleeBegin` (lunge, slam in the air, katana target/stab, typhoon cyclone, trident jab), `meleeTick`, `meleeSweep` (8 points, 3 sub-steps, `swingHit`), `afterSwing` (breaking) | ported; spatula, bat, katana (incl. slam, giant), mallet, hammer, wirewhip, trident (jab, slam, giant, breaking, interrupted) parity tested (blocks `melee`, `melee2`). Typhoon cyclone path ported but untested (typhoon is a thrown type, next batch). The melee code is fully data driven: no weapon-specific code beyond katana/typhoon/trident |
| guns: `fireGun` plain hitscan (spread, assist/aim point, climb, falloff, head multiplier, victim merge, `maxForce`, Mammoth headshot, topple chance, recoil, kickback/hop, `hipD`) | ported; smg, ak (incl. ADS), sniper, revolver, mammoth (head snap, Giant), shotgun (`shotSpread` + pellet circle, ADS, falloff, hop; the on-screen circle in `frame` ~10031 is HUD only and stays with the HUD), dual Uzi (`uziSide`, right axis of the arm = `Weapons.arm_right`, a port of the `arm.quaternion` maths in `animate` ~6029), minigun spin-up (`Weapons.gun_tick`, mirrors the `playerControl` gun lines; bots skip spin-up like the JS), Spring Glove (`style: 'punch'`, `Weapons._punch`) parity tested (blocks `guns`, `uziMinigun`, `shotgun`, `glove`) |
| knife: `throwKnife`, `releaseKnife`, `updateKnives` (4 sub-steps, gravity, wall stick, hits, homing/pierce fields) | ported; knife parity tested, homing (shuriken) ported but untested |
| Air Blower (`type: blower`): the blower branch of `playerControl` ~9827 (cone push along the arm, lift, stun 0.12, blame, head kicks, recoil, drain, drop when empty) | ported as `Weapons.blower_tick` (PlayerControl calls it while fire is held; bots never use it, like the JS), parity tested (block `blower`, op `blow`) |
| net: `S` entry, `h`, `ko`, `netCleanHit`, `netGuard` rules | ported; rounding/cleaning parity tested against JS, round-trip test |

Not ported yet (TODO in code): emotes in `timers`, ninja dash (`dashTick`, `doDash`), hot potato in `hit`, dev god mode, kill cam, gun style `flame`, the trident throw (`throwTrident`), all other projectile types (next batch), shrinking-arena respawn, Weapon Ladder (`ggGive/ggAdvance`), crates/drops (`pickCrateKey`, `spawnDrop`, `updatePickups`), match end on KO limit (the world reads the `ko` event).

`FighterPhysics.step(dt, solids, st)` (now `logic/fighter_physics.gd`) applies `stun`, `down_t`, `trap_t`, `spd_t` and `dash_air_t` from the FighterState, parity tested; `MatchSim` (`logic/match_sim.gd`) runs the whole step order below for an offline match.

## Where each remaining weapon type lives (JS)

Already done and removed from this table: plain guns, shotgun, dual Uzi, minigun, glove, all plain melee, the Air Blower. Crates only drop weapons for which `Pickups.usable` is true (only `style: flame` guns and the types below are filtered out).

| `type` (weapons.json) | Keys | JS | Port into |
|---|---|---|---|
| `gun` style `flame` | flame | `fireGun` flame branch ~5960, burn in `timers` | `Weapons.fire_gun` |
| `rocket` | rocket, meteor, cluster | `launchRocket` ~6257, `updateRockets` ~6985, `explode` ~6938 | new `launch_rocket`, `step_rockets`, `explode` |
| `glauncher` | glauncher | `launchGrenade` ~6345, `updateGrenades` ~7026 | `LAUNCH`/`RELEASE` + own stepper |
| `bow` | bow | `shootArrow` ~6401, `updateArrows` ~6414 (draw charge) | own stepper |
| `shuriken` | shuriken | `throwShuriken/releaseShuriken` ~6650 (two stars, homing) | `LAUNCH`/`RELEASE`; flight is `step_projectiles` (homing ready) |
| `typhoon` | typhoon | `throwTyphoon` ~6608, `ty` branch of `updateKnives` | `LAUNCH`/`RELEASE` + the `ty` return branch |
| `boomerang` | boomerang | `throwBoomerang/releaseBoomerang/updateBoomerangs` ~6480-6566 | own stepper |
| `snake` | snake | `shootSnake/updateSnakes` ~6714 | own stepper |
| `ball` | snow | `shootBall/updateBalls` ~6796 | own stepper |
| `net` | net | `shootNet/landNet/updateNets` ~6807 (sets `trap_t`) | own stepper |
| `melee` | trident (throwable) | swing done; `throwTrident/releaseTrident` ~6283 | `LAUNCH` for the throw (TODO) |
| `heal` / power-ups | heal, speed, rage, shield | `updatePickups` ~6182 | pickups task |

## How to add a weapon type

1. Read the JS for the type (table above). Port the launcher into `Weapons` as `throw_<type>(f, key)` / `launch_<type>(f, key)` and register it in `LAUNCH` (and `RELEASE` if it has a wind-up: `Combat.timers` calls `release` when the throw lands). Hitscan variants go into `fire_gun`.
2. Projectiles: reuse `Proj` + `step_projectiles` when the flight is the `knives` loop; otherwise add a list and a `step_<type>s(dt)` called from the sim step, mirroring the JS loop (same sub-steps, same order of gravity / move / wall test / hit test).
3. Keep every `Math.random`/`rand` call in the same place and order (`combat.rng.next()`, `combat.rng.range_f(a, b)`), including ones whose result is only visual if they sit between gameplay calls.
4. Emit events for visuals; never touch nodes.
5. Add a block to `scenario()` in `tools/combat-reference.js` (`blocks.<name>() { ... }`): place fighters, `pickup` the weapon, `pose` the aim, `fire`, `step`. If the JS needs a new global or function, add it to `FUNCS` / `LINES` / the stub list in `makeContext` (visual stubs must not call `Math.random`). If a new op is needed, add it to `apply()` in the reference **and** in `godot/tests/combat_test.gd`, with the same meaning. If the type keeps its own projectile list, add it to `dump()` in both.
6. `npm run test:godot-combat` must stay at worst_error <= 1e-9. Check the block really hits something (a quick look at `st.hits` in the reference output), and that a deliberate change in your port makes the test fail.
