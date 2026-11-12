# Godot graphics: tiers, look and budgets

Phase 4 part 1 (ROADMAP): the stylised look, every piece behind the tier switch so the phone stays at 60 fps and the
web build stays cheap. Screenshots: `docs/style/godot-gfx-<map>-before.png` (main before this pass) and
`-after.png` (HIGH), `docs/style/godot-gfx-tiers-farm.png` (HIGH / MID / LOW, top to bottom).

## Tiers

`Tier` (autoload, `godot/autoload/tier.gd`) picks the platform; `Tier.quality()` maps it to a graphics level.
Override for testing with `-- --tier=pc|mobile|web` (and the matching `--rendering-method`).

| | HIGH (PC, Forward+) | MID (iOS / Android, Mobile renderer, iPhone 12 budget) | LOW (web, Compatibility) |
|---|---|---|---|
| Tonemap | filmic, white 1.4, exposure 0.88 (night 0.94) | same | linear (the web game's look) |
| Grade (`map_look.json`) | contrast 1.1, saturation 1.18 day / 1.1 night / 1.08 indoor, split tone: shadows toward the hemisphere ground colour, mid-tones toward the sun | same | none |
| Glow | screen blend, threshold 1.0, levels 2-4: only HDR pixels (sun disc x1.6, lamps, emissive) | off | off |
| SSAO | radius 1.3, intensity 1.6 | off (Mobile has none) | off |
| Vignette | 16 %, CanvasLayer under the HUD | same | off |
| Sun shadow | 4 PSSM cascades (splits 0.08 / 0.22 / 0.5, blended), range 2.6 x map shadow size, blur 1.3, normal bias 2.0 | 2 cascades (split 0.22), range 1.9 x, blur 1.2 (2048 map, soft filter 1) | 1 orthogonal map, range 1.6 x, no blur |
| Fighter shadows | real | real | not cast; a soft blob on the ground under each fighter (`Gfx.BlobShadow`, follows the highest solid below while airborne) |
| Level boxes | `shaders/box.gdshader`: soft cel ramp (35 %), darker foot and vertical corners, light bevel on top edges; Practice Range grid (1 m / 5 m lines, 5 m checker, tone noise, as the web's `protoMat`) | same | plain `StandardMaterial3D` |
| Fighters | lambert wrap, rim light 0.6 (tint 0.3), specular off | same | plain lambert |
| Level decor (trees, props) | soft cel light | same | lambert |
| Far scenery | web `farPatch` (darker foot, lighter top) + up to 10 % fade toward the fog colour from 150 to 380 m (aerial perspective) | same | `farPatch` only |
| Moving scenery | balloons, ships, blimps, asteroids, turbines, smoke move (vertex shader) | same | same (a few hundred vertices: free) |
| Leaf wind | far leaves (web `farPatch` sway) and level tree canopies | same | still |
| Lava / water | slow churn / ripple highlights on the void plane and flat seas | same | colour only |
| Cloud layer | `shaders/clouds.gdshader`: one 720 m quad at 78 m, value-noise blobs with a crisp edge drifting ~1.7 m/s, tinted by sun / fog colour, faded before the far plane and when the camera is high | same | off (the baked web clouds stay) |

Tried and dropped: Godot height fog and aerial perspective (with depth fog at density 1 they wash the pastel sky and the
fog-free far scenery white), SSIL (noisy on flat colour faces, not worth its cost), full toon diffuse on fighters
(flattens the low-poly facets).

## Where it lives

- `godot/world/map_builder.gd`: `make_environment` + `_grade` (tonemap, grade, glow, SSAO), sky shader (sun boost),
  `box_material` / `_append_box` (box faces with UV = metres, UV2 = face size), `decor_material` (soft cel, `farPatch`,
  haze, moving / wind / liquid variant), `_add_decor` (still and moving meshes, `custom_aabb` for movers),
  `_add_cloud_layer`, `gfx_q()`.
- `godot/shaders/`: `box`, `clouds`, `blob_shadow`, `vignette` (`.gdshader`, no textures).
- `godot/world/gfx.gd`: `Gfx.add_post` (vignette), `Gfx.dress_fighter` (LOW blob shadows), called by `world.gd`.
- `godot/autoload/tier.gd`: `quality()`, `configure_sun` (cascades per tier), `configure_viewport` (MSAA).
- `godot/actors/wobbler.gd` `_make_mat`: fighter rim / wrap light (still a `StandardMaterial3D`, so hit flash and
  recolours work as before).
- `tools/export-map-decor.js`: measures the web game's moving pieces and writes their motion per vertex (format
  `WAD2`, see its header); `npm run map-decor` re-exports.

## Performance budget (`npm run test:godot-gfx`)

`godot/tests/gfx_bench.gd` builds Farm (40.7k decor tris), Candy (38.3k) and Crater Dome (18k, 51 moving pieces) with
10 fighters, plays 90 warm-up + 240 measured frames and records: CPU ms of `World.tick` (sim, 10 fighters' animation,
camera), the wall time of whole frames (vsync off; on a 120 Hz Mac the compositor may still cap it at 8.33 ms), and
the busiest frame's draw calls / primitives / objects from `RenderingServer.get_rendering_info` (shadow passes
included). `tools/test-gfx.js` runs it once per tier with that tier's renderer in a window; `--headless` (CI) checks
CPU only, `--tier=high|mid|low` runs one.

| Budget | HIGH | MID | LOW |
|---|---|---|---|
| CPU (`World.tick`, dev Mac) | 4 ms | 4 ms | 4 ms |
| Draw calls | 1400 | 800 | 650 |
| Primitives | 200k | 130k | 110k |
| Frame (dev Mac, sanity only) | 16.6 ms | 12 ms | 12 ms |

Why: an iPhone 12 CPU is roughly 3x slower than the dev Mac, so 4 ms here is ~12 ms there, leaving the render thread
room inside 16.6 ms. Draw calls and primitives do not depend on the device; ~10 fighters x ~35 parts (x shadow
cascades) are most of the draws, the level itself is a few dozen. Metal on an A14 handles ~1000 simple draws per
frame; MID stays under 800.

Measured (dev Mac, 1170x540 window, this branch):

| Tier | Farm | Candy | Crater Dome |
|---|---|---|---|
| HIGH | cpu 1.59 ms, 955 draws, 112k prims | 1.52 ms, 1104, 70k | 1.46 ms, 1237, 50k |
| MID | 1.60 ms, 492 draws, 82k prims | 1.48 ms, 692, 63k | 1.42 ms, 662, 41k |
| LOW | 1.56 ms, 394 draws, 67k prims | 1.44 ms, 463, 56k | 1.39 ms, 512, 35k |

Frames ran at the display's 8.33 ms on HIGH / MID and 8.5-9.5 ms on LOW (p95 under 11.1 ms).

Before this pass (main, same bench): HIGH 609-816 draws / 41-83k prims (2 cascades), MID 572-730 / 39-70k (one
cascade), LOW 578-779 / 40-71k, CPU 1.4-1.7 ms on every tier.

What is not measured here: GPU time on a phone and thermals (ROADMAP: 15 min on an iPhone 12 without throttling); that
needs a TestFlight build. Fill rate is the MID risk: the vignette and the cloud layer are two blended layers (the
clouds cover the sky only), MSAA 2x.

## Effects (Phase 4 part 2: motion polish and particles)

Screenshots (HIGH): `docs/style/godot-fx-explosion.png` (mid-explosion), `-confetti.png` (K.O. confetti + ring),
`-dash.png` (dash streaks + ring), `-melee.png` (katana swing trail), `-dust.png` (landing dust, ring and squash);
`tools/shoot-godot-fx.sh` re-renders them (`godot/tests/fx_shots.gd`).

Everything here is presentation only: it reads Combat events and fighter states, never writes sim state and never
draws from the global RNG. `npm run test:godot-fx` plays a seeded 40 s match with effects on and off and compares
the sim hash every second (identical), and floods every pool on every level.

| | LOW | MID | HIGH |
|---|---|---|---|
| Particle density (puff / dust / spark counts) | x0.4 | x0.75 | x1 |
| `bits` (puffs, dust, sparks, footsteps) cap | 96 | 320 | 720 |
| `chips` (confetti, debris, shells) cap | 24 | 120 | 240 |
| `blobs` (fireball, smoke, flames, muzzle flash) cap | 16 | 56 | 112 |
| `rings` (shockwaves) cap | 6 | 16 | 32 |
| `streaks` (dash, spark streaks, tracers) cap | 16 | 64 | 128 |
| Damage-number labels (pooled Label3D) | 10 | 20 | 28 |
| Ribbons (live trails) / samples per ribbon | 4 / 8, melee only | 12 / 12 | 24 / 18 |
| Ambient specks | off | 36 | 72 |
| Explosion | 2 fireballs, ring, 2 smoke, 4 debris | 3 fireballs, 2 rings, 5 smoke, 8 debris, 6 spark streaks | + 4 offset fireballs, 9 smoke, 14 debris, 10 streaks |
| Shell casings, spark streaks, head-hit ring, take-off dust, sprint footsteps | off | on | on |
| Squash / stretch, hitstop, camera shake | on | on | on |

Level: Settings `effects` (gear sheet "Effects": Auto / Low / Medium / High; Auto = the graphics tier). Screen shake:
Settings `screen_shake` (gear sheet toggle, default on).

What triggers what:
- **Dust** on hard landings (> 7 m/s down: a radial ring of bits, a ground ring and a small player shake over 11 m/s, as
  the web's `landDust`), skid dust on sudden stops (> 3 m/s speed lost in a frame from > 7 m/s), take-off dust and
  footstep puffs while sprinting (> 9 m/s), crate landings, quake tiles.
- **Dash**: streaks along the dash (Ninja dash `dx/dz`, or the dashing fighter's velocity for the katana lunge), a ring at
  the feet and a puff. **Slam** landing (an air swing that lands): a shockwave ring, dust ring, shake.
- **Hits** (`hit` event, damage zones from its `part`): sparks in the part colour (the damage-number colours: head red,
  torso yellow, arms blue, legs grey, so the struck spot and the number read the same) at the struck point, count by
  damage, speed by force, spark streaks above LOW, a small ring on head hits; the wobbler's own hit flash stays.
- **K.O.**: the death pop (`ko_burst`: puffs + `koBurst` ring + sparkles) and confetti in the killer's colour (with a
  ring), a 0.18 shake and, when the player scored it, a 4-frame hitstop.
- **Explosions** (rockets, grenades, meteor): fireball layers, ground ring(s), rising smoke, tumbling debris, sparks,
  shake by camera distance (the web's `0.34 - d x 0.011`). Flames and rocket exhaust smoke are blobs too.
- **Guns** (`shot`): a muzzle flash blob and three sparks; a brass (red for the shotgun) shell flicked out above LOW.
- **Bounce pads**: a cyan ring (+ white inner ring) and a puff.
- **Trails** (`world/trails.gd`): melee swing ribbon from the shoulder along the sim's swing target (`aim_*`, the arm
  itself lags on a spring) to the weapon tip, in the weapon colour, 0.2 s; projectile ribbons (arrow, rocket,
  shuriken, typhoon, boomerang, knife, trident), camera facing, 0.16-0.4 s. One ImmediateMesh for all of them.
- **Squash / stretch** (`actors/fighter_juice.gd`): a spring kicked by the landing speed (squash, overshooting into a
  stretch), a stretch kick on take-off, vertical stretch with speed in the air, a squeeze on hits. It scales the rig on
  top of the classic pose or the ragdoll overlay; `Fighter.present` restores the nodes before `animate()`, so the
  gameplay points (hand, head, chest) never see it.
- **Hitstop**: 2-4 rendered frames (hits >= 6 damage the player deals or takes, by damage; K.O.s by the player) where
  the presentation holds: fighters' visible pose, particles, trails, projectile views. The sim, `animate()` (whose
  points feed melee) and the camera's aim keep running, so gameplay timing never changes.
- **Camera shake** (`FollowCamera.add_shake / apply_shake`): the web's `cam.shake` (max of pulses, random offset,
  decays `exp(-9 t)`), applied after `aim_point` is computed and removed before the next frame.
- **Specks** (MID / HIGH): the web's drifting specks around the camera, kind from `map_look.json` `specks`, colour
  from `maps.json` `env.speckColor` (confetti: five colours).

Where it lives: `godot/world/fx.gd` (`FxSystem`: pools, builders, event handling, fighter motion watch, specks),
`godot/world/trails.gd`, `godot/actors/fighter_juice.gd`, `godot/shaders/fx_ring.gdshader`, `world.gd`
(`present`: hitstop, order), `projectile_views.gd` (blasts / flames / bursts / smoke go to `fx` when set),
`follow_camera.gd` (shake).

Pools: each is one `MultiMeshInstance3D` (one draw call), particles simulated in GDScript into one packed buffer per
frame (`MultiMesh.buffer`), live ones packed at the front (swap-remove), `visible_instance_count = n`; a full pool
overwrites its oldest slots (recycles), never grows. Nothing allocates per event except the trail sample arrays at
creation (ribbon objects are reused).

### Effects budget (`npm run test:godot-gfx`, scene `fx`)

`gfx_bench.gd` has a fourth scene, `fx`: Farm, 10 fighters, bots handed melee weapons (trails) and, every frame on top
of the real fight, synthetic events: 2 hits with sparks, an explosion every 6 frames, 3 flames, a muzzle flash every 3,
a dash every 10, a K.O. confetti burst every 20. Pools run at their caps. Same budgets as the maps, plus a check that
no pool or the ribbons ever go over their cap.

Measured (dev Mac, 1170x540 window, this branch):

| Tier | Farm (no stress) | `fx` stress (Farm) | fx peaks |
|---|---|---|---|
| HIGH | cpu 1.76 ms, 894 draws, 114k prims | cpu 2.79 ms (p95 3.35), 912 draws, 143k prims | bits 697 / chips 240 / blobs 112 / rings 24 / streaks 84, 5 ribbons |
| MID | cpu 1.74 ms, 464 draws, 83k prims | cpu 2.41 ms (p95 2.96), 512 draws, 99k prims | 320 / 120 / 56 / 16 / 58, 5 ribbons |
| LOW | cpu 1.62 ms, 349 draws, 67k prims | cpu 1.94 ms (p95 2.39), 431 draws, 74k prims | 96 / 24 / 16 / 6 / 6, 4 ribbons |

All under the 4 ms CPU / 1400-800-650 draw / 200k-130k-110k primitive budgets; frames stayed at the display's
8.33 ms (LOW p95 10.6 ms). The effects add at most ~7 draw calls (five pools, trails, specks) plus the labels; the
cost is CPU (~1 ms at HIGH caps, ~0.3 ms at LOW), i.e. ~3 ms of an iPhone 12 frame at MID worst case. A normal match
stays far below the caps (40 s, 8 fighters, HIGH: bits peak ~110, blobs 24, streaks 23).

## Still off

- LOW (Compatibility) renders noticeably brighter than Forward+ / Mobile with the same materials (before this pass
  too); its linear look is not tuned to match.
- Smoke columns bob instead of rising; birds are not drawn; the baked web clouds do not drift.
- Effects: alpha blobs inside one pool are not depth sorted (spawn order: smoke is spawned before the fire so the
  fire draws on top); the melee ribbon follows the sim's swing target, so with the ragdoll's lagging arm the trail can
  lead the visible blade a little; trails are pooled and capped but rebuilt every frame on the CPU (ImmediateMesh).
- Shadow edges keep a little PCF noise on HIGH.
