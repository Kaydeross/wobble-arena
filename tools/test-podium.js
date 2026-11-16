'use strict';
/* Godot winner podium test (world/winner_podium.gd + world/world.gd, run by npm run test:godot-podium):
   the results moment builds a 3D podium with every fighter on it in the results' own order (the match winner, or the
   whole winning team, first; then K.O.s and damage), only the winners are asked to play the victory emote, the camera
   eases onto a framing shot, the results panel still shows, the podium is skipped in tutorial / trial / sandbox and in
   headless runs, and there are no node leaks. Needs Godot (GODOT env var or the macOS default). */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/podium_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 120000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(PODIUM|NODES|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^PODIUM ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out) && !/^FAIL/m.test(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 2000)); console.log('godot podium test FAILED'); process.exit(1); }
console.log('godot podium test passes');
