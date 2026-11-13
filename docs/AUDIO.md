# Godot sound effects

The web game has no audio files: `public/index.html` synthesizes every effect and its music at runtime with the
layered `SoundManager` (WebAudio; `docs/CODEMAP.md` section 2). The Godot client plays 21 pre-rendered effects made
from the web game's original, simpler `tone` / `noise` recipes, frozen in `tools/sfx-recipes.js`.

## Approach: pre-rendered WAVs
`tools/render-sfx.js` (`npm run sfx`) slices the `SFX` table out of `tools/sfx-recipes.js`, runs each recipe with an
offline, sample-by-sample version of the WebAudio nodes it uses and writes `godot/audio/sfx/<name>.wav` (16-bit,
44.1 kHz mono, ~550 KB for all 21, imported as uncompressed PCM).

Why not `AudioStreamGenerator` at runtime: the recipes are fixed (no per-call parameters), so rendering them once gives
identical output on iOS, PC and web, costs no CPU per hit, works with the web export's sample playback (generators
are stream-only there and need the main thread to keep the buffer full) and keeps the runtime a plain player pool.
Fidelity is not a problem because the renderer models the nodes directly:

- `tone`: band-limited oscillator (Fourier series of WebAudio's sine/triangle/square/sawtooth, normalised to peak 1
  like the built-in waves, harmonics up to Nyquist), exponential frequency ramp `f0 -> max(20, f1)` over `dur`, gain
  `vol -> 0.001` exponential ramp, stop at `dur + 0.03`, optional `delay`.
- `noise`: the 0.7 s white-noise buffer through a lowpass biquad (Q = 1 dB, the spec's cookbook formulas), same gain
  envelope. JS starts the buffer at a random 0..0.3 s offset; the render uses 0.15 s and a seeded generator so the
  output is deterministic (`node tools/render-sfx.js --check` verifies the committed files).
- Mixed through the master gain 0.9 (the JS `0.9 * settings.vol`; the volume part is applied by Godot) and clamped
  to +-1 like the browser's output (nothing clips; the loudest, `boom`, peaks at 0.70).

Change a recipe in `tools/sfx-recipes.js` -> run `npm run sfx` and commit the WAVs; `npm run test:godot-audio` fails until then.

## Runtime: autoload `Sfx` (`godot/autoload/audio.gd`)
- `Sfx.play(name, volume := 1.0)`: 12 pre-made `AudioStreamPlayer`s, round robin over idle ones, the oldest is cut
  when all are busy; no allocation per call. Unknown names are ignored (like JS `sfx('thunder')`).
- Settings keys `volume` (default 0.5 = web `settings.vol`) -> Master bus volume; `muted` mutes the bus and skips play.
- iOS: `audio/general/ios/session_category` = Solo Ambient (honours the silent switch), `mix_with_others` = false.
  CoreAudio reactivates the session after interruptions; `Sfx` stops half-played sounds and re-applies the bus on
  `APPLICATION_RESUMED` / `FOCUS_IN`, and on the first touch/click/key (the web AudioContext needs a user gesture).
- `Sfx.on_event(e, sim)` maps match events to sounds; `World._drain_events` passes every event through it.

| JS call site | Godot event | sound |
|---|---|---|
| `topple` | `sfx` (Combat) | boing |
| kick lean / kick connects | `sfx` (Combat) | kick / whack |
| melee swing / melee hit (`hitSfx`) | `sfx` (Combat) | swing / clink or whack |
| knife throw / knife hits wall or fighter | `sfx` (Weapons) | swing / clink |
| `fire` (one sound per 0.07 s for fast guns) | `shot` | shot, shotgun, mammoth, sniper or whack |
| `updatePads` | `pad` | bounce |
| `spawnDrop` / crate lands | `crate` / `crate_land` | drop / clink |
| weapon or ammo pickup, heal / power-up crate (player) | `pickup` / `crate_take` | pickup |
| reload (player) | `reload` | mag (shell guns: shellIn) |

Not hooked yet because the Godot port has no matching event: the later reload-phase clicks, flame, rocket/boom, bow,
boomerang, emotes, shop/UI clicks, match end. The JS has no jump/land or K.O. sound.

Test: `npm run test:godot-audio` (`tools/test-audio.js` + `godot/tests/audio_test.gd`).
