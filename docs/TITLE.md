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

## Pack selector (`ui/pack_selector.gd`)

`PackSelector` (a `UiPage`) is the carousel of every pack. It is reached from the opened container's top-left **Packs**
chip (`TitleShowcase.packs_requested` -> `main.open_packs(pack_id)`), so the idle title stays as clean as above. The cards
come from `PackRegistry.ids()` (the hub's `order`) and `DLCPacks`; nothing in the selector is hard-coded per pack except the
icon triple (`ICONS`) and the rail pattern drawn by `art()` (see "How to add a fifth pack" in `CONSTRUCTION_DLC.md`).

- **Layout**: the centred card is scaled up, the side cards (`SIDE_SCALE`) are smaller and dimmed, and each layer of a card (badge,
  weapon icons, pattern rail, backdrop glow) moves with its own parallax.
- **Input**: swipe (a drag of 14 px or more; a tap on a side card centres it), the two arrows, the page dots (in the header, or
  their own row in portrait), Left / Right and the pad. The position is **clamped** at both ends (a drag may overshoot by
  0.25 of a card, then eases back). It eases to the target with `pos = lerp(pos, target, 1 - exp(-12 dt))`, so it is
  frame-rate independent.
- **Buttons**: the big button says PLAY (owned) or UNLOCK PACK (locked). UNLOCK PACK emits `unlock_requested` (the existing hub card:
  coins or the code). PLAY plays the pack's transition and the hub opens at its switch point (`play_requested` ->
  `main._open_hub_from_selector`); the hub's Back returns to the selector. While a transition runs (`busy`) ENTER is ignored and a
  second press skips it.
- **Secret code**: stays in Settings > About (seven taps) and, when allowed (see "Tester unlock" below), unlocks every pack
  (`DlcUnlock.redeem_with`).

## Per-pack smoothed transitions (`ui/pack_transition.gd`)

`PackTransition.play(pack_id, parent, on_done, on_end)` draws one transition per pack, 1.15 to 1.35 s (`DURATION`), chosen by
`style_for(id)`:

| Pack | Style | What it is |
| --- | --- | --- |
| construction | `site` | the hazard-tape wipe (`ui/dlc_transition.gd`, untouched) |
| kitchen | `fire` | a flame wall (`shaders/pack_flame_wipe.gdshader`, the only shader), embers and a frying-pan CLANG |
| xmas | `xmas` | snow swirl, wrapping paper, a ribbon cross and a bow that unwraps again |
| australia | `outback` | three layers of dust, a sunburst, a spinning boomerang with streaks and a whip crack |

Each is a function of one number `p` (cover 0 to 0.45, `on_done` at 0.5 = the moment the hub opens behind it, reveal 0.55 to 1),
so it is smooth and can be scrubbed in a test. The lowest graphics tier (Settings > Graphics > Effects: Low, or the web build,
`tier_lite()`) plays a plain colour wipe (`lite`). A tap, key or pad button skips it, a safety timer ends it at 2x its length + 1 s,
and headless runs end it at once with the same callbacks. At most 60 particles, drawn from fixed arrays with a local
`RandomNumberGenerator` (seeded from the pack id, so a screenshot is reproducible). An unknown pack id falls back to `lite`.

## 3D landing pages (`ui/pack_landing*.gd`)

Every pack's hub (`dlc/construction/construction_hub.gd` serves all packs) opens on a landing page, `PackLanding`
(`ui/pack_landing.gd`), built from `godot/data/extra/<pack>/landing.json` (palette, `headline`, `tagline`, three `features`,
`weapon_roles`, the dressed `wobbler`, `arena_seed`; every text is an English `tr()` key).

| Part | File | What |
| --- | --- | --- |
| Backdrop | `pack_landing_scene.gd` | the pack's two colours top to bottom; Construction adds a crane and hazard-tape overlay (CPUParticles2D) |
| Hero band | `pack_landing.gd` | badge, title lockup, stage slot, weapon name and role, arena thumbnail and features; it takes only the height the cards leave (shows what fits: under `MIN_H` nothing, short bands the lockup, stage, caption and features, tall ones also the arena) |
| Arena thumbnail | `pack_landing_arena.gd` | a still top-down picture drawn once from the arena's own boxes (`PackMaps.generate`) |
| 3D stage | `pack_landing_stage.gd` | the ONE `SubViewport` of the page, reused for every pack and weapon, no MSAA, at most 520 k pixels, rendered only while the band is on screen; `frame()` puts the subject into the stage slot with a shifted-lens camera so the scenery runs on behind the texts |
| 3D set | `pack_landing_set.gd` | the lit low-poly scene built in code, chosen by `kind` (`KINDS`) |

The three sets (`PackLandingSet`, all primitives, no image files):

- **kitchen**: tiled wall, a stainless prep counter the Wobbler stands behind, pots on a swinging rail, a stove with glowing burners
  (one small flickering OmniLight), a hood, pendant lamps; the weapon turns on a turntable on the counter.
- **xmas** (snow globe): the Wobbler inside a glass sphere (a small fresnel shader), a red base with a gold band, a mini tree and
  gifts, snow falling inside the glass, fairy lights on the wall; `shake()` swirls the snow.
- **australia** (desert suburb): red dirt, a big sun, a corrugated fence, low-poly houses, gum trees, a turning Hills Hoist with
  washing and a kangaroo (idle bob, ear twitch; `shake()` makes it hop).

Tap the stage (or wait `CYCLE_S`, 3.6 s) to see the pack's next weapon on the turntable (the real `WeaponModels.build(id)`).

Budgets (checked by `tests/pack_landing_test.gd`): one SubViewport; at most `MESH_CAP` = 250 mesh instances for the whole stage (the
Australia set uses 244, so there is no room left: check before adding props); `PARTICLE_CAP` = 100 particles for the whole page;
nothing allocated per frame; everything paused while the hub is hidden or covered. The key light casts the page's one cheap
orthogonal shadow, never on the lowest tier. Lowest graphics tier (`Tier.q() == 0`): no particles and the stage renders once per
change. Headless: no stage, 3D or particles (the layout nodes stay so tests read the texts and buttons); `PackLanding.force_fx = true`
builds them anyway. Visual code only: random numbers come from a local `RandomNumberGenerator`, never `combat.rng`.

Known polish gaps: outside the hero band the page is a flat gradient, the stage slot shows as a brighter window, portrait keeps the
older small band, and no iPhone frame times have been measured for the sets.

## Tester unlock (`tester_unlock`)

The secret code (and the seven-tap entry in Settings > About) works in debug and editor builds always. In a **release** build
(TestFlight, App Store) it works only while the remote config flag `tester_unlock` is a real JSON `true`:

- `DlcUnlock.dev_code_allowed()` = `not is_release() or tester_unlock()`; `tester_unlock()` reads `RemoteConfig.get_value("tester_unlock")`
  at call time, so a refreshed config applies at the next attempt.
- `RemoteConfig.validate` accepts only a real boolean `true` (`"true"`, `1`, `"yes"` count as false). Default `false` in the client,
  in the bundled `godot/data/extra/remote_config.json` and in the server's `remote-config.json`.
- Turn it on for testers with `TESTER_UNLOCK=1` (or `true` / `yes`) on the server, or `"tester_unlock": true` in the file the host reads
  for `/api/config`. Check `curl -s https://play.<your-domain>/api/config`. **Turn it off before the App Store** (checklist item in
  `OWNER_RELEASE_RUNBOOK.md` 4.9; wire format in `PROTOCOL.md`).
- One right code unlocks all packs (`redeem_with`: unlock everything plus `grant_owned`). Tests: `npm run test:godot-pack-selector`
  (section 3) and `godot/tests/remote_config_test.gd`.

## Tests and screenshots (selector, transitions, landing)

- `npm run test:godot-pack-selector`: the carousel, clamping, buttons, transitions (every style, skip, lite tier) and the tester switch.
  Images: `godot/tests/pack_selector_shots.gd` (windowed Godot, run by hand).
- `npm run test:godot-pack-landing`: the landing page for every pack, texts in five languages, one SubViewport, mesh and particle
  budgets, tiers, and the hub layout at five phone and tablet sizes. Images: `godot/tests/pack_landing_shots.gd`.
