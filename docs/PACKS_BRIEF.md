# Three new DLC packs: owner's brief (authoritative)

This is the owner's own direction (2026-11-17) for three data-driven packs. It **supersedes** `docs/PACK2_SPEC.md` wherever they disagree
(6 weapons per pack, pack ids, procedural arenas in Godot). `docs/PACK2_SPEC.md` §7 (how a zero-code pack loads, what is not zero-code)
and §9 (risks) are still useful background. Concept art for each pack is in `docs/img/packs/` (read the images):
`kitchen-on-fire.webp`, `xmas-ho-ho-ho.webp`, `australia-hey-mate.webp`.

## Task as given

Implement 3 new data-driven DLC packs for Wobbler Arena:
1. Kitchen Pack ("On Fire", id: "kitchen")
2. Xmas Pack ("Ho Ho Ho", id: "xmas")
3. Australia Pack ("Hey Mate", id: "australia")

First read `docs/CONSTRUCTION_DLC.md` and inspect `godot/data/extra/construction/`, `godot/dlc/construction/`, `godot/ui/dlc_transition.gd`, and
`godot/tests/dlc_ui_test.gd` so all 3 packs follow the exact same architecture and conventions.

### Hard constraints
- Do NOT modify core combat math, `shared/*.json`, or existing `construction` DLC balance/tests.
- Keep all weapons mapped to existing combat types (`melee`, `gun` with punch/flame styles, `ball`, `knife`).
- Maintain >=44x44px touch targets and 60fps mobile performance (keep procedural map box counts <= 450, hard cap 690).

### Deliverables across all 3 packs
1. **Data packs** (`godot/data/extra/{kitchen,xmas,australia}/`):
   - `pack.json` manifest (id, name, version, weapons, modes, stages).
   - `weapons.json`: 6 distinct themed weapons per pack (18 total), flagged pack-only.
     - Kitchen: `fryingpan`, `cleaver`, `flambetorch`, `rollingpin`, `peppergrinder`, `souppot`
     - Xmas: `candycane`, `snowballcannon`, `giftbomb`, `tinselwhip`, `ornamentlauncher`, `toymallet`
     - Australia: `cricketbat`, `boomerang`, `thongslapper`, `vegemitejar`, `bbqtongs`, `didgeridooblaster`
   - `modes.json`: pack-specific classic mode + `allowWeapons` and `dropWeights`.
   - `stages.json`: 6-stage Arcade Boss Rush per pack with `difficulties` (Easy/Normal/Nightmare), unique boss `hp_bar_color`, themed bot crews,
     and 1.5x Giant Final Bosses.
2. **Low-poly models and cosmetics:**
   - Extend `WeaponModels.build()` with low-poly primitive models for all 18 weapons.
   - Extend `WobblerLooks` / `locker.json` with pack hats/outfits (Chef Toque, Santa Hat, Elf Cap, Cork Slouch Hat, Apron/Singlet variants) and
     exclusive Arcade Normal/Nightmare victory hats.
3. **Procedural maps and stage events:**
   - Create pack map generators (boxes, ladders, bounce pads, hazard zones) modelled on `site_map.gd` / `site_props.gd` (`kitchen_chaos`,
     `toy_workshop`, `backyard_bbq`), each verified navigable on a 1m grid.
   - Extend `StageEvents` only where needed for pack hazards (burner/BBQ hotplates, icy floor friction, spinning Hills Hoist).
4. **Multi-pack DLC hub and title showcase (Option 2B):**
   - Generalise `dlc_unlock.gd`, `dlc_save.gd`, and the Option 2B Crane & Shipping Container Drop showcase to support selecting between
     `construction`, `kitchen`, `xmas`, and `australia` packs cleanly.
5. **Localisation and tests:**
   - Add 5-language i18n entries (`zh_TW`, `zh_CN`, `ja`, `fr`, `es`) under `godot/i18n/src/` and rebuild strings with `node tools/i18n.js`.
   - Add automated Godot headless tests verifying pack manifest loading, weapon/stage schemas, map playability across seeds, and multi-pack DLC UI flow.

Work in clean, verifiable phases: (A) Data and i18n -> (B) WeaponModels and Cosmetics -> (C) Maps and Arcade Stages -> (D) Multi-Pack Hub UI and Tests.
Report exact test commands and results after each phase.

## Content per pack

### 1. Kitchen: "On Fire" (`id: kitchen`)
- Arena (`kitchen_chaos`): stainless-steel prep counters as cover, glowing stove-burner hazard strips, rolling prep carts, and overhead
  exhaust-vent bounce pads.
- Cosmetics: tall Chef Toque hat, stained apron outfit, and metallic Dishie Bot look.
- Weapons (6): Frying Pan (heavy `melee`, high topple), Cleaver (fast `melee`), Flambe Torch (`gun` flame), Rolling Pin (medium `melee`),
  Pepper Grinder (rapid `gun`), Hot Soup Pot (`ball` lob).
- Arcade twist: floor-wide "Dinner Rush" burner hazards and falling ingredient crates.

### 2. Xmas: "Ho Ho Ho" (`id: xmas`)
- Arena (`toy_workshop`): giant Christmas tree centrepiece, stacked gift-box cover, low-friction icy floor patch, candy-cane perimeter fence,
  and a chimney bounce pad.
- Cosmetics: Santa hat + fluffy beard, Elf cap + green tunic.
- Weapons (6): Giant Candy Cane (high-lift hook `melee`), Snowball Cannon (rapid `gun`), Gift Bomb (`ball` heavy knockback), Tinsel Whip
  (long-reach `melee`), Ornament Launcher (`knife` projectile), Toy Mallet (heavy `melee`).
- Arcade twist: slippery ice zones and gift-drop crate barrages.

### 3. Australia: "Hey Mate" (`id: australia`)
- Arena (`backyard_bbq`): corrugated-iron fence perimeter, glowing BBQ hotplate hazard, spinning Hills Hoist clothesline obstacle, Esky cooler
  stacks, and a kangaroo-spring trampoline pad.
- Cosmetics: cork-dangling slouch hat, singlet + shorts, and thongs (flip-flops).
- Weapons (6): Cricket Bat (heavy `melee`, huge launch), Boomerang (`knife` projectile), Thong Slapper (ultra-fast `melee`), Vegemite Jar
  (`ball` lob), BBQ Tongs (long-reach `melee`), Didgeridoo Blaster (`gun` punch/air blast).
- Arcade twist: spinning Hills Hoist sweeps and "Sausage Sizzle" hotplate bursts.

## Notes added by the lead
- Tone: affectionate and goofy. Keep Indigenous cultural items and stereotyping out (the didgeridoo blaster is the owner's call; flag it in review
  if an alternative name/model such as "Drone Blaster" would be safer, but build what the brief says).
- Price: 1500 coins each, same rule as Construction (`dlc_unlock.gd` `PRICE`). Xmas selling window is undecided (default: always available).
- Chinese / Japanese wording must use glyphs already in `tools/cjk-coverage.json` (the i18n check enforces it); reword, never edit fonts.
