# Body-part damage

Where a hit lands changes its damage. Godot only for now; the web game still has just the headshot bonus.

## Table (`shared/damage.json`, copied to `godot/data/` by `node tools/sync-shared.js`)

| Part | `zones` (offline) | `classic` (web / online) |
| --- | --- | --- |
| head | weapon's own head bonus: guns `headMul` or x2 (+100%), knives and arrows x1.8 (+80%); melee x1.5 (+50%, table) | same weapon bonus; melee never headshots |
| torso | x1.0 (0%) | x1.0 |
| arms | x0.85 (-15%) | x1.0 |
| legs | x0.75 (-25%) | x1.0 |

Splash (rockets, grenades), the flamethrower and the Spring Glove hit the whole body: no part, no multiplier.

## How the part is decided (`Combat.body_part`)

The hit spheres are unchanged (head 0.4, chest 0.62, legs 0.5; x1.5 for giants). The struck point is: the ray hit point for guns (per pellet; a volley is labelled with the head if any pellet hit it, else the part that took most damage), the projectile position for knives and arrows, the bat sample that touched for melee (the chest for Cyclone body contact). Then:

1. the head sphere was hit -> **head** (exactly the old head flag);
2. point lower than `chest - legsBelow` (0.45) -> **legs**;
3. further than `armSide` (0.34) from the chest centre along the victim's right axis (it turns with `yaw`) -> **arms**;
4. otherwise **torso**.

The multiplier is applied to the weapon damage before `Combat.hit()`; class, rage, shield and mode modifiers apply on top as before.

## Feedback

`dmg_number` events carry `part` and `pct` (rounded bonus %). The world colours and sizes the number by part (head red and big, torso yellow, arms blue, legs grey) and adds a second line such as `+50%` / `-25%`. The `hit` event carries the part and the struck point, where the world pops a small puff in the part's colour.

## Rules and net compatibility

- `Combat.damage_rule`: `"classic"` (default of a bare `Combat`, used by the JS parity tests) or `"zones"` (set by `MatchSim` for offline matches).
- `Combat.zones_active()` is false whenever `net_started`, unless `Combat.net_zones` is set: web clients compute their own shots with the classic rule and the shooter decides the damage it sends in `h`, so mixing rules would make the same shot hurt differently depending on who fired it. Turn `net_zones` on only when every client (including the web game) reads `shared/damage.json`.
- With `classic` every non-head multiplier is exactly 1.0 and the head value is the old one, so damage is bit-identical to the web game (`npm run test:godot-combat` stays green).

## Tests

`npm run test:godot-damage` (`godot/tests/damage_test.gd`): zone geometry (incl. turned and giant victims), every part on hitscan, a `headMul` gun, knife, arrow and melee under both rules, splash without a part, and the online fallback.
