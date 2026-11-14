# Destructible environment mode (optional, M0)

An **optional offline mode** that adds breakable crates and barricades to three arenas. Bullets and explosions chip at
them; when the hit points run out the prop breaks, its collision goes away and it bursts into the existing pooled debris
with dust, a short camera shake and a sound, then leaves a flat rubble patch. It is **off by default**: a normal match has
no extra solids, meshes or random draws and plays exactly as before.

This is milestone **M0** of the plan in `docs/DESTRUCTIBLE_ENV_STUDY.md` (a feasibility study, not a plan of record):
new props only, three arenas, no online, no breakable map walls, no cascades, no decals beyond a flat rubble patch.

## Turning it on

| Where | What |
|---|---|
| Settings | key `destructible` (bool, default `false`) - persisted like every other preference |
| Setup Wizard → Arena | the **Breakable props** row: `Off` / `On` (next to Moving floor), then the Start summary says `Props` |
| Command line | `--destruct=on` / `--destruct=off` (offline world; overrides Settings, handy for screenshots/soak runs) |

**Mode gates (documented limits, not bugs):**

- **Offline only.** Online rooms, host/guest sessions and Arcade co-op ignore the setting completely: breaks are
  simulation state that every peer would have to agree on, which is the separate M1-online design below.
- **Off on the Practice Range, Sandbox and Construction.** The range's dummies and the sandbox's editable blocks own
  their collision, and Construction's generated sites are not authored for props. The wizard row disables itself for
  those game types and the world ignores the setting there.
- Arenas without authored props get **no props** and play normally (enabling the mode on them is a no-op).
- The mode **forces a steady floor** (`dyn = off`) for the match: props are static boxes, and mixing them with moving
  tiles would make them float. Setting the floor back on a destructible match is an M1 task (props would need to ride
  their tile / drift block).

## What breaks and how

| Hit | Path | Behaviour |
|---|---|---|
| Bullets / hitscan | `Weapons.fire_gun` (`ray_walls` distance + `Destruct.ray_hit`) | each pellet damages the nearest breakable only when no wall or fighter is closer; the shot stops on it and draws its tracer there |
| Rockets / grenades / meteor / cluster | `Weapons.explode` (`Destruct.break_blast`) | every unbroken prop inside the blast radius takes `dmg × (1 - distance/radius)` - the same linear falloff explosions use on fighters |
| Melee / flame / punch | - | **not in M0**: a later offline slice, which the study calls its M1 (this page's M1 is the online step); these still collide with props but do not damage them |

A prop has `hp` from the data (crates 24 = 3 rifle hits, barricades 40 = 5) and a visible `color`. A break is
immediate and in-place: the solid is removed from `sim.solids` (so fighters, bots' line-of-sight and every weapon query
see the hole on the next step), the prop mesh is hidden and freed, a flat rubble patch is added, and
`{"type": "break"}` + `{"type": "sfx"}` events are appended to `Combat.events`. `world.gd` turns the break event into
pooled chips/dust/ring + camera shake; `Sfx` plays `clink` (crate) or `whack` (barricade). Never call
`MapBuilder.rebuild_boxes` on a break: props are extra individual meshes, exactly as the study measured.

Budget per break: at most **24 chips + 2 dust** (scaled down by the effects level), one ring above LOW, all from the
existing `FxSystem` pools, so no new draw calls and the MID caps in `docs/GRAPHICS.md` are unchanged. Each prop costs
two draw calls (body + trim) and casts no shadow; 26 props across the three arenas are ~52 draws and 26 rubble patches at
most, well inside the measured MID headroom.

## Authoring

**Data file: `godot/data/extra/destructible.json`** (a Godot-side overlay: never hand-edit `shared/*.json` or
`godot/data/*.json` outside `extra/`, per `docs/WRITING.md`). Only arenas listed there get props, so the mode is opt-in
per arena and other arenas cannot be affected by a bad entry.

```json
{
  "version": 1,
  "budget": {"total": 40, "perArena": 12},
  "arenas": {
    "arena": {
      "name": "Sunny Arena",
      "props": [
        {"id": "crate_sun_1", "kind": "crate",
         "box": {"x": -3, "y": 0, "z": -14, "w": 1.6, "h": 1.5, "d": 1.6},
         "hp": 24, "color": 13290059}
      ]
    }
  }
}
```

| Field | Meaning |
|---|---|
| `id` | unique prop id (event payload, mesh name `Prop_<id>`, rubble `Rubble_<id>`) |
| `kind` | `crate` (1.6 m cube-ish, hp 24) or `barricade` (3 × 0.7 m slab, hp 40); the kind only changes the look/cost |
| `box` | `{x, y, z, w, h, d}` exactly like `shared/maps.json`: x/z centre, y the bottom, w/d footprint, h height |
| `hp` | damage the prop absorbs before it breaks (1..500) |
| `color` | `0xRRGGBB` body/debris tint (the trim is a lighter shade of it) |
| `drop` | reserved for M1 (a crate can drop a pickup later); M0 ignores it, validation only requires a string |

`Destruct.validate()` re-checks the whole file against `shared/maps.json` (the test runner fails on any problem) and
`Destruct.setup()` re-checks the arena it is loading (a bad entry reports an error and adds no props - never a broken
match). The rules, in `godot/logic/destruct.gd`:

- the arena id exists and is not a mode-excluded map (`custom` / `test` / `practice` / `pillars` / shrink maps / range);
- the box sits on a floor top (`y` equals the support height) and the **whole footprint plus a 0.9 m margin** has floor
  under it, so a prop can never hang over a ring-out edge;
- it does not overlap existing map geometry or another prop, and stays clear of the spawn points, the player start, the
  bot spots (2 m), ladders (1.5 m), bounce pads (pad radius + 0.8 m) and the map's crate drop spots (1.5 m);
- box sizes are 0.2..8 m, hp 1..500, colour inside 24 bits, `kind` is known, ids are unique;
- budget: **≤ 40 props total and ≤ 12 per arena** (the file may lower the budget, never raise it above the hard caps).

Current content: **26 props on three arenas** - Sunny Arena 10 (5 crates + 5 barricades), Space Capsule 8 (5 + 3),
Neon Crossroads 8 (4 + 4). They are authored in the open spaces the three maps already have, clear of every point the
match uses; the test runner prints nothing when the data is clean.

To add an arena: add an entry with a few props, run `node tools/test-godot-destruct.js`, and it validates the placement
(the data file is the only change; no map data is touched).

## Implementation

| File | Role |
|---|---|
| `godot/logic/destruct.gd` (`Destruct`, `RefCounted`) | authoring data + validation, appends tagged solids to `sim.solids`, builds prop meshes, `ray_hit` / `break_hit` / `break_blast`, `props` / `broken_count()` / `is_breakable()` queries, rubble |
| `godot/data/extra/destructible.json` | the authored props (above) |
| `godot/logic/match_sim.gd` | `destructible` / `view_parent` / `destruct`; when on, forces `dyn = off` and creates `Destruct` before anyone can hit a prop |
| `godot/logic/combat.gd` | `combat.destruct` reference (null = mode off) |
| `godot/logic/weapons.gd` | the two impact hooks (hitscan + `explode`), each behind `if combat.destruct != null` |
| `godot/world/world.gd` | Settings/mode gating, the mode line (`Breakables`), break event -> chips/dust/shake; meshes are children of the built map so `load_map` clears them |
| `godot/autoload/settings.gd` | `"destructible": false` |
| `godot/ui/setup_wizard.gd` | the Arena page's **Breakable props** row (disabled on the range / sandbox / construction) |
| `godot/tests/destruct_test.gd` + `tools/test-godot-destruct.js` | the M0 test suite |
| `docs/DESTRUCTIBLE.md` | this page |

Off is a real null path: `MatchSim.destructible` false means no `Destruct`, no tagged solids, no prop meshes, no extra
RNG draws and `combat.destruct == null`, so every weapon hook is skipped. The test compares a normal match against a run
with the mode explicitly off after 2 s: same state hash and same `CombatRng.state`. Turning the mode on for an arena
without authored props is also identical (no solids, no RNG draws).

## Tests

`godot/tests/destruct_test.gd` (run by `node tools/test-godot-destruct.js`, add
`"test:godot-destruct": "node tools/test-godot-destruct.js"` to `package.json`; not edited here):

1. authoring data: every prop on the floor, inside the arena, clear of spawns/ladders/pads/ring-out edges, no overlaps,
   sane hp/colour/size, budgets respected - plus negative cases proving each rule rejects bad data;
2. off: no solids/meshes/Destruct, and the baseline match is identical in state hash and RNG state;
3. on, for each arena: props load as solids with collision, an AK breaks a prop after its hp (solid removed, mesh
   released, events fired), an explosion breaks a nearby prop, a launched rocket breaks the crate it hits, broken props
   stay broken through 1 s of sim, and a fresh match rebuilds every prop unbroken;
4. every prop of every arena broken, then 120 more sim frames: no errors, no solids left, one rubble patch per prop,
   prop mesh nodes freed;
5. World wiring: Settings off = no props, on = props + `Breakables` mode line, `load_map` clears and rebuilds,
   `--destruct=on` override, and the Practice Range / Sandbox gates.

## Limits and the next milestone

Known M0 limits: offline only; three arenas; bullets and explosions only (no melee/flame); props do not ride a moving
floor (the mode forces `dyn = off`); no cascades (breaking one prop never breaks its neighbours); static rubble patches,
no pre-fractured chunk meshes or scorch decals; no per-prop `drop`; bots do not seek cover (nothing changed there).

**M1 (online, Godot-only rooms)** would need: a match rule (`start.rules.dest` like `dyn`/`dseed`/`dt0`), a host-authored
`brk` event carrying prop indices and already-broken indices on `start` for late joiners, guest-side application of a
break (remove the solid, hide the mesh, spawn debris - guests never roll prop hp), rejoin/host-migration state in `rsx`,
and a hard guard so web guests (who cannot render or collide with the props) are kept out of destructible rooms. See
`docs/DESTRUCTIBLE_ENV_STUDY.md` sections 5-6 for that design and `docs/PROTOCOL.md` for the message layout.
