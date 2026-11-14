# Wobblers Arena network protocol

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
| `join` | `id`, `build`, `kind?` | `id` is case-insensitive. `kind` (optional) is the kind of room this screen expects: `pvp` or `arcade-coop`. Replies `joined` or `nojoin`; a valid `kind` that does not match the room answers `{reason: "kind", kind: <the room's kind>}` (see 1.4). |
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
| `kind` | string | `pvp` (a normal room) or `arcade-coop` (the Construction hub's Arcade co-op); default `pvp`, derived from `mode: "construction"` for older hosts |
| `arcade` | bool | `true` exactly when `kind` is `arcade-coop` |
| `kindName` | string | 24, a human label (`Arcade co-op`, otherwise the mode name) |

An Arcade co-op room is Construction-only: when a client sends `arcade: true` (or `kind: "arcade-coop"`) with another
`mode`, the server keeps it a normal `pvp` room rather than mislabelling a classic match.

### 1.2 Server → client

| `op` | Fields | Meaning |
|---|---|---|
| `hi` | `online` | Sent on connect. `online` = connected clients. |
| `pong` | `ts` | |
| `authed` / `noauth` | `user` | Result of `auth`. |
| `rooms` | `rooms[]`, `online` | Each: `{id, name, host, mode, modeName, map, n, max, started, build, pub:true}`. Public rooms only, fullest first. |
| `created` | `id`, `pub` | You are the host (cid 0). Public rooms are `r<base36 counter>`; private rooms are a 5-char code from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. |
| `nocreate` | `reason` | `auth`, `inroom`, `busy` |
| `joined` | `cid`, `id`, `pub`, `kind`, `arcade` | You are a guest. `cid` is the server's connection id inside the room (1, 2, …) and is **not** the game slot. `kind`/`arcade` say what kind of room you just joined (1.4). |
| `nojoin` | `reason`, `kind?` | `auth`, `inroom`, `none`, `full`, `build`, `kind`. `kind` means the room exists but its kind differs from the `kind` you asked for (and carries the room's real `kind`/`arcade`); `none` means no room with that code **on this server**. |
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

Host migration: the room's `started` flag resets to false, guest cids are re-issued (the new host is cid 0, others keep their cids), and **every guest must send `hello` again**. The web client does not carry the match over (`netMigrate()`); a promoted Godot client does (6.3).

---

### 1.4 Server identity (which server is this?)

A room code is only a key on the server that created it: a code from the Official server will never be found on a
Local/Custom one and vice versa. The client names the server it is on (`godot/logic/server_info.gd`, UI chip
`godot/ui/server_badge.gd`) and shows the mismatch hint when a code cannot be found:

| Kind | What it matches | Notes |
|---|---|---|
| `official` | exactly the shipped `url` in `godot/data/extra/server.json` (after ignoring a trailing `/` and `/ws`) | the real server; release builds default to it |
| `local` | `localhost`, `127.x`, `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, Tailscale/CGNAT `100.64/10`, `*.ts.net`, `*.tailscale.net`, `*.local`, `*.lan`, `*.home` | the editor and `npm start`; only this device/LAN/tailnet |
| `custom` | any other `ws://` / `wss://` URL | typed into Settings > About |

`ServerInfo.mismatch_hint(other_url)` returns "" when both sides are the same server, and plain words otherwise ("That
room is on the Official server, but this device is on the local server …"), which is what a "room not found" screen
shows next to the code. The relay cannot see its own public URL, so this hint is computed on the client.

---

## 2. Room messages (layer 2): lobby and match flow

All are objects with a `t` field, sent inside `tohost`/`to`/`all` (layer 1). The host also receives guests' `t` messages as `msg {from, m}`.

### 2.1 Handshake

| `t` | Dir | Fields | Meaning |
|---|---|---|---|
| `hello` | guest → host | `build`, `name`, `skin`, `hat`, `color`, `cls?` | First message. `build` must equal the host's `NET_BUILD` or the host answers `badver`. Info fields are validated against the host's tables (see §5). |
| `welcome` | host → guest | `id` (slot, ≥1), `name` (room name), `pub` | `id` is the game slot, the lowest free one. Until `welcome`, a guest ignores everything except `welcome`, `full`, `badver`, `kick`. |
| `full` | host → guest | – | No free slot. |
| `badver` | host → guest | – | Build mismatch. |
| `kick` | host → guest | `msg` | Removed by the host (e.g. did not click Rematch). |
| `info` | anyone → host | – | Peer-mode room browsing only; the host replies with a `info` object. Not used in server mode. |
| `ping` / `pong` | guest ⇄ host | `ts` | Sent every 1.5 s by guests; the host echoes `ts`. Used for the ping display. |

### 2.2 Lobby

| `t` | Dir | Fields | Meaning |
|---|---|---|---|
| `roster` | host → all | `roster[]`, `max`, `bots`, `lim`, `bhv`, `diff`, `modeName`, `map` | Players in the lobby. Each roster entry is `{id, name, skin, hat, color, cls?}`. `bots`: fill empty seats with bots. `lim`: KO limit. `bhv`: `brawl` or `dummy`. `diff`: bot difficulty id. |
| `start` | host → all | `slots[]`, `map`, `custom`, `limit`, `rules` | Begins a match (also re-sent on rematch and to a guest who joins mid-match). |
| `slot` | host → all | `slot`, `kind`, `info` | Slot owner changed: a friend replaced a bot (`human`), left (`bot`/`empty`). |
| `crates` | host → joiner | `list[] {cid,key,spot}` | Pickups currently on the map, sent to a mid-match joiner. |
| `rv` | guest → host | – | "Rematch" vote. |
| `rvs` | host → all | `list[]`, `total` | Rematch votes so far (slot ids) and the number of humans. When all humans vote, or after **20 s**, the host restarts and kicks anyone who did not vote. |

`slots[]` entries: `{kind: 'human'|'bot'|'empty', id, name, skin, hat, color, cls?}`. Index = slot. Slot 0 is always the host.

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
| `/api/claim` | POST | `name` (same rules as `username`; case-insensitive unique), `data?` | `{ok, token, user, data, t}` — **the easy path**: a password-less account from just a name. Same rate limit as sign-up (40 per IP per hour); 409 `username` when taken |
| `/api/protect` | POST | `password` (6–72) | `{ok, recovery, user}` — authenticated; puts a password (and a recovery code, shown once) on a name-only account so it can use `/api/login` on another device; 409 `has` if it already has one |
| `/api/login` | POST | `id` (username or email), `password` | `{ok, token, user, data, t}` |
| `/api/me` | GET | – | `{ok, user, data, t, hasRecovery, hasPassword}`, renews the token |
| `/api/save` | PUT | `data`, `base?`, `force?` | `{ok, t}`; if another device saved newer: `409 {ok:false, err:'stale', data, t}` |
| `/api/logout` | POST | – | `{ok}` |
| `/api/password` | POST | `old`, `next` | `{ok, token}` — revokes every old session and returns a replacement token (400 `nopass` on a name-only account: use `/api/protect`) |
| `/api/recovery` | POST | `password` | `{ok, recovery}` (new code; old one stops working) |
| `/api/reset` | POST | `id`, `code`, `password` | `{ok, token, user, data, t, recovery}` |
| `/api/delete` | POST | `password` (not needed for a name-only account) | `{ok}` — revokes every session; **required by App Store 5.1.1(v)** |
| `/api/rank` | GET | query `board=kos\|wins\|arcade`, `limit?` | `{ok, board, entries: [{rank, name, score, updated, me?}], you?}` — public; a valid Bearer token adds `you` |
| `/api/rank` | POST | `kos?`, `wins?`, `matches?`, `arcade_best?`, `arcade_diff?` (`easy`\|`normal`\|`nightmare`, default `normal`), `board?`, `limit?` | `{ok, board, entries, you, stats}` — authenticated; stores the account's bests (monotonic) and returns the requested board |
| `/health` | GET | – | `{ok, rooms, players, accounts, saved}` |

`user` is `{username, email, created, hasPassword}` (`email` is `''` for a name-only account).

**Inactive accounts are retained by default.** The server keeps a `lastSeen` per account (written by `/api/me`, `/api/save`, `/api/login` and the relay `auth` op, at most once an hour per account). A sweep at start-up and every 6 hours can erase accounts older than an explicitly configured positive `ACCOUNT_TTL_DAYS`; the default `0` never erases them. Erasure removes the account, cloud save, every token and the email and frees the name. Accounts created before `lastSeen` existed get `lastSeen = now` the first time the sweep sees them. The server logs counts only, never names.

Password change and reset revoke every token for the account. Reset and password change return one fresh token for the current device. Account deletion also revokes every token. Do not attach a purchasable wallet to an account with automatic expiry enabled.

Error shape: `{ok:false, err, msg}` with HTTP 400/401/409/413/429/500. Tokens last 365 days and are renewed by `/api/me`. Failed logins are rate limited (8 per account / 40 per IP per 10 min).

The `data` blob is the whole client save (settings, coins, owned cosmetics, stats). Its schema belongs to the web client today; see §7 for why the server must own the economy before iOS ships.

### 4.1 Ranking (leaderboard)

Three boards: `kos` (lifetime K.O.s), `wins` (lifetime matches won) and `arcade` (the furthest Arcade co-op stage,
weighted by difficulty: `easy` x1, `normal` x2, `nightmare` x3, so Nightmare 2 = 6 ranks above Normal 2 = 4).

- **Storage.** The account record gets a `rk` object (`{kos, wins, matches, arcade: {easy, normal, nightmare}, at}`),
  raised only: a lower value in a later submit is ignored, so an old device or a replayed request can never lower a
  best. Each board has one small cache key `rank:<board>` with its top 100 entries; both store kinds (file `db.json`,
  Upstash) use the same get/set calls. `accounts.js` holds all of it; `GET` is one store read.
- **Validation.** `kos`/`wins`/`matches` are whole numbers `0..10000000`; `arcade_best` is `0..6` (the number of stages);
  anything else (string, float, negative, NaN/Infinity, too large) is `400 err:"stats"`, and an unknown `board` or
  `arcade_diff` is refused too. At least one stat field is required. Authenticated: no/invalid token is `401 err:"auth"`.
- **Rate limit.** 6 accepted submits per account per 10 s (`429 err:"slow"`); rejected bodies do not use the budget.
- **Ordering.** `score` descending, then the earlier `updated` time, then name. `updated` is the epoch milliseconds of
  the submit that first reached that score. `rank` is 1-based; `you.rank` is estimated (`top.length + 1`) when the player
  is below the cached top, and `you.estimated` is true while it is not the exact position.
- **Kids mode** is not ranked: `godot/net/account_api.gd` `submit_rank()` refuses before any request when
  `Settings.kids_mode` is true, `world/world.gd` submits only after a result when signed in and not in Kids mode, and the
  RankingSheet says so. Reading a board is still allowed.

Client: `AccountApi.fetch_rank(board, cb)` / `AccountApi.submit_rank(stats, cb)`; UI `godot/ui/ranking_sheet.gd`
(tabs, loading/empty/error states, the player's row highlighted, the server badge + host in the header), opened from the
Account sheet's Leaderboard button. Gameplay never waits for a submit.

---

## 5. Shared content ids a second client must know

The room messages refer to content by string/number ids. Both clients must agree on them. Today they live only in `public/index.html`:

| Table | Used in | Validation |
|---|---|---|
| Map ids (`MAPS`, about 31) | `start.map` | Unknown → `arena` |
| Mode ids (`MODES`, about 12) | `rules.mode`, `info.mode` | via `netMode()` |
| Weapon keys (`WEAPONS`, about 29) | `S.w`, `sw.w`, `f.w`, `crate.key` | Unknown weapon ignored |
| Skins (`SKINS`), hats (`HATS`), colours (`SWATCH`) | `hello`, `roster`, `slots` | Invalid → `none` / default colour `0x39b5a8` |
| Character classes (`CLASSES`, `shared/classes.json`) | `hello`, `roster`, `slots`, `slot` (`cls`) | Missing/unknown → `wobbler`. Optional, additive: proto stays 1; old clients ignore it |
| Crate rates (`CRATE_RATE`), difficulties (`DIFFS`) | `rules.crate`, `roster.diff` | Invalid → default |

**Character classes (`cls`).** Each player's class id is an optional string in the info fields (`wobbler` default, `bruiser`, `kid`, `elder`, `alien`). It is cosmetic-plus-stats: every client applies the multipliers in `shared/classes.json` to the fighters it simulates (its own and, for display, ghosts). Nothing else on the wire changes: `S.hp` stays absolute, so a receiver must draw a remote HP bar against that fighter's own max (`cfg.hp * (giant ? 2 : 1) * CLASSES[cls].hp`). Hit damage `d` on `h` is the raw weapon damage; the victim side multiplies by the attacker's `dmg` and by the victim's own `kb` (knockback taken). Multipliers (1 = Wobbler): `hp` max health, `spd` run speed, `acc`/`air` ground/air steering, `jump`, `kb` knockback taken, `dmg` damage dealt, `rate` fire rate, `reload`, `ammo` pickup ammo, `wob` wobbliness, `size` body scale, `head` head scale, `wide` torso width and `skin` (Zorp green tint) (looks only: hitboxes and collision never change). Movement uses `spd`, `acc`, `air`, `jump` exactly as `Fighter.physics` (see `godot/logic/fighter_physics.gd`, parity-tested for every class).

| id | Name | Idea | hp | spd | acc | air | jump | kb | dmg | rate | reload | ammo |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `wobbler` | Wobbler | balanced | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| `bruiser` | Bruiser | strong but slow | 1.3 | 0.88 | 0.85 | 0.8 | 0.92 | 0.65 | 1.12 | 0.95 | 1 | 1 |
| `kid` | Scamp | fast but light | 0.75 | 1.22 | 1.2 | 1.3 | 1.12 | 1.3 | 0.92 | 1.05 | 1 | 1 |
| `elder` | Gramps | control | 1.05 | 0.95 | 1.55 | 2.1 | 1 | 0.9 | 1 | 1 | 0.75 | 1.1 |
| `alien` | Zorp | low HP, great tech | 0.7 | 1.02 | 1 | 1.25 | 1.18 | 1.1 | 1 | 1.2 | 0.8 | 1.5 |

Plan (PR C): move these tables to `shared/*.json` so web and Godot load the same data.

Names: `name` is truncated to **12 chars** by guests' hosts (`cleanInfo`).

---

## 6. What a new client must implement (minimum for cross-play)

1. **Layer 1:** connect, `auth`, `list`, `join`, `create`, `tohost`/`to`/`all`, `peer`, `promoted`/`rehost`, `leave`.
2. **Guest role:** `hello` → `welcome` → `roster`/`start`/`slot`/`crates`, then in-match `S`, `sw`, `f`, `k`, `h`, `ko`, `take`, `pend`, `ping`.
3. **Host role (Phase 2, Godot: see 6.2):** everything above plus: assigning slots, running bots, relaying guest messages, `pend`, rematch voting, host migration. This is the largest piece of work, because bots and match rules run on the host.
4. **Simulation parity:** the web game uses a hand-rolled controller (AABB collision and spring limbs). A native client must reproduce movement speeds, jump, dash, hit force and damage tables, otherwise players will see each other glide, rubber-band or take wrong damage. The numbers must come from shared data, not be re-guessed.
5. **Version handshake:** today the room refuses guests whose `build` differs from the host's. Two clients on different release schedules cannot do that. See `proto` below.

### 6.1 Protocol version (`proto`) — added in PR A

- `PROTO = 1` is the current room-message protocol.
- `hello` and `welcome` carry an integer `proto`. A missing `proto` means 1 (old builds).
- The room refuses a guest only when `proto` differs. `build` stays informational; the server's room-list `build` filter is relaxed in a later PR.
- Bump `PROTO` only for incompatible changes to layer 2.

### 6.2 Godot host notes (Phase 2, `godot/net/host_session.gd` + `godot/net/host_match.gd`)

A Godot client can host a room that web and Godot guests join. It speaks exactly the web host's layer 2:

- **Room:** `create {pub, info}` with the same `info` as `srvInfo` (`build` = `NetClient.BUILD`), `update` when the
  roster, the started flag or the room size changes. `info` requests are answered with `roomInfo`.
- **Lobby:** `hello` -> `badver` if `proto` differs, else the lowest free slot (a running match also skips human
  slots), `full` past the seat count (`max` players in the lobby, the slot count in a match), `welcome {id, name, pub,
  proto}`, then `roster` to everybody (`max`, `bots`, `lim`, `bhv`, `diff`, `modeName`, `map`). Refused guests are
  removed with `close` 0.4 s later.
- **Start:** slots = the roster (human) plus, for the free seats, as many `bot` seats as the host picked and `empty`
  for the rest (the web host fills every seat with a bot or none; an `empty` seat is just a seat a late joiner can
  take). The `start` goes out after the host's match is set up, so bot seats carry the bots' real name / look / class.
  `rules` = `{mode, hp, crate, wstate, grav, kb, inf, dyn, dseed, dt0?}`; `mode` through `HostSession.net_mode`
  (= `netMode`, plus Pillars -> Classic until `pp`/`pt` are hosted); a fresh `dseed` every match and rematch;
  `limit` 0 in lives / ladder modes.
- **In match:** the host's own fighter and every bot in one `S` at 30 Hz (`sw`/`f`/`k` when they start an action);
  crates spawned only by the host, announced with `crate {cid, key, spot}`; every take (host, bot or guest) as
  `take`. Guests' messages go through `HostSession.guard` (= `netGuard`: allowed types only, `id` stamped, first `S`
  entry only, `h.from` must be the sender and numbers clamped, `ko.to` must be the sender, `take` only for a live
  crate) and are then handled and relayed to the other guests; `h` with `to` 0 is applied by the host, any other `h`
  goes only to that guest. A guest joining a running match takes a bot's (or an empty) seat: `welcome`, `start` with
  the current `dt0`, `crates`, and `slot {kind: human}` to the others; a guest leaving turns the seat back into a bot
  (`slot {kind: bot}`) when the room has bots, else empties it.
- **Match end:** the host's K.O. limit / last-one-standing decides and sends `pend {w}` (the web host leaves that to
  every client except in Pillars; sending it is harmless for web guests and is what Godot guests rely on).
- **Rematch:** `rv` votes -> `rvs {list, total}`; all humans voted, or 20 s after the first vote (once the host's
  match is over): non-voters get `kick` and their seat becomes a bot, and a new `start` goes out.
- **Rules:** the Host sheet's mode, K.O. limit (`limit`; -1 = the mode's own), `hp`, `grav`, `kb`, `crate`, `inf` and
  `dyn` go out in `rules` like the web host's ruleSnap; Explosive always sends `hp` 300.
- **App-only modes, host migration, emotes:** see 6.3. **Not yet:** chat display, the web host's Pillars (`pp`/`pt`
  for browsers), weapon toggles (`wstate` is always `{}`).
- **Tests:** `npm run test:godot-host` (web-protocol guest + Godot guest against a Godot host on the real server).

### 6.3 Godot-only additive fields (web clients ignore them)

Everything here is optional and additive: the web client never sends it and drops or ignores it on receipt (unknown
`t` values fall through its `netHandle`, unknown `rules` / `start` / roster fields are not read, its `netGuard` drops
unknown guest messages). `PROTO` stays 1.

| Where | Field | Meaning |
|---|---|---|
| `hello` (guest → host) | `gd: 1` | "I am a Godot client" (capability level 1). |
| `hello` | `pslot` | After a host migration: my slot in the old match, so a Godot host gives it back. |
| `welcome` (host → guest) | `gd: 1` | The host is a Godot client. |
| `welcome` | `rsm: 1` | Host migration: this host carries the running match on; keep the arena and wait for `start`. |
| `roster` entries, `slots` entries | `gd: 1` | That player is a Godot client (a Godot host marks web players in its lobby). |
| `roster` | `rl` | The Godot host's rules for the lobby line: `{want, mode, lim, hp, grav, kb, crate, inf, dyn, map}` (`want` = the host's pick, `mode` = what plays). |
| `start.rules` | `gmode` | An app-only mode the Godot clients play (`mode` stays the web fallback, Classic): `tdm`, `deathmatch`, `sudden`, `chaos`, `pillars`, `lowg`, `duel`, `t2`, `t3`, `t4`, and (`6.4`) `construction` for an Arcade co-op room (`NetMatch.GODOT_MODES`). Sent only when every guest said `gd`. |
| `start.rules` | `gteam` | Team modes: the side (0 blue / 1 red) of every slot, `slot % 2`. |
| `start.rules` | `pp` | Pillars: the pillar (spawn index) of every slot, a permutation, shuffled every match by the host. |
| `start.rules` | `grav: 0.15` | Moon Drift (`gmode: lowg`). |
| `start` | `rs`, `rsx` | Host migration: the old match's state per (new) slot `[{id, x, y, z, yaw, hp, ko, dt, lv, el, d, gg}]` (`d` = was down: starts on its spawn; `el` = eliminated) and `{pt}` (Pillars clock). `rules.dseed` / `dt0` keep the arena seed and clock. |
| `start` | `arc` | Arcade co-op run (`6.4`): `{run, st, of, diff, seed, seats:[0,1], crew:[2,…], boss, big, state, lv}` — the whole run as the host sees it, re-sent with **every stage's** `start` (that is the stage-transition mechanism). |

New room messages (host → all unless noted):

| `t` | Fields | Meaning |
|---|---|---|
| `gm` | `k: "st"`, `ko[]`, `dt[]`, `gg[]`, `pt?` | 1 Hz mode state: every slot's K.O.s, deaths and Weapon Ladder rung, the Pillars clock. Godot guests take it over (team scores are the sums of `ko` by `gteam`). |
| `gm` | `k: "cw"` / `"cs"` / `"ce"`, `id`, `fl?`, `g?` | Chaos: an event was announced (3 s countdown) / started / ended. `id` = `crates`, `gravity`, `knockback`, `giant`, `speed`, `floor`; `fl` = the floor it forces; `g` = the giant's slot. Guests apply it (gravity, knockback, speed, giant, floor) instead of rolling their own. |
| `am` | `st`, `of`, `s`, `lv`, `hf`, `sh`, `dn[]`, `dnt[]`, `rv?`, `bt[]`, `cn`, `last?`, `won`, `ph?`, `vic?` | Arcade co-op run state (`6.4`): stage index / count, state (`intro`/`fight`/`clearing`/`cleared`/`failing`/`failed`/`over`/`won`), shared lives, boss health fraction 0–1, shrinking-floor size in metres (0 = none), the downed player seats' slots and seconds to their revive, the latest revive instruction, the bot-played seats, the clear/victory counter, the stage summary (`_pay()`: `seats[]` with each seat's K.O.s, `reward`/`bonus`, and the coins that save gets), `won`, the boss phase and the victory summary. Display state only: it never advances a stage or damages anyone; it does drive the guest's own cards/HUD/floor and its own save (per player, once per `cn`). |
| `emote` | `id`, `e` | guest → host → others (and the host's own): player `id` plays emote `e` (an id of `godot/data/extra/locker.json` `emotes`). The host stamps `id`, drops unknown ids and more than one per 0.4 s. |

Rules a Godot host follows:

- **Mode choice:** the Host sheet's pick plays when it is web-compatible (`netMode`) or every guest is a Godot client;
  otherwise the match plays Classic, the lobby line says why ("app-only: a web player is here") and the host's status
  names the web player. A web guest who joins a running app-only match gets `kick {msg}` with the reason.
- **Match end:** in an app-only mode the Godot guests never end the match themselves (`ModeRules.remote`): the host's
  K.O. limit / last one standing / Pillars clock decides and sends `pend`. Team results name the side.
- **Determinism:** the host's random source is seeded from the arena seed (`dseed`); Chaos events, Pillars shuffles and
  bots run on the host only and reach the guests as `gm` / `pp` / snapshots.
- **Host migration (a Godot guest promoted):** the guest's own view of the match (positions, health, K.O.s, deaths,
  lives, ladder rungs, Pillars clock, arena clock) becomes `rs`. It becomes slot 0, the old host's seat becomes its old
  slot (a bot, or empty without bots), every other seat keeps its number: Godot guests reclaim it with `pslot`, web
  guests by name. After 3 s (or as soon as everybody is back) a `start` with `rs`, the same `dseed` and `dt0` resumes
  the match; bots keep their names. Godot guests stay in the arena ("HOST CHANGED" banner) and continue in place; web
  guests run their normal migration and start the round from their spawn. With no running match the new host opens the
  lobby. If the relay promotes a web client, Godot guests re-join it as before.

---

## 6.4 Arcade co-op room (Godot only, additive)

The Construction DLC's boss rush can be played by two players (`docs/ARCADE_COOP_PLAN.md`, M1). It is an **app-only**
room: `mode` / `rules.gmode` are `construction`, a web guest is refused with `kick` (never downgraded to Classic: there
is no Classic version of a run), the room is private and has two seats.

| Field | Where | Meaning |
|---|---|---|
| `arcade: true` | host opts (`begin_host`) | Opens an Arcade co-op room: it reads Construction from the run instead of the Host sheet (HP, gravity, knockback, crates and the K.O. limit come from the stage table) and caps at two seats. The hub's "Play co-op" calls this directly. **On the wire** the room's `info` and the room list carry `kind: "arcade-coop"`, `arcade: true` and `kindName: "Arcade co-op"` (1.1), and `join` may send `kind: "arcade-coop"` to be sure a code is this kind of room. |
| `start.slots` | `start` | `[seat0, seat1, crew0, crew1, …]` — the two player seats first, then the stage's crew bots (the boss is `crew[0]`). `MatchSim.setup` gets `bot_count = slots.size() - 1`, so the host has a fighter for every slot; `HostMatch.setup` turns seat slots into ghosts (humans) or keeps them as teammate bots and keeps the crew as its AI bots. **The crew slots are not joinable**: a joining/rejoining guest only ever gets slot 1. `slots.size() <= 8` (stage 1: 2 + 4). |
| `start.arc` | `start` | `{run, st, of, diff, seed, seats, crew, boss, big, state, lv}`: the run seed, this stage (0-based) and the stage count, the difficulty, this stage's generated-site seed (`SiteMap.set_seed` — the guest rebuilds the identical site from it), the seat/crew slots, the boss' slot (-1 on a stage without one), the 1.5x Client visual flag, the state (always `intro` for a stage's start) and the shared lives. **A new `start` per stage is the stage-transition mechanism**, exactly like a rematch: the guest's world rebuilds (`_on_net_start` → `load_map`), so no stale map, crates, hazards or crew survive. A mid-run join/rejoin gets the same `start` with the current stage's `arc`. |
| `am` | host → all | Run display state, ~5 Hz + on every state change (table in `6.3`): stage/count, state, shared lives, boss hp fraction, shrink size, downed seats (`dn`+`dnt`), the revive instruction (`rv`), bot-played seats (`bt`), the clear/victory counter (`cn`), the stage summary and the victory flag. The guest applies it for its cards/HUD, its own shrinking floor and its own down/revive; it is presentation only (it never advances a stage or damages anyone). Coins and records are per player: the host writes its own save, and each guest applies its own `DlcSave.has_cleared` to `last` / `vic` and pays its own save once per `cn` (never a second save on the host, never a guest save on the host). |
| `am.dn` / `am.dnt` | host → all | The downed player seats' **room slots** (from `arc.seats`) and the seconds left on their 6 s auto-revive, for the guest's HUD lines and its "Down! Back in N" overlay. A guest whose own slot is in `dn` pins its own fighter (no input, no local respawn); the 6 s auto-revive and the "all seats down" rule stay host-side (`ArcadeManager`). |
| `am.rv` | host → all | The latest revive, applied once by its `n`: `{n, k (room slot), x, y, z, hf (health fraction), iv (invulnerability s)}`. The guest places its own fighter at that safe spot with that health fraction and invulnerability; without it the guest never brings its own fighter back. |
| `am.cn` | host → all | A monotonic counter bumped by the host's stage clear (`_pay`) and final victory (`_win`). The guest pays its own save for a clear/victory only when `cn` moves past what it already paid, so repeated `am`s and a stage retry pay nothing twice. |
| `am.bt` | host → all | The room slots played by a **bot** (a dropped guest's seat, or the teammate bot the room started with): `am` marks them so the HUD/cards can say so. The seat stays a player seat (it fights the crew) and is joinable again. |

Rules a Godot host follows for this room (implemented in `host_session.gd` / `host_match.gd` / `arcade_manager.gd`):

- `net_mode("construction")` returns `construction` for an arcade room (else Classic for anything the web cannot play);
  the `start` carries `rules.gmode = "construction"` so Godot guests play Construction.
- The run's stage/seed/lives/crew live in the host's `ArcadeManager`; `next_stage`/`retry_stage` reload the world, and the
  new `start` (with the stage's `arc`) goes out from `match_ready` like any other match start.
- A teammate bot fills an empty seat: the room may start 1 human + 1 bot. If the friend leaves mid-run the seat becomes a
  bot that KEEPS the player's fighter (class, look, name, weapon; `HostMatch.ghost_to_bot`) and fights the crew
  (`ghost_to_bot` + `ArcadeManager.refresh_seats(keep)`), and `am.bt` marks it; the friend rejoins the same slot, gets the
  current stage's `start` (current `arc.st`/seed) and `bot_to_human` gives the seat back with the class from its hello.
  Seat flags (`is_player`) are re-applied when a seat changes owner.
- If the host leaves, the run is over: no host migration inside an Arcade run for v1 (`capture_resume` never carries one).
  The relay promotes the remaining player, but the Arcade world does not resume it: it closes the promoted room and both
  sides return with "The host left. The Arcade run is over." (the host's own message is "The Arcade run is over.").

Test: `npm run test:godot-host`, scenario D ("arcade"): the room's relay metadata carries `kind: "arcade-coop"` / `arcade: true`, a probe asking to join it as `pvp` is refused with `nojoin {reason: "kind"}` while a made-up code is `reason: "none"`, and a real join's `joined` reply carries the kind; then a host starts the room with the teammate bot; a Godot guest joins
mid-fight and reports the same site seed, the host seat / every crew slot / the boss as ghosts, and `am`; the host puts
the guest seat down (`am.dn`) and auto-revives it (`am.rv`: the guest pins itself, then is placed at the host's spot with
its health fraction); a real clear and a retry clear pay the guest's OWN save once (350 coins) and then nothing (the
`GUEST_SAVE` lines); the HUD names "Stage 2 / 6" with the boss bar at `am.hf`, and `am.sh` sets the guest's shrinking
floor; the guest leaves and seat 1 becomes a teammate bot that keeps the player's class and targets the crew; the guest
REJOINS mid-run and gets a `start` with the current `arc.st`/seed and seat 1 (`slots[1].kind == "human"`, its class);
the host wins (the guest pays the victory bonus + hat on its own save) and leaves (the run-over reason).

---

## 7. Known weaknesses

Items 1–5 were fixed in PR B (`netGuard` and `netCleanHit` in `public/index.html`). The rest are open and on the roadmap in `docs/IOS_PLAN.md`.

**Host rules for guest messages (implemented):**
- A guest may only send `s`, `S`, `sw`, `f`, `k`, `h`, `ko`, `take`, `chat`, `rv`, `ping`, `hello`, `info`. Anything else (`start`, `roster`, `slot`, `crate`, `crates`, `pend`, `rvs`, `kick`, …) is dropped.
- The host overwrites `id` with the guest's real slot on `s`, `sw`, `f`, `k`, `chat`, and keeps only the guest's own entry in `S` (stamped with its slot).
- `h` is dropped unless `from` equals the sender's slot. `d` is clamped to 0–250, `f` to 0–120 and the direction to ±2. Receivers clamp again.
- `ko` is dropped unless `to` is the sender's own slot. `take` is dropped unless the crate `cid` exists.
- Guests rebuild every `roster` entry through `cleanInfo`, so a hostile host cannot send odd colours or extra fields.

| # | Weakness | Status |
|---|---|---|
| 1 | Sender not checked on relayed messages | **Fixed** |
| 2 | `h.d` trusted | **Fixed** (clamped; per-weapon limits still to do) |
| 3 | Guest can send `pend` | **Fixed** |
| 4 | `ko` and `take` forgeable | **Fixed** |
| 5 | Roster colour rendered unescaped | **Fixed** |
| 6 | Economy is client-side: coins, unlocks and `coins_####` redeem codes live in the save blob (`redeem()`) | Open. The web game has no dev/release split yet, so the codes stay until the server-side wallet (Phase 4) |
| 7 | A malicious host can ruin a room (it runs bots and decides the winner) | Accepted for the friends-and-rooms launch |
| 8 | Free-text `chat` has no report or block, only a local `/mute` | Open. iOS ships with chat off |
| 9 | Public relay credentials (STUN/TURN, PeerJS cloud) in peer mode | Open. iOS uses only the WebSocket relay |
