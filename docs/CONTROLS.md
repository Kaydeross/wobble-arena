# Controls: one scheme per device, and the Training

The game has three ways to play, and the player only ever sees the one they are using:

| Profile | When | Moves | Look | Fire / aim | Shove / kick |
|---|---|---|---|---|---|
| `touch` | the on-screen controls are on (a phone / tablet, a web page on a touch device, or Settings > Controls > Touch buttons "On") | stick | drag | FIRE button, double-tap | MELEE: tap = shove, hold = kick |
| `keyboard` | desktop (and a desktop browser), the default | W A S D | mouse | left mouse, right mouse / Z | **E** shove, **F** kick |
| `gamepad` | desktop with a controller, after the last input was a pad press | left stick | right stick | RT, LT | **RB** shove, **B** kick |

Code: `godot/input/control_profile.gd` (`ControlProfile`, no autoload).

## Which profile is active
`ControlProfile.current()`:
1. `ControlProfile.force` (tests, screenshots) if set;
2. `touch` when `TouchControls.wanted()` (the same rule that shows the touch layer: `Tier.touch_default()` = a phone / tablet, or a
   **web page where `DisplayServer.is_touchscreen_available()`**, or Settings `touch_mode` = on). Touch devices stay touch;
3. otherwise the **last desktop device used**, live: a joypad button press or a pushed stick (> 0.6) -> `gamepad`; a key press,
   a mouse click or real mouse movement -> `keyboard`. A small listener node (`ControlProfileWatcher`, added lazily under the root,
   sees input before the UI) tracks it and emits `changed`.

On the web export a desktop browser reports no touchscreen, so it is `keyboard` (+ `gamepad` once a pad is pressed); a phone
browser reports one, so it is `touch`. (A touch-screen laptop in a browser also reports one: it gets the touch layer, as it
always did; Settings > Controls > Touch buttons "Off" forces keyboard.)

## Labels are read, never copied
`ControlProfile.names(action, profile)` / `name_of()` read the live bindings: the InputMap actions that `PlayerInput.ensure_actions()`
seeded from its `KEYS` / `MOUSE` / `PAD` / `PAD_AXES` tables (so a rebinding shows up at once), `EmoteWheel.KEYS` for the emote keys and
`TouchControls.BUTTONS` for the touch buttons. The Controls screen, the Training prompts and the HUD hint all go through it.
Words ("Left mouse", "Left stick") are translated; key and button letters (E, Space, RB) are not.

## The Controls screen (`ui/controls_help.gd`)
One scheme at a time with a `Touch | Keyboard & mouse | Gamepad` switch (the active one preselected) and a **Training** button:
- touch: the picture of the real layout (mirrored when left-handed) and four how-to lines;
- keyboard: keycap cards, built by `ControlsArt.keyboard_board()`: Move, Combat (Fire, Aim, **SHOVE**, **KICK**: the yellow keycaps),
  Moves, Weapons, Emotes, Pause. It grows to fill a bigger window (up to 1.6x);
- gamepad: a drawn controller (`ControlsArt.PadPic`) with a leader line and a word per button.
In the pause menu the Training button asks once before it leaves a running offline match, and is hidden online.

## The Training (`world/tutorial.gd`, `logic/tutorial_steps.gd`, `ui/tutorial_card.gd`)
The Practice Range as a `trial` world (`World.tutorial = true`): flat, dummies that never fight back, no K.O. limit, no clock,
nothing is written (no coins, stats, goals, history, ranking, ads counter). The player has an AK-47 and a Ninja Katana with endless
ammo, cannot be K.O.'d, and the class signature is kept recharging so the touch context button is free for RELOAD / DASH.

Steps: Move, Look, Jump, Fire, Aim, Reload, Shove, Kick, Switch weapon, Dash, back to the Spatula, Pause. A step is done when the real
input happens: the training listens to `InputState.action_down` / `looked` (every device writes into that one state), polls the move
vector, the scope, the weapon in hand and the pause menu. The coach card (top centre, away from the thumb zones) shows the active
profile's prompt with the real key / button highlighted, progress dots, **Skip step** and **Exit**; a green cheer between steps; the
finish card (**Play** / **Replay** / **Back**). If the player switches device mid-lesson (keyboard <-> gamepad) the prompt follows. On touch a
pulse ring sits over the real control (positions read from `TouchControls`).

Entry points:
1. the one-time offer: the first time a **fresh, saved** profile (no match played, `seen_tutorial` false, `Settings.persist`) presses Play or
   Quick play, a small card asks "Learn the controls? Start / Skip" (`ui/tutorial_offer.gd`). Never forced; either answer sets
   `seen_tutorial`, so it comes once. Never shown for `--no-save` sessions / tests;
2. the **Training** button on the Controls screen (Settings > Controls > See the controls, and the pause menu's Controls page).
The title screen itself has no new control.

Settings keys: `seen_tutorial` (the offer was answered or the lesson finished), `ctl_hint_matches` (real matches that showed the hint).

## The match hint line
For a player who has not done the training, the HUD hint line also shows what shove / kick / jump are on this device
(`Shove: E · Kick: F · Jump: Space`, `Shove: RB · Kick: B · Jump: A`, `Melee: tap to shove, hold to kick`) for the first 14 s of the first two
real matches. Nothing after that or after the training.

## Tests and screenshots
`npm run test:godot-tutorial` (`godot/tests/tutorial_test.gd`): profile detection and live switching, labels from real bindings (a rebinding
changes the label), the Controls screen (only the active profile, the switch), the Training end to end for all three profiles through the
real device paths (key and pad events into `PlayerInput`, screen touches into `TouchControls`), wrong inputs do not advance, Skip / Replay /
Exit, nothing saved, the offer once, the hint. `godot/tests/controls_shots.gd` renders the screenshots (`docs/style/godot-controls-*.png`).

Known gaps: a real gamepad, real touches and real mouse capture are not exercised in the headless tests (a joypad press, `Input` actions,
screen-touch events and `InputState` writes stand in for them); the mouse "look" and "fire" steps are driven through `InputState`
because a headless window cannot capture the mouse.
