# Aim modes (Normal / Advanced)

The aiming system has two modes, picked in **Settings › Gameplay › Aim mode** (key `aim_mode`, default `normal`). The
row applies live: on every local-player step `PlayerControl.think()` copies it into `Combat.aim_mode`, so a mid-match
change takes effect at once without restarting. A bare `Combat` (and therefore the JS parity fixtures) always starts
`"normal"` and never reads Settings, so the shared numbers stay deterministic.

| Mode | Aim assist | Damage | Where it works |
| --- | --- | --- | --- |
| **Normal** (default) | on: the crosshair point is pulled slightly toward a nearby enemy | exactly the shared numbers | offline (Practice / Arcade / bot matches); online keeps today's aim and damage |
| **Advanced** | off: manual aim only, no target snapping or magnetism | the local player's own hits **+25%** | the damage bonus is **offline only** (see below) |

Neither mode changes the weapon numbers in `shared/*.json` or the web game: both are client-side preferences.

## Normal: aim assist

`PlayerControl._assisted_aim()` (logic/player_control.gd) runs while the player is aiming or firing, **offline only**
(the web game has no mouse/controller magnetism, and online the shooter's client decides every hit, so a client-side
assist would skew cross-play):

- a target qualifies when it is an enemy (`Combat.is_friend`), alive, not a ghost and not left, **1–32 m** from the
  shoulder, with line of sight (`MatchSim.has_los`), and inside a **~7° cone** around the crosshair
  (`ASSIST_CONE_COS` 0.9925);
- of the qualifying targets the one closest to the crosshair is picked; the aim direction is moved **85 %** of the way
  from the crosshair to its **chest** (`ASSIST_PULL` 0.85), keeping the crosshair's distance so weapon range and falloff
  do not change;
- with no qualifying target the crosshair is untouched. The camera and the movement stick are never moved; this is the
  crosshair point only, and it is deliberately gentle (a target that is not roughly under the crosshair is not helped).

This is the "existing assistance, improved" half of the owner request: the base game already sends the local player's
shots exactly where the crosshair points (`Weapons.aim_from_hand`); Normal adds the small target magnetism the touch
build had on the web (`touchAssist`), for mouse and controller too. The old, unused `touch_assist` setting is not
wired into this (the assist row is the single switch).

## Advanced: no assist, +25% damage

- No aim magnetism: the crosshair point, the arm and the camera all stay exactly where the player puts them. (The
  shared gun/melee aiming model itself is untouched: the player's shots still follow the crosshair, as on the web game.
  What Advanced removes is the assist layer above it.)
- **+25% damage** (`Combat.ADVANCED_DAMAGE` 1.25, applied in `Combat.hit`) when **all** of these hold:
  - the attacker is the local player (`attacker.is_player` and not a ghost; `Combat.aim_mode` is copied from the
    Settings row by `PlayerControl` on every local step),
  - the victim is someone else (self-damage is not boosted),
  - the match is **offline** (`Combat.net_started == false`, which includes Practice, Arcade and every bot match).

  It does **not** apply online, to bots (they are not `is_player`), to ghost-relayed hits (those return through the
  network path before the damage math) or on the web game. Online the shooter's client decides the damage it sends in
  the `h` message, so a local +25% there would make the same shot hurt differently depending on who fired it: the damage
  bonus is therefore **offline only** to keep web cross-play parity. This is deliberate and documented, not an
  oversight.
- The bonus multiplies the final damage together with the existing class / rage / shield / mode multipliers, so the
  floating damage number, the stats and the K.O. threshold all use the boosted value.

## HUD

`ui/hud.gd` adds a small badge in the K.O. pill while a match runs in Advanced: **"Advanced aim · +25% damage"**
offline, **"Advanced aim · no bonus online"** online. It follows the setting live and is hidden in Normal, so the
existing HUD layout tests are unchanged.

## Settings key and migration

`aim_mode` used to mean the mouse/controller aim **button** (hold | toggle). That setting is now `aim_button`
(Settings › Controls › Aim button); `Settings.migrate_aim_button()` moves an old stored value on the first launch, so
existing players keep their aim button behaviour. `aim_mode` now holds `normal` (default) | `advanced`.

## Tests

- `godot/tests/weapons_test.gd` (`--no-save`): the spatula switch (cycle / slot key / touch action), the aim-assist
  on/off assertions at the `PlayerControl` level (Normal pulls the aim point toward the chest, Advanced is bit-exact
  manual aim, out-of-cone and online targets are never assisted) and the settings default / migration.
- `godot/tests/damage_test.gd`: Advanced is exactly ×1.25 for the local player offline, Normal is the old damage,
  bots / online / a ghost-relayed hit get no bonus.
- `godot/tests/gunfeel_test.gd`: spatula cycling / `spatula_lock` / pickups / dropped weapons (CI-run via
  `npm run test:godot-gunfeel`).
- `godot/tests/flow_test.gd` (`npm run test:godot-flow`): the Settings › Gameplay row exists, choosing Advanced writes
  the key immediately, and the HUD badge follows it live.
