# Ragdoll wobble rig (Godot)

Goal: fighters look and feel like floppy ragdolls driven by their legs (Gang Beasts / Human Fall Flat lite), while
the deterministic match (FighterPhysics capsule, Combat, net snapshots, web cross-play) stays bit-identical.
Setting: `Settings.wobble_rig` = `"ragdoll"` (default) | `"classic"`.

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

## Files and tests

- `godot/actors/ragdoll_rig.gd` — the overlay maths (standing controller, stepping, knock-down body, get-up, posing).
- `godot/actors/wobbler.gd` — `rig_mode`, `overlay(dt)`, classic transform save/restore, `ragdoll_hit()`.
- `godot/actors/fighter.gd` — reads the sim points, then calls `wobbler.overlay(dt)`; routes `lean` hits.
- `godot/autoload/settings.gd` — `wobble_rig` key.
- `npm run test:godot-ragdoll` (`godot/tests/ragdoll_test.gd`): classic vs ragdoll gameplay points bit-identical,
  finite/bounded pose, feet planted while idle and never skating, grip on the sim hand, collapse and get-up,
  frame-time budget with 8 fighters.
- `sh tools/shoot-godot-ragdoll.sh [classic]` renders `docs/style/godot-ragdoll-*.png`.
