# Pack #2 (WP 1.0-C) — content specification and pipeline audit

**Status:** specification, ready to execute. Written against `origin/main` at `08a89b2` (0.5.0). Analysis + documentation
only: this document adds no gameplay code.

**What it specifies.** Pack #2 is the second paid, data-only content pack in the 1.0 line ("Pack #2 (1.0-C)" in the
owner's revised plan, `docs/REVISED_PLAN.md` in the owner's checkout — that file is not committed in this branch, so
everything a worker needs is repeated here). Pack #1 is the Construction DLC (`docs/CONSTRUCTION_DLC.md`,
`godot/data/extra/construction/`). Pack #2 uses the same machinery and the same commercial rule: **bought with coins
inside the game, no platform/IAP entitlement**.

Read alongside: `docs/CONSTRUCTION_DLC.md` (pack manifest, "How to add a DLC pack with zero code"),
`docs/GODOT_ARCH.md` (DLC packs, JSON cache), `docs/WRITING.md` (every player-facing string), `docs/I18N.md`
(translations and fonts). Nothing in this document overrides the parity rules in `docs/GODOT_ARCH.md`.

---

## 1. Contents at a glance

Pack id **`kitchen`**, display name **Kitchen**, subtitle **"9 Tools + The Café"**. Theme: a greasy-spoon café —
front of house, back of house, and everything in it is a weapon. It is deliberately a different flavour from
Construction's worksite while reusing exactly the same systems (no new combat code).

| # | Kind | id | English name (i18n key) | Lives in |
|---|---|---|---|---|
| 1 | weapon | `fryingpan` | Frying Pan | `godot/data/extra/kitchen/weapons.json` |
| 2 | weapon | `rollingpin` | Rolling Pin | same |
| 3 | weapon | `cleaver` | Cleaver | same |
| 4 | weapon | `ladle` | Ladle | same |
| 5 | weapon | `tenderiser` | Tenderiser | same |
| 6 | weapon | `peppermill` | Pepper Mill | same |
| 7 | weapon | `ketchup` | Ketchup Gun | same |
| 8 | weapon | `blender` | Blender | same |
| 9 | weapon | `potlid` | Pot Lid | same |
| 10 | arena | `cafe` | The Café | `public/index.html` `MAPS` → `shared/maps.json` → `godot/data/maps.json` |
| 11 | arena | `galley` | The Galley | same |
| 12 | mode | `cookoff` | Cook-off | `godot/data/extra/kitchen/modes.json` (front end needs 3 Godot consts, §8.3) |
| 13 | class | `cook` | Cook | `godot/data/extra/kitchen/classes.json` (ownership hook in PR 4) |
| 14 | outfit | `linecook` | Line Cook | `public/index.html` `SKINS`/`SKIN_SHOP` + `godot/data/extra/locker.json` |
| 15 | outfit | `souschef` | Sous-Chef | same |
| 16 | outfit | `potwash` | Pot Wash | same |

**Count:** 9 tools, 2 arenas, 1 mode, 1 class, 3 outfits (16 content items). No new hats, no emotes, no Arcade stages
(see §9). The title showcase's pack container uses the existing `chef` hat as its preview badge — no new hat geometry.

**Price:** 1500 coins, the same as the Construction DLC (`godot/dlc/construction/dlc_unlock.gd:9` `PRICE`). No separate
store entitlement, no receipt, no restore-purchases: ownership is a client-side save flag exactly like Construction
today, and the pack ships **after** WP 1.0-A (server wallet) so the 1500 coins are deducted by server-owned state.

---

## 2. Where each piece lives — and what must not be hand-edited

| Content | Source of truth (edit this) | Generated (never hand-edit) |
|---|---|---|
| tools, mode, class | `godot/data/extra/kitchen/*.json` (Godot-only, a DLC pack) | — |
| arenas | `public/index.html` (`MAPS` object; the web `MAP_ORDER` for display order) | `shared/maps.json`, `godot/data/maps.json` (`npm run content`) |
| outfits | `public/index.html` (`SKINS`, `SKIN_SHOP`) **and** the hand-maintained Godot copy `godot/data/extra/locker.json` (`skin_shop`) | `shared/cosmetics.json`, `godot/data/cosmetics.json` (`npm run content`) |
| strings | `godot/i18n/src/9a-kitchen-data.json` (+ `godot/data/extra/wizard.json` for the mode card's `short`/icon) | `godot/i18n/strings.json`, `public/i18n-data.js` (`node tools/i18n.js`) |
| mode card metadata | `godot/data/extra/wizard.json` `modes.cookoff` | — |
| pack name + subtitle | `godot/dlc/packs/kitchen.tres` + the i18n file (`display_name`/`subtitle` are i18n keys) | — |
| fonts / CJK coverage | owner-only: `python3 tools/subset-fonts.py <Noto dir>` | `godot/ui/fonts/NotoSans*-Subset.otf`, `public/fonts/*.woff2`, `tools/cjk-coverage.json` |

**Never hand-edit** `shared/*.json`, `godot/data/*.json` (all of them — only `godot/data/extra/` is hand-owned),
`godot/i18n/strings.json`, `public/i18n-data.js`, `tools/cjk-coverage.json`, or the subset fonts. `npm test` fails when
`shared/` or `godot/data/` drift from `public/index.html` (`npm run content -- --check`), when the i18n build is stale, or
when a CJK glyph is missing.

Data files that stay *outside* the pack folder (the pack manifest schema has no section for them today, §8.3):
`godot/data/extra/wizard.json` (mode card), `godot/data/extra/locker.json` (outfit prices), `godot/dlc/packs/*.tres`
(title showcase).

---

## 3. Data schemas and worked examples

### 3.1 `godot/data/extra/kitchen/pack.json` (manifest)

Schema and validation rules are in `godot/autoload/content.gd:219-291` (`_read_pack`); the shipped Construction example is
`godot/data/extra/construction/pack.json`. Consumed sections are `weapons`, `classes`, `modes`, `stages`
(`PACK_SECTIONS`, `content.gd:110`); `maps`, `cosmetics`, `strings` are reserved and **ignored with a warning**
(`PACK_RESERVED`, `content.gd:112`).

```json
{
  "_readme": "Kitchen DLC pack manifest (docs/PACK2_SPEC.md). Files are relative to this folder. See docs/CONSTRUCTION_DLC.md 'DLC pack manifest' for the section rules. A malformed manifest is push_error'd and the pack is skipped; the game keeps running.",
  "id": "kitchen",
  "name": "Kitchen",
  "version": 1,
  "requires": [],
  "weapons": "weapons.json",
  "modes": "modes.json",
  "classes": "classes.json"
}
```

Rules a worker must satisfy (all enforced by the loader or the pack test):
`id` equals the folder name and matches `^[a-z][a-z0-9_-]*$`; `name` non-empty; `version` integer ≥ 1;
every declared path is a file inside the folder that parses as a JSON object; no absolute paths, `..`, or `://`;
two packs must not define the same table key (first sorted id wins + `push_error`); unknown top-level keys are warned and
ignored, `_`-prefixed keys are comments.

Do **not** declare `maps`, `cosmetics` or `strings`: they would be silently ignored today, and the test asserts the manifest
declares only the three sections above.

### 3.2 Weapon (`weapons.json`)

The `shared/weapons.json` shape (`public/index.html` `WEAPONS`), plus the Godot-only tag. The loader merges these into
`Content.weapons`/`Combat.weapons_data` without overriding shared weapons (`godot/logic/extra_weapons.gd:20-31`); only
weapons whose types the port already simulates are allowed (no new weapon code, no new projectile behaviour):

| field | required for | rule |
|---|---|---|
| `name` | all | English i18n key, unique |
| `type` | all | one of `melee`, `gun`, `ball`, `knife` |
| `cooldown`, `stiff`, `dmg`, `force`, `ammo`, `speedMul` | all | `cooldown>0`, `stiff>0`, `dmg>=0`, `force>=0`, `ammo>0` int, `speedMul>0` |
| `color` | all | int `0xRRGGBB` |
| `kitchenOnly` | all | `true` (documentary tag mirroring `constructionOnly`; asserted by the pack test, used by nothing at runtime) |
| `swingTime`, `tip`, `thick`, `lift`, `topple`, `hitSfx` | melee | `swingTime>0`, `tip>0`, `thick>0`, `hitSfx` in `whack`/`clink` |
| `pellets`, `range`, `spread`, `mag`, `reload`, `rtype:"mag"`, `recoil`, `muzzle` | gun, default style | — |
| `range`, `maxForce`, `topple`, `recoil`, `muzzle`, `spread:0` | gun, `"style":"punch"` | close-range melee-gun |
| `range`, `burn`, `botBurst`, `recoil`, `muzzle` | gun, `"style":"flame"` | `burn>0` |
| `throwSpeed`, `muzzle` | ball | `throwSpeed>0` |
| `speed`, `assist`, `muzzle` | knife (thrown) | `speed>0` |

Optional, Godot-only tuning overlay: `godot/data/extra/weapon_tuning.json` (only applies while `Combat.tuning_active()`,
i.e. offline or `net_zones`; do not edit for parity reasons unless the PR says so).

Worked example — `fryingpan` in `godot/data/extra/kitchen/weapons.json`:

```json
{
 "fryingpan": {
  "name": "Frying Pan",
  "type": "melee",
  "cooldown": 1.05,
  "swingTime": 0.5,
  "stiff": 30,
  "dmg": 36,
  "force": 25,
  "tip": 1.85,
  "thick": 0.48,
  "lift": 0.32,
  "topple": 0.62,
  "hitSfx": "whack",
  "speedMul": 0.88,
  "ammo": 6,
  "kitchenOnly": true,
  "color": 4935509
 }
}
```

Reference stats for the other eight (the numbers matter for the balance smoke test, not for parity — these weapons exist
only in the Godot build): `rollingpin` melee 24 dmg / 2.7 m tip / 0.68 s cooldown / 8 ammo; `cleaver` melee 46 dmg / 1.5 m tip
/ 1.3 s cooldown / 5 ammo; `ladle` melee 15 dmg / 2.4 m tip / 0.42 s cooldown / 12 ammo; `tenderiser` melee 13 dmg / 1.3 m tip
/ 0.30 s cooldown / 18 ammo; `peppermill` gun style `punch`, 11 dmg, range 5.0, 22 ammo; `ketchup` gun, 3 pellets of 7 dmg,
range 13, mag 12 / 24 ammo, reload 1.5 s; `blender` gun style `flame`, 1.8 dmg/tick, range 5.2, `burn` 1.6, 44 ammo;
`potlid` knife (thrown), 30 dmg, speed 27, 6 ammo. Every one carries `"kitchenOnly": true`, a `color`, `speedMul` and
`stiff`; use the values in the PR description table as the balance baseline and let `test:godot-kitchen-pack`'s smoke pass
judge them.

`godot/actors/weapon_models.gd` builds held models by weapon id (`build()` match); nine new ids fall back to the grey
placeholder block until PR 3 adds them, which is the one piece of pack code that is purely visual (no parity impact).

### 3.3 Mode (`modes.json`)

Schema = `shared/modes.json` mode shape (exported from `MODES` in `public/index.html`) plus the additive Godot-only hooks
`allowWeapons`/`dropWeights` (`godot/logic/mode_rules.gd:178-214`, `_merge_modes_file`). A mode id that does not exist in
`shared/modes.json` is added whole; its crate pool comes from `dropWeights` because the exported `drops.json` has no
`allow` list for it (`godot/logic/pickups.gd:53-80`: a key is allowed when the mode's `dropWeights` names it). That is why
the nine tools **and** the heal/power-ups must all be weighted here.

```json
{
 "_note": "Kitchen DLC mode: a new, offline-only mode. Its crate pool is entirely in dropWeights (drops.json has no 'cookoff' allow list); heal/power-ups are copied from drops.json base weights.",
 "cookoff": {
  "name": "Cook-off",
  "desc": "Everything in the kitchen is a weapon. Grab whatever's nearest and swing",
  "start": "fryingpan",
  "preset": { "limit": 20 },
  "allowWeapons": ["fryingpan", "rollingpin", "cleaver", "ladle", "tenderiser", "peppermill", "ketchup", "blender", "potlid"],
  "dropWeights": {
   "fryingpan": 0.9, "rollingpin": 0.8, "cleaver": 0.6, "ladle": 0.8, "tenderiser": 0.8,
   "peppermill": 0.7, "ketchup": 0.7, "blender": 0.5, "potlid": 0.7,
   "heal": 3.2, "shield": 0.8, "speed": 0.9, "rage": 0.7
  }
 }
}
```

`preset.limit: 20` is the K.O. limit (`ModeRules.preset_limit`, `mode_rules.gd:117-121`) — the mode is not in
`LIMITLESS_BRAWL`, so without it the match never ends. Do not set `teams` (free-for-all). Front-end visibility needs
`ModeRules.PLAYABLE`, `MODE_MAPS` and `OFFLINE_ONLY` entries (PR 3, §8.3); the mode data alone is inert.

### 3.4 Class (`classes.json`)

Same shape as `godot/data/extra/classes.json` (built-in extras win over a pack), multipliers only:
`name`, `tag`, `hp`, `spd`, `acc`, `air`, `jump`, `kb`, `dmg`, `rate`, `reload`, `ammo`, `wob`, `size`, `head`, `wide`,
plus optional `skin`/`icon`/`rar`, plus the new `pack` field used by the ownership hook (PR 4). No `price` (it must not
appear in the Shop's coin list) and no `unlock`/`hidden` (it is not a secret).

```json
{
 "cook": {
  "name": "Cook",
  "icon": "",
  "tag": "Fast hands, hot pans. Never turn your back on the fryer",
  "hp": 0.95,
  "spd": 1.1,
  "acc": 1.15,
  "air": 1.0,
  "jump": 1.0,
  "kb": 1.1,
  "dmg": 0.95,
  "rate": 1.15,
  "reload": 0.9,
  "ammo": 1.1,
  "wob": 0.9,
  "size": 0.98,
  "head": 1.05,
  "wide": 0.95,
  "rar": "epic",
  "pack": "kitchen"
 }
}
```

Bots never pick extra classes (`MatchSim.BOT_CLASS_ORDER`), so bot/parity tests are untouched. Until the PR 4 ownership
hook lands, an extra class with no `price`, no `unlock` and `hidden` absent is simply not owned
(`godot/autoload/save.gd:359-364`), i.e. invisible and harmless; the pack test asserts that.

### 3.5 Arena (`public/index.html` `MAPS`)

Arenas are **shared data**, not a pack section: the pack schema has no `maps` section (`content.gd:112` reserves and
ignores it), and there is no Godot-only maps overlay. That is also how Pack #1's `siteyard` arena ships
(`shared/maps.json`). Consequently a Pack #2 arena is visible to the web game's data too, but unplayable there because
`only: "cookoff"` and `cookoff` does not exist in the web `MODES` (`public/index.html:8662` `mapAllowed`). This is the only
zero-Godot-code way to add arenas; a generated arena (like `sitegen`) would be a code change and is a non-goal.

Authoring form (in `public/index.html`, next to the other `MAPS.<id> = { … }` entries; `addBox`, `addLadder`,
`addBouncePad`, `addFloorPad`; decorative meshes are not exported):

```js
MAPS.cafe = {
  name: 'The Café', cat: 'obstacle', tags: ['Food', 'Indoor', 'Cover'], only: 'cookoff',
  blurb: 'Booths, a counter and a jukebox. Open edges, so one good swing sends you out for a breath of fresh air.',
  hemi: 0.9, sunI: 0.95,
  sky: 0xd9a66a, skyTop: 0x6a4a3a, voidColor: 0x3a2a22, hills: [0x6a4a38, 0x7a5642, 0x5c3f30, 0x8a6650],
  shadow: 44, orbit: 50, orbitH: 30,
  spawns: [[-16, -6], [16, 6], [-16, 10], [16, -10], [0, 18], [0, -18], [-8, 16], [8, -16]],
  player: [0, 18],
  bots: [[-16, -6], [16, 6], [-16, 10], [16, -10], [0, -18], [-8, 16], [8, -16]],
  wander: 20,
  drops: [[-12, 0], [12, 0], [0, -8], [0, 12], [-16, -16], [16, 16], [-16, 16], [16, -16], [0, 0, 1.6]],
  build() {
    addBox(0, 0, 44, 44, 2, 0x6b4f3a, -2); addFloorPad(40, 0x8a6a50);                        // the scuffed café floor
    addBox(0, -14, 26, 2.4, 1.1, 0x7a3b2e); addBox(0, -14, 26.4, 2.8, 0.15, 0xc9a06a, 1.1);   // counter + top
    for (const [x, z] of [[-14, -4], [14, -4], [-14, 8], [14, 8], [-8, 14], [8, 14]]) {       // booth tables and seats
      addBox(x, z, 3.2, 3.2, 0.9, 0x8a4a34); addBox(x - 3, z, 1.0, 4.0, 0.6, 0x4a2e24); addBox(x + 3, z, 1.0, 4.0, 0.6, 0x4a2e24);
    }
    addBox(-16, -16, 2.2, 1.4, 2.4, 0x2a2a32);                                                 // jukebox
    addBox(16, -16, 3.0, 2.0, 1.2, 0xb8c0c8);                                                  // pie display
    addBouncePad(0, -18); addBouncePad(0, 18);
  },
};
```

The exported shape (what actually lands in `shared/maps.json` via `npm run content`, and what the pack test checks) is the
map's non-function keys plus `geometry`; decor meshes are dropped:

```json
{
 "name": "The Café", "cat": "obstacle", "tags": ["Food", "Indoor", "Cover"], "only": "cookoff",
 "blurb": "Booths, a counter and a jukebox. Open edges, so one good swing sends you out for a breath of fresh air.",
 "hemi": 0.9, "sunI": 0.95,
 "sky": 14263914, "skyTop": 6965818, "voidColor": 3811874, "hills": [6965816, 8017474, 6045488, 9070160],
 "shadow": 44, "orbit": 50, "orbitH": 30,
 "spawns": [[-16, -6], [16, 6], [-16, 10], [16, -10], [0, 18], [0, -18], [-8, 16], [8, -16]],
 "player": [0, 18],
 "bots": [[-16, -6], [16, 6], [-16, 10], [16, -10], [0, -18], [-8, 16], [8, -16]],
 "wander": 20,
 "drops": [[-12, 0], [12, 0], [0, -8], [0, 12], [-16, -16], [16, 16], [-16, 16], [16, -16], [0, 0, 1.6]],
 "geometry": {
  "boxes": [{"x": 0, "z": 0, "w": 44, "d": 44, "h": 2, "y": -2, "color": 7032634}],
  "ladders": [],
  "bouncePads": [{"x": 0, "z": -18, "r": 1.2, "power": 17}, {"x": 0, "z": 18, "r": 1.2, "power": 17}],
  "floorPads": [{"size": 40, "color": 9071184}]
 }
}
```

(The `boxes` list is abridged — the real file also carries the counter, table, seat, jukebox and pie-display boxes above;
every other field is exactly what `npm run content` writes for the `MAPS.cafe` source entry. Values are the decimal form of
the `0x…` colours in the web source, as `export-content.js` writes them.) Requirements:

- **`check-maps` is the design gate** (`tools/check-maps.js`, part of `npm test`): every spawn/bot start/drop must be on
  something standable and not inside a wall; every spawn must be reachable from every other spawn by walk/jump/ladder/pad;
  no pit you can fall into and never leave. Author on a grid and run `node tools/check-maps.js cafe galley` while iterating.
- `MAPS` entries are added after the `const MAPS = { … };` literal (`MAPS.cafe = { … };`) or inside it; either is exported.
  Adding the ids to the **web** `MAP_ORDER` (`public/index.html:4096`) is optional and ordering-only (unknown ids are
  appended), but it keeps the exported `shared/maps.json` order stable and the web data tidy.
- Add `cafe` and `galley` to the Godot `ModeRules.MAP_ORDER` (`godot/logic/mode_rules.gd:82-84`, sorting only) and to
  `ModeRules.MODE_MAPS["cookoff"]` (PR 3) so the mode lists exactly its two arenas.
- The Godot look (`godot/data/extra/map_look.json` + `godot/data/extra/decor/`) is generated by `npm run map-decor`
  (needs network + Playwright chromium) and is **optional**: `MapBuilder.look()` returns `{}` and the map renders with
  native hills/void when absent (`godot/world/map_builder.gd:271-279`). Do not hand-write those files.
- `The Galley` is the second map, same rules: a tight back-of-house room (island, pass, shelves), `only: "cookoff"`.

### 3.6 Outfits (`cosmetics.json` + `locker.json`)

Outfits are data-only colour schemes (`col`, `tone`, `pants`, `shoes`, `icon`, `name`) — no geometry code. Add each to the
web `SKINS` and `SKIN_SHOP` (`public/index.html`), then run `npm run content`, and copy the price/rarity pair by hand into
`godot/data/extra/locker.json` `skin_shop` (that file is a hand-maintained Godot copy; `godot/tests/save_test.gd:171-176`
checks every `skin_shop` price against the web source, so a mismatch fails `test:godot-save`).

```js
// public/index.html, SKINS
linecook: { name: 'Line Cook', icon: '🍳', col: 0xd8d8d8, tone: 0xe8c0a0, pants: 0x2a2a32, shoes: 0x1c1c22 },
```
```json
// godot/data/extra/locker.json, skin_shop
"linecook": [600, "uncommon"],
```
Same for `souschef` (900, rare) and `potwash` (450, uncommon; a rubber-glove look). These are regular coin-shop outfits,
**not** pack-gated: they are content shipped alongside Pack #2, exactly like any other shop outfit (pack-exclusive
cosmetics are a non-goal, §9).

### 3.7 The pack resource (`godot/dlc/packs/kitchen.tres`)

The title showcase cycles through `DLCPacks.PATHS` (`godot/dlc/dlc_packs.gd:8-13`); one `.tres` per pack, no showcase
code change beyond the one-line array entry. Model it on `godot/dlc/packs/construction.tres`:

```
[gd_resource type="Resource" script_class="DLCPackData" load_steps=2 format=3]

[ext_resource type="Script" path="res://dlc/dlc_pack_data.gd" id="1"]

[resource]
script = ExtResource("1")
pack_id = "kitchen"
display_name = "Kitchen"
subtitle = "9 Tools + The Café"
accent_color = Color(0.85, 0.35, 0.3, 1)
weapon_ids = Array[String](["fryingpan", "rollingpin", "cleaver", "ladle", "tenderiser", "peppermill", "ketchup", "blender", "potlid"])
arena_id = "cafe"
container_style = "hazard"
badge_icon = "chef"
test_mode = "cookoff"
unlock_kind = "pack"
price = 1500
```

`container_style` has exactly one shipped style today (`"hazard"`, the fallback for unknown values); keep it. `badge_icon`
must be a hat that exists (`WobblerLooks.hat_parts()` non-empty — `chef` does). `unlock_kind`/`price` are the PR 4
additions described in §8.3.

### 3.8 Mode card metadata (`godot/data/extra/wizard.json`)

The wizard's mode cards read `wizard.json` `modes.<id>` for `short`, `icon`, `col` and section placement
(`godot/ui/setup_wizard.gd:134-162`, `ModeRules.blurb`). Add:

```json
"cookoff": { "short": "Nine kitchen tools, one greasy café", "col": "#ff8a5c", "icon": "crate" }
```

Do **not** add `cookoff` to `wizard.json` `featured`: a locked pack mode must never be in the featured row.

---

## 4. i18n — every user-facing string in 5 languages

Rules: `docs/I18N.md`; voice/spelling: `docs/WRITING.md` (British spelling, sentence case, short lines without a trailing
full stop, `…` not `...`, ` · ` separators). English text is the message id. Every Godot string goes in
`godot/i18n/src/*.json` (one new file, `9a-kitchen-data.json`; files are merged in sorted order) in the exact shape:

```json
{
 "Frying Pan": { "zh_TW": "…", "zh_CN": "…", "ja": "…", "fr": "Poêle", "es": "Sartén" }
}
```

Then run `node tools/i18n.js`, commit the regenerated `godot/i18n/strings.json` and `public/i18n-data.js`, and verify with
`npm run i18n -- --check`.

**Key inventory to translate** (the PR must contain all of them, in all five languages):

| group | English keys |
|---|---|
| pack | `Kitchen`, `9 Tools + The Café` |
| tools | `Frying Pan`, `Rolling Pin`, `Cleaver`, `Ladle`, `Tenderiser`, `Pepper Mill`, `Ketchup Gun`, `Blender`, `Pot Lid` |
| arenas | `The Café`, `The Galley`; their blurbs; tags `Food`, `Indoor`, `Cover`, `Close quarters`, `Hazards` |
| mode | `Cook-off`, its `desc` (above), its `short` (`Nine kitchen tools, one greasy café`) |
| class | `Cook`, its `tag` (above) |
| outfits | `Line Cook`, `Sous-Chef`, `Pot Wash` |
| UI | reuse existing keys only: `Unlock for %d coins`, `Need %d more`, `Owned`, `UNLOCK PACK`, `TEST IN %s`, `Arena: %s` (all already translated) |

Rules the checker enforces: all five languages non-empty; `%` placeholders identical and in the same order; `{names}`
identical; the same number of line breaks; no unknown language codes. Duplicate keys across source files are warnings
(the first sorted file wins) — keep each new English key unique so nothing silently shadows.

### CJK coverage rule (this is the hard gate for any new pack)

`node tools/i18n.js --check` fails if a zh_TW/zh_CN/ja string uses a Han, kana or full-width character that is not in
`tools/cjk-coverage.json`, the character list of the shipped subset fonts (`tools/i18n.js:144-152`). That file is generated
by `python3 tools/subset-fonts.py <dir with NotoSansTC/SC/JP-Bold.otf>` together with the fonts — **the Noto source fonts are
not in the repo**, so a worker cannot refresh it. Consequences:

1. Author the translations, then run `node tools/i18n.js --check`. If it reports missing characters, that list is the exact
   input the owner needs.
2. **Owner action (blocks the PR):** download Noto Sans CJK `Sans/SubsetOTF/{TC,SC,JP}/NotoSans*-Bold.otf`
   (github.com/notofonts/noto-cjk, SIL OFL), run `npm run i18n && python3 tools/subset-fonts.py <that dir>`, commit the
   regenerated fonts, `tools/cjk-coverage.json` and `public/fonts/*.woff2`.
3. Never hand-edit `tools/cjk-coverage.json` or the `.otf`/`.woff2` files, and never hard-code another font.

A useful pre-check before the owner step: any character outside the subset shows as a box on the web export and falls back
on device, so treat every `--check` CJK error as blocking. Expect new pack names to need a font refresh (Pack #1's tool
names did).

Also run `npm run i18n:scan -- --strict` while reviewing: it lists `tr()` keys in code with no catalog entry (not part of
`npm test`, but the new mode/class/sheet code must not ship untranslated text).

---

## 5. Tests and CI that gate it

`npm test` (the content/i18n gate, runs in the `check` CI job) is a chain — all of it must pass:

| step | what it protects for Pack #2 |
|---|---|
| `node tools/check-version.js` | single version source untouched |
| `node tools/export-content.js --check` | `shared/*.json` (including the two new arenas, the three outfits, cosmetics) regenerates **identically** from `public/index.html` |
| `node tools/sync-shared.js --check` | `godot/data/*.json` copies are identical to `shared/` — proves the arenas reached Godot |
| `node tools/i18n.js --check` | every string in 5 languages, built files current, **CJK glyph coverage** |
| `node tools/check-maps.js --quiet` | both new arenas are walkable: spawns/bots/drops standable and mutually reachable, no soft pits |
| `node tools/test-server.js` | unrelated (relay); must stay green |

Godot suites (CI `godot` job, four shards; 6 total checks including `export-smoke`):

| suite (CI shard) | why it gates Pack #2 |
|---|---|
| `npm run test:godot-construction-data` (net) | the DLC pack registry, merge hooks, JSON cache, synthetic malformed packs; **must be generalised to two packs in PR 1** |
| `npm run test:godot-title` (rest) | the showcase registry and test drive; **hardcodes one pack today** (§8.3) |
| `npm run test:godot-dlc-ui` (rest) | DlcUnlock/DlcSave/Construction hub; PR 4 changes the save shape and the unlock button routing |
| `npm run test:godot-save` (rest) | outfit prices match the web (`locker.json`); the `dlc` blob migration/round-trip |
| `npm run test:godot-maps` (net) | every map builds; catches a broken exported arena |
| `npm run test:godot-modes` (sim) | modes play to their end; the new `cookoff` row goes here (PR 3) |
| `npm run test:godot-ui` (ui) | wizard mode cards, safe-area/touch targets; the new card must not overflow (`ui_layout_test.gd:661`) |
| `npm run test:godot-title-fit` (rest) | translated pack/title text fits its room; new French/Spanish strings are the risk |
| `npm run test:godot-quick-play` (rest) | Quick play must not roll a locked pack mode (`quick_play_test.gd:71-72`) |
| `npm run test:godot-arcade`, `test:godot-construction`, `test:godot-modes` | must stay untouched: Pack #2 adds no Arcade stages and changes no Construction data |
| `npm run test:godot-perf`, `test:godot-bots` (rest/net) | no new RNG draws, no new simulation; bot parity untouched |
| CI `export-smoke` | the Web export still builds and packs `res://data/extra/kitchen/` |

**New pack-specific test (PR 1, extended in PR 3/4):** `godot/tests/kitchen_pack_test.gd` + runner
`tools/test-kitchen-pack.js` + npm script `test:godot-kitchen-pack`, modelled on `tools/test-construction-data.js` (Godot
import, then `--script`, filter + fatal-line check). It must assert:

1. `Content.pack_ids()` == `["construction", "kitchen"]` (sorted), both manifests valid, `scan_errors()` empty;
2. `kitchen` section paths resolve via `Content.pack_section_file`, and its three sections are the only declared ones;
3. all nine ids exist in `Content.weapons` and `Combat.weapons_data`, have no id clash with shared or Construction data,
   pass the per-type field checks, carry `kitchenOnly: true`, and have a model (`WobblerLooks._weapon_visual(id)` non-empty,
   PR 3);
4. `ExtraWeapons.is_extra()` is true for each kitchen id and the Construction tools still resolve (per-pack tables, not a
   global count);
5. mode `cookoff` exists, `allowWeapons`/`dropWeights` cover the nine tools + heal/shield/speed/rage, `preset.limit == 20`,
   `ModeRules.maps_for("cookoff") == ["cafe", "galley"]`, and the mode is listed only when the pack is owned (PR 3);
6. a 4-second headless smoke per tool on `cafe` in `cookoff` (copy `_smoke_tools` from `construction_data_test.gd`): each
   tool fires or swings, no script error, all state finite;
7. class `cook` is hidden when the pack is unowned and owned when it is (PR 4); outfits are listed in the shop and the
   web price parity holds (fails in `test:godot-save` too);
8. showcase: `DLCPackData` entry loads, `problem()` is empty, `real_weapons().size() == 9`, `badge_icon` exists,
   `unlock_kind == "pack"` (PR 3); buying is refused when poor, deducts `PRICE` once, is live from the save and
   round-trips through `apply_blob` (PR 4).

**Existing tests that must be generalised (they assume exactly one pack):**

| file:line | today | change |
|---|---|---|
| `godot/tests/construction_data_test.gd:158` | `ExtraWeapons.ids().size() == 9` | assert the Construction ids are a subset / compare per-pack tables |
| `:374` | `pack_ids() == ["construction"]` | `== ["construction", "kitchen"]` |
| `:328-332, 410-414` | legacy mode merge compares against Construction only | loop over every shipped pack folder in sorted id order |
| `:406, 469, 474` | `ExtraWeapons.data() == construction/weapons.json` | compare `Content.pack_tables("weapons")` scoped per pack |
| `:472-473` | `load_dlc_packs().size() == 1` | `== 2` |
| `godot/tests/title_showcase_test.gd:90` | one shipped pack | two packs, `packs[0].pack_id == "construction"` |
| `:410, 547` | "the showcase starts on the shipped pack" / "one pack" | two packs; keep the one-pack branch by hiding the second through `DLCPacks.extra` or a test seam |
| `godot/tests/ui_layout_test.gd:661` | every `PLAYABLE` mode has a card | the pack mode is skipped while unowned; assert both states |
| `godot/tests/quick_play_test.gd:71-72` | rolled modes are not `NOT_QUICK` | also assert no locked pack mode is rolled |
| `.github/workflows/ci.yml` | — | add `npm run test:godot-kitchen-pack` to one shard (put it with `test:godot-construction-data`, net) |

`npm test` alone passes without Godot; the pack is not releasable until the Godot suites above are green (the lead runs
them from a clean checkout; parity suites only run on the Mac).

---

## 6. Build order — four small, reviewable PRs

Branch every PR from freshly fetched `origin/main`, one worktree each. PR n depends on PR n-1.

### PR 1 — `feat(kitchen): Pack #2 data — manifest, 9 tools, Cook-off mode, class, i18n`
Data + tests only, no gameplay code. Files: `godot/data/extra/kitchen/{pack.json,weapons.json,modes.json,classes.json}`;
`godot/i18n/src/9a-kitchen-data.json`; regenerated `godot/i18n/strings.json` + `public/i18n-data.js`;
`godot/data/extra/wizard.json` (`modes.cookoff`); new `godot/tests/kitchen_pack_test.gd` +
`tools/test-kitchen-pack.js` + `package.json` script + one `ci.yml` step; generalise `construction_data_test.gd`
(§5 table). Owner font refresh if the CJK check fails (§4). Gates: `npm test`, `test:godot-construction-data`,
`test:godot-kitchen-pack`. User-visible: nothing yet (the content loads and merges but is unreachable), which is safe to
merge behind the later PRs.

### PR 2 — `feat(kitchen): arenas — The Café and The Galley`
`public/index.html` (two `MAPS` entries + `MAP_ORDER`), `npm run content` (regenerates `shared/maps.json` and
`godot/data/maps.json`), arena names/blurbs/tags in the i18n file, PR 1 test extended to assert both maps exist and build.
Optional: `npm run map-decor` for the web look (needs network/Playwright; not required). Gates: `npm test` (parity, i18n,
check-maps), `test:godot-maps`, `test:godot-world` (map build smoke). No gameplay code.

### PR 3 — `feat(kitchen): pack front end — models, mode listing, title showcase`
The playable/visible layer, still free-to-play through the title test drive. Files: `godot/actors/weapon_models.gd` (new
`PACK2_KEYS` + nine `_xxx()` builders + `build()` cases); `godot/logic/mode_rules.gd` (`PLAYABLE`, `OFFLINE_ONLY`,
`MODE_MAPS["cookoff"]`, `MAP_ORDER`); `godot/ui/setup_wizard.gd` (`modes()` filters locked pack modes via the pack's
`play_modes`), `godot/logic/quick_play.gd` (`modes()` same filter); `godot/dlc/dlc_pack_data.gd` (`play_modes`,
`price`, unlock branch — ownership false until PR 4, or `unlock_kind=""` for a free preview); `godot/dlc/packs/kitchen.tres`
+ `godot/dlc/dlc_packs.gd` `PATHS`; `godot/tests/title_showcase_test.gd`, `ui_layout_test.gd`, `quick_play_test.gd`,
`modes_test.gd` (`cookoff` row), `ui_layout_test`/`hud_test` if the card changes layout. Gates: `test:godot-title`,
`test:godot-title-fit`, `test:godot-ui`, `test:godot-modes`, `test:godot-quick-play`, `test:godot-weapons` (models),
`test:godot-kitchen-pack`.

### PR 4 — `feat(kitchen): 1500-coin pack unlock and pack classes`
The DLC wiring. Files: `godot/dlc/construction/dlc_save.gd` (add `packs: {id: bool}` to fresh/clean with a backwards-
compatible migration: legacy `owned: true` implies `packs.construction = true`); new `godot/dlc/pack_unlock.gd`
(`price`, `owned`, `missing`, `buy`, `owns_any`); `godot/dlc/dlc_pack_data.gd` (`unlocked()` `unlock_kind == "pack"` →
`PackUnlock.owned(pack_id)`); `godot/scripts/main.gd:262-264` (route `unlock_requested` to the new sheet instead of
`open_hub()`); new `godot/ui/pack_sheet.gd` (price, coins, Buy, "Need %d more", owned chip; modelled on
`construction_hub.gd`'s buy card); `godot/autoload/save.gd:359-364` (`owns_class`: `ExtraClasses.pack_of(id) != ""` →
`PackUnlock.owned(...)`); `godot/logic/extra_classes.gd` (`pack_of`); `godot/dlc/construction/dlc_unlock.gd` unchanged for
Construction (it keeps its own `owned` flag + developer code); tests: `dlc_ui_test.gd` (button routing), `save_test.gd`
(blob migration), `locker_test.gd` (class hidden/owned), `title_showcase_test.gd` (unlock button per pack),
`kitchen_pack_test.gd` (buy). Gates: all four plus `test:godot-save`, `test:godot-locker`, `test:godot-dlc-ui`,
`test:godot-title`, `test:godot-ui`.

If the owner wants to ship Pack #2 as a free pack, PR 4 is not needed: set `unlock_kind: ""` in the `.tres` (always
unlocked, no buy button) and drop the class ownership hook (the class then needs `price` in classes.json to be reachable,
or is omitted). Decide before PR 3 — it changes the PR 3 mode-listing filter.

---

## 7. Audit — how a zero-code pack is loaded today, ownership, and what Pack #2 really needs

### 7.1 Load path (all data-driven, no pack-specific code)

1. Autoload `Content` (`godot/autoload/content.gd`) `_init()` → `reload()` (`:120`).
2. `reload()` invalidates the parsed-JSON cache, then `load_dlc_packs()` (`:296`) → `scan_dlc_packs()` (`:174`): every
   `res://data/extra/*/pack.json`, validated by `_read_pack()` (`:219`) — id/folder equality, name, version, `requires`,
   in-folder section paths, each section must parse as a JSON object. Deterministic order: sorted pack id, then
   `requires` resolution (a pack whose dependency is missing is dropped). A bad manifest is `push_error`'d into
   `Content.scan_errors()` and **only that pack is skipped** — a broken DLC never stops a match.
3. The reload then merges through the existing hooks:
   `weapons` → `ExtraWeapons.merge` (`godot/logic/extra_weapons.gd:20-31`),
   `classes` → `ExtraClasses.merge` (`godot/logic/extra_classes.gd:20-49`, built-in extras win),
   `modes` → `ModeRules.merge_extra` (`godot/logic/mode_rules.gd:178-214`: new modes added whole, existing modes get the
   additive `allowWeapons`/`dropWeights` hooks).
   A `stages` table is only **published by path** via `Content.pack_section_file` and read by `ArcadeCoop.table()` /
   `ArcadeCoop.stages_path()` (`godot/dlc/construction/arcade_coop.gd:32-34`).
4. Hooks cache their tables per registry generation (`Content.generation()`), so a `reload()` picks up a new pack with no
   restart of code paths; the parsed-JSON cache is invalidated and re-decodes on next read.
5. The title screen has a second, independent registry: `DLCPacks.PATHS` → `DLCPackData` `.tres` resources
   (`godot/dlc/dlc_packs.gd:8-32`) filtered by `problem()` (weapons exist, arena exists) and sorted with the shipped packs
   first; `TitleShowcase` presents them (`godot/ui/title_showcase.gd:109-160`), and its "TEST IN <arena>" starts a trial
   world directly (`godot/scripts/main.gd:300-312`: arena id, `test_mode`, the pack's real weapons laid on the floor, no
   saving, open to owners and non-owners alike).

So the *content* half is genuinely zero-code: a folder + `pack.json` + section files is merged at startup. The gaps are
all about **reachability, looks and money** — see §7.3.

### 7.2 Pack DLC ownership today

- The Construction purchase is `DlcUnlock` (`godot/dlc/construction/dlc_unlock.gd`): `PRICE = 1500` coins (`:9`),
  `owned()` (`:23-25`) reads `Save.dlc["owned"]` **or** `Save.codes.has("dev")`, `buy()` (`:35-43`) deducts coins and
  sets the flag, state in the profile blob key `dlc` (`godot/autoload/save.gd:51`, cleaned/migrated by
  `DlcSave.clean`, `godot/dlc/construction/dlc_save.gd:35-62`). The developer code is debug-only since WP L1
  (`dev_code_allowed()`, `dlc_unlock.gd:54-56`) and the 7-tap entry is hidden in release builds.
- **There is no platform entitlement**: nothing calls StoreKit/Play Billing, there is no receipt, no restore, no server
  check. The web game ignores the `dlc` blob key. Coins themselves are client-authoritative today
  (`docs/IMPROVEMENT_PLAN.md` §2/§3, "server-side wallet"); WP 1.0-A replaces that, which is why Pack #2 (1.0-C) must
  ship *after* 1.0-A.
- The presentation layer knows ownership only through `DLCPackData.is_unlocked` → `unlocked()` → `unlock_kind`:
  `""` = always unlocked; `"construction"` = `DlcUnlock.owned()`; any other value = locked (`dlc_pack_data.gd:34-40`,
  asked live every refresh, never stored in the `.tres`). The showcase's "UNLOCK PACK" button emits `unlock_requested`, and
  `godot/scripts/main.gd:263` routes **every** pack to `open_hub()` — the Construction hub. That handler is the first
  thing that cannot serve a second pack.

### 7.3 Verdict: Pack #2 is **not** end-to-end zero-code

The content loads with no code (§7.1), but today it would be invisible, unplayable and unpurchasable. Four real code gaps,
none of them gameplay simulation:

| # | Gap | Exact file / function | What happens without it |
|---|---|---|---|
| 1 | No title entry | `godot/dlc/dlc_packs.gd` `PATHS` (+ new `godot/dlc/packs/kitchen.tres`) | pack never appears in the showcase, no preview/test drive |
| 2 | No mode reachable | `godot/logic/mode_rules.gd` `PLAYABLE` (`:37`), `OFFLINE_ONLY` (`:40`), `MODE_MAPS` (`:74`); `godot/ui/setup_wizard.gd` `modes()` (`:86`); `godot/logic/quick_play.gd` `modes()` (`:20-27`) | `cookoff` is in `Content.modes` but no picker lists it; Quick play could roll it for a non-owner and hand out DLC weapons (bypass) |
| 3 | No weapon models | `godot/actors/weapon_models.gd` `DLC_KEYS` (`:17`) + `build()` match (`:56`) | nine grey placeholder blocks in hand, in the showcase racks and in the HUD |
| 4 | No per-pack purchase | `godot/dlc/dlc_pack_data.gd` `unlocked()`; `godot/dlc/construction/dlc_save.gd` `fresh/clean`; new `Dlc/*` unlock helper; `godot/scripts/main.gd:263`; `godot/autoload/save.gd` `owns_class`; a small pack sheet UI | "UNLOCK PACK" opens the Construction hub; no way to charge 1500 coins for this pack; a pack-gated class is never owned |

Arenas are deliberately **not** a gap: the pack schema has no `maps` section (reserved + ignored), so arenas are shared
content authored in `public/index.html` and exported (`siteyard`'s precedent). Cosmetics are likewise not a pack section:
hats need geometry code, outfits are data-only and are copied into `godot/data/extra/locker.json` by hand (price parity is
tested in `save_test.gd`).

**If the owner later wants truly zero-code packs**, the follow-up is to consume the already-reserved `maps` and
`cosmetics` sections in `Content._read_pack` (`content.gd:262-266`): merge map tables into `Content.maps`
(`MapBuilder`-compatible), and route hat/outfit tables into `WobblerLooks.data("cosmetics")`. That is a separate WP — the
Data-only design intentionally stops at `weapons`/`classes`/`modes`/`stages` today.

---

## 8. Non-goals (explicit)

- **No new weapon simulation or mechanics.** The nine tools use the existing `melee`, `gun` (default/punch/flame), `ball`
  and `knife` types. No new snapshot fields, no new `Combat` branches, no parity impact.
- **No Arcade boss rush for Pack #2.** `godot/dlc/construction/arcade_manager.gd` still hardcodes
  `STAGES_PATH` (`:45`) and the whole run manager, panels and HUD are Construction-flavoured; a second Arcade is a code +
  level-design project, not a content drop. The manifest declares no `stages` section.
- **No platform IAP entitlement** (StoreKit/Play Billing), no receipt validation, no restore purchases, no server-side
  entitlement check. That is the 1.0-A/1.0-B monetisation work; until then Pack #2 follows Construction's coin rule.
- **No pack-exclusive cosmetics or emotes.** New hats need `WobblerLooks` geometry; emotes need pose code + web data. The
  three outfits are regular coin-shop items.
- **No Godot-only arena generator** (the `SiteMap`/`sitegen` pattern) — arenas are authored shared data.
- **No changes to `shared/*.json`, `godot/data/*.json`, `godot/data/extra/construction/*`, the Construction hub, or
  `DlcUnlock`'s Construction behaviour.** Pack #2 is additive.
- **No balance changes to shared or Construction data**, and no `combat.rng` draws in UI/visual code (`docs/GODOT_ARCH.md`).
- **No new CJK font glyphs authored by a worker** — the font subset refresh is an owner step (§4).

## 9. Risks and mitigations

1. **CJK font subset (highest).** New Chinese/Japanese names almost certainly use glyphs the shipped subsets lack; the
   i18n check will fail. Mitigation: PR 1 runs the check first, hands the owner the exact missing-character list, and the
   owner reruns `tools/subset-fonts.py` with the Noto CJK OTFs; nothing merges before that. Do not bypass with covered-only
   renames unless the owner asks — the copy would get weird.
2. **DLC bypass through the mode listing.** The pack's weapons are merged into every client's `Content.weapons` regardless of
   ownership (that is how the pack system works). If `cookoff` is listed without an ownership filter, a non-owner plays it
   and gets the paid tools from crates. Mitigation: PR 3 filters it in `SetupWizard.modes()` **and** `QuickPlay.modes()`,
   `ModeRules.OFFLINE_ONLY` keeps it out of online rooms, and the pack test asserts hidden-when-unowned.
3. **Online/web peers.** `cookoff` must never travel in an online room (`OFFLINE_ONLY`; the web export has no such mode and
   web peers would not know the ids/mode), and the pack's weapons must never leak into a shared mode's crate pool. The mode
   data stays a pack section; the construction mode is untouched.
4. **Coin economy / wallet sequencing.** A 1500-coin purchase is client-trusted until WP 1.0-A lands; Pack #2 is 1.0-C and
   must not ship before the server wallet, or the purchase can be forged/restored by editing a save. Mitigation: sequencing
   (1.0-A before 1.0-C), and PR 4 buys through `Save`/server-wallet APIs rather than a second client-side truth.
5. **Save-format migration.** Adding `packs` to the `dlc` blob must keep old saves and cross-device merges working
   (`DlcSave.clean` unknown keys are dropped today; `apply_blob` "keep this device" can drop another device's purchase
   until 1.0-A item 6 adds per-field merge). Mitigation: explicit migration test in `save_test.gd`, legacy
   `owned:true` → `packs.construction:true`, and no second blob key.
6. **Single-pack assumptions in tests.** `construction_data_test.gd` and `title_showcase_test.gd` hardcode one pack
   (§5 table); a Pack #2 PR that only adds data turns CI red for the wrong reason. Mitigation: PR 1 generalises them (and
   keeps the byte-equal legacy comparisons by scoping per pack).
7. **Arena authoring quality.** `check-maps` catches unreachable spawns/pits but not fun; both arenas need a short
   practice match and a fresh screenshot review (the lead's normal gate). Keep them box-only; no decor dependency.
8. **Parity drift.** The arenas are shared data, so `npm test`'s `export-content --check` and `sync-shared --check` are the
   guarantee; never edit `shared/maps.json` by hand. Weapon/mode/class data must stay in `godot/data/extra/kitchen/`
   (never `shared/`), so the web game and the JS parity references never see it.
9. **Localization fit.** French/Spanish pack, mode, arena and class strings are longer than English; `test:godot-title-fit`
   and `test:godot-ui` check the title/wizard/shop layouts. Budget a wrap/reword pass rather than shrinking text.
10. **Review size.** PR 3's weapon-model builders are mechanical but bulky; split the model additions into their own commit
    inside the PR (`weapon models` / `mode wiring` / `showcase entry`) so the diff stays reviewable.

## 10. Owner actions

1. **Font subset refresh** after the translations exist: download Noto Sans CJK `Sans/SubsetOTF/{TC,SC,JP}/*-Bold.otf`,
   `npm run i18n && python3 tools/subset-fonts.py <dir>`, commit fonts + `tools/cjk-coverage.json` + `public/fonts/*.woff2`.
2. **Decide paid vs free** before PR 3 (default in this spec: paid 1500 coins, same rule as Construction). It changes the
   `.tres` `unlock_kind`, whether PR 4 exists, and the class ownership hook.
3. If the web look is wanted for the two arenas: run `npm run map-decor` (network + Playwright chromium) after PR 2 and
   commit `godot/data/extra/decor/<map>.bin` + `map_look.json`.
4. Re-confirm the price and the pack name/subtitle copy (they appear on the title container, the showcase header and the
   shop sheet).

## 11. Definition of done (Pack #2)

- `npm test` green (parity: `shared/` regenerates identically; i18n in 5 languages; CJK coverage; `check-maps` green).
- `npm run test:godot-construction-data`, `test:godot-kitchen-pack`, `test:godot-title`, `test:godot-title-fit`,
  `test:godot-ui`, `test:godot-modes`, `test:godot-maps`, `test:godot-save`, `test:godot-locker`, `test:godot-dlc-ui`,
  `test:godot-quick-play`, `test:godot-weapons` green locally (Godot 4.7.2) and in CI (6 checks).
- All nine tools swing/fire in a real `cookoff` match and have a held model; both arenas play without falling through or
  trapping; the title showcase previews the pack and its test drive opens The Café with the nine tools on the floor.
- Ownership: locked → buy for 1500 coins → unlocked live, in one session, with coins deducted once; save/blob round-trips;
  non-owners cannot enter `cookoff` or receive its tools.
- No hand-edited generated file; every player-facing string translated; no new RNG draws; no shared-table changes.
