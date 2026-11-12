# Cross-play test: web host, Godot guest

How to play a match between the browser game (host) and the Godot client (guest) on one Mac. The Godot side is the
Phase 1 guest role (`godot/net/guest_session.gd`, `godot/net/net_match.gd`); hosting from Godot is Phase 2.

## 1. Start the server without logins

```sh
npm install
REQUIRE_LOGIN=0 npm start          # Wobble Arena server on port 3000
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

## What to look for

- The browser player and its bots move smoothly in Godot (no teleporting except respawns), and your wobbler moves in
  the browser.
- Hits both ways: spatula/kick on the browser player lowers its health bar there; its hits lower yours in Godot.
- K.O.s show in both kill feeds; crates the host drops appear in Godot and disappear for everyone when taken.
- If something is off, the Godot console prints script errors; the browser's console shows the web side.

## Known limits (Phase 1)

- Godot can only be a guest. If the host leaves and the server picks Godot as the new host, Godot leaves the room
  with a message; if another player becomes host, Godot re-joins them (back to the title screen until they start).
- Weapons not ported to Godot yet (rockets, bows, shotguns, flame, ...) can be picked up but do not fire in Godot;
  when the browser player fires them Godot only shows the weapon (their hits still arrive and count).
- Modes other than the free-for-all basics (lives, Pillars clock, teams, Weapon Ladder) are not handled on the Godot
  side yet. Chat is off (nothing is sent or shown).

## Automated version

`npm run test:godot-netguest` runs the same flow with a Node host bot instead of the browser (see
`tools/test-net-guest.js`), plus a parity check of the ghost interpolation against the web game's `netStep`.

Real browser host: `npm run test:crossplay-web` (Playwright; needs network for three.js) hosts in headless Chromium with
`netHost({auto: true})`, joins from the Godot title screen with `--join`, and checks that the web host sees the Godot
player move and that a hit from the web host lowers its health.
