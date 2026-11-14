'use strict';
/* Godot random-start test: the player begins on a random safe point of every arena (godot/tests/start_spots_test.gd):
   on one of the map's own player / spawns / bots points, on the floor (not inside a solid), at least 2 m from the void,
   facing the middle; 16 matches give more than one spot; random_start = false (and -1 under --no-save) keeps the old
   fixed spot, so the bot-parity run is untouched. Needs Godot (GODOT env var or the macOS default).
   Run: npm run test:godot-start-spots */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/start_spots_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(START-SPOTS|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^START-SPOTS ok/m.test(out) && !isFatal(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot start-spots test FAILED'); process.exit(1); }
console.log('godot start-spots test passes');
