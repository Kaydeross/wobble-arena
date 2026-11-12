# Godot client architecture (Phase 1)

Written by the lead so parallel sessions fit together. If a rule here blocks you, stop and report instead of working around it.

## Principles
- The web game (`public/index.html`, index in `docs/CODEMAP.md`) is the spec. Port logic, don't redesign it. Every ported system gets a **parity test**: slice the real JS (see `tools/physics-reference.js`), run a scripted input, replay in Godot, compare (worst error ~0). Tunables come from `shared/*.json`, never hard-coded.
- **Logic is separate from visuals.** Logic classes are plain `RefCounted` (like `FighterPhysics`) with no scene dependency, so they run headless in tests. Scenes/nodes only present state.
- **Fixed sim step.** The web game simulates at `SIM = 1/120`. Godot logic steps at the same fixed dt from a single accumulator in `World`; visuals interpolate/animate per frame.
- 64-bit floats for logic (plain `float` fields, not `Vector3`) where parity matters.
- Render tiers via one autoload (`Tier`): `PC` (Forward+), `MOBILE` (iOS), `WEB` (Compatibility). Heavy effects check `Tier`.
- Style: tabs, typed GDScript, `class_name` for shared classes. Run `godot --headless --path godot --import` after adding a `class_name`.

## Layout (`godot/`)
```
autoload/   content.gd (loads ../shared/*.json via res:// copy), tier.gd, settings.gd
logic/      fighter_physics.gd fighter_state.gd combat.gd weapons.gd pickups.gd match_sim.gd bot_brain.gd player_control.gd spring.gd ...   (RefCounted, headless)
actors/     wobbler.tscn/.gd   (visual only)     fighter.tscn/.gd (FighterState + Wobbler)
world/      world.tscn/.gd (sim loop, camera, map)  map_builder.gd
ui/         theme_builder.gd -> theme.tres (project theme), juicy_button.gd, safe_area.gd, logo.gd, hud.tscn/.gd (+ hud_*.gd), fps_overlay.gd (autoload)
net/        net_client.gd (exists) snapshot.gd ...
tests/      one script per parity/unit test + tools/test-*.js runner in the repo's tools/
```
`shared/*.json` is the source of truth; Godot reads copies synced by `tools/sync-shared.js` into `godot/data/` (committed, checked by `npm test` the same way as shared/).

Foundation pieces (Phase 1): autoloads `Tier`, `Content` (res://data/*.json), `Settings` (ConfigFile key/value); `world/map_builder.gd` (`MapBuilder.build(id)` -> `MapNode` with `solids`, `pads`, `ladders`; `MapBuilder.material()` is the one material factory); `world/world.tscn` (offline test world, fixed 1/120 step); `input/input_state.gd` (`InputState`, the one input object), `input/player_input.gd` (keyboard/mouse/gamepad), `input/touch_controls.tscn` (touch). `FighterPhysics` now lives in `logic/fighter_physics.gd`.

## Contracts between tracks

**FighterState** (plain Dictionary or class `FighterState` in `logic/`), the only thing visuals need:
`pos: Vector3, vel: Vector3, yaw: float, aim: Vector3 (arm direction), grounded: bool, crouch: float (0..1), hp: float, dead: bool, down_t: float, weapon: String, swing: float (-1 idle, 0..1.3), kick_t: float (-1 idle), invuln: bool, flash: float, class_id: String, skin: String, hat: String, color: int`.

**Wobbler (visual node)**, owned by the wobbler track:
- `setup(class_id, skin, hat, color)`; `apply_state(state: Dictionary)` each frame; `animate(dt)`; `hit_kick(dir: Vector3, force: float)`; `set_weapon(key)`; no gameplay logic inside.
- Looks (proportions, class accessories) come from `shared/classes.json` (`size`, `head`, `wide`, `skin`) and `shared/cosmetics.json`.

**Combat (logic)**, owned by the combat track: `Combat.hit(victim: FighterState-like, dmg, dir, force, head, attacker_class, modes...) -> result`, `melee_sweep(...)`, weapon firing helpers per `shared/weapons.json` type. Pure functions over state objects + the same RNG-free math as `Fighter.hit` (public/index.html ~5390).

**World / map**, owned by the foundation track: `MapBuilder.build(map_id) -> Node3D` makes visuals from `shared/maps.json` (boxes, pads, ladders, sky/fog colours) and returns the `solids` array used by `FighterPhysics.solids_from_map`.

## Integration (offline vertical slice)

How the pieces fit since the integration track (`npm run test:godot-integration`):

- **`logic/fighter_physics.gd` `FighterPhysics`** (moved from `scripts/`): `step(dt, solids, st: FighterState)` reads the fighter's status effects like `Fighter.physics`: no control when `dead`/`down_t`/`trap_t`, acceleration x0.12 while `stun` (counted down here), 18 while down, run speed x1.4 while `spd_t`, air steering 3 while `dash_air_t` (counted down here), ice grip (`set_map`: `grip`, `ceil`), ladders (`ladder_step`; only fighters with `can_climb`, i.e. the player, grab one by walking into it; `climb_in` = forward input) and the dome ceiling. `bounce_pads(pads, st)` is the `updatePads` loop (uses `st.pad_cool`, which `Combat.timers` counts down). Parity: `tools/physics-reference.js` runs the real `physics`, `ladderStep` and `updatePads` with scripted status flags, every bounce pad and ladder of the map (`npm run test:godot-physics`, 5 maps + every class, worst error 0).
- **`logic/match_sim.gd` `MatchSim`**: one offline match, no nodes. `setup()` = `loadMap` + `setBotCfg` (player class from Settings `class`, bots in `BOT_CLASS_ORDER` with DIFFS speed/dmg, hats and colours like `allBots`); `step(dt)` follows `simStep`: time -> controllers (`PlayerControl`/`BotBrain`, melee ticks inside) -> per fighter `Combat.timers` + `FighterPhysics.step` -> bounce pads -> crates -> projectiles -> ring-out (K.O. credit, bot death timer `BOT_RESPAWN`, player respawns at once: no kill cam yet) -> `separate` -> the gameplay half of `animate` (yaw smoothing, crouch, recoil climb). `sweep()` = `meleeSweep` for everyone, once per rendered frame after the animation points are written. Also `quick_melee` and `has_los`.
- **`logic/player_control.gd` `PlayerControl`**: `playerControl` + key handlers over `InputState` and the camera (`cam_yaw`, `aim_point`): move/sprint/crouch/jump, facing, aim target, gun fire, melee swing + tick, kick, shove, quick melee, slots, reload. Tests drive the same InputState (`"script"` source).
- **`logic/bot_brain.gd` `BotBrain`**: a reduced `botThink` (nearest target, crates it wants, chase/circle-strafe, shoot when the arm is lined up, kick/swing up close, hop when stuck). The full AI is a later task.
- **`logic/pickups.gd` `Pickups`**: `pickCrateKey`/`spawnDrop`/`updatePickups` over `res://data/drops.json` (new export: `DROP_BASE` weights, `CRATE_MULT`, heal/power-up labels, per-mode allowed keys) and `crate-rates.json`. `ported_only` (default true) keeps crates to weapons the port can use yet (melee, plain guns, knives) plus heal and power-ups.
- **`actors/fighter.tscn/.gd` `Fighter`**: a FighterState + a Wobbler child, at the identity transform. `present(dt)` = `animate` + `applyPose`: `wobbler.apply_state(visual_state())`, `wobbler.animate(dt)`, then writes `hand_*` (the Grip node), `arm_*` (`wobbler.arm_dir`), `shoulder_*`, `head_*`, `chest_*` and `update_leg()` back into the state. `on_event` applies Combat's `lean`/`head`/`arm` events to the wobbler's springs.
- **State keys the Wobbler gets** (`Fighter.visual_state`): the contract keys from `FighterState.to_visual()` with `yaw` = `face_yaw` (the wobbler smooths toward it like `animate`), plus `wish` (Vector2 move input, drives the stride), `trap` (bool, `trap_t > 0`), `fall_side` (+1/-1 from Combat, so the K.O. fall matches), `flash` (seconds left, Combat sets 0.12 on a hit), `skin`/`hat`/`color` (the look). `stiff` is not sent (the wobbler takes it from the held weapon).
- **`world/world.gd`**: builds the map, a MatchSim and one Fighter per fighter; per frame (`frame`): camera -> sim steps from the accumulator -> `present` -> `sim.sweep()` -> Combat events to effects (damage numbers, puffs, tracers, K.O. burst, crates with a beam, kill feed, toasts) -> HUD (HP bar against the class max, weapon + ammo, K.O. count + clock). `tick(dt)` is the whole frame (tests call it with `auto_run = false`). Exports / `--` args: `map_id` (`--map=`), `player_class` (`--class=`, default Settings `class`), `bot_count` (`--bots=`), `rng_seed` (`--seed=`), `hp_setting`. The title scene has a class picker.
- **Tests / shots**: `tests/integration_test.gd` (`npm run test:godot-integration`): 30 s on arena, scripted player + 3 bots; K.O.s, respawn, HP range, finite positions, crate + SMG, no node leaks. `sh tools/shoot-godot-slice.sh` renders `docs/style/godot-slice-{melee,smg,wide}.png`.

Each track merges to `main` behind its own tests. The lead integrates `Fighter` (physics + combat + wobbler) in a second round once all three exist. Do not edit another track's files; if you need a change, describe it in your report.

## UI (first UI pass)

- **Theme**: `ui/theme_builder.gd` (`UiTheme`, colour constants + `box()`/`font()` helpers) writes `ui/theme.tres`, set as `gui/theme/custom` in project.godot. Rebuild: `godot --headless --path godot --script res://ui/theme_builder.gd`. Font: Fredoka (SIL OFL, `ui/fonts/OFL.txt`). Type variations: `PrimaryButton`, `HudPanel`, `ChipPanel`, `HudLabel`, `TitleLabel`, `MutedLabel`. `JuicyButton.attach_all(node)` adds the hover/press tween to every button under a node.
- **Safe area**: `SafeArea.insets(viewport)` (canvas units; phones only; tests set `SafeArea.override`). Used by the title screen, HUD, touch layer and FPS overlay.
- **HUD**: `ui/hud.tscn` (`MatchHud`) under `world.tscn` `UI/Hud`; World calls `hud.bind(self)` after `load_map`, `hud.update(delta)` per frame, `hud.toast()` and `hud.add_feed()` from Combat events. It only reads `sim`/`cam`/`touch`/`input` (no gameplay accessors were needed: FighterState/MatchSim fields are public). The old `Fighter.tag` Label3D is removed by World in favour of the HUD nameplates.
- **FPS overlay**: autoload `FpsOverlay` (`ui/fps_overlay.gd`), Settings `show_fps` (title Options + pause menu), F3 or a three-finger tap.
- **Brand**: `tools/shoot-godot-brand.sh` renders `icon.png` and `ui/brand/launch_logo.png` (boot splash + iOS storyboard). `tools/shoot-godot-ui.sh` renders `docs/style/godot-ui-*.png`.

## Test commands
`npm test` (JS + content + `godot/data` drift), `npm run test:godot-physics`, `npm run test:godot` (cross-client join), `npm run test:godot-world` (every map builds, offline world keeps a scripted player on the floor, touch input), `npm run test:godot-integration` (offline match), `npm run test:godot-ui` (title layout at 4 window sizes with safe areas, HUD layout vs touch buttons, FPS overlay toggles). New Godot tests: add `tools/test-<name>.js` runner + npm script `test:godot-<name>`, and mention it in your PR.
