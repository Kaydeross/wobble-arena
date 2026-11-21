# Handover: Wobblers Arena (Claude → DeepSeek), updated 2026-11-21

Read this first, then `docs/REVISED_PLAN.md` (trust the code over the old plan). Repo `/Users/kedrosng/Developer/wobble-arena` (GitHub `Kaydeross/wobble-arena`). Godot 4.8 beta 4 game (until 4.8 stable) + Node relay. iOS first.

## Rules for working
- **One DeepSeek task at a time.** The owner does not yet know how stable DeepSeek is. Review the diff and rerun the gates yourself (never trust a "green" report) before starting the next task.
- Never work in the main checkout (`/Users/kedrosng/Developer/wobble-arena`): it is on a stale branch with the owner's uncommitted `README.md`. Use a git worktree off fresh `origin/main`, one branch and one PR per task, merge with `gh pr merge <n> --merge`.
- Parity: gate Godot-only combat/physics behind `Combat.tuning_active()`. Never hand-edit `shared/*.json` or the synced `godot/data/*.json`. Godot-only data goes in `godot/data/extra/` or a pack folder.
- RNG: never call `combat.rng` from visual code; use a local `RandomNumberGenerator`.
- i18n: every `tr()` string in all 5 languages (zh_TW, zh_CN, ja, fr, es) under `godot/i18n/src/*.json`, then `node tools/i18n.js` and `npm run i18n -- --check`. CJK glyphs must be in `tools/cjk-coverage.json`: reword, never edit fonts. On merge conflicts in generated i18n files: `git checkout --theirs` those files, then `node tools/i18n.js`.
- Gates: `npm test` plus the relevant `npm run test:godot-*`. Run Godot suites one at a time (`godot-ui` and `godot-bots` take over 4 minutes each, about 12 minutes in the worst case). New `.gd` files create `.uid` files: commit them.
- Never print or paste the DeepSeek API key.

## State (2026-11-21)
- `main` (merge `494e257`, PR #173) has: release hardening, join throttle and server-stamped names, analytics (off), first-five-minutes UX, 0.5.0, monetisation groundwork (inert), unified online combat, podium, spatial audio, result card, ledge/rubble, server wallet, balance runner, and the three packs (Kitchen "On Fire" `kitchen`, Xmas "Ho Ho Ho" `xmas`, Australia "Hey Mate" `australia`; 1500 coins each).
- **PR #165 is merged**: pack selector carousel, per-pack smoothed transitions, real 3D landing pages (kitchen / snow globe / desert suburb with kangaroo), denser Backyard BBQ arena and clearer Hills Hoist, fix so online guests see pack hats and outfits, and the `tester_unlock` switch.
- **Merged since the last handover (#166)**:
  - **#167** balance: Cricket Bat, Pepper Grinder, Snowball Blaster, Thong Slapper and BBQ Tongs retuned from 808 bot matches; `--pack` and `--starts` added to the balance runner (`tools/run-balance-matrix.js`); a Pack weapons section in `docs/BALANCE_TELEMETRY.md`. Hey Mate still runs hot (start weapon in `modes.json`), left for a follow-up. The old `wp/packs-F2` worktree work is finished: nothing is uncommitted there any more.
  - **#168** README version is 0.5.0 and `check-version` now guards the README badge and What's new section.
  - **#169** docs: pack selector, transitions, 3D landing pages, `tester_unlock`, and how to add a fifth pack.
  - **#170** the follow camera stays inside walled pack yards (Backyard BBQ fence). Headless test `npm run test:godot-camera-fence`; not checked on a device.
  - **#171 and #172** audit fixes: wallet retry no longer double-charges (ids named like `Object.prototype` keys), 5xx wallet ops are retried, a refused pack purchase takes back the pack outfits but keeps emotes it did not grant, `cleanInfo` keeps Godot-only classes (Bulwark, Zippy, Ace) online, and expired wallet rate entries are pruned.
  - **#173** the engine base moved to **Godot 4.8 beta 4** until 4.8 stable: build, test and screenshot scripts, CI and docs target `4.8.beta4` (app `/Applications/Godot_4.8-beta4.app`, templates in `export_templates/4.8.beta4`), assets were re-imported with the 4.8 importer, and the pre-assist aim precondition in `weapons_test` went from 0.9985 to 0.995 (the aim-assist check itself is unchanged). All 66 `test:godot*` suites passed locally on 4.8 beta 4; the PR left "CI green with the 4.8 beta 4 Linux build" unticked, so check CI on `main`.
- **TestFlight**: 0.5.0 builds 1 to 7 are uploaded (build 4 contains everything in #165; build 7 is the latest). Upload recipe: memory note `testflight-upload-via-xcodebuild` (no ASC API key here: build with `BUILD_NUMBER=<n> tools/build-ios.sh` from a fresh `origin/main` worktree, then `xcodebuild -exportArchive` with an options plist whose `destination` is `upload`). Each upload needs a higher `BUILD_NUMBER` (next is 8). Builds are now made with Godot 4.8 beta 4 templates, so install them first.
- **Secret code in release builds** works only when the remote flag `tester_unlock` is true: set `TESTER_UNLOCK=1` on the server, or `"tester_unlock": true` in the remote config file (runbook `docs/OWNER_RELEASE_RUNBOOK.md` §4.9). Turn it off before the App Store.

## Good small first tasks for DeepSeek (do one, review, then the next)
1. Housekeeping: remove merged worktrees and branches (`wobble-arena-v06c`, `v06d`, `wobble-ctl/fit/ship/title/wn`, `packB/C/D/E1/E2/E3/F1/F2/F3`, `wobble-arena-work`, and `backup/v06e-local-fff305c` only if the owner agrees) and clear the old stashes. Look before deleting.
2. Finish the pack weapon balance: retune Hey Mate (it still runs hot because of its start weapon in `modes.json`), with a before and after table in `docs/BALANCE_TELEMETRY.md`.
3. Landing polish: the page outside the hero band is a flat gradient; the stage slot shows as a brighter window; portrait keeps the old small band; the Australia landing set is at 244 of 250 mesh instances (cap 250).

Done since the last handover: the `docs/TITLE.md` and `docs/CONSTRUCTION_DLC.md` docs (#169), the five-weapon balance pass (#167), and the Backyard BBQ fence camera (#170).

## Known gaps
- Online co-op Arcade is Construction-only.
- Older app builds show pack items as `none` for online players (fixed only in new builds).
- Some Chinese and Japanese wording was reworded for glyph coverage; a font rebuild would let it read better.
- Pack weapons are range-checked and bot-matched, not playtested. Nothing in #149 (monetisation), #161 (ledge/rubble), #170 (fence camera) or the packs has been played on a real device.
- No iPhone frame-time measurements for the 3D landing pages, the transitions or the Hills Hoist shadow.
- The kitchen transition may still not be what the owner wants; ask before redesigning.
- Godot 4.8 is a beta: expect importer or API changes until 4.8 stable, then move the scripts, CI and templates again.

## Owner-only items
Production host and `server.json`, privacy page and Terms, iPhone 12 15-minute soak run, App Store Connect (screenshots, age rating, privacy label, export compliance, demo account), native ad, purchase, share and thermal plugins, a CJK font rebuild, and turning analytics on. (The README version badge is done, #168.)

## DeepSeek tooling
`~/.claude/mcp/deepseek-delegate` runs `dsh --profile headless` (with `enable-credentials.yml`). Give it complete briefs: it cannot see this conversation, and concurrent tasks need separate worktrees (the owner wants them one by one for now).
