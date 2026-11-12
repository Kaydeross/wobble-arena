<p align="center">
  <img src="docs/img/banner.jpg" alt="Wobblers Arena" width="100%">
</p>

<p align="center">
  <b>Bonk your friends off floating arenas.</b><br>
  A chaotic, wobbly-physics party brawler. Play free in your browser today.<br>
  Native iPhone and Android builds are in testing. Same rooms, same chaos.
</p>

<p align="center">
  <img alt="Play now" src="https://img.shields.io/badge/Play%20in%20browser-ffcf5a?style=for-the-badge&labelColor=102b35">
  <img alt="iPhone" src="https://img.shields.io/badge/iPhone-TestFlight%20testing-4aa3d8?style=for-the-badge&labelColor=102b35">
  <img alt="Android" src="https://img.shields.io/badge/Android-APK%20export%20ready-8fe0a5?style=for-the-badge&labelColor=102b35">
  <img alt="Cross-play" src="https://img.shields.io/badge/Cross--play-web%20%2B%20native-8fe0a5?style=for-the-badge&labelColor=102b35">
</p>

---

## The Game

You’re a floppy, spring-limbed wobbler. Fight on floating maps with open edges. Weapons rain from the sky. Every hit sends bodies flying.

**Knock everyone else off. Or fall trying.**

Play solo against bots (Easy to Insane), practise weapons on the practice range, or jump into online rooms with up to 8 players using a room code. Works on desktop and phone, with touch controls included.

## Screenshots

<table>
  <tr>
    <td><img src="docs/img/shot-sunny-arena.jpg" alt="Sunny Arena"><br><sub><b>Sunny Arena</b></sub></td>
    <td><img src="docs/img/shot-volcano-rim.jpg" alt="Volcano Rim"><br><sub><b>Volcano Rim</b></sub></td>
  </tr>
  <tr>
    <td><img src="docs/img/shot-pirate-ship.jpg" alt="Pirate Ship"><br><sub><b>Pirate Ship</b></sub></td>
    <td><img src="docs/img/shot-temple-ruins.jpg" alt="Temple Ruins"><br><sub><b>Temple Ruins</b></sub></td>
  </tr>
  <tr>
    <td><img src="docs/img/shot-moon-base.jpg" alt="Moon Base"><br><sub><b>Moon Base</b></sub></td>
    <td><img src="docs/img/shot-haunted-hollow.jpg" alt="Haunted Hollow"><br><sub><b>Haunted Hollow</b></sub></td>
  </tr>
</table>

<p align="center">
  <img src="docs/img/iphone-menu.jpg" alt="Phone menu" width="45%">
  <img src="docs/img/iphone-match.jpg" alt="Phone match" width="45%">
</p>

## Pick Your Wobbler

| Class | Vibe | Superpower | Trade-off |
|---|---|---|---|
| **Wobbler** | Balanced | Reliable all-rounder | None |
| **Bruiser** | Heavy tank | +30% health, hits harder | Slow & clumsy in air |
| **Scamp** | Tiny & zippy | Fastest, great air control | Fragile |
| **Gramps** | Precision | Sharp steering, fast reloads | Lower top speed |
| **Zorp** | Alien tech | Guns 20% faster, more ammo | Lowest health |

<p align="center">
  <img src="docs/style/godot-wobbler-classes.png" alt="The five classes" width="80%">
</p>

## What’s Inside

- **15 modes** in the browser game: Classic, Melee, Guns, Ninja, Explosive, Giant, Mega Damage, Weapon Ladder, Pillars, team fights (1v1 to 4v4), Sandbox and Construction.
- **Native build extras:** Team Deathmatch, Death Match, Sudden Death, Chaos (5v5 with random events), Moon Drift (low gravity) and Practice Range.
- **34 maps** including Sunny Arena, Volcano Rim, Pirate Ship, Moon Base, Haunted Hollow and Candy Land.
- **30 weapons**: bats, spring gloves, shotguns, rockets, flamethrowers, katanas, boomerangs, bows, nets and more.
- **5 classes** (see above), with a locker for skins, hats and emotes.
- **Bots** on Easy, Normal, Hard and Insane.
- **Online rooms** with room codes, a room browser and host-run bots.
- **Accounts and cloud save**, shop, results with coins, kill cam and a Settings screen.
- **Cross-play** between browser and native clients (in progress).

## Platforms

| Platform | Status |
|---|---|
| **Browser** | Playable now (the original three.js game) |
| **iPhone** | Native Godot build on TestFlight for internal testers. External testing is waiting on Apple review |
| **Android** | Same Godot project. APK and AAB export pipeline is ready (`docs/BUILD_ANDROID.md`) |
| **PC** | After phones |
| **Godot web** | Planned once the native client reaches parity. The browser game will move to `/classic` |

The native client is a Godot 4 project in `godot/`. It is not yet verified on real phone hardware for performance or thermals.

## Play It

You need Node.js 18 or newer.

```bash
npm install
npm start
```

Open http://localhost:3000 and choose Play online → Quick play.

By default, online play requires a signed-in account. To try online play locally without logging in:

```bash
REQUIRE_LOGIN=0 npm start
```

Other settings:

| Variable | Default | What it does |
|---|---|---|
| `PORT` | `3000` | Port the server listens on |
| `REQUIRE_LOGIN` | on | Set to `0` to allow online play without an account |
| `DATA_DIR` | `./data` | Where account data is stored on the file store |
| `PUBLIC_DIR` | `./public` | Folder of static game files to serve |
| `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN` | unset | Use Upstash Redis for accounts instead of files |

The server exposes a health check at `GET /health`.

## Play the Native Build

1. Install Godot **4.7.2** (the version CI and the export scripts use).
2. Open the `godot/` folder as a project and run it. The main scene is `res://scenes/main.tscn`.

For a headless run from the command line, set `GODOT` to your Godot binary before running the Godot tests (see below).

## Repository Layout

| Path | What is in it |
|---|---|
| `server.js` | Static file server and WebSocket room relay |
| `accounts.js` | Login, signup, password reset and cloud save REST API |
| `public/index.html` | The browser game (the reference implementation) |
| `godot/` | The native Godot 4 client: logic, scenes, net, tests |
| `shared/*.json` | Game data (weapons, modes, maps, classes, cosmetics, difficulties). Source of truth |
| `godot/data/` | Copies of `shared/*.json` synced for Godot, checked by `npm test` |
| `tools/` | Content export, map checks, test runners, build scripts, screenshot tools |
| `docs/` | Protocol, architecture, roadmap, build guides and per-system notes |

## Testing

```bash
npm test                    # content drift, map checker and server tests
npm run test:browser        # browser game smoke test (Playwright)
npm run test:godot          # cross-client join test (needs Godot)
```

The Godot suites run headless and need `GODOT` set to a Godot 4.7.2 binary. Examples:

```bash
export GODOT=/path/to/godot
npm run test:godot-physics  # movement parity with the browser game
npm run test:godot-combat   # hit and knockback math
npm run test:godot-bots     # bot AI parity and full bot-only matches
npm run test:godot-modes    # every ported mode played to its end
npm run test:godot-host     # Godot host with web and Godot guests
```

`npm run` lists every test script. Content in `shared/` must be exported and synced with `npm run content` and `npm run sync`. `npm test` fails if they have drifted.

## Deploying

`render.yaml` describes a Render web service (Node, free plan, health check on `/health`). The `Dockerfile` builds a Node 22 image that runs the same server on port 3000.

## Developers

Full server protocol, architecture, roadmap, build notes and test details live in [`docs/`](docs/). Start here:

- [`docs/ROADMAP.md`](docs/ROADMAP.md): current status and plan for the native client
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md): WebSocket room protocol
- [`docs/CODEMAP.md`](docs/CODEMAP.md): where each system lives in the browser game
- [`docs/GODOT_ARCH.md`](docs/GODOT_ARCH.md): how the Godot client is structured
- [`docs/BUILD_IOS.md`](docs/BUILD_IOS.md) and [`docs/BUILD_ANDROID.md`](docs/BUILD_ANDROID.md): device builds
- [`docs/CROSSPLAY_TEST.md`](docs/CROSSPLAY_TEST.md): testing browser and native players in one room
