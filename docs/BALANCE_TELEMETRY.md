# Balance telemetry

A headless runner that plays many bot-vs-bot offline matches and prints Markdown balance tables, so balance can be tuned from data before a seasonal release. Tooling only: it reads the sim, never changes combat, physics or bot behaviour.

## Run it

```
npm run balance -- --matches 200 --out balance.md
npm run balance -- --matches 4 --jobs 2 --seconds 20          # tiny smoke, table on stdout
npm run test:balance-tool                                       # selftest of the aggregation (no Godot)
```

Options of `tools/run-balance-matrix.js`: `--matches N` (200), `--jobs N` (CPUs minus 1, max 8), `--bots N` (4), `--seconds N` (90, simulated), `--mode id` (classic), `--maps a,b,c` (arena,rooftops,temple), `--seed BASE` (1), `--out file.md` (default stdout), `--json raw.json` (every match's raw result), `--weapon id` (everyone starts with that weapon), `--pack id[,id]|all` (a DLC pack's classic mode on its own arenas, one report section per pack; see "Pack weapons"), `--starts a,b,c|pack` (controlled weapon sweep), `--timeout S` (120, wall-clock limit of one match), `--selftest`. Progress and failures go to stderr.

Each match is one Godot process running `godot/tests/balance_match.gd`, which prints one line `BALANCE {json}`. You can run a single match by hand:
`Godot --headless --path godot --script res://tests/balance_match.gd -- --no-save --seed=7 --map=arena --classes=kid,bruiser,alien,elder,wobbler`.

`--bots 4` means 4 bots plus the player's seat, which is also driven by a bot brain: 5 fighters, one per class in a normal run. Match i uses seed `base+i`, map `maps[i % n]`, and rotates the classes through the seats, so every class appears equally often (exactly, when matches x fighters is a multiple of 5). A match that crashes or exceeds 120 s is killed, reported on stderr, and counted as FAILED in the header; the tables use the rest. Not in CI.

The player's seat is made a true bot for the run (same difficulty damage scale and run speed as the bots), otherwise the class sitting there would hit harder and look overpowered. Classes also rotate through the seats for the same reason.

## Columns

Per class: **Appearances** (fighter-matches); **K.O.s/match** and **Deaths/match** per appearance; **K.O. share** = this class's K.O.s / all K.O.s; **K/D**; **Ring-out rate** = falls / deaths (share of deaths that were ring-outs, whoever pushed); **Dmg/match** = damage dealt; **Win rate** = matches where the class had strictly the most K.O.s / appearances (ties count as no winner, so rates sum to under 100%).

Per weapon (the weapon in hand when the K.O. was scored; `spatula` is the default melee): **K.O. share**, **Avg TTK**, **Picks** (weapon pickups that were not just ammo top-ups; the starting weapon is not a pick), **Picks/fighter-min**, **K.O.s/pick**.

Per weapon, damage and time in hand: **Dmg/pick** and **Held s/pick** (damage dealt and seconds in hand per pickup), **Dmg/held-min** and **K.O.s/held-min** (per minute the weapon was in hand, all fighters). Damage counts for the weapon in hand when it lands, so it includes the holder's kicks (about 40 per held-minute whatever the weapon). A mode's start weapon counts as one pick per life. The raw JSON also has `crate_drops` (crates that fell, by content).

Crates: crate pick rate = crates taken (every crate: weapons, health, power-ups) per fighter per simulated minute.

## TTK definition

TTK of a K.O. = seconds from the killer's latest respawn (or match start), or from the killer's previous K.O., whichever is later, until this K.O. It is "time to get a kill while alive", not time to kill one victim, so it mixes search time and fight time. Compare it between weapons, not against a stopwatch fight. Ring-outs with no attacker credit are not K.O.s and have no TTK.

## Determinism

The world seed fixes combat.rng, crate drops and bot decisions, the dynamic arena and destructibles are off, and `--no-save` fixes the start spots, so the same seed, map, mode and class list give the same result (checked: identical line apart from the `real_s` wall-clock field). The class override uses no random numbers. Results can differ between Godot versions or after any balance / bot change, which is the point of re-running it.

## Reading OUTLIER flags

The even share is 1 / (number of classes or weapons in the table). A row is flagged **OUTLIER high** when its K.O. share is above 1.5x the even share and **OUTLIER low** below 0.5x. Rows with fewer than 10 K.O.s are marked `low n` instead (too little data; run more matches). `spatula` (the default weapon every fighter starts with and falls back to) is naturally the top weapon; ignore its flag. Weapon shares depend on how often crates hand a weapon out, so check Picks and K.O.s/pick before blaming a weapon: a high share with a normal K.O.s/pick is a spawn-rate effect, a high K.O.s/pick is a strength effect. Bots are not humans: use class flags as a prompt to look, and sanity-check against play. Ring-out rate and K/D show whether a class is hard to keep on the floor or just deals more damage.

## Run time

Measured on the 10-core dev Mac with the default 7 jobs: the 200-match default run (90 s of simulated play each, 5 fighters, 3 maps) took 4 m 24 s wall time (about 9 s of one core per match). A 4-match, 20 s smoke takes about 9 s.

## Pack weapons

The 18 weapons of the On Fire (kitchen), Ho Ho Ho (xmas) and Hey Mate (australia) packs live in `godot/data/extra/<pack>/weapons.json` and only appear in that pack's classic mode (mode id = pack id) on that pack's arena.

```
npm run balance -- --pack kitchen,xmas,australia --matches 30 --bots 7 --seconds 150 --timeout 400        # the real pack modes
npm run balance -- --pack all --starts pack --matches 60 --bots 7 --seconds 120 --timeout 400             # controlled sweep
npm run balance -- --pack australia --starts bat,mallet,trident --matches 12 --bots 7 --seconds 120      # base weapons on a pack arena
```

- `--pack` reads the mode and the arenas from the pack's `hub.json`. `balance_match.gd` owns the pack in memory for the run (`--no-save`, nothing is written); without that the world falls back to classic. The runner warns when a match ran another mode than the one asked for.
- `--starts` is the controlled comparison: in match i every fighter gets `starts[i % n]` on every life, in place of the mode's start weapon (`balance_match.gd --start=<id>`, in memory only). `pack` means the pack's own six weapons. Any weapon id works, so base weapons can be measured on a pack arena for reference.
- Why the sweep is needed: bots walk to a weapon crate only when empty-handed and only for ranged weapons (`Pickups.bot_wants`), and every pack mode hands out a start weapon on each life. In the real pack modes the crate melee weapons are almost never picked up by bots (5 to 16 picks in 30 matches against 110 to 165 crates dropped per weapon), so only the sweep gives them enough data.

### Check of 2026-11-17 (commit b6eabb9 + this change, Godot 4.7.2)

Runs, all 8 fighters (7 bots + the player's seat as a bot), normal difficulty, 0 failed matches:

| Run | Matches | Sim time each |
|---|---|---|
| Sweep, pack weapons, before tuning (60 per pack, 10 per weapon) | 180 | 120 s |
| Sweep, 16 base and Construction weapons on the three pack arenas (4 per weapon per arena) | 192 | 120 s |
| Real pack modes, before tuning (30 per pack) | 90 | 150 s |
| Tuning trials (changed weapons only, other seeds) and one cross-check | 76 | 120 s |
| Sweep, pack weapons, after tuning | 180 | 120 s |
| Real pack modes, after tuning | 90 | 150 s |

808 matches in all.

Reference: base and Construction weapons as the start weapon on the pack arenas, pooled over the three arenas. The default spatula measured 142 to 149 Dmg/held-min and 0.53 to 0.61 K.O.s/held-min in the same runs.

| Weapon | K.O.s/pick | Dmg/pick | Dmg/held-min | K.O.s/held-min |
|---|---|---|---|---|
| bat | 0.22 | 81 | 203 | 0.55 |
| hammer | 0.12 | 64 | 130 | 0.25 |
| mallet | 0.41 | 44 | 108 | 1.01 |
| trident | 0.07 | 51 | 105 | 0.15 |
| wirewhip | 0.09 | 74 | 133 | 0.16 |
| pipewrench | 0.32 | 63 | 150 | 0.76 |
| drill | 0.03 | 59 | 72 | 0.04 |
| smg | 0.08 | 50 | 144 | 0.22 |
| ak | 0.05 | 70 | 182 | 0.13 |
| flame | 0.52 | 151 | 405 | 1.38 |
| glove | 0.37 | 2 | 5 | 1.11 |
| jackhammer | 0.05 | 48 | 26 | 0.03 |
| knife | 0.14 | 77 | 272 | 0.48 |
| conelauncher | 0.06 | 44 | 240 | 0.35 |
| snow | 0.02 | 2 | 21 | 0.16 |
| cementbucket | 0.07 | 6 | 28 | 0.36 |

Pack weapons, before -> after tuning. The first four columns are from the sweep (matches where the weapon is the start weapon). The last two are from the real pack modes: picks per fighter per minute (start-weapon hand-outs included) and the share of all K.O.s scored with the weapon in hand. Weapons whose numbers changed are in bold.

| Pack | Weapon | K.O.s/pick | Dmg/pick | Dmg/held-min | K.O.s/held-min | Picks/fighter-min (real mode) | K.O. share (real mode) |
|---|---|---|---|---|---|---|---|
| kitchen | fryingpan (start weapon) | 0.09 -> 0.11 | 54 -> 54 | 123 -> 121 | 0.21 -> 0.26 | 0.90 -> 0.92 | 23% -> 21% |
| kitchen | cleaver | 0.12 -> 0.07 | 60 -> 61 | 104 -> 106 | 0.20 -> 0.12 | 0.01 -> 0.01 | 0% -> 0% |
| kitchen | flambetorch | 0.43 -> 0.44 | 145 -> 145 | 212 -> 211 | 0.63 -> 0.63 | 0.12 -> 0.13 | 16% -> 17% |
| kitchen | rollingpin | 0.21 -> 0.20 | 77 -> 78 | 136 -> 137 | 0.37 -> 0.36 | 0.01 -> 0.01 | 0% -> 0% |
| kitchen | **peppergrinder** | 0.03 -> 0.07 | 48 -> 61 | 83 -> 100 | 0.05 -> 0.11 | 0.16 -> 0.15 | 5% -> 5% |
| kitchen | souppot | 0.04 -> 0.04 | 5 -> 4 | 25 -> 24 | 0.23 -> 0.20 | 0.13 -> 0.12 | 2% -> 3% |
| xmas | candycane (start weapon) | 0.11 -> 0.13 | 69 -> 70 | 124 -> 124 | 0.20 -> 0.23 | 0.77 -> 0.80 | 28% -> 30% |
| xmas | **snowballcannon** | 0.03 -> 0.05 | 42 -> 59 | 62 -> 80 | 0.04 -> 0.06 | 0.17 -> 0.16 | 7% -> 10% |
| xmas | giftbomb | 0.04 -> 0.03 | 3 -> 3 | 25 -> 23 | 0.28 -> 0.25 | 0.12 -> 0.12 | 2% -> 1% |
| xmas | tinselwhip | 0.11 -> 0.11 | 59 -> 60 | 97 -> 99 | 0.17 -> 0.17 | 0.01 -> 0.02 | 0% -> 0% |
| xmas | ornamentlauncher | 0.07 -> 0.10 | 39 -> 38 | 169 -> 173 | 0.32 -> 0.44 | 0.14 -> 0.14 | 5% -> 5% |
| xmas | toymallet | 0.18 -> 0.19 | 58 -> 58 | 130 -> 133 | 0.40 -> 0.42 | 0.02 -> 0.02 | 0% -> 0% |
| australia | **cricketbat** (start weapon) | 0.54 -> 0.36 | 41 -> 49 | 119 -> 126 | 1.56 -> 0.92 | 1.40 -> 1.23 | 72% -> 66% |
| australia | aussieboomerang | 0.05 -> 0.04 | 46 -> 46 | 224 -> 221 | 0.24 -> 0.19 | 0.21 -> 0.18 | 2% -> 1% |
| australia | **thongslapper** | 0.01 -> 0.01 | 66 -> 71 | 61 -> 65 | 0.01 -> 0.01 | 0.02 -> 0.02 | 0% -> 0% |
| australia | vegemitejar | 0.05 -> 0.06 | 8 -> 8 | 32 -> 33 | 0.21 -> 0.26 | 0.15 -> 0.17 | 3% -> 2% |
| australia | **bbqtongs** | 0.02 -> 0.02 | 42 -> 42 | 64 -> 67 | 0.02 -> 0.04 | 0.02 -> 0.03 | 0% -> 0% |
| australia | didgeridooblaster | 0.12 -> 0.12 | 19 -> 19 | 15 -> 15 | 0.10 -> 0.10 | 0.12 -> 0.15 | 2% -> 3% |

Real pack modes, K.O.s per match (ring-outs per match): kitchen 10.1 (3.6) -> 10.4 (3.7), xmas 7.5 (3.6) -> 8.0 (3.8), australia 20.2 (19.3) -> 16.2 (14.9).

The data changes (only `godot/data/extra/<pack>/weapons.json`):

| Weapon | Field | Before | After | Why |
|---|---|---|---|---|
| Cricket Bat | force | 28 | 25 | 1.56 K.O.s/held-min and 0.54 K.O.s/pick: above every base weapon (Giant Mallet 1.01 and 0.41, Flamethrower 1.38 and 0.52), and it is the start weapon of its mode. Now just under the Giant Mallet. Lift 0.6 and force 25 keep it the biggest launch of the pack melee weapons |
| Cricket Bat | cooldown | 1.2 | 1.3 | same |
| Pepper Grinder | dmg | 3.2 | 4.0 | 83 Dmg/held-min was 0.58x the SMG and 0.46x the AK. Now 0.69x the SMG. Still the short-range (22 m) rapid gun |
| Snowball Blaster | dmg | 3 | 4.2 | 62 Dmg/held-min was 0.43x the SMG. Now 0.56x, plus its chill status. Still the weakest rapid gun per bullet |
| Thong Slapper | dmg | 8 | 10 | lowest K.O.s/pick of all 34 weapons measured. Cooldown 0.2 and swing 0.13 untouched (still ultra-fast): 50 damage per second on paper, 240 damage per pick (Big Bat 240, Cordless Drill 216) |
| BBQ Tongs | dmg | 18 | 21 | 64 Dmg/held-min was 0.61x the Trident, the base weapon with the same thrust swing. Reach 3.0 untouched |

Left alone, inside the base band: Frying Pan (heavy, topple 0.85: Hammer-like damage), Cleaver and Rolling Pin (Trident to Spatula level), Flambe Torch (as many K.O.s per pick as the base Flamethrower at half its damage per minute), Hot Soup Pot / Gift Bomb / Vegemite Jar (ball type: same shape as the Snowball Cannon and the Cement Bucket), Giant Candy Cane, Tinsel Whip, Toy Mallet, Ornament Launcher and Aussie Boomerang (between the Cone Launcher and the Throwing Knife), Didgeridoo Blaster (between the Jackhammer and the Spring Glove).

Caveats when reading these numbers:

- Bots swing every melee weapon at the same pace (`BotBrain`: 1 to 2 s between swings whatever the weapon's cooldown), so a fast weapon gets no credit for its speed: the Cleaver, Thong Slapper, BBQ Tongs and Tinsel Whip (and the Cordless Drill) read low here and are stronger in a player's hands. For them damage per pick and damage per second on paper matter more than Dmg/held-min. This is why the Thong Slapper and BBQ Tongs barely move in the table after a 17 to 25% damage buff: about 40 of their Dmg/held-min is kicks.
- Thrust-style melee weapons (Thong Slapper, BBQ Tongs, like the Trident and the Drill; the style is set in `weapon_tuning.json`) hit a narrow line and land less often with bots than cleave or whip weapons.
- Bots now have preferred ranges for the pack ranged weapons (`BotBrain.PREF`: Flambe Torch and Didgeridoo Blaster 4.5 m, the rest 9 to 11 m), so the 7 m weapons are fired from inside their 92% range (the old default 8 m kept bots out of it).
- K.O.s per pick are noisy at this sample size: the unchanged Cleaver read 0.12 and then 0.07 (18 and 11 K.O.s). Treat a difference under about 2x as no difference.
- Bots walk to pack crate weapons, melee too (`Pickups._bot_wants_pack_weapon`, only while `Combat.tuning_active()`, never for the human), instead of only when empty-handed with a ranged weapon. A bot used to hold its start weapon all match.
- Damage is counted for the weapon in hand, so a projectile that lands after a swap is credited to the next weapon.

### 0.6.0 pass: Hey Mate parity (bot pack crates, Cricket Bat launch)

Before: Hey Mate ran 14.1 K.O.s per match against 10.4 (kitchen) and 8.0 (xmas), 91% of them ring-outs (12.8 per match, first K.O. at 7 s), 62% with the Cricket Bat. Start-weapon sweep of the arena (16 matches each, everyone on that start weapon): Cricket Bat 13.7 K.O.s/match (13.5 ring-outs), base Mallet 11.7, spatula 7.5, BBQ Tongs 5.7. So the start weapon's launch, not the arena alone, drove it. Changes: Cricket Bat `force` 25 -> 17 and `lift` 0.6 -> 0.45 (bat start: 8.1 K.O.s, 6.6 ring-outs, first K.O. at 24 s), plus the bot changes above.

Real pack modes, `npm run balance -- --pack kitchen,xmas,australia --matches 30 --bots 7 --seconds 150 --timeout 400`, K.O.s per match (ring-outs per match), same seeds:

| Pack | Before | After |
|---|---|---|
| kitchen | 10.4 (3.7) | 7.6 (3.1) |
| xmas | 8.0 (3.8) | 6.6 (4.2) |
| australia | 14.1 (12.8) | 7.6 (5.8) |

Hey Mate is now 1.0 to 1.15x the other packs (target: within 1.5x). The other two packs fell by 14 to 27% only because their bots now swap weapons too. Cricket Bat share of Hey Mate K.O.s 62% -> 37%; its picks stay about 1 per fighter-minute (start weapon hand-outs).
