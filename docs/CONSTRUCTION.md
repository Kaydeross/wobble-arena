# Construction Mode

Scaffold for a tradie-themed offline mode. Keeps the existing Claude / class / online flow intact: no new Locker classes, no `cls` protocol changes, and Construction stays offline like Sandbox.

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
