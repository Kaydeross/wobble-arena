# Destructible environments (Godot): feasibility study

Optional mode: crates, barricades and cover that break under bullets, melee and explosions. This is a study, not a
plan of record. Measurements below are from a headless benchmark of this worktree (Godot 4.7.2, Apple M2 Pro,
no rendering) and from the numbers `docs/GRAPHICS.md` already records; they are a desktop proxy, not a phone result.

## Verdict

| Question | Answer |
|---|---|
| Worth building? | Yes, as an **offline opt-in mode** built on a **new prop class**: it fits the existing collision, event and effects systems. |
| Online now? | No. Breaks are host-authoritative state and cannot be web-cross-played without a different design; that is a separate, larger milestone. |
| First slice | Breakable barricades/crates on three small arenas, offline, bullets + explosions only, collision removed and debris spawned. Roughly 3-5 dev days. |
| Biggest risk | Online replication and the web-guest constraint; second is authoring/validating enough props per arena without blocking spawns or bot paths. |
| Cut for v1 | Online, breaking existing map walls, scenery, cascades, decals, pre-fractured meshes, Arcade. |

## What exists today that we can reuse

| System | Where | What it gives us |
|---|---|---|
| Collision representation | `FighterPhysics.solids_from_map` (`godot/logic/fighter_physics.gd`): one flat `Array` of `{minX,maxX,minZ,maxZ,top,bottom}` dictionaries | Nothing to invent: a movable solid is just a dictionary in that array |
| Runtime solid mutation | `ArenaDyn._build_tiles` (`godot/logic/arena_dyn.gd`) replaces the floor with up to 144 tile solids in place; `update` moves them in the array; `ModeRules.setup_shrink` (`godot/logic/mode_rules.gd`) mutates the floor box | Proof that the list is mutable at runtime and that tile/anchor rules already exist |
| Mesh swapping | `World._build_dyn_views` (`godot/world/world.gd`) calls `MapBuilder.rebuild_boxes` (`godot/world/map_builder.gd`); `_build_shrink_view` does the same | The pattern for "one mesh per movable box, merged boxes rebuilt without it" |
| Effects | `FxSystem` (`godot/world/fx.gd`): five pooled `MultiMesh` sets, one draw call each; `chips()` already tumbles flat boxes for debris | Debris, dust and sparks need no new pipeline |
| Events | `Combat.ev` and `World._drain_events` (`godot/world/world.gd`) forward every event to effects, audio, projectile views and the net match | A new `break` event reaches every consumer with no new plumbing |

## 1. Which props break, and how they are authored

| Candidate | Data today | Verdict |
|---|---|---|
| **Existing map geometry** (walls, cover, pillars) | `shared/maps.json` boxes, exported from `MAPS.*.build()` in `public/index.html`; exported boxes carry only `x,z,w,d,h,color,y` (recorder in `tools/export-maps.js`) | Best spectacle (a wall collapsing changes the arena), but there is no per-box identity or tag and no safe key. Needs a source tag plus a content pass over 34 arenas. Slice 3, not v1. |
| **Scenery (decor)** | `_add_decor` (`godot/world/map_builder.gd`) bakes every tree, rock and lamp into at most four merged meshes per arena | No. Individual pieces have no node identity; breaking scenery means changing the exported `WAD2` format and re-exporting every arena. Out of scope. |
| **New prop class** (crates, barricades, barrels) | Nothing yet; new manifest in `godot/data/extra/` | **Pick this for v1.** New solids appended at setup, no map data touched, trivially authorable and testable. |

**Authoring.** `docs/WRITING.md` is explicit: never hand-edit `shared/*.json` or `godot/data/*.json` outside `extra/`.
So v1 authors a Godot-side overlay, `godot/data/extra/destructible.json`, keyed by arena id, with props
`{x, z, w, d, h, y, color, kind, hp}` (the shape `MapBuilder.custom_map` already emits). Only arenas in the file get
props, so the mode is opt-in per arena and normal modes are untouched. The later wall slice moves the tag to the source
(`addBox` gains an optional breakable tag in `public/index.html`, the exporter carries it, `npm run content` regenerates
`shared/maps.json`); no hand-edited export and no box-index overlay.

**Validation** (must exist before content): every prop stands on a solid top, stays clear of spawns, bot starts, crate
spots, ladders and bounce pads, does not overlap another box and sits inside the arena bounds. Re-run the walkability
idea from `tools/check-maps.js` so a barricade cannot cut bots off (extend `godot/tests/maps_test.gd`, not a new test).

**Wiring.** `MatchSim.setup` builds solids at `godot/logic/match_sim.gd` line 81 and calls `dyn.setup` immediately
after; props are appended between those two, so dynamics anchors floor tiles under them, but `Dynamics.plan`'s drift
candidate scan must skip tagged props (one condition) or a crate could be selected as a drifting block.

## 2. Collision at runtime

Removing a prop is `remove_at` on `sim.solids`: fighters, bots (`MatchSim.has_los`) and every weapon query read the
same list, so a break takes effect on the next sim step. `ArenaDyn` keeps dictionary references to its tiles, not
indices, so a later removal does not corrupt the dynamic arena. Order matters only in that removal must happen at the
top of the step, before fighters collide.

Measured costs (dev Mac, per break unless noted; draw props as individual meshes and never call `rebuild_boxes` on a
break):

| Operation | Cost | Reading |
|---|---|---|
| Remove one solid from a 150-solid list | 1.3-2.2 µs (1000 removals, 1.3-2.2 ms) | Free; budget is not the concern |
| Rebuild a whole map's merged boxes excluding 24 | 1.1 ms (43 boxes), 1.4 ms (94), 8.0 ms (340-box generated site) | Do **not** rebuild the map per break |
| Rebuild one 20-box destructible group | 0.6 ms | Acceptable per break, but avoid on a busy frame |
| Create 40 individual prop meshes at load | 0.45 ms once | The v1 approach |
| 10 fighters, 120 physics steps, tiled arena (107 solids) | 30 ms (0.25 ms per 1/120 s step) | Existing cost; losing solids makes it cheaper |

**Impact queries.** Today every weapon asks a different question, and each needs a "which solid did I hit" variant:

| Source | Current query | Change |
|---|---|---|
| Hitscan | `Weapons.ray_walls` (nearest distance only) in `fire_gun` | Return the hit solid too; accumulate prop damage on that prop |
| Rockets, grenades, thrown | AABB containment in `step_rockets`, `_in_solid` in `step_grenades`/`step_knives` | Return the box (or its index) instead of a boolean |
| Explosions | `explode` only calls `ground_below` and tests fighters in radius | Add a destructible-only loop with the same distance falloff |
| Melee | `Combat.melee_sweep` tests fighter spheres only | Add a segment test against the destructible subset on the bat line |
| Flame, punch | `_punch` uses wall rays for sight only; flame tests fighters only | Optional in v1; the same helper covers it later |

**Bounds.** One break per sim step, two at most, queued; props are finite per arena so the match total is bounded by
authoring. Debris uses the existing capped pools (MID: 120 chips, 320 bits), so over-breaking recycles the oldest
particles instead of growing.

**Cascade.** A supporting rule ("a prop whose bottom rests on a broken prop's top within 3 cm also breaks") is cheap
and reads as a wall collapse, but it must be computed by the authority and queued, never by every peer. Keep it out
of v1; the queue already exists, so it is one function later. One blemish to decide early: crates sit on a stored
ground height (`Pickups.spawn_drop`), so a crate on a destroyed platform would float; setting it ungrounded on break
is three lines.

## 3. Visuals

| Technique | Cost | Look | v1? |
|---|---|---|---|
| Procedural chips (`FxSystem.chips`, existing pool) | 0 extra draws, ~10 chips = 120 triangles | Tumbling coloured slabs; reads as splintering wood/plastic, not masonry | **Yes** |
| Dust puff + ring (`dust`, `ring`, `bits`) | 0 extra draws | Sells the impact; same language as explosions | Yes |
| Cameras shake (`FollowCamera.add_shake`) on walls only | 0 draws | Big break feels big | Yes, walls only |
| Scorch/scuff decals | +1 draw (new quad `MultiMesh`) | Nice on the floor | Later |
| Pre-fractured chunk meshes | +1-2 draws (new pool) + authoring per prop | Proper chunks; worth it for hero walls only | Later |
| New "crack" sound | none in-engine; needs a recipe in `public/index.html` `SOUNDS`, `tools/render-sfx.js`, `godot/autoload/audio.gd` `NAMES` | Wood/stone crack | Reuse `clink`/`whack` + `land` in v1, add later |

Budget: MID measured 472 (Farm), 677 (Candy) and 651 (Crater Dome) draws against 800, and the effects stress scene
563 draws / 97k primitives against 800 / 130k. Each prop mesh costs one draw, plus two shadow cascades on MID if it
casts; turn shadow casting off for small props. Cap destructibles at **24-40 per arena**: 40 props with shadows off is
~40 draws, comfortably inside the measured headroom; with shadows that becomes up to 120 and gets close on Candy.
Primitives are irrelevant (40 boxes = 480 triangles).

At M/VFX quality: a crate takes 2-3 hits, flashes, bursts into 8-12 coloured chips with a dust ring and a short clink,
and the same prop count stays fixed all match; a barricade or wall collapses in two or three groups with a dust cloud
and a small camera shake. That matches the existing explosion/impact fidelity, not a geometry-fracture showcase: no
textures, no decals, no persistent rubble piles.

## 4. Rules and modes

Follow `Dynamics` exactly: a `Settings` key (`destruct`: `off` | `light` | `full`, default `off`) with a row in the
Setup Wizard next to "Moving floor" (`godot/ui/setup_wizard.gd`), a `--destruct=` override like `--dyn=`, and the
choice stored per match, not baked into arenas. Off means no props, no code path, identical behaviour to today; normal
modes are untouched because props exist only in arenas listed in the manifest.

- **Mode gates:** opt-in arenas only; skip the Sandbox (`custom`, whose blocks `BuildHud` already owns and mutates),
  the Test Map and Practice Range, and the shrinking-arena maps (their floor is scaled, not broken).
- **Ring-outs:** v1 props stand on the floor, so ring-out behaviour is unchanged. The wall slice is where this
  matters: never break the only floor, perimeter walls, or boxes carrying a spawn, ladder, pad or crate spot — the
  same "anchored" idea `Dynamics.plan` already uses for floor tiles. A fall through a new hole is credited by the
  existing 10-second `last_attacker` window; an unattributed environmental K.O. is already handled as a plain fall.
- **Bots:** no work needed. `BotBrain` re-reads `sim.has_los` every think, and `MatchSim.has_los` raycasts the live
  solid list, so a removed barricade opens a firing line next think. Bots do not seek cover today, so there is nothing
  to teach them; they also avoid walking off edges (`docs/ARENAS.md`), so new holes are not bot traps.
- **Arcade:** leave out of v1. Arcade runs on generated `sitegen` sites and is host-authoritative co-op; its notes
  already mention shoving a melee boss through a fence gate, and more holes make that worse. Revisit after online.

## 5. Online

Collision is simulation state, so a peer that does not know a prop broke walks into geometry that is not there on the
other screen. Local prediction cannot fix it: hitscan spread uses each client's own `CombatRng` stream, so the two
sides would not agree. Therefore breaks must be **host-authoritative**, exactly like crate spawns and takes.

| Need | Addition |
|---|---|
| Turn it on | `start.rules.dest` (`off`/`light`/`full`), read before `MatchSim.setup` like `rule_dyn` does for `dyn`/`dseed`/`dt0` |
| A break happened | Host `brk` message (`i` = prop index, optionally batched as `l[]`) sent from `HostMatch.on_event` when the break event drains |
| Guest applies | `NetMatch.handle` removes the solid, hides the prop mesh, spawns debris; guests run no prop HP, no cascade and never send `brk` (guard like `take`) |
| Join mid-match | `brks` list of already-broken indices on `start`, like `crates` |
| Host migration | Broken list in `rsx`, like `crate` ids and `dyn` clock already are |
| Cross-play | Web guests cannot render or collide with broken props. The mode must be app-only: gate it on `gd`/`gmode` the way app-only modes are, or disable destruction when a web guest is present |

Protocol cost is tiny (`brk` is tens of bytes against the server's 32 KiB payload cap, and only on a break), and
`PROTO` need not change; the real cost is state: late break application (the guest walks into a wall for one round
trip), rejoin, host migration, and keeping web clients out of these rooms. **Offline-first v1 is the right call**: it
validates look, feel, authoring and cost without touching the protocol or cross-play.

## 6. Milestones

| # | Slice | Scope | Files touched | Test harness | Main risk |
|---|---|---|---|---|---|
| **M0** | Breakable crates/barricades, offline | Manifest for three small arenas (~8 props each); bullets and explosions break; solid removed, mesh hidden, chips + dust; setting + wizard row | New `godot/logic/destruct.gd`, `godot/data/extra/destructible.json`; `logic/match_sim.gd`, `logic/dynamics.gd` (skip props in drift), `logic/weapons.gd`, `world/world.gd`, `world/fx.gd`, `autoload/settings.gd`, `ui/setup_wizard.gd` | New `godot/tests/destruct_test.gd` + `tools/test-godot-destruct.js` (copy the dynamics runner); extend `godot/tests/maps_test.gd` for manifest validation; `godot/tests/physics_test.gd` for walk-through-after-break | Prop placement blocks a spawn or bot path; the "which solid" change touches four weapon paths |
| **M1** | Impact coverage and prop types | Melee, flame, grenades; per-prop HP and materials; one-break-per-step cap; cascade; sound, shake, debris tuning | `logic/combat.gd`, `logic/weapons.gd`, `world/fx.gd`, `logic/destruct.gd`, new sfx recipe + `tools/render-sfx.js`, `autoload/audio.gd` | `godot/tests/combat_test.gd`, `godot/tests/fx_test.gd` (pool caps), `gfx_bench` scene | Cascade cost and draw-call growth; more breakables per arena than the budget allows |
| **M2** | Breakable map walls and cover | Tag existing boxes at the source (`addBox` tag, exporter, `npm run content`); per-arena opt-in; anchors near spawns/pads/ladders are never breakable; walkability re-checked | `public/index.html`, `tools/export-maps.js`, `shared/maps.json` + `godot/data/maps.json` regenerated, `godot/logic/destruct.gd`, `godot/tests/maps_test.gd` | `npm run content:check`, `npm run check:maps`, `godot/tests/maps_test.gd`, screenshots of three arenas | Box order churn breaks the tag mapping; more ring-outs and bot path changes than intended; content pass across 34 arenas |
| **M3** | Online (Godot-only rooms) | `rules.dest`, `brk`/`brks`, guest apply, rejoin and migration state, guard rules, protocol doc | `godot/net/net_match.gd`, `godot/net/host_match.gd`, `godot/net/guest_session.gd`, `godot/net/host_session.gd`, `docs/PROTOCOL.md` | `npm run test:godot-netguest`, `test:godot-host`, `test:godot-arcade`, `npm run test:crossplay-web` | Divergence under latency, web guests in a destructive room, host migration losing the broken list |
| **M4** | Hero-quality pass | Pre-fractured chunks for walls and barriers, decals, dedicated debris pool, shot harness | `world/fx.gd`, `world/map_builder.gd`, new debris data, `godot/tests/destruct_shots.gd`, `tools/test-gfx.js` | `npm run test:godot-gfx`, screenshot run | Art time; the extra pool and shadow casters eat the headroom saved in v1 |

M0 is deliberately small: one new logic class, one data file, one-line hooks and a copy of the dynamics test runner.

## 7. Recommendation and cost

Build it offline, as an opt-in mode, starting with new props. Rough shape: M0 3-5 dev days; M1 about a week; M2 1-2
weeks plus a content pass; M3 2-3 weeks with cross-play restrictions; M4 about a week of polish. Budget the whole
offline feature at 4-6 weeks at M/VFX quality, with online as a separate 2-3 week risk.

It is worth it because the cheap version is genuinely cheap: props are just solids, breaks are just events, debris
already exists, and the mode is off by default. The honest limits: **walls are the expensive part** (source tags,
per-arena validation, ring-out and bot balance), **scenery is out**, and **online is a second feature** that also locks
web players out of those rooms. Cut online, cascades, decals and Arcade from the first milestone; keep the crates.

## Open questions (owner only)

1. **Name and wording** for the setting row and any mode name, in the game's goofy kid-safe voice: "Breakables"? "Smashable props"? "Destructible arena"?
2. **Which arenas first.** Proposal: three small phone-friendly arenas with real cover (Sunny Arena, Wobble Park, Brawl Pit) before the large team maps.
3. **How destructive.** Crates and barricades only, or genuine wall/cover collapse (which changes ring-outs, bot paths and fairness)? How many per arena, and do they return next match only?
4. **Online scope.** Offline only for now, Godot-only rooms later, or is cross-play with web guests a hard requirement
   (a much larger design)? May web players be excluded from destruction rooms?
5. **Scoring.** Should an environmental K.O. count normally, get its own stat/toast, or stay an unattributed fall?
6. **Access.** Free for everyone, or tied to the Arcade/Construction DLC? On by default for new players or opt-in?
