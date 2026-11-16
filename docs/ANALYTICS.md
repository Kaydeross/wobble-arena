# Analytics (first-party, anonymous)

Wobblers Arena measures how it is used with its **own server only**: no third-party SDK, no advertising id, no name,
account, email, IP address or device identifier is ever attached to an event. Code: `godot/autoload/analytics.gd`
(client), `events.js` (server, `POST /api/event`, docs/PROTOCOL.md 4.2), `tools/report-metrics.js` (reports).

## When anything is sent

Nothing is sent unless **both** hold:

1. the remote config switch `analytics` is `true` (`remote-config.json`, default `false`, so a release can ship dark and be turned on without an update), and
2. the player has "Share anonymous usage data" on (Settings > Account; Settings key `analytics_optout`, default off = sharing on).

Kids mode never sends anything (the client checks `kids_mode`), regardless of the two switches. Turning the toggle off
clears any events still waiting on the device.

## The install id

A random 128-bit id (`iid`, 32 hex chars) made on the device the first time analytics is allowed and kept in
`settings.cfg`. It is not derived from anything and is not linked to an account or name. Reinstalling the game makes a
new one. It lets retention be counted without knowing who anyone is.

## Events

Common to every batch: `iid`, `ver` (game version), `plat` (`ios`, `android`, `macos`, `windows`, `web`...). Each event has
`n` (name), `t` (client epoch ms) and `p` (params: at most 8 scalars, strings cut to 64 chars, 200 for `error`).

| Event | When | Params |
|---|---|---|
| `install` | once, the first time analytics is allowed on this install | none |
| `session_start` | boot (or resume from background) | none |
| `session_end` | the app is paused or closed | `secs` |
| `ftue_step` | first-run milestones | `step`: `intro_shown`, `intro_done`, `intro_skipped`, `first_fight_offered`, `first_match_start`, `first_match_end` (+ `page`, `result`) |
| `match_start` | a match begins (not the tutorial) | `mode`, `map`, `online` |
| `match_end` | the results show | `mode`, `map`, `online`, `result` (`win`/`loss`/`other`), `secs` |
| `coins_spent` | a locker purchase (`Save.buy`) | `kind` (`skin`/`class`/`emote`), `price` |
| `online_join_result` | joining a room succeeds or is refused | `ok`, `reason` (server refusal code, only when `ok` is false) |
| `error` | a script error (`OS.add_logger`, Godot 4.7 `Logger`) | `text` (200 chars), `at` (`file.gd:line`); de-duplicated, at most 5 a session |

The client queues events in memory (max 200), flushes every 30 s, when 20 are waiting, and on pause or quit. A failed
batch is retried once, then dropped. Analytics never blocks or slows the game.

## What the server keeps

`events.js` accepts only the names above, rejects anything else, keeps only `i` (install id), `n`, `t`, `v`, `o` (platform)
and the cleaned params. The caller's IP is used for a rate limit (30 batches a minute per IP, in memory) and is **never
stored**. Events are appended to one bucket per UTC day in the accounts store (Upstash if configured, else `data/db.json`),
at most 20000 events a day (oldest dropped) and each bucket expires after 31 days. No account or token is read, so an event
cannot be tied to an account. The retention window is 30 days.

## Reports

`node tools/report-metrics.js [--days=30]` reads the store (Upstash or the file in `DATA_DIR`) and prints D1/D3/D7 retention
(only cohorts old enough to measure), sessions per day, median session length, matches per session, the FTUE funnel
(installs that reached each step) and the top errors. `--selftest` checks the maths against a fixture.

## Privacy policy wording (the policy page is hosted outside this repo; paste this)

> **Usage data.** If you leave "Share anonymous usage data" on, the game sends our own server a small number of anonymous
> events: when you open and close the app, how long a session lasts, which game modes and maps you play and whether you
> win, when you spend in-game coins, whether joining an online room worked, and technical errors. These events are tied
> only to a random install id created on your device, not to your name, account, email, IP address or any device
> identifier, and they are not used for advertising or tracking across other apps and websites. We use them to fix bugs and
> balance the game. We do not share them with third parties. Events are deleted automatically after 30 days. You can turn
> this off at any time in Settings > Account > Share anonymous usage data, and nothing is sent in Kids mode.

## App Store privacy label (App Privacy "nutrition label")

- **Data type:** Usage Data > Product Interaction (sessions, modes, matches, purchases of in-game items with in-game coins), and Diagnostics > Crash/Performance Data > Other Diagnostic Data (script errors).
- **Linked to the user's identity?** **No**: *not linked to identity.*
- **Used for tracking?** **No**: *not used for tracking.*
- **Purposes:** Analytics, and App Functionality (bug fixing).
- Exact line to report: **"Usage data, not linked to identity, not used for tracking."**
- If account login or ads are enabled in the same build, those are declared separately (Contact Info and Identifiers for ads, per the ads provider); this document covers only first-party analytics.

Google Play Data safety: "App activity" and "App info and performance", collected, **not shared**, optional (users can turn it off), encrypted in transit, data deleted automatically (30 days).
