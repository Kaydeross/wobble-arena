# Cross-play test: web and Godot, either side hosting

How to play a match between the browser game and the Godot client on one Mac (or a phone and a computer on one
network). Sections 1–4: the browser hosts, Godot joins (the guest role, `godot/net/guest_session.gd`,
`godot/net/net_match.gd`). Section 5: Godot hosts, browsers and other Godot apps join (the host role,
`godot/net/host_session.gd`, `godot/net/host_match.gd`).

## 1. Start the server without logins

```sh
npm install
REQUIRE_LOGIN=0 npm start          # Wobblers Arena server on port 3000
```

`REQUIRE_LOGIN=0` lets anyone create and join rooms. With logins on, both sides must log in (see section 4).

## 2. Host a room in the browser

1. Open <http://localhost:3000>.
2. Go to **Online**. Classic on Sunny Arena is the best-tested combination on the Godot side.
3. Create a room: choose **Private**, press **NEXT**. The lobby shows a 5-letter **room code** (e.g. `K7QMP`).
4. Leave the browser tab in the lobby. You can start the match now or after Godot has joined: Godot also joins a
   match that is already running (it takes over a bot's slot).

## 3. Join from Godot

From the title screen:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path godot
```

Fill in **server** (`ws://127.0.0.1:3000/ws`, the default; it is remembered), **room code**, **your name**, pick a
class in the class menu, then **Join room**. The status line shows each step (connecting, joining, welcomed, waiting
for the host). When the host presses Start, Godot loads the map and you play.

Or straight from the command line (skips typing):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path godot -- --join=K7QMP --server=ws://127.0.0.1:3000/ws --name=Mac
```

To join a server on another machine on your network, use its address, e.g. `--server=ws://192.168.1.20:3000/ws`
(and open `http://192.168.1.20:3000` in that machine's browser to host).

In the match: Esc opens the menu (the online match keeps running behind it); **Leave room** goes back to the title.
When the host ends the match, a results panel offers **Rematch** (sends the vote) and **Leave room**.

## 4. With logins on (no `REQUIRE_LOGIN=0`)

Make an account in the browser (Account page), then in Godot type the username/email and password on the title
screen and press **Log in**. The token is kept in Godot's settings (`user://settings.cfg`, key `token`) and sent with
the `auth` op on every connect. **Log out** clears it.

## 5. Godot hosts a mixed room (Godot app + browser)

1. Start the server as in section 1. To use a phone, run it on a computer on the same Wi-Fi and note that
   computer's address (e.g. `192.168.1.20`).
2. In the Godot app (desktop: `/Applications/Godot.app/Contents/MacOS/Godot --path godot`; phone: the exported app),
   press **Play** once and pick the arena you want (the online room uses your last setup's arena when the game type
   allows it). Back on the title, open **Play online with friends**, set **server** to `ws://127.0.0.1:3000/ws`
   (phone: `ws://192.168.1.20:3000/ws`), type your name.
3. Press **Host a room**. Three tabs: **Room** (room name, **Private (code)** or **Public**, **Seats** 2–8, **Bots**:
   how many free seats get a bot, the others stay open for late joiners), **Mode** (game type with ‹ ›, app-only ones
   marked "(app)"; **K.O. limit** Auto / None / 5–30; arena **Floor** Steady / Random / Wobble / Tilt / Quake / Drift)
   and **Rules** (**Health** 100–500, **Gravity**, **Ammo** normal / infinite, **Knockback** 0.5x–3x, **Crates**). Then
   **Create room**. The lobby shows the room code, the players (web players marked "(web)") and a rules line. If the
   server cannot be reached the status line says so (no hang).
4. In the browser (<http://localhost:3000>, or `http://192.168.1.20:3000` on the other machine): **Online → Join with a
   code**, type the code (or pick the room in the list if it is public). The browser player appears in the Godot lobby.
   A second Godot app can join the same code with **Join room**.
5. Press **Start** in the Godot lobby. Everybody loads the arena; the Godot app runs the bots and the match rules.
6. Play to the K.O. limit (or **Leave room**): the results panel offers **Rematch**; when every player voted (or after
   20 s) the Godot host restarts with the same players, and anyone who did not vote is removed (a bot takes the seat).
7. Close the browser tab during a match: its seat turns back into a bot for everybody.
8. App-only modes (Team Deathmatch, Death Match, Sudden Death, Chaos, Pillars, Moon Drift, the team modes): pick one in
   the Mode tab with only Godot apps in the room; Start plays it for everybody (sides by seat: blue = seats 0, 2, 4, 6).
   Let a browser join the lobby: the lobby line says the mode is app-only and the match will play Classic, and the host
   status line names the browser player. A browser that tries to join while an app-only match runs is told why.
9. Host migration: with two Godot apps and a browser in a running match, quit the host app. The Godot guest that joined
   first becomes the host ("HOST CHANGED") and the match goes on where it was (same seats, K.O.s, bots, floor and
   clock; the old host's seat gets a bot). The browser re-joins and restarts the round from its spawn (the web game
   restarts a match after a migration); other Godot apps carry on in place.
10. Emotes: the emote button (or T / G / H) plays your emote for every Godot app in the room (the web game has no
   emote message, so browsers neither send nor show them).

Command line for a quick desktop host (no typing): there is none yet; use the title screen.

## What to look for

- The browser player and its bots move smoothly in Godot (no teleporting except respawns), and your wobbler moves in
  the browser.
- Hits both ways: spatula/kick on the browser player lowers its health bar there; its hits lower yours in Godot.
- K.O.s show in both kill feeds; crates the host drops appear in Godot and disappear for everyone when taken.
- If something is off, the Godot console prints script errors; the browser's console shows the web side.

## Known limits

- Host migration to a Godot guest carries the match on; a web guest promoted to host does what the web game does (it
  goes back to its lobby and Godot guests re-join it). A web guest always restarts the round after a migration.
- With a web player in the room a Godot host plays the web-compatible modes only (Classic, Melee Only, Guns Only,
  Ninja, Explosive, Giant, Mega Damage, Weapon Ladder); app-only picks play Classic (`rules.mode`), and Pillars is
  app-only from a Godot host (the web host's `pp` / `pt` Pillars is not hosted for browsers). Weapon toggles
  (`wstate`) are always all on.
- Weapons not ported to Godot yet (rockets, bows, shotguns, flame, ...) can be picked up but do not fire in Godot;
  when the browser player fires them Godot only shows the weapon (their hits still arrive and count).
- Chat is off (nothing is sent or shown); emotes are app-to-app only.

## Automated version

`npm run test:godot-host` (`tools/test-net-host.js`): the real server, a Godot host (`godot/tests/net_host_test.gd`),
a web-protocol guest in Node (`tools/wa-client.js`) and a second Godot guest (`godot/tests/net_host_peer.gd`): roster,
start, 30 Hz snapshots both ways, guest input moving its fighter on the host, hits both ways, forged messages dropped,
bot K.O. -> `ko` + `pend`, rematch votes and a second start, a leaving guest's seat back to a bot, and the clear error
when the relay is unreachable. The host picks Team Deathmatch with Host-sheet rules: with the web guest present the
`start` is Classic with the standard rules fields and no `gmode`; emotes both ways. Then
(`godot/tests/net_modes_host.gd`, `godot/tests/net_modes_peer.gd`): a room of Godot clients (the Godot peer and a
protocol guest sending `gd: 1`) plays every app-only mode to its end (`gmode`, `gteam`, `pp`, Moon Drift gravity,
Explosive health, `gm` Chaos events, `pend`), a late web guest is refused with the reason, and host migration: the
Godot host leaves mid-match, the Godot guest is promoted and resumes (`start.rs`), the web guest re-joins with a plain
`hello` and gets the standard `start` (same seats, bot, arena seed, `dt0`).

`npm run test:godot-netguest` runs the same flow with a Node host bot instead of the browser (see
`tools/test-net-guest.js`), plus a parity check of the ghost interpolation against the web game's `netStep`.

Real browser host: `npm run test:crossplay-web` (Playwright; needs network for three.js) hosts in headless Chromium with
`netHost({auto: true})`, joins from the Godot title screen with `--join`, and checks that the web host sees the Godot
player move and that a hit from the web host lowers its health.
