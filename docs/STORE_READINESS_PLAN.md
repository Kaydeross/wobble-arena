# Wobblers Arena: store-readiness execution plan

This is the checked-in execution version of the 2026-11-14 plan
(`docs/IMPROVEMENT_PLAN.md`, which holds the audit findings, the full improvement
backlog and the attraction plan). It keeps the agreed business model and turns
the recommendations into ordered work with concrete exit criteria and a live
status table at the end.

## Product decisions

- Launch free with ads on iOS and Android.
- Offer one paid, non-consumable purchase that removes ads.
- Add coins, DLC and subscriptions only after the server is authoritative for
  the wallet and entitlements.
- Target a general audience in the normal Games category.
- Keep paid gameplay content cosmetic or a sidegrade. Classes must remain
  earnable through play.
- Do not sell random paid items.

## Operating rules

1. Fix gameplay blockers before adding revenue.
2. Measure on a physical phone before treating a rendering or thermal result as
   known.
3. Keep PC, mobile and web playable. New offline combat rules stay behind
   `Combat.tuning_active()` until the web client is retired.
4. Ship all DLC code in the app. A server entitlement may unlock data and
   configuration, but not introduce executable code.
5. Ads never interrupt a live match, a lobby or a friend rematch.
6. Rewarded ads remain optional. "Remove ads" removes forced interstitial ads
   and grants rewarded bonuses immediately.
7. Coins, owned purchasable items and entitlements become server-authoritative
   before they can be bought.
8. A release needs a recoverable account boundary before an app-store purchase
   is attached to it.

## Stage 0: immediate fixes

### Melee bosses

- Every Construction Arcade boss starts with an approved melee tool.
- Guns and thrown tools enter boss stages only through crates.
- A boss holding a melee tool may replace it with a gun crate.
- `keep_kit` refills only melee tools; picked-up ranged tools run out normally.
- The Client's change-request event chooses melee tools only.
- The Angle Grinder pickup has lower burst output and limited fuel.
- Tests reject a boss starts-with-gun regression and cover a boss taking a gun.

Exit: arcade data, balance and gameplay tests pass; documentation names the new
boss weapons.

### Stuck touch controls

- Reusing a touch index releases the action previously owned by that finger.
- Pressing a held button again takes ownership and cannot leave it orphaned.
- A held action is released when its owning touch disappears.
- Focus loss, application pause and cancelled touches call `release_all()`.
- A scripted regression test covers each case.
- The diagnostics readout reports held actions by input source.

Exit: the touch test and existing UI/performance tests pass.

## Stage A: feel and measurement

- Add light hit, medium hurt, heavy K.O. and explosion haptics, with a setting.
- Vary repeated sound pitch and volume, preserve important voices, and use the
  existing 2D/3D audio buses consistently.
- Render available movement and UI synth recipes; add big-moment cues for the
  countdown, K.O., ring-out, respawn, win and loss.
- Add frame caps (30 / 60 / 120), render scale and thermal-safe defaults.
- Make high-impact camera motion and temporary audio ducking respect settings.
- Update the graphics benchmark for the current build and record the build hash
  beside every result.
- Run the 15-minute soak on an iPhone 12 with Low Power Mode both on and off.
- Add thermal state, load-hitch logging and a supported CSV export path.

Exit: all automated tests pass; a real-device report records fps, GPU time,
memory, thermal state, load hitches and input behaviour.

## Stage B: launch with ads

### Ads and consent

- Add one `Ads` policy service with provider-neutral show/load/cap APIs.
- Use AdMob through a maintained Godot iOS/Android plugin.
- Implement rewarded placements on results, daily bonus and Arcade continue.
- Implement a capped between-match interstitial; do not use banners.
- Gate on first-session grace, placement eligibility, online lobby state,
  minimum interval, consent and the Remove Ads entitlement.
- Pause gameplay and audio around an ad, then restore exactly.
- Ship consent/tracking prompts, family-safe ad content and the required store
  privacy declarations.

### Account and server safety

- Disable automatic idle-account deletion by default. A TTL may remain as an
  explicit operator choice.
- Revoke every session on password change, password reset and account deletion.
- Rotate the current session after a password change.
- Use full-width millisecond timestamps for cloud-save conflict checks.
- Use a persistent database or managed Redis in production; a redeploy must not
  erase accounts.
- Bake a production server address owned by the project into release builds.
- Keep the authentication token in iOS Keychain / Android secure storage.
- Disable developer unlock codes in release builds.
- Add report, block and filtered display-name support for online play.

### Operations

- Add remote config over HTTPS with a bundled, safe fallback for ad caps,
  featured mode, news, minimum client version and feature kill switches.
- Add consented analytics and crash reporting.
- Separate staging and production configuration.
- Add API and protocol version gates with a clear "Update the game" message.
- Add cached Godot setup, all practical suites and export smoke builds to CI.

Exit: a TestFlight build works on a clean device with consent accepted and
declined, ads on and off, no network, a lost session and an expired version.

## Stage C: charm and depth

- Show the player's actual Wobbler on the title screen.
- Replace static onboarding cards with a scripted, winnable first fight.
- Add blink, hurt and K.O. facial expressions.
- Turn results into a podium moment with emote poses, coin count-up and unlock
  progress.
- Add per-family impact VFX and audio identity.
- Add visual state feedback for low health, burn, stun and wind-up.
- Add a timed shove/parry and one signature move per class.
- Add tap light / hold heavy melee attacks and per-weapon swing shapes.
- Add burn, chill and shock status effects where the content calls for them.
- Add aim-assist strength and optional auto-fire for touch.
- Prefer silhouettes and large outfit shapes over recolours.
- Dress the most-played arenas before adding more arenas.
- Curate the launch mode/arena list and feature a rotating mode.
- Add share-link invites, quick play with bots and shareable K.O. clips.

Exit: a new player reaches and wins the first fight, understands defence and
weapon identity, and can complete a share/reward loop without a dead end.

## Stage D: paid no-ads purchase

- Add an `Entitlements` service in front of StoreKit 2 and Google Play Billing.
- Sell one non-consumable Remove Ads purchase in the existing app.
- Restore purchases and expose a clear entitlement status.
- Remove forced between-match ads and grant rewarded bonuses immediately when
  the entitlement is active.
- Test StoreKit sandbox and Play licensing on clean installs, restore, refund and
  offline launch.

Exit: purchase, restore, offline entitlement cache and cross-relaunch behaviour
pass on TestFlight and an internal Play track.

## Stage E: monetised economy and content

Prerequisites:

- Recoverable login before any wallet purchase.
- Server-side wallet and entitlement endpoints.
- Server-verified App Store and Play purchases plus renewal/refund webhooks.
- Server-decided rewards, caps and time.
- Online ownership validation before selecting a paid cosmetic class.
- Save schema versioning, migrations and per-field merge.

After those prerequisites:

- Add coin packs only after the free/ad economy is settled.
- Add DLC purchases through entitlements while keeping their code in the app.
- Consider a subscription only when a new arena, mode or cosmetic set ships on a
  reliable rhythm.

## Measurement and release gates

### Every change

- Content and translation checks pass.
- Relevant headless gameplay tests pass.
- No new warnings in Godot import or runtime logs.

### Every release

- Fresh install reaches a match with no dead end.
- A physical iPhone 12 sustains the selected frame target for 15 minutes.
- Account deletion and session revocation work.
- Offline play and cloud-save recovery work.
- Ads never appear during play and respect consent and purchase state.
- Privacy manifest, policy, age rating and store declarations match the build.

## Current implementation status

| Area | Status |
| --- | --- |
| Plan checked in (`docs/IMPROVEMENT_PLAN.md`, `docs/ROADMAP.md`, this file) | complete |
| Melee-boss redesign (melee kits, crate-only guns, melee-only change requests, ring-outs no longer clear a boss) | complete, retuned against the balance probe |
| Stuck FIRE regression (index reuse, takeover, focus loss, cancel, orphan sweep, perf-readout held line) | complete, regression test fails before / passes after |
| Haptics | complete (light/medium/heavy, Settings switch, phone-only; iOS only plays the heavy system vibrate) |
| Audio quick wins (pitch/volume variation, voice priority, movement sounds, UI clicks) | complete |
| Big-moment audio (K.O., fall, respawn, countdown, win/lose, low-health pulse, results music, ducking) | complete |
| Frame cap / render scale | complete (Settings > Graphics + autoload `Perf`) |
| Launch-service policy (`Ads`, `Entitlements`, `RemoteConfig`, `Safety`) and their tests | complete, provider-neutral |
| Account revocation, retention safety, 64-bit save timestamps, name filter, report/block | complete |
| Version single source and CI (all suites + export smoke) | complete |
| AdMob / StoreKit native plugins, consent forms, analytics and crash reporting | blocked on store credentials and native plugin selection |
| Remove Ads purchase, restore and store sandbox runs | blocked on the StoreKit plugin choice |
| Ads placements UI (rewarded results/daily/continue, between-match ad) | policy layer ready; UI waits for the provider so no dead button ships |
| Sound distance / left-right cues | remaining |
| Physical-device soak, phone GPU/thermal measurement, #105 look decisions | blocked on iPhone 12 access |

