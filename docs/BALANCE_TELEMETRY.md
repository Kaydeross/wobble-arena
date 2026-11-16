# Balance telemetry

A headless runner that plays many bot-vs-bot offline matches and prints Markdown balance tables, so balance can be tuned from data before a seasonal release. Tooling only: it reads the sim, never changes combat, physics or bot behaviour.

## Run it

```
npm run balance -- --matches 200 --out balance.md
npm run balance -- --matches 4 --jobs 2 --seconds 20          # tiny smoke, table on stdout
npm run test:balance-tool                                       # selftest of the aggregation (no Godot)
```

Options of `tools/run-balance-matrix.js`: `--matches N` (200), `--jobs N` (CPUs minus 1, max 8), `--bots N` (4), `--seconds N` (90, simulated), `--mode id` (classic), `--maps a,b,c` (arena,rooftops,temple), `--seed BASE` (1), `--out file.md` (default stdout), `--json raw.json` (every match's raw result), `--weapon id` (everyone starts with that weapon), `--selftest`. Progress and failures go to stderr.

Each match is one Godot process running `godot/tests/balance_match.gd`, which prints one line `BALANCE {json}`. You can run a single match by hand:
`Godot --headless --path godot --script res://tests/balance_match.gd -- --no-save --seed=7 --map=arena --classes=kid,bruiser,alien,elder,wobbler`.

`--bots 4` means 4 bots plus the player's seat, which is also driven by a bot brain: 5 fighters, one per class in a normal run. Match i uses seed `base+i`, map `maps[i % n]`, and rotates the classes through the seats, so every class appears equally often (exactly, when matches x fighters is a multiple of 5). A match that crashes or exceeds 120 s is killed, reported on stderr, and counted as FAILED in the header; the tables use the rest. Not in CI.

The player's seat is made a true bot for the run (same difficulty damage scale and run speed as the bots), otherwise the class sitting there would hit harder and look overpowered. Classes also rotate through the seats for the same reason.

## Columns

Per class: **Appearances** (fighter-matches); **K.O.s/match** and **Deaths/match** per appearance; **K.O. share** = this class's K.O.s / all K.O.s; **K/D**; **Ring-out rate** = falls / deaths (share of deaths that were ring-outs, whoever pushed); **Dmg/match** = damage dealt; **Win rate** = matches where the class had strictly the most K.O.s / appearances (ties count as no winner, so rates sum to under 100%).

Per weapon (the weapon in hand when the K.O. was scored; `spatula` is the default melee): **K.O. share**, **Avg TTK**, **Picks** (weapon pickups that were not just ammo top-ups; the starting weapon is not a pick), **Picks/fighter-min**, **K.O.s/pick**.

Crates: crate pick rate = crates taken (every crate: weapons, health, power-ups) per fighter per simulated minute.

## TTK definition

TTK of a K.O. = seconds from the killer's latest respawn (or match start), or from the killer's previous K.O., whichever is later, until this K.O. It is "time to get a kill while alive", not time to kill one victim, so it mixes search time and fight time. Compare it between weapons, not against a stopwatch fight. Ring-outs with no attacker credit are not K.O.s and have no TTK.

## Determinism

The world seed fixes combat.rng, crate drops and bot decisions, the dynamic arena and destructibles are off, and `--no-save` fixes the start spots, so the same seed, map, mode and class list give the same result (checked: identical line apart from the `real_s` wall-clock field). The class override uses no random numbers. Results can differ between Godot versions or after any balance / bot change, which is the point of re-running it.

## Reading OUTLIER flags

The even share is 1 / (number of classes or weapons in the table). A row is flagged **OUTLIER high** when its K.O. share is above 1.5x the even share and **OUTLIER low** below 0.5x. Rows with fewer than 10 K.O.s are marked `low n` instead (too little data; run more matches). `spatula` (the default weapon every fighter starts with and falls back to) is naturally the top weapon; ignore its flag. Weapon shares depend on how often crates hand a weapon out, so check Picks and K.O.s/pick before blaming a weapon: a high share with a normal K.O.s/pick is a spawn-rate effect, a high K.O.s/pick is a strength effect. Bots are not humans: use class flags as a prompt to look, and sanity-check against play. Ring-out rate and K/D show whether a class is hard to keep on the floor or just deals more damage.

## Run time

Measured on the 10-core dev Mac with the default 7 jobs: the 200-match default run (90 s of simulated play each, 5 fighters, 3 maps) took 4 m 24 s wall time (about 9 s of one core per match). A 4-match, 20 s smoke takes about 9 s.
