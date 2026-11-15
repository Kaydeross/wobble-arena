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

The hit spheres are the classic ones (head 0.4, chest 0.62, legs 0.5; x1.5 for giants) unless the balance overlay is in
use, where a class scales them ("Tuned hitboxes" below). The struck point is: the ray hit point for guns (per pellet; a
volley is labelled with the head if any pellet hit it, else the part that took most damage), the projectile position for
knives and arrows, the bat sample that touched for melee (the chest for Cyclone body contact). Then:

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
the overlay. `npm run test:godot-skills` checks the bow ammo (8 volleys; the shared pickup keeps 12), the net trap
(2.0 s) and Uzi damage (3.8), plus the tuned hit spheres: the clamps, the giant x1.5 on top, the exact classic values for
a bare `FighterState` / classic rule / online-without-`net_zones`, and that the flag is re-armed by `place_at`.

## Balance and cooldowns

Godot only, and parity-neutral: `shared/*.json` and `godot/data/weapons.json` are untouched. `godot/data/extra/weapon_tuning.json` is an overlay that `MatchSim._init` merges (`Combat.apply_tuning`) next to `damage_rule = "zones"`. It is used only while `Combat.tuning_active()`, which is the same gate as the zones table (`zones_active()`): offline matches, or online with `net_zones`. A bare `Combat` (the JS parity tests, `combat_test`) and any match on the classic rule (`bots_parity_test`) see the shared numbers. Online, web peers keep the old numbers too; damage is computed by the attacker, so a Godot player online also uses the web numbers until `net_zones` is turned on.

### Tuning table (overlay vs shared)

| Weapon | Field | Shared | Tuned | Why |
| --- | --- | --- | --- | --- |
| Mammoth Pistol | `headMul` | 8 (120 head; 144 for a Bruiser) | 8 (same) | the shared value used to be a 230-damage one-shot; both regimes now use the fair value |
| | `cooldown` | 0.9 s | 1.4 s | |
| | `swapCd` | - | 0.45 s | |
| Meteor Launcher | `cooldown` / `ammo` | 2 s / 3 | 3.2 s / 2 | strongest splash in the game |
| | `burst` / `swapCd` | - | {n 1, regen 4.5 s} / 0.6 s | |
| Rocket Launcher | `cooldown` / `ammo` | 1.25 s / 4 | 1.8 s / 3 | |
| | `burst` / `swapCd` | - | {n 2, regen 3.5 s} / 0.45 s | |
| Grenade Launcher | `cooldown` / `ammo` | 0.85 s / 6 | 1.15 s / 4 | |
| | `burst` / `swapCd` | - | {n 3, regen 3 s} / 0.35 s | |
| Cluster Launcher | `cooldown` / `ammo` | 1.1 s / 4 | 1.5 s / 3 | |
| | `burst` / `swapCd` | - | {n 2, regen 4.5 s} / 0.35 s | |
| Minigun | `force` / `maxForce` | 2 / 2.6 | 1.4 / 1.8 | a held stream pushed people off ledges |
| Snowball Cannon | `force` | 30 | 24 | |
| Giant Mallet | `force` / `topple` | 30 / 0.85 | 26 / 0.75 | |
| Twin Fang Bow | `ammo` (volleys) | 12 | 8 | a pickup was 1152 damage at full draw (12 volleys = 24 arrows x 48); 8 volleys = 768 |
| Net Gun | `trap` | 4.5 s | 2.0 s | the pin was 2.5 s; one ammo still buys a long free-hit window |
| Dual Uzis | `dmg` | 4.4 | 3.8 | a 40-round mag is 152 damage, so one mag K.O.s a 150 HP class (was 3.4 = 136) |
| Flamethrower | `force` / `maxForce` | 1.2 / 1.6 | 0.6 / 1.2 | per-tick push; a stream pinned whoever could not walk against it |
| Air Blower | `dmg` | - (no damage) | 2.8 per puff | it was not a weapon: only a push; a full tank can now finish a 150 HP class |
| crates | Meteor weight (`drops.json` base) | 1.4 | 0.6 | `drops` in the overlay, read by `Pickups.pick_crate_key` |

Shared (web, online and offline) balance also changed in this pass: the Mammoth Pistol's `headMul` is 8 and the Giant Mallet's `ammo` is 6, both edited in the web source and re-exported to `shared/weapons.json`. See [BALANCE_FIXES.md](BALANCE_FIXES.md).

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

The `blower` type had no `dmg` at all: its `blower_tick` only pushes, stuns and drains. The overlay adds `dmg` 2.8 and
`Weapons.blower_tick` applies it through `Combat.hit` **once per puff** (the weapon's 0.06 s `cooldown`, not once per
120 Hz physics step), so it is a real but low-DPS weapon: 2.8 / 0.06 s ≈ 47 damage per second, below every automatic gun
(AK-47 tuned ≈ 60, SMG ≈ 62, Minigun ≈ 71, Uzi ≈ 57), and a full 100-ammo tank (3.6 s of jet) is ≈ 167 damage, enough to K.O. a 150 HP class. Its job
stays control (the strong push and stun); the damage just means the jet is no longer free to stand in. The web game /
parity tests keep the no-damage blower (`tuning_active()` gate).

### Optional weapon fields (overlay only)

- `burst {n, regen}`: a charge pool per weapon key (cloned from the ninja dash charges). Each shot spends a charge (`Combat.use_ammo` -> `Skills.burst_spend`); with no charge left `Weapons.try_fire` / `gun_tick` refuse to fire; one charge comes back every `regen` s. The pool survives weapon swaps (no refill by swapping) and resets on a new life. The HUD mode line shows `Shots ◆◆◇` while such a weapon is held (`ModeRules.hud_text`).
- `swapCd`: draw time. `Combat.equip_slot` sets `cool = max(cool, swapCd)` when this weapon comes into the hand, so fire-swap-fire chains between heavy weapons are gone.

### Gun feel (overlay only)

Same gate as above (`Combat.tuning_active()`), so web peers and parity tests are untouched. `npm run test:godot-gunfeel`.

- **Net Gun**: `trap` 4.5 s -> 2.0 s (2.5 s before Sprint 1.2).
- **Scatter**: the player's gun assist is `Weapons.PLAYER_ASSIST` (0.8) instead of a perfect lock; bots keep their own `assist`. Gun `spread` is widened and damage / `force` / `maxForce` lowered (AK, SMG, Uzis, Minigun, Shotgun, Revolver, Sniper, Mammoth).
- **Bloom**: `bloomAdd` per shot on top of `spread`, capped at `bloomMax`, cooling at `bloomDecay` per second (default 0.05). Sustained fire sprays; tap-firing stays accurate.
- **Arm wobble**: weapons with `wobble` get random arm nudges every 0.12-0.35 s (`Weapons.climb_tick`), stronger while moving and halved when aiming. The visible arm jerks (`push_arm`) and a small part (`WOB_AIM`) reaches the shot direction.
- **Stacked knockback**: each gun hit adds `GUN_KICK_STEP` to the victim's `gun_kick`; the next push is divided by `1 + GUN_KICK_DAMP * gun_kick`; it recovers at `GUN_KICK_RECOVER` per second. A stream of bullets no longer pins someone against a wall; damage is unchanged by the stack.

### Tuned hitboxes (overlay only)

Same gate (`Combat.tuning_active()`): the hit spheres follow the class from `shared/classes.json` instead of being the same
for everyone. `FighterState.set_class` stores the class `head` and `size` multipliers (`cls_head`, `cls_size`), and
`FighterState.spheres` scales them:

| sphere | classic | tuned |
| --- | --- | --- |
| head | 0.4 | `0.4 * clampf(cls_head, 0.85, 1.25)` |
| chest | 0.62 | `0.62 * clampf(cls_size, 0.88, 1.15)` |
| legs | 0.5 | `0.5 * clampf(cls_size, 0.88, 1.15)` |

The Chaos Giant `x1.5` multiplier still applies on top of the class scale. So a Scamp (`head` 1.4, `size` 0.86) has a
0.5 head (clamped to +25 %) and 0.5456 / 0.44 body spheres, a Bulwark (`tank`: `head` 0.85, `size` 1.16) a 0.34 head
and 0.713 / 0.575 body, a Bruiser (`head` 0.92, `size` 1.12) 0.368 / 0.6944 / 0.56, and a Wobbler stays exactly
0.4 / 0.62 / 0.5.

`FighterState` never reads the `Combat` class itself (that would be a static dependency cycle): it carries a plain
`tuned` flag that the simulation writes from `Combat.tuning_active()` when a fighter is created (`MatchSim._new_fighter`)
and on every `Combat.place_at` (respawn / new life, which also re-arms arcade enemies and revives). Default false, so a
bare `FighterState` and every parity path (the JS `bots_parity_test`, `combat_test`) keep the exact classic spheres—
the untuned tables are the same floats as before. The flag is a per-life snapshot: a match never flips the gate mid-life,
and Arcade runs (offline, tuned) arm their crew/enemies through `add_fighter` / `place_at`.

### Skills (`godot/logic/skills.gd`)

Per-fighter timers `FighterState.skill_n` (charges, a missing id = full) and `skill_cd` (seconds to the next charge), ticked by `Combat.timers` (`Skills.tick`), cleared by `Combat.place_at`. Nothing in `Skills` draws a random number.

**Air recovery ("boing burst")**: the `recover` tap (touch: the contextual button turns into RECOVER while airborne within 3 s of a hit (plain jumps keep RELOAD) when no dash weapon is held, with a ring while the charge comes back; keyboard X; the dash key / pad left shoulder also recovers in the air without dash gear). Allowed when airborne, alive, not knocked down, not trapped, not on a ladder, at least 0.2 s after the last hit, with the charge (1; back on landing or after 6 s), and not below `ring_out_y * 0.25` (a ledge knock can be saved, a free fall cannot). Effect: stun cleared, the knock's horizontal speed x0.3 plus a 13 m/s burst toward the stick (or the arena centre with no stick), `vy = max(vy, 8)`, 0.5 s of boosted air control (`FighterState.recover_air_t`, read by `FighterPhysics.step`: air acceleration 22 toward up to 12 m/s, momentum kept with no stick; default 0 keeps the physics parity), 0.2 s invulnerability, dash puff + swing sound. Bots do not use it. No protocol change: the state snapshot already carries the velocity.

Tests: `npm run test:godot-skills` (`godot/tests/skills_test.gd`).

## Teammate carry/throw (Fastball Special)

Post-v0.4.0 Sprint 2.2, Godot only: in **TEAM modes** (`t2`, `t3`, `t4`, `tdm`, `ctf`) and in **two-seat Arcade co-op** a
player can hoist a teammate overhead and throw them.

- **Gate:** `Combat.carry_active()` = `tuning_active()` **and** (a `CARRY_MODES` team mode with `Combat.teams != 0`, or
  `Combat.arcade_coop`, the flag `ArcadeManager._apply_friendly_fire` writes for a two-seat run). FFA, classic, solo
  Arcade, duel/chaos and every match on the shared web numbers never carry, so `npm run test:godot-bots` /
  `test:godot-physics` stay bit-identical. Online co-op therefore only lights up when `Combat.net_zones` is on (the same
  `tuning_active()` gate as the rest of this file); a remote player's ghost is never a carry candidate (moving it would
  need a protocol change, out of scope).
- **Lift:** the `shove` key within `CARRY_RANGE` 1.4 m (feet distance) of a teammate while **empty-handed**. Empty-handed
  is the default Spatula only (`FighterState.slot < 0`, the same condition quick melee reads), so any picked-up weapon
  refuses the lift. A living teammate, or a **downed Arcade co-op seat** (the seat system's `dead`/`elim` marker), can be
  hoisted. The normal shove is suppressed and the lift takes the 0.9 s shove cooldown.
- **Carry:** `FighterState.carrying` / `carried_by`. The body is pinned at `CARRY_HOLD_HEIGHT` 2.3 m above the carrier's
  feet, following its facing (the Net Gun-trap pinning pattern: `Combat.carry_tick` writes the position and zeroes the
  velocity after physics, once per fixed step), and it cannot act (its `PlayerControl` / `BotBrain` step returns). The
  carrier walks at `CARRY_SPEED_MUL` 0.85 of its walk speed and no weapon fires.
- **Throw:** the `fire` key launches the body forward along the carrier's facing at `THROW_SPEED` 18 m/s plus `THROW_UP`
  6 m/s of arc (`vx = sin(face_yaw) * 18`, `vz = cos(face_yaw) * 18`, `vy = 6`).
  - **Living teammate — body-slam:** the FIRST enemy the flying body touches takes `SLAM_DMG` 35 damage / `SLAM_FORCE`
    20 knockback; the carrier is the attacker (K.O. credit, the existing hit Fx shake/hitstop), the "FASTBALL SPECIAL!"
    toast (5 languages) is emitted, and the thrown fighter takes no damage from its own slam.
  - **Downed Arcade co-op seat — limp body:** a thrown downed body never slams. When it lands on the floor (`grounded`
    on a solid) it calls `ArcadeManager.fastball_revive(f, 2.0)` through the sim meta `"arcade_run"` (has_method: no
    static DLC dependency from `Combat`), shaving `CARRY_REVIVE_SHAVE` 2.0 s off that seat's auto-revive countdown
    (`ArcadeManager.seat_down`; the HUD already counts `seat_revive_left()`, so the shorter time shows at once). The
    landing must be on a solid — a body thrown into the void pays nothing and the seat revives on its normal timer.
- **Reset:** `Combat.place_at` (respawn, Arcade revive, match start) cuts the carry link on both sides and forgets a throw
  in flight, so a fresh life never inherits one; `Combat.dispose` drops the references at match end.
- **Determinism:** no branch here draws a random number (`test:godot-skills` compares `CombatRng.state` around the lift,
  the throw and the tick); the Arcade side keeps using its own scripted RNG.

Tests: `npm run test:godot-skills` (`_carry`: gate off in FFA/classic/tuning-off and for enemies/non-empty hands, the
1.4 m range, 0.85x carrier speed, the pin, the exact launch vector, the 35/20 slam to the first enemy only, no
self-damage, the toast, the limp body, the `place_at` reset and no RNG draw) and `npm run test:godot-arcade` (`_fastball`:
the offline `arcade_run` meta, solo Arcade off, a downed-seat throw = -2.0 s round trip on the revive countdown, and the
living body-slam 35/20 + toast against the stage crew).

## Wobble Reactions (overlay only)

Post-v0.4.0 Sprint 2.3, Godot only, **every branch gated on `Combat.tuning_active()`** (the same overlay gate as the
sections above): the web game, online matches without `net_zones` and the JS parity suites never reach any of it. The
rules live in `Combat` (`bowl_slides`, `hazard_source`), `Weapons` (`deflect_near` / `deflect_ray`) and the Arcade
`StageEvents` (the deflectable crate registration). Nothing in the feature draws a random number: the "reaction" event
carries the presentation, which the `FxSystem` turns into pooled sparks/dust/rings with its own RNG.

### Human Bowling Ball

A fighter pinned by a Net Gun trap (`trap_t > 0`) that takes a **heavy melee swing** is released from the net and slides
across the floor as a bowling ball.

- **Heavy** = the weapon **table's** `force >= 16` (`Combat.HEAVY_FORCE`, read before the class / slam / cyclone
  multipliers, exactly the value `melee_sweep` multiplies). Tuned tables: Bat 17, Giant Mallet 26, Hammer 16, Pipe
  Wrench 24; the Spatula 13, Katana 11 and Trident 9 never launch.
- The trap is released for real (`TrapNet.victims.erase`, `trap_net = null`, `trap_t = 0`; a net holding other fighters
  keeps them) and the body's post-hit knockback is replaced by a flat slide: `vx = dx * BOWL_SPEED 26`, `vz = dz * 26`,
  `vy = 0`, `grounded = true`, `stun = 0`. Horizontal launch direction = the swing's horizontal knockback direction
  (the same `d` the melee hit used). The slide lasts `BOWL_TIME` 0.9 s and re-asserts 26 m/s on every fixed step
  (`Combat.timers` -> `_bowl_tick`, so it is inside `MatchSim.step` and render-rate independent); physics friction after
  the re-assert is the only slowdown.
- **Bowling pins:** every other fighter inside `BOWL_PIN_R` 1.1 m horizontally (and 1.6 m vertically) when the body
  reaches it takes `BOWL_PIN_DMG` 30 damage / `BOWL_PIN_FORCE` 18 force once per launch. `hit()` is always called with
  the sliding fighter as the **attacker** and the pin as the victim, so the bowler is never hurt by its own pins (and
  `Combat.is_friend` / the Arcade seat rule still decide friendly pins: a friend takes nothing).
- **STRIKE!** (translated): one toast per launch, emitted the first time a pin's hit really applies.
- The slide ends on expiry, death, a knockdown (`down_t > 0`) or a fresh net; `Combat.place_at` clears it on a new life
  and `Combat.dispose` at match end.

### Mid-Air Crate Redirect

A **melee swing** or a **high-force shot** that touches a falling `load_test` hazard crate (an Arcade stage event owned
by `StageEvents`) or an **explosive projectile in flight** (the rockets / grenades lists in `Weapons`) redirects it:

- melee: the weapon line (`now`/`prev` + the halfway samples `melee_sweep` already tests fighters with) against the
  crate's `r = 1.1` + the weapon's `thick` sphere, and against a rocket/grenade's `DEFLECT_PROJ_R` 0.45 + `thick`;
- shot: the pellet ray against the same spheres. **High-force shot** = the weapon table's `maxForce >= 8`
  (`Weapons.SHOT_DEFLECT_FORCE`): tuned Shotgun 9, Sniper 8 and Mammoth Pistol 8 qualify; AK/SMG/Uzi/Minigun/Revolver/
  Flamethrower do not. The Spring Glove's punch path is deliberately not wired.
- The redirect is horizontal only: a projectile keeps its horizontal speed magnitude and only changes heading
  (`vx,vz = dir * |vx,vz|`, `vy` untouched); a crate gets `CRATE_DEFLECT_SPEED` 8 m/s horizontally while its scripted
  fall (and therefore `_land`, still host-side and unchanged) continues, so it lands where it was deflected. Melee
  redirects one object per call; a shot's tracer stops on the object it swatted (no damage, no damage multiplication).
- `StageEvents.deflectables()` / `deflect_crate(id, dx, dz)` are registered on `Combat.hazard_source` (duck-typed weak
  reference, no DLC import from logic; cleared by `StageEvents.finish`). The warning ring and the host's `am.ev`
  descriptors follow the drifted x/z.

Both reactions are covered by `npm run test:godot-skills` (`_reactions`: trap release + 26 m/s, 30/18 pins, no
self-damage, one STRIKE toast, tuning-off / trap-0 / light-weapon gates, crate drift and single landing, rocket/grenade
redirect, high-force shot vs AK) and `npm run test:godot-arcade` (crate registration, drift, am.ev spot, finish clears it).

## Charged heavy melee and swing archetypes (overlay only)

Post-v0.4.0 Sprint 3.1, Godot only. Both halves are gated on **`Combat.tuning_active()`** (the same overlay gate as the
sections above) and the charge is additionally **offline only** (`not Combat.net_started`): the peer replay message `sw`
carries no heavy bit, so an online client would replay a normal swing while the attacker's game computed a heavy hit
(and its local parry check would disagree) — charging is disabled online and no protocol change was made. The web game,
the JS parity suites (`combat_test`, `bots_parity_test`, `test:godot-physics`) never see any of it, and nothing here
draws a random number (`CombatRng.state` is unchanged across charge, heavy swing and hit).

### Heavy Swing (hold FIRE 0.45 s)

- **Charge:** `PlayerControl.think` (a non-throwable melee weapon in hand) grows `FighterState.charge_t` while the raw
  fire input is held; at `Combat.HEAVY_CHARGE` 0.45 s the Heavy Swing **auto-releases while FIRE is still held**. A
  release before 0.45 s is the normal light swing (a quick tap), so tapping is unchanged apart from moving the light
  swing from press to release. Holding on after a swing + cooldown starts a new charge, so a held button chains heavies.
- **Cancels:** being hit (`FighterState.flash`), a stun, a weapon swap (`Combat.set_weapon`), death/knockdown, being
  carried (Fastball) or the Net Gun trap cancels the charge; release paths clear `charge_t` and `melee_begin` re-writes `heavy` every swing, so the flag
  never leaks into the next swing. The trident keeps its tap-jab/hold-throw (`Weapons.trident_tick`), and Kids mode's
  auto-fire keeps tapping (the assist `fire` is not the raw hold), so it gets no free heavies.
- **Effect** (`Combat.melee_sweep`, after the slam/cyclone factors and before the body-part multiplier):
  `dmg *= Combat.HEAVY_DMG_MUL 1.45`, `force *= Combat.HEAVY_FORCE_MUL 1.5`. The swing also **breaks a parry**: the
  victim's `parry_t` is consumed and a `parry_break` event is emitted instead of `try_parry` cancelling the swing
  (`try_parry` itself refuses a `heavy` attacker). A `heavy_swing` event is the gold-rim presentation hook for the
  visual layer (the HUD draws its own feedback, see below); neither event draws a number.
- **HUD** (`ui/hud.gd`, no new text so no i18n): the crosshair gets a gold arc (`UiTheme.ACCENT`) filling with
  `Combat.charge_frac(charge_t)` (= `clamp(charge_t / 0.45, 0, 1)`, a full white ring near the top), and the first
  `MatchHud.HEAVY_FLASH_TIME` 0.18 s of a Heavy Swing flash a gold rim around the screen edge. It is all drawn in the
  existing crosshair `_draw_cross` pass (no extra node or draw pass; LOW tier unaffected).
- **Bots** keep calling `Combat.melee_begin` directly (`BotBrain` unchanged): they always tap, never charge, and draw
  no new random numbers.

### Swing archetypes (`weapon_tuning.json`)

Melee weapons name an archetype with `"swingStyle"`; a top-level `"swingStyles"` table holds the parameters, and
`Combat.apply_tuning` resolves them into the tuned weapon's `"style"` dictionary once, so a data edit changes the swing
with no code edit (`Combat.wdata(key)["swingStyleDef"]`; a distinct key, because shared weapon records use `style`
for guns such as "punch" / "flame"). A per-weapon `"swingStyleDef": {...}` overrides single parameters. The
parameters and their per-style values:

| Style | Weapons | `arc` (rad) | `lift` | `tipMul` | `hitStart` | `hitEnd` |
| --- | --- | --- | --- | --- | --- | --- |
| `cleave` | bat, spatula, spiritlevel | 3.4 | -0.02 | 1.0 | 0.04 | 1.2 |
| `crush` | mallet, pipewrench, hammer | 2.2 | -0.28 | 0.92 | 0.10 | 0.85 |
| `thrust` | drill, katana, trident | 0.8 | 0.04 | 1.15 | 0.18 | 0.60 |
| `whip` | tapemeasure, wirewhip | 4.8 | 0.10 | 1.25 | 0.28 | 1.2 |

- `melee_tick`: the base swing pose is `a = lerp(arc/2, -arc/2, t)` with the arm vertical component `lift` (cleave's
  values are exactly the old literals 1.7 / -0.02). Slam/cyclone/stab poses keep their own shape.
- `melee_sweep`: `tipMul` multiplies the weapon `tip` (so `cleave` stays 1.0, a whip reaches 25 % further) and
  `hitStart`/`hitEnd` are the normalized swing-time window that may hit (a stab keeps at least 0.3; crush ends early,
  a whip cracks late).
- **No style = the shared/web swing**: `wdata` returns the shared weapon (which has no `swingStyleDef`), the code falls back to
  the exact old literals, and the parity/Wobble Reactions/charge gates all stay as before. A tuned melee weapon's only
  overlay difference beyond the styles is whatever its own entry lists.

Tests: `npm run test:godot-skills` (`_charged_melee`: the archetype data per weapon, the style arc/lift/tip/window read
through `wdata`, the 0.45 s auto-release boundary and tap/early-release light swing, 1.45x / 1.5x on scripted hits, the
parry smash, the online `net_started` and tuning-off paths, the cancel paths, bots never charging, no RNG draw and a
data edit changing the arc).

## Elemental and physics statuses (overlay only)

Post-v0.4.0 Sprint 3.2, Godot only, **every branch gated on `Combat.tuning_active()`** (the same overlay gate as the
sections above): the web game, online matches without `net_zones` and the JS parity suites never reach any of it.
Nothing in the feature draws a random number, so bot decisions and the combat/parity traces are unchanged; the spark
burst is presentation, emitted as a `"spark"` event and drawn by the `FxSystem` with its own RNG.

The **status table is overlay data, not code**: a `godot/data/extra/weapon_tuning.json` weapon entry may carry one of
the sub-dictionaries below, and `Combat.apply_status(v, w)` reads them (`is-Dictionary` guarded) from the weapon data
`wdata()` / the ball's resolved `w`) for the fighter that weapon just hit. The names never collide with a gun's String
`style` or a melee `swingStyleDef`. `Combat` holds the same numbers as fallback constants (`CHILL_TIME/SPEED/TRACTION`,
`SHOCK_TIME`, `HEAVY_TIME/GRAV/JUMP`) for an entry that omits a value.

| weapon (key) | type | status | values |
| --- | --- | --- | --- |
| Snowball Cannon (`snow`) | ball | `chill` | `time` 3.0 s, `speed` 0.68, `traction` 0.3 |
| Live Wire (`wirewhip`) | melee | `shock` | `time` 0.35 s |
| Cement Bucket (`cementbucket`) | ball | `heavy` | `time` 4.0 s, `grav` 1.4, `jump` 0.65 |

The **Angle Grinder** (`anglegrinder`) is a `type: "gun"`, `style: "flame"` weapon: it does not share the Live Wire's
melee hit path, so it has no shock entry (checked, deliberately not forced).

Application happens at the weapon hit path, once per **applied** hit (never per tick); a parried or invulnerable hit,
a dead target and the tapless charged-melee cancel paths never tag anyone:

- melee: `Combat.melee_sweep`, in the `if hit(...)["applied"]:` block (`_swing` `swing_hit` makes one hit per target);
- ball: `Weapons.step_balls`, after the roll hit, guarded by the same hit result (`b.hit_set` makes one hit per ball).

**Chill** (`snow`, 3.0 s): `FighterPhysics.step` multiplies the target move speed by `chill_speed` (0.68x: 7.5 -> 5.1
m/s on a Wobbler) and reuses the existing ice-grip machinery for the ground traction: when grounded and not
incapacitated the acceleration is the ice formula (`32` steering, `20 * 0.05^ice_setting` for the glide) times
`chill_traction` 0.3, i.e. ~9.6 m/s2 steering and ~1.0 m/s2 glide stopping versus the normal 40 m/s2. Air control is
untouched. A second hit refreshes the timer to 3.0 s (`maxf`) and keeps exactly one 0.68x multiplier: no stacking.

**Shock** (`wirewhip`, 0.35 s): a short hit-stun interrupt (`stun = maxf(stun, 0.35)`; the weapon's own force stagger may
already be longer) plus `"spark"`. It cancels whatever the victim was winding up: melee swing (`swing`, `bat_valid`,
`slam`/`stab`/`cyclone`/`assist_on`), kick, throw wind-up, trident charge / bow draw (`t_charge`, `draw`, `nocked`) and
the charged Heavy Swing (`charge_t`, `heavy`). Pressing again starts a fresh input (no replay). No damage over time.

**Heavy** (`cementbucket`, 4.0 s): `FighterPhysics.step` multiplies the gravity (`GRAV * grav_scale * heavy_grav`, i.e.
1.4x) and the jump impulse (`(7.4 if grav_scale < 0.3 else 9.2) * jump_mul * heavy_jump`, i.e. 0.65x). Walk speed and
air control are unchanged.

Timers are counted down in `Combat.timers` (clamped at 0) and `Combat.place_at` (and so respawn) clears all three
statuses; a fresh life never inherits them.

Tests: `npm run test:godot-skills` (`_statuses` + `_status_physics`: the overlay table and its exact 3.0/0.35/4.0
values, applies-only-on-the-matching-weapon though the real melee and `Weapons.Ball` paths, 0.68x speed and reduced
traction, 1.4x gravity / 0.65x jump with the walk speed unchanged, refresh-not-stack, the shock interrupt list,
`place_at` clearing, the `spark` event, tuning-off no-op and no combat RNG draw) plus the existing
`test:godot-physics`, `test:godot-combat`, `test:godot-damage`, `test:godot-bots` and `test:godot-fx` parity runs.

## Class signature skills (overlay only)

Post-v0.4.0 Sprint 3.3, Godot only, **every entry point gated on `Combat.tuning_active()`** (the same overlay gate as the
sections above): the web game, online matches without `net_zones` and the JS parity suites never reach any of it.
Nothing in the feature draws a combat random number: the hits go through the shared `Combat.hit()` (whose only draw is
the normal K.O. fall side, exactly like any attack) and the Seismic Slam's knockdown uses the deterministic
`Combat.topple_flat()` (`combat.rng.state` is asserted unchanged around the casts). The moves live in
`godot/logic/skills.gd` (`SIG_*`), the charge in `FighterState.skill_n` / `skill_cd` under the id `"sig"` (one charge,
`SIGNATURE_CD` 12.0 s, missing = full; `Combat.place_at` -> `Skills.reset` refills it on a fresh life), the short move
windows in `Combat.sig_fx` (cleared by `place_at` and `dispose`). Bots never cast (no `BotBrain` change), so the
bots-reference/parity traces and the JS decisions stay identical.

**Input:** keyboard **B** or pad **D-pad Up** (`PlayerInput`, the `"signature"` tap); touch: the contextual button turns
into SIG while the move is ready and appropriate. Context priority is **DASH > RECOVER > SIG > RELOAD**, so a dash
weapon or an air recovery never loses the button and a gun-wielder only sees RELOAD when the signature skill cannot be
cast. Each class has its own vector icon; a tap while the charge is not back (or after the cast) does nothing (the same
stale-tap guard RECOVER / RELOAD use).

| class id (name) | skill | exact effect |
| --- | --- | --- |
| `wobbler` (Wobbler) | Belly Bounce | everyone within 3.0 m horizontally and 2.0 m vertically takes 10 damage / 15 force away and up (hit direction y 0.55); the caster bounces off the floor (`vy = max(vy, 4.5)`) |
| `bruiser` (Bruiser), `champ`, `rampage` | Seismic Slam | **airborne only**: a straight dive (`vy = -22`, the terminal fall speed); on landing everyone within 3.8 m / 2.5 m vertically takes 18 damage / 22 force plus a deterministic 1.1 s knockdown (`topple_flat`) |
| `kid` (Scamp), `dash` (Zippy) | Vault Flip | 1.5 s speed burst (`spd_t`, x1.4); an opponent within 2.0 m / 2.4 m vertically in the 2 m front half (dot >= 0) takes 6 damage / 10 force downward and the caster springs up (`vy >= 9.5`) |
| `tank` (Bulwark) | Fortress Stance | **ground only**, 1.5 s planted: `Combat.hit` adds no velocity, no stun and no launch (a K.O. hit still kills, just without the launch; the K.O. burst VFX stays), and the window doubles as the tuned parry window (`try_parry`: the next melee hit from the front is cancelled and the attacker staggered; a Heavy Swing breaks that parry but still cannot launch the tank) |
| `alien` (Zorp), `ace` (Ace) | Tac-Reload | needs a firearm with a magazine in hand: the reload is cancelled and the magazine instantly refilled to `min(mag, ammo)` (the same cap a finished reload uses), plus 1.5 s of x1.5 fire rate (`Skills.tick` adds `dt * cls_rate * 0.5` to the cooldown recovery) |
| `ghost` (Boo) | Phase Shift | 0.6 s of invulnerability: attacks, projectiles, the Net Gun's `landNet` (it already skips `invuln` targets) and damaging props pass through; `place_at` clears it with the rest of a fresh life |
| `elder` (Gramps) | none (documented) | the context button stays RELOAD / hidden and the key does nothing |

The class table is total: every shipped class id is in `Skills.SIG_CLASS` or in `Skills.SIG_NONE` (only `elder`), and an
unknown id gets no move. `Skills.sig_block` returns why a cast is refused right now (`off` / `dead` / `down` / `trapped` /
`none` / `charge` / per-move `grounded` / `air` / `gun`), and `Skills.sig_offer` is the touch button's "offer it now"
question (the `Skills.recover_offer` precedent).

**Online:** no protocol change. The self-affecting windows (cooldown, Fortress, Phase, the speed/rate bursts) live on the
owner's client and a remote hit already crosses `Combat.hit`/`net_zones` rules, so the local player's casting behaves the
same; a remote player's signature move is **not** replicated to this client (no skill message exists), so other players
do not see its VFX — a known limitation, out of scope here.

Tests: `npm run test:godot-skills` (`_sig_map`, `_sig_gate_charges`, `_sig_moves`, `_sig_fortress`, `_sig_context`: the
total class table, the 12 s charge shared with `Skills.tick` regen, every move's exact radius/damage/force/duration, the
refusals, the Fortress knockback immunity and K.O.-without-launch, the front parry, Tac-Reload's x1.5 cooldown recovery,
Phase Shift vs `hit()` and a fresh life, no RNG draw, bots never casting, and the touch context offer/priority/tap) plus
`npm run test:godot-touch` (the SIG button's tap-staleness), `test:godot-ui`, `test:godot-bots`, `test:godot-physics`,
`npm run i18n -- --check` and `npm run content:check`.
