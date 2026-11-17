# Handover: Wobblers Arena (Claude → DeepSeek), updated 2026-11-17

Read this first, then `docs/REVISED_PLAN.md` (trust the code over the old plan). Repo `/Users/kedrosng/Developer/wobble-arena` (GitHub `Kaydeross/wobble-arena`). Godot 4.7.2 game + Node relay. iOS first.

## Rules for working
- **One DeepSeek task at a time.** The owner does not yet know how stable DeepSeek is. Review the diff and rerun the gates yourself (never trust a "green" report) before starting the next task.
- Never work in the main checkout (`/Users/kedrosng/Developer/wobble-arena`): it is on a stale branch with the owner's uncommitted `README.md`. Use a git worktree off fresh `origin/main`, one branch and one PR per task, merge with `gh pr merge <n> --merge`.
- Parity: gate Godot-only combat/physics behind `Combat.tuning_active()`. Never hand-edit `shared/*.json` or the synced `godot/data/*.json`. Godot-only data goes in `godot/data/extra/` or a pack folder.
- RNG: never call `combat.rng` from visual code; use a local `RandomNumberGenerator`.
- i18n: every `tr()` string in all 5 languages (zh_TW, zh_CN, ja, fr, es) under `godot/i18n/src/*.json`, then `node tools/i18n.js` and `npm run i18n -- --check`. CJK glyphs must be in `tools/cjk-coverage.json`: reword, never edit fonts. On merge conflicts in generated i18n files: `git checkout --theirs` those files, then `node tools/i18n.js`.
- Gates: `npm test` plus the relevant `npm run test:godot-*`. Run Godot suites one at a time. New `.gd` files create `.uid` files: commit them.
- Never print or paste the DeepSeek API key.

## State (2026-11-17)
- `main` (merge `113502e`) has: release hardening, join throttle and server-stamped names, analytics (off), first-five-minutes UX, 0.5.0, monetisation groundwork (inert), unified online combat, podium, spatial audio, result card, ledge/rubble, server wallet, balance runner, and the three packs (Kitchen "On Fire" `kitchen`, Xmas "Ho Ho Ho" `xmas`, Australia "Hey Mate" `australia`; 1500 coins each).
- **PR #165 is merged**: pack selector carousel, per-pack smoothed transitions, real 3D landing pages (kitchen / snow globe / desert suburb with kangaroo), denser Backyard BBQ arena and clearer Hills Hoist, fix so online guests see pack hats and outfits, and the `tester_unlock` switch.
- **TestFlight**: 0.5.0 builds 1 to 4 are uploaded (build 4 contains everything in #165). Upload recipe: memory note `testflight-upload-via-xcodebuild` (no ASC API key here: build with `BUILD_NUMBER=<n> tools/build-ios.sh` from a fresh `origin/main` worktree, then `xcodebuild -exportArchive` with an options plist whose `destination` is `upload`). Each upload needs a higher `BUILD_NUMBER` (next is 5).
- **Secret code in release builds** works only when the remote flag `tester_unlock` is true: set `TESTER_UNLOCK=1` on the server, or `"tester_unlock": true` in the remote config file (runbook `docs/OWNER_RELEASE_RUNBOOK.md` §4.9). Turn it off before the App Store.
- A balance pass for the 18 pack weapons was started (worktree `wobble-arena-packF2`, branch `wp/packs-F2`, **uncommitted**: `godot/tests/balance_match.gd`, `tools/run-balance-matrix.js`). It may not have finished. Check its diff; it is safe to finish or discard.

## Good small first tasks for DeepSeek (do one, review, then the next)
1. Housekeeping: remove merged worktrees and branches (`wobble-arena-v06c`, `v06d`, `wobble-ctl/fit/ship/title/wn`, `packB/C/D/E1/E2/E3/F1/F3`, `wobble-arena-work`, and `backup/v06e-local-fff305c` only if the owner agrees) and clear the old stashes. Look before deleting.
2. Docs: add the selector, transitions and landing pages to `docs/TITLE.md` and `docs/CONSTRUCTION_DLC.md` (how to add a fifth pack).
3. Finish the pack weapon balance pass (see above), tuning only the three packs' `weapons.json`, with a before and after table in `docs/BALANCE_TELEMETRY.md`.
4. Landing polish: the page outside the hero band is a flat gradient; the stage slot shows as a brighter window; portrait keeps the old small band; the Australia landing set is at 244 of 250 mesh instances (cap 250).
5. Camera at the fence in Backyard BBQ looks over the fence from some spawns (shared camera code).

## Known gaps
- Online co-op Arcade is Construction-only.
- Older app builds show pack items as `none` for online players (fixed only in new builds).
- Some Chinese and Japanese wording was reworded for glyph coverage; a font rebuild would let it read better.
- Pack weapons are range-checked, not playtested. Nothing in #149 (monetisation), #161 (ledge/rubble) or the packs has been played on a real device.
- No iPhone frame-time measurements for the 3D landing pages, the transitions or the Hills Hoist shadow.
- The kitchen transition may still not be what the owner wants; ask before redesigning.

## Owner-only items
Production host and `server.json`, privacy page and Terms, iPhone 12 15-minute soak run, App Store Connect (screenshots, age rating, privacy label, export compliance, demo account), native ad, purchase, share and thermal plugins, a CJK font rebuild, turning analytics on, and the README version badge.

## DeepSeek tooling
`~/.claude/mcp/deepseek-delegate` runs `dsh --profile headless` (with `enable-credentials.yml`). Give it complete briefs: it cannot see this conversation, and concurrent tasks need separate worktrees (the owner wants them one by one for now).
