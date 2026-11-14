# Ragdoll study: wobblier legs

**Owner question:** "Study if we can make the character more like ragdoll — the legs more randomly wobbly?"

**Verdict:** feasible and cheap at the first slice. The game already ships a presentation-only ragdoll overlay
(`Settings.wobble_rig = "ragdoll"`, the default), so the problem is not missing simulation: both leg models are
**straight, single-segment, perfectly periodic sticks**, and the overlay's stepping is fully deterministic. M0 (seeded
per-fighter leg wobble, asymmetric gait, foot flop/splay, landing splay, a `Settings` slider) is presentation only, touches
no sim/net code, and should cost **1.5-2.5 dev days** including on-device visual tuning. A knee-bending pseudo-ragdoll is
a **4-6 day** follow-up; a physics ragdoll is **not** recommended now (Godot only; the web build keeps its classic pose).

## 1. What animates the legs today

Two visual modes, chosen by `Settings.wobble_rig` (`godot/autoload/settings.gd` ~56; `Fighter.rig_setting` +
`Wobbler.rig_mode`). In both, legs are geometry only: no logic reads a visible leg point.

| Layer | Where | What it does | Kind |
|---|---|---|---|
| Rig | `Wobbler._build` (`godot/actors/wobbler.gd` ~213-221) | each leg is one `Node3D` hip pivot at x ±0.2, y 0.8, holding **one** 0.8-long 5-sided cylinder (`Thigh`) and a foot box; **no shin, no knee joint** | view |
| Classic gait | `Wobbler.animate` ~612-625 | `stride` follows input, `phase += stride * dt * 1.5`; legs pitch about the hip: `leg0 = sin(phase) * amp`, `leg1 = -sin(phase) * amp`; `amp = min(speed / 5, 1) * 0.85` grounded, 0.4 airborne; body bob `abs(sin(phase)) * 0.07` | view |
| Ragdoll standing | `RagdollRig.update` ~254-319; `render` ~471-487 | feet are **world points**: a planted foot stays fixed; when it trails its home point (hip width ±0.2 plus a speed lead) it steps on an arc. A leg is drawn as one straight stretched segment (`leg_k` clamped 0.6-1.1); the foot is rotated back so it stays flat | view |
| Hips | `RagdollRig.update` ~321-345 | damped offset spring (k 60, zeta 0.35) plus `pel += (feet_mid - pos) * 0.25`; height spring k 160, zeta 0.5, clamped 0.35-1.15 of leg length | view |
| Torso/head/off arm | `RagdollRig.update` ~347-363; `render` ~495-526 | `tilt` spring 70/wob, `nod` 45/wob, off-arm verlet pendulum; sway `0.09 * sin(PI * step_t)` while a foot is stepping | view |
| Knock-down | `RagdollRig._start_down` 169-187; `_simulate_down` 388-430 | 6-point position-based body (pelvis, chest, head, 2 feet, aim hand), sticks, gravity, floor; stunned limbs paddle with `sin(time * 11 + i * 1.7)` | view |
| Readback | `Fighter.present` (`godot/actors/fighter.gd` 73-97), `FighterState.update_leg` (`godot/logic/fighter_state.gd` 204-206), `Combat.melee_sweep` (`godot/logic/combat.gd` ~766+) | classic `animate()` writes hand, arm direction, shoulder, head and chest into the state; `update_leg` writes the legs sphere point from the sim; the overlay then re-poses the visible nodes; melee tests the weapon line from the classic hand/arm | **sim** |
| Hit spheres | `FighterState.spheres` 198-202 | head/chest come from the classic pose written *before* the overlay; the legs sphere is `phys.py + 0.5` from the **sim**, not the rig | **sim** |
| Knobs | `shared/classes.json` via `Wobbler.cls` | `size` scales the rig; `wob` (Wobbler 1.0, Bruiser 0.7, Kid 1.45, Elder 0.55, Alien 1.2) only softens/stiffens the body springs today | view |

- The classic gait is a port of web `Fighter.animate` (`docs/CODEMAP.md` ~5601; legs `public/index.html` ~6413-6423),
  i.e. exactly this symmetric sinusoid; `Spring2` is parity-tested against the web class. The overlay is default-on on
  every tier (measured in §5); `docs/style/godot-ragdoll-*.png` shows both legs as straight lines, feet flat, one stance
  width for every fighter.

## 2. Why it reads stiff

| Cause | Evidence | What the player sees |
|---|---|---|
| No knee / shin | `Wobbler._build`; `RagdollRig.render` ~471-487 stretches one straight cylinder from hip to foot | a puppet on two sticks: the floppiness reads in the torso, not the legs |
| No splay, no ankle | foot kept flat (`foot_meshes[i].basis = unscale * ...`); stance is exactly hip width | stiff, ballerina-like base; legs never widen on a stop or a landing |
| Perfect antiphase, shared start | `leg0 = +sin(phase)`, `leg1 = -sin(phase)`; `phase` starts at `0.0` for every fighter | every fighter marches in lockstep at spawn; the gait is a metronome |
| Zero randomness | ragdoll step threshold, duration `0.42 / (speed + 1.4)` and lift are fixed; no seeded presentation RNG exists | identical steps forever; no per-fighter personality beyond torso stiffness |
| High cadence, capped travel | classic swing amplitude stops growing above 5 m/s; the ragdoll step duration clamps at 0.10 s | at sprint the legs churn quickly but do not flail like a ragdoll |
| Legs ignore impacts | `RagdollRig.hit` kicks hips/torso/head/arm; landings only dip `hy`; legs just step to catch up | hits look like the body was hit, not the legs |
| Hips mostly rigid | only 25 % pull toward the feet midpoint, heavily damped offset spring | the torso floats over a static base, the opposite of leg-driven floppiness |

The knock-down/K.O. path is the only genuinely ragdoll-like leg motion (6-point PBD, paddling limbs), which is why the
game reads floppy when down and stiff when standing.

## 3. Options, by cost

| | Option | What changes | Gameplay / net | Visual outcome | Cost (rough) | Risk |
|---|---|---|---|---|---|---|
| a | **Presentation-only gait tuning** (pick) | seeded per-fighter gait constants, asymmetric legs, step jitter, foot flop/splay, landing splay, small hip roll spring; `Settings` slider | none; legs still straight | irregular, puppet-like gait and per-fighter personality; no knee bend | **1.5-2.5 d** | low |
| b | **Procedural pseudo-ragdoll legs** | split each leg into thigh + shin + foot, two-bone IK to the planted foot, hip/knee/ankle springs reacting to speed, impacts, landings | none (still a view) | real knee bend, toe-off, heel strike, splayed catches; closest to the goal | **4-6 d** | medium: +2 meshes/fighter (+20 draws), more node-restore and test work |
| c | **Active ragdoll / physics limbs** | `RigidBody3D` / `PhysicalBone3D` per limb + joints + motors, arena collisions, possibly a skinned mesh | sim untouched only if strictly a view | true physical ragdoll | **2-4 weeks** | high: 6-10 bodies x 10 fighters on an iPhone 12, motor tuning, jitter, clipping |

**(a) presentation tuning (recommended M0).** Sample constants once per fighter (gait phase offset, frequency/amplitude
multipliers, left/right asymmetry, step duration/lift jitter, foot pitch/roll, stance splay, landing splay). Keep every
`PLANTED` foot exactly where it is (the no-skate test depends on it); put irregularity into the step arc, hip roll, foot
orientation and idle sway. Files: `ragdoll_rig.gd` (fields, sample, pose), `fighter.gd` (seed + setting plumbing),
`wobbler.gd` (seed holder, `leg_wobble` strength), `settings.gd` + `ui/settings_screen.gd` (one slider),
`tests/ragdoll_test.gd`. Determinism: seed from fighter identity known on every client (`net_slot` when online, else the
local `id`, mixed with a hash of class/skin/hat/colour), local generator only, no net fields. Cost/risk: ~1 day code,
~0.5-1 day tuning, ~0.5 day visual/device check; low risk, no draw-call change, and the largest cheap visual gain.

**(b) pseudo-ragdoll legs.** Two segments per leg (thigh + shin), two-bone IK to the planted/stepping foot, hip/knee/ankle
springs kicked by speed, landings and `lean` hits so the knee dips while the sole stays put; the cheaper variant reuses
the existing 6-point verlet body while standing with a weak "muscle" toward the standing pose. Files: `ragdoll_rig.gd`
(chain + IK), `wobbler.gd` (shin mesh; add nodes to `_xf_nodes` so `animate()` restore, `FighterJuice` and the overlay
see them), `wobbler_looks.gd` if leg parts need re-parenting, plus tests and shots. Every extra node must be
saved/restored exactly like the current 12. Cost/risk: +2 mesh instances per fighter = **+20 draw calls** for 10 fighters
before shadow cascades, roughly +5-15 us into the overlay; MID/HIGH draw headroom exists (MID 472-677 of 800, HIGH
902-1151 of 1400) but `npm run test:godot-gfx` must be re-run on all tiers. Medium risk: more nodes to restore, fixtures.

**(c) active ragdoll.** Real `RigidBody3D`/`PhysicalBone3D` limbs with joints and motors; needs a skinned mesh or rigid
parts parented to bones. Safe only if it stays a view (sim and hit spheres untouched); Godot physics is fixed-step but
not bit-identical across platforms, so it must never feed gameplay. 2-4 weeks, and a per-frame physics cost and tuning
burden that conflicts with the iPhone 12 / 10-fighter budget; the rigid-block rig makes skinned deformation a separate
art/programming job. Files would be a new limb script/scene under `actors/` plus hooks in `wobbler.gd`/`fighter.gd`. Not
now.

## 4. Determinism and network

- **Sim and net:** the fixed 1/120 s step (`World.SIM`) belongs to `MatchSim`/`FighterPhysics`; nothing in the leg work
  touches it. The 30 Hz `S` entry (`godot/logic/net_snapshot.gd`) carries position, velocity, yaw, arm direction, weapon,
  hp, dead/grounded, squash, invuln and lives: **no leg, foot, gait phase or wobble data is sent**, and ghosts run the same
  overlay locally from the interpolated snapshots.
- **Readback order is the guarantee:** `Fighter.present` reads the gameplay points from the **classic** `animate()` pose,
  then calls `overlay()`; `ragdoll_test.gd` asserts they are bit-identical in both modes, so a visual leg change cannot
  move them.
- **Hit spheres:** head/chest are rig-derived but read *before* the overlay; the legs sphere is `phys.py + 0.5`
  (`FighterState.update_leg`), so it already ignores the visible legs. Wobbling the legs affects neither hit detection nor
  melee (`Combat.melee_sweep` uses the classic hand/arm). Keep it that way: never write visible leg points into
  `FighterState`.
- **RNG:** sim randomness is `CombatRng` (Park-Miller), not the global stream; bots and dynamics have their own
  generators. Presentation may use its own. Do not copy the existing quirk where `Wobbler.apply_state` calls the global
  `randf()` for `fall_side` when the state omits it (`Fighter.visual_state` always provides it in game, but new code
  should not draw from the global RNG).
- **Per-client cosmetics:** a locally seeded wobble can look slightly different on each client; acceptable for legs (no
  gameplay reads them) and a stable fighter-identity seed usually matches. Exact sync would need the seed on the wire
  (`start.rules` or `S`) — a protocol change shared with the web game, **not** part of M0.
- Leave classic mode as the byte-for-byte web pose (the default is already ragdoll; classic exists for A/B and web
  parity); the Godot slider is Godot-only.

## 5. Performance

Measured in this worktree (Godot 4.7.2 headless, dev Mac; `test:godot-ragdoll`, `test:godot-spring`, `test:godot-wobbler`):

| Measurement | Value |
|---|---|
| Classic animate / ragdoll overlay per fighter-frame | 16.2 us / 23.3 us |
| 8 fighters, animate + overlay | 0.32 ms/frame (budget 150 us per fighter) |
| Spring parity, 4,000 mixed-dt ops | worst error 0.0 |
| Ragdoll test, 5 classes | 0 fails; 34-41 steps per run; max leg stretch 1.11-1.15 (limit 1.25); grip error <= 2e-6 |
| World CPU budget / measured (`docs/GRAPHICS.md`) | 4 ms / ~2.0-2.2 ms with 10 fighters |

- **M0:** a few extra `Spring2` instances and one small per-fighter generator: **+2-5 us per fighter-frame** (+0.02-0.05
  ms for 10 fighters), no new meshes/draws/nodes; the 150 us overlay and 4 ms world CPU budgets have large headroom.
- **Option (b):** +5-15 us per fighter and +2 meshes per fighter; CPU stays fine, but re-run `npm run test:godot-gfx` on
  HIGH/MID/LOW to check the draw calls (and shadow-cascade draws).
- **What to cap:** sample parameters once per fighter (no allocations in `update`/`render`), keep planted feet untouched,
  cap foot pitch/splay so the sole cannot visibly sink or lift far, cap landing splay by speed, add no per-leg meshes
  until (b), and scale all new amplitude by `leg_wobble` so 0 costs nothing.

## 6. Recommended first slice (M0)

Goal: visibly wobblier legs in **ragdoll mode**, no gameplay/network change, revertible with a slider.

1. **Seed once per fighter.** `Fighter.bind` sets a leg seed from `hash(class_id, skin, hat, colour, net_slot if online
   else id)`; `RagdollRig` samples the constants below once from a local generator (not in `_reset`, which runs on
   teleport, so respawns keep the same personality).
2. **Seeded gait constants:** `phase0` 0..2π, frequency x0.85..1.15, amplitude x0.8..1.25, left/right asymmetry
   x0.85..1.0, step duration/lift jitter x0.85..1.15 per step, foot pitch 0.10..0.25 rad in swing, foot roll ±0.10 rad,
   stance splay 0.02..0.08 rad; multiply amplitude by `clampf(cls.wob, 0.7, 1.3)` (Kid wobblier, Elder calmer).
3. **Where it acts:** ragdoll `update()` step trigger/arc (jitter only at step start, never on a planted foot), hip
   roll/yaw from a small `Spring2` kicked by steps and landings, `render()` foot basis (flop + splay, foot still flat at
   plant), and a landing splay kick scaled by landing speed; the dead/knock-down PBD path only gets a shared phase offset.
4. **Setting:** `"leg_wobble"` float 0..1, default **0.55** (0 = exactly today's pose), slider "Leg wobble" under
   Settings > Gameplay, applied live via `Settings.changed` (`Fighter._on_setting` already exists for `wobble_rig`); make
   0 a true bit-identical regression case by skipping the new terms.
5. **Visual check:** rerun `sh tools/shoot-godot-ragdoll.sh` (needs a window), compare `running`/`midstride`, then a real
   60 fps match with 10 fighters and one on-device pass; M0 adds no draw calls, so device risk is mainly the look.

Explicitly **out of M0:** knee/shin geometry, classic-mode changes, net fields, physics bodies, tier-specific looks.

## 7. Test plan

- `npm run test:godot-ragdoll`: keep every existing assertion (gameplay points bit-identical, finite, feet idle < 1e-5, no
  skate, leg stretch < 1.25, collapse/get-up); add: `leg_wobble = 0` reproduces the current pose bit-for-bit; different
  seeds give different leg poses at the same frame; the same seed and state give the same pose across runs; pose stays
  bounded; overlay budget still < 150 us.
- `npm run test:godot-wobbler` and `test:godot-spring`: unchanged (leg geometry/node counts; `spring.gd` is not modified).
- `npm run test:godot-ui`: already lays out every Settings section, so the new row is covered; re-run it after adding the slider.
- Visual: `sh tools/shoot-godot-ragdoll.sh` before/after (running, midstride, hit, down, getup), a moving 10-fighter
  match, and a phone pass for readability and motion comfort.
- Regression: `npm run test:godot-fx` (sim hash unchanged with effects on/off) is the cheap guard against a sim leak.

## 8. Not recommended / what to avoid

- Do not make legs game-affecting: no writes to `FighterState` hit/arm/head/chest points, no leg-based hit spheres, no `S`
  fields for wobble in M0.
- Do not move planted feet for "randomness": it breaks the no-skate test and the leg-driven feel; randomise the step only.
- Do not use the global RNG (`randf`/`randi`) per frame, wall-clock seeds, or frame counts as seed.
- Do not touch `Spring2`, the classic `animate()` pose, `logic/` or `net/` code, or the web-shared `shared/*.json`.
- Do not add per-tier leg looks: screenshots are compared across HIGH/MID/LOW; a cosmetic difference is not worth it.
- Avoid big amplitudes: the visible legs already disagree with the sim legs hit sphere; large wiggles make hits look
  wrong. Keep the aim arm and grip untouched (accuracy is sim data).
- Do not tie footstep audio/dust to the randomised gait; those systems are speed-based (`World._audio_motion`,
  `FxSystem.watch`) and already independent.
- Do not start with a physics ragdoll: cost and tuning outweigh the visual gain at 10 fighters.

## 9. Open questions for the owner

1. **How silly?** Proposal: slider default 0.55, range 0-1 (0 = today). Separate "Ragdoll strength" setting, or one slider?
2. **Accessibility:** is the slider enough, or also a "Reduce motion" toggle capping leg sway (and camera shake)?
3. **Readability/competitiveness:** is an irregular gait acceptable online if cosmetic? Some players read gait to judge speed, even though the sim is unchanged.
4. **Classic mode:** leave it as the web pose (recommended), or wobblify it behind the same slider?
5. **Knee bend:** straight-stick M0 with the knee (option b) as a follow-up, or is a visible knee mandatory for M0?
6. **Per-class personality:** use `wob` (Kid wobblier, Elder calmer) as proposed, or keep all fighters equal?
7. **Online cosmetics:** is it fine that each client's legs wobble slightly differently, or must it be identical (then a seed field must go into the protocol and the web game)?
