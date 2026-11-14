# Godot sound effects

The web game has no audio files: `public/index.html` synthesizes every effect and its music at runtime with the
layered `SoundManager` (WebAudio; `docs/CODEMAP.md` section 2). The Godot client plays 33 pre-rendered effects
(the `NAMES` in `godot/autoload/audio.gd`) rendered from that same engine. Twelve of those names were not rendered
for Godot before: `hover`, `jump`, `dash`, `land`, `step` and `ko` were already in the web `SOUNDS` table but unused
by its gameplay, and `fall`, `respawn`, `countdown`, `win`, `lose`, `lowhp` are new Godot-only recipes added to
`SOUNDS` as data (the web game's own gameplay never calls them).

## Approach: pre-rendered WAVs from the real engine
`tools/render-sfx.js` (`npm run sfx`) boots the web page in Playwright's Chromium (like `tools/render-music.js`),
builds a `SoundManager` whose `init()` is given a stereo 44.1 kHz `OfflineAudioContext`, and plays each `SOUNDS` entry
through the real graph (sfx bus -> master -> compressor -> limiter). Master volume is 1 (Godot applies the player's
volume). Per sound:

- `Math.random` is seeded and the entry's `vary` is set to 0 during the render, so the WAV is the centre pitch.
- The sound is played with `{ delay: 0.5 }` and the output is cut from the voice start (0.5 s + the 0.005 s in the
  `SndVoice` constructor): Chromium's compressor misbehaves for sounds at the very start of an offline render.
- The stereo render is downmixed to mono ((L + R) / 2) and the tail is trimmed once the signal stays below 1e-4
  (20 ms are kept after the last louder sample).
- Output: `godot/audio/sfx/<name>.wav` (16-bit, 44.1 kHz mono, imported as uncompressed PCM) and
  `godot/audio/sfx/sfx.json` = `{name: {dur, peak}}` (seconds, peak amplitude), which `tools/test-audio.js` hands to the
  Godot test as the expected lengths.

Why not `AudioStreamGenerator` at runtime: the sounds are fixed once pitch variation is dropped, so rendering them once
gives identical output on iOS, PC and web, costs no CPU per hit, works with the web export's sample playback (generators
are stream-only there and need the main thread to keep the buffer full) and keeps the runtime a plain player pool.

Chromium's offline render is not bit-exact between runs, so a re-render differs by tiny amounts and
`node tools/render-sfx.js --check` verifies structure only: every name has a WAV and an `sfx.json` entry, and the WAV
length matches `dur` within 1 ms. Change a sound in `public/index.html` -> run `npm run sfx` and commit the WAVs and
`sfx.json`. Needs Chromium (`CHROME_PATH` to use a specific binary).

## Runtime: autoload `Sfx` (`godot/autoload/audio.gd`)
- `Sfx.play(name, volume := 1.0, priority := -1)`: 12 pre-made `AudioStreamPlayer`s, round robin over idle ones.
  No allocation per call. Unknown names are ignored (like JS `sfx('thunder')`).
- Every play gets a small random pitch (`+-4 %`) and volume (`+-1.5 dB`) shift with a private RNG, so a burst of
  the same effect does not sound like one sample played by a machine. The game's own RNG stream is never touched.
- When all 12 players are busy, an incoming sound may only cut a player whose priority is the same or lower. Ordinary
  fire is priority 0, so it can never swallow `boom`, `ko`, `win`, `lose` (2) or `rocket`, `sniper`, `mammoth`, `fall`,
  `respawn`, `countdown`, `lowhp` (1); if every slot is taken by something at least as important the new sound is
  dropped instead (the same rule as the web engine's `pri`).
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
| dash / air recover (a `swing` with no swing animation) | `sfx` (Combat) | dash |
| knife throw / knife hits wall or fighter | `sfx` (Weapons) | swing / clink |
| `fire` (one sound per 0.07 s for fast guns) | `shot` | shot, shotgun, mammoth, sniper or whack |
| `updatePads` | `pad` | bounce |
| `spawnDrop` / crate lands | `crate` / `crate_land` | drop / clink |
| weapon or ammo pickup, heal / power-up crate (player) | `pickup` / `crate_take` | pickup |
| reload (player) | `reload` | mag (shell guns: shellIn) |
| respawn (player) | `respawn` | respawn |
| the player's own movement (presentation state, `World._audio_motion`) | — | jump / land / step |

Big-moment cues (all wired in `world/world.gd` unless noted):
- K.O. involving the player -> `ko` (a ring-out / fall off the map -> `fall`); player respawn -> `respawn`.
- Pre-match 3-2-1 -> `countdown` per number plus a "GO!" banner (`World._update_countdown`; presentation only, the sim
  is never frozen by it).
- Results screen -> `win` / `lose`, under a calm `menu` loop (see below).
- Under 25 % health -> `lowhp` heartbeat about once a second, from `ui/hud.gd` (no new setting; stops on heal/death).
- `ui/juicy_button.gd` -> a soft `click` on press for every JuicyButton.

Haptics (autoload `Haptics`, `godot/autoload/haptics.gd`, Settings > Audio "Haptics"): `FxSystem` calls
`Haptics.hit()` for a hit the player lands, `Haptics.hurt()` when the player is hit, and `Haptics.heavy()` for a K.O.
involving the player and for an explosion within ~14 m; the K.O./explosion also calls `Music.duck()`. Android plays
the requested 25 / 55 / 120 ms; iOS only plays its fixed system vibrate for the heavy moments (the light/medium
weights are skipped there rather than turning every hit into a full buzz).

Not hooked yet because the Godot port has no matching event: the later reload-phase clicks, flame, bow, boomerang,
emotes, shop/UI hover.

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
- Follows the scene by itself: a scene with a `MatchSim` in `sim` (the world) plays the match loops; once the match
  is over or the results panel is up it settles into the calm `menu` loop (the results screen is never silent);
  anything else (title, menus, lobby) plays `menu`.
- `Music.duck(db, seconds)`: a short negative-offset envelope on the Music bus added on top of `music_volume`, easing
  back over its last 0.12 s. `FxSystem` ducks by -6 dB for 0.5 s on a K.O. involving the player and by -5 dB for
  0.35 s on an explosion within ~14 m, so the sting / boom reads without stopping the track.
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
