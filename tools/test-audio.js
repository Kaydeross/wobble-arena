'use strict';
/* Godot sound effects: the committed WAVs (godot/audio/sfx) must be what tools/render-sfx.js rendered from the web game's
   SoundManager (checked structurally: WAV + sfx.json per name), and the Sfx autoload must have a stream of the right length (sfx.json dur +-10%), a sane peak and play
   every name without errors (godot/tests/audio_test.gd; headless = dummy audio driver). The spatial wiring (Sfx.play_at,
   the bounded 3D pool, the world-event routing and the Settings toggle) is checked statically here and behaviourally in
   the Godot suite (docs/AUDIO.md "Spatial sound").
   npm run test:godot-audio */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot_4.8-beta4.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');

const chk = spawnSync(process.execPath, [path.join(__dirname, 'render-sfx.js'), '--check'], { encoding: 'utf8' });
console.log(chk.stdout.trim());
let bad = chk.status !== 0;

// The positional twin stays wired up: the autoload offers it, its pool is bounded and lazily built, every routed match
// cue goes through it, and Settings > Audio still offers the switch (the behavioural checks are in audio_test.gd).
const gdFile = f => fs.readFileSync(path.join(GD, f), 'utf8');
for (const [file, re, what] of [
  ['autoload/audio.gd', /func play_at\(sfx_name: String, world_pos: Vector3/, 'Sfx.play_at(name, world_pos, volume)'],
  ['autoload/audio.gd', /const POOL_3D := \d+/, 'a bounded 3D pool'],
  ['autoload/audio.gd', /func _emit\([\s\S]*?play_at\(/, 'world-event routing through play_at'],
  ['autoload/settings.gd', /"sfx_3d": true/, 'the sfx_3d default'],
  ['ui/settings_screen.gd', /_toggle\("sfx_3d", "3D sound"/, 'the Settings > Audio "3D sound" toggle'],
]) if (!re.test(gdFile(file))) { console.log(`audio: missing ${what} in godot/${file}`); bad = true; }

const meta = JSON.parse(fs.readFileSync(path.join(GD, 'audio', 'sfx', 'sfx.json'), 'utf8')), expected = {};
for (const [n, m] of Object.entries(meta)) expected[n] = { dur: m.dur };
const tf = path.join(os.tmpdir(), 'wa-audio-' + process.pid + '.json');
fs.writeFileSync(tf, JSON.stringify(expected));

spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 120000 });
const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/audio_test.gd', '--', '--no-save', tf], { encoding: 'utf8', timeout: 120000 });
fs.unlinkSync(tf);
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(SFX|AUDIO|FAIL)/.test(l));
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
if (r.status !== 0 || !/^AUDIO ok/m.test(out) || errs.length) { if (!lines.length) console.log(out.slice(0, 3000)); bad = true; }
console.log(bad ? 'godot audio test FAILED' : 'godot audio test passes');
process.exit(bad ? 1 : 0);
