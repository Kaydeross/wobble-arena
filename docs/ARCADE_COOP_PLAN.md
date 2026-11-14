# Arcade co-op (two players): feasibility and plan

_Status: design only. Read from the working tree on `claude/match-start-quickplay`; it carries uncommitted quick-play
work in `world.gd`, `main.gd` and `match_sim.gd`, so their line numbers will move — grep the function name. The net
(`godot/net/*`), Arcade (`godot/dlc/construction/*`) and logic files are unmodified._

## 1. The ask

Two players co-op the Construction DLC Arcade (the six-stage boss rush that is offline single-player today, see
`docs/CONSTRUCTION_DLC.md` "Unit D"); if one drops, a bot plays their fighter until they rejoin. The online layer already
has drop → bot → rejoin. The Arcade has no online story: its run state (stage, lives, site seed, crew, events) lives in
`ArcadeManager` on one machine, and guests get one `start` and a static map.

## 2. What already exists

| Capability | Where (unmodified files) | State |
|---|---|---|
| Rooms, seats, rules, app-only modes | `godot/net/host_session.gd` (`begin_host` 77-102, `start_match` 603-620, `_begin_match` 624-636, `net_mode`/`app_only` 129-146), `net_match.gd:21` | works (tdm, deathmatch, sudden, chaos, pillars, lowg, duel, t2-t4) |
| Host sim + guest ghosts, 30 Hz `S`, hits, K.O.s, crates | `host_match.gd`, `net_match.gd` (`setup` 128-160, `report` 339-360, `step_ghosts` 363-391, `handle` 399-466) | works |
| Drop → bot, rejoin → bot makes room | `_hello` 403-444 / `_drop` 447-468; `bot_to_human` 119-131 / `human_to_bot` 134-155 | works |
| Mid-match `start` (join running, rematch) | `_hello` 433, `guest_session.gd:_on_room` 292-300, `world.gd:_on_net_start` → `load_map` | works |
| Host migration | `_promote` 228-239, `take_over` 252-292 / `_resume_start` 325-355, `capture_resume` 222-235 | works for a match, no run state |
| Arcade run | `arcade_manager.gd`, `stage_events.gd`, `arcade_boss_hud.gd`, `arcade_panels.gd` | offline, one `sim.player` |

### 2.1 Drop → bot → rejoin, as it runs today

The relay reports a closed socket (`host_session.gd:234-236`) or the host drops the guest (`rematch_start` 711-716), so
`_drop(cid)` 447-468 removes the cid and roster row, calls `hm.human_to_bot(id, opt_bots)` and broadcasts
`{"t":"slot",…}` plus "*X* left, a bot took their place" (462). `human_to_bot` 134-155 deletes the ghost and restores the
seat's **original bot** — class, look, damage and speed from `orig[k]`, recorded in `setup` 46-91 before the human became
a ghost — with `brains[k]` driving it; with `opt_bots` off the seat becomes `empty`. A rejoin's `hello` (`_hello`
403-444) is checked (proto, `gd`; a web guest is refused on a **running** app-only match, 410-414) and gets the old slot
after a migration (`_resume_seat` 314-321) or the first free id below `_cap()` 369-371, skipping seats marked `human`
(415-422); a full room gets `full`. In a running match it then receives `welcome`, a **full `start`** (433: slots, map,
limit, rules with `dseed`), `crates` (434) and a `slot` broadcast (435), and `bot_to_human` → `_make_ghost` 100-117 makes
a **fresh fighter** (class from `info`, full health, empty inventory, spatula, reset K.O./lives). `World._on_net_start` →
`load_map` rebuilds the world, `NetMatch.setup` 128-160 ghosts the other slots, and the rejoiner starts on its own spawn
while the host's ghost is dragged there by snapshots.

### 2.2 Limits of that machinery

- Only **while `started` and `HostMatch != null`** (`_hello` 430, `_drop` 457); a drop after `pend` rejoins the finished
  match until the rematch. The takeover bot is the seat's original bot (`human_to_bot` 147), not the player's fighter;
  rejoin is a **fresh fighter at spawn** (no position, health, inventory, K.O.s or lives — `rs` is migration-only), and
  `opt_bots` must be on.
- Races: `_closing` delays the relay `close` 0.4 s (366-368); `_hello` ignores a known cid (404); `_cap()` shrinks to the
  running table; during a rematch the old `HostMatch` is disposed but `_match` still points at it until `match_ready`, so
  a seat edit then touches a disposed match.
- A **web** guest can never rejoin an app-only match (410-414) and gets `hostgone` when the host leaves
  (`guest_session.gd:196-197`); only Godot guests get `promoted`/`rehost` (198-239). **Migration** carries
  `capture_resume` (positions, health, K.O.s, lives) and the arena seed/clock, not a mode controller: stage, lives, run
  seed, crew and paid coins are lost.

## 3. Why the Arcade is offline today

`HostSession.net_mode` 129-132 turns `construction` into `classic`; `online_modes` 135-139 lists `ModeRules.PLAYABLE`
(`mode_rules.gd:38-40`), which has no `construction`, so the Host sheet cannot offer it (`main.gd:step_host_mode`), and
`app_only` 145-146 is `NetMatch.GODOT_MODES.has(m)` with `construction` absent (`net_match.gd:21`), so `_refresh_mode`
165-167 / `rule_snap` 581-595 never send `rules.gmode` and a guest falls back through `play_mode` 80-85 to Classic
(`construction` is also `ModeRules.OFFLINE_ONLY`, `mode_rules.gd:41`). The map cannot even be named: `begin_host` 94 and
`clean_start` 339 validate against `res://data/maps.json`, which lacks `sitegen` (runtime-registered by
`Content.add_extra_maps`, `godot/autoload/content.gd:34-38`) — hosting it today silently becomes `arena`. `main.play_arcade`
stays offline (`ArcadeManager.launch` 120-130).

**To host `construction` as an app-only co-op room** (small; the gate for everything else): add `construction` to
`GODOT_MODES` and to `online_modes`/`net_mode`/`play_mode`; refuse web guests outright (the downgrade-to-Classic path in
`_refresh_mode` is wrong for Arcade — Arcade *is* the mode); teach `begin_host`, `clean_start`, `map_label` and
`_host_map` about `sitegen`; add an "Invite a friend" entry in the Construction hub that creates the room with
`mode: "construction"`, `map: "sitegen"`, two seats, bots on, and the Host sheet's HP/mode/limit ignored (the stage table
owns them).

## 4. Proposed design

### 4.1 The model: player seats first, then the crew

Keep `start.slots` as the positional table `MatchSim.setup`/`HostMatch.setup` already use (slot `k` ↔ `sim.fighters[k]`,
`host_match.gd:57-79`); seats first, the stage's crew after:

```
start.slots = [ host(seat), guest/bot(seat), crew1, crew2, … ]     ← ≤ 8 slots
start.arc   = { run, st, of, diff, seed, seats:[0,1], crew:[2], boss, big, state, lv }
```

Online `MatchSim.setup` already gets `bot_count = slots.size() - 1` (`HostSession.sim_bots` 660-661), so the host creates
a placeholder per crew slot too; `HostMatch.setup` keeps crew as `ai` bots and turns seats into ghosts — **`S`/`h`/`ko`/
`crate`/`take` then replicate the crew with no new message**. `arc.crew` marks the crew so `_hello`/`bot_to_human` never
hand a boss to a joining player. Cap: seats + crew ≤ 8 (`NetSnapshot.NET_MAX`); stage 1 has 4 crew, so up to 4 players,
and more needs a separate crew id space in `S`/`h` (touches shared validation — not recommended).

### 4.2 Three additive protocol pieces (Godot-only, like `gm`: `docs/PROTOCOL.md` 6.3)

| Where | Field | Meaning |
|---|---|---|
| `start.arc` | full | The run as the host sees it: stage/count, difficulty, the stage's `seed`, `seats`/`crew`, boss slot, `state`, `lv`, `run` |
| `am` (host → all) | `st, of, s, lv, hf, sh, dn[], ev` | 5 Hz + on change: stage, state, shared lives, boss health fraction, shrink size (metres), downed crew slots, one-shot event payloads |
| `arc` (guest → host) | `a: "start"\|"next"\|"retry"` | Optional guest button; guarded in `_host_recv` like `rv` (384) and checked against the same state machine |

`am` is display state only: it never advances a stage, pays coins or damages anyone. Effects that change collision are
**not** cosmetic: `am.sh` sets the guest's `rules.shrink["size"]`/box via a small `ModeRules.apply_shrink_size`, and
guests skip `update_shrink` while `rules.remote` (already true for app-only modes, `net_match.gd:_setup_mode` 163-171).

### 4.3 Stage transitions: re-send `start` per stage (recommended)

Chosen over a dedicated `stage` op and over "host state + fully presentation-only guest" because it reuses the two
mechanisms that already work: a mid-match `start` rebuilds the guest world (`_on_net_start` → `load_map`), and
`match_ready` 639-649 already sends a fresh `start` after every host `load_map`.

```
HOST                                                  GUEST
card Next → next_stage() 374-378                       (arena frozen behind the card)
  stage += 1; seed = stage_seed() 157-158
  _reload() 385-386 → world.load_map("sitegen")
    begin_stage: SiteMap.set_seed(seed); start_msg.slots = seats+crew; start_msg.arc = {st,seed,…}
    sim.setup(bot_count = slots-1); setup_sim: slice(seats)
    net_match.setup → match_ready  ──── start(slots, arc) ───►  _on_net_start → load_map
                                                                begin_stage: SiteMap.set_seed(arc.seed)
                                                                NetMatch.setup: ghosts for seats+crew
                                                                stage_ready: HUD strip + intro card
  am {s:"intro"} ──────────────────────────────────────────►  card ("Waiting for the host")
  host presses Start → begin_fight 227-232  ── am ─────────►  card closes, fight starts
```

This one change serves **stage advance, retry, mid-run rejoin** and (if wanted) migration resume; `clean_start` 326-342
stays the validation choke point; the guest arena is rebuilt, so no stale map, crates, hazards or ghosts survive a stage.
Cost: a full `load_map` per stage on the guest (a hitch hidden behind the card) and a short window out of the fight.

**Determinism.** `SiteMap.set_seed` 53-55 + `MapBuilder.build("sitegen")` → `SiteMap.generate(seed)` is pure and cached
per seed (`site_map.gd:68`), and crew positions are not map data (the host moves them with `S`), so `start.arc.seed`
suffices for both clients. `SiteMap.current_seed` is a **process-global**: two worlds in one process (offline tests, or
host + guest in one process) would fight over it — set it per world in `begin_stage`.

**Boss bar, crates, downed, coins.** `ArcadeBossHud` reads `boss_frac()` 491-493; on a guest the boss is a ghost whose
`combat.max_hp` is not the host's (`_dress` sets `cls_hp`/`big_t` on the host only), so drive the bar from `am.hf` and
`arc.big` for the Client's 1.5× visual. Crates already replicate (host `cid` from `stage_events.gd:274-275`,
`HostMatch.on_event` 211-216 announces, `take` removes, a joining player gets `crates` 434); the `load_test` hazard
crates do not (`stage_events.gd:147-200` host-only nodes), so `am.ev` carries `{x, z, spot, warn}` for the guest's
visuals and the damage stays host-side — widen `_land` 191 (it skips `is_ghost`) and `Combat.hit` on a ghost emits the
`h` for its owner (`combat.gd:200-209`). Solo, death = stage failed (`_failed` 316-321); proposed for two: a dead player
is *down* (pinned) while the teammate plays, revived after 6 s while a teammate is up, and the attempt fails only when
**every seat is down at once**, costing one shared life — `seats == 1` keeps today's rule verbatim. `lives` is shared and
host-authoritative (`am.lv`; the HUD strip already says "Lives n", `arcade_boss_hud.gd:95`). **Coins are per player and
local**: each client applies the same stage result to its own `Save.dlc`/`Save.coins`, so the first-clear bonus is per
save; each guest tracks its own K.O.s/time for its card.

**Host drops mid-run.** M1-M3 return `{}` from `capture_resume` for an Arcade world, so the promoted guest lands in the
lobby and both see "The host left: the Arcade run is over." Carrying a run across a migration (stage, lives, seed, crew,
hazard/shrink timing in `rs.arc`, plus a real `ArcadeManager` on the promoted guest) is M5 and the one genuinely hard part.

### 4.4 Rules for two players

- Enemies target the **nearest player**, not `sim.player`: `BotBrain.pick_target` 110-117 iterates `[sim.player]` when
  `ffa` is false (Arcade sets `ffa = false`, `arcade_manager.gd:191`) — replace with a "player seats" list, including a
  bot-played seat, which should still fight the crew. `bots_can_hit` (`combat.gd:136-138`) gates enemy swings on
  `is_player`, so the co-op ghost is untouchable today; widen it for a PvE match (`e.is_player or e.net_human`).
- **Friendly bots** (a seat that starts or becomes a bot) must target the crew — today a bot with `ffa = false` only
  targets `sim.player`, so a teammate bot would attack the host: new PvE AI (target the crew, follow the player when
  idle). Unglamorous, but it is what makes "bots on" playable and M3's takeover useful.
- Cards go to **both**: the host shows its own, the guest builds the same panel from `am` with a "Waiting for the host"
  button state.

## 5. Single-player assumptions (and what they become)

`godot/dlc/construction/arcade_manager.gd`:

| Line | Assumption | For two players |
|---|---|---|
| 178 | `w.bot_count = crew.size()` | `seats - 1 + crew.size()` |
| 187-206 | `setup_sim` dresses `s.fighters.slice(1)` | `slice(seats)`; `_deaths0`, `player_dmg` per seat |
| 203-204, 246, 269 | one `sim.player`; `p.dead` fails the stage | loop the seats; fail only when all are down |
| 272-275, 293, 308 | `_down`/`_revive`/`_cleared` use the one player | nearest live player (distance picks, final-hit credit) |
| 316-318, 324-341 | `_failed` pins `sim.player.death_t`; `_pay` reads `sim.player.ko` | pin each downed seat; sum the seats' K.O.s |
| 458-483 | `spawn_minion` spawns away from `sim.player` | away from the nearest player |
| 44, 138 | one `player_class`, one `lives` | per-seat class (from the slot); shared run lives |

`godot/dlc/construction/stage_events.gd`: **140-141** the first `load_test` crate lands near `sim.player` → near the
nearest player (or one each); **188-200** `_land` skips `is_ghost` → include the co-op ghost so the host's hit reaches its
owner; **313** `change_request` hands the tool to `sim.player` → to every live player seat. `world.gd:arcade.setup_sim` /
`stage_ready` need a guest path; `match_sim._ring_out` respawns `is_player` fighters, so a downed co-op player must be
pinned by the manager exactly like the solo player is.

## 6. Bot takeover and rejoin inside a run

The seat model fits; the **fighter handover** does not. **Drop** (host): keep the seat's `FighterState` (class, health,
inventory, position) and swap its `GhostControl` for a `BotBrain` — a new `ghost_to_bot(k)` beside `human_to_bot`
134-155, which stays as it is for the other modes. The bot uses the co-op player AI (§4.4) and the seat still counts for
"all seats down"; `am` marks it bot-played. **Rejoin** (host): the existing `bot_to_human` path works; with `start.arc` in
the rejoin `start` (433) the rebuilt world lands on the **current stage and site seed**, so reconnect is the same code as
a stage transition. The fighter starts fresh and the host's ghost snaps there; carrying the bot's exact health/kit is a
stretch (`start.arc.seat`), not assumed. The room is found by its code (or room-list entry, `srv_info` 513-516); `_hello`
takes the first non-human seat under `seats` (415-422), unambiguous with two seats — with more, two reconnecting players
can swap (a plain-rejoin limitation that only migration's `pslot` fixes).

## 7. Milestones

| # | Size | Work | Test | Main risk |
|---|---|---|---|---|
| M1 | L | App-only `construction` room + `sitegen` allowlists (`host_session.gd`, `net_match.gd`, `guest_session.gd`, `main.gd`, `construction_hub.gd`); `start.arc`; per-stage `start`; guest presentation manager (seed-only `begin_stage`, HUD in `stage_ready`, no-op `step`); `am`; shrink sync | `net_modes_host.gd` + `net_modes_peer.gd` via `tools/test-net-host.js`, new `arcade` scenario: `start.arc.st` 1→2, peer `SiteMap.current_seed` == host's stage seed, peer ghosts == slots-1, peer HUD names the stage, peer shrink within 0.5 m, a web guest refused; in `arcade_test.gd`: `begin_stage` seeds the site, `setup_sim` slices after seats, `start.arc` carries that seed | guest world rebuild is a hitch; `_cap`/seat scan must not hand out crew slots; `HostMatch` disposal races a seat edit |
| M2 | L | Two seats: shared lives, down/revive, summed K.O.s, per-player coins, cards on both; enemy targeting nearest player; friendly-bot AI; `change_request`/`load_test` for both | `arcade_test.gd` two-seat harness (a second `PlayerControl` fighter as seat 1): enemy picks the nearest seat, `bots_can_hit` lets crew hurt seat 1, one seat down does not fail the stage, both down does, one shared life lost, `run_kos` is the sum, the clear card exists | PvE friendly-bot AI touches shared `BotBrain`; two players make the table much easier (open question) |
| M3 | M | `ghost_to_bot` (keep the fighter) + co-op bot AI; rejoin = `start.arc` at the current stage; `am` marks bot-played seats | `net_modes_host.gd`/`peer` `arcade-drop`: peer leaves → host prints the seat as a bot with the player's class/kit and not `empty`; peer rejoins → `START` with `arc.st` = current stage and same seed, `slots[1].kind == "human"`, peer `world.slot == 1`; `net_host_test.gd` guards unchanged | rejoin starts at the guest's spawn, not the bot's state; seat edit during `load_map` |
| M4 | S/M | Guest parity: hazard `am.ev` visuals, `weapon_drop`/takes, boss phases (swaps on the ghost look), toasts, "Waiting for the host" cards, guest `arc` requests | `net_modes_peer` prints peer `ArcadeBossHud.boss_visible()`, phase count, hp drop after a `load_test`, `arc` accepted/ignored in the right states; `arcade_test.gd` single-player checks stay green | payloads drift from the host state (double damage, double toast) |
| M5 | XL | Migration inside a run: `rs.arc` in `capture_resume`, promoted guest builds a real manager, `take_over`/`_resume_start` carry the run, re-payment rules | `net_modes_host.gd`/`peer` `arcade-migrate`: host leaves mid-stage → peer `PROMOTED`, `start` with `rs.arc` rebuilds the same stage/seed/lives, peer plays on | genuinely hard: hazard/shrink timing, crew AI state, coins already paid, two saves. **Recommend cutting** |

Order M1 → M2 → M3 → M4. M1 alone (one online player) is a useful proof and carries most of the protocol risk.

## 8. Not decided / open questions

1. **Lives:** shared run lives (recommended, one HUD number) or per-player lives? **Downed player:** auto-revive after
   6 s while a teammate is up (recommended), out until the next stage, or a teammate revive? Does a revive cost a life?
2. **Records and coins:** do co-op clears write `arcade_best`, `arcade_clears` and the first-clear bonus on **each**
   player's save (duplicated economy, carried players get the Foreman hat) or only solo clears? Recommended: coins and
   records per save, but say so in the UI.
3. **Players and balance:** two only, or up to 4 (stage 1's 4 crew fill the 8-slot budget exactly)? The table is tuned
   for one player and two roughly halve the pressure — keep as-is, or scale crew health/damage by seat count (careful:
   applying it blindly would also change offline solo)?
4. **Host sheet rules:** do HP / mode / K.O. limit apply to an Arcade room? Recommended: no — the stage table owns them.
5. **Lobby and start:** may a room start with 1 human + 1 teammate bot so a friend can take the seat later? Recommended
   yes; it reuses the existing seat/bot model.
6. **Host migration:** is M5 wanted, or is "the host left, the run is over" acceptable for v1?
7. **Reconnect identity and guest buttons:** room found by code (fine for two seats?); may a guest press
   Start/Next/Retry, or host-only for v1?

## 9. Honest conclusion

Drop → bot → rejoin and the "`start` rebuilds the guest world" machinery are real and carry most of the weight; the
Arcade is the part never written with more than one human in the room. The smallest honest version — M1-M4, app-only
room, per-stage `start`, host-authoritative crew + guest presentation, the seat model reused for takeover and rejoin — is
an **L/XL effort, with M3's fighter handover and M2's PvE bot AI as the sharp edges**, and it can ship without touching
the shared web protocol (`S`/`h`/`ko` stay byte-identical; the new fields are Godot-only like `gm`). Full host migration
inside a run is the one case that is not clean: it needs run state, hazard timing and two saves to agree. Ship v1 with
the run ending when the host leaves and decide M5 separately.

## 10. Decisions (owner, 2026-11-14)

1. **Lives:** shared run lives, one HUD number.
2. **Downed player:** auto-revive after 6 s while a teammate is still up; a revive does not cost an extra life.
3. **Records and coins:** co-op clears and first-clear coins are written on each player's save; the UI says so.
4. **Seats:** two players per room.
5. **Lobby:** a room may start with one human plus a teammate bot, so a friend can take the seat later.
6. **Host migration:** not needed for v1. If the host leaves, the run ends and the players return to the hub.

These settle section 8's questions; M1-M4 are in scope, M5 is out.

## 11. Milestone status

- **M1 (net layer): protocol + host + stage sync + entry point done; guest presentation pending (second agent).**
  `construction` is in `NetMatch.GODOT_MODES` and an Arcade room (`arcade` host opt, hub "Play co-op" →
  `main.play_arcade_coop`) plays it app-only on the generated site, two seats + the stage's crew, with a web guest
  refused. `start.arc` (`godot/dlc/construction/arcade_coop.gd`: `{run, st, of, diff, seed, seats, crew, boss, big,
  state, lv}`) travels with every stage's `start` (the transition mechanism) and with a mid-run join/rejoin; the host
  rebuilds slots as seats + the new stage's crew, adopts the crew fighters `MatchSim.setup` made, and sends `am`
  (~5 Hz + on change: stage, state, lives, boss fraction, shrink, downed seats, stage summary, victory). The guest
  rebuilds the site from `arc.seed`, maps the seats onto the net ghosts (`NetMatch.slot_fighter(arc.seats[k])`), shows a
  stage number + "Waiting for the host" card and stores `am`; its HUD/cards/downed/coins presentation is the remaining
  M1 work. Test: `npm run test:godot-host` scenario D ("arcade") — host room with the teammate bot, a Godot guest joins
  mid-run, stage 1 → 2 (`start.arc.st` 0 → 1, matching fresh seeds), the guest sees the host seat / every crew slot / the
  boss as ghosts and receives `am`; the guest leaving turns seat 1 back into the teammate bot while the host keeps
  running; host and guest exit clean. Not done: guest HUD/cards, the rejoin leg (the seat flag refresh hook and the
  current-stage `start` exist; the fighter handover is M3), and web guests are simply refused.
- **M2 (Arcade seats): done, offline-verified.** `ArcadeManager` is seat-aware: `seat_count` (1 or 2) and `seat_names`
  set before the first `load_map`; the seats are `sim.fighters[0..seat_count-1]` in room-slot order (crew after) and are
  read with `seat(k)`, `seat_name/label(k)`, `seat_alive`, `seat_is_down`, `seat_revive_left`, `living_seats`,
  `downed_seats`, `all_seats_down`, `seat_control(k)`. Rules: per-seat damage scale, a downed seat auto-revives after
  `REVIVE_TIME` (6 s) at full class health on a safe spot with no life lost while a teammate is up, all seats down loses
  exactly one shared life and retries the same stage, K.O.s are summed, `_pay()`/`_win()` return a `seats` array with
  each seat's share (one local save is written), the HUD shows one line per seat with the down countdown, and the cards
  name the seats. Crew/boss targeting is nearest living seat (`BotBrain.pick_target` via the `pve_seats` sim meta; a
  `bot:true` seat is a full target and fights the crew); the 1-seat path is unchanged (`npm run test:godot-bots` parity
  untouched). `combat.bots_can_hit` accepts a co-op ghost seat (`net_human`), and `Combat.hit`'s ghost branch already
  relays a host crew bot's hit to that seat's owner. Offline two-seat harness in `godot/tests/arcade_test.gd`
  (`npm run test:godot-arcade`); single-player tests and their numbers are unchanged. Remaining for the net layer:
  slot→seat mapping (`seat_count`/`seat_names`/`seat_bot` before a stage), mirror `seat_downed`/`seat_revived` as the
  downed-state messages (`am.dn` + revive countdown, ideally from `seat_is_down`/`seat_revive_left`), and deliver
  `last["seats"]`/`victory["seats"]` to each client so every save is paid on its own client (never two saves here).
