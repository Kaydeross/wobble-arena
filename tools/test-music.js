'use strict';
/* Godot background music (godot/autoload/music.gd + the loops tools/render-music.js renders): runs
   godot/tests/music_test.gd headless. npm run test:godot-music */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 120000 });
const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/music_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 120000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(MUSIC|FAIL)/.test(l));
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
const bad = r.status !== 0 || !/^MUSIC ok/m.test(out) || errs.length;
if (bad && !lines.length) console.log(out.slice(0, 3000));
console.log(bad ? 'godot music test FAILED' : 'godot music test passes');
process.exit(bad ? 1 : 0);
