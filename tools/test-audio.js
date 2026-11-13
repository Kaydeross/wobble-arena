'use strict';
/* Godot sound effects: the committed WAVs (godot/audio/sfx) must be what tools/render-sfx.js rendered from the web game's
   SoundManager (checked structurally: WAV + sfx.json per name), and the Sfx autoload must have a stream of the right length (sfx.json dur +-10%), a sane peak and play
   every name without errors (godot/tests/audio_test.gd; headless = dummy audio driver).
   npm run test:godot-audio */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');

const chk = spawnSync(process.execPath, [path.join(__dirname, 'render-sfx.js'), '--check'], { encoding: 'utf8' });
console.log(chk.stdout.trim());
let bad = chk.status !== 0;

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
