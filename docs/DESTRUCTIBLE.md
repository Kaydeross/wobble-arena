# Destructible environment mode (optional, M1 all maps)

An **optional offline mode** that makes part of every arena's own cover breakable. On each supported map it analyses the
existing `maps.json` boxes, picks about **half of the safe-to-break cover components** with a per-match seed, swaps those
boxes out of the merged map mesh and collision for tagged breakable ones, and lets bullets and explosions chip at them.
A broken component loses its collision, bursts into the existing pooled debris (dust, a short camera shake, a sound) and
leaves a flat rubble patch; **100-140 s later (randomised) it comes back** with collision and mesh, fades in, and can be
broken again. It is **off by default**: a normal match runs no analysis, has no extra solids, meshes or RNG draws, and
plays exactly as before.

This is milestone **M1 "all maps"**. M0 shipped three hand-authored arenas; M1 replaces that data with a config and
selects from each arena's existing boxes instead. Online, Arcade and cross-play are still out of scope (see
`docs/DESTRUCTIBLE_ENV_STUDY.md`).

## Turning it on

| Where | What |
|---|---|
| Settings | key `destructible` (bool, default `false`) - persisted like every other preference |
| Setup Wizard → Arena | the **Breakable props** row: `Off` / `On` (next to Moving floor), then the Start summary says `Props` |
| Command line | `--destruct=on` / `--destruct=off` (offline world; overrides Settings, handy for screenshots/soak runs) |

**Mode gates (documented limits, not bugs):**

- **Offline only.** Online rooms, host/guest sessions and Arcade co-op ignore the setting completely: breaks and
  respawns are simulation state every peer would have to agree on.
- **On every real arena map**, not just three. The mode never runs on the Practice Range / Test Map, Sandbox (custom),
  Construction's generated `sitegen` site, Lava Pillars' generated lake, or the shrinking-floor maps
  (`shrink` / `squeeze`): those own or generate their collision in ways this mode does not analyse. The wizard row
  disables itself for those game types and the world ignores the setting there.
- The mode **forces a steady floor** (`dyn = off`) for the match: breakable components are static boxes, and mixing them
  with moving tiles would make them ride/floating. Setting the floor back on for a destructible match is a later task.
- A supported map with **no eligible cover** (future content) gets no props and plays normally; a bad config is reported
  and adds no props. Never a broken match.

## Which components are chosen

1. **Analyse the map's boxes.** Every `geometry.boxes` entry is a component by default. Boxes that are one object are
   merged first: an upper box resting on a comparable lower box (a wall plus its thin cap, a stacked crate pile) becomes
   part of that component, so it breaks (and respawns) as one piece.
2. **Throw away essential geometry** (a component is essential when the first matching rule fires):

   | Rule | What it protects |
   |---|---|
   | `hidden` | invisible map_look boxes (invisible boundary walls) |
   | `ground` | ground slabs: any component whose bottom is at/below -0.25 (the buried base floor on every arena) |
   | `roof` | big roofs (`bottom >= 6`, area `>= 1500`) |
   | `thin` / `tall` / `span` / `tiny` | slivers and stairs are not cover: min height `0.8`, max height `5.5`, max span `8`, min thin side `0.35`, min area `0.5` |
   | `supports-above` | a box with another box resting on it would leave that box floating |
   | `stair` | a step in a staircase/ramp run (same footprint, adjacent, small height step to a neighbour) |
   | `spawn` | within `1.5 m` of a spawn point, bot spot or the player start |
   | `ladder` | within `1.5 m` of a ladder |
   | `pad` | within bounce-pad radius + `0.8 m` |
   | `edge-wall` | a thin/tall box that fails the ring-of-floor margin (`0.9 m`), i.e. a ring-out boundary wall |

   A near-edge **cover** box that is not thin/tall is allowed: breaking it cannot remove floor or open the ring-out edge
   (only its own box disappears).
3. **Pick ~half, seeded.** `target = clamp(round(eligible * fraction), 1, budget.perMap)` (fraction `0.5`, cap `40`), then
   a Fisher-Yates shuffle driven by `RandomNumberGenerator` seeded from `map id + MatchSim.destruct_seed` takes the first
   `target` components. Same seed = same breakables; another seed = another set ("components appear randomly"). The
   selection uses its **own** RNG: it takes no `CombatRng` draws, so the weapon stream of a match is unchanged.
4. **Swap them in.** `MatchSim.setup` removes those boxes' solids and appends one tagged component solid each (the map's
   own collision, not a rebuild per break); `MapBuilder.rebuild_boxes` prunes them from the merged map mesh once at load;
   `Destruct` builds the component meshes. A break removes only that solid and hides/recycles its mesh.

The world computes the plan before `MatchSim.setup` (seed = `Dynamics.hash32(rng_seed, 17, ...)`, or one fresh random
draw per match when the world runs without a fixed seed) and passes it in through `MatchSim.destruct_plan`.

### Measured selection (config as shipped, seed 424242, Godot 4.7.2 headless)

| Arena | boxes | components | eligible | breakable | Arena | boxes | components | eligible | breakable |
|---|---|---|---|---|---|---|---|---|---|
| arena | 8 | 8 | 4 | 2 | blast | 92 | 79 | 16 | 8 |
| park | 9 | 9 | 4 | 2 | siteyard | 88 | 75 | 13 | 7 |
| ice | 8 | 8 | 2 | 1 | gunrange | 114 | 101 | 6 | 3 |
| temple | 81 | 81 | 18 | 9 | brawlpit | 62 | 45 | 6 | 3 |
| rooftops | 66 | 66 | 4 | 2 | craterdome | 15 | 13 | 5 | 3 |
| tower | 35 | 35 | 6 | 3 | capsule | 12 | 12 | 4 | 2 |
| arenaxl | 10 | 10 | 5 | 3 | playroom | 82 | 63 | 17 | 9 |
| rinkxl | 14 | 14 | 8 | 4 | farm | 94 | 88 | 46 | 23 |
| colosseum | 43 | 27 | 7 | 4 | crossroads | 14 | 14 | 6 | 3 |
| fortress | 20 | 20 | 6 | 3 | donut | 18 | 18 | 4 | 2 |
| moonbase | 19 | 19 | 4 | 2 | chasm | 20 | 20 | 4 | 2 |
| volcano | 22 | 22 | 4 | 2 | summit | 12 | 12 | 4 | 2 |
| candy | 45 | 21 | 14 | 7 | pirate | 38 | 38 | 7 | 4 |
| haunted | 36 | 24 | 18 | 9 | beach | 24 | 20 | 7 | 4 |
| dojo | 75 | 70 | 6 | 3 | | | | | |

Every supported map gets at least one breakable; 131 breakable components exist across 29 arenas but only one arena's
set is live per match (max 23, comfortably under the 40 cap and the 40-60 draw budget). Run
`node tools/test-godot-destruct.js` to re-print/verify this table from the shipped data.

## Hit points

`hp` scales with the component's total box volume from `hp.min` (small crate, ~3 rifle hits) to `hp.max` (big block,
~7 rifle hits): `round(lerp(min, max, clamp((volume - volumeMin) / (volumeMax - volumeMin), 0, 1)))`. Rifle damage is
unchanged; the test proves a hit stream breaks a component after 2-24 hits.

## Respawn

- When a component breaks it is scheduled `randf_range(respawn.minSeconds, respawn.maxSeconds)` later, i.e. **100-140 s by
  default**, drawn from the mode's own RNG (deterministic for a match seed, but not metronomic - the test requires two
  distinct delays among four breaks).
- `Destruct.step(dt)` runs once per fixed sim step. At zero it restores the tagged solid in `sim.solids`, resets hp, makes
  the mesh visible again, hides the rubble node, appends a `prop_respawn` + `pop` sound event, and fades the mesh in over
  `respawn.fadeSeconds` (`GeometryInstance3D.transparency` 1 -> 0, no per-material transparency changes). The component is
  immediately breakable again and can be broken/respawned repeatedly.
- If a living fighter overlaps the box when the timer fires, the respawn is **postponed** by `respawn.retrySeconds` (2.5 s)
  instead of materialising around them, and retried until clear.
- Meshes and rubble nodes are **recycled**: a break hides its mesh (never frees it) and reuses one lazily created rubble
  node per component; the test runs several break -> respawn cycles and checks the node count stays flat.

## Visuals and budget

- A breakable component is tinted slightly toward `colors.accent` (`colors.tint` 0.12) and wears a thin accent band at its
  top, so players can tell cover from static geometry; the rest of the map keeps its own palette.
- One `MeshInstance3D` per component member box plus the accent band (a capped wall is 2-3 draws), materials shared per
  colour, **no shadow casting**. Rubble is one unshaded, shadowless box per component, created on first break and reused.
- Break effects stay inside the M0 budget: at most 24 chips + 2 dust + one ring above LOW, all from the existing
  `FxSystem` pools; respawn adds one dust particle at the base.
- Empty plan / bad config means no meshes and no solids, so the caps are guaranteed by construction (budget cap 40 per
  map; per-map mesh counts measured in the test, max 49 for Farm's 23 components).

## Config (authoring data)

**Data file: `godot/data/extra/destructible.json`** - a Godot-side CONFIG overlay, never per-arena authored props. Never
hand-edit `shared/*.json` or `godot/data/*.json` outside `extra/`, per `docs/WRITING.md`.

```json
{
  "version": 2,
  "enabled": true,
  "fraction": 0.5,
  "budget": {"perMap": 40},
  "hp": {"min": 20, "max": 56, "volumeMin": 0.6, "volumeMax": 30.0},
  "respawn": {"minSeconds": 100, "maxSeconds": 140, "fadeSeconds": 0.35, "retrySeconds": 2.5},
  "colors": {"accent": 16765286, "tint": 0.12, "rubble": 0.45},
  "selection": {"spawnClearance": 1.5, "ladderClearance": 1.5, "padClearance": 0.8, "edgeMargin": 0.9,
                "minHeight": 0.8, "maxHeight": 5.5, "maxSpan": 8.0, "minThin": 0.35, "minArea": 0.5, "stackRatio": 2.0}
}
```

| Field | Meaning |
|---|---|
| `version` | must be `2` (M0's authored-props schema is rejected) |
| `enabled` | `false` makes the mode a no-op everywhere (validated as off by `Destruct.validate`) |
| `fraction` | share of eligible components made breakable (`0.05..1.0`, shipped `0.5`) |
| `budget.perMap` | hard cap of breakable components per map (`1..60`, shipped `40`) |
| `hp` | hp band by volume; `min`/`max` `1..500`, `volumeMin < volumeMax` |
| `respawn` | randomised delay band (30-600 s), fade-in and blocked-respawn retry |
| `colors` | accent colour (24-bit), body tint mix `0..0.5`, rubble darkening `0..0.9` |
| `selection` | every exclusion knob above; bounds documented by the validator |

`Destruct.validate_config()` checks shape/ranges (cheap, runs on every setup); `Destruct.validate()` re-runs it and, for
every supported arena, proves the analysis yields at least one eligible component, the plan is deterministic for a fixed
seed and the target obeys fraction/budget. The test runner fails on any problem; a bad config at match time is reported
and the match runs with no props (fail safe).

## Implementation

| File | Role |
|---|---|
| `godot/logic/destruct.gd` (`Destruct`, `RefCounted`) | config + validation, the box analysis (component clustering, exclusions), seeded `plan_for()`, solid/mesh swap-in, `ray_hit` / `break_hit` / `break_blast`, respawn timers + fade, queries |
| `godot/data/extra/destructible.json` | the config above (no authored props) |
| `godot/logic/match_sim.gd` | `destructible` / `destruct_seed` / `destruct_plan` / `view_parent` / `destruct`; forces `dyn = off`, calls `destruct.step(dt)` once per fixed step, fails safe when no props |
| `godot/logic/combat.gd` | `combat.destruct` reference (null = mode off) |
| `godot/logic/weapons.gd` | the two impact hooks (hitscan + `explode`), each behind `if combat.destruct != null` |
| `godot/world/world.gd` | Settings/mode gating, per-match seed + plan, mode line (`Breakables`), break -> chips/dust/shake, respawn -> a small dust puff; meshes are children of the built map so `load_map` clears them |
| `godot/world/map_builder.gd` | unchanged: M1 reuses the existing `MapBuilder.rebuild_boxes(root, boxes, exclude)` used by dynamic arenas to prune the merged meshes |
| `godot/autoload/settings.gd` | `"destructible": false` |
| `godot/ui/setup_wizard.gd` | the Arena page's **Breakable props** row (disabled on the range / sandbox / construction) |
| `godot/tests/destruct_test.gd` + `tools/test-godot-destruct.js` | the M1 test suite |
| `docs/DESTRUCTIBLE.md` | this page |

Off is a real null path: `MatchSim.destructible` false means no `Destruct`, no analysis, no tagged solids, no prop
meshes, no extra RNG draws (CombatRng or global) and `combat.destruct == null`, so every weapon hook is skipped. The test
compares a normal match against a run with the mode explicitly off after 2 s: same state hash, same `CombatRng.state` and
same solids. Turning the mode on for an excluded map is also identical (no solids, no RNG draws, same hash).

## Tests

`godot/tests/destruct_test.gd` (run by `node tools/test-godot-destruct.js`, also `npm run test:godot-destruct`):

1. Config: every knob validates; negative cases prove the validator rejects a v1 manifest, a missing `enabled`, a
   fraction > 1, a bad budget, inverted hp/respawn bands, a bad accent, a missing selection rule and the old `arenas`
   schema.
2. Off: no Destruct / tagged solids / meshes / RNG draws, baseline match identical in state hash and RNG; an excluded map
   with the mode on is a no-op; mode-on takes no CombatRng draws; steady floor.
3. **Every supported map**: components partition every box; eligible > 0; target = ~half within the budget and
   deterministic for a seed; different seeds vary; the selected boxes pass independent exclusion checks (not ground,
   hidden, spawn/ladder/pad-adjacent, structural, stair or boundary wall; cover-sized; sane hp/kind); the live match swaps
   exactly those boxes out of collision and builds one mesh root per component.
4. Behaviour on six arenas: collision stops fighters; hitscan and explosions break components after their hp; broken ones
   stay broken; the randomised delay is in band and not metronomic; the timer simulation respawns with collision + mesh +
   fade, a respawn is postponed while a fighter stands in the box, a respawned component breaks again, and three
   break -> respawn cycles keep the node count flat; the rocket path is exercised once.
5. World wiring: Settings off = no props, on = props + `Breakables` mode line + pruned merged meshes, `load_map` clears
   and rebuilds, `--destruct=on` override, and the Practice Range / Sandbox gates.

## Limits and the next milestone

Known limits: offline only; every arena but no online; bullets and explosions only (no melee/flame); components do not
ride a moving floor (the mode forces `dyn = off`); a break removes the whole component (no cascade or partial fracture);
respawn is a fade-in of the original boxes, not rebuilt geometry; rubble patches are static; bots do not seek cover
(nothing changed there).

**Online (Godot-only rooms)** would need: a match rule (`start.rules.dest` like `dyn`/`dseed`/`dt0`), a host-authored
`brk` event carrying component indices plus the already-broken + respawn schedule on `start` for late joiners, guest-side
application (remove/restore the solid, show/hide the mesh - guests never roll hp or timers), rejoin/host-migration state
in `rsx`, and a hard guard so web guests (who cannot render or collide with the components) are kept out of destructible
rooms. See `docs/DESTRUCTIBLE_ENV_STUDY.md` sections 5-6 and `docs/PROTOCOL.md` for the message layout.
