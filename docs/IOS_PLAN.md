# Wobble Arena → iOS: Review, Plan & Design

_Status: proposal · Written against build b76 (`public/index.html`) · Nov 2026_

---

## 1. Executive summary

Wobble Arena already has the hard part done: a fun, content-rich wobbly-physics brawler. It has about 12 modes, about 31 maps, about 29 weapons, bots with 4 difficulties, cosmetics, accounts, cloud save, online rooms and a kill-cam. The market also has a gap: **no major wobbly-physics party brawler is native on iOS yet**. Party Animals mobile is announced but has no date.

**It cannot ship to iOS as it is today.** Five blockers:

1. **It can't be played on a phone.** Touch controls were removed in build 68, and starting play requires Pointer Lock, which iOS doesn't support.
2. **It can't start offline.** three.js and PeerJS load from CDNs, and the server address is derived from `location.host`.
3. **It's too heavy for a phone.** The default quality is High: shadow map 2048, antialias, pixel ratio 2, no shared materials, few `dispose()` calls.
4. **The economy can't be monetized.** `coins_####` gives unlimited coins, everything runs on the client, and there's no In-App Purchase.
5. **It's missing App Store policy items.** There's no report/block for chat and names (guideline 1.2), a free shared TURN server is hard-coded, and there's no privacy manifest.

**Recommendation.** Ship with **Capacitor (WKWebView) first**, with all game code bundled into the app. Add native Game Center, In-App Purchase, haptics and push so it clears guideline 4.2 ("more than a repackaged website"). Only rewrite in Unity or Godot if real iPhones show performance or thermal problems in Phase 1.

---

## 2. Review

### 2.1 What's good
- **Lots of content:** modes, maps, weapons, outfits, emotes, daily gift, levels/XP, stats, match analysis, kill-cam replay.
- **Synthesized audio** (WebAudio, no files), so the app stays small.
- **Built to survive problems:** a crash guard, a backup save, recovery after a graphics reset, automatic resolution scaling, Low/Med/High quality.
- **Solid server.** Accounts use salted scrypt hashes, rate limits, recovery codes and account deletion (deletion is required by App Store 5.1.1(v)). There's a compressed static cache, a build-version gate on rooms, and host migration.

### 2.2 iPhone check (Playwright, iPhone 15 Pro landscape 852×393)

| Main menu | In match |
|---|---|
| ![menu](img/iphone-menu.jpg) | ![match](img/iphone-match.jpg) |

What these show:
- **Main menu:** the title is cut off at the top. The "Guest mode" bar sits on top of Locker and Shop, and the tip text overlaps the buttons. The layout is a desktop grid that doesn't fit a 393pt-tall screen.
- **In match:** the HUD shows keyboard hints (`DASH [V]`, `Q`, `1`) and there are no touch controls at all. The weapon label is clipped ("SHURIKE…"), name tags overlap, and the scoreboard takes about 25% of the screen.

### 2.3 Problems, by severity

| # | Severity | Problem | Where |
|---|---|---|---|
| 1 | **Blocker** | No touch input in b76, and play is gated on `requestPointerLock`. The touch layer still exists in the stale root `index.html` (b66). | `public/index.html` ~7428, 8856, 9686 |
| 2 | **Blocker** | three.js loads through an import map from jsDelivr, and PeerJS from 5 CDNs. The game won't start offline or in a bundled app. | 1301, 8167 |
| 3 | **Blocker** | `SERVER_URL` is empty, and the API and WebSocket addresses come from `location.host`, which becomes `capacitor://localhost` in a wrapped app. | 8259–8275 |
| 4 | High | `redeem()` turns `coins_<n>` (up to 9999) into coins, as often as you like. Fine for testing, fatal once coins can be bought. | 4399 |
| 5 | High | Netcode: the host relays guest messages without stamping who sent them, so a guest can fake the sender, claim any amount of damage, or end the match (`pend`). | 8422, 8617–8624 |
| 6 | High | Chat and player names have mute only. App Review 1.2 needs report, block, a filter and contact info. | 8616 |
| 7 | High | The free public "openrelay" TURN credentials and the PeerJS cloud are used as production infrastructure. | 8176 |
| 8 | Medium | The roster from the host is rendered with an unescaped `color` field, so a malicious host can inject HTML. | 8237 |
| 9 | Medium | GPU memory leak risk: about 160 places create meshes, there's a new material per mesh, and only 11 `dispose()` calls. Repeated map loads and the menu turntables grow memory. That's dangerous under iOS memory limits. | 1437, `loadMap`, `TT` |
| 10 | Medium | Too heavy by default for phones: High preset, 2048 shadow map, `antialias`, DPR up to 2. Auto-resolution only runs while Pointer Lock or a network match is active, so it never runs on touch devices. | 1323, 1416, 9727 |
| 11 | Low | No `viewport-fit=cover` or safe-area insets, `100vh` instead of `100dvh`, no orientation lock. | line 6, 628 |
| 12 | Low | Audio isn't resumed after an iOS interruption (a call, Siri), and saves and the login token live only in localStorage, which iOS can clear. | 1354, 7881, 8028 |
| 13 | Housekeeping | The root `index.html` is a stale b66 duplicate. Delete it once the touch code has been ported. | `/index.html` |

### 2.4 Architecture
- **One 929 KB file:** a single module, about 400 top-level functions, global mutable state, no build step, tests or lint. Changelog HTML and "build N" CSS patches have piled up inline.
- **What that costs:** this is fine for a solo web prototype, but it's the biggest risk to shipping native features (IAP, Game Center) and regular live updates.
- **Physics** is hand-rolled: AABB collision plus spring-driven limbs, not a real ragdoll. That's fine and cheap, and it keeps the "wobble" feel without a physics library.
- **Server:** one process with rooms in memory. Fine for launch. It needs a region plan and a paid always-on host; Render's free tier sleeps.

---

## 3. Market and trend fit (late 2026)

What the leaders do (sources are in the research brief, summarized here):

| Pattern | Who | What it means for Wobble Arena |
|---|---|---|
| 2–5 minute sessions, rotating modes | Stumble Guys, Brawl Stars | Matchmaking straight from Play, a **mode-of-the-hour rotation**, rounds of 3 minutes or less |
| Cosmetics-only, no pay-to-win | All leaders | Keep weapons free. Sell outfits, hats, emotes, KO effects, trails |
| Season pass about $5–10 | Brawl Pass about $8.99; Brawl Stars revenue rebounded in 2026 after reworking its pass | **Wobble Pass**: free plus premium track, 6-week seasons |
| Daily and weekly quests | Universal | Replaces the plain "daily gift" with 3 dailies and a weekly chain |
| UGC / map maker | Eggy Party (100M+ user maps), Stumble Workshop | We already have a **Sandbox block builder**. Grow it into "Wobble Workshop" in a later phase (needs 1.2 moderation) |
| Creator codes, licensed or themed crossovers | Stumble Guys | Later. Creator codes are cheap to add to the existing `redeem()` flow (server-checked) |
| Live-ops is what keeps a game alive | Squad Busters shuts down Dec 2026 despite Supercell backing | Plan a content cadence before launch, not after |
| Ranked mode | Stumble Guys, Brawl Stars | Trophy road first. Ranked comes once there are enough players |

**Positioning:** "_The wobbly party brawler you can play in 3 minutes, with your friends, on your phone._" Lead with the physics comedy (funny KOs, kill-cam clips you can share) instead of competing on battle-royale size.

**Payments:** coins and cosmetics must use Apple IAP (consumables or non-consumables, with the pass as a non-renewing purchase). US external purchase links currently carry 0% commission, but the court case is still open. Treat a web shop as an optional extra, not the plan. **No loot boxes.** If you add random items, 3.1.1 requires showing the odds.

---

## 4. Design

### 4.1 Core loop (mobile)
```
Open app → (Play) → matchmade 3-min round (bots fill instantly) → KO highlights + rewards
      ↑                                                                 ↓
  Locker / Shop ← coins, pass XP, quest progress ← trophies / level up ←┘
```
- **One-tap Play.** Bots fill empty seats right away, so nobody waits more than about 8 s. Humans replace bots between rounds.
- **Round length:** 3 minutes or 5 KOs. Matches are best of 3 rounds in party mode.
- **Rotation:** 3 featured modes at a time (e.g. Classic, Ninja, Moon Drift). The others are available in Custom or Private rooms.

### 4.2 Touch controls (the most important design work)
These are landscape controls in the style of Brawl Stars and Stumble Guys, re-using b66's touch layer as the starting point:

```
┌──────────────────────────────────────────────────────────────┐
│ [≡]  KOs 2 · 1:42                    🏆 Leader: Moxie  [map] │
│                                                              │
│                                                  (Grab)      │
│   ( floating                                  (Jump)  (Dash) │
│     move stick )                           ( ATTACK / aim )  │
│                          [1][2][Q]                           │
└──────────────────────────────────────────────────────────────┘
```
- **Movement:** a floating left stick that appears where the thumb lands. The camera follows automatically, and dragging on the right half of the screen looks around.
- **Attack button doubles as aim:** tap to swing or shoot at the nearest target (aim assist), or drag to aim yourself and release to fire. This is the Brawl Stars convention.
- **Weapon slots:** the hotbar becomes 3 compact icons with no keyboard hints. Hide hints whenever the last input was touch.
- **Haptics:** light on a hit, heavy on a KO, selection ticks in menus (Capacitor Haptics).
- **Accessibility:** left-handed swap, button size and opacity sliders, Reduce Motion (already exists), and aim-assist strength.
- **Controllers:** MFi and PlayStation/Xbox controllers through the Gamepad API (WKWebView supports it). It's cheap to add and on-trend.

### 4.3 HUD and menus for a 393 pt tall screen
- **HUD:** collapse the scoreboard into a top-centre pill (your KOs, the timer, the leader). The full table appears on hold or at round end. Cap name tags to 3 at a time and fade the far ones.
- **Main menu:** a big **PLAY** button with the current-mode carousel at the bottom right. Coins, gems, pass and profile go along the top bar. Locker, Shop, Pass, Friends and Settings go in a left rail. That gives the menu one clear focus and stops the overlap bugs.
- **Guest banner:** make it a small chip instead of a full-width bar.
- **Layout fixes:** `viewport-fit=cover`, `env(safe-area-inset-*)` padding, `100dvh`, and orientation locked to landscape in the native shell.

### 4.4 Progression and economy
- **Coins** (soft currency) are earned by playing and spent on base cosmetics.
- **Gems** (hard currency) are bought with IAP and spent on premium cosmetics and the pass.
- **Wobble Pass:** 50 tiers, free and premium tracks, about $6.99, with a 6-week season and a theme (e.g. "Pirate Panic" using the existing pirate map and skins).
- **Quests:** 3 dailies (e.g. "KO 5 with the spatula") and a weekly chain.
- **Trophy road:** trophies are won and lost per match and unlock modes, maps and cosmetics. That's the main long-term goal for players.
- **All currency and grants are server-side.** The client asks and the server decides. Remove `coins_####` from release builds, keep it only behind the dev panel in dev builds, and move codes to the server.

### 4.5 Social
- **Game Center:** sign-in for identity, plus friends, leaderboards (KOs, trophies) and achievements. Game Center counts as Apple's own service, but if Google or other third-party sign-in is added, guideline 4.8 means also offering Sign in with Apple.
- **Party up:** invite links (Universal Links) and a 4-digit room code (already exists).
- **Quick-chat and emotes** as the default communication. Free-text chat is off by default for under-16s, with report and block on every name and message.
- **Kill-cam clip share:** export a 6-second clip to Photos or a share sheet. Shareable clips are free marketing.

### 4.6 Tech architecture target
```
iOS app (Capacitor)
 ├─ WKWebView ── bundled web build (Vite): three.js, game modules, assets (offline-capable)
 ├─ Native plugins: Game Center, StoreKit 2 IAP, Haptics, Push, Keychain storage, Share
 └─ HTTPS/WSS ──► Game server (Node, ws) ── Redis/Postgres
                    ├─ accounts, wallet, inventory, IAP receipt validation (App Store Server API)
                    ├─ matchmaking + room relay (existing), regional instances
                    └─ live-ops config (rotation, shop, pass season) as JSON
```
- **Drop PeerJS for ranked and public play.** Use only the WebSocket relay (it already exists and is more reliable on mobile networks). Keep P2P only for "LAN or no server".
- **Netcode hardening without rewriting the game logic:** the server stamps who sent each message, the host clamps damage per weapon, only the host can end a match, and the server checks that results are plausible before granting rewards.

---

## 5. Roadmap

| Phase | Length (1 dev) | Goal | Key work | Exit criteria |
|---|---|---|---|---|
| **0. Foundation** | 1–2 wk | A buildable project | Split `index.html` into ES modules with Vite; bundle three and PeerJS locally; configurable `SERVER_URL`; delete the stale root `index.html`; add a smoke test (Playwright boots the game, starts a match) | `npm run build` produces an offline bundle, and CI is green |
| **1. Playable on iPhone** | 2–3 wk | Fun with thumbs | Touch controls (§4.2); remove Pointer Lock gating; mobile HUD and menu (§4.3); a Mobile quality preset (DPR ≤1.5, shadows 1024 or off, no AA, shared materials, `dispose()` on map change); audio resume; Capacitor iOS shell; TestFlight | 60 fps on iPhone 13, 30+ on iPhone 11, no thermal throttling in 15 min, 10 testers rate the controls "good" |
| **2. Store-ready** | 2–3 wk | Pass App Review | Game Center sign-in and leaderboards; report, block and filter (1.2); in-app account deletion (already exists, re-check); privacy manifest and nutrition labels; age rating questionnaire (expect 9+ or 13+); remove the client coin codes; netcode fixes #5 and #8; paid server host and own TURN (or relay only) | Internal review checklist passed, submitted |
| **3. Monetization and meta** | 3–4 wk | Retention and revenue | StoreKit 2 IAP with server receipt validation; gems; Wobble Pass; quests; trophy road; server-side wallet; analytics (privacy-friendly, no ATT) | D1 ≥ 35%, D7 ≥ 12% in soft launch |
| **4. Soft launch** | 4–6 wk | Tune | Launch in 2–3 small markets (e.g. Philippines, Canada, Nordics); tune the economy; fix crashes; mode rotation | Crash-free sessions ≥ 99.5% and the KPIs above met |
| **5. Global and live-ops** | ongoing | Grow | Season 1; Workshop (UGC block builder sharing); clip sharing; controller support; regional servers; Android with the same Capacitor shell | Steady 6-week season cadence |

**Rough total to global launch:** about 4–5 months for one developer, about 2.5–3 months with two.

---

## 6. Decisions needed from you

1. **Capacitor (reuse the code, faster)** or a **native rewrite in Unity or Godot** (better performance, 4–6 extra months)? This plan recommends Capacitor first.
2. **Monetization model:** cosmetics, a pass and gems (recommended), premium paid ($2.99, no IAP), or rewarded ads?
3. **Online scope at launch:** full public matchmaking, or **friends and private rooms plus bots** only? The second is smaller, with less moderation and lower server cost.
4. **Free-text chat at launch:** off (quick-chat and emotes only) is the simplest way through App Review.
5. **Target devices:** iPhone 11 and newer as the minimum?

---

## 7. Immediate next steps (proposed PRs)
1. **PR A — Foundation:** Vite build, local three and PeerJS, `SERVER_URL` config, remove the stale root `index.html`.
2. **PR B — Touch controls and Mobile preset:** port and redesign the b66 touch layer, remove Pointer Lock gating on touch, safe-area CSS, a mobile quality tier.
3. **PR C — Security quick wins:** host stamps the sender, clamp damage, host-only `pend`, escape roster colours, `coins_` only in dev builds.
4. **PR D — Capacitor iOS shell:** `ios/` project, Haptics, Keychain storage, TestFlight lane.
