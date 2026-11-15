# Balance fixes: the review follow-up

This is the implemented follow-up to [BALANCE_REVIEW.md](BALANCE_REVIEW.md). That document is the read-only snapshot
taken on `claude/balance-review`; it intentionally keeps its original numbers. This page lists what changed, why, and
which review items were deliberately left for a later pass.

Tests: `npm run content:check`, `npm run i18n -- --check`, `npm run test:godot-construction`,
`npm run test:godot-construction-data`, `npm run test:godot-arcade`, `npm run test:godot-skills`,
`npm run test:godot-modes`, `npm run test:godot-ui` and the full CI matrix.

## Classes

| Class | Change | Why |
| --- | --- | --- |
| Champ | `reload` 1.00 -> 1.10 | Champ upgraded every combat and movement stat over Wobbler (230 EHP, 7.80 m/s, 1.08 damage, 1.05 rate, 0.85 knockback taken). A 10 % slower reload is the trade-off: burst DPS is unchanged, sustained gun DPS is now below Wobbler's, and the unlock still feels like an upgrade everywhere else. |
| Boo | `reload` 1.00 -> 0.85 | Boo paid 20 % HP and +20 % knockback for floaty jumps while Gramps got better air control, more HP and faster reloads. A 15 % faster reload gives Boo a real combat identity without raising its EHP or mobility. |

## Weapons

| Weapon | Change | Why |
| --- | --- | --- |
| Mammoth Pistol | shared `headMul` 15.33 -> 8 (web source `public/index.html`, re-exported to `shared/weapons.json`) | 15.33 was a 230-damage headshot: a one-shot on every 150/200 HP class except Bruiser and Bulwark, in web and online matches. 8 gives 120 (134 on a Bruiser), a two-headshot kill in every mode. The Godot offline overlay already used 8; the two regimes now agree. |
| Giant Mallet | shared `ammo` 4 -> 6 | 4 swings = 112 damage per pickup, less than a 150 HP class. 6 swings = 168: still a ring-out tool first, but a full pickup can now finish a wounded target and the 6.5 s body TTK comes down. |
| Angle Grinder | `ammo` 30 -> 50 (Godot-only DLC) | 30 fuel was ~70 damage per pickup, far below the Nail Gun (480) and Jackhammer (200) crate drops. 50 fuel brings it to roughly 117 plus burn at 5 m. |
| Air Blower | tuned `dmg` 2.5 -> 2.8 | A full 100-fuel tank did 28/s for ~3.57 s = ~149 damage, one point short of a 150 HP K.O. 2.8 tops out at ~167 and can secure the K.O. The shared (web/online) blower still does no damage. |
| Rocket Launcher | burst `regen` 5.0 -> 3.5 s | After the two-shot burst the tuned launcher had a long dead-air window (38.9 burst -> 14.0 sustain DPS). |
| Grenade Launcher | burst `regen` 4.0 -> 3.0 s | Same sustain cliff (57.4 burst -> 16.5 sustain). |
| Meteor Launcher | burst `regen` 6.0 -> 4.5 s | Same, at the top end (57.5 burst -> 19.2 sustain). |
| Cluster Launcher | unchanged (4.5 s) | Its 3-grenade burst is already close-range-only; the other three launchers were the worst offenders. |

## Construction crates

`shared/drops.json` is exported from the web game, which has no DLC tools, so adding the 9 tools there would make
`npm run content:check` fail and would put Godot-only content in the cross-client data. Instead,
`godot/data/extra/construction/modes.json` now carries `dropWeights` for all nine tools; `ModeRules.merge_extra`
merges that dictionary into the existing `construction` mode and `Pickups.pick_crate_key` reads it next to the shared
weights. `drops.allow.construction` still gates the shared pool; an explicit `dropWeights` entry is its own allow entry.

Weights: Pipe Wrench 0.7, Nail Gun 0.8, Jackhammer 0.7, Spirit Level 0.8, Tape Measure 0.8, Cement Bucket 0.6, Cone
Launcher 0.7, Angle Grinder 0.5, Drill 0.8. They are about 38 % of the Construction crate pool (heal is the largest
single entry), which is enough for the DLC tools to show up in a normal match without crowding out the hammer / Live
Wire / Air Blower identity of the mode. `construction_test.gd` draws 3,000 crates and requires every tool to appear;
`construction_data_test.gd` validates the weights.

## Arcade pickups

Arcade enemies now have `FighterState.arcade_enemy`. `Pickups.bot_wants` refuses Rage and Shield for them (they still
take Speed), so those crates are left for the players. `ArcadeManager.keep_kit` also clamps any Rage or Shield that does
land to `ENEMY_BUFF_TIME` (2.0 s), exactly like Speed. Before this a Phase 2 boss with Rage hit for x2.16 (1.44 phase
damage x 1.5 Rage) and a Shield doubled its effective HP for 12 s.

## Offline K.O. limit

The Setup Wizard's Players page now has a **K.O. limit** row: Auto / None / 5 / 10 / 20, saved as `Settings limit`
(-1 = Auto). Auto follows the mode preset; when a brawl mode's preset is still 0 (no limit, no lives, no ladder and no
clock), it plays to `ModeRules.LIMITLESS_DEFAULT` (20). This gives Classic, Melee Only, Guns Only, Ninja, Explosive,
Giant, Moon Drift and Construction a victory screen without changing team modes (Duel 5, 2v2 10, 3v3 15, 4v4 20) or
the modes that already end by lives / ladder / clock. An explicit **None** still means no limit. The Start page's
Players summary shows the effective value ("First to 20"). Arcade runs pass 0 explicitly: a boss rush is cleared stage
by stage, never by a K.O. count.

## Supervisor

- `backup_call` now marks the summon spot with an amber ground ring for `warning_time` (1.5 s) before the tradie
  lands, the same readable warning the Engineer's load-test crates use. The spawn itself is unchanged: one Bluey,
  once per attempt, at 50 % boss HP, at the farthest safe floor spot. If the Project Manager's floor (or a future
  shrink) has moved off that spot in the meantime, the manager picks a fresh one.
- Easy and Normal now scale outgoing **melee force and topple chance** as well as damage: Easy 0.75 force / 0.65
  topple, Normal 0.9 / 0.8, Nightmare 1.0 / 1.0. This targets the Pipe Wrench chain-shove without touching its
  damage floor (`dmg_scale: 0.6`) or any other boss's table numbers. The multipliers are fields on `FighterState`
  (`melee_force_mul`, `melee_topple_mul`) applied where melee hits are resolved, so they are per-fighter and do not
  leak into the web parity paths (default 1.0).

## Deliberately left for a later pass

These are design calls, not bugs, and each needs an owner decision:

- **Online vs offline weapon split.** The tuning overlay still applies only offline (or `net_zones`). Merging the two
  regimes would change web/online balance far beyond this PR.
- **Twin Fang Bow's 24-arrow pickup, Net Gun's 4.5 s/2.5 s pin, Dual Uzis' 40-round magazine.** These are outliers in
  the review, but changing them is a larger weapon-economy pass.
- **Melee Only's pool** (no Katana, 0-damage Glove, 52.8 % heal / power-up crates). The glove is an intentional
  ring-out tool; the pool composition is a mode-design call.
- **Chaos / Mega multiplicative stacks** (Rage x headshot x mode damage). Changing them would touch the web game's
  mode rules and the damage parity tests; worth its own pass.
- **Two-seat co-op enemy HP.** A 1.35x-1.5x co-op multiplier is a plausible next change, but the current tests and
  the owner brief treat co-op as the same fight with two players and auto-revive; this PR does not change it.
- **`change_request.params.phases`.** The Client's phases still come from `ArcadeManager.PHASES`; reading the table
  value is a small cleanup, not a balance change.
- **Class head / size / wide hitboxes.** Hit spheres remain fixed; making them scale is a combat-feel change that
  would break the combat parity tests unless it is gated to Godot offline.
