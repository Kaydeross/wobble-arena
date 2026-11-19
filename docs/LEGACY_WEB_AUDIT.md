# Legacy web retirement audit

_Status: decision document (docs only; this PR changes no code). Measured on branch `docs/legacy-web-audit` from `origin/main` at `08a89b2`, 16 November 2026. The legacy client at that commit is `NET_BUILD = 'b77.0'` (`public/index.html:9193`)._

Inputs: the revised execution plan v1.0 (the `docs/REVISED_PLAN.md` draft landing in a parallel docs change — it is **not** on `main` at this commit, so references to it below are marked "draft"), plus the checked-in documents cited inline. Every count was produced on this checkout; the commands are in Appendix A.

## Summary for the decision

- "Legacy web" is the original three.js browser game, `public/index.html` (1,043,346 bytes, 11,329 lines), served by the game server at `/` (`server.js:43-51,122-126`, `Dockerfile:6`), plus the content pipeline that exports `shared/*.json` from it, the parity gates that keep the Godot port bit-identical to it, and the web-only i18n/content/test tooling around it.
- Measured tax: **34 references to `tuning_active()` in production GDScript** (21 on executable lines; 22 more in tests, 56 in total), 4 `zones_active()` sites, **5 JS-reference slicers (1,320 lines)** and **10 Godot test runners that read the web source**, 6 web-only test suites, 8 exported content tables and 34 exported maps, 33 rendered SFX/4 music tracks/36 baked decor files, 902 web-only translations, and 28 pre-existing docs that mention the web game (29 with this audit).
- The replacement already exists and is advertised: the **Godot Web export** (`README.md:107`), a PWA built by the CI job `export-smoke` (`ci.yml:155-187`) and manually published to `gh-pages` (currently 0.4.0). Retirement of the legacy client is not a decision to drop web players; they can be redirected to the Godot web build.
- **Recommendation: option B — freeze the legacy client now, migrate the entry point to the Godot web build as `docs/ROADMAP.md:141` already plans, and retire `/classic` in v0.6 (`docs/ROADMAP.md:151`). Do not keep as-is (C).** Option A (delete now) is acceptable only if the owner wants it in one release; the fixture/content decoupling PRs in §5 are prerequisites either way.
- **Biggest risk: the size of the existing web audience is UNVERIFIED.** The legacy page has no analytics (0 matches for "analytics" in `public/index.html`), the server keeps no page counters, and publishing is manual — so a redirect must be announced, and the Godot web build is ~54 MB on first load (`README.md:107`) against ~2.3 MB of legacy assets plus a CDN three.js.

---

## 1. What exactly is "legacy web support"?

### 1.1 The client

- `public/index.html` — one 11,329-line file (CSS, DOM, one module script). three.js 0.160.0 is loaded from jsDelivr (`public/index.html:1446-1447`) and PeerJS 1.5.4 from CDN fallbacks (`:9202`). The network build marker is `NET_BUILD = 'b77.0'` (`:9193`).
- `public/i18n.js` (132 lines), generated `public/i18n-data.js` (571,694 bytes) and `public/fonts/NotoSans{TC,SC,JP}-Subset.woff2` (3 files, 681,904 bytes total); the web page uses `window.I18N_DATA` (`tools/i18n.js:67`).
- `web-i18n/src/*.json` — 9 files, 6,185 lines, **902 web-only strings** (`npm test` reports "1420 godot + 902 web-only strings x 5 languages").
- Served by the Node game server: `server.js:3-8` (purpose), `:22-23` (`PUBLIC_DIR = public/`), `:43-51` (find `index.html`), `:52-78` (static, brotli/gzip cache, 304), `:122-126` (route). `Dockerfile:6` copies `public/`; `render.yaml:1-8` runs `npm start`; `deploy/nas/docker-compose.yml` builds the same image; `docs/SERVER_PLAN.md:11` documents "Static web game from `public/`".
- Production origin: release builds point at `wss://homeserver.tailcc5a5.ts.net/ws` (`godot/data/extra/server.json`), and the NAS/Tailscale runbook serves the game page from that same origin (`docs/SERVER_PLAN.md:11,51`). That the live page is the legacy client is an inference from those files — **UNVERIFIED** by an actual request.
- A stale second copy is tracked at the repo root: `index.html`, 770,563 bytes, 8,794 lines, `NET_BUILD = 'b66.4'` (`index.html:7239`), last touched 2026-11-13; the canonical `public/index.html` was last touched 2026-11-16. No tool, server or test reads the root copy (all tooling reads `public/index.html`); only `README.md:159` lists it. It is dead duplicate weight.
- The README already frames it as superseded: "The original JavaScript web game (served by `npm start`). The Godot web export above replaces it for players" (`README.md:159`; Web link at `:107`).

### 1.2 The content pipeline (web → shared → godot)

- `tools/export-content.js:3-5,13` slices tables out of `public/index.html` and writes **8 tables**: `weapons.json`, `drops.json`, `modes.json`, `difficulties.json`, `crate-rates.json`, `classes.json`, `cosmetics.json`, `maps.json` (`:57-70` builds the output object, `:69` adds the map table). Maps come from `tools/export-maps.js:2-10`, which runs the web map builders; `shared/maps.json` holds **34 maps**.
- `shared/README.md:3,11` states `shared/*.json` is "exported from `public/index.html`" and "Do not edit the exported files by hand"; `:9` names `damage.json` as the only hand-written shared file.
- `tools/sync-shared.js` copies the **9** shared JSON files into `godot/data/` (an exported app cannot read `../shared`); its `--check` is one of the six steps of `npm test` (`package.json:77`).
- Consequence: the web client is the source of truth for weapons, modes, maps, classes, cosmetics, drops, difficulties and crate rates.

### 1.3 Combat parity gating (`tuning_active`, `zones_active`, `net_zones`)

- `Combat.tuning_active()` (`godot/logic/combat.gd:203-204`) is "tuning overlay loaded **and** zones rule active": `return not tuned_weapons.is_empty() and zones_active()`.
- `Combat.zones_active()` (`combat.gd:239-240`): `return damage_rule != "classic" and (not net_started or net_zones)`.
- `Combat.net_zones` is declared at `combat.gd:50` and read only at `:240`. **No production code sets it**; the only assignments are in tests (`godot/tests/damage_test.gd:120`; `godot/tests/skills_test.gd:120,187,190,855,861`). Online matches therefore run the web "classic" numbers by default.
- The reason is documented: web clients compute their own shots with the classic rule, so the shooter's damage would desync if the Godot side used per-body-part zones (`docs/DAMAGE.md:44-46`); the balance overlay is "Godot only, and parity-neutral... used only while `Combat.tuning_active()`" (`docs/DAMAGE.md:62`). Code comments repeat this at `combat.gd:75,345-346,843,1026,1161`, `skills.gd:13-14,154-156`, `weapons.gd:327`.
- **34 textual references in production `.gd` files**, spread over 7 files, 21 of them on executable lines (table in §2.2). The remaining 22 are in Godot tests, for **56 total**.

### 1.4 Cross-play gating in the Godot host

- `HostSession.web_guests()` (`godot/net/host_session.gd:202-206`) treats any roster member without the `gd` marker as a web guest.
- `HostSession.app_only(m)` (`host_session.gd:179-180`) returns `NetMatch.GODOT_MODES.has(m)`; `NetMatch.GODOT_MODES` (`godot/net/net_match.gd:23`) is **10 ids**: `tdm`, `deathmatch`, `sudden`, `chaos`, `lowg`, `duel`, `t2`, `t3`, `t4`, `construction`.
- Behavioural consequences: the room's picked mode silently falls back to Classic when a web guest is present (`host_session.gd:213`); a web guest is refused a running app-only match (`:476`) and blocked from the pick (`:506`); start is gated (`:720`). UI labels: `main.gd:1275` (`(app)`), `:1278` (app-only explanation), `:1439` (`(web)` in the roster).
- Wire marker: Godot clients send `gd` (`godot/scripts/net_client.gd:74`), the host stamps it (`host_session.gd:98,323,467-470`); the protocol tables explain it (`docs/PROTOCOL.md:410,431-432,450`).
- App-only *offline* modes are 7 in `godot/data/extra/modes.json` (tdm, deathmatch, sudden, chaos, ctf, lowg, practice), merged by `ModeRules.merge_extra`; `ModeRules.PLAYABLE` lists 20 offline modes (`godot/logic/mode_rules.gd:37-38`), plus Construction. Only 8 modes are currently web-compatible online (`docs/CROSSPLAY_TEST.md:97-103`).

### 1.5 Godot-only data and assets that are **generated from the web game**

This is the deepest dependency and it is not in the revised-plan bullet:

- `godot/data/extra/` holds **50 files**: 14 JSON (4 of them the Construction pack) and 36 decor `.bin` files. Generated from the web client: `locker.json` ("Generated from `public/index.html`", `godot/data/extra/locker.json:2`), `godot/data/extra/decor/*.bin` plus `map_look.json` (`tools/export-map-decor.js:2-14`, bakes the web three.js levels in Chromium), `godot/audio/sfx/*.wav` — **33 files** — (`tools/render-sfx.js:2-4`, renders the web WebAudio engine) and `godot/audio/music/*.ogg` — **4 tracks** — (`tools/render-music.js:2-4`, renders the web procedural music).
- Hand-authored Godot-only data: `extra/modes.json`, `extra/classes.json`, `weapon_tuning.json`, `news.json`, `server.json`, `remote_config.json`, `wizard.json`, `destructible.json`, `extra/construction/*`.
- Retiring the web client means the committed assets keep working but **cannot be regenerated**. That is the "content must be re-pointed first" item in `docs/IMPROVEMENT_PLAN.md:232`.

### 1.6 Server-side web assumptions

- Static game page serving is the only web-specific part of the server (`server.js:43-78,122-126`). The MIME table (`server.js:44`) has no `.wasm`/`.pck` entries and the server sends no COOP/COEP headers (0 matches), so the Godot Web export is **not** server-hosted today even though `docs/ROADMAP.md:141` plans exactly that.
- There is no build-number gate: `server.js:196` relies on the host comparing `proto` in `hello`. Any stale client (including a frozen legacy tab) can still connect until the protocol/host refuses it.
- Analytics: `docs/ANALYTICS.md:25` lists `web` as a platform, but that is the **Godot** client's `plat` field. The legacy page contains no analytics code (0 matches for "analytics" in `public/index.html`) and the server stores no page/hit counters. The analytics switch is also off by default (`remote-config.json:18`, `docs/ANALYTICS.md:11`). **The legacy web audience size is therefore UNVERIFIED.**
- The accounts REST API (`accounts.js`) is shared by app and legacy web (login, cloud save, leaderboard; `docs/CROSSPLAY_TEST.md:49-53`) — it is not web-only.

### 1.7 The replacement (do not delete it with the legacy client)

- **Godot Web export**: preset `Web` in `godot/export_presets.cfg:65-99` (output `build/web/index.html` `:74`, `variant/thread_support=false` `:88`, PWA enabled `:97-99`). CI job `export-smoke` installs the web export templates and builds it on every PR/push (`ci.yml:155-187`, export step `:182-185`). It is advertised as the Web build (`README.md:107`) and published on the `gh-pages` branch.
- `gh-pages` currently carries "Publish Godot web build 0.4.0" commits (latest example `f8fe21d`, 16 November 2026), i.e. it lags `main` (0.5.0). `.github/workflows/` contains only `ci.yml` and no script references `gh-pages` or `kaydeross.github.io` — **how the branch is produced and refreshed is UNVERIFIED**.
- Godot Web players are ordinary Godot clients (they send `gd`), so they keep working after the legacy client is deleted. "Dropping web" in this audit means dropping the legacy client, not the Godot web channel.

---

## 2. Inventory and measurements

### 2.1 Claims checked against the repository

| Claim | Measured state |
|---|---|
| Revised-plan draft: "~34 `tuning_active()` branches" | **34 textual references in production GDScript** across 7 files (21 on executable lines, 13 in comments), plus 22 in Godot tests = 56 total (38 non-comment). Accurate as a reference count; not all 34 are branches. |
| Revised-plan draft: parity suites "need Godot at `/Applications/Godot_4.8-beta4.app` (not CI-portable)" | The macOS path is only each runner's default (`const GODOT = process.env.GODOT \|\| '/Applications/Godot_4.8-beta4.app/...'`, e.g. `tools/test-combat.js:8`). CI sets `GODOT=/opt/godot/godot` (`ci.yml:27-28`) and runs **54** `test:*` suites on Linux. The suites that are genuinely not CI-portable are the **6 web-only suites** (5 need Playwright and the three.js CDN; `test:dynamics` only slices the JS). |
| Brief: "`tools/test-crossplay-web.js`" | The file is **`tools/crossplay-web.js`** (58 lines); npm script `test:crossplay-web` (`package.json:38`). |
| Brief: "gh-pages publishing" as part of the legacy channel | `gh-pages` publishes the **Godot web build 0.4.0**, not the legacy three.js page (`README.md:107`, branch history). It survives retirement. |
| Brief: "export-smoke Web preset" as legacy-only | It is the **Godot** Web export job (`ci.yml:182-185`); keep it. |
| "5-language i18n" | English source + 5 translated languages (`zh_TW`, `zh_CN`, `ja`, `fr`, `es`; `tools/i18n.js:25`), i.e. 5 translations for every string. |
| `npm test` is the docs gate | Yes: 6 chained steps (`package.json:77`); 2 of them depend on legacy web artefacts (`export-content --check` reads `public/index.html`; `i18n --check` validates generated `public/i18n-data.js` and the shared CJK subset coverage). |

### 2.2 Gate counts by file

`tuning_active` production references (all textual; executable in brackets):

| File | Refs | Executable |
|---|---|---|
| `godot/logic/combat.gd` | 19 | 12 |
| `godot/logic/weapons.gd` | 4 | 3 |
| `godot/logic/skills.gd` | 3 | 1 |
| `godot/logic/player_control.gd` | 3 | 2 |
| `godot/logic/match_sim.gd` | 2 | 2 |
| `godot/logic/fighter_state.gd` | 2 | 0 |
| `godot/logic/pickups.gd` | 1 | 1 |
| **Production total** | **34** | **21** |
| `godot/tests/skills_test.gd` | 17 | 14 |
| `godot/tests/arcade_test.gd` | 4 | 2 |
| `godot/tests/gunfeel_test.gd` | 1 | 1 |
| **Test total** | **22** | **17** |
| **Grand total** | **56** | **38** |

- Key gate sites: `combat.gd:203-204` (definition), `:168` and `:204` (zones), `:346` (flame), `:481` (statuses), `:596` (hit spheres), `:650` (spatula), `:829` (parry window), `:846` (parry), `:884` (carry), `:1044` (hazards), `:1180` (heavy), `:1367,1374` (melee deflect); `weapons.gd:204,454,677`; `skills.gd:248`; `player_control.gd:135,140`; `pickups.gd:64`; `match_sim.gd:306`.
- `zones_active`: 9 references — `combat.gd:168,204,239,245` (production), `match_sim.gd:67`, `damage_test.gd:115,117,119,121`.
- `net_zones`: 2 code references (`combat.gd:50,240`), 6 test assignments, **no production assignment**.
- Web-guest gating: 6 code sites in `host_session.gd` (`:179-180`, `:202-206`, `:213`, `:476`, `:506`, `:720`), 3 UI labels in `main.gd` (`:1275,1278,1439`), 1 mode set in `net_match.gd:23`.

### 2.3 Parity suites

- **5 reference slicers, 1,320 lines**: `tools/bots-reference.js` (226), `tools/combat-reference.js` (764), `tools/modes-reference.js` (186), `tools/net-interp-reference.js` (36), `tools/physics-reference.js` (108). They slice the real JS out of `public/index.html`.
- **10 Godot test runners read the web source directly or through a slicer**, and all 10 run in CI: `test:godot-physics`, `test:godot-spring`, `test:godot-combat`, `test:godot-modes`, `test:godot-bots`, `test:godot-netguest`, `test:godot-dynamics`, `test:godot-sandbox`, `test:godot-maps` and `test:godot-range`. Six of them go through the slicers; four slice blocks directly (e.g. `MAPS.custom` in `tools/test-godot-maps.js:14`). Several other Godot runners (`test:godot`, `test:godot-flow`, `test:godot-host`) also use `tools/wa-client.js`, a pure Node protocol client — that fixture survives retirement (renamed "protocol guest") and is not a web-source dependency.
- **6 web-only npm suites are not in CI**: `test:browser` (`tools/test-browser.js`, 44 lines), `test:sound` (85), `test:dynamics` (86), `test:dyn` (108), `test:touch` (65), `test:crossplay-web` (58). Five of the six drive the page in Playwright; `test:dynamics` only slices the JS.
- Coverage: of the **63** `test:*` scripts, **54 run in CI**; the 9 that do not are the 6 web ones above plus `test:godot-ctf`, `test:godot-gfx`, `test:godot-analytics` (unrelated coverage gaps, noted for honesty).
- **No CI job touches the legacy client.** All browser/web suites are local-only, and `npm test` only reads web *files*, never runs the game.
- Why the browser suites are not CI-portable as written: they need `npx playwright install chromium` (not in `ci.yml`), boot the full 11k-line page in Chromium, and load three.js 0.160.0 from jsDelivr (`public/index.html:1447`); the cross-play suite also needs network for the CDN (`tools/crossplay-web.js:1-13`; comments at the top of each runner, e.g. `tools/test-browser.js:1-4`, `tools/test-sound.js:2-5`, `tools/test-touch.js:2-5`).
- The Godot parity suites, by contrast, need only the Godot binary. CI installs 4.7.2 (`ci.yml:28,37-43`) and runs them in 4 shards: "the whole suite is ~19 min sequential; the longest shard is ~5-6 min" (`ci.yml:21-22`). This is the real automated cost of the legacy reference, and it stays until the JS references are snapshotted (PR 2 in §5).

### 2.4 Tests and build steps that exist only for the web channel

| Step | Where | Notes |
|---|---|---|
| Content export (8 tables + 34-map geometry) | `tools/export-content.js`, `tools/export-maps.js`; `npm run content` (`package.json:9`), `export-content --check` in `npm test` (`package.json:77`) | Web is the upstream source of truth. |
| Web i18n output | `tools/i18n.js:3-9,137-160` writes `public/i18n-data.js`; `--web` scan; 902 web-only strings in `web-i18n/src` (9 files) | `npm run i18n`, and `i18n --check` in `npm test`. |
| Web fonts | `tools/subset-fonts.py:1-13` writes `godot/ui/fonts/*.otf`, `public/fonts/*.woff2`, `tools/cjk-coverage.json`; coverage 1,358 / 1,353 / 971 characters for zh_TW / zh_CN / ja | Needs an external Noto Sans CJK directory; rerun when a translation adds characters (`docs/I18N.md:33-40`). |
| Audio assets | `npm run sfx` (`render-sfx.js:2-4`, 33 WAVs), `npm run music` (`render-music.js:2-4`, 4 OGGs) | Rendered from the web engine into `godot/audio/`. |
| Map decor bake | `npm run map-decor` (`export-map-decor.js:2-14`, 36 `.bin` + `map_look.json`) | Runs the web three.js levels in Chromium. |
| Screenshots | `npm run shots` (`shoot-maps.js`), `tools/shoot-scenes.js` | Legacy page screenshots; README screenshots now come from `shoot-godot-*.sh` (`README.md:165`). |
| Cross-play scripts | `tools/crossplay-web.js`, `tools/wa-client.js` (protocol guest, `BUILD = 'b77.0'` at `:4`), `docs/CROSSPLAY_TEST.md` | `wa-client` is also the protocol fixture for the Godot net tests, so it should be kept/renamed, not deleted. |
| Browser/feature suites | `test-browser`, `test-sound`, `test-dynamics`, `test-dyn`, `test-touch` | Local only; no CI coverage of the legacy client at all. |
| CI `export-smoke` | `ci.yml:155-187` | **Godot** Web export, not legacy — keep. |
| `gh-pages` publish | branch history, README:107 | **Godot** Web build 0.4.0, manual/undocumented in the repo — keep, but refresh/automate. |

Playwright is a devDependency (`package.json:92-93`, `^1.65.0`) and is required by **10 tools scripts**: the 5 web test suites (including cross-play) and the 5 asset/screenshot generators.

### 2.5 What would break if the legacy channel were dropped

1. `npm test` fails at step 2 (`export-content --check`) until PR 3 lands, and at step 4 (`i18n --check`) until PR 4 lands.
2. 5 slicers + 10 parity runners stop working (they read `public/index.html`): 1,320 lines of slicers plus the runners around them. They must be converted to committed fixtures first (PR 2).
3. 6 web-only npm scripts become dead code; `docs/CROSSPLAY_TEST.md` must be rewritten/deleted (its real-browser section is the only cross-play automation over the legacy channel).
4. The content regeneration path disappears: new weapons/modes/maps cannot be exported; `shared/` must become hand-maintained or generated from Godot data; editing the 34 maps becomes manual unless a new pipeline is built.
5. Godot asset regeneration disappears: 36 decor bakes + `map_look.json`, 33 SFX + 4 music tracks, the locker copy. Existing committed artefacts are fine; regeneration is blocked (an accepted cost under B; the plan already calls this "L", `docs/IMPROVEMENT_PLAN.md:232`).
6. Web i18n output disappears (902 web-only strings, 9 source files, 3 woff2 fonts, 571 KB generated data). The Godot catalogue and Godot CJK subsets are unaffected.
7. Server/deploy changes: `/` no longer serves a game (needs a redirect/notice), `Dockerfile:6` and `render.yaml`/NAS image shrink, `docs/SERVER_PLAN.md:11`, `README.md:159` and 28 docs that mention the web game need sweeps.
8. Online simplification becomes possible: legacy web guests go away, so the `web_guests`/`app_only` fallbacks and `GODOT_MODES` online gating can be removed, and `net_zones` can become the default ("S once web guests are gone", `docs/IMPROVEMENT_PLAN.md:130`; `docs/DAMAGE.md:45`).
9. Player access breaks at the game-server origin unless redirected; the announced replacement is the Godot web build (`README.md:107`) or the app (TestFlight link `README.md:9`; other platforms build from source today).
10. **Not** broken: accounts/REST, the room relay, the Godot test suites, CI `export-smoke`, `gh-pages`, and Godot Web players (they are `gd` clients).

---

## 3. Cost and benefit

### 3.1 The per-WP tax today

The rules every work package must follow are documented in `docs/REVISED_PLAN.md` standing rules 1-4 (draft), `docs/IMPROVEMENT_PLAN.md:133` and `docs/ROADMAP.md:176`. Concretely:

- **Parity gating.** New Godot-only mechanics must sit behind `Combat.tuning_active()` so the JS parity tests keep passing "until the three.js game is retired" (`docs/IMPROVEMENT_PLAN.md:133`; `docs/GODOT_ARCH.md:5-6` calls the web game "the spec"). That is where the 34 production references and 22 test references come from; each new mechanic adds another gate plus a "web numbers unchanged" test path (examples: charge/parry/skills/statuses comments at `combat.gd:465,829,846,884,1044,1180`, `weapons.gd:327`, `skills.gd:13-14,154-156`).
- **Content regeneration.** No hand edits to `shared/*.json` or `godot/data/*.json`; table changes start in `public/index.html` and run `npm run content`, and `npm test` fails otherwise (`shared/README.md:11`, `package.json:77`). Every WP touching weapons/modes/maps/classes/cosmetics/drops pays this, including the map-geometry export for 34 maps.
- **Five-language i18n plus CJK subsets.** Every new string needs 5 translations in `godot/i18n/src` (1,420 keys today) and, if web-only, in `web-i18n/src` (902 keys); a new Han/kana character means rerunning `tools/subset-fonts.py` with an external Noto directory and committing new fonts (`docs/I18N.md:33-40`). A concrete example from the plan draft: any web-UI copy change must be made in `public/index.html`/`web-i18n/src` and then needs `npm run content` (when it touches a content table), `node tools/i18n.js` and `test:crossplay-web`; the 4-digit-code copy in the draft's WP L2 has since landed (`public/index.html:1292` now reads `maxlength="4"`), which shows the drift this pipeline creates.
- **Parity suite gate.** The local gate is `npm test` plus each WP's `test:godot-*` suites (`docs/ROADMAP.md:176`); `npm test` itself includes 2 web-dependent checks, and the parity suites compare against the live JS rather than frozen fixtures.
- **Cross-play verification.** Mixed web/Godot rooms cannot be fully automated: the automated browser host needs Playwright + a CDN (`docs/CROSSPLAY_TEST.md:126-128`), and the manual phone-to-browser check is an open item in the roadmap status table (`docs/ROADMAP.md:16`, `docs/CROSSPLAY_TEST.md:55`).
- **Mode/UI classification.** Every new mode must be classified as app-only or web-compatible (`net_match.gd:23`; fallbacks in `host_session.gd:213,476,506,720`), and "same rules online and offline" is explicitly blocked on web guests being gone (`docs/IMPROVEMENT_PLAN.md:130`).
- **Documentation drift.** 28 of the 37 pre-existing docs mention the web game/three.js; `CODEMAP.md:6,218`, `CROSSPLAY_TEST.md`, `GODOT_ARCH.md:5-6`, `PROTOCOL.md`, `DAMAGE.md`, `I18N.md` are the core ones.

### 3.2 What retirement removes (measured)

- 34 production `tuning_active()` references (21 executable) + 22 test references; 4 `zones_active()` production references; 2 `net_zones` code references (the flag becomes unnecessary).
- 5 slicers (1,320 lines) + 10 Godot test runners that depend on the web source; 6 web-only npm scripts/suites (446 lines of runners, 474 including `wa-client`, which is kept as a protocol fixture).
- 902 web-only translations + 9 `web-i18n/src` files (6,185 lines) + 3 web woff2 fonts (681,904 bytes) + `public/i18n.js` (5,899 bytes) + generated `public/i18n-data.js` (571,694 bytes).
- 8 exported content tables and 34-map geometry export; 3 asset bakers (33 SFX, 4 music tracks, 36 decor bakes + `map_look.json`, plus the generated `locker.json`).
- The legacy client itself: 1,043,346 bytes in `public/index.html` (11,329 lines) and the stale root `index.html` (770,563 bytes); the `public/` directory totals ~2.3 MB before CDN three.js.
- Server: the static-page block (`server.js:43-78,122-126`), the `Dockerfile:6` copy, one documented deployment line, and the risk of stale browser tabs.
- **CI time saved is small** (no CI job runs the legacy client; only 2 of 6 `npm test` steps disappear). The real saving is per WP: no parity gate, no web content export, no web-only i18n, no manual cross-play check, and the "same rules online and offline" work unblocks.
- `docs/IMPROVEMENT_PLAN.md:232` sizes the whole retirement as **L**; the decomposition in §5 is consistent with that (weeks, not days).

### 3.3 What retirement does NOT remove

- The Godot Web export, its CI `export-smoke` job and the `gh-pages` channel — that is the replacement, and web *players* are redirected to it.
- Godot's own 5-language i18n, CJK font subsets (`godot/ui/fonts`) and the `cjk-coverage.json` check.
- `shared/ → godot/data/` sync (an exported app cannot read `../shared`); it remains needed unless the source moves to `godot/data`.
- The room relay, accounts REST, events endpoint, remote config, and every Godot-only feature that is not parity-gated.

---

## 4. Options and recommendation

| Option | What it means | Tax removed | Player risk | Prerequisites |
|---|---|---|---|---|
| **A — retire now** | Stop serving `public/index.html`; delete the client, generators, web tests and i18n; redirect `/` | All of §3.2 in one release | Highest: unknown audience, no analytics, 54 MB replacement | Content/fixtures/source-of-truth PRs (2-4 in §5) must land first; so "now" is really "next release after those" |
| **B — freeze (recommended)** | Declare `public/index.html` frozen at b77.0: still served, **no new parity work, no web content/i18n updates**; Godot data becomes the source of truth and new content goes to `godot/data/extra`; content pipeline stays generated until the retirement PR | The parity gate and content/i18n rules immediately; code deletion later | Low: page keeps working during the announcement window | Freeze declaration + fixture snapshot (PRs 2-3); retirement target agreed with the owner |
| **C — keep as-is** | Continue parity-gating and web content/i18n/cross-play work | None | None | Contradicts `ROADMAP.md:53,151` and the revised-plan intent |

**Recommendation: B.** Reasons, in order of evidence weight:

1. The replacement is already live and advertised (`README.md:107`, CI `export-smoke`), and the roadmap already schedules the same migration: Godot web at `/`, three.js at `/classic` (`docs/ROADMAP.md:141`), and "Retire `/classic`" after soft launch (`docs/ROADMAP.md:151`). B is the no-new-commitment way to start that clock; C contradicts the owner's own plan.
2. Freezing stops the per-WP tax immediately without any player-visible break; deletion (A) can follow the same PR sequence once fixtures and content ownership are moved.
3. A hard A today is not data-driven: the legacy audience is UNVERIFIED (no analytics, no server counters). For a live product, that argues for an announced window, not a silent cut.
4. The prerequisite work for A (fixtures, content source flip, i18n decoupling) is required under B too, so recommending B costs no extra work.
5. The concrete freeze/retire triggers are checkable: Godot web build refreshed to the current release and served at `/`, then one release window, then delete `/classic` in v0.6.

### 4.1 Retirement/redirect plan for existing web players

1. **Announce first.** Put a notice on the legacy page and in release notes: "The browser version is moving to the new engine. Play the app (TestFlight) or the new browser build at <URL>. Accounts and rooms keep working. This old page closes on <date>." Keep the page playable during the window.
2. **Migrate the entry point**, following `docs/ROADMAP.md:141`: serve the Godot Web export at `/` and move the legacy client to `/classic`. This needs the current Godot web build (currently 0.4.0 on `gh-pages`) refreshed to 0.5.0, and the game server (or GitHub Pages) hosting it. If served by `server.js`, add `.wasm`/`.pck` MIME types (`server.js:44` currently lacks them) and decide on COOP/COEP: the preset is single-thread (`export_presets.cfg:88`), so cross-origin isolation should not be required, but the PWA export setting (`:97-99`) must be verified — **UNVERIFIED** until a build is hosted and tested.
3. **Measure the migration.** Enable the Godot analytics switch (`remote-config.json:18` currently `false`; `docs/ANALYTICS.md:11-25`) before/at the redirect so `plat: "web"` sessions are visible; the legacy page itself cannot report anything (no analytics code, 0 matches). If a before/after count is required, add a minimal server-side hit counter on `/classic` — none exists today.
4. **Retire `/classic`.** Delete the files (§5 PR 7) and leave a permanent, small redirect/notice page with links to the app stores/TestFlight and the Godot web build. Keep that redirect for at least one release cycle to catch external links and bookmarks. No 301 is assumed: the owner should choose between 302/notice and a plain 301 after the window (**owner decision D2**).
5. **Do not delete `gh-pages`.** It is the Godot web channel; refresh it and decide whether GitHub Pages stays the web home or the game server serves `build/web/` (roadmap says server, `:141`).

### 4.2 Required owner decisions

- **D1 — Exposure:** confirm there is no known legacy-web player commitment (or accept the unknown); the repo cannot answer it.
- **D2 — Freeze and date:** approve option B, the announcement/redirect window, and the v0.6 deletion target (or choose A explicitly).
- **D3 — Web destination:** Godot web build on `gh-pages` vs served by `server.js` at `/`; who refreshes it from 0.4.0 to 0.5.0 and how (the publish process is undocumented today).
- **D4 — Content ownership:** approve flipping the source of truth to `shared/`/`godot/data/extra`, and accept that map-geometry, audio and decor generation from the web engine will stop (new pipeline or hand maintenance is a separate decision).
- **D5 — Deletions:** approve deleting `public/index.html`, `public/{i18n.js,i18n-data.js,fonts,placeholder.txt}`, `web-i18n/`, the stale root `index.html`, the 5 slicers, the 6 web test suites and the browser/asset scripts that become dead — plus the docs sweep.
- **D6 — Analytics/comms and stale clients:** approve enabling analytics for web sessions and the stale-client policy (server has no build gate today, `server.js:196`; a `proto` bump or a server-side refusal for non-`gd` `hello` after the cutoff needs an explicit choice).

---

## 5. Staged implementation plan (small PRs)

Ordering: **PR 2 → PR 3 → PR 4 → PR 6 → PR 7 → PR 8**; PR 5 can follow PR 2/4; PR 9 is housekeeping. Each PR must keep `npm test` green and run its listed `test:godot-*` suites; the owner runs the gates per the process rule (`docs/REVISED_PLAN.md` standing rule 4, draft).

| PR | Change | Tests/CI | Risk and notes |
|---|---|---|---|
| **PR 1** (this) | Add this audit; no code | `npm test` (docs-only) | None; decision input only |
| **PR 2** | Snapshot the web reference: commit fixtures for the 5 slicers (physics/combat/modes/bots/net-interp traces) and re-point the 10 runners at them instead of `public/index.html` | All 10 parity suites via CI; `npm test` | Fixture drift must be zero: generate once from b77.0, keep tolerances, change no semantics. This is the prerequisite for deleting `public/` |
| **PR 3** | Flip content source of truth: `shared/*.json` (and `godot/data/extra/`) authoritative; drop `export-content.js`/`export-maps.js` from `npm test` (`package.json:77`); keep `sync-shared --check`; update `shared/README.md`; freeze the generators | `npm test` (steps 2 removed), `test:godot-maps` | 34-map geometry and table edits become manual; content authors must be told. No runtime change |
| **PR 4** | Decouple web i18n/fonts: stop writing `public/i18n-data.js` and `public/fonts/*.woff2` (`tools/i18n.js:137-160`, `tools/subset-fonts.py`); keep Godot strings + `cjk-coverage.json` check; delete `web-i18n/src` when the page is retired | `npm test` (`i18n --check`), Godot UI tests | Do not delete the committed web copies during the freeze window; only stop regenerating them |
| **PR 5** | Delete the 6 web-only suites (`test:browser`, `test:sound`, `test:dynamics`, `test:dyn`, `test:touch`, `test:crossplay-web`) and convert `docs/CROSSPLAY_TEST.md` to a protocol-guest doc; keep `tools/wa-client.js` as the protocol fixture (rename its "web" comments) | CI unchanged (6 checks); verify every npm script still resolves | Loses the only browser smoke coverage of the legacy page; acceptable because CI never ran it. If desired, replace with one Playwright smoke of the Godot web build later |
| **PR 6** | Migrate the entry point per `docs/ROADMAP.md:141`: publish the current Godot web build, serve it at `/`, move the legacy page to `/classic`; add MIME/headers as needed; refresh `gh-pages` 0.4.0 → current; document/automate publishing | CI `export-smoke` (already builds it); manual browser check | 54 MB first load, PWA/header behaviour, server bandwidth; rollback = keep both routes. Note: the publish process is undocumented today |
| **PR 7** | Retire `/classic`: add the redirect/notice page; delete `public/index.html`, `public/i18n.js`, `public/i18n-data.js`, `public/fonts/`, `public/placeholder.txt`, `web-i18n/`, stale root `index.html`, the 5 slicers and dead generators; remove static game serving from `server.js`, `Dockerfile:6`; sweep README/SERVER_PLAN/CODEMAP/PROTOCOL and the 28 web-mentioning docs | `npm test`, CI 6 checks | Stale tabs/old links: server has no build gate (`server.js:196`) — add a `proto` bump or refusal for non-`gd` `hello` (D6). Keep the redirect for one release |
| **PR 8** | Net/mode simplification once web guests cannot exist: remove `web_guests()`/`app_only()` fallbacks and `GODOT_MODES` online gating (`host_session.gd:179-213,476,506,720`; `main.gd` labels); make `net_zones` the default online rule (`combat.gd:50,240`; `docs/DAMAGE.md:45`; `docs/IMPROVEMENT_PLAN.md:130`); simplify `net_modes_host`/`net_host` expectations (web-guest refusal tests become "legacy guest refused" or are deleted) | `test:godot-host`, `test:godot-netguest`, net-modes tests, `test:godot-damage`, `test:godot-skills` | Wire semantics change: old app builds may still connect; needs the D6 stale-client gate first. This is the PR that pays back the parity tax |
| **PR 9** | Housekeeping: enable analytics (`remote-config.json`, owner), verify `plat: "web"` events, refresh `gh-pages`, update ROADMAP status, cross-link this audit | Docs only | No historical baseline exists; metrics start at migration |

**CI changes:** the 6 checks stay (the legacy client has none to remove; `export-smoke` must stay). `npm test` loses 2 of its 6 steps in PR 3/4. The 54 Godot suites keep running, but after PR 2 they read committed fixtures instead of the live JS file; no CI job is added or removed. Add a `gh-pages` publish workflow only if the owner chooses automation (D3).

**gh-pages implications:** do not delete the branch; refresh it from 0.4.0 to the current build (PR 6); decide whether it remains the web home or the server serves `build/web/` (PR 6/D3).

**Analytics implications:** the legacy page must be measured by redirection/announcement, not instrumentation; the Godot client already tags `plat: "web"` (`docs/ANALYTICS.md:25`) but the switch is off (`remote-config.json:18`). Enabling it before/at migration is the only way to see uptake.

---

## 6. Non-goals and unknowns

**Non-goals of this PR**

- No code, asset or config changes — documentation only.
- Not a decision to drop the **Godot** web channel; the Godot Web export is the replacement and is assumed to stay.
- Does not delete any file, script, test or branch; the deletions are staged in §5 and require owner approval.
- Does not port the asset-generation pipelines (audio renders, decor bake, map export) to Godot; that cost is accepted under B unless separately funded.
- Does not change balancing, gameplay, the server protocol, accounts, remote config or i18n content.
- Does not commit to dates; the target release is the owner's decision (D2).
- No measurements of the live audience are possible from the repo.

**Unknowns**

| Question | Status |
|---|---|
| How many players use the legacy page? | **UNVERIFIED** — no analytics in `public/index.html` (0 matches), no server page counters, and the revision plan/roadmap record no figure |
| Is the production page at `homeserver.tailcc5a5.ts.net` currently the legacy client? | Inferred from `godot/data/extra/server.json` + `docs/SERVER_PLAN.md:11`; not verified by a request |
| How is `gh-pages` produced and refreshed? | **UNVERIFIED** — no workflow or script in the repo references it; only the branch history and `README.md:107` |
| Do external links/SEO point at the legacy URL? | **UNVERIFIED** — outside the repo |
| Will the Godot web build work when hosted with the expected headers? | **UNVERIFIED** — export preset is single-thread and PWA-enabled (`export_presets.cfg:88,97-99`), but no hosted test was run in this audit |
| Is a 54 MB Godot web build an acceptable replacement on low-end browsers? | **UNVERIFIED** — no performance data; the legacy page is ~2.3 MB before CDN three.js |
| Does the stale root `index.html` have any consumer? | **UNVERIFIED** — no in-repo reference except the README table; last updated 2026-11-13 at b66.4 |
| Exact per-PR effort | Estimates only; the plan totals "L" (`docs/IMPROVEMENT_PLAN.md:232`) |
| Are any server API endpoints consumed only by legacy web? | **UNVERIFIED** — accounts/rank REST is documented as shared with the app (`docs/CROSSPLAY_TEST.md:49-53`); a per-endpoint audit was not done |
| How long do users keep stale tabs/old app builds after a cutoff? | **UNVERIFIED** — no telemetry; the server has no build-number gate (`server.js:196`) |

---

## Appendix A — reproducing the counts

All commands run from the repository root on the measurement commit. Only read-only commands; `npm test` is the project's own gate.

```bash
# 1. Gate (also prints the i18n counts)
npm test
#   -> translations ok: 1420 godot + 902 web-only strings x 5 languages
#   -> 0 errors, 18 warnings; server integration tests pass

# 2. tuning_active / zones_active references by file (textual and non-comment)
grep -rn "tuning_active" godot --include=*.gd | wc -l      # 56
grep -rn "zones_active"  godot --include=*.gd | wc -l      # 9
#   per-file totals are in §2.2; executable-line counts were produced by treating
#   lines whose first non-space characters are '#' as comments.

# 3. net_zones is never assigned in production code
grep -rn "net_zones" godot --include=*.gd | grep -v "/tests/"

# 4. Reference slicers and their line counts
ls tools/*-reference.js
wc -l tools/*-reference.js | tail -1                      # 1320

# 5. Which test runners read the web source or a slicer
grep -ln "public', 'index.html'\|public/index.html\|-reference\|wa-client" tools/test-*.js tools/crossplay-web.js

# 6. CI coverage
grep -c "npm run test:" .github/workflows/ci.yml          # 54
node -e "const p=require('./package.json');console.log(Object.keys(p.scripts).filter(k=>k.startsWith('test:')).length)"  # 63
#   54 in CI, 9 not: test:browser test:sound test:dynamics test:dyn test:touch
#   test:crossplay-web test:godot-ctf test:godot-gfx test:godot-analytics

# 7. Client and pipeline sizes
wc -c public/index.html index.html                        # 1043346 770563
wc -l public/index.html index.html                        # 11329 8794
grep -n "NET_BUILD" public/index.html index.html | head -4 # b77.0 / b66.4
ls public/fonts/*.woff2 | wc -l                           # 3
ls godot/audio/sfx/*.wav | wc -l                          # 33
ls godot/audio/music/*.ogg | wc -l                        # 4
ls godot/data/extra/decor/*.bin | wc -l                   # 36
find godot/data/extra -type f | wc -l                     # 50

# 8. gh-pages provenance (manual publish, Godot build)
git log --format='%h %ad %s' --date=short origin/gh-pages -5
ls .github/workflows/                                      # ci.yml only
```

For reference, the key code anchors used above: `server.js:43-78,122-126,196`; `Dockerfile:6`; `ci.yml:10-17,18-28,155-187`; `package.json:9,11,16-24,38,75,77,92-93`; `godot/net/host_session.gd:179-213,476,506,720`; `godot/net/net_match.gd:23`; `godot/logic/combat.gd:50,168,203-204,239-245`; `godot/logic/mode_rules.gd:37-44`; `docs/ROADMAP.md:16,53,141,151,176`; `docs/IMPROVEMENT_PLAN.md:130,133,232`; `docs/DAMAGE.md:44-46,62`; `docs/I18N.md:33-40,80-95`; `docs/CROSSPLAY_TEST.md:55,78-79,97-103,109,126-128`; `docs/SERVER_PLAN.md:11`; `shared/README.md:3,9,11`; `godot/export_presets.cfg:65-99`.
