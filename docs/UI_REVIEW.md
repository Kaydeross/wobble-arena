# UI review: clean, uncluttered, nothing overlapping

Goal: every screen reads at a glance on a phone held in landscape. Nothing overlaps, nothing is crowded.

## Rules (enforced by `godot/tests/ui_layout_test.gd`, `npm run test:godot-ui`)

- Spacing comes from the scale in `ui/theme_builder.gd`: `SP_1` 4, `SP_2` 8, `SP_3` 12, `SP_4` 16, `SP_5` 24 (canvas px).
- Two interactive controls are at least 8 pt apart (`MIN_GAP`) and never overlap (landscape, 44 pt scale).
- Touch targets stay at least 44 pt.
- No label is set below `UiTheme.MIN_FONT` (14 px), and no visible text is truncated (ellipsis, clipped line, over-long wrap).
- A busy bar (title top row and cards row, wizard footer and header, Walldrobe header and footer) holds at most 4 buttons.
- The checks also run in Francais and Japanese on the key screens.

## What changed

- Title: What's new moved into Settings > About, with a gold dot on the gear while patch notes are unseen; three cards remain (Walldrobe, Shop, Goals). The version line hides on the online tab.
- Setup wizard: the five step pills became progress dots; the footer is Back / Next only.
- HUD: the toast has its own top band (`MatchHud.TOP_STACK`) and the team board / mode line start below it; long hotbar weapon names wrap to two lines instead of shrinking.
- Results: a dim layer sits under the panel and the toast is cleared, so only Play again / Quit compete for attention.
- Sheets (host a room, lobby, account, What's new): opaque or strongly dimmed backdrop, centred in the safe area, long player names trimmed.
- Walldrobe, Settings, controls help, room browser, team board: spacing moved onto the scale.

No simulation, combat, physics or gameplay behaviour changed; all text still goes through `tr()`.
