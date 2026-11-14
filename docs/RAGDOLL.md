# Ragdoll wobble rig (Godot)

Goal: fighters look and feel like floppy ragdolls driven by their legs (Gang Beasts / Human Fall Flat lite), while
the deterministic match (FighterPhysics capsule, Combat, net snapshots, web cross-play) stays bit-identical.
Setting: `Settings.wobble_rig` = `"ragdoll"` (default) | `"classic"`. `Settings.leg_wobble` 0..1 (default **0.55**)
adds the seeded per-fighter leg wobble in ragdoll mode only (see "Leg wobble (M0)" below).

## What exists today

- `godot/actors/wobbler.gd` is a port of the web `Fighter.animate` + `applyPose`. The whole character is one rig
  node at the sim position, rotated by yaw; legs are single cylinders swung by `sin(phase)`, the torso leans with a
  `Spring2` (`lean`), the head with another (`head`), the aiming arm is a direction spring chasing the sim `aim`,
  the off arm swings with the stride. Knock-downs rotate the whole rig about its forward axis (`fall_a`).
- `godot/logic/spring.gd` (`Spring2`) is a 2D damped spring, a 1:1 port of the web class, parity tested.
- `godot/actors/fighter.gd` feeds the `FighterState` to the wobbler, animates it, then **reads points back into the
  state**: hand, arm direction, shoulder, head, chest. Combat, bots and weapons use those points (melee sweep,
  headshot sphere, muzzle position), exactly like the web game. So the classic pose is *gameplay data*: it must keep
  being computed the same way, from the same springs, every frame, on every client.
- Combat events `lean` / `head` / `arm` kick those springs on a hit; `topple` sets `down_t`; K.O. sets `dead` +
  `fall_side`.

Legs today are decoration: feet slide over the floor (skating), the body never reacts to where the feet are.

## Approaches

| | Approach | Pros | Cons |
|---|---|---|---|
| A | **Godot physics ragdoll** (`PhysicalBone3D` / RigidBody per limb, joints, motors pulling toward a pose) | Real collisions with the arena, "true" ragdoll | ~10 bodies x 8 fighters is too heavy for an iPhone 12 at 60 fps; not deterministic and hard to keep near the sim capsule; wants a skinned mesh (ours is rigid blocks); motor tuning is fragile |
| B | **Procedural pose + springs** (today's approach, tuned harder: bigger leans, phase-driven legs) | Cheapest, no new state | Still skates; nothing is driven by the legs; knock-downs stay a canned rotation |
| C | **Verlet / spring overlay driven by foot planting** (pick) | A few dozen vector ops per fighter; feet planted in world space; hips follow the feet like an inverted pendulum; spring chains for torso/head/off arm; a 6-point verlet body only while knocked down; pure view, so no determinism risk | Not a real collision ragdoll (the collapsed body only knows the floor height); single-segment legs stretch a little instead of bending a knee |

## Pick: C, as a presentation-only overlay

The classic pose runs unchanged every frame and `Fighter.present` reads the gameplay points from it **before** the
overlay re-poses the visible nodes. So in ragdoll mode the sim sees exactly what it sees in classic mode (and on the
web); only the pixels change. The overlay saves the classic transforms of the nodes it touches and the next
`animate()` restores them first, so even a zero-dt present reads the classic pose.

`godot/actors/ragdoll_rig.gd` (`RagdollRig`, one per wobbler, allocated once) computes the visible points per frame
(pelvis, chest, head, two feet, off hand, aim hand) and derives every node transform from them.

### How "purely leg control" maps to the controls

1. **Stick -> feet.** The stick moves the sim capsule; each foot has a home point (hip width to the side, a little
   ahead in the travel direction). A planted foot stays fixed in world space (no skating). When it trails too far
   behind, or the leg would over-stretch, it steps: lifts on an arc and lands on the *predicted* home (where the body
   will be when the step ends). Feet alternate; at a sprint the steps get short and quick (a chibi scurry). Turning
   in place re-plants the feet; standing still, a late tidy-up step squares them up.
2. **Hips follow the feet (damped inverted pendulum).** The pelvis is the sim position pulled toward the feet
   centroid, plus an offset spring driven by the sim acceleration: the hips lag on starts and overshoot on stops.
   Hip height is capped by leg reach to the planted feet, so the body bobs with every stride and dips on landing
   (a vertical spring kicked by the landing speed).
3. **Torso, head, arms are spring chains with lag.** The torso tilts with a soft `Spring2` driven by acceleration
   and speed (leans into runs, flops on stops, sways over the stance foot); the head is a second spring on top,
   driven by the torso's angular acceleration; the off arm is a verlet pendulum hanging from the visible shoulder
   with a weak "muscle" pull toward the classic swing.
4. **Aim stays accurate.** The aim direction and hand point are sim data. The visible aiming arm starts at the
   wobbling shoulder and stretches to the sim hand; the grip/weapon keeps its exact classic world transform, so
   bullets leave the muzzle you see (tested to 1e-4).
5. **Hits** shove the hips and snap the torso/head away from the blow and fling the off arm, scaled by knockback
   force (the `lean` event) and damage (hp drop): a stagger the feet must step to catch.
6. **Knock-down / K.O. / net trap** switch to a 6-point position-based body (pelvis, chest, head, feet, aim hand):
   stick constraints, gravity, floor at the sim height with friction, carried along with the sim position and
   leashed to it. It collapses toward `fall_side` and the hit direction; stunned limbs paddle. When `down_t` ends it
   **gets up**: a 0.55 s eased blend from the collapsed points back to the standing controller (feet re-planted
   first). A K.O. stays down until the respawn teleport resets the rig.
7. **Landing squash** keeps the classic rig squash and adds the hip dip.

Cost: no per-frame allocations; ~30 us per fighter-frame for the overlay on a desktop dev machine (see the test
output), i.e. well under 1 ms for 8 fighters even at iPhone-12 speed.

## Leg wobble (M0, seeded gait)

`docs/RAGDOLL_STUDY.md` is the rationale: the legs are straight single-segment sticks and the overlay's stepping is
perfectly periodic, so M0 adds a deterministic per-fighter "gait personality" to the presentation. It touches no sim,
net, hit-sphere or classic-pose code: the classic `animate()` pose (and the gameplay points read from it) is exactly
as before, and the wobble never moves a foot point — it changes step timing, the hip roll and the foot block's
orientation, not where a planted sole is.

- **Seed.** `Wobbler.gait_identity()` mixes the owning `Fighter.state.net_slot` when online (the slot is the stable
  per-client identity), else the match `state.id` (unique offline, bots included), with the look (class, skin, hat,
  colour) through a local FNV-1a/xorshift32. A standalone wobbler (tests/tools) mixes the look and an optional pinned
  `gait_seed`. Nothing reads the global `randf()`/`randi()`. `Wobbler.overlay()` samples the personality once per
  fighter (`RagdollRig.set_gait`) when the identity or look changes; `_reset` (teleport/respawn) keeps it.
- **Sampled once per fighter** from a local xorshift32: phase offset 0..2π, step cadence ×0.85..1.15, swing/lift
  amplitude ×0.8..1.25, left/right asymmetry ×0.85..1.0, per-step duration/lift jitter ×0.85..1.15 (a pure hash of
  seed + step count, so it replays), foot flop 0.10..0.25 rad in swing, foot roll ±0.10 rad, stance splay
  0.02..0.08 rad, landing splay 0.05..0.12 rad, hip-roll step kick. Amplitudes are scaled by
  `clampf(cls.wob, 0.7, 1.3)` (Kid wobblier, Elder calmer) and by the setting.
- **Pose.** A small hip-roll `Spring2` is kicked by step starts and hard landings and idles with the phase offset; it
  only tilts the leg roots, so planted feet stay put. The foot block gets the stance splay, a pitch/roll flop while
  stepping, and a short splay envelope after a hard landing. While down/K.O. the leg pose gets no wobble (it would
  fight the 6-point PBD body); only the down-struggle paddle gets the shared phase offset. Classic mode is
  untouched (the web pose).
- **Setting.** `Settings.leg_wobble` float 0..1, default **0.55**, slider under Settings > Graphics
  ("Leg wobble": "Extra random wobble in the legs. Cosmetic only."). It is applied live through `Settings.changed`.
  **0 is the exact pre-M0 pose**: every extra term is skipped and the step/plant maths runs the old code path
  (the in-flight step returns to the base cadence immediately).
- **Zero-proof.** `godot/tests/ragdoll_test.gd` hashes the rendered leg node transforms and foot blocks over 480
  scripted frames (locomotion, a hop/landing, a hit kick). The pre-M0 build and the new build at `leg_wobble = 0`
  both produce `00cb48fb5026807c00be8e2497c392aad40ec709df77bbf19d91cbab8d1b2535`.
- **Determinism.** Same seed + same state frames = the same pose; the per-step jitter is a pure hash of seed + step
  count; different seeds give different leg poses; a lockstep pair with the same seed matches transform for
  transform. Online, each client may wobble slightly differently — it is cosmetic (M0 adds **no** wire fields; the
  seed would have to be published for exact cross-client match, and the web game does not have it).
- **Cost.** No new nodes, meshes or draw calls, no per-frame allocations: two extra jitter lookups and one `Spring2`
  step per fighter-frame. Measured (Godot 4.7.2 headless, dev Mac, `test:godot-ragdoll`): overlay
  **~22.5-25.6 µs**/fighter-frame at 0 and **~26-27 µs** at 0.55 (+3-4 µs, ~15 %), i.e. **0.30-0.34 ms/frame at
  8 fighters** and **0.41-0.49 ms at 10** (budget 150 µs per fighter). The pre-M0 build measured 22.5 µs / 0.30 ms.

## Files and tests

- `godot/actors/ragdoll_rig.gd` — the overlay maths (standing controller, stepping, knock-down body, get-up, posing)
  and the seeded gait (`mix_seed`, `set_gait`, step jitter, hip roll, foot splay/flop, landing splay).
- `godot/actors/wobbler.gd` — `rig_mode`, `overlay(dt)`, classic transform save/restore, `ragdoll_hit()`, the
  `leg_wobble`/`gait_seed` knobs and `gait_identity()`.
- `godot/actors/fighter.gd` — reads the sim points, then calls `wobbler.overlay(dt)`; routes `lean` hits.
- `godot/autoload/settings.gd` — `wobble_rig`, `leg_wobble` keys. `godot/ui/settings_screen.gd` — both pickers.
- `npm run test:godot-ragdoll` (`godot/tests/ragdoll_test.gd`): classic vs ragdoll gameplay points bit-identical,
  finite/bounded pose, feet planted while idle and never skating, grip on the sim hand, collapse and get-up,
  frame-time budget with 8/10 fighters, plus the M0 leg-wobble checks: `leg_wobble = 0` reproduces the pre-M0
  digest bit for bit, 1 changes the legs, same seed+frames replays, different seeds differ, planted soles stay on
  the floor, the Settings default/live change, and the seeded identity from fighter id / net_slot.
- `sh tools/shoot-godot-ragdoll.sh [classic]` renders `docs/style/godot-ragdoll-*.png`.
