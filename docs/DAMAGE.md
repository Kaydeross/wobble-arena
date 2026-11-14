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

## Aim modes (docs/AIM.md)

Settings › Gameplay › Aim mode (`aim_mode`) has two modes: **Normal** (default, aim assist, shared damage) and
**Advanced** (no aim assist, the local player's own hits deal **+25%**). The bonus is a final multiplier in
`Combat.hit` (`Combat.ADVANCED_DAMAGE` 1.25) and is **offline only**: not online, not for bots, not on ghost-relayed
hits, never on the web game, so cross-play damage stays identical. See [AIM.md](AIM.md) for the assist rules and the
full gate.

## Rules and net compatibility

- `Combat.damage_rule`: `"classic"` (default of a bare `Combat`, used by the JS parity tests) or `"zones"` (set by `MatchSim` for offline matches).
- `Combat.zones_active()` is false whenever `net_started`, unless `Combat.net_zones` is set: web clients compute their own shots with the classic rule and the shooter decides the damage it sends in `h`, so mixing rules would make the same shot hurt differently depending on who fired it. Turn `net_zones` on only when every client (including the web game) reads `shared/damage.json`.
- With `classic` every non-head multiplier is exactly 1.0 and the head value is the old one, so damage is bit-identical to the web game (`npm run test:godot-combat` stays green).

## Tests

`npm run test:godot-damage` (`godot/tests/damage_test.gd`): zone geometry (incl. turned and giant victims), every part on hitscan, a `headMul` gun, knife, arrow and melee under both rules, splash without a part, and the online fallback.

The balance overlay's numbers and rules are checked by `npm run test:godot-arcade` (`godot/tests/arcade_test.gd`, "balance
overlay"): the tuned flame/blower values versus the shared ones, the flame contact cap (a 60-tick stream cannot carry a
stunned target, one contact adds at most `maxForce` m/s, further ticks add nothing and a new contact after 0.4 s pushes
again) and the blower's per-puff damage (shared blower still does none). `npm run test:godot-gunfeel` covers the rest of
the overlay.

## Balance and cooldowns

Godot only, and parity-neutral: `shared/*.json` and `godot/data/weapons.json` are untouched. `godot/data/extra/weapon_tuning.json` is an overlay that `MatchSim._init` merges (`Combat.apply_tuning`) next to `damage_rule = "zones"`. It is used only while `Combat.tuning_active()`, which is the same gate as the zones table (`zones_active()`): offline matches, or online with `net_zones`. A bare `Combat` (the JS parity tests, `combat_test`) and any match on the classic rule (`bots_parity_test`) see the shared numbers. Online, web peers keep the old numbers too; damage is computed by the attacker, so a Godot player online also uses the web numbers until `net_zones` is turned on.

### Tuning table (overlay vs shared)

| Weapon | Field | Shared | Tuned | Why |
| --- | --- | --- | --- | --- |
| Mammoth Pistol | `headMul` | 15.33 (230 head) | 8 (120 head; 144 for a Bruiser) | headshot was a one-shot at 200 HP |
| | `cooldown` | 0.9 s | 1.4 s | |
| | `swapCd` | - | 0.45 s | |
| Meteor Launcher | `cooldown` / `ammo` | 2 s / 3 | 3.2 s / 2 | strongest splash in the game |
| | `burst` / `swapCd` | - | {n 1, regen 6 s} / 0.6 s | |
| Rocket Launcher | `cooldown` / `ammo` | 1.25 s / 4 | 1.8 s / 3 | |
| | `burst` / `swapCd` | - | {n 2, regen 5 s} / 0.45 s | |
| Grenade Launcher | `cooldown` / `ammo` | 0.85 s / 6 | 1.15 s / 4 | |
| | `burst` / `swapCd` | - | {n 3, regen 4 s} / 0.35 s | |
| Cluster Launcher | `cooldown` / `ammo` | 1.1 s / 4 | 1.5 s / 3 | |
| | `burst` / `swapCd` | - | {n 2, regen 4.5 s} / 0.35 s | |
| Minigun | `force` / `maxForce` | 2 / 2.6 | 1.4 / 1.8 | a held stream pushed people off ledges |
| Snowball Cannon | `force` | 30 | 24 | |
| Giant Mallet | `force` / `topple` | 30 / 0.85 | 26 / 0.75 | |
| Flamethrower | `force` / `maxForce` | 1.2 / 1.6 | 0.6 / 1.2 | per-tick push; a stream pinned whoever could not walk against it |
| Air Blower | `dmg` | - (no damage) | 2.5 per puff | it was not a weapon: only a push |
| crates | Meteor weight (`drops.json` base) | 1.4 | 0.6 | `drops` in the overlay, read by `Pickups.pick_crate_key` |

### Flamethrower knockback (overlay only)

A flame-style weapon (`flame`, and the Construction's Angle Grinder) hits on every damage tick (0.06 s). The shared
numbers add `force` 1.2 to the target's velocity on every tick: 16.7 pushes a second, i.e. a constant ~6.4 m/s² shove
that adds up faster than a stunned target (12 % of its walk accel) can walk it off.

The overlay lowers the per-tick push to `force` 0.6 and makes `maxForce` the **total knockback velocity one contact may
add to a target**: `Combat.hit` keeps a per-victim contact budget (`Combat.flame_push`) and each flame hit spends its
push from it, so once a stream has added `maxForce` 1.2 m/s to a target the rest of that contact adds nothing. A new
contact (and a fresh 1.2 m/s) starts after `Combat.FLAME_RESET` 0.4 s with the flame off that target; `Combat.place_at`
clears it on a new life. The first ticks still push (0.19 m/s each) but no amount of held fire can carry a target: even a
stunned target with no walk input stays put (verified in `arcade_test.gd`: the shared numbers carry it > 3 m in a 3.6 s
stream, the tuned stream < 1 m). Everything is gated on `Combat.tuning_active()`; the web game and the parity tests keep
the shared numbers and never run the contact budget.

### Air Blower damage (overlay only)

The `blower` type had no `dmg` at all: its `blower_tick` only pushes, stuns and drains. The overlay adds `dmg` 2.5 and
`Weapons.blower_tick` applies it through `Combat.hit` **once per puff** (the weapon's 0.06 s `cooldown`, not once per
120 Hz physics step), so it is a real but low-DPS weapon: 2.5 / 0.06 s ≈ 42 damage per second, below every automatic gun
(AK-47 tuned ≈ 60, SMG ≈ 62, Minigun ≈ 71, Uzi ≈ 57), and a full 100-ammo tank (3.6 s of jet) is ≈ 150 damage. Its job
stays control (the strong push and stun); the damage just means the jet is no longer free to stand in. The web game /
parity tests keep the no-damage blower (`tuning_active()` gate).

### Optional weapon fields (overlay only)

- `burst {n, regen}`: a charge pool per weapon key (cloned from the ninja dash charges). Each shot spends a charge (`Combat.use_ammo` -> `Skills.burst_spend`); with no charge left `Weapons.try_fire` / `gun_tick` refuse to fire; one charge comes back every `regen` s. The pool survives weapon swaps (no refill by swapping) and resets on a new life. The HUD mode line shows `Shots ◆◆◇` while such a weapon is held (`ModeRules.hud_text`).
- `swapCd`: draw time. `Combat.equip_slot` sets `cool = max(cool, swapCd)` when this weapon comes into the hand, so fire-swap-fire chains between heavy weapons are gone.

### Gun feel (overlay only)

Same gate as above (`Combat.tuning_active()`), so web peers and parity tests are untouched. `npm run test:godot-gunfeel`.

- **Net Gun**: `trap` 4.5 s -> 2.5 s.
- **Scatter**: the player's gun assist is `Weapons.PLAYER_ASSIST` (0.8) instead of a perfect lock; bots keep their own `assist`. Gun `spread` is widened and damage / `force` / `maxForce` lowered (AK, SMG, Uzis, Minigun, Shotgun, Revolver, Sniper, Mammoth).
- **Bloom**: `bloomAdd` per shot on top of `spread`, capped at `bloomMax`, cooling at `bloomDecay` per second (default 0.05). Sustained fire sprays; tap-firing stays accurate.
- **Arm wobble**: weapons with `wobble` get random arm nudges every 0.12-0.35 s (`Weapons.climb_tick`), stronger while moving and halved when aiming. The visible arm jerks (`push_arm`) and a small part (`WOB_AIM`) reaches the shot direction.
- **Stacked knockback**: each gun hit adds `GUN_KICK_STEP` to the victim's `gun_kick`; the next push is divided by `1 + GUN_KICK_DAMP * gun_kick`; it recovers at `GUN_KICK_RECOVER` per second. A stream of bullets no longer pins someone against a wall; damage is unchanged by the stack.

### Skills (`godot/logic/skills.gd`)

Per-fighter timers `FighterState.skill_n` (charges, a missing id = full) and `skill_cd` (seconds to the next charge), ticked by `Combat.timers` (`Skills.tick`), cleared by `Combat.place_at`. Nothing in `Skills` draws a random number.

**Air recovery ("boing burst")**: the `recover` tap (touch: the contextual button turns into RECOVER while airborne within 3 s of a hit (plain jumps keep RELOAD) when no dash weapon is held, with a ring while the charge comes back; keyboard X; the dash key / pad left shoulder also recovers in the air without dash gear). Allowed when airborne, alive, not knocked down, not trapped, not on a ladder, at least 0.2 s after the last hit, with the charge (1; back on landing or after 6 s), and not below `ring_out_y * 0.25` (a ledge knock can be saved, a free fall cannot). Effect: stun cleared, the knock's horizontal speed x0.3 plus a 13 m/s burst toward the stick (or the arena centre with no stick), `vy = max(vy, 8)`, 0.5 s of boosted air control (`FighterState.recover_air_t`, read by `FighterPhysics.step`: air acceleration 22 toward up to 12 m/s, momentum kept with no stick; default 0 keeps the physics parity), 0.2 s invulnerability, dash puff + swing sound. Bots do not use it. No protocol change: the state snapshot already carries the velocity.

Tests: `npm run test:godot-skills` (`godot/tests/skills_test.gd`).
