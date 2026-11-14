# Kids mode

An optional assist for younger players (and anyone who wants a calmer match). Setting: **Settings › Controls › Kids
mode**, key `kids_mode` (default off, `godot/autoload/settings.gd`). It applies live: `logic/kids_assist.gd` reads the
key on every think step, so the toggle takes effect mid-match without restarting.

In return for the help, kids mode pays **half coins** and **never submits a leaderboard score**. It is **offline-only in
v1**: it changes only the local player's controls and rewards. The online lobby, rooms and protocol are untouched. Online
the other players are ghosts, so the auto-aim has no valid target and stays quiet (the edge guard still helps locally).

## Auto-aim and auto-fire (`logic/kids_assist.gd`, called from `PlayerControl.think`)

- **Target:** the nearest living enemy that is not a friend (`Combat.is_friend`), not a ghost, not dead and not
  eliminated, inside the held weapon's range and a **±75° cone** around the camera, with line of sight
  (`MatchSim.has_los` from shoulder to chest). "In range" is the gun's `range`; for a melee weapon the tip plus the
  arm (an enemy within 2.5 m is at least faced); for thrown weapons without a range, 22 m.
- **Sticky target:** the current target is kept while another enemy is less than 1.25× closer, so the aim does not
  flicker between two enemies at the same distance.
- **Aim:** at the enemy's **chest** (glauncher / cluster / net / snowball: the feet plus their drop, like the bots).
  A slow **±0.35 m lateral sway** (0.85 Hz sine of the match clock, deterministic) keeps it assistance, not an aimbot;
  the assist does **not** lead a moving target and adds no random error.
- **Fire:** held automatically while a target is in range. Melee swings only once the enemy is inside the weapon's tip
  (`tip + 0.9 m`); the bow holds the draw and lets go at 85 %; the trident taps a jab up close and charges ~0.35 s before
  throwing further out; every other weapon holds the trigger (reloads and cool-downs are the normal ones).
- **No fight with the player:** with no target the manual crosshair, aim point and fire button are untouched, and the
  player still moves with the stick. Edge guard and assist never change the camera.

## Edge guard

While the player is on the floor and walking, the guard probes the floor (`sim.solids`, the same probe as the bots'
`botGround`) at **0.9 / 1.8 / 2.7 m** ahead. If the floor runs out it **steers** the stick up to **±0.55 / ±1.1 / ±1.6
rad** to a direction that has floor (sliding along the edge); if even those are void it **stops** the walk. It never
teleports, and walking back inward is always allowed, so a corner is not a trap. A jump is cancelled when the estimated
landing spot (about the running-jump distance ahead) is in the void, or when the walk is already blocked. Knockback can
still ring the player out — the normal respawn handles that.

## Rewards

Kids mode earns **half coins** (`SaveProfile.award_coins`): odd awards round down (5 → 2, 101 → 50, 1 → 0, 0 → 0).
It applies to `Save.add_coins`, K.O. coins, the match / win bonus, the daily streak bonus and claimed Goals. The results panel reports
the halved coins. Construction Arcade payouts are paid directly by the arcade manager and are not halved in v1.

## Ranking

No score is submitted in kids mode: the ranking client checks the setting (`AccountApi.rank_allowed()` reads
`kids_mode`), and `KidsAssist.leaderboard_allowed()` exposes the same guard for any other submit path. No rank is shown
for a kids mode session.

## In the HUD

The score pill grows a small badge — **"Kids mode · half coins · no leaderboard"** (`ui/hud.gd`) — that follows the
setting live. Normal play never sees it, so the HUD layout tests are unchanged.

## Tests

`godot/tests/kids_test.gd` + `tools/test-kids.js` (`npm run test:godot-kids`, add the line
`"test:godot-kids": "node tools/test-kids.js"` to `package.json` scripts): auto-fire at the nearest enemy in range, no
fire behind the camera or through a wall, no assist with the setting off, the melee reach, the edge guard (walk, jump,
corner), half coins and the live toggle + HUD badge.
