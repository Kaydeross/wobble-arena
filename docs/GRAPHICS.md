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

## Still off

- LOW (Compatibility) renders noticeably brighter than Forward+ / Mobile with the same materials (before this pass
  too); its linear look is not tuned to match.
- Smoke columns bob instead of rising; specks and birds are not drawn; the baked web clouds do not drift.
- Shadow edges keep a little PCF noise on HIGH.
