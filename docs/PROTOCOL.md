# Wobble Arena network protocol

_Describes build b76 (`NET_BUILD = 'b76.0'`). Source of truth: `server.js` (layer 1) and `public/index.html` lines ~8158–8800 (layers 2–3). Written so that a second client (the Godot iOS app) can join the same rooms as the web client._

## 0. How it fits together

There are **three layers**:

| Layer | Who speaks it | Format |
|---|---|---|
| **1. Server ops** | client ⇄ `server.js` over WebSocket `/ws` | JSON text frames, `{"op": "...", ...}` |
| **2. Room messages** | host ⇄ guests, carried inside layer 1 as the `m` field | JSON objects, `{"t": "...", ...}` |
| **3. Account REST API** | client ⇄ `server.js` over HTTPS | JSON, `Authorization: Bearer <token>` |

**The server is a post office, not a referee.** It only creates rooms, relays messages and picks a new host. The game itself is simulated by the players:

- **The host** (the room creator, slot 0) runs every bot and relays guests' messages to the other guests.
- **Each human** simulates and owns their own fighter, and broadcasts its state 30 times a second.
- **Hits** (`h`) are decided by the attacker's side and applied by the victim's side.

Everything below is a faithful description of what exists today, including the weak spots (§7).

---

## 1. Connection and server ops (layer 1)

Connect a WebSocket to `wss://<server>/ws`. Text frames only (binary is ignored). Limits (`server.js` `LIMITS`):

| Limit | Value |
|---|---|
| Max message | 32 KiB |
| Rate | 400 msg/s per connection (bursts up to 1.5×; over 200 dropped messages → close 1008) |
| Connections | 3000 total, 40 per IP |
| Rooms | 300 |
| Players per room | 8 (`perRoom`) |
| Keep-alive | server pings every 20 s; a silent client is terminated |

Messages are processed in order, but while an `auth` check is running the messages behind it wait.

### 1.1 Client → server

| `op` | Fields | Notes |
|---|---|---|
| `ping` | `ts` | Server replies `pong` with the same `ts`. |
| `auth` | `token` | 64 hex chars from `/api/login`. Replies `authed {user}` or `noauth`. Send right after connecting. |
| `list` | – | Replies `rooms`. |
| `create` | `pub` (bool), `info` | Needs auth unless the server runs with `REQUIRE_LOGIN=0`. Replies `created` or `nocreate`. |
| `update` | `info` | Host only. Refreshes the room-list entry. |
| `join` | `id`, `build` | `id` is case-insensitive. Replies `joined` or `nojoin`. |
| `quick` | `mode`, `build` | Joins the fullest public room of that mode. Replies `joined` or `nomatch`. |
| `tohost` | `m` (object) | Guest → host. Server wraps it as `msg {from: cid, m}`. |
| `to` | `cid`, `m` | Host → one guest. |
| `all` | `m`, `except` (cid, optional) | Host → every guest except one. |
| `close` | `cid` | Host removes a guest. That guest gets `kicked`. |
| `leave` | – | Leave the room. Replies `left`. |

`info` (room-list data, all strings are control-character-stripped and truncated):

| Field | Type | Limit |
|---|---|---|
| `name` | string | 24, default `Room` |
| `host` | string | 12 |
| `mode` | string | 16 (mode id, e.g. `classic`) |
| `modeName` | string | 24 |
| `map` | string | 24 (display name) |
| `max` | int | clamped 2–8 |
| `started` | bool | |
| `build` | string | 16 |

### 1.2 Server → client

| `op` | Fields | Meaning |
|---|---|---|
| `hi` | `online` | Sent on connect. `online` = connected clients. |
| `pong` | `ts` | |
| `authed` / `noauth` | `user` | Result of `auth`. |
| `rooms` | `rooms[]`, `online` | Each: `{id, name, host, mode, modeName, map, n, max, started, build, pub:true}`. Public rooms only, fullest first. |
| `created` | `id`, `pub` | You are the host (cid 0). Public rooms are `r<base36 counter>`; private rooms are a 5-char code from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. |
| `nocreate` | `reason` | `auth`, `inroom`, `busy` |
| `joined` | `cid`, `id`, `pub` | You are a guest. `cid` is the server's connection id inside the room (1, 2, …) and is **not** the game slot. |
| `nojoin` | `reason` | `auth`, `inroom`, `none`, `full`, `build` |
| `nomatch` | `reason?` | No suitable public room, or `auth`/in a room. |
| `msg` | `from?`, `m` | To the host: `from` = guest cid. To a guest: no `from` (it is from the host). |
| `peer` | `cid`, `ev` | Host only. `ev` = `open` (a guest joined) or `close` (a guest left). |
| `promoted` | `id`, `pub` | The old host left; **you** are the new host. |
| `rehost` | `id` | The old host left; another guest is the new host. Re-send your `hello` to the new host. |
| `kicked` | – | The host removed you. |
| `left` | – | Reply to `leave`. |
| `hostgone` | – | Defined in the web client but not sent by the current server. |

### 1.3 Room lifecycle

```
create ─► created                        host (cid 0)
join   ─► joined ─┬─► (host gets peer open) ─► guest sends  tohost {t:'hello'} ─► host replies  to {t:'welcome'}
host leaves ──────┴─► longest-standing guest gets promoted; the others get rehost; the new host gets peer{open} per guest
```

Host migration: the room's `started` flag resets to false, guest cids are re-issued (the new host is cid 0, others keep their cids), and **every guest must send `hello` again**. The match in progress is not carried over. The web client handles this in `netMigrate()`.

---

## 2. Room messages (layer 2): lobby and match flow

All are objects with a `t` field, sent inside `tohost`/`to`/`all` (layer 1). The host also receives guests' `t` messages as `msg {from, m}`.

### 2.1 Handshake

| `t` | Dir | Fields | Meaning |
|---|---|---|---|
| `hello` | guest → host | `build`, `name`, `skin`, `hat`, `color` | First message. `build` must equal the host's `NET_BUILD` or the host answers `badver`. Info fields are validated against the host's tables (see §5). |
| `welcome` | host → guest | `id` (slot, ≥1), `name` (room name), `pub` | `id` is the game slot, the lowest free one. Until `welcome`, a guest ignores everything except `welcome`, `full`, `badver`, `kick`. |
| `full` | host → guest | – | No free slot. |
| `badver` | host → guest | – | Build mismatch. |
| `kick` | host → guest | `msg` | Removed by the host (e.g. did not click Rematch). |
| `info` | anyone → host | – | Peer-mode room browsing only; the host replies with a `info` object. Not used in server mode. |
| `ping` / `pong` | guest ⇄ host | `ts` | Sent every 1.5 s by guests; the host echoes `ts`. Used for the ping display. |

### 2.2 Lobby

| `t` | Dir | Fields | Meaning |
|---|---|---|---|
| `roster` | host → all | `roster[]`, `max`, `bots`, `lim`, `bhv`, `diff`, `modeName`, `map` | Players in the lobby. Each roster entry is `{id, name, skin, hat, color}`. `bots`: fill empty seats with bots. `lim`: KO limit. `bhv`: `brawl` or `dummy`. `diff`: bot difficulty id. |
| `start` | host → all | `slots[]`, `map`, `custom`, `limit`, `rules` | Begins a match (also re-sent on rematch and to a guest who joins mid-match). |
| `slot` | host → all | `slot`, `kind`, `info` | Slot owner changed: a friend replaced a bot (`human`), left (`bot`/`empty`). |
| `crates` | host → joiner | `list[] {cid,key,spot}` | Pickups currently on the map, sent to a mid-match joiner. |
| `rv` | guest → host | – | "Rematch" vote. |
| `rvs` | host → all | `list[]`, `total` | Rematch votes so far (slot ids) and the number of humans. When all humans vote, or after **20 s**, the host restarts and kicks anyone who did not vote. |

`slots[]` entries: `{kind: 'human'|'bot'|'empty', id, name, skin, hat, color}`. Index = slot. Slot 0 is always the host.

`rules` (`ruleSnap`): `{mode, hp, crate, wstate, grav, kb, inf, pp?, pt?}`

| Field | Values |
|---|---|
| `mode` | mode id (see §5) |
| `hp` | one of 100, 150, 200, 300, 500 |
| `crate` | crate-rate key |
| `wstate` | weapon-enabled object |
| `grav` | 0.5, 1, 1.5 |
| `kb`, `inf` | knock-back / infinite-ammo settings |
| `pp` | Pillars mode: permutation of spawn indices, one per slot |
| `pt` | Pillars mode: seconds left on the clock for a joiner |

`custom` (only when `map` = `custom`): `{size, obs, plat, walls, pads, seed, theme, ice}`.

### 2.3 Match setup rules (what a client must do on `start`)

1. Load `map` (unknown ids fall back to `arena`). Apply `custom`.
2. For each slot ≠ my own id, create a "ghost" fighter (a remote-controlled fighter) for `human` and `empty`, and a ghost for `bot` too (guests don't simulate bots).
3. Only the host simulates bots. Bots are owned by the host and report their state like humans.
4. Spawn positions: map spawn list; in Pillars mode, `spawns[pp[slot]]`.

---

## 3. Room messages: in-match

### 3.1 State and events

| `t` | Dir | Rate | Fields |
|---|---|---|---|
| `S` | owner → host → all | 30 Hz | `l[]`: one entry per fighter this client owns (own fighter; the host also sends every bot). A guest's `S` is relayed to other guests unchanged. |
| `s` | (internal) | – | One entry of `S`, handled as if sent alone. |
| `sw` | owner → all | on event | Melee swing: `id`, `yaw`, `w` (weapon key). |
| `f` | owner → all | on event | Fired a ranged weapon: `id`, `w`, `dr` (bow draw 0..1). |
| `k` | owner → all | on event | Kick: `id`, `yaw`. |
| `h` | attacker side → victim side | on event | Hit: `to` (slot that applies it, see below), `vs` (victim slot), `from` (attacker slot), `d` (damage), `x`,`y`,`z` (knock direction), `f` (force), `hd` (1 = headshot). |
| `ko` | owner → all | on event | `from` (killer slot or -1), `to` (victim slot). Feeds the scoreboard and kill feed. |
| `pend` | host → all | once | Match over: `w` = winner slot. |
| `chat` | any → all | ≤2/s | `id`, `txt` (≤140 chars). Guests ignore it unless the user setting `chat` is on and the sender is not muted. |
| `crate` | host → all | on spawn | Pickup spawned: `cid`, `key` (weapon key), `spot` (`[x, z]`). |
| `take` | any → all | on event | Pickup taken: `cid`. |

**`S` entry fields** (numbers rounded to 2 decimals):

| Field | Meaning |
|---|---|
| `id` | slot |
| `x`,`y`,`z` | position |
| `vx`,`vy`,`vz` | velocity |
| `yaw` | facing |
| `ax`,`ay`,`az` | arm direction vector |
| `w` | weapon key, or `null` when dead (`spatula` = default melee) |
| `hp` | health, integer |
| `d` | 1 = dead |
| `g` | 1 = grounded |
| `sq` | 1 = squatting |
| `iv` | 1 = invulnerable |
| `lv` | lives left (Lives modes) |
| `el` | 1 = eliminated (Lives modes) |
| `pt` | Pillars clock (only from the host's own fighter) |

**Receiving an `S`:** do not teleport. Predict forward by the age of the snapshot (≤0.2 s) using the velocity, then ease toward it with `k = 1 − exp(−dt·22)`. Snap if the error is over 6 m. The web client does this in `netStep`.

**Routing of `h`:** the attacker's side picks the destination. If the victim is a human, `to` = the victim's slot; if the victim is a bot (owned by the host), `to` = 0. The host applies `h` with `to = 0` itself and forwards other `h` to just that one guest (`hostOut` / `hostRecv`). A guest receiving `h` applies it to its own fighter only.

**Who sends `ko`:** the owner of the dead fighter (the host for bots). The receiver ignores `ko` about itself.

**Pickup flow:** only the host spawns pickups and assigns `cid`. Anyone can take one and broadcasts `take`.

### 3.2 Match end

The host decides the winner (last standing, KO limit reached, timer) and sends `pend {w}`. Everybody then shows results and may vote `rv`.

---

## 4. Account API (layer 3)

Base: same origin as the page (the iOS app must use a configurable `SERVER_URL`). CORS is `*`. JSON bodies, max save 250 KiB.

| Route | Method | Body | Returns |
|---|---|---|---|
| `/api/signup` | POST | `username` (3–16 `A-Za-z0-9_`), `email`, `password` (6–72), `data?` | `{ok, token, user, data, t, recovery}` — `recovery` is shown once, `XXXX-XXXX-XXXX-XXXX` |
| `/api/login` | POST | `id` (username or email), `password` | `{ok, token, user, data, t}` |
| `/api/me` | GET | – | `{ok, user, data, t, hasRecovery}`, renews the token |
| `/api/save` | PUT | `data`, `base?`, `force?` | `{ok, t}`; if another device saved newer: `409 {ok:false, err:'stale', data, t}` |
| `/api/logout` | POST | – | `{ok}` |
| `/api/password` | POST | `old`, `next` | `{ok}` |
| `/api/recovery` | POST | `password` | `{ok, recovery}` (new code; old one stops working) |
| `/api/reset` | POST | `id`, `code`, `password` | `{ok, token, user, data, t, recovery}` |
| `/api/delete` | POST | `password` | `{ok}` — **required by App Store 5.1.1(v)** |
| `/health` | GET | – | `{ok, rooms, players, accounts, saved}` |

Error shape: `{ok:false, err, msg}` with HTTP 400/401/409/413/429/500. Tokens last 365 days and are renewed by `/api/me`. Failed logins are rate limited (8 per account / 40 per IP per 10 min).

The `data` blob is the whole client save (settings, coins, owned cosmetics, stats). Its schema belongs to the web client today; see §7 for why the server must own the economy before iOS ships.

---

## 5. Shared content ids a second client must know

The room messages refer to content by string/number ids. Both clients must agree on them. Today they live only in `public/index.html`:

| Table | Used in | Validation |
|---|---|---|
| Map ids (`MAPS`, about 31) | `start.map` | Unknown → `arena` |
| Mode ids (`MODES`, about 12) | `rules.mode`, `info.mode` | via `netMode()` |
| Weapon keys (`WEAPONS`, about 29) | `S.w`, `sw.w`, `f.w`, `crate.key` | Unknown weapon ignored |
| Skins (`SKINS`), hats (`HATS`), colours (`SWATCH`) | `hello`, `roster`, `slots` | Invalid → `none` / default colour `0x39b5a8` |
| Crate rates (`CRATE_RATE`), difficulties (`DIFFS`) | `rules.crate`, `roster.diff` | Invalid → default |

Plan (PR C): move these tables to `shared/*.json` so web and Godot load the same data.

Names: `name` is truncated to **12 chars** by guests' hosts (`cleanInfo`).

---

## 6. What a new client must implement (minimum for cross-play)

1. **Layer 1:** connect, `auth`, `list`, `join`, `create`, `tohost`/`to`/`all`, `peer`, `promoted`/`rehost`, `leave`.
2. **Guest role:** `hello` → `welcome` → `roster`/`start`/`slot`/`crates`, then in-match `S`, `sw`, `f`, `k`, `h`, `ko`, `take`, `pend`, `ping`.
3. **Host role (Phase 2):** everything above plus: assigning slots, running bots, relaying guest messages, `pend`, rematch voting, host migration. This is the largest piece of work, because bots and match rules run on the host.
4. **Simulation parity:** the web game uses a hand-rolled controller (AABB collision and spring limbs). A native client must reproduce movement speeds, jump, dash, hit force and damage tables, otherwise players will see each other glide, rubber-band or take wrong damage. The numbers must come from shared data, not be re-guessed.
5. **Version handshake:** today the room refuses guests whose `build` differs from the host's. Two clients on different release schedules cannot do that. See `proto` below.

### 6.1 Protocol version (`proto`) — added in PR A

- `PROTO = 1` is the current room-message protocol.
- `hello` and `welcome` carry an integer `proto`. A missing `proto` means 1 (old builds).
- The room refuses a guest only when `proto` differs. `build` stays informational; the server's room-list `build` filter is relaxed in a later PR.
- Bump `PROTO` only for incompatible changes to layer 2.

---

## 7. Known weaknesses (to fix before a second client ships)

These are on the roadmap in `docs/IOS_PLAN.md` (PR B). A second client doubles the attack surface, so they matter more now.

| # | Weakness | Where | Fix |
|---|---|---|---|
| 1 | The host relays guest messages to everyone **without checking the sender**. A guest can send an `S`, `sw`, `ko` or `chat` with someone else's `id`. | `hostRecv` → `netHandle(m); netAllConns(m, c)` | The host overwrites `id` with the connection's real slot before relaying (for all message types that carry `id`). |
| 2 | `h.d` is trusted. A guest can send any damage or force to any victim. | `case 'h'` | The receiver clamps `d` to the weapon's max and `f` to a sane range; the host checks `from` equals the sender's slot. |
| 3 | `pend` can be sent by a guest and relayed. | `case 'pend'` | Only the host may send it; the host drops it from guests, and guests ignore it unless it came from the host. |
| 4 | `ko` and `take` can be forged. | `case 'ko'`/`'take'` | `ko` sender must own the victim's slot; `take` must name an existing `cid`. |
| 5 | The roster colour is rendered unescaped in the lobby HTML. | `netShowLobby` | Validate as an integer on receipt; escape on render. |
| 6 | Economy is client-side: coins, unlocks and `coins_####` redeem codes live in the save blob. | `redeem()`, `/api/save` | Server-side wallet and grants (Phase 3), remove codes from release builds. |
| 7 | Hosting is authoritative for bots and match end, so a malicious host can ruin a room. | Design | Accept for friends-and-rooms launch; consider server-side checks on rewards. |
| 8 | Free-text `chat` has no report or block, only a local `/mute`. | `chatSend` | iOS ships with chat off (quick-chat and emotes only); add report and block before enabling text. |
| 9 | Public relay credentials (STUN/TURN, PeerJS cloud) are used for peer mode. | `NET_ICE` | The iOS client uses only the WebSocket relay; peer mode stays web-only. |
