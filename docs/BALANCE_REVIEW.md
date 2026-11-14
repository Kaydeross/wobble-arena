# Balance review: classes, weapons, buffs, modes and Arcade bosses
Manual-review snapshot of the Construction DLC worktree (`claude/balance-review`). It is a **read-only**
analysis: no gameplay value was changed. Every number is derived from the shipped files listed in
[How the numbers were derived](#how-the-numbers-were-derived); inferred values are marked **[i]**.
## Legend and reference numbers
- **HP/TTK@150**: Godot offline is fixed at **200** HP (web default 200; the web lobby also offers 100/150/200/300/500).
  The 150 column is the owner's reference, reachable only through the web's 150 HP option; for Godot offline multiply
  it by 4/3. TTK assumes body/torso hits, no headshots, ideal range, every pellet/projectile of a volley hitting, no
  misses; reloads count when a magazine runs dry mid-kill. The first pickup's spare ammo is ignored (see **Dmg/pickup**).
- **DPS burst** = damage per trigger ÷ effective trigger cycle; **DPS sustain** adds magazine reload / burst-pool regen;
  **Dmg/pickup** = ideal damage from one pickup (full volley; explosions as a centre hit).
- **Head×**: guns ×2 unless their own `headMul` says otherwise; thrown/knife/arrow ×1.8; boomerang ×1.5; melee has **no
  headshot on web** and ×1.5 in Godot offline (`shared/damage.json` `zones.meleeHead`).
- **Shared** = what web and online play use; **Tuned** = `godot/data/extra/weapon_tuning.json`, applied only in Godot
  offline (or `net_zones`). A cell like `80→60` is shared→tuned.
- **Effective HP** = 200 × class `hp` (no class armour exists); **TTD** is time-to-die against an offline AK-47 body
  stream (60 DPS). Player regen (below 50% HP, +4%/s after 6 s unhit) is not in TTD. Class `head`/`size`/`wide`/`wob`
  are **visual only**: hit spheres are fixed at head 0.4 / chest 0.62 / legs 0.5.
- **[i]** = inferred from code, not a data field: bow cycle 0.73 s (nock 0.28 + full draw 0.45), boomerang cycle ≈1.3 s,
  typhoon cycle ≈1.2 s, arcade class inheritance.
## 1. Classes
| Class | Key | HP× | EHP | TTD@200 / @150 | Spd m/s | Acc | Air | Jump | KB× | Dmg× | Rate× | Reload× | Ammo× | Role / strengths / weaknesses |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Wobbler | wobbler | 1.00 | 200 | 3.33 / 2.50 | 7.50 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | Baseline; every class is +/- against these bars |
| Bruiser | bruiser | 1.30 | 260 | 4.33 / 3.25 | 6.60 | 0.85 | 0.80 | 0.92 | 0.65 | 1.12 | 0.95 | 1.00 | 1.00 | Tank/melee brawler: +30% HP, hard to shove, hits +12%; slow steering and jumps; gun DPS ×1.064 |
| Scamp | kid | 0.75 | 150 | 2.50 / 1.88 | 9.15 | 1.20 | 1.30 | 1.12 | 1.30 | 0.92 | 1.05 | 1.00 | 1.00 | Fastest shared class; huge air/jump; smallest HP and flies 30% further |
| Gramps | elder | 1.05 | 210 | 3.50 / 2.63 | 7.13 | 1.55 | 2.10 | 1.00 | 0.90 | 1.00 | 1.00 | 0.75 | 1.10 | Aerial/skill pick: best air control, fast reloads, +10% ammo |
| Zorp | alien | 0.70 | 140 | 2.33 / 1.75 | 7.65 | 1.00 | 1.25 | 1.18 | 1.10 | 1.00 | 1.20 | 0.80 | 1.50 | Glass cannon economy: 1.5× ammo, 1.2× fire rate, 0.8× reload time; lowest EHP |
| Bulwark | tank | 1.45 | 290 | 4.83 / 3.63 | 6.00 | 0.75 | 0.70 | 0.85 | 0.50 | 1.00 | 0.90 | 1.10 | 1.20 | Shop 1500. Highest EHP (2.07× Zorp), half knockback; slowest feet, worst steering |
| Zippy | dash | 0.85 | 170 | 2.83 / 2.13 | 9.75 | 1.35 | 1.20 | 1.05 | 1.20 | 0.95 | 1.00 | 1.00 | 1.00 | Shop 1200. Fastest class (9.75 m/s), best accel; low HP, flies far |
| Ace | ace | 0.95 | 190 | 3.17 / 2.38 | 7.50 | 1.10 | 1.00 | 1.00 | 1.05 | 1.00 | 1.15 | 0.70 | 1.30 | Shop 2000. Gun specialist: fastest reload, +30% ammo; no HP/melee help |
| Boo | ghost | 0.80 | 160 | 2.67 / 2.00 | 7.95 | 1.00 | 1.70 | 1.28 | 1.20 | 1.00 | 1.00 | 1.00 | 1.00 | Secret (play 10 matches). Floaty: best jump multiplier, low HP |
| Champ | champ | 1.15 | 230 | 3.83 / 2.88 | 7.80 | 1.10 | 1.00 | 1.00 | 0.85 | 1.08 | 1.05 | 1.00 | 1.00 | Secret (win 5). Well-rounded strong: HP, damage, rate and KB-resist |
| Rampage | rampage | 1.10 | 220 | 3.67 / 2.75 | 7.13 | 0.95 | 0.90 | 0.95 | 0.80 | 1.20 | 0.88 | 1.05 | 1.00 | Secret (50 K.O.s). +20% damage at -12% rate (DPS ×1.06), +10% HP |

Notes: class `spd` multiplies 7.5 m/s; `acc` multiplies 40 m/s² ground acceleration; `air` multiplies 14 m/s²;
`jump` multiplies 9.2 m/s jump; `dmg`/`rate` multiply outgoing damage and cooldown recovery; `reload`/`ammo`
multiply reload time and pickup ammo. Bots use Bruiser/Scamp/Zorp/Gramps/Wobbler in that slot order
(`MatchSim.BOT_CLASS_ORDER`), so bot difficulty is partly class-driven. There is no class armour or regen.
## 2. Weapons
### Melee and contact
| Weapon | Key | Type | Dmg | Hits@150 | Cd | TTK@150 | DPS | Ammo | Dmg/pickup | Move× | Force | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ninja Katana | katana | melee | 28 | 6 | 0.42 | 2.10 | 66.7 | 12 | 336 | 1.10 | 11 | Highest melee DPS; slam ×1.7 airborne; ninja-only |
| Big Bat | bat | melee | 40 | 4 | 0.95 | 2.85 | 42.1 | 6 | 240 | 0.90 | 17 | Best shared melee burst; 6 swings per pickup |
| Claw Hammer | hammer | melee | 32 | 5 | 0.75 | 3.00 | 42.7 | 8 | 256 | 1.00 | 16 | Arcade starter; 256 dmg per pickup vs a 392 HP boss |
| Cordless Drill | drill | melee | 12 | 13 | 0.28 | 3.36 | 42.9 | 18 | 216 | 1.05 | 6 | DLC; fast but low force, short reach (1.35) |
| Pipe Wrench | pipewrench | melee | 38 | 4 | 1.10 | 3.30 | 34.5 | 6 | 228 | 0.88 | **24** | DLC; best melee force-per-hit on stage 1 crew / Supervisor |
| Spatula | spatula | melee | 24 | 7 | 0.65 | 3.90 | 36.9 | ∞ | ∞ | 1.00 | 13 | Default weapon, never breaks |
| Spirit Level | spiritlevel | melee | 16 | 10 | 0.45 | 4.05 | 35.6 | 12 | 192 | 1.05 | 8 | DLC; long thin reach (2.85) |
| Tape Measure | tapemeasure | melee | 20 | 8 | 0.60 | 4.20 | 33.3 | 10 | 200 | 1.00 | 10 | DLC; longest thin reach (3.30) |
| Live Wire | wirewhip | melee | 18 | 9 | 0.55 | 4.40 | 32.7 | 10 | 180 | 1.05 | 9 | DLC/Construction; long reach (3.15) |
| Trident | trident | melee | 20 | 8 | 0.70 | 4.90 | 28.6 | 8 | 160 | 1.00 | 9 | Throwable: 22–42 dmg / 7–11 force (charged 0.9 s) |
| Giant Mallet | mallet | melee | 28 | 6 | 1.30 | 6.50 | 21.5 | 4 | **112** | 0.80 | **30→26** | Lowest melee DPS, highest force/topple (0.85→0.75): a ring-out tool |
| Spring Glove | glove | gun/punch | **0** | — | 0.85 | n/a | 0 | 8 | 0 | 1.00 | 20 (22) | Pure knockback, no damage at all; only ring-outs/K.O. assists |
| Jackhammer | jackhammer | gun/punch | 10 | — | 0.22 | 3.08 | 45.5 | 20 | 200 | 0.85 | 10 (14) | DLC; contact range 5.5, 0.5 topple |

Melee mechanics: all melee swings deal a default ×1.3 "slam" damage when airborne (Katana ×1.7); the Typhoon's
every third swing is a ×1.6 cyclone (not shared outside Ninja). Melee headshots exist only in Godot offline
(×1.5) — on web/online a melee hit is always 1.0. Melee `stiff` is animation spring stiffness only.
### Ranged and thrown
`Shared→tuned` where the overlay changes it. `Dmg/pickup` is ideal, all projectiles hitting.

| Weapon | Key | Type | Dmg/trigger | Head× | Cd | TTK@150 | DPS burst | DPS sustain | Ammo (mag) | Dmg/pickup | Range | Force (max) | Move× | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Shotgun | shotgun | gun | 80→64 | ×2 | 0.80 | 0.80→1.60 | 100→80 | 59→47 | 10 (5) | 800→640 | 40 | 3.5→2.2 (13→9) | 0.95 | 8 pellets; full damage only ≤2.5 m, 12% at 15 m+ |
| Sniper | sniper | gun | 50→42 | ×2 | 1.30 | 2.60→3.90 | 38.5→32.3 | 25.5→21.4 | 8 (4) | 400→336 | 140 | 8→5 (12→8) | 0.80 | Longest range; head 100→84 (2 headshots kill 150 either way) |
| Mammoth Pistol | mammoth | gun | 15 | **×15.33→×8** | 0.90→1.40 | 13.50→18.00 | 16.7→10.7 | 10→7.5 | 8 (3) | 120 | 110 | 11→7 (8) | 0.95 | **Head 230 (one-shot at 150/200 except Bruiser/Bulwark) shared / 120 tuned**; body TTK worst in game |
| Revolver | revolver | gun | 31→26 | ×2 | 0.62 | 2.48→3.10 | 50→41.9 | 32→26.8 | 9 (6) | 279→234 | 70 | 9→6 (10→7) | 1.00 | Tuned 26 dmg needs all 6 rounds to kill 150 |
| AK-47 | ak | gun | 8→6 | ×2 | 0.10 | 1.80→2.40 | 80→60 | 48→36 | 45 (30) | 360→270 | 105 | 3.4→1.8 (4→2.2) | 0.95 | Shared best automatic body TTK |
| SMG | smg | gun | 5→4 | ×2 | 0.065 | 1.88→4.21 | 76.9→61.5 | 40→32 | 45 (30) | 225→180 | 80 | 2.2→1.2 (3→1.8) | 1.00 | Close-mid bullet hose |
| Dual Uzis | uzi | gun | 4.4→3.4 | ×2 | 0.06 | 2.04→4.74 | 73.3→56.7 | 39→30.2 | 80 (40) | 352→272 | 70 | 2→1 (2.8→1.6) | 1.00 | Tuned: 45 rounds needed but only 40 per mag |
| Minigun | minigun | gun | 4→3.2 | ×2 | 0.045 | 1.66→2.07 | 88.9→71.1 | 47→38 | 150 (75) | 600→480 | 125 | 2→1 (2.6→1.3) | 0.60 | Spin-up 0.45 s (not in TTK); -40% move speed |
| Flamethrower | flame | gun/flame | 1.9/tick | — | 0.06 | 4.68 (direct) | 31.7 | 31.7 | 65 | 124+burn | 10 | 1.2→0.6 (1.6→1.2) | 0.85 | Burn 3.2 s = 2.2 dmg/0.4 s; ≈37 DPS while burning |
| Grenade Launcher | glauncher | glauncher | 66 | — | 0.85→1.15 | 1.70→2.30 | 77.6→57.4 | 77.6→16.5 | 6→4 | 396→264 | — | 22 | 0.90 | Splash r4.7; tuned burst 3 then 1 charge/4 s |
| Cluster Launcher | cluster | glauncher | 144 (3×48) | — | 1.10→1.50 | 1.10→1.50 | 130.9→96 | 130.9→32 | 4→3 | 576→432 | — | 16 | 0.90 | 3 grenades fanned ±0.16 rad; splash r3.6; all 3 hitting is close-range only |
| Rocket Launcher | rocket | rocket | 70 | — | 1.25→1.80 | 2.50→6.80 | 56→38.9 | 56→14 | 4→3 | 280→210 | — | 24 | 0.85 | Splash r6, falloff; tuned burst 2 then 1/5 s |
| Meteor Launcher | meteor | rocket | 115 + 6×34 | — | 2.00→3.20 | 2.00→6.00 | 57.5→35.9 | 57.5→19.2 | 3→2 | 345→230 | — | 34 | 0.80 | Highest burst: direct 115 + up to 204 bomblets (r3.4 each); two direct hits kill 150 |
| Net Gun | net | net | 0 | — | 1.00 | n/a | 0 | — | 1 | 0 | 16 | 0 | 0.95 | Pins every enemy in r2.1 for **4.5 s (2.5 tuned)**; one shot |
| Snowball Cannon | snow | ball | 22 (26.6 max) | — | 1.30 | 7.80 | 16.9 | 16.9 | 2 | 44 (53 max) | — | 30→24 | 0.90 | Rolls/grows to 1.7 r, topples 1.5, can hit several; tuned only force |
| Snake Shooter | snake | snake | 15/bite | — | 0.90 | 8.10 | 16.7 | 16.7 | 3 | 45 | — | 9 | 1.00 | 3 bites (3 more after a K.O.), homing, 14 s life |
| Twin Fang Bow | bow | bow | 96 (2×48) | ×1.8 | 0.30 | 0.73 | 131.5 | 131.5 | 12 volleys | **1152** | — | — | 0.95 | Full draw 0.45 + nock 0.28 [i]; 24 arrows per pickup |
| Throwing Knives | knife | knife | 30 | ×1.8 | 0.85 | 3.40 | 35.3 | 35.3 | 10 | 300 | — | 5 | 1.05 | Fast straight projectile, 0.88 assist |
| Shuriken | shuriken | shuriken | 20 (2×10) | ×1.8 | 0.60 | 4.20 | 33.3 | 33.3 | 14 throws | 280 | — | 3.5 | 1.10 | Two homing stars per throw |
| Typhoon Blades | typhoon | typhoon | 39 (3×13) | ×1.8 | 0.50 | 3.60 | 32.5 | 32.5 | 8 throws | 312 | — | 5 | 1.05 | Piercing, returning blades: cycle return-gated ≈1.2 s [i] |
| Boomerang | boomerang | boomerang | 24 (48/two hits) | ×1.5 | 0.50 | 7.80 | 18.5 | 18.5 | 5 | 120 | — | 6 | 1.05 | Can hit out + back; cycle ≈1.3 s [i] |
| Air Blower | blower | blower | 0→2.5/puff | — | 0.06 | n/a | 0→41.7 | — | 100 | 0→**≈149** | 9 | continuous | 0.90 | Shared: pure push/stun. Tuned: 2.5 per puff, drain 28/s, just short of a 150 kill |
| Nail Gun | nailgun | gun | 10 (2×5) | ×2 | 0.16 | 2.24 | 62.5 | 45.8 | 48 (24) | 480 | 20 | 2.5 (5) | 1.00 | DLC; 2 pellets, 20 m range |
| Cone Launcher | conelauncher | knife | 34 | ×1.8 | 0.75 | 3.00 | 45.3 | 45.3 | 6 | 204 | — | 14 | 0.95 | DLC; thrown cone |
| Cement Bucket | cementbucket | ball | 26 | — | 1.30 | 6.50 | 20 | 20 | 3 | 78 | — | 28 | 0.85 | DLC; heavier, shorter snowball |
| Angle Grinder | anglegrinder | gun/flame | 1.5/tick | — | 0.08 | 7.92 | 18.8 | 18.8 | 30 | 45 (+burn) | 5 | 1.2 (1.6) | 0.90 | DLC; tiny flame cone, burn 1.5 s, ≈24 DPS, ≈70 max per pickup |

Weapon-system notes: `cooldown` is the trigger cycle; **`runtime cooldown = base cooldown ÷ class `rate`**
(rate 0.88–1.2 therefore changes DPS by ±20%). Shotgun falloff is [2.5 m…15 m, 12%]; explosions use linear
falloff (0 at radius) and half damage to self. Overlay changes not shown above: spread/bloom/wobble, recoil,
`swapCd` draw time, net trap 4.5→2.5 s, snow force 30→24, mallet force 30→26, flame force/push cap, crate
weight for meteor 1.4→0.6. See `godot/data/extra/weapon_tuning.json`. **Online and web never apply the overlay**,
so tuned columns are Godot-offline only.
## 3. Buffs, kits and mutators
### Pickups and status effects
| Source | Effect | Stacking | Duration | Appears in | Notes |
| --- | --- | --- | --- | --- | --- |
| Health Pack | Heal 60% of max HP | No stack; capped at max | instant | classic, melee, guns, ninja, duel, t2–t4, explosive (35.6% of its crate pool), mega (27.6%), giant (19.3%), construction (31.4%), lowg, arcade ambient crates | Arcade **enemies** heal only 5/8/10% (easy/normal/nightmare) via `heal_frac` |
| Speed Boost | ×1.4 run speed (`spd_t`) | Refresh to 12 s, no stacking | 12 s | all pools above incl. lowg; not mega/pillars | ×1.4 target speed only: Scamp/Zippy reach 12.8–13.7 m/s |
| Damage Boost (rage) | ×1.5 outgoing damage | Refresh to 12 s | 12 s | same pools | Multiplies with mode/class/headshot; huge on snipers |
| Shield | ×0.5 incoming damage | Refresh to 12 s | 12 s | same pools | Best defensive pickup; doubles effective HP |
| Player regen | +4% max HP/s, capped at 50% | — | persistent | every mode, player only (not bots) | Starts after 6 s without being hit; no full heal |
| Spawn protection | invulnerable | — | 2.5 s (0.3 on practice) | every mode | Also 1.0 s get-up immunity after topple |
| Knockdown | ×0.5 damage taken | independent | until get-up | every mode | Nets suppress the downed bonus (`trap_t`) |
| Shove parry | 0.22 s front parry cancels a melee swing, staggers attacker | — | 0.22 s | Godot offline (tuned) only | `Combat.try_parry`; web has no parry |
| Air recovery | clears stun, keeps 30% knock, 13 m/s burst toward stick, 0.2 s invuln, 0.5 s air control | one charge, back on landing/6 s | instant | Godot offline (X / touch RECOVER) | Bots never use it; a large survivability buff vs ring-outs |
| Ninja dash / Pillars dash | 24 m/s burst, 3 charges, 4 s/charge, 0.45 s min gap | charges | instant | Ninja weapons; Pillars always | Dash gear: katana/shuriken/knife/typhoon; Pillars: any weapon |
| Low gravity | gravity 0.15 (Moon Drift), 0.4 (Chaos, 8 s), 0.5/1.5 (online host) | sets `grav_scale` | mode / 8 s / match | Moon Drift, Chaos, online rules | Jump becomes 7.4 m/s under 0.3 gravity; lobbed projectiles float too |
| Infinite ammo | guns/thrown never consume ammo; burst pools still spend; melee tools still break | — | match | online host rule | `cfg.inf`; ladder mode has the same spare-ammo effect |
| Crate rate | crate every uniform 3–5 s × rate: slow 1.2, normal 0.42, fast 0.28, chaos 0.15 | — | match | online host rule; Godot offline fixed `normal` | Max 10 live crates, 45 s lifetime → normal ≈35.7 crates/min uncapped |
| Bot pickup behaviour | bots seek heals <85%, power-ups always, weapons only when empty-handed | — | — | every brawl mode | Arcade enemies also take power-ups: a rage/shield boss is a serious swing (see §5) |
| Aim assist | Kids mode auto-aim/auto-fire/edge guard; Settings `aim_mode` hold/toggle; `PLAYER_ASSIST` 0.8 offline | — | match | offline; aim-mode/assist work **in flight** is referenced by name only | Kids mode: half coins, no leaderboard; online/web gun assist is a perfect 1.0 lock |
### Mode and arena mutators
| Source | Effect | Stacking | Duration | Where | Notes |
| --- | --- | --- | --- | --- | --- |
| Mega Damage | damage ×2, knockback ×0.8, 3 lives | multiplicative with buffs | match | `mega` | TTK halves: AK body 0.9 s, sniper head one-shot; 3 lives + shrinking map |
| Giant | damage ×2, **max HP ×2**, KB ×1.1, model/hit-spheres ×1.5, melee tip ×2.2, explosion r ×1.4, glove force ×2.1, mammoth dmg ×0.65 | mode flags | match | `giant` | Damage and HP both double → TTK is ~unchanged; the real gain is reach and +10% KB |
| Explosive | HP = 300 always, launchers only, no K.O. limit | class HP applies on top | match | `explosive` | Bruiser = 390 HP; 8-key crate pool with 35.6% heal |
| Pillars | knockback ×0.4, one life, new weapon every 10 s from a 9-weapon pool, 3-min clock | — | match | `pillars` | Force is reduced 60%: ring-outs are hard; most K.O.s wins |
| Moon Drift | gravity 0.15, SMG start, 12-gun pool | — | match | `lowg` | No K.O. limit/lives → endless; air fights |
| Chaos | every 15–25 s a random event: crate rain ×5, low gravity 0.4/8 s, knockback storm ×2.5/10 s, one random Giant 12 s (double HP, ×1.5 dmg), speed surge ×1.4/8 s, floor quake 9 s | events don't stack | event | `chaos` (5v5) | 3 s warning; never repeats the same event twice in a row |
| Shrinking floor | floor shrinks from 64→16 m (`shrink`) or 80→22 m (`squeeze`), then grows/rests | — | match | Mega, and PM's deadline event | Shrink kills bots that don't step in (bots get `shrink_guard` offline) |
| Dynamic arena | wobble 0.3 m/6 s, tilt 0.5 m/12 s, quake holes (from 12 s), drift blocks ±2 m | one kind per match | match | Settings default **random** offline; online host picks; off in Arcade | Changes footing, not damage |
| Team rules | teammates cannot damage each other; team K.O. totals; spawn colour | — | match | `duel`, `t2`–`t4`, `tdm`, `chaos` | Arcade co-op seats also have friendly fire off by default |
| Bot skill | `easy/normal/hard/insane` (below) | per match | match | offline wizard; Arcade stage table bakes its own per-bot skill | Arcade difficulty scales stats, **not** AI skill |
### Arcade kits and boss buffs
| Source | Effect | Stacking | Duration | Where | Notes |
| --- | --- | --- | --- | --- | --- |
| Enemy trade kit | Melee kit re-equipped; ammo refilled to full once below max(2, 30% of max) | — | every 0.5 s | all stages | Guns taken from crates are not refilled; a dry boss returns to melee |
| Boss phases | +10% speed and +20% damage each (cumulative ×1.21 speed / ×1.44 damage) | multiplicative | until next phase | stages 2–6 at 66% / 33% HP | Toast only; also fires The Client's change request |
| Backup call | Summon 1 Bluey at ≤50% boss HP | none | once per attempt | Supervisor | 180 HP normal, spawned far away, 1.5 s invulnerability (see §5) |
| Tool crate | Random nailgun / jackhammer / angle grinder / cone launcher / cement bucket | — | every 20 s (× event timing) | boss stages | First to the crate; the boss may claim it while holding melee |
| Deadline shrink | Floor holds, then closes to 18 m at 2 m/s | — | first hold 20 s; later cycles use fixed 3 s/5 s holds | Project Manager | Spawn and revive spots are filtered to the live floor |
| Scope creep | +1 extra tradie, at most 3 alive | cap 3 | every 25 s raw | Project Manager | Extras are Wobbler-class, 180 HP on Normal |
| Change request | Boss and every live seat get a random melee tool | every phase | at 66% / 33% | The Client | RNG swing (drill vs pipe wrench); map's `phases` param is unused |
| Enemy power-ups/heals | Boss/crew take speed/rage/shield and heal packs (5/8/10% HP) | — | match | all stages | Rage + phase 2 = ×2.16 damage; shield doubles boss EHP |

### Difficulty scaling
Bot skill (`shared/difficulties.json`, `bot_brain.gd`). Bot speed is absolute and then multiplies the bot's class
`speed_mul` (so the same skill gives a Bruiser bot 3.9 m/s and a Scamp bot 5.4 m/s at Normal).

| Skill | Speed | Damage× | Attack× | Sight | Kick× | Jump | React s | Aim error | Crate grab |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Easy | 3.0 | 0.30 | 0.55 | 12 m | 0.6 | 0 | 0.45 | ±2.2 | 9 m |
| Normal | 4.4 | 0.45 | 1.00 | 20 m | 1.0 | 0 | 0.25 | ±1.1 | 15 m |
| Hard | 5.4 | 0.70 | 1.70 | 30 m | 1.5 | 0.35 | 0.12 | ±0.45 | 32 m |
| Insane | 6.4 | 1.00 | 2.60 | 60 m | 2.2 | 0.70 | 0.04 | ±0.12 | 70 m |

Arcade difficulty (`stages.json` `difficulties`): scales HP/damage/speed/event timing/lives/coins; stage AI
skill is fixed by the stage's `bots[].difficulty` (Normal / Hard / Insane).

| Difficulty | HP× | HP floors crew/boss | Damage× | Speed× | Events slower | Lives | Coins× |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Easy | 0.4 | 0.8 / 1.2 | 0.35 | 0.85 | ×1.5 | 5 | 0.6 |
| Normal | 0.7 | 0.9 / 1.4 | 0.65 | 1.0 | ×1.15 | 4 | 1.0 |
| Nightmare | 1.0 | none | 1.0 | 1.0 | ×1.0 | 3 | 1.5 |
## 4. Modes
Offline rules are **not exposed**: Godot offline always uses 200 HP, knockback 1.0, crate rate `normal`,
infinite ammo off, gravity from the mode preset, and the mode's own K.O. limit. The web Host/Game-Rules sheet
(HP 100/150/200/300/500, gravity 0.5/1/1.5, knockback 0.5–3.0, crate slow/normal/fast/chaos, infinite ammo)
is the only source of those knobs, and online is the only place Godot sees them. A **limit of 0 means no win
condition** — the match only ends by quitting (except lives/ladder/clock modes).

| Mode (id) | Teams | HP | Lives | Limit | Grav | Dmg× | KB× | Crates | Bots | Mutators / win condition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Classic | FFA | 200 | 0 | **0** | 1 | 1 | 1 | 24 weapons, heal 8.5%, power-ups 6.4% | 1–7 (3) | Endless by default; web's limit buttons (5/10/20) are not in the Godot wizard |
| Melee Only | FFA | 200 | 0 | **0** | 1 | 1 | 1 | 8-key pool: bat 18.9%, mallet/glove/trident 9.4% each, heal 30.2%, power-ups 22.6% | 1–7 (3) | Endless; not actually all-melee (glove is a gun, trident throws) |
| Guns Only | FFA | 200 | 0 | **0** | 1 | 1 | 1 | 13 guns + heal 14.5%; launchers 4.5% each | 1–7 (3) | Endless; SMG start |
| Ninja | FFA | 200 | 0 | **0** | 1 | 1 | 1 | katana/typhoon/shuriken/knife 14.7% each, heal 23.5% | 1–7 (3) | 3 dashes; shuriken start; endless |
| 1v1 Duel | 1v1 | 200 | 0 | 5 | 1 | 1 | 1 | classic pool | 1 | First to 5 team K.O.s |
| 2v2 / 3v3 / 4v4 | 2–4 | 200 | 0 | 10/15/20 | 1 | 1 | 1 | classic pool | 3/5/7 | Team K.O. totals; no friendly fire |
| Team Deathmatch | 2 teams, flex | 200 | 0 | 30 | 1 | 1 | 1 | classic pool | odd 1–7 | Sides sized from bot count (default 2v2) |
| Deathmatch | FFA | 200 | 0 | 20 | 1 | 1 | 1 | classic pool | 1–7 (3) | First to 20 K.O.s |
| Sudden Death | FFA | 200 | 1 | 0 | 1 | 1 | 1 | classic pool | 1–7 (3) | One life, one K.O./fall eliminates; last standing |
| Chaos | 5v5 | 200 | 0 | 50 | 1 | 1 | 1 | classic pool | 9 | Random event every 15–25 s (see above); 8 large arenas only |
| Explosive | FFA | **300** | 0 | **0** | 1 | 1 | 1 | 4 launchers incl. meteor, heal 35.6% | 1–7 (3) | Endless; rocket start; class HP applies on top |
| Pillars | FFA | 200 | **1** | 0 | 1 | 1 | **0.4** | none (weapon every 10 s: 9-weapon weighted pool) | **7 fixed** | 3-min clock, most K.O.s wins; fall = out; launchers banned |
| Mega Damage | FFA | 200 | **3** | 0 | 1 | **2** | 0.8 | 7 weapons, heal 27.6% | 1–7 (3) | 3 lives, shrinking arena maps; ends when one survivor |
| Giant | FFA | 200 (×2 = 400) | 0 | **0** | 1 | **2** | 1.1 | 8 weapons, heal 19.3% | 1–7 (3) | Endless; huge reach/hit spheres; damage and HP both double |
| Weapon Ladder | FFA | 200 | 0 | ladder | 1 | 1 | 1 | none; ammo effectively endless | 1–7 (3) | 12 rungs (SMG→AK→Uzi→Shotgun→Revolver→Sniper→Bow→Shuriken→Knife→Grenade→Bat→Spatula); 12 K.O.s wins |
| Moon Drift | FFA | 200 | 0 | **0** | **0.15** | 1 | 1 | `dropAllow`: 12 guns + heal/PU | 1–7 (3) | Endless; low gravity; SMG start |
| Construction | FFA | 200 | 0 | **0** | 1 | 1 | 1 | **3 tools** (hammer 19.6%, wirewhip 19.6%, blower), heal 31.4% | 1–7 (3) | DLC 9 tools are **not in the crate pool** (see §6); hammer start |
| Sandbox / Practice | FFA / dummies | 200 | 0 | 10 / 0 | 1 | 1 | 1 | custom / rack | 1–7 / 10 dummies | Sandbox test run caps at 10 K.O.s; Practice never scores |

Mode notes: `classic` has no preset limit in `shared/modes.json` (`MODE_DEFAULTS.limit = 0`), and the Godot
wizard/settings never set `limit`, so **offline Classic is endless** even though the web has 0/5/10/20 buttons.
Teams modes set `bots = teams × 2 - 1` (Duel 1, 2v2 3, 3v3 5, 4v4 7); TDM makes sides even from an odd bot
count; Pillars fills 7 pillars; Practice always 10 dummies. The Setup Wizard has five pages (Game type, Arena, Players, Character, Start) and saves mode, map, dynamic arena, destructibles, bots, difficulty and class; it has no HP/crate/KB/gravity/infinite-ammo/K.O.-limit controls. Explosive/Giant/Moon Drift/Construction have neither a limit nor
lives, so they too never end on their own. Arena pool per mode: `ModeRules.MODE_MAPS` (e.g. Mega only shrink/
squeeze; Giant playroom + the four big arenas; Chaos the eight large maps).
## 5. Arcade bosses (Construction DLC)
Six stages, one generated building site each (`sitegen`, seed per stage/attempt), shared lives 5/4/3 by
difficulty, a downed seat auto-revives in 6 s while a teammate is up; crew/enemies never respawn; a **ring-out
is not a K.O.** (the enemy is put back with its health). Boss phases at 66% / 33% HP: **×1.1 speed and ×1.2
damage per phase** (cumulative ×1.21 speed / ×1.44 damage). Enemy trade kits are topped up every 0.5 s (melee
only); guns taken from crates are not refilled. Event `every` values below are raw: Normal multiplies them ×1.15 (Easy ×1.5, Nightmare ×1.0).

**Exact Supervisor backup mechanic (verified in code).** Stage 4 (`supervisor`, `stages.json`), event
`backup_call`, `every: 0.0`, threshold **0.5** of max HP, `summon_count: 1`, `summon_bots: ["Bluey"]`.
`StageEvents.update` checks every sim step until `boss_frac() <= 0.5`; then `e.done = true` and `_backup()`
calls `spawn_minion("Bluey")` once per stage attempt. Cap = **1 extra body**; no repeat, no respawn. The minion
is a Wobbler (not Kid-class), customised from the **stage 1 Bluey** entry: pipe wrench, 180 HP on Normal
(220 Nightmare, 160 Easy), ≈11.1 DPS, 4.18 m/s, 1.5 s spawn invulnerability, spawned at the farthest of six
random floor spots from the nearest seat. It can take power-ups and heals (8% HP per pack). It is **not** a
"pressed/aggro" trigger: any route to 50% boss HP fires it, at any distance; at 50% the boss has already had its
first phase buff, and the summon lands between phases 1 and 2 (a pressure spike).

| # | Boss | Table HP | Easy / Normal / Nightmare HP | Walk solo/co-op m/s | Weapon (reach) | DPS vs player P1 solo/co-op | Force / topple | Ability / crew |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2 | Engineer | 2.8× | 240 / 392 / 560 | 5.70 / 7.91 | drill (1.35) | 33.2 / 30.1 | 6 / 0.05 | Load-test crates 3× every 12 s (2.5 s warning, 30 dmg/12 force, can hit the boss); tool crate every 20 s; 1 boss |
| 3 | Designer | 3.4× | 272 / 476 / 680 | 6.18 / 8.56 | spiritlevel (2.85) | 31.0 / 28.1 | 8 / 0.1 | 3 revision pads (bounce ×1.6) for 8 s every 15 s; tool crate; 1 boss |
| 4 | Supervisor | 3.6× | 288 / 504 / 720 | 4.28 / 5.93 | pipewrench (1.80) | 10.0 / 9.1 | **24 / 0.65** | Backup call at 50% (1 Bluey); tool crate; 1 boss |
| 5 | Project Manager | 4.0× | 320 / 560 / 800 | 5.13 / 7.12 | tapemeasure (3.30) | 22.6 / 20.5 | 10 / 0.15 | Floor deadline shrink (first hold 20 s Nightmare / 23 s Normal, then closes at 2 m/s to 18 m); scope creep +1 every 25 s (max 3 extras); tool crate |
| 6 | The Client | 4.8× | 384 / 672 / 960 | 5.91 / 8.20 | mallet (giant reach 4.62) | 20.1 / 18.3 | **30 / 0.85** | Change request at 66/33%: boss **and every live seat** get a random melee tool; always Giant (×1.5 model/spheres, double HP, ×1.5 dmg offset by /1.5 table scale); tool crate; 1 boss |

"Walk solo/co-op" and the DPS split exist because arcade enemies **inherit the MatchSim slot class** and
`_dress()` overrides `hp`/speed/damage but not `cls_dmg`, `cls_rate`, `cls_kb`, `phys.*_mul`. Solo stage crew
therefore start at slots 1… → Bruiser (bosses are Bruiser class: ×0.65 knockback taken, ×0.88 speed, ×1.12
damage, ×0.95 rate); in 2-seat co-op the first crew slot becomes Kid (×1.30 KB taken, ×1.22 speed, ×0.92
damage, ×1.05 rate). That is why co-op bosses are ≈39% faster and take twice the knockback, while the DPS
shown after the slash is ≈9% lower. This is a real cross-mode inconsistency, not a table field — fix by
giving arcade bots an explicit class (e.g. Wobbler) in `_dress()`.

| Stage | Fight | Crew (normal) | Boss/crew HP (normal) | Events / shape |
| --- | --- | --- | --- | --- |
| 1 Tradies | No boss: 4 crew in Bruiser/Kid/Zorp/Gramps slot order (solo), effective 3.9–5.1 m/s | hammer, pipewrench, wirewhip, tapemeasure | 4 × 180 = 720 | No events; first "gear check"; player starts with 8-swing hammer |
| 2 Engineer | 1 boss | drill | 392 | Falling-crate zone + a free tool every 20 s |
| 3 Designer | 1 boss | spiritlevel | 476 | Bounce-pad mobility, then a free tool |
| 4 Supervisor | 1 boss | pipewrench | 504 + 180 summon at 50% | CC/summon fight; low boss damage, high shove |
| 5 Project Manager | 1 boss | tapemeasure | 560 + up to 3 × 180 extras | Closing floor + adds; area-denial fight |
| 6 The Client | 1 boss | mallet (Giant) | 672 | Tool-swap RNG + 4.62 m reach + highest force |

Documented probe results (`godot/tests/arcade_balance.gd`, 8 seeds; a scripted melee player that never dodges —
a crude yardstick, copied from `docs/CONSTRUCTION_DLC.md`): Normal wins/HP-left: Tradies 6/8, 42%; Engineer 8/8,
75%; Designer 7/8, 54%; Supervisor **2/8, 24%**; PM 3/8, 28%; Client 3/8, 27%; all stages 29/48 (60%). Easy
45/48 (94%), Nightmare 13/48 (27%). Supervisor is still the worst stage for the probe on Normal/Nightmare (0/8
on Nightmare) because its pipe wrench force is not scaled by `dmg_scale` and it is the tankiest low-damage boss.
**Supervisor fairness read:** HP 504, 11.6 dmg per pipe hit, 10 DPS, but force 24/topple 0.65 per 1.1 s swing is a
chain-shove; one 180 HP summon at 50% roughly doubles incoming bodies and adds ~110% DPS if both engage. It is readable
(toast + 1.5 s invuln) and one-shot, but untelegraphed and not "being pressed" — the biggest difficulty spike for a non-dodger.
## 6. Cross-cutting analysis
### Outliers
| Category | Outlier | Numbers | Read |
| --- | --- | --- | --- |
| Burst DPS | Cluster Launcher | 130.9 shared / 96 tuned (sustain 32) | 3 grenade splash; close-range only; tuned sustain is 3× worse than burst |
| Single-shot potential | Meteor Launcher | 115 direct + up to 204 bomblets = 319 | Two direct hits kill 150 (2 s); tuned 2 ammo, 1 charge/6 s |
| Burst DPS | Shotgun | 100 shared / 80 tuned at ≤2.5 m | 8 pellets; falls to 12% past 15 m; best "melee-range" gun |
| Ammo economy | Twin Fang Bow | 1152 ideal damage per pickup (24 arrows) | Massive if arrows land; 12 volleys, not 12 arrows |
| Lowest DPS (damage weapons) | Mammoth body / Snowball / Snake / Boomerang | 16.7 / 16.9 / 16.7 / 18.5 | Mammoth is a headshot weapon (shared 230 one-shot); snow/snake/boomerang are utility/area |
| No-damage weapons | Spring Glove, Net Gun, Air Blower (shared) | 0 | Glove = ring-out tool; Net = 4.5 s pin (2.5 tuned); Blower tuned max ≈149 < 150 |
| Lowest TTK | Shotgun 0.8 s, Bow 0.73 s, Cluster 1.1 s, AK 1.8 s | — | All require ideal range/volley; sniper head 1.3 s |
| Worst body TTK | Mammoth 13.5 s shared / 18 s tuned; Mallet 6.5 s | — | 10–13 body hits needed; Mallet's value is force, not damage |
| Melee DPS | Katana 66.7; next Bat 42.1; Mallet 21.5 | — | Katana is ninja-only and 3.1× the mallet's DPS |
| Survivability class | Bulwark 290 EHP / 0.5 KB taken; Zorp 140 EHP | 2.07× EHP spread | Bruiser 260 is second; Scamp 150 |
| Mobility class | Zippy 9.75 m/s, Scamp 9.15; Bulwark 6.0 | +63% speed spread | Speed boost stacks ×1.4 → Zippy 13.65 m/s |
| Boss HP | The Client 672 HP normal (960 nightmare) | 3.36× a 200 HP player | vs a 256-damage hammer pickup: 2.6 hammers + crate RNG |
| Buff stack | Mega + rage + headshot | ×2 ×1.5 ×2 = ×6 on a body-scaled stat | Sniper head 50 becomes 300; every 200 HP class is one-shot |
| Ring-out stack | Chaos knockback ×2.5 × Scamp 1.3 × Giant 1.1 | ×3.575 force taken | vs Pillars 0.4 × Bulwark 0.5 = ×0.2: ~18× spread |
### Melee vs ranged, ring-out, headshots and ammo
- **Melee vs ranged gap.** Best melee DPS is 66.7 (Katana, ninja-only) or 42.9 (Drill) vs 80–100 for AK/
  Minigun/Shotgun; melee TTK is 2.1–6.5 s at 1.35–3.3 m reach, while guns kill in 0.8–3.9 s at 20–140 m. Melee
  tools compensate with force (9–30 vs 1.2–9 for guns) and with the tuned shove-parry, i.e. melee is a
  displacement/ring-out role, not a damage role. The **"Melee Only" mode's 0-damage glove** makes this starker:
  excluding glove, only Bat/Trident/Mallet deal damage from its crate pool.
- **Ring-out / force power.** Incoming velocity = weapon force ×0.8 × match `kb`/`kbMul` × victim class `kb`
  (×0.4 for light <8 hits). Highest: Meteor 34, Mallet 30 (26 tuned), Snowball 30 (24), Pipe Wrench 24, Rocket 24,
  Glove 20/22. Pillars lowers it to ×0.4, Mega ×0.8, Giant ×1.1, Chaos storm ×2.5; class KB runs 0.5–1.3.
  Effective push therefore spans ×0.16 to ×3.575 of nominal, and `maxForce` only caps gun pushes (melee is
  uncapped). Arena edges are the win condition in Pillars/lava maps; a low-KB class in Pillars can be nearly
  unringable.
- **Headshots.** Guns ×2 (Mammoth shared ×15.33 = 230 = one-shot at the 200/150 HP settings (except Bruiser/Bulwark);
  tuned ×8 = 120, still a 2-headshot kill), thrown/knife/arrow ×1.8, boomerang ×1.5, melee ×1.5 offline only,
  explosions/ball/snake/flame never headshot. Offline zones also reduce arms to 0.85 and legs to 0.75 (web body
  shots are always 1.0). Headshot-dependent balance: Mammoth, Sniper (100→84), Revolver (62→52), Shotgun volley
  (8×20=160 close if all pellet heads).
- **Ammo economy.** Guns pay for their DPS in magazine/reload downtime; the tuned heavy launchers deliberately
  become burst-then-wait (Rocket sustain 14 vs 56 burst; Meteor 19 vs 57; Grenade 16.5 vs 57). Multi-projectile
  ammo is counted as **triggers**, not projectiles: Bow 12 volleys = 24 arrows; Shuriken 14 throws = 28 stars;
  Typhoon 8 = 24 blades; Cluster 4 = 12 grenades. Melee tools break after 4–18 swings (Mallet only 112 dmg).
  Infinite ammo (online) removes the gun tax but not burst regen or melee breakage.
- **Mode-specific.** Mega is the highest-lethality mode (×2 damage, half TTK, ×0.8 KB) with one-shot headshots;
  Giant is TTK-neutral (both HP and damage ×2) but adds reach and ring-out; Explosive's 300 HP lengthens launcher
  fights. Classic/Melee/Guns/Ninja/Explosive/Giant/Lowg/Construction have **no end condition** offline. Chaos compounds the
  outlier multipliers above (Giant event + rage + headshot).
- **Data inconsistencies found.** (1) Arcade bots inherit MatchSim slot classes (`_dress` does not reset class
  stats) → solo vs co-op bosses differ in speed/KB/damage. (2) The 9 DLC construction tools are in
  `modes.construction.allowWeapons` but not in `drops.allow.construction`, which is the list Godot's crate
  picker actually reads: only hammer/wirewhip/blower can drop in a normal Construction match; Arcade surfaces
  five more via its own `weapon_drop`. (3) Shared `mammoth.headMul 15.33` = 230 (one-shot) vs overlay 8 = 120
  (documented deliberate fix, but web/online still one-shot). (4) `melee` mode includes the 0-damage glove (a
  `gun`-type) and the throwable trident. (5) Class `head`/`size`/`wide` look like combat stats but are visual
  only; head hit-spheres never scale. (6) `change_request.giant_scale` is read at stage start, not per phase,
  and its `phases` param is unused (PHASES is hard-coded); `deadline_shrink.every` is only the first hold, later
  cycles use the fixed 3 s/5 s ModeRules holds. (7) `lowg` HP 200 duplicates the default, `BOT_GUNS` lists `snow`
  twice; offline has no K.O.-limit/HP/crate/gravity/KB/infinite-ammo UI, unlike the web rules sheet.
### Prioritised proposed changes (no code changed here)
| P | Change | File / key | Suggested value / action | Why |
| --- | --- | --- | --- | --- |
| P0 | Give Arcade enemies a fixed class | `godot/dlc/construction/arcade_manager.gd` `_dress()` | `b.set_class("wobbler", sim.combat.classes["wobbler"])` (or add a `class` field per stage bot and use it) | Removes the solo/co-op speed/KB/damage drift; today co-op bosses are Kid class |
| P0 | Decide Supervisor's "pressed" trigger | `stages.json` `supervisor.events[backup_call]` + `stage_events.gd` `_backup` | If "pressed" is the intent: add `near_m` (e.g. 14 m to nearest seat) and/or `hit_recent` (2 s) to the check; keep `summon_count 1` | Current trigger is only HP ≤50% at any distance; code cannot express pressure |
| P1 | Make the summon readable and less swingy | same event | Add a 1.0 s wind-up + HUD/toast marker at the spawn spot; at Normal maybe summon HP ×0.8 (144) | One 180 HP body at 50% roughly doubles incoming pressure with no direction cue |
| P1 | Surface the DLC tools in normal Construction | `shared/drops.json` `allow.construction` (export source) or a Godot-only crate allow override | Add the 9 DLC keys (at least the five boss-stage tools); otherwise mark the mode as 3-tool only | Currently the tools exist but cannot drop outside Arcade's scripted crates |
| P1 | Give offline modes an end | Setup Wizard Players page / `Settings limit` presets | Add the web's 0/5/10/20 K.O. pills, default Classic to 20 | Every Godot offline Classic match currently runs until quit |
| P1 | Restore a melee niche | `shared/weapons.json` bat/mallet or `weapon_tuning.json` | Option A: melee `dmg` +15%; Option B: ranged `force`/`maxForce` as-is and give melee more reach; owner call | Melee's 2.1–6.5 s TTK at 1.4–3.3 m vs guns' 0.8–3.7 s at 20–140 m |
| P2 | Mammoth shared one-shot | `shared/weapons.json` `mammoth.headMul` (exported from web) | 15.33 → 8 (the overlay value) in the web source, then re-export | A body-shot weapon with a one-shot head at 200/150 HP is the biggest single outlier online |
| P2 | Air Blower tank ceiling | `weapon_tuning.json` `blower.dmg` or `.ammo` | 2.5 → 2.6 or ammo 100 → 110 | Tuned tank tops out at ≈149 damage, unable to finish a full 150/200 HP target |
| P2 | Net Gun pin in 1v1 | `weapon_tuning.json` `net.trap` | 2.5 → 2.0 s, or restore a second shot at reduced trap | 2.5 s free hit window from one ammo is a huge 1v1 swing; shared 4.5 s is worse |
| P2 | Heavy launcher sustain trough | `weapon_tuning.json` `rocket/glauncher/meteor/cluster` `burst.regen` | Rocket 5→3.5 s, Grenade 4→3 s, Meteor 6→4.5 s | Sustained DPS 14–19 vs 56–78 burst is a very sharp cliff |
| P3 | Class visual stats | `shared/classes.json` or `FighterState.spheres` | Either scale hit spheres by `head`/`size`, or relabel as cosmetic | Scamp's head 1.4 does not make it easier to headshot; Bulwark's 0.85 does nothing |
| P3 | Arcade power-up pickups | `godot/logic/pickups.gd` `bot_wants` / arcade owner | Exclude Arcade enemies from power-ups, or halve rage/shield effect on them | Boss + phase ×1.44 + rage ×1.5 = ×2.16 damage; shield doubles its EHP |
### Questions for the owner
1. Is **Classic offline** meant to end? If yes, which default limit (web buttons are 0/5/10/20)?
2. Should the Supervisor's backup be **once at 50% HP** or a genuine "pressed" response (recent damage,
   proximity, or being stun-locked)? Should it ever repeat (cap 2)? Is one 180 HP tradie the intended weight?
3. Is the 9-tool DLC crate gap intentional (Construction mode is a 3-tool mode; Arcade is the only place to
   see the rest), or should the tools drop in normal Construction too?
4. Should the **shared/web Mammoth headshot one-shot** stay? That is a web-source change, not a Godot one.
5. Is the current melee-vs-ranged gap acceptable (melee = displacement role), and should the melee mode's
   glove stay as the only "melee" defence?
6. Should **Arcade enemies be allowed power-ups** (rage/shield/speed) and health packs at 5/8/10%?
7. Which difficulty/HP is the tuning baseline: 200 HP Godot offline, 150 HP web lobbies or Nightmare Arcade?
   Should Arcade co-op seats' **class inheritance** be fixed to Wobbler, or per-stage classes in `stages.json`?
8. When the **aim-mode/assist** work lands, should these gun DPS/assist notes be re-derived (this snapshot has
   `PLAYER_ASSIST` 0.8 offline vs a perfect 1.0 lock online)?
## How the numbers were derived
- **Source of truth**: `shared/*.json` (exported from the web game by `tools/export-content.js`, copied to
  `godot/data/` by `tools/sync-shared.js`; verified byte-identical) and hand-written `shared/damage.json`.
  Godot-only data: `godot/data/extra/{classes,modes,weapon_tuning}.json` and `extra/construction/{weapons,stages}.json`.
- **Two balance regimes**: web/online uses shared numbers and the `classic` rule (body 1.0, no melee headshots).
  Godot offline merges `weapon_tuning.json` and uses `zones` (melee head 1.5, arms 0.85, legs 0.75) only while
  `Combat.tuning_active()`; damage is attacker-computed, so a Godot player online still uses the web numbers.
- **Formulas**: DPS = per-trigger damage ÷ effective cycle (cooldown ÷ class `rate`); TTK@150 = simulated trigger
  pulls with magazine reloads and launcher burst regen; class EHP = `hp_setting × class hp`; boss HP =
  `200 × min(table hp, max(table hp × hp_mul, hp_floor))`; boss damage scale = `DIFFS.dmg × table dmg_scale ×
  arcade dmg_mul × inherited class dmg`; boss walk speed = `DIFFS.speed × table speed × arcade speed_mul ×
  inherited class speed_mul`; phases ×1.2 damage and ×1.1 speed each.
- **Hand checks**: AK 8/0.1 = 80 DPS; Shotgun 8×10/0.8 = 100 DPS; Katana 28/0.42 = 66.7 DPS; Bruiser EHP 260; Engineer normal HP 392; Supervisor summon 180. All match the generator.
- **Regenerate**: `node tools/balance-tables.js` (or `weapons`, `classes`, `drops`, `modes`, `bosses`). It is
  read-only, has no dependencies, is not in `package.json`, and prints the computed tables. Timings that the JSON
  does not carry (0.4 s burn tick, 0.28 s nock, 1.5 s spawn immunity, 0.5 s kit top-up, 6 s revive) are from
  `godot/logic/*.gd`. Inferred cycles are tagged **[i]** above; everything else is directly from a file.
- **Caveats**: all TTK/DPS values assume no misses, no body-part penalties, ideal range and full volleys; real fights
  add spread, falloff, movement, reload interruptions and class `rate`/`reload`/`ammo`. The Arcade probe numbers are a
  scripted yardstick, not human win rates; `godot/tests/arcade_balance.gd` regenerates the curve (≈25 min, 8 seeds).
