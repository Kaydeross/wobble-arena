# Owner release runbook

Everything in this file needs **you**, the owner. An agent can prepare the code, run the
tests and draft the words, but it cannot sign with Apple, create accounts, pay for a host,
accept a legal agreement or press the button in App Store Connect. Each step is written so
you can tick it off and leave a date.

Written against `origin/main` at `08a89b2` (PR #148), release **0.5.0**. All paths are
relative to the repository root. The release flow lives in `godot/project.godot`,
`godot/export_presets.cfg`, `tools/build-ios.sh`, `tools/check-version.js` and
`godot/data/extra/news.json`; read those, not an older note, if the two disagree.

**Order matters.** Do the sections in this order:

1. Code gate → 2. Production server → 3. Privacy and legal → 4. iOS and TestFlight →
5. Analytics and metrics → 6. Track P (parallel, does not block).

Sections 2 and 3 gate the submission as well as the build: the app ships online, so the
server must be up for review, and the privacy page, privacy label, Terms and age rating must
be right before you submit. Analytics stays off until the policy says what it does. Track P
is a spike and can run alongside any of it.

## Current facts to work from

| Fact | Value |
|---|---|
| Release version | `0.5.0` (`godot/project.godot`) |
| 0.4.0 release tag | `v0.4.0` → `8962b9f` |
| 0.5.0 release tag | `v0.5.0` → `4c87268` |
| Current `main` tip | `08a89b2` (PR #148) |
| Commits after `v0.5.0` | two, docs only (`git diff --stat v0.5.0 origin/main`) |
| iOS bundle ID | `com.kedrosng.wobblearena` |
| Apple team ID | `663Q47AS93` |
| Last 0.4.0 build | `458`; the 0.5.0 TestFlight train starts at `1` |
| Shipped server | `wss://homeserver.tailcc5a5.ts.net/ws` (home NAS, Tailscale Funnel) |
| Privacy page | `https://kaydeross.github.io/wobble-arena/privacy.html` |
| Analytics switch | `analytics: false` in `remote-config.json` and `godot/data/extra/remote_config.json` |

The two tags above are already pushed. This runbook does **not** ask you to move or push
tags; verify them, then leave them alone.

---

## 1. Pre-release code gate

Do this before you touch a store record or a server. It proves the tree you are about to
ship is the tree that passed.

### 1.1 Verify the release tags

The tags are already on `origin`; fetching them is safe from any checkout because it does not
touch your working tree or branch. Verify, then leave them alone — do not move or re-push a
tag.

```bash
git fetch origin --tags
git rev-list -n1 v0.4.0   # expect 8962b9f9cdafe7213943410dc61032701e340517
git rev-list -n1 v0.5.0   # expect 4c87268b958b5c47a8fbe3e7a449a692a71bbe4b
git diff --stat v0.5.0 origin/main   # at the time of writing: four docs files only
```

- [ ] `v0.4.0` points at `8962b9f`
- [ ] `v0.5.0` points at `4c87268`
- [ ] Whatever is on `main` after `v0.5.0` is documentation only, or you know why the code
      differs and rebuild the gate below on that commit

### 1.2 Run the code gate on a clean checkout

Use a fresh worktree, never the main checkout: that one may hold your uncommitted `README.md`
edits, and a release build must come from the exact commit CI passed.

```bash
git fetch origin
git worktree add -b release/0.5.0-check ../wobble-arena-release-check origin/main
cd ../wobble-arena-release-check
npm install
npm test
```

`npm test` runs the version check, content sync, translation check, map check and the server
suite. It prints `server integration tests pass` at the end. The 18 "also in an earlier
file" translation warnings are pre-existing; only errors fail.

- [ ] `npm test` exits 0
- [ ] You kept the output (or a screenshot) with the date

`npm test` runs no Godot test. CI's four `godot` shards run the whole Godot suite on Linux
(see 1.3), so a green CI run on the shipping commit is the real Godot gate. To reproduce the
0.5.0 local Godot set on this Mac, Godot must be at `/Applications/Godot_4.8-beta4.app`; run each suite
once, never in parallel:

```bash
npm run test:godot-ui
npm run test:godot-title-fit
npm run test:godot-settings
npm run test:godot-world
npm run test:godot-modes
npm run test:godot-tutorial
npm run test:godot-flow
npm run test:godot-save
npm run test:godot-locker
npm run test:godot-quests
npm run test:godot-whats-new
```

- [ ] Every suite you ran passed, and you noted which ones on which machine

### 1.3 Confirm CI is 6/6 on `main`

The required result is **6 of 6** checks: `check`, `export-smoke`, and the four Godot shards
`godot (ui)`, `godot (sim)`, `godot (net)`, `godot (rest)`. All six PRs below are green at the
time of writing; re-check if `main` has moved.

| PR | What landed | Checks |
|---|---|---|
| [#143](https://github.com/Kaydeross/wobble-arena/pull/143) | Release hardening: dev unlock and F3 overlay inert in release | 6/6 |
| [#144](https://github.com/Kaydeross/wobble-arena/pull/144) | Join throttle, server-stamped names, ping badge | 6/6 |
| [#145](https://github.com/Kaydeross/wobble-arena/pull/145) | First-party anonymous analytics, off by default | 6/6 |
| [#146](https://github.com/Kaydeross/wobble-arena/pull/146) | First-five-minutes UX | 6/6 |
| [#147](https://github.com/Kaydeross/wobble-arena/pull/147) | 0.5.0 release prep and What's new | 6/6 |
| [#148](https://github.com/Kaydeross/wobble-arena/pull/148) | Release docs caught up to 0.5.0 | 6/6 |

```bash
gh pr checks 148
gh pr checks 147
```

- [ ] Every PR you intend to ship from shows 6/6, or you have explained the difference
- [ ] You checked `main`, not a stale local branch (`git log --oneline -1 origin/main`)

### 1.4 Version bump flow

There is one marketing version. It lives in `godot/project.godot` and is copied into the
export presets; `npm run check:version` fails if they drift. 0.5.0 is already set and tagged,
so for this release the flow is a check, not an edit; use the same steps for the next bump.

1. Set `config/version="0.5.0"` in `godot/project.godot` (the value you are shipping).
2. In `godot/export_presets.cfg`, set the same value on:
   - `application/short_version` in the iOS preset
   - `application/short_version` in the macOS preset
   - `application/file_version` and `application/product_version` in the Windows preset
   - `version/name` in the Android preset
3. Leave `application/version` and `version/code` alone. They are build counters, stamped
   per upload by `tools/build-ios.sh` and `tools/build-android.sh` (the Android script
   restores the committed placeholder afterwards).
4. Run:

```bash
npm run check:version   # expect: release version 0.5.0 is consistent
npm test
```

`check:version` accepts a four-part Windows value that ends in `.0` and trims it, so
`0.5.0.0` matches `0.5.0`. It also fails if either build script stops reading
`godot/project.godot` or grows a hard-coded fallback version.

- [ ] `npm run check:version` prints the version you intend to ship
- [ ] `npm test` passes again after the bump

### 1.5 What's new entry rules

The card is driven by `godot/data/extra/news.json` plus the translation source in
`godot/i18n/src/`.

- Newest entry first; its `version` must match `config/version` exactly.
- The card opens once per version the player has not seen. Do not add an entry for a
  version already shipped, and do not rewrite an old entry after release.
- Keep the title and the seven-or-so notes short. One silly beat at most, facts first, no
  trailing full stop on short lines. The voice rules are in `docs/WRITING.md`.
- Every English note must be a key in a translation file such as
  `godot/i18n/src/99-whats-new-050.json`, with all five languages: `zh_TW`, `zh_CN`, `ja`,
  `fr`, `es`. English is the source; the five translations sit beside it.
- New CJK characters must already be in `tools/cjk-coverage.json`. If the check rejects a
  character, reword first; extending the font subset with `tools/subset-fonts.py` is the
  last resort.

```bash
npm run i18n -- --check
```

Expect `0 errors, 18 warnings`; the warnings are the known earlier-file duplicates.

- [ ] `news.json` has one new top entry with the shipping version
- [ ] Every note has five translations
- [ ] `npm run i18n -- --check` reports 0 errors

### 1.6 README and release docs

`README.md` still advertises 0.4.0 in its version badge and its What's new heading. PR #148
deliberately left it alone because you have a rewrite of that file in progress in your main
checkout; an agent must not commit your uncommitted edits. Update it yourself for 0.5.0, or
accept that the repository front page is a version behind.

- [ ] `README.md` version badge and What's new heading name 0.5.0, or you accept the gap
- [ ] No store text or release note still says 0.4.0

---

## 2. Production server

The shipped URL is still the home NAS behind Tailscale Funnel. That is fine for friends, not
for a store build: one power cut or ISP outage is a game outage, and the hostname is not
yours.

### 2.1 Choose the soft-launch markets, then the host region

This is an **OPEN** decision. Pick the two or three markets first; the host must sit near
them, because the relay is latency-sensitive and there is one region.

- [ ] Markets chosen: ______________________________
- [ ] Host region chosen to match: ______________________________

### 2.2 Provision a paid, always-on host

Any of the options in `docs/SERVER_PLAN.md` works: a paid Render instance with a persistent
disk, Fly.io, or a small VPS running the repo `Dockerfile`.

- [ ] Host provisioned and paid for
- [ ] `DATA_DIR` points at persistent storage (never `/tmp`)
- [ ] `REQUIRE_LOGIN=1`
- [ ] `TRUST_PROXY` matches the real proxy: `1` for one hop you control, `cloudflare` only
      behind Cloudflare, never while port 3000 is reachable directly
- [ ] The host survives a redeploy with accounts intact

### 2.3 Create Upstash Redis and set the environment

Create a Redis database in Upstash in the same region as the host, then set both variables
on the host. Both must be present; a partial pair is ignored and silently falls back to the
file store.

```bash
# values from the Upstash dashboard; never commit them
UPSTASH_REDIS_REST_URL=...
UPSTASH_REDIS_REST_TOKEN=...
```

Check the account backend from outside:

```bash
curl -s https://play.<your-domain>/health
```

Expect `"accounts":"upstash"` in the JSON. If it says `"accounts":"file"`, the variables are
missing or the process was not restarted.

- [ ] Upstash database created near the host
- [ ] Both variables set in the host's secret store, not in git
- [ ] `/health` reports `"accounts":"upstash"`

### 2.4 Put a project domain and TLS in front

Use a hostname you own, for example `play.<your-domain>`, with a valid certificate. On a
cloud VM, a reverse proxy with Let's Encrypt is the simple path; from a home machine, a
Cloudflare Tunnel gives `wss://` TLS without opening a port. WebSockets need the `Upgrade`
headers and must not be buffered.

```bash
curl -s https://play.<your-domain>/health   # {"ok":true,...}
```

- [ ] The domain resolves and the certificate is valid
- [ ] `/health` returns `{"ok":true,...}` from a phone on mobile data, not from the host's own
      network
- [ ] A WebSocket reaches `wss://play.<your-domain>/ws` (the game's own Settings check is
      enough)

### 2.5 Move `godot/data/extra/server.json` off the NAS

Release builds read this file; the editor and tests keep the dev address. Change the `url`
to the new host and rebuild. The committed value is still the NAS funnel
(`wss://homeserver.tailcc5a5.ts.net/ws`) and must not ship.

```json
{
  "url": "wss://play.<your-domain>/ws"
}
```

- [ ] `godot/data/extra/server.json` points at the new `wss://` host
- [ ] No build made after this step still contains the NAS hostname
- [ ] A release export (not just the editor) connects to the new host

### 2.6 Migrate accounts from the NAS `data/db.json`

Back up first. The NAS file holds password hashes and cloud saves and is the only copy.

- [ ] Nightly backup taken and copied off the NAS
- [ ] A restore has been tested once (stop, copy back, start)

There is **no migration script in `tools/` yet**, and the cutover needs one. That is agent
work; you run it. The script must:

1. Read the NAS `data/db.json` (accounts, cloud saves, tokens, leaderboard keys).
2. Write the same records to Upstash with the same key names, without printing secrets.
3. Be safe to re-run, and report counts rather than contents.

After it exists:

```bash
# run from a checkout that can read a copy of the NAS db and the Upstash credentials
node tools/migrate-accounts.js --from /path/to/db.json
```

Then verify before switching players over:

- [ ] Account count matches the NAS file
- [ ] An existing account can log in
- [ ] A cloud save loads on a second device
- [ ] A leaderboard entry is present
- [ ] The NAS stays up, read-only, until a full day of successful logins

- [ ] Migration script written and reviewed (agent)
- [ ] Migration run and verified (owner)
- [ ] The NAS funnel is retired only after the new host has served real logins

### 2.7 Server wallet is a prerequisite for any coin sale

Coins are client-trusted today: the save blob holds them and the relay cannot stop a
modified client. `docs/STORE_READINESS_PLAN.md` makes the server wallet and server-verified
purchases the prerequisite for buying coins or premium content. Until that lands, **do not
sell coins, premium currency, coin packs or any DLC that depends on a wallet balance**. Free
coins earned in play are fine. Selling before the wallet exists turns a client edit into free
currency and makes refunds unauditable.

- [ ] You have confirmed no paid currency is on sale in 0.5.0
- [ ] The wallet work is scheduled before the first coin or premium-currency sale

### 2.8 Operations before review

- [ ] Uptime monitor on `https://play.<your-domain>/health` every 5 minutes, keyword
      `"ok":true`, alerting to a phone you actually carry
- [ ] Backups: nightly `db.json` copy if the file store is still in use, or the Upstash
      backup/export path
- [ ] `docker logs -f` (or the host's log view) checked after the first deploy
- [ ] Load test with `tools/wa-client.js` before opening the doors
- [ ] The host will stay up for the whole App Review window (days, not hours)

---

## 3. Privacy and legal

The current privacy page is live but stale. It says, in "What we do not do", that the game
does **not** use "advertising or analytics trackers". That sentence becomes false the moment
you flip the analytics switch, so it must change first. The live page is dated
12 November 2026; it is hosted outside this repository, so an agent cannot edit it.

### 3.1 Update the privacy page before analytics is on

Paste the usage-data block from `docs/ANALYTICS.md` ("Privacy policy wording") into
`https://kaydeross.github.io/wobble-arena/privacy.html`. Keep the existing account, relay
and children sections, remove or rewrite the "no analytics" bullet, and update the
"Last updated" date.

- [ ] Usage-data paragraph is on the live page
- [ ] The "no analytics trackers" claim is removed or qualified
- [ ] The date at the top is today's date
- [ ] The page is reachable from a phone without logging in

### 3.2 Add a Terms link

There is no Terms page and no Terms link in the game. `godot/ui/settings_screen.gd` currently
builds a single link row for the privacy policy. A Terms page and its wording are an owner
and legal decision; an agent can add the link once the page exists.

- [ ] Terms page published at a stable URL you control
- [ ] Terms link added beside "Privacy policy" in `godot/ui/settings_screen.gd`
- [ ] The link opens in the release build, not just the editor
- [ ] **OPEN:** who writes and approves the Terms text

### 3.3 Declare the App Store privacy label

In App Store Connect, under App Privacy, declare exactly what ships in this build. For
first-party analytics only (`docs/ANALYTICS.md`):

| Question | Answer |
|---|---|
| Data type | Usage Data > Product Interaction, and Diagnostics > Crash/Performance Data > Other Diagnostic Data |
| Linked to identity | No |
| Used for tracking | No |
| Purposes | Analytics, and App Functionality (bug fixing) |
| The line to report | "Usage data, not linked to identity, not used for tracking." |

If account login is in the same build, declare Contact Info and Identifiers separately, as
the policy already describes. Do not declare advertising data in 0.5.0: there is no ads SDK.

- [ ] App Privacy answers match the page and the build
- [ ] No advertising or tracking declaration is present in 0.5.0

### 3.4 Turn analytics on only after 3.1–3.3

The switch is remote, so this needs no app update. Edit the production `remote-config.json`
(the host reads `REMOTE_CONFIG`, default `remote-config.json`) and set `"analytics": true`.
The app fetches it at `/api/config`. The bundled copy in
`godot/data/extra/remote_config.json` can stay `false`; it is only the offline fallback.

- [ ] Privacy page and privacy label are live (3.1 and 3.3)
- [ ] `"analytics": true` on the production config
- [ ] `curl -s https://play.<your-domain>/api/config` shows `"analytics":true`
- [ ] New events appear in the store within a session or two

**OPEN:** the policy currently says the game is "not directed at children under 13" while
the build has a Kids mode and the store plan targets a general audience. Decide the age
rating and the audience sentence together before submission; do not leave the contradiction
in a reviewed build.

---

## 4. iOS build and TestFlight

The signing identity, App ID and first TestFlight build already exist. The steps below are
the repeatable release path, not first-time setup.

### 4.1 Confirm Xcode and App Store Connect access

- [ ] Xcode is signed in to team `663Q47AS93` (Xcode > Settings > Accounts)
- [ ] The App Store Connect app record exists for `com.kedrosng.wobblearena`
- [ ] An App Store Connect API key exists (Users and Access > Integrations), with the
      `AuthKey_<KEY_ID>.p8` file in `~/.appstoreconnect/private_keys/`
- [ ] Key ID and Issuer ID are to hand; do not commit or paste them

### 4.2 Build the 0.5.0 train

The marketing version comes from `godot/project.godot`; only the build number is passed in.
`BUILD_NUMBER` **resets for a new version train**: 0.5.0 starts at `1`, because 0.4.0 ended
at 458 and TestFlight sorts by build number within a version. The default is the git commit
count, which would look like a continuation of 0.4.0, so set it explicitly.

```bash
# from the clean worktree created in 1.2, never from a dirty checkout
BUILD_NUMBER=1 tools/build-ios.sh
```

Output: `build/ios/ipa/WobbleArena.ipa`, logs under `build/ios/logs/`. The script archives
with Apple Development, then re-signs for distribution with `beta-reports-active`.

- [ ] `BUILD_NUMBER=1` used for the first 0.5.0 upload
- [ ] The script printed `Version 0.5.0, build 1 (...)`
- [ ] The `.ipa` exists and the signature summary shows the store profile
- [ ] Later uploads use `BUILD_NUMBER=2`, `3`, … (never reuse a number)

### 4.3 Upload to TestFlight

```bash
xcrun altool --upload-app -f build/ios/ipa/WobbleArena.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

Transporter.app works too. Uploading is not done by `tools/build-ios.sh`.

- [ ] The upload was accepted (processing can take a while)
- [ ] The build appears in TestFlight under version 0.5.0
- [ ] Internal testers are assigned

### 4.4 Export compliance

Godot's Info.plist sets `ITSAppUsesNonExemptEncryption = false`; standard HTTPS and WSS are
exempt. Answer the export-compliance question in App Store Connect to match ("No" for
non-exempt encryption), unless you have added custom encryption since.

- [ ] Export compliance answered and recorded

### 4.5 TestFlight test matrix

Run every row on the TestFlight build, not on a local export. The matrix is the exit
criterion in `docs/STORE_READINESS_PLAN.md`.

| # | Test | Pass condition |
|---|---|---|
| 1 | Clean install | Reaches a playable match with no dead end |
| 2 | No network | Offline play works; online shows a clear, non-blocking error |
| 3 | Lost session | Reconnect or re-login recovers without losing the save |
| 4 | Forced update | Raising `minimum_version` in remote config shows "Update the game" and blocks cleanly |
| 5 | Sign-up and login | A new account can sign up, log in and cloud-save |
| 6 | Account deletion and report/block | Deletion works and revokes sessions; report and block work in a room |

- [ ] All six rows pass on a real device
- [ ] Failures are written down with the build number and the device

The plan's exit line also names ads and consent. There is no ad SDK in 0.5.0, so those rows
are out of scope; the account rows above cover the rest.

### 4.6 iPhone 12 15-minute soak

Use the iPhone 12, not a simulator. The soak is Settings > Graphics > Start soak test; it
runs an offline Chaos 5v5 on three arenas for five minutes each.

1. Charge to at least 50 %, close other apps, turn Low Power Mode off.
2. Turn Performance readout on (Settings > Graphics) and glance at it in a normal match: about
   60 fps, MID tier, GPU under about 12 ms.
3. First run unplugged, second run plugged in.
4. Start the soak, prop the phone up and leave it alone for 15 minutes; do not switch apps.
5. When the card appears, tap Copy summary.
6. Pull the CSV from `user://soak/` with Xcode: Window > Devices and Simulators > the app >
   Download Container. The app does not share these files because `settings.cfg` holds the
   account token.
7. Record the result in `docs/GRAPHICS.md`, under "Measuring on device". Add a table if one
   is not there, with: date, build number, device, iOS version, run type (unplugged or
   plugged), average fps, % slow frames, worst minute, p95 frame ms, average CPU and GPU ms,
   thermal state, and PASS or FAIL.

PASS needs average fps ≥ 58, ≤ 5 % slow frames, no fall-off of more than 10 % between the
first and last third of the run, and no serious thermal state. A run that leaves the app or
lets the screen lock is invalid. The app cannot read thermal state itself: run the soak with
the phone attached to Xcode and watch the Thermal State instrument, then write that down next
to the CSV numbers.

- [ ] Unplugged run PASS, summary and CSV kept
- [ ] Plugged-in run PASS or explained
- [ ] Both recorded in `docs/GRAPHICS.md` with the build number
- [ ] `npm run test:godot-perf` still passes

### 4.7 Demo account for App Review

Online play requires login, so App Review needs an account that works against the production
server for the whole review window.

- [ ] A dedicated review account exists on the production server (not a personal account)
- [ ] Username and password entered in App Store Connect > App Review Information, sign-in
      required
- [ ] The account is tested from a clean install on a phone that is not yours
- [ ] The server stays up, and the hostname and certificate do not change during review
- [ ] Notes explain what to tap for online play, and that offline play needs no account

Never put the password in the repo, a screenshot or a PR.

### 4.8 Screenshots, age rating and release

- [ ] Fresh screenshots from the 0.5.0 build, in the required sizes
- [ ] Age rating questionnaire completed and consistent with the audience decision at the
      end of section 3
- [ ] Support URL and marketing URL set in App Store Connect
- [ ] Pricing set to free
- [ ] Release to 2–3 small markets near the host region first, using phased release
- [ ] **OPEN:** the exact markets

Watch crash-free rate and the first-match funnel for the first week before widening.

### 4.9 Tester unlock: the secret code in TestFlight builds (remote switch)

A release export (TestFlight and the App Store) ignores the secret code and hides the seven-tap entry in Settings > About,
unless the server's config says `tester_unlock: true`. Debug and editor builds always accept it. One code unlocks **all**
four packs (Construction, On Fire, Ho Ho Ho, Hey Mate), their outfits and hats, every emote and class, and pays 5000 coins
once. The switch is **off by default everywhere**: the bundled `godot/data/extra/remote_config.json`, `remote-config.json`
and the server code all say `false`, so an install that cannot reach the server, or a server that is not told otherwise,
refuses the code.

**Turn it on for testing (no app update needed):**

1. On the production host, either set the environment variable `TESTER_UNLOCK=1` and restart the server, or edit the
   file the host reads for `/api/config` (`REMOTE_CONFIG`, default `remote-config.json`) and set `"tester_unlock": true`.
   The environment variable wins over the file; `TESTER_UNLOCK=0` forces it off.
2. Check: `curl -s https://play.<your-domain>/api/config` shows `"tester_unlock":true`.
3. In the TestFlight build, relaunch the game (the config is fetched at start and again whenever it refreshes). Settings >
   About > tap the version line seven times, enter the code.

**Turn it off before App Store release (do this before row 28 of the checklist):**

1. Remove `TESTER_UNLOCK` from the host (or set it to `0`) and set `"tester_unlock": false` in the config file.
2. `curl -s https://play.<your-domain>/api/config` must show `"tester_unlock":false`.
3. On a TestFlight build, relaunch: the seven taps now do nothing and a typed code is refused.
4. Do not ship the App Store build until step 2 shows `false`. A player who already redeemed the code while it was on keeps
   what it unlocked (that is saved in the profile); the switch only controls whether the code is accepted.

- [ ] `"tester_unlock": false` on the production config before the App Store submission
- [ ] `curl -s https://play.<your-domain>/api/config` shows `"tester_unlock":false`

---

## 5. Analytics and metrics gates before ad spend

These gates decide whether 0.5.1 ads are worth building and buying. Do not spend on
acquisition until all four pass on real soft-launch data.

### 5.1 Turn the data on

Complete section 3 first. Then flip the production remote config (`"analytics": true`) and
confirm events arrive. No app update is needed. A player must also leave Settings > Account >
Share anonymous usage data on (it is on by default), and Kids mode never sends anything.

### 5.2 Read the numbers

```bash
node tools/report-metrics.js --days=30
```

It reads Upstash when `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` are set,
otherwise the file store in `DATA_DIR`. `--selftest` checks the maths without a store.

| Gate | Threshold | Where it comes from |
|---|---|---|
| Crash-free sessions | ≥ 99 % | Xcode Organizer > Crashes, or TestFlight feedback; **not** `report-metrics.js` |
| First match finished | ≥ 70 % of installs | FTUE funnel: `ftue_step` `first_match_end` divided by `install` |
| D1 retention | ≥ 30 % | `report-metrics.js` D1 |
| D7 retention | ≥ 8 % | `report-metrics.js` D7, only for cohorts old enough |

- [ ] Analytics has run for at least 7 full days before judging D7
- [ ] Crash-free ≥ 99 %
- [ ] First match finished ≥ 70 %
- [ ] D1 ≥ 30 %
- [ ] D7 ≥ 8 %
- [ ] The result is written down with the date and window

If a gate misses, fix the funnel before buying users. Ads on top of a leaky first match only
pay for people who leave.

---

## 6. Track P: native plugin proofs

Time-boxed and parallel. It does **not** block build 1, and nothing from it ships in 0.5.0.

Prove on a real iPhone, with Godot 4.7.2:

1. **AdMob with UMP and ATT.** The candidate in `docs/IMPROVEMENT_PLAN.md` is the Poing
   Studios Godot plugin. The tracking prompt must actually appear; a missing ATT prompt has
   caused App Review rejections before.
2. **StoreKit 2.** A non-consumable purchase, restore, and an offline entitlement read
   through the `Entitlements` service.

Output is a short go/no-go note covering: which plugin and version, what worked, what broke,
the exact export and privacy-manifest changes, the ATT/UMP flow, and whether the plugin is
safe to adopt in 0.5.1. Use a throwaway branch; do not merge it into `main`.

- [ ] AdMob + UMP + ATT proved on a real iPhone
- [ ] StoreKit 2 purchase and restore proved on a real iPhone
- [ ] Go/no-go note written and dated
- [ ] **OPEN:** the StoreKit plugin choice and where the note lives (proposed new
      `docs/TRACK_P.md`, or a section in `docs/ROADMAP.md`)

---

## 7. What an agent can and cannot do

| An agent can | An agent cannot |
|---|---|
| Read the repo and the docs, and write code or documentation | Create or sign in to Apple, Google, Upstash, Cloudflare or host accounts |
| Run `npm test`, the Godot suites on this Mac, and the build scripts in export-only mode | Sign an archive with your distribution certificate or accept Apple's agreements |
| Draft the privacy wording, the Terms text, the review notes and the go/no-go note | Decide the legal text, the age rating or the launch markets |
| Write the account-migration script and a dry-run report | Run a migration against production data, or hold production credentials |
| Prepare a PR, run CI and report the checks | Merge, push tags, upload a build, submit for review, or press Release |
| Inspect a build's config, `server.json` and version fields | Provision or pay for the host, or flip the production `analytics` switch |
| Reproduce a bug on a simulator | Approve a real-device soak, an ATT prompt or a purchase |

The dividing line is simple: agents prepare and verify; the owner signs, pays, publishes and
accepts the legal risk.

---

## 8. Checklist

Dates in the last column are for you to fill in as you go. Anything marked **OPEN** needs a
decision before the row can be ticked.

| Done | # | Step | Owner | Date |
|---|---|---|---|---|
| [ ] | 1 | Verify `v0.4.0` → `8962b9f` and `v0.5.0` → `4c87268`; later commits docs only | Owner | |
| [ ] | 2 | `npm test` passes on a clean checkout at the shipping commit | Owner | |
| [ ] | 3 | CI 6/6 on the shipping PRs; `main` tip checked | Owner | |
| [ ] | 4 | Version fields agree; `npm run check:version` green | Owner | |
| [ ] | 5 | `news.json` entry and five translations; `npm run i18n -- --check` 0 errors | Owner | |
| [ ] | 6 | README version badge and store text name 0.5.0, or the gap is accepted | Owner | |
| [ ] | 7 | **OPEN:** soft-launch markets and host region chosen | Owner | |
| [ ] | 8 | Paid always-on host provisioned near those markets | Owner | |
| [ ] | 9 | Upstash Redis created; both env vars set; `/health` shows `upstash` | Owner | |
| [ ] | 10 | Project domain and TLS live; `/health` and `/ws` reachable | Owner | |
| [ ] | 11 | `godot/data/extra/server.json` points at the new host; release rebuilt | Owner | |
| [ ] | 12 | NAS `data/db.json` backed up and a restore tested | Owner | |
| [ ] | 13 | Agent-built account-migration script exists and has been reviewed | Owner | |
| [ ] | 14 | Accounts migrated and verified; NAS funnel retired | Owner | |
| [ ] | 15 | No coin or premium-currency sale before the server wallet | Owner | |
| [ ] | 16 | Uptime monitor, backups and load test done | Owner | |
| [ ] | 17 | Privacy page carries the usage-data wording and a new date | Owner | |
| [ ] | 18 | **OPEN:** Terms page written, published and linked in the app | Owner | |
| [ ] | 19 | App Store privacy label matches the build | Owner | |
| [ ] | 20 | Production `analytics: true` only after rows 17–19 | Owner | |
| [ ] | 21 | Xcode signing and App Store Connect API key ready | Owner | |
| [ ] | 22 | `BUILD_NUMBER=1 tools/build-ios.sh` succeeds | Owner | |
| [ ] | 23 | `.ipa` uploaded to TestFlight; internal testers assigned | Owner | |
| [ ] | 24 | Export compliance answered | Owner | |
| [ ] | 25 | TestFlight matrix passes all six rows | Owner | |
| [ ] | 26 | iPhone 12 soak PASS; results in `docs/GRAPHICS.md` | Owner | |
| [ ] | 27 | Demo account created, tested and entered in App Review Information | Owner | |
| [ ] | 28 | Screenshots, age rating, support URL and pricing set | Owner | |
| [ ] | 29 | **OPEN:** age-rating and audience contradiction resolved | Owner | |
| [ ] | 30 | **OPEN:** App Store release markets chosen; phased release started | Owner | |
| [ ] | 31 | Crash-free ≥ 99 %, first match ≥ 70 %, D1 ≥ 30 %, D7 ≥ 8 % | Owner | |
| [ ] | 32 | **OPEN:** Track P go/no-go note, plugin choice and where the note lives | Owner | |
| [ ] | 33 | Ad spend approved only after row 31 | Owner | |
| [ ] | 34 | `tester_unlock` is `false` on the production config before the App Store submission (section 4.9) | Owner | |
