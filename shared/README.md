# shared/

Game content as JSON, exported from `public/index.html` by `tools/export-content.js`. The web game still uses its own copy; the Godot client loads these files.

- `weapons.json`, `modes.json` (`allowWeapons` is the `allow()` function evaluated for every weapon), `difficulties.json`, `crate-rates.json`, `cosmetics.json`
- `maps.json`: per map, the metadata (name, spawns, bot spots, sky colours…) and `geometry`: the collision boxes (`x,z` centre, `w,d` size, `h` height, `y` base), ladders, bounce pads and floor pads. Decor-only meshes are not exported. `pillars` has no boxes: its platforms are built in the mode code.

Do not edit by hand. After changing a table in `index.html` run `npm run content`. `npm test` fails when these files are out of date.
