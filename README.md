<p align="center">
  <img src="docs/img/banner.jpg" alt="Wobble Arena: a wobbly-physics party brawler" width="100%">
</p>

<p align="center">
  <b>A wobbly, chaotic party brawler that runs right in your browser. No download, no install.</b><br>
  Bonk your friends off floating arenas with bats, rockets and spring gloves.
</p>

---

## What is Wobble Arena?

Wobble Arena is a 3D, physics-driven arena brawler. You play a floppy, spring-limbed character and fight on floating maps with open edges. Weapons rain from crates and the goal is simple: **knock everyone else off, or out**. Every hit sends bodies flying, and falling off the map is just as deadly as getting shot.

It plays in any modern browser on desktop and phone (touch controls and safe-area fixes are built in). You can play solo against bots, practise, or jump into online rooms with friends.

## Screenshots

<table>
  <tr>
    <td><img src="docs/img/shot-sunny-arena.jpg" alt="Sunny Arena"><br><sub><b>Sunny Arena</b>: open edges, knock people off</sub></td>
    <td><img src="docs/img/shot-volcano-rim.jpg" alt="Volcano Rim"><br><sub><b>Volcano Rim</b>: fall in the lava and you are out</sub></td>
  </tr>
  <tr>
    <td><img src="docs/img/shot-pirate-ship.jpg" alt="Pirate Ship"><br><sub><b>Pirate Ship</b>: do not fall in the sea</sub></td>
    <td><img src="docs/img/shot-temple-ruins.jpg" alt="Temple Ruins"><br><sub><b>Temple Ruins</b>: climb the giant pyramid</sub></td>
  </tr>
  <tr>
    <td><img src="docs/img/shot-moon-base.jpg" alt="Moon Base"><br><sub><b>Moon Base</b>: fight under the Earth</sub></td>
    <td><img src="docs/img/shot-haunted-hollow.jpg" alt="Haunted Hollow"><br><sub><b>Haunted Hollow</b>: hide behind the tombstones</sub></td>
  </tr>
</table>

<p align="center">
  <img src="docs/img/iphone-menu.jpg" alt="Main menu on a phone" width="48%">
  <img src="docs/img/iphone-match.jpg" alt="A match on a phone" width="48%">
</p>

## Features

- **14 game modes**: Classic, Melee Only, Guns Only, Ninja, Explosive, Giant, Mega Damage, Weapon Ladder, Pillars, Sandbox, and 1v1, 2v2, 3v3 and 4v4 team fights.
- **About 30 maps**: from the Sunny Arena and Slippery Rink to a Pirate Ship, Volcano Rim, Moon Base, Candy Land, Haunted Hollow and a Giant's Playroom. Some are built for one mode, such as the Moonlit Dojo for ninjas and the Blast Yard for explosives.
- **28 weapons**: bats, mallets and spring gloves, shotguns, snipers, miniguns, flamethrowers, boomerangs, net guns, snake shooters, rocket and cluster launchers, Typhoon Blades, the Ninja Katana and more.
- **Bots on 4 difficulties**: Easy, Normal, Hard and Insane. They fill teams and rooms so there is always a match.
- **Online play**: Quick play, a live list of open rooms, and room codes to invite friends (up to 8 players).
- **Accounts and cloud save**: coins, outfits, controls, settings and stats follow you to any device.
- **Locker and shop**: earn coins and unlock hats, skins and colours.
- **Practice range and Sandbox**: test weapons on dummies, or build your own arena block by block.
- **Kill-cam and radar**, so you can see who got you and who is above or below you.

## Game modes

| Mode | What happens |
|---|---|
| **Classic** | Everything drops from the sky. Last wobbler standing wins. |
| **Melee Only** | Bats, mallets and spring gloves. Get up close. |
| **Guns Only** | SMGs, shotguns, snipers and launchers. |
| **Ninja** | Shuriken, throwing knives, Typhoon Blades and the Katana, plus 3 dashes. |
| **Explosive** | Rockets and grenade launchers. Boom. |
| **Giant** | Every weapon is double size. |
| **Mega Damage** | Double damage, heavy weapons, only 3 lives and a huge arena that keeps shrinking. |
| **Weapon Ladder** | Every K.O. swaps you to the next weapon. Finish the whole ladder to win. |
| **Pillars** | Start on tall pillars too far apart to jump, so you have to dash. A new weapon arrives every 10 seconds. Most K.O.s after 3 minutes wins. |
| **1v1 Duel** | You against one bot. First to 5. |
| **2v2, 3v3, 4v4** | Team scores with no friendly fire. First team to 15 (3v3) or 20 (4v4). |
| **Sandbox** | Build an arena, place blocks and mess about. |

Sandbox and the Weapon Ladder are offline only for now.

## Quick start

```bash
npm install
npm start
```

Open <http://localhost:3000> in two browser tabs. In each, press **Play online → Quick play**, pick a mode, and you land in the same match.

## Project layout

| Path | What it is |
|---|---|
| `public/index.html` | The whole game (rendering, physics, bots, UI) in one file. |
| `server.js`, `accounts.js` | Node.js server: serves the game, keeps the room list, relays messages, stores accounts. |
| `shared/` | Game content (modes, maps, weapons, cosmetics) exported as JSON. Do not edit by hand, run `npm run content`. |
| `godot/` | An early Godot client that speaks the same room protocol. |
| `docs/` | `PROTOCOL.md` (the wire protocol) and `IOS_PLAN.md` (the plan for a native iOS version). |
| `tools/` | Content export, protocol test client, and server and browser tests. |

## Tests

```bash
npm test               # content drift check + server integration test
npm run test:browser   # browser smoke test (needs Playwright)
npm run test:godot     # Godot client cross-test
```

---

# Running the server

The server is a small Node.js app. It does three jobs:

1. **Serves the game page** (the file in `public/`), so players just open your web address.
2. **Keeps the real room list**, so Quick play and Browse rooms always show what is actually open.
3. **Passes messages between the players of a room.** The game itself still runs in the players' browsers: the room's host runs the bots and the rules, and this server is the post office. It does not run the match.

If the game can't find this server it falls back to the old direct (peer-to-peer) connections, so nothing breaks, but you only get the room list and the reliable connections when this server is up.

### Try it on your own computer (2 minutes)

1. Install Node.js 18 or newer from nodejs.org.
2. Open a terminal in this folder and run `npm install` (the `ws` package is already included in `node_modules`, so you can skip this).
3. Run `npm start`.
4. Open `http://localhost:3000` in two browser tabs. In one: Play online → Quick play → pick a mode. In the other: do the same. You should end up in the same game.

The page `public/index.html` is the game. When you get a new version of the game, replace that one file.

### Put it on the internet

Any host that can run a Node.js app and supports WebSockets works. Players need `https` (the host gives you that for free), because browsers only allow secure WebSockets from secure pages.

**Render (easy, has a free plan)**
1. Put this folder in a GitHub repository (the `.gitignore` already leaves out `node_modules`).
2. On render.com: New → Web Service → pick the repository. Render reads `render.yaml`; if it asks, build command is `npm install` and start command is `npm start`.
3. When it finishes you get an address like `https://wobble-arena.onrender.com`. That address *is* your game. Send it to people.
4. Free plans go to sleep when nobody is using them, so the first visit after a quiet period takes up to a minute to wake. A paid plan (a few dollars a month) stays awake.

**Railway, Fly.io, or any VPS:** the included `Dockerfile` works on all of them (`docker build -t wobble . && docker run -p 3000:3000 wobble`). Or just run `npm start` behind a reverse proxy (Caddy and nginx both handle WebSockets).

**Your own domain:** buy one anywhere, then add it as a custom domain in your host's settings. HTTPS is set up automatically.

**Game page on a different site than the server** (for example the game on itch.io and the server on Render): open the game once with `?server=wss://your-server-address/ws` on the end of its web address. It remembers it. Or write the address into `SERVER_URL` near the top of the online code in the game file.

### Accounts

Players sign up in the game with a username, email and password (no email check). The server keeps the account, and a copy of the player's whole save (coins, outfits, controls, settings, stats) so it follows them to any device. Passwords are stored only as salted scrypt hashes. Online play needs an account; guests can press Play and play offline but nothing is saved.

**Where accounts are kept.** Render's free plan wipes the server's own files on every redeploy, so accounts need a small free database:
1. Make a free account at upstash.com, then Create Database (Redis). Pick a region near your server (Singapore if Render is in Singapore). Leave the other settings alone.
2. On the database page, find the **REST API** section and copy **UPSTASH_REDIS_REST_URL** and **UPSTASH_REDIS_REST_TOKEN**.
3. In Render, open your service, then Environment, and add those two as environment variables. Save. Render redeploys.
4. Open `/health` on your site. It should say `"accounts":"upstash"` and `"saved":true`. If it says `"file"`, the two values are missing or mistyped, and accounts will be lost on the next redeploy.

Without those two values the server still works (accounts go in a file under `./data`), which is fine on your own computer.

### Updating

- New game version: replace `public/index.html` and restart. Each build has a version tag, and the server will not let a player on an old build into a room of a new build ("different version, refresh the page"). That stops half-broken matches after an update.
- The server squashes the game page (brotli or gzip, about 800 KB down to about 215 KB) and remembers it, so friends on slow wifi load it much faster. The page is only re-sent when it changes.
- Check it is alive: open `/health`. It shows how many rooms and players there are.

### Settings

Environment variables: `PORT` (default 3000), `PUBLIC_DIR` (default `./public`), `REQUIRE_LOGIN` (set to `0` to let guests play online; default is that online needs an account), `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` (where accounts are kept, see below), `DATA_DIR` (only used when there is no Upstash: where the accounts file goes).
Limits are at the top of `server.js` (`LIMITS`): rooms at once (300), connections at once (3000), connections per address (40), biggest message (32 KB), messages per second per player.

### What it does not do yet (honest list)

- **If the host leaves, the longest-standing player becomes the host** and everyone is moved back to the lobby of the same room. A match that was running is not carried over: the new host starts a fresh one.
- **The host's browser still runs the match**, so a player who edits their own game could cheat. Stopping that needs the match to run on the server. That is a rewrite of the game logic, not a small step.
- **No moderation yet** (no report or ban). Chat has a mute command only. Forgotten passwords: there is no email reset. Instead every account gets a one-time **recovery code** when it is made (shown in the game, stored on the server only as a hash). Typing it on the Forgot password screen sets a new password and gives a fresh code. Players can make a new code in Account > Security. Accounts made before build 70 have no code until they make one. Someone who loses both the password and the code needs a new account. Logins last a year and renew every time the game opens.
- **One server process.** Rooms live in memory, so a restart ends the running games, and you can't run several copies side by side without extra work. One small server is plenty for hundreds of players.
