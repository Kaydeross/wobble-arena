# Dynamic arenas

The floor (or the free-standing blocks on it) moves during a match. Web: `public/index.html` (`DYN-PURE` block + runtime
right after it). Godot/iOS: `godot/logic/dynamics.gd` (pure port) + `godot/logic/arena_dyn.gd` (runtime), drawn by `godot/world/world.gd`.

## Kinds

| Setting | Name | What happens |
|---|---|---|
| `off` | Steady | nothing moves |
| `random` | Random (default) | one of the kinds below that the level supports, picked from the match seed |
| `wobble` | Wobble | a slow wave rolls across the floor tiles (0.3 m, 6 s period) |
| `tilt` | Tilt | the floor rocks like a see-saw on a slowly turning axis (0.5 m at the edge, 12 s; axis turns once per 40 s) |
| `quake` | Quake | from 12 s, one quake per 15 s slot (+0..3 s jitter): 1.5 s shake on the 3x3 tiles round an epicentre, then ~40 % of them drop 30 m for 3 s and rise back over 1.2 s |
| `drift` | Drift | up to 12 free-standing blocks slide +-2 m along one axis (period 10..14 s each) |

Everything eases in over the first 4 s (`DYN_RAMP`, smoothstep), so nothing moves under a spawn at t = 0.
Levels that never move: `dynMapAllowed` (noDynamics / shrinks / range / randSpawn, and custom, test, practice, pillars).
Tile kinds need a single floor slab and >= 30 % free tiles (`dynPlan`); `node tools/test-dynamics.js --table` prints the per-level table.

The optional **destructible environment mode** (`docs/DESTRUCTIBLE.md`) appends static prop solids to the arena, so it forces
`dyn = off` for its match in M0 (`MatchSim.setup`): props cannot ride a moving tile yet. With the mode off nothing about the
dynamic arena changes.

## Constants (identical in both)

`RAMP 4`, `WOB_A 0.3 / WOB_P 6`, `TILT_A 0.5 / TILT_P 12 / TILT_ROT 40`, `Q_FIRST 12 / Q_SLOT 15 / Q_JIT 3`,
`Q_SHAKE 1.5 / Q_DROP 0.6 / Q_DOWN 3 / Q_RISE 1.2 / Q_DEPTH 30 / Q_JA 0.05 / Q_HZ 9 / Q_HOLE 0.4`, `DRIFT_A 2 / DRIFT_P 10 / DRIFT_PV 4`.
Grid: `nx, nz = clamp(round(size / 4), 4, 12)`. Tile mask bit 1 = anchored (another solid, ladder or pad on it), bit 2 = never a hole (near a spawn).

## Determinism

- Everything is a function of `(kind, seed, t)` and the map's collision data: no `Math.random`, no frame time.
- `dynHash` is a uint32 integer hash (`Math.imul` = low 32 bits). GDScript ints are 64-bit, so `Dynamics.imul` splits the
  product and masks with `0xFFFFFFFF`; `Math.round` is `floor(x + 0.5)`. Trig is plain `sin`/`cos` on doubles.
- The clock is match time: `t = simTime - t0` on the web, `MatchSim.dyn_clock() = combat.time - match_start + dyn_t0` in Godot.
  `updateDyn` / `ArenaDyn.update` runs first in every 1/120 s sim step, right after the clock advances.
- Tiles replace the floor in the collision list at the floor's index, row by row (`iz` outer, `ix` inner), so solid indices match across clients.
- Riders: a grounded fighter standing on a moving tile (`|y - top| < 0.002`) is lifted/lowered with it when the step is <= 0.03 m;
  on a drifting block it is carried along the axis. Crates draw on the tile under them (`dynFloorDy` / `floor_dy`).

## Network

The host picks the kind (its Arena setting) and a fresh seed every match. `start.rules` carries:

| Field | Meaning |
|---|---|
| `dyn` | the chosen kind (`off`/`random`/...); unknown or missing = steady |
| `dseed` | uint32 seed (`>>> 0`) |
| `dt0` | seconds already elapsed on the host's dynamic clock (late join / rejoin), clamped 0..36000 |

Godot is guest-only today: `NetMatch.rule_dyn(rules)` reads the three fields and `world.gd` sets `sim.dyn_choice / dyn_seed / dyn_t0`
before `MatchSim.setup`. When a Godot host path is added it must send the same three fields (see `ruleSnap` / `netStartMatch`).

## Godot port

- `godot/logic/dynamics.gd` (`Dynamics`): line-by-line port of the pure block (`hash32`, `rand`, `ramp`, `map_allowed`, `resolve`, `offset`, `delta`, `plan`).
- `godot/logic/arena_dyn.gd` (`ArenaDyn`): collision half of `dynSetup` / `dynBuildTiles` / `dynBuildDrift` / `dynSupport` / `updateDyn` / `dynFloorDy`; owned by `MatchSim.dyn`.
- `godot/world/world.gd`: `_build_dyn_views` rebuilds the merged box meshes without the floor / drifting blocks (`MapBuilder.rebuild_boxes`),
  adds one mesh per tile (checker shading, big floor pads hidden and their colour put on the tiles) or per block, and
  `_update_dyn_views` moves them to the live solids every frame; quake drops / rises puff a little dust. No screen shake (not ported yet).
- Setting: `Settings` key `dyn` (default `random`), chosen on the title screen ("Arena: ..." picker next to map and class, `scripts/main.gd`).
  Command line: `--dyn=<kind>`. Online the host's choice wins.

## Tests

- `npm run test:dynamics`: the web pure functions (ranges, neighbour steps < 0.55 m, no holes under spawns, every level's plan).
- `npm run test:godot-dynamics`: `tools/test-godot-dynamics.js` slices the JS block, generates vectors (hashes, rand, ramp, resolve,
  offsets incl. quake epicentres, deltas, every map's plan) plus 40 s of tile / drift collision on several levels, and
  `godot/tests/dynamics_test.gd` checks the port (hashes and plans exact, floats <= 1e-9), that tile solids follow the offsets in the
  web order, that fighters ride tiles and blocks, that `rule_dyn` parses the rules, and that a late-joining sim (t0) matches the host.
- Screenshots: `godot --path godot --resolution 1600x900 --script res://tests/dyn_shots.gd -- --no-save --out docs/style`
  writes `docs/style/godot-dyn-{wobble,tilt,quake,drift}.png`.
