# Title screen: menu rail, 3D stage, DLC showcase

The title (`godot/scenes/main.tscn`, `godot/scripts/main.gd`) is a **left menu rail** beside a **3D stage**.
No gameplay, combat or physics code is involved; the one hook in the match is the `trial` flag described below.

```
landscape                                         portrait
+-----------+-----------------------------+       +-----------------------+
| Play      | WOBBLERS ARENA    (you) (⚙) |       | WOBBLERS ARENA (you)(⚙)|
| Quick play|                             |       |        3D stage       |
| Play onl. |        3D stage             |       |      DON'T ENTER      |
| Walldrobe |   wobbler  crane+container  |       | Play                  |
| Shop      |                             |       | Quick play ... Goals  |
| Goals     | [       DON'T ENTER       ] |       +-----------------------+
+-----------+-----------------------------+
```

| Node | What |
| --- | --- |
| `Background` | `ui/title_bg.gd`, the drawn sky. With the stage (`stage_3d`) it no longer draws its own crane / props on the Construction title. |
| `Showcase` | `ui/title_showcase.gd`: the stage's picture, full screen, behind the controls. |
| `Safe/Rail` | Play, Quick play, Play online with friends, Walldrobe, Shop, Goals. Same routes as before. |
| `Safe/Col` | `Top` (logo, account chip, gear), `Body/Home` (`Stage`: the slot the scene is framed in, and the `Construction` DON'T ENTER sign), `Body/Online`, `Tip`, `Build`. |
| `ShowcaseUI` | `TitleShowcase.overlay`: the TAP TO OPEN tag; Back, the pack header and the bar while a container is open. |

`apply_safe_area()` lays it out: in landscape the rail is a strip 36 % of the safe width (300 to 430 px) and the column
takes the rest; in portrait the column is on top and the rail under it (thumbs). `_unit()` is the touch-size factor: 1
in landscape (UiScale already keeps 60 canvas px at 44 pt), about 2.4 in portrait, where the same 1170 px canvas shows
on a third of the points. `_fit_rail()` shrinks a button's big line to the rail and shows its small line only when it
fits on one line (it is the tooltip too); `_fit_logo()` gives the logo what the chip and the gear leave, on two lines
when a long account name leaves very little. Other pages (wizard, Walldrobe, online tab) hide the rail and the stage
(`_home_layers()`), and the stage stops rendering under Settings, Goals and the Construction hub.

## The stage (`ui/showcase_stage.gd`)

`ShowcaseStage` extends `CharacterStage`: the same lights and the same real Wobbler in the player's class, outfit, hat
and colour. Added: a round concrete pedestal with a hazard kerb, a tower crane, and the pack's container on the hook.
Built in code from boxes: the crane, the container shell and each door are one merged vertex-colour mesh each; a rack
weapon is the Wobbler's own fused held-weapon mesh (`Wobbler._weapon_visual`), so the rack shows exactly what a match
shows; one unshadowed lamp inside the container; the landing dust is eight pooled low-poly blobs. The render target is
the window's pixels, capped at 2.2 MP (`TitleShowcase.MAX_PIXELS`), MSAA by tier.

The whole scene is posed from five numbers (`lower`, `doors`, `cam_k`, `hoist`, `pop`) in `apply_pose()`. The camera
frames a box of metres inside a screen rectangle (`frame_pos`): the idle scene inside the `Stage` slot, the open
container between the pack header and the bottom bar. Picking is plain ray maths against the container's and the rack
cells' boxes (`pick`), with no physics bodies; `project` / `cell_rect` give the screen positions back. Portrait sets
`compact`: the wobbler stands closer and the doors open square, so a rack cell is still 44 pt wide.

## The showcase (`ui/title_showcase.gd`)

| State | What happens | Input |
| --- | --- | --- |
| `IDLE` | The container hangs shut; the "TAP TO OPEN" tag dangles under it. | The tag is a real Button (mouse, touch, keyboard, gamepad, screen reader). A tap on the container itself is ray-picked (`tap_at`, forwarded from the `Stage` slot). |
| `OPENING` | The rail and the column fade (`ui_changed`), the camera moves in, the crane lowers the container (dust, `land` + `clink`), the latch lifts, both doors swing open. | Back reverses it at once. Everything else is dropped. |
| `OPENED` | Racks: the pack's weapons and an arena badge. A tap (ray) or focus (one proxy Button per cell) puts the weapon in the wobbler's hand and the pack's hat on its head. | Back, `‹ SWAP PACK` / `SWAP PACK ›` (two packs or more), `TEST IN <ARENA>`, `UNLOCK PACK` or an OWNED badge. |
| `SWAPPING` | Doors shut, the container is hoisted out of the picture, the next pack's comes down and opens. | Swap spam is ignored; a Back is remembered and runs after the landing. |
| `CLOSING` | Doors shut, the container goes back up, the camera and the title return. | A tap on the tag re-opens from where it is. |

One tween drives the pose numbers from wherever they are, so open and back can interrupt each other half-way; a
full-screen catcher keeps taps off the title while not `IDLE`; `snap()` jumps to a resting state (used when another
page opens mid-animation, and by screenshots). Back is the Back button, Escape / controller B (`ui_cancel`) and
Android's back gesture: `main.go_back()` closes the container before the pages under it.

The weapon preview is **only a preview**: nothing is written to Settings or Save. The game has no loadout for crate
weapons (they come from crates in a Construction match), so there is nothing to equip; an owned pack shows OWNED.
`UNLOCK PACK` opens the existing Construction hub (`open_hub()`: coins or the code), and the bar refreshes when the
profile changes.

## Packs (`dlc/dlc_pack_data.gd`, `dlc/dlc_packs.gd`)

`DLCPackData` is a Resource: `pack_id` (the `data/extra/<id>/pack.json` id), `display_name`, `subtitle`,
`accent_color`, `weapon_ids`, `arena_id`, `container_style`, `badge_icon` (the preview hat), `test_mode`,
`unlock_kind`. `is_unlocked` is a getter that asks the profile every time (`DlcUnlock.owned()` for `"construction"`),
never a stored bool. `DLCPacks.PATHS` lists the `.tres` files (an explicit list: a directory scan of `res://` is not
reliable in an exported build); a pack whose weapons or arena do not exist in the build is skipped with a warning.

To add a pack: make `godot/dlc/packs/<id>.tres`, add its path to `DLCPacks.PATHS`, add an `unlock_kind` branch in
`DLCPackData.unlocked()` if it has its own unlock, and add its strings to `godot/i18n/src/`. The showcase code does
not change. With one pack the swap arrows are hidden.

## Test drive (`main.play_trial`, `world.trial`)

`TEST IN SITE YARD` starts an offline match on the pack's `arena_id` in its `test_mode` with two easy bots, no K.O.
limit and every pack weapon on the floor round the start (`Pickups.place_perm`: they come back 2.5 s after a pick).
It is open to players who do not own the pack, so `world.trial` skips every `Save` call of a match: no coins, stats,
goals, history or ranking, and the unlock is never touched.

## Tests and screenshots

- `npm run test:godot-title` (`godot/tests/title_showcase_test.gd`): the pack data, every rail route, 44 pt targets
  at 852x393 / 667x375 / 390x844, the state machine under spammed input with a second test-only pack, the test drive.
- `npm run test:godot-ui` checks the rail and the column on the `title` screen at every size and in French and
  Japanese (`_title_home`).
- `sh tools/shoot-godot-ui.sh "" title title-site title-open title-open-owned title-weapon` writes
  `docs/style/godot-ui-title*.png` (`--pick N` chooses the rack cell for `title-weapon`).

## Performance

Counted on the dev machine (an Apple-silicon Mac, 1704x786 window; the whole title, 2D included; the same on Forward+,
Mobile and Compatibility):

| | no stage | idle stage | open container |
| --- | --- | --- | --- |
| draw calls per frame | 145 | 193 | 135 to 141 |
| triangles per frame | 5.9 k | 13.1 k | 13.5 k |

So the stage costs about 50 draw calls and 7 k triangles, shadow pass included. Whole-frame times with vsync off were
between 1.5 and 7.5 ms on all three renderers (130 fps or more) and too noisy to give a per-renderer cost.
**Not measured on a device**: an iPhone and the web export in a phone browser still need a real run (the perf overlay,
Settings > Graphics, works on the title).
