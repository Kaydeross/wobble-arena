# Handover: Wobblers Arena, updated 2026-11-21

Read this first, then `docs/REVISED_PLAN.md` (trust the code over the old plan) and `docs/OWNER_RELEASE_RUNBOOK.md`. Repo `Kaydeross/wobble-arena`. Godot 4.8 beta 4 game plus Node relay. iOS first.

## Rules for working
- One branch and one PR per task, off fresh `origin/main`. Use a worktree, never the owner's main checkout (`/Users/kedrosng/Developer/wobble-arena`), which may hold uncommitted edits.
- Parity: gate Godot-only combat and physics behind `Combat.tuning_active()`. Never hand-edit `shared/*.json` or the synced `godot/data/*.json`. Godot-only data goes in `godot/data/extra/` or a pack folder.
- RNG: never call `combat.rng` from visual code; use a local `RandomNumberGenerator`.
- i18n: every `tr()` string in all 5 languages (zh_TW, zh_CN, ja, fr, es) under `godot/i18n/src/*.json`, then `node tools/i18n.js` and `npm run i18n -- --check`. CJK glyphs must be in `tools/cjk-coverage.json`: reword, never edit fonts. On merge conflicts in generated i18n files take theirs, then rerun `node tools/i18n.js`.
- Gates: `npm test` plus the relevant `npm run test:godot-*`, one Godot suite at a time. New `.gd` files create `.uid` files: commit them.
- Never print or paste keys or tokens.

## State (2026-11-21)
- `main` is at the merge of #173 (Godot 4.8 beta 4 until 4.8 stable). It has everything through 0.5.0, unified online combat, podium, spatial audio, share card (#160), ledge cling and rubble (#161), the server wallet and its audit fixes (#171, #172), balance runner (#162, #167) and the three packs (Kitchen `kitchen`, Xmas `xmas`, Australia `australia`; 1500 coins each) with selector, transitions and landing pages (#165).
- No open issues, no open PRs at the time of writing. The checked-in version is 0.5.0; 0.6.0 is the planned verify-and-release train.
- TestFlight: 0.5.0 builds 1 to 4 are uploaded (build 4 has #165). A 0.6.0 version starts its train at `BUILD_NUMBER=1`. Recipe: build with `BUILD_NUMBER=<n> tools/build-ios.sh` from a fresh `origin/main` worktree, then `xcodebuild -exportArchive` with an options plist whose `destination` is `upload`.
- Secret code in release builds works only when the remote flag `tester_unlock` is true (runbook 4.9). Turn it off before the App Store.
- Prop debris sync (offline then online break) is being fixed in a separate thread: do not touch prop or debris code from other work.

## Known gaps
- Online co-op Arcade is Construction-only.
- Older app builds show pack items as `none` for online players (fixed only in new builds): gate with `minimum_version`.
- Some Chinese and Japanese wording was reworded for glyph coverage; a font rebuild would let it read better.
- Pack weapons are range-checked, not playtested. Nothing in #149 (monetisation), #161 (ledge/rubble) or the packs has been played on a real device. No iPhone frame-time numbers for the 3D landing pages, transitions or the Hills Hoist shadow; the iPhone 12 soak has never run.
- Hey Mate has about twice the K.O.s per match of the other packs (Cricket Bat start weapon); bots barely use pack weapons (see `BALANCE_TELEMETRY.md`).
- Landing pages: flat gradient outside the hero band, stage slot reads as a brighter window, portrait uses the old small band, Australia set is at 244 of 250 mesh instances. Ask the owner before redesigning the kitchen transition.
- Engine is a beta: pin 4.8 stable (or decide on 4.7.2) before an App Store build.

## Owner-only items
Production host and `server.json` (still the home NAS), privacy page and Terms, iPhone 12 15-minute soak, App Store Connect (screenshots, age rating, privacy label, export compliance, demo account), native ad, purchase, share and thermal plugins, a CJK font rebuild, turning analytics on.

## Housekeeping (local, look before deleting)
Merged worktrees and branches left over from earlier sprints (`wobble-arena-v06c`, `v06d`, `wobble-ctl/fit/ship/title/wn`, `packB/C/D/E1/E2/E3/F1/F3`, `wobble-arena-work`) and old stashes. `wobble-arena-packF2` (uncommitted balance work) is probably obsolete after #167. `backup/v06e-local-fff305c` only with the owner's agreement.
