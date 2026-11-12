# Construction Mode

Scaffold for a tradie-themed offline mode. Keeps the existing Claude / class / online flow intact: no new Locker classes, no `cls` protocol changes, and Construction stays offline like Sandbox.

## Standing product instructions (Claude flow)

These decisions stay in force for this branch and later Construction PRs (same answers as the Godot / iOS plan interview):

| # | Decision |
|---|---|
| Platforms | **Web + PC wrapper + iOS**, with **cross-play** between them |
| First TestFlight | Start from the **web client** (touch + phone layout already there) |
| Engine | **Godot everywhere** — one codebase for web / PC / iOS long-term; web three.js stays the live client until Godot parity |
| Priority | **Playable on iPhone soonest** — do not block the Godot / protocol path |
| App Store v1.0 | **Everything** in scope eventually; ship Construction as data-first content, unlock gameplay in follow-ups |

How this PR respects that:

- Content lands in `shared/*.json` so a Godot client can load the same mode / weapons / map later.
- Construction is **offline-only** until cross-play host parity exists (`netMode` → Classic).
- No protocol (`PROTO`) bump and no new `cls` values — parallel Claude class / mobile / Godot PRs keep merging.
- Boss rush and cosmetics stay documented follow-ups, not blockers for iPhone.

See also [`docs/IOS_PLAN.md`](IOS_PLAN.md) and [`docs/PROTOCOL.md`](PROTOCOL.md).

## Shipped in this PR (scaffold)

| Piece | Id / notes |
|---|---|
| Mode | `construction` — locked “Coming soon” in the mode list |
| Map | `siteyard` / Site Yard — exclusive stub worksite |
| Weapons | `hammer` (Claw Hammer), `wirewhip` (Live Wire), plus existing `blower` (Air Blower) |
| Online | `netMode` maps Construction → Classic; button hidden in host/create-room flow |
| Classes | None — loadouts are mode-only weapons, not new character classes |

Edit tables in `public/index.html`, then run `npm run content` so `shared/*.json` stays in sync.

## Unlock follow-up (playable v1)

1. Remove the locked class / “Coming soon” blurb once combat + bots feel good offline.
2. Start weapon / crate pool already filter to hammer, Live Wire, blower.
3. Optional tradie tips on the home screen and a Builder-skin suggest in the locker.

## Boss rush follow-up (from brainstorm)

Offline ladder of site bosses, patterned after Weapon Ladder (`gungame`) / Pillars init:

1. Engineer  
2. Designer  
3. Supervisor  
4. Project Manager  
5. The Client (final)

Suggested rules: one life per boss wave, escalating HP / damage / knockback, each boss favours a tool (plans, red tape net, clipboard bat, contract rocket). Keep it offline until the mode is stable.

## Extra ideas worth a later PR

- **Hard-hat hats / hi-vis skins** — cosmetic only; Builder skin already exists.
- **Scaffold dash** — short climb boost on scaffold boxes (mode flag, not global movement change).
- **Cone traps / wet-cement pads** — slow or sticky floor pads on Site Yard only.
- **Toolbox crates** — Construction-only crate table (tools + rare “site plan” that marks rivals briefly).
- **Tradie callouts** — short KO lines per weapon (“That’s going in the variation!”) without touching netcode.
- **Wobble Workshop bridge** — later, unlock Sandbox block place/remove *inside* Construction for temporary cover (still offline).

## Merge notes

- Do not expand `PROTO` or require guests to understand Construction.
- Prefer additive edits near `MODES`, `WEAPONS`, `MAPS.siteyard`, and `netMode` so parallel Claude PRs on classes / mobile UI stay easy to merge.
- After merge conflicts in `public/index.html`, re-run `npm run content` and `npm test`.
