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
logic/      fighter_physics.gd (exists) combat.gd  spring.gd  map_data.gd ...   (RefCounted, headless)
actors/     wobbler.tscn/.gd   (visual only)     fighter.tscn/.gd (composes logic + wobbler)
world/      world.tscn/.gd (sim loop, camera, map)  map_builder.gd
ui/         (later phases)
net/        net_client.gd (exists) snapshot.gd ...
tests/      one script per parity/unit test + tools/test-*.js runner in the repo's tools/
```
`shared/*.json` is the source of truth; Godot reads copies synced by `tools/sync-shared.js` into `godot/data/` (committed, checked by `npm test` the same way as shared/).

Foundation pieces (Phase 1): autoloads `Tier`, `Content` (res://data/*.json), `Settings` (ConfigFile key/value); `world/map_builder.gd` (`MapBuilder.build(id)` -> `MapNode` with `solids`, `pads`, `ladders`; `MapBuilder.material()` is the one material factory); `world/world.tscn` (offline test world, fixed 1/120 step); `input/input_state.gd` (`InputState`, the one input object), `input/player_input.gd` (keyboard/mouse/gamepad), `input/touch_controls.tscn` (touch). `FighterPhysics` stays in `scripts/` until the lead moves it to `logic/`.

## Contracts between tracks

**FighterState** (plain Dictionary or class `FighterState` in `logic/`), the only thing visuals need:
`pos: Vector3, vel: Vector3, yaw: float, aim: Vector3 (arm direction), grounded: bool, crouch: float (0..1), hp: float, dead: bool, down_t: float, weapon: String, swing: float (-1 idle, 0..1.3), kick_t: float (-1 idle), invuln: bool, flash: float, class_id: String, skin: String, hat: String, color: int`.

**Wobbler (visual node)**, owned by the wobbler track:
- `setup(class_id, skin, hat, color)`; `apply_state(state: Dictionary)` each frame; `animate(dt)`; `hit_kick(dir: Vector3, force: float)`; `set_weapon(key)`; no gameplay logic inside.
- Looks (proportions, class accessories) come from `shared/classes.json` (`size`, `head`, `wide`, `skin`) and `shared/cosmetics.json`.

**Combat (logic)**, owned by the combat track: `Combat.hit(victim: FighterState-like, dmg, dir, force, head, attacker_class, modes...) -> result`, `melee_sweep(...)`, weapon firing helpers per `shared/weapons.json` type. Pure functions over state objects + the same RNG-free math as `Fighter.hit` (public/index.html ~5390).

**World / map**, owned by the foundation track: `MapBuilder.build(map_id) -> Node3D` makes visuals from `shared/maps.json` (boxes, pads, ladders, sky/fog colours) and returns the `solids` array used by `FighterPhysics.solids_from_map`.

## Integration
Each track merges to `main` behind its own tests. The lead integrates `Fighter` (physics + combat + wobbler) in a second round once all three exist. Do not edit another track's files; if you need a change, describe it in your report.

## Test commands
`npm test` (JS + content + `godot/data` drift), `npm run test:godot-physics`, `npm run test:godot` (cross-client join), `npm run test:godot-world` (every map builds, offline world keeps a scripted player on the floor, touch input). New Godot tests: add `tools/test-<name>.js` runner + npm script `test:godot-<name>`, and mention it in your PR.
