# Writing for Wobblers Arena

How the game talks. Applies to every player-facing string: the web game (`public/index.html`), the shared data it exports (`shared/*.json` → `godot/data/`), the Godot extras (`godot/data/extra/*.json`) and text hard-coded in GDScript. When you add text, match this. When you change a name or a description, change it everywhere it appears (see "One thing, one wording" below).

## Voice

Goofy and wobbly, never mean. The fighters are jelly-legged toys and the game knows it. The jokes are short and silly, with no regional slang, and safe for kids.

- **Help, errors, settings, account:** plain and clear first. Say what happened and what to do next. No jokes in error messages.
- **Flavour spots** (class tags, map blurbs, loading tips, toasts, results lines, What's new notes): one silly beat is plenty. Keep the facts in and land the joke at the end.
  - Good: `Tiny and zippy. Flies like a frisbee`
  - Too much: `Tiny and zippy!!! Watch out, LOL, this little rascal goes WHEEE`

## Rules

| Topic | Rule | Example |
|---|---|---|
| Game name | **Wobblers Arena** (ids, package names and the network prefix keep `wobble-arena`) | |
| Knock-outs | **K.O.**, **K.O.s**, **K.O.'d**. Never "kill" or "knock-out" in visible text | `Get 10 K.O.s` |
| Spelling | British | colour, centre, metres, grey, armour |
| Contractions | Use them | `You're out!`, `Can't reach the game server` |
| Casing | Sentence case for buttons, titles, labels and tabs | `Play again`, `Quit to title` |
| ALL CAPS | Only for the touch buttons (FIRE, JUMP, MELEE…) and the big in-match banners (`YOU WIN!`) | |
| Short lines | Labels, tags, card lines, goals and mode descriptions have **no** trailing full stop | `Balanced. No surprises` |
| Prose | Multi-sentence text (map blurbs, info panels, errors, sentence toasts) ends with a full stop, `!` or `?` | |
| Ellipsis | The `…` character, never `...` | `Connecting…` |
| Separator | ` · ` (middle dot, single spaces) | `3 K.O.s · 1 death` |
| Numbers | Digits in UI (`First to 5`), with units spelt out where there's room (`10 seconds`, `12s` in timers) | |
| Places | **Arena** is where you fight (not "level" or "map" in UI text) | `Pick an arena` |
| Menus | **Walldrobe** (your stuff), **Shop** (buy stuff), **Goals**, **Practice Range**, **Settings** | |
| Verbs | Wear (outfits, hats), Use (colours), Equip (emotes), Pick (classes), Buy | |
| Errors | `Couldn't …` + the thing + what to do next | `Couldn't delete your account. Try again in a moment.` |

## One thing, one wording

Some text lives in more than one place. Keep the copies identical.

| Text | Source | Copies |
|---|---|---|
| Mode name and `desc` | `MODES` in `public/index.html` → `npm run content` | Godot reads `godot/data/modes.json` |
| Mode card line (short) | web `BLURB` in `public/index.html` | `godot/data/extra/wizard.json` `short` |
| Godot-only modes | `godot/data/extra/modes.json` (Moon Drift copies web `MODES.lowg`) | |
| Map name, blurb, tags | `MAPS` in `public/index.html` → `npm run content` | Lava Pillars in `godot/logic/pillars_map.gd` |
| Class name and tag | `CLASSES` in `public/index.html` → `npm run content` | Godot-only classes in `godot/data/extra/classes.json` |
| Emotes, hat labels, rarity labels | `EMOTES` / `HAT_LABEL` / `RAR_LABEL` in `public/index.html` | `godot/data/extra/locker.json` |
| Power-up names and pickup toasts | `PU_META` / `HEAL_META` in `public/index.html` → `npm run content` | |
| Bot names | `BOT_NAMES` in `public/index.html` | `godot/logic/match_sim.gd` |
| Patch notes | web: `.news` block in `public/index.html`; Godot: `godot/data/extra/news.json` | |

Never hand-edit `shared/*.json` or `godot/data/*.json` (outside `extra/`). Edit `public/index.html`, then run `npm run content`. `npm test` fails if they drift.
