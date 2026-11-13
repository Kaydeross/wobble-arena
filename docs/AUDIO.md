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

# Godot music

The web game's procedural score (`SoundManager.note`: bass, echoed arpeggio, pad, drums that grow with intensity) is
pre-rendered for Godot, like the effects, so iOS pays no synthesis CPU and the web export can use sample playback.

## Rendering: `tools/render-music.js` (`npm run music`)
Boots the web page in Chromium and runs the real scheduler at a fixed mood and intensity through the real bus graph
(music bus at full music volume -> compressor -> limiter) in an `OfflineAudioContext`, then encodes with ffmpeg
(libvorbis q5) to `godot/audio/music/<track>.ogg` (~450 KB for all four) plus `music.json` (mood, intensity, bpm,
bars, seconds) and `<track>.ogg.import` (loop on, tempo metadata, uid kept across re-renders).

| track | mood / intensity | tempo | what you hear |
|---|---|---|---|
| `menu` | menu / 0.1 | 88 bpm | pad, sparse bass, slow arpeggio |
| `match_low` | match / 0.2 | 118 bpm | driving 8th bass, 8th arps, kick |
| `match_mid` | match / 0.5 | 127 bpm | 16th arps, hats, claps |
| `match_high` | match / 0.85 | 137.5 bpm | E-major turnaround, 4-on-the-floor kick, extra hats |

Seamless loops: each loop is 4 bars, rendered twice; the second pass is kept (pad releases and arp echoes from the end
already wrap into its start) and the render just past the loop is crossfaded into its first 2048 samples. Measured wrap
jump: 5-24 (16-bit), below the 99th-percentile sample step of every loop. Chromium's offline render is not bit-exact
between runs, so re-render only when the music changes and commit the new files.

## Runtime: autoload `Music` (`godot/autoload/music.gd`)
- Follows the scene by itself: a scene with a `MatchSim` in `sim` (the world) plays the match loops; `match_over` or
  the results panel is silent; anything else (title, menus, lobby) plays `menu`.
- Match intensity = the web's `musicTick` (`Music.match_intensity`): 0.2, +0.13 per enemy within 14 m (max +0.4),
  +0.2 for 3 s after a hit, +0.15 under 35 % health, +0.15 when someone is one K.O. from the limit; smoothed, then
  tiers with hysteresis (up at 0.38 / 0.70, down at 0.30 / 0.62).
- Changes wait for the playing loop's next bar line and crossfade (0.35 s) into the new loop at the matching bar;
  first start fades in over 1.5 s, stopping fades out over 0.7 s. Two players, no nodes created at runtime.
- "Music" bus -> Master; Settings `music_volume` (default 0.5 = the web `settings.music`), slider in Settings > Audio.
  `muted` mutes Master (autoload Sfx), which silences the music too. Plays under the pause menu; pauses with the app.
- iOS: the loops are ordinary imported resources, so every export (TestFlight included) packs them; they use the same
  Solo Ambient audio session as the effects.
- Tests: `npm run test:godot-music` (`godot/tests/music_test.gd`, in CI) and the Music slider check in
  `ui_layout_test.gd`.
