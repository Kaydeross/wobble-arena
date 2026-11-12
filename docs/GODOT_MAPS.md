# Godot maps: audit and how they are built

Every web level is playable in the Godot app and looks like the web one: collision from `godot/data/maps.json`
(`tools/export-maps.js`, as before), everything else exported from the running web game.

## How a map is built (`godot/world/map_builder.gd`)

- **Collision and gameplay pieces** (as before): `maps.json` boxes (merged into one mesh per colour), ladders,
  bounce pads (with their per-pad `power`: 15, 16, 17 or 19), floor pads.
- **Restyled boxes**: some levels change a box after `addBox` (Crater Dome / Capsule glass walls at 14 % opacity,
  Toy Room's invisible walls, the Practice Range's grid colours). `map_look.json` `boxes` lists those by box index and
  `_add_boxes` applies them (also when a dynamic arena rebuilds the boxes).
- **Decor**: `godot/data/extra/decor/<map>.bin`, written by `npm run map-decor` (`tools/export-map-decor.js`). It loads
  the web game in headless Chromium, runs `loadMap(id)` for every level and bakes every mesh the level adds that is
  not a collision box, ladder, bounce pad or floor pad (trees, rocks, rings, snowmen, lamps and their glow, lava,
  candy, ships, ...), plus the far scenery ring (`buildFar`: mountains, city, mesas, sea, toys, lunar, ...), the clouds,
  the far hills and the void plane, into world space at t = 0. Triangles are grouped by material kind (lit, unlit,
  see-through, additive glow, lit see-through; fogged or not; casts / receives shadows) with per-vertex colour, so a
  level is **2-4 MeshInstances with 2-6 surfaces each** (up to ~30 on the lunar levels, whose far scenery has many
  opacities): still and moving pieces, each split into shadow casters and the rest. Moving pieces carry their motion
  per vertex (format `WAD2`, see the tool's header): the exporter runs the web game's backdrop anims for 8 s and fits
  each moving mesh as a steady rotation round a pivot (orbiting balloons, ships, asteroids; spinning turbines) plus a
  bob; leaves are flagged for wind and the void plane / sea for lava or water shimmer. The decor shader moves them.
  Flat shading comes from the shader (`dFdx`/`dFdy`), so no normals are stored. Positions are 16-bit in the group's
  box, 6 MB for all 35 levels. Static decor costs nothing per frame; loading a level's decor takes 1-6 ms.
- **Look**: `godot/data/extra/map_look.json` (same export): the 12 sky bands after `setBackdrop`, fog colour / range,
  the hemisphere sky / ground colours and intensity and the sun colour / intensity after `gradeLook`, the sun disc
  colour, size and direction, night (moon and stars), the horizon haze colour. `make_environment` turns the bands into
  a sky shader (gradient, sun disc with two glows, three haze layers, moon and stars at night; no `TIME`, so the sky
  is not re-rendered every frame); indoor levels (Practice Range) get a flat background.
- **Custom level** (`custom`, Sandbox): `MapBuilder.custom_map(cfg)` is a port of `MAPS.custom.build` with the same
  seeded random numbers (mulberry32 via `Dynamics.imul`), themes, obstacle / platform / wall / pad placement, ice grip
  and player blocks; `MapBuilder.build("custom")` uses the defaults. The grass theme uses the exported meadow decor,
  the other themes the plain hills and void in their colours.
- **Mechanics**: ice grip (`grip`, `FighterPhysics.ice_grip`), shrink / squeeze floors (`ModeRules.SHRINK`, the world
  draws the shrinking first box), domes (`ceil`, `FighterPhysics.ceil_y`), bounce pad power, dynamic arenas
  (`ArenaDyn`; `rebuild_boxes` keeps the restyled boxes) all work as before.

Re-export after changing a level in `public/index.html`: `npm run content` (collision), then `npm run map-decor`
(decor and look, needs network for three.js), then `sh tools/shoot-godot-maps.sh thumbs` (wizard card art).

## Arena lists and thumbnails

`ModeRules.MODE_MAPS` now matches the web game's final `MODES[k].maps` (index.html ~3713-3727: the new and big
arenas for Melee, Guns, Duel and 2v2, Ninja's Dojo / Grand Arena / Fortress, Giant's Toy Room + big arenas,
Explosive, Moon Drift), only adding maps (3v3 / 4v4 keep the small team maps as well as the big ones). Lists follow the
web `MAP_ORDER`. Classic-style modes (Classic, Weapon Ladder, Team Deathmatch, Deathmatch, Sudden Death) get every
map that does not belong to another mode (`only`); exclusive maps (Site Yard, Dojo, Blast Zone, ...) only show in
their own mode. Each arena card shows a picture of the level, `godot/ui/map_thumbs/<id>.jpg` (360x92, 384 KB in all),
rendered once from the real Godot map by `sh tools/shoot-godot-maps.sh thumbs`; the old colour strip is the fallback.

## Audit (`npm run test:godot-maps`, `--verbose` prints this per map)

`godot/tests/maps_test.gd` builds every map in `maps.json` and `custom`, and checks: it builds, its solids, ladders,
bounce pads and floor pads equal the web export, every spawn / bot start / player start lands on a solid top (dropped
from 4 m when it has no height, like `check-maps.js`) and not inside a wall, the decor and look load and the decor
indices are in range. Custom levels for three settings must match the web generator box for box (the runner evaluates
`MAPS.custom.build` from `public/index.html`). Every wizard mode must list only existing maps, never another mode's
exclusive map, and classic-style modes every open map.

| Map | Solids / ladders / pads / floor pads (= web) | Spawns on ground | Decor tris | Sky | Mechanics | Still in Godot |
|---|---|---|---|---|---|---|
| test | 1/0/0/0 | 12 ok | 6130 | sky | range dummies | specks:pollen, birds |
| practice | 12/0/0/0 | 12 ok | 734 | indoor | range dummies | - |
| arena | 8/1/0/1 | 13 ok | 8714 | sky | - | 3 moving backdrop pieces, specks:pollen, birds |
| park | 9/0/6/1 | 13 ok | 9154 | sky | - | 3 moving backdrop pieces, specks:pollen, birds |
| ice | 8/0/0/1 | 13 ok | 7972 | sky | ice grip 0.2 | specks:snow, birds |
| temple | 81/0/4/1 | 14 ok | 10406 | sky | - | specks:petal, birds |
| rooftops | 66/4/0/1 | 12 ok | 8314 | sky | - | specks:ember, birds |
| shrink | 1/0/0/0 | 12 ok | 5762 | sky | shrinks | specks:pollen, birds |
| squeeze | 5/0/0/0 | 12 ok | 1558 | sky | shrinks | 2 moving backdrop pieces, specks:ember |
| tower | 35/2/4/1 | 12 ok | 9014 | sky | pad power [19.0] | 4 moving backdrop pieces, specks:pollen, birds |
| arenaxl | 10/2/0/1 | 17 ok | 9054 | sky | - | 4 moving backdrop pieces, specks:pollen, birds |
| rinkxl | 14/0/0/1 | 17 ok | 7980 | sky | ice grip 0.2 | specks:snow, birds |
| colosseum | 43/0/0/1 | 17 ok | 7122 | sky | - | specks:dust, birds |
| fortress | 20/6/0/1 | 17 ok | 13580 | sky | - | specks:dust, birds |
| moonbase | 19/4/0/1 | 12 ok | 17184 | night | - | 49 moving backdrop pieces, specks:star |
| volcano | 22/0/0/5 | 12 ok | 4584 | sky | - | 2 moving backdrop pieces, specks:ember |
| candy | 45/0/0/1 | 12 ok | 38338 | sky | - | specks:confetti, birds |
| pirate | 38/0/0/1 | 12 ok | 7256 | sky | - | 4 moving backdrop pieces, specks:bubble, birds |
| haunted | 36/2/0/1 | 12 ok | 14648 | night | - | 29 moving backdrop pieces, specks:wisp, birds |
| beach | 24/0/0/1 | 12 ok | 7158 | sky | - | 3 moving backdrop pieces, specks:petal, birds |
| dojo | 75/0/0/1 | 12 ok | 6994 | night | - | 2 moving backdrop pieces, specks:petal |
| blast | 92/0/2/1 | 16 ok | 4392 | sky | - | 4 moving backdrop pieces, specks:ember, birds |
| siteyard | 88/0/2/1 | 16 ok | 4642 | sky | - | 4 moving backdrop pieces, specks:dust, birds |
| gunrange | 114/0/2/1 | 16 ok | 4326 | sky | - | 5 moving backdrop pieces, specks:pollen, birds |
| brawlpit | 62/0/4/1 | 16 ok | 1734 | night | - | 2 moving backdrop pieces, specks:ember |
| craterdome | 15/0/0/1 | 16 ok | 17968 | night | dome ceil 24.0 | 51 moving backdrop pieces, specks:star |
| capsule | 12/0/0/0 | 16 ok | 17788 | night | dome ceil 20.0 | 51 moving backdrop pieces, specks:star |
| pillars | 0/0/0/0 | 1 ok (dynamic floor) | 5130 | sky | moving pillars (Pillars mode) | 12 moving backdrop pieces, specks:bubble, birds |
| playroom | 82/0/6/1 | 16 ok | 10138 | sky | - | 3 moving backdrop pieces, specks:pollen, birds |
| farm | 94/0/1/1 | 18 ok | 40676 | sky | - | 20 moving backdrop pieces, specks:pollen, birds |
| crossroads | 14/0/4/0 | 12 ok | 6628 | night | pad power [15.0] | 2 moving backdrop pieces, specks:star |
| donut | 18/0/2/0 | 12 ok | 6578 | sky | pad power [16.0] | specks:confetti, birds |
| chasm | 20/0/2/0 | 12 ok | 6140 | sky | pad power [16.0] | specks:ember, birds |
| summit | 12/0/2/0 | 12 ok | 6120 | sky | pad power [15.0] | specks:petal, birds |
| custom | 11/0/3/1 | 12 ok | 8422 | sky | - | 2 moving backdrop pieces, specks:pollen, birds |

Everything builds and every spawn is on solid ground. Pillars has no boxes: its pillars come from the Pillars mode,
which the port does not play yet (the map is not offered; its decor and look are exported).

## Known gaps

- Moving backdrop pieces now move (vertex shader, `docs/GRAPHICS.md`), fitted as rotation + bob: smoke puffs bob
  instead of rising and looping, and pieces that blink or rescale (searchlights, comets) keep their t = 0 look.
  Drifting specks (pollen, snow, embers, ...) and circling birds / bats are still not drawn. The baked web clouds stay
  put; MID / HIGH add a drifting flat cloud layer above them.
- Lighting is close but not identical: Godot's ambient is one colour (80 % hemisphere sky, 20 % ground), the web's
  hemisphere light shades side faces darker. Depth fog in Godot tints far objects a little darker than three.js.
- Textured materials are flattened to their colour (the Practice Range's prototype grid is a shader on MID / HIGH),
  the glow blob is a radial falloff in the shader. Lamp sprites and the sun rays / halo are not drawn.
- The Practice Range's still and moving dummies (`range.movers`) are not ported: bots there play normally.
- Custom levels in themes other than grass use the plain hills and void, not the meadow scenery.
