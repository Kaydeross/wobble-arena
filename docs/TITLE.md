# Title screen: Hero Stage

The title (`godot/scenes/main.tscn`, `godot/scripts/main.gd`) is the **3D stage full-bleed behind everything** with a few
controls on top: the logo top left, the chips top right, an icon dock bottom left, one huge Play button bottom right and a
hazard-striped CONSTRUCTION pill hanging from the container. Landscape only (the game is landscape-only). No gameplay,
combat or physics code is involved; the one hook in the match is the `trial` flag described below.

```
+----------------------------------------------------------+
| WOBBLERS                          (coins 635)(Guest)( ⚙ ) |   crane + container top right
| ARENA                          [=== container ===]       |
|                                 [ CONSTRUCTION  NEW ]    |   the pill hangs under it
|          your wobbler (60 % of the height)               |
|                                                          |
| [⚡][🌐][👔][🛍][🎯2]                     [  ▶  Play  ]    |   dock bottom left, Play bottom right
| Quick Online Wall. Shop Goals                  v0.5.0    |
+----------------------------------------------------------+
```

| Node | What |
| --- | --- |
| `Background` | `ui/title_bg.gd`, the drawn sky behind the stage. |
| `Showcase` | `ui/title_showcase.gd`: the stage's picture, full screen, behind the controls. It is also the tap layer: a tap on the container opens it. Because of that `Safe`, `Safe/Col`, `Top`, `Body` and `Home` have `mouse_filter = ignore`. |
| `Safe/Col/Top` | `Logo` (two lines, WOBBLERS / ARENA), `Coins` (coin chip: tap = Shop), `GuestChip` (Account), `Gear` (Settings). The same row is the header of the online panel (one-line logo, no coin chip). |
| `Safe/Hero` | `Dock` (`ui/title_dock.gd`, `TitleDock`: Quick, Online, Locker, Shop, Goals, each a Button with a drawn icon tile, a word and, on Goals, the claimable-goals badge), `Play` and `Build` (the version). Anchored to the corners of the padded safe area by `main._fit_hero()`. |
| `ShowcaseUI` | `TitleShowcase.overlay`: the CONSTRUCTION pill (`DlcPill`, `ui/dlc_pill.gd`) while idle; Back, the pack header, the bar and the DON'T ENTER sign while a container is open. |

Where the old actions went: Play, Quick play, Play online with friends (now "Online"), Walldrobe, Shop and Goals have the
same routes as before (wizard, `quick_play()`, online panel, locker, shop, goals). The six-button rail, the boxed stage
column, the TAP TO OPEN tag, the full-width DON'T ENTER bar, the Play sub line and the tip line are gone. The tip is the
Play button's tooltip (with the last setup). The coin count that used to be the Shop button's second line is the coin chip.
**The DON'T ENTER sign** (`DontEnterSign`, still the route into the Construction title: `toggle_dlc`, the tape wipe) is
now in the **opened showcase**, top right. On the Construction title the pill and that sign read EXIT SITE and go back.

`apply_safe_area()` lays the title out: `HOME_MARGIN` padding plus the phone insets; the logo as big as 5.7 % of the width
(never wider than the chips leave); the dock as wide as its words; Play 31 % of the width. `_unit()` is the touch-size
factor (1 in landscape: UiScale already keeps 60 canvas px at 44 pt). Other pages (wizard, Walldrobe, online tab) hide
the hero controls and the stage (`_home_layers()`), and the stage stops rendering under Settings, Goals and the
Construction hub. The dock words are 16 canvas px (about 11.7 pt on an iPhone; the theme minimum is 14).

The pill says NEW while the pack is not owned (no "seen" flag is saved: the profile schema stays as it was).

## The stage (`ui/showcase_stage.gd`)

`ShowcaseStage` extends `CharacterStage`: the same lights and the same real Wobbler in the player's class, outfit, hat
and colour. Added: a round concrete pedestal with a hazard kerb, a tower crane, and the pack's container on the hook.
Built in code from boxes: the crane, the container shell and each door are one merged vertex-colour mesh each; a rack
weapon is the Wobbler's own fused held-weapon mesh (`Wobbler._weapon_visual`), so the rack shows exactly what a match
shows; one unshadowed lamp inside the container; the landing dust is eight pooled low-poly blobs. The render target is
the window's pixels, capped at 2.2 MP (`TitleShowcase.MAX_PIXELS`), MSAA by tier.

The whole scene is posed from five numbers (`lower`, `doors`, `cam_k`, `hoist`, `pop`) in `apply_pose()`. The camera
frames a box of metres inside a screen rectangle (`frame_pos`): the idle hero shot inside the title's padded safe area
(`IDLE_VIEW`: container top right, pedestal low, the wobbler forward and 1.7x big on `WOB_IDLE_POS`; it steps back to its
rack place as the camera moves in), the open container between the pack header and the bottom bar. Picking is plain ray maths against the container's and the rack
cells' boxes (`pick`), with no physics bodies; `project` / `cell_rect` give the screen positions back. Portrait sets
`compact`: the wobbler stands closer and the doors open square, so a rack cell is still 44 pt wide.

## The showcase (`ui/title_showcase.gd`)

| State | What happens | Input |
| --- | --- | --- |
| `IDLE` | The container hangs shut; the CONSTRUCTION (NEW) pill hangs under it. | The pill is a real Button (mouse, touch, keyboard, gamepad, screen reader). A tap on the container itself is ray-picked (`tap_at`, from the showcase's own `gui_input`). |
| `OPENING` | The hero controls and the column fade (`ui_changed`), the camera moves in, the crane lowers the container (dust, `land` + `clink`), the latch lifts, both doors swing open. | Back reverses it at once. Everything else is dropped. |
| `OPENED` | Racks: the pack's weapons and an arena badge. A tap (ray) or focus (one proxy Button per cell) puts the weapon in the wobbler's hand and the pack's hat on its head. | Back, `‹ SWAP PACK` / `SWAP PACK ›` (two packs or more), `TEST IN <ARENA>`, `UNLOCK PACK` or an OWNED badge, and the DON'T ENTER sign (the way on to the Construction title). |
| `SWAPPING` | Doors shut, the container is hoisted out of the picture, the next pack's comes down and opens. | Swap spam is ignored; a Back is remembered and runs after the landing. |
| `CLOSING` | Doors shut, the container goes back up, the camera and the title return. | A tap on the pill re-opens from where it is. |

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

- `npm run test:godot-title` (`godot/tests/title_showcase_test.gd`): the pack data, every dock / Play / chip / pill route,
  44 pt targets, dock words of 11 pt or more, no overlaps (logo, chips, container, pill, dock, Play, version) and the
  hero wobbler at 50 to 80 % of the screen height, at 852x393 / 667x375 / 932x430 (with phone insets); the state machine
  under spammed input with a second test-only pack; the test drive.
- `npm run test:godot-ui` checks the title home and the column on the `title` screen at every size and in French and
  Japanese (`_title_home`); `test:godot-quick-play` and `test:godot-dlc-ui` check Quick play in the dock and the pill.
- `sh tools/shoot-godot-ui.sh "" title title-owned title-site title-open title-open-owned title-weapon` writes
  `docs/style/godot-ui-title*.png` (`--pick N` chooses the rack cell for `title-weapon`; the shots give the profile a
  couple of claimable goals so the Goals badge shows).

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
