# CODEMAP: where each system lives

Index for porting (e.g. to Godot). Line numbers are approximate (`~N`) and match **NET_BUILD = `b76.0`** (`public/index.html` ~8414). They drift as the file grows: if a line is off, grep for the symbol name in the first column. Read only the range you need.

Files:
- `public/index.html` (~10,530 lines): CSS 12-860, DOM 862-1408, one `<script type="module">` from ~1412 to the end (three.js via importmap at ~1409). Everything is top-level script scope; the only classes are `Fighter` and `Spring2`.
- `server.js` (~229 lines): static files + WebSocket room relay. `accounts.js` (~209): login/cloud-save REST API.

## Things a porter must know first

- **Global mutable state everywhere.** `cfg` (match rules, ~7076), `settings` (~1431), `net` (~1430, null = offline), `fighters[]` (~3833), `player` (~7059), `currentMap` (~1836), `page`/`ui` (~7714/7695), `matchOver` (~7102), `pot`/`pil`/`shrink` (~7156/7192). Almost every function reads these directly.
- **Definition order matters** (module-level `const`s hit the TDZ): `WEAPONS` (~2678) before `MODES` (~2742, uses MELEE_KEYS/GUN_KEYS); `MAPS` (~1596) is extended by later passes (~1728, ~2846, ~3035, ~3290) before `MAP_ORDER` (~3363); `Fighter` (~4798) needs `CLASSES` (~4786) and `SKINS` (~3914); `player` (~7059) is built after the class; `cfg` is defined at ~7076 but referenced by earlier functions (only called after load).
- **Fixed-step simulation**: `frame` (~10059) accumulates `acc` and calls `simStep` (~9612) at `SIM = 1/120` (~9733). The order inside `simStep` is the update order (section 11).
- **Size/gravity globals**: `R`, `STEP`, `FH` (~2474) are rewritten by `giantSizes` (~9502) for Giant mode.
- **Hits are decided by the shooter's client.** `Fighter.hit` on a ghost sends the hit to the victim's game. The host runs bots, match end and rematch (section 12).
- **Inventory** is `Fighter.slots[]` + `slot` index; `ammo` is a getter/setter on the current slot.
- Weapon behaviour is data-driven by `WEAPONS[k].type`; thrown/projectile launchers are dispatched via the `PROJ` table (~9343).
- `CLASSES` (~4786) is pure data (a comment says it is exported to `shared/classes.json`).
- Many cosmetic blocks are wrapped in `try { } catch { }` and silently swallow errors; `crashNote` (~10103) records the rest.
- Menu "live battle" (`SHOW`, ~9503) temporarily swaps `cfg`; `cfgReal` (~8792) undoes it. Fragile, skip in a port.

## 1. Core helpers, settings, dev tools

| Symbol | Lines | What |
|---|---|---|
| `el, clamp, lerp, rand, wrapPi, V` | ~1416-1423 | tiny helpers; `V` makes a Vector3; scratch vectors `tmpA..` ~1425 |
| `DEF_BINDS` | ~1427 | default key bindings (KeyboardEvent.code) |
| `SHOW` | ~1429 | state of the live bot battle behind the menus |
| `settings` | ~1431 | player prefs (sens, fov, vol, binds, quality...) saved by `save()` |
| `DEVLOG, devLog, PERF, DEVS` | ~1434-1446 | error log, perf counters, dev switches (god/ammo/freeze/timescale) |
| `koPop, toast` | ~1449-1462 | on-screen K.O. banner and toast text |
| `crashNote, perfTick, applyScale` | ~10103-10128 | crash guard, auto-resolution scaling |

## 2. Audio (synth, no files)

| Symbol | Lines | What |
|---|---|---|
| `initAudio` | ~1464 | creates AudioContext, master gain, noise buffer (needs a user gesture; the Play handler and `startGame` call it) |
| `tone(f0,f1,dur,type,vol,delay)` | ~1478 | oscillator blip with pitch slide |
| `noise(dur,vol,freq,delay)` | ~1488 | filtered noise burst |
| `SFX`, `sfx(name)` | ~1497-1520 | name -> recipe table; every sound effect is here |

## 3. Renderer, scene, lights, materials, main loop

| Symbol | Lines | What |
|---|---|---|
| `IS_TOUCH_DEV` | ~1523 | pointer:coarse check; turns off antialias |
| `renderer, canvas, scene, camera` | ~1524-1535 | WebGLRenderer, Scene, PerspectiveCamera(72) |
| `hemi, sun` | ~1537-1545 | HemisphereLight + one shadow-casting DirectionalLight (2048 map) |
| `lm(color)` | ~1546 | the one material factory: MeshStandardMaterial, flat shaded |
| `applyQuality, syncGfx` | ~8382-8412 | quality presets (shadows, pixel ratio) |
| `fxSky, hazeApply, skyFxTick` | ~10130-10168 | horizon haze, lightning, sun glare |
| `frame` | ~10059 | rAF loop: camera, sim steps, pose, HUD, render |
| `bgTick` | ~10084 | worker timer that keeps online sims running in a hidden tab |

## 4. Maps / world

| Symbol | Lines | What |
|---|---|---|
| `solids, solidMeshes, mapObjs, pads, ladders` | ~1549-1553 | per-map collision AABBs, raycast meshes, cleanup list, pads, ladders |
| `addDecor` | ~1555 | adds a non-colliding mesh and tracks it |
| `addBox(cx,cz,w,d,h,color,yBase)` | ~1556 | THE collision primitive: box mesh + AABB in `solids` |
| `addLadder` | ~1566 | climbable ladder volume |
| `addStairs` | ~1578 | stack of boxes |
| `addFloorPad, addBouncePad` | ~1584-1588 | floor tint; bounce pad (power 17) |
| `MAPS` | ~1596-1727 | map table: `build()` fn, `spawns`, `bots`, env, size, flags. First batch of arenas |
| `ringPts` | ~1729 | helper: points on a ring |
| more `MAPS` | ~1728-1835 | sky/rooms/obstacle/underground levels |
| `CUSTOM_THEMES, customDefaults, addPlayerBlock, removeBlockRef` | ~1797-1835 | Sandbox/custom level editor |
| `currentMap, hills, voidPlane` | ~1836-1846 | current map id, far hills, void plane |
| `ENV_DEFAULT, backdrop, mixHex` | ~1852-1885 | per-map sky/env presets and the backdrop object |
| `clearFar, mergeFar, buildFar(kind,m,env,id)` | ~1945-1983 | distant scenery per `kind` (mountains, city, sea...); a long switch to ~2380 |
| `setBackdrop(m,id)` | ~2383 | applies sky, fog, sun, clouds for a map |
| `updateBackdrop(dt)` | ~2431 | animates clouds, stars, birds |
| big-arena / new-arena passes | ~2769-3350 | `bigPlatform`, `ball/cone/flatRing`, `floatRock`, `MAP_LOWG_NIGHT`, `PIL_PTS` (Pillars positions ~3101), more MAPS entries |
| `NEW_ARENAS, BIG_ARENAS, MAP_ORDER, TEAM_MAPS` | ~2766, ~3352-3363 | menu ordering and team-allowed maps |
| `loadMap(id)` | ~7598-7666 | tears down old map, builds new, resets fighters/stats/spawns, `dressBots`, mode init. THE match reset |
| `mapBounds, drawThumb, shot3d, ttEnsure, heroLive` | ~10358-10508 | 2D/3D map thumbnails and the spinning hero card |

Porting note: `MAPS[id].build` is imperative three.js code, not data. Spawn/bot arrays are `[x, z, y?]`.

## 5. Physics, collision, springs

| Symbol | Lines | What |
|---|---|---|
| `R, STEP, FH, GRAV, projG` | ~2474-2475 | capsule radius, step height, fighter height, gravity (projG = projectile gravity scale) |
| `collide(f)` | ~2477 | AABB-vs-capsule resolve against `solids`; sets `grounded` |
| `inSolid` | ~2502 | point-in-solid test |
| `Spring2` | ~2509 | 2D damped spring used for all floppy limb/hair wobble |
| `raySphere, raycaster` | ~2520-2532 | hit tests |
| `Fighter.physics(dt)` | ~5569 | movement, jump, ice, pads, ladders |
| `Fighter.ladderStep` | ~5544 | ladder climbing |
| `separate()` | ~9486 | pushes fighters apart |
| `groundBelow, netGround` | ~6932, ~6808 | floor raycast helpers |
| `DYN-PURE` block, `dynSetup`, `updateDyn` | ~2603-2834 | dynamic arenas (wobble / tilt / quake / drift); Godot port `godot/logic/dynamics.gd` + `arena_dyn.gd`, see `docs/DYNAMICS.md` |

## 6. Weapons

| Symbol | Lines | What |
|---|---|---|
| `WEAPONS` | ~2678-2735 | data table. `type`: melee, gun, rocket, glauncher, bow, ball, net, snake, boomerang, shuriken, typhoon... |
| `MELEE_KEYS, GUN_KEYS, PIL_BAN` | ~2736-2741 | weapon groups used by modes |
| `makeWeaponMesh(key, skin)` | ~3504-3830 | builds every weapon model procedurally |
| `GRIP, TWO_HAND, RL_HOLD, UZI_SIDE` | ~3408-3411 | hand placement per weapon |
| `skinSpatula` | ~3442 | skin-specific default spatula (wand, sword, katana) |
| Melee: `meleeBegin, meleeTick, meleeSweep` | ~5441-5543 | swing start, per-frame, per-frame hit sweep (`meleeSweep` is called from `frame`, not `simStep`) |
| `quickMelee, afterSwing, startKick, kickStep` | ~5149-5160, ~5375 | quick-melee and kick; `shove, doKick` ~9320-9336 are the input side |
| Guns: `Fighter.fireGun(w)` | ~5924 | hitscan/spread, tracer, recoil; flame style spawns `flameFx` (~5952) |
| `shotSpread, ejectShell, bulletTracer, bulletHole, tracer` | ~2572-2623 | gun visuals |
| `flameFx` | ~3402 | flame particles (damage is in `fireGun`; burning/trap countdowns are in `timers` ~5217) |
| `PROJ` | ~9343 | key -> launcher fn for thrown/projectile weapons |
| `useAmmo` | ~9345 | ammo spend; reload is `startReload ... tickReload` ~4977-5109 |
| Rockets: `launchRocket, updateRockets, explode, delayedBooms` | ~6257, ~6985, ~6938, ~6984 | rocket flight and the shared explosion (radius falloff knockback) |
| Grenades: `launchGrenade, predictLanding, updateAimRing, updateGrenades, moveGrenadeAxis` | ~6345, ~6311, ~6331, ~7026, ~7017 | arc, bounce, fuse, landing preview |
| Bow: `shootArrow, updateArrows, updateBowMesh, makeArrowMesh` | ~6401, ~6414, ~6363, ~6392 | charge draw, arrows |
| Knives: `throwKnife, releaseKnife, updateKnives` | ~6446-6459, ~6661 | also shuriken (`throwShuriken` ~6632) and typhoon (`throwTyphoon` ~6608) |
| Trident: `throwTrident, releaseTrident` | ~6283-6300 | throwable melee (`TRIDENT_THROW`) |
| Boomerang: `throwBoomerang, releaseBoomerang, updateBoomerangs, endBoomerang` | ~6480-6566 | out-and-back path, catch |
| Snake: `shootSnake, updateSnakes` | ~6714-6795 | crawler projectile |
| Snowball: `shootBall, updateBalls` | ~6796, ~6889 | |
| Nets / traps: `shootNet, landNet, updateNets, nets, trapNets` | ~6807-6888 | trap sets `f.trapT`, `f.trapNet`; the fighter is pinned in `simStep` after `separate()` |
| `clearProjectiles` | ~6302 | wipes all projectile arrays at match reset |
| `hitMarker` | ~2672 | crosshair hit feedback |
| `enemyInReach, crossInRange` | ~9711-9731 | reach test and crosshair colour |
| `aimFromHand, assistDir, aimPoint` | ~6270-6279, ~9318 | aim vectors and aim assist |
| Ninja dash: `DASH_*, doDash, dashTick` | ~9357-9372 | |

## 7. Game modes

| Symbol | Lines | What |
|---|---|---|
| `MODES` | ~2742-2757 | table: name, `allow(k)` weapon filter, `teams`, `lives`, `preset`, `dmgMul`, `ladder`... Modes: classic, melee, guns, ninja, duel, t2/t3/t4, explosive, pillars, mega, giant, gungame, sandbox |
| `MODE_ORDER, VS, MODE_DEFAULTS, pickMode` | ~3369, ~3367, ~8252 | menu list, team modes, per-mode default rules |
| `TEAM_COL, isFriend, teamKo, colOf` | ~2738-2740, ~7155 | teams and friendly fire |
| `giantOn, hpOf, maxHp, giantSizes` | ~3392, ~4796, ~7077, ~9502 | Giant mode scaling |
| Lives: `eliminate`, `updateKoText` | ~7157, ~7275 | lives out -> eliminated; last one standing wins (also `netStep` ~8950) |
| Hot potato: `initPotato, passPotato, updatePotato` | ~7174, ~7173, ~7215 | bomb holder, fuse, explode (state `pot`) |
| Shrinking arena: `updateShrink` | ~7246 | state `shrink`; enabled by the map flag `MAPS[id].shrinks`, not by a mode |
| Weapon Ladder (gun game): `GG, GG_NAMES, ggGive, ggAdvance, initLadder, ladderOn` | ~7178-7191, ~3391, ~9344 | each KO advances weapon rung `f.ggRung` |
| Pillars: `initPillars, pillarGive, updatePillars, PIL_PTS` | ~7193-7214, ~3101 | tall pillars, timed weighted weapon grants, dash with any weapon |
| `updateModeHud` | ~7262 | mode-specific HUD line |
| Scoring: `feedAdd, addKo, newSt, stats, xpOf, lvOf, BADGES` | ~7269-7288, ~1419, ~7104-7135 | kill feed, K.O. credit, per-match stats and profile |
| `computeAwards, renderResult` | ~7819-7859 | result screen |

## 8. Fighter class (`class Fighter`, ~4798-6063)

| Method | Lines | What |
|---|---|---|
| `constructor` | ~4799-4882 | builds the body mesh hierarchy, Spring2 limbs, all state fields (`slots, slot, hp, vel, pos, trapT, ...`) |
| `recolor, setSkin, skinFlags, setHat` | ~4883-4933 | colour, outfit (`buildSkinParts` ~4004), hat (`makeHat` ~3842) |
| `setWeapon, equipSlot, clearInventory, pickup, dropSlot, autoEq` | ~4937-5148 | inventory and equipping |
| `autoReload ... finishReload` | ~4971-5110 | reload state machine |
| `timers(dt)` | ~5172 | per-frame countdowns: stun, trap, burn, invuln, power-ups, death timer |
| `respawn, placeAt` | ~5248, ~5300 | respawn and teleport |
| `setClass, classLook` | ~5262-5299 | class multipliers (`CLASSES` ~4786, ids `CLASS_IDS` ~4793) |
| `hit(dmg, dir, force, head, attacker)` | ~5309 | damage, knockback, KO, ghost handling |
| `topple(dur,msg)` | ~5362 | fall down and get up (`downT`) |
| melee / kick / ladder | ~5375-5568 | see Weapons |
| `physics` | ~5569 | see Physics |
| `animate(dt)` | ~5601-5853 | procedural animation: walk, wobble springs, weapon poses, emotes (`emotePose` ~4440) |
| `updateBike` | ~5854 | Sur-Ron bike pose (`makeSurron` ~4726) |
| `applyPose` | ~5864 | writes spring state to meshes (called from `frame`) |
| `barrelDir, fireGun` | ~5918-6062 | muzzle direction and firing |

Related data: `HATS, makeHat` ~3839-3911; `SKINS, SKIN_SHOP, FREE_SKINS, CODE_SKINS, procTex, buildSkinParts` ~3914-4397; `CLASSES` ~4786 (hp/speed/size multipliers); `EMOTES, SKIN_EMOTES, playEmote` ~4399-4439; materials `eyeMat, beltMat` ~3834.

## 9. Bots

| Symbol | Lines | What |
|---|---|---|
| `BOT_NAMES, BOT_POOL, shuffleBotNames, BOT_COLORS` | ~7062-7069 | naming and colours |
| `DIFFS` | ~7070 | easy/normal/hard/insane tuning |
| `cfg` | ~7076 | match config (count, behav `brawl`/`dummy`, difficulty, hp, lives, wstate) |
| `allBots, bots, botMode, dressBots, setBotCfg, setBotMode` | ~7078-7101, ~7315-7355 | bot roster management |
| `pickTarget` | ~7357 | target choice (hot potato overrides) |
| `BOT_AIM_ERR, BOT_PREF, BOT_GRAB, BOT_GUNS, botWants` | ~7369-7371, ~6174-6181 | per-difficulty aim error, weapon preference, pickup greed |
| `clampToWalls, hasLOS` | ~7372-7387 | muzzle and line-of-sight checks |
| `rangeBot` | ~7388 | practice-range dummies |
| `botGround, pillarAt, pillarNear, botPillarHop` | ~7401-7422 | pillars-mode jumping |
| `botThink(b, dt)` | ~7423-7596 | the whole AI: move, aim, fire, flee potato, pick up |
| `BOT_RESPAWN` | ~9950 | bot respawn delay (5s) |

## 10. Pickups and crates

| Symbol | Lines | What |
|---|---|---|
| `DROP_POOL` | ~3398 | list with duplicates = relative weight; `DROP_BASE` (~6068) holds the final weights |
| `HEAL_META, PU_META, PU_KEYS, PU_MODE` | ~3393-3396 | power-ups (heal/speed/rage/shield) |
| `pickups, dropTimer` | ~6065 | live pickups, spawn timer |
| `CRATE_MULT, CRATE_RATE` | ~6072-6073 | rarity setting and drop frequency |
| `pickCrateKey` | ~6074 | weighted pick from `wstate`/mode |
| `makeCrateNet, spawnDrop` | ~6088, ~6102 | crate parachute visuals and spawn |
| `updatePickups` | ~6182 | fall, land, pickup collision, expire |
| `placeSideRacks, placeWeaponGrid, removePickup, permQ` | ~6160-6173 | practice-range weapon racks |
| `updatePads` | ~6232 | bounce pad launch |
| `RARITY, weaponIcon, hotbarHtml` | ~9736-9775 | rarity and hotbar icons |

## 11. Match flow

| Symbol | Lines | What |
|---|---|---|
| `startGame` | ~8080 | despite the name: only guest init + audio + `setUi('lobby')` |
| `setUi(st)` | ~7698 | UI state machine: boot -> title -> lobby -> play (var `ui` ~7695) |
| `el('play').onclick` | ~7683 | the real offline match start (re-loads the map if `matchOver`, enters pointer lock/touch); wrapped again at ~9129 for host/edit flows |
| `loadMap` | ~7598 | resets everything (see Maps) |
| `endMatch(w)` | ~7289 | sets `matchOver`, stats, coins, save; the game keeps running `endT` (~3.4s) |
| `updateEnding, finishMatch` | ~7304, ~7296 | after the delay: exit pointer lock, go to the result page |
| `updateLeader` | ~9857 | leader tracking |
| `simStep(dt)` | ~9612 | update order: potato/pillars/shrink -> input -> bots -> net -> fighter timers+physics -> pads -> pickups -> rockets -> grenades -> knives/boomerangs/arrows/snakes/balls/nets -> ring-out check -> `separate` -> trap pin -> animate -> replay record |
| Rematch (online): `netVote, netRematchCheck, netRematchStart, netRematchUi` | ~9069-9094 | everyone votes, host restarts with the same roster |
| Kill cam: `capFighter, kcSegments, startKillCam, endKillCam, kcStep, kcCamera, recBuf` | ~9947-10057 | records 6s at 30Hz, replays from behind the killer |
| `updateCamera` | ~9656 | third-person/scoped/orbit camera |

## 12. Networking (PeerJS WebRTC, plus optional relay via server.js)

Constants ~8414: `NET_PREFIX, NET_HZ=30, NET_MAX=8, NET_BUILD, NET_PROTO, PUB_SLOTS`.

| Symbol | Lines | What |
|---|---|---|
| `net` object | ~1430 | null offline; `{host, started, slots, conns, ghosts, ai, id, clock...}` |
| `loadPeerLib, makePeer, NET_ICE, netDiag, netErrText` | ~8421-8455 | PeerJS loaded from CDN; STUN |
| `myInfo, cleanInfo, infoOfBot` | ~8456-8458 | player cosmetics sent to others |
| `roomOpts, rosterMsg, netShowLobby, applyRoomOpts, roomSum*` | ~8468-8513 | lobby/rules sync |
| `SERVER_URL, srvUrls, srvConnect, srvTx, srvWire, srvAsk, srvRecv, srvInfo` | ~8515-8579 | WebSocket client to `server.js` |
| `mkVc` | ~8563 | fake connection object over the relay (so peer and relay paths share code) |
| `netHost`, `netHostSrv`, `netHostPeer` | ~8586, ~8590, ~8623 | create room (relay first, P2P fallback) |
| `netJoin`, `netJoinSrv`, `netJoinPeer` | ~8602, ~8606, ~8712 | join |
| `hostRecv(c, m)` | ~8656 | host handling of guest messages |
| `GUEST_MSGS, HIT_MAX, netNum, netCleanHit, netGuard(m, slot)` | ~8682-8701 | host-side whitelist/validation of guest messages |
| `hostDrop` | ~8702 | guest left |
| `clientRecv(m)` | ~8744 | guest handling of host messages |
| `makeGhost(b, slot, info)` | ~8764 | remote-fighter proxy (`isGhost`); `netRemoveGhost` ~8760 |
| `netBotToHuman, netHumanToBot, netSlotChanged` | ~8770-8790 | slots swap between bot and human |
| `netMode, cfgReal, ruleSnap` | ~8791-8793 | team modes are sent as base modes |
| `netStartMatch(slots, mapId, ...)` | ~8794 | start a synchronized match on all peers |
| `netStartHosted, netCfgSnap` | ~8990-8998 | host kicks off |
| `netResetLocal, netLeave` | ~8833-8847 | teardown |
| `netMigrate(me)` | ~8848 | host left: promote a new host |
| `ghostEquip, ghostFire` | ~8867-8885 | replay remote weapons/shots locally |
| `netHandle(m)` | ~8887 | shared message dispatcher (s=state, f=fire, h=hit, ko, take...) |
| `netSnap, netStep(dt, pre)` | ~8915, ~8949 | send/receive state at 30 Hz, remote lives rules |
| `netBrowse, renderRooms, netQuickPlay, netHostQuick` | ~9001-9066 | public room list at fixed ids `pub0..` |
| `chatAdd, chatSend, chatOpen, chatClose, chatTick` | ~8921-8947 | chat |

Flow: guests send to the host, the host validates (`netGuard`) and broadcasts. P2P and relay both go through `hostRecv`/`clientRecv` via `hostOut`/`mkVc`.

## 13. Menus, HUD, UI

| Symbol | Lines | What |
|---|---|---|
| `PAGES, ONL, PAGE_NAME, NEXT, PREV, page` | ~7710-7714 | page graph |
| `showPage(pg)` | ~7730 | switches visible page with animation; ties to `ui` |
| `applyPauseUi` | ~7763 | pause overlay |
| `refreshHome, dailyInfo, claimDaily, homePanels` | ~7772-7818 | home screen, daily gift |
| `renderModeButtons, buildMapCards, updateMapList, applyCat` | ~3373, ~7684, ~7897-7906 | mode/map pickers |
| `renderChips` + `WCATS, STATES` | ~8224-8250 | per-weapon drop-rate chips |
| `syncRules, syncSettings, syncRanges` | ~7312, ~7911-7936 | DOM <-> `cfg`/`settings` |
| `wallet, renderShop, buySkin, buyEmote, redeem, CODES` | ~4433, ~4565-4623 | shop, coins, codes |
| `renderLocker, classCard, classThumb, applyLook, look` | ~4626-4676, ~8260 | locker and classes UI |
| `drawPreview, previewTick, previewSkin, previewEmote` | ~4683-4724 | live wobbler preview in shop |
| `renderBinds, applyBind, keyName, rebinding` | ~7937-8006 | key rebinding |
| `initSettingsUi, syncPro` | ~10183-10243 | settings page tabs and search |
| `updateHud(dt)` | ~9877 | hp bar, ammo, hotbar, feed, mode HUD |
| `updateTags, drawRadar, updateDmgNumbers, dmgNumber` | ~9781-9855 | nameplates, minimap radar, damage numbers |
| `renderAccount, acShow` | ~7137-7154 | profile, badges |
| Dev panel: `devBuild ... devToggle` | ~10245-10355 | F2 panel, unlocked by code `im-a-dev` |
| `BOOT, bootStep` | ~10510-10533 | loading screen and startup (last thing run) |
| `SHOW*` (live battle background) | ~9503-9610 | `showStart/Stop/Tick/Camera` |

## 14. Input and touch controls

| Symbol | Lines | What |
|---|---|---|
| `keys, mouse, is, down, aimOn, locked, cam` | ~7668-7681 | raw input state, pointer lock |
| `playerControl(dt)` | ~9373-9485 | converts input to movement/attack/weapon switching for `player` |
| `cycleWeapon, trackSlot, clearInputs, zoomScale` | ~9248-9316 | |
| `TC, TOUCH, tcSave, touchWanted` | ~9136-9139 | touch settings and state |
| `TBTN, tcLayout, touchBuild, touchEnter, touchLeave, tPress, tHold, touchAssist, touchPill` | ~9142-9247 | on-screen buttons that write into the same `keys` as the keyboard |
| `fakeKey` | ~9272 | synthetic key events |

## 15. Save, accounts, cloud sync (client)

| Symbol | Lines | What |
|---|---|---|
| `snapshot` | ~8274 | serializable save (`v: 64`): cfg, settings, wallet, stats, look |
| `acct` | ~8276 | `{user, token, guest, dirty, stale, expired...}` |
| `authLoad, authKeep, readSave, save, load, rmSave` | ~8277-8381 | localStorage keys `wobbleArena`, `wobbleAuth`, `waTouch` |
| `cloudDirty, cloudPush, cloudBeacon, apiBases, api` | ~8299-8335 | pushes the save to the server; conflicts use timestamp `t` |
| `openAuth, authSuccess, doLogout, verifyLogin, renderAcctBox, needAcct` | ~8084-8222 | login/signup UI and flow |

Save data is one JSON blob (<= 250 KB) per account. Guests play fully offline; online play needs login unless `REQUIRE_LOGIN=0`.

## 16. Effects

| Symbol | Lines | What |
|---|---|---|
| `fx[]`, `updateFx` | ~2535, ~2624 | single particle/effect list updated each frame |
| `puff(p, color, n, spd, dir)` | ~2540 | dust/spark particles |
| `koBurst(p)` | ~2550 | K.O. shockwave ring + particles (`koRingGeo`) |
| `ringFx` | ~2557 | flat shockwave |
| `landDust(f, v)` | ~2562 | landing dust ring |
| `tracer, bulletTracer, bulletHole, ejectShell, dropMagFx` | ~2572-2623, ~3413 | gun visuals |
| `flashV` | ~6937 | explosion screen flash |
| `hurtFlash` | ~1447 | damage vignette |

## 17. Server (`server.js`)

| Symbol | Lines | What |
|---|---|---|
| `LIMITS, ALPHABET, rooms, perIp` | ~21-33 | caps and room state (memory only) |
| `serveStatic` | ~47 | gz/br cached static server, etag |
| `http.createServer` | ~72 | `accounts.handle` first, then `/health`, then static |
| `WebSocketServer` at `/ws` | ~89 | |
| `cleanInfo, publicView, newCode, findRoom, send, leaveRoom, joinRoom` | ~92-139 | room helpers (5-char codes) |
| `handlers` | ~140-192 | ops: `ping, list, create, update, join, quick, tohost, to, all, close, leave`. Pure relay: the server never simulates |
| `wss.on('connection')` | ~193 | rate limits, auth gate, dispatch |
| `beat, sweep` | ~219-222 | dead socket and stale room cleanup |
| `start, stop` | ~224-227 | |

## 18. Accounts (`accounts.js`)

| Symbol | Lines | What |
|---|---|---|
| `upstashStore, fileStore, makeStore` | ~16-54 | storage backends (Upstash Redis, or JSON files) |
| `hashPw, checkPw` | ~59-64 | scrypt passwords |
| `newRecovery, newToken` | ~65-68 | recovery codes; 64-hex bearer tokens (365 days) |
| `create(store)` | ~73 | factory; `routes` ~93: signup, login, me, save, logout, password, recovery, reset, remove |
| route map | ~177 | `/api/signup`, `login`, `me`, `save` (PUT), `logout`, `password`, `recovery`, `reset`, `delete` |
| `handle(req,res,ip)` | ~190 | dispatch, CORS, rate limits (`failCount`, `signups`) |
| exports | ~209 | `create, makeStore, fileStore, upstashStore` |

## Gotchas when porting

1. `startGame` is not the match start; use the Play handler (~7683) + `loadMap`, and `netStartMatch` for online.
2. Team modes (`t2/t3/t4/duel`) set `cfg.teams`; online they are sent as a base mode via `netMode`.
3. `Fighter.hit` on a ghost does not apply damage locally; it forwards to the owner. A server-authoritative port should redesign this.
4. Death flow lives in several places: `Fighter.hit` (KO), `simStep` ring-out (~9627), `eliminate`, `netStep`; keep them consistent.
5. Bots run on the host only and are mirrored to guests as ghosts (`net.ai`).
6. Many magic numbers were tuned by feel (comments say "build N"); copy values, not formulas.
