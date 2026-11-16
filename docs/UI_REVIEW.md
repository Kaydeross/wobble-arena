# UI review: clean, uncluttered, nothing overlapping

Goal: every screen reads at a glance on a phone held in landscape. Nothing overlaps, nothing is crowded.

## Rules (enforced by `godot/tests/ui_layout_test.gd`, `npm run test:godot-ui`)

- Spacing comes from the scale in `ui/theme_builder.gd`: `SP_1` 4, `SP_2` 8, `SP_3` 12, `SP_4` 16, `SP_5` 24 (canvas px).
- Two interactive controls are at least 8 pt apart (`MIN_GAP`) and never overlap (landscape, 44 pt scale).
- Touch targets stay at least 44 pt. This includes the optional Small density on handhelds; Small remains denser only
  on mouse-driven devices.
- No label is set below `UiTheme.MIN_FONT` (14 px), and no visible text is truncated (ellipsis, clipped line, over-long wrap).
- A busy bar (title top row and cards row, wizard footer and header, Walldrobe header and footer) holds at most 4 buttons.
- The checks also run in Francais and Japanese on the key screens.
- The title's icon dock is exactly five buttons in their own panel, counted on its own; the dock, Play, the chips, the logo and the CONSTRUCTION pill must never overlap (`_title_home`). See [TITLE.md](TITLE.md).

## What changed

- Title: What's new moved into Settings > About, with a gold dot on the gear while patch notes are unseen; three cards remain (Walldrobe, Shop, Goals). The version line hides on the online tab.
- Setup wizard: the five step pills became progress dots; the footer is Back / Next only.
- HUD: the toast has its own top band (`MatchHud.TOP_STACK`) and the team board / mode line start below it; long hotbar weapon names wrap to two lines instead of shrinking.
- HUD text has an ink outline over bright arenas. The F3 frame-time pill and detailed performance readout stack below
  the score panel, preserving the top-centre objective band and clear thumb arcs.
- Results: a dim layer sits under the panel and the toast is cleared, so only Play again / Quit compete for attention.
- Sheets (host a room, lobby, account, What's new): opaque or strongly dimmed backdrop, centred in the safe area, long player names trimmed.
- Walldrobe, Settings, controls help, room browser, team board: spacing moved onto the scale.

No simulation, combat, physics or gameplay behaviour changed; all text still goes through `tr()`.

## Combat HUD on phones (mobile HUD review)

A phone is a touch layer on a canvas that is not tablet-class (`MatchHud.compact`, `TouchControls.is_tablet`). Desktop and tablets keep the full HUD.

- Radar 124 -> 96 canvas px (`HudRadar.D_COMPACT`); health bar drawn at 86 % (`HudHealth.COMPACT_K`), which frees room for the hotbar slots.
- Score pill: the "No leader yet" line is hidden until someone leads (the row only returns with a leader).
- Kill feed: the two latest lines, 3.5 s each (was four lines, 5 s) so it stays off the right thumb's play area.
- Nameplates: two, within 30 m (was three, 45 m).
- Off-screen enemy arrows (`ui/enemy_indicators.gd`): three nearest within 45 m on phones (six on tablets/desktop), a slightly bigger and brighter marker (30 px, min alpha 0.65), measured from the view centre, able to slide all the way round the rim past the hotbar (an enemy dead behind you used to get no arrow when the bottom edge was blocked), kept clear of the move stick, and for enemies behind the camera the vertical part of the arrow is the world height difference (damped) rather than camera-up, so looking down does not make level enemies point up.
- `tests/ui_shots.gd` has a `busy` shot (five bots around the player, three off screen, a feed, a toast, a damage number, fingers down) and `--safe L,T,R,B` (pt) to fake a notch: `godot --path godot --resolution 852x393 --script res://tests/ui_shots.gd -- --no-save --shot busy --safe 59,0,59,21 --out FILE.png`.
