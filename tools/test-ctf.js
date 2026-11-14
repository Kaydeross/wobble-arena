'use strict';
/* Capture the Flag in Godot (godot/logic/ctf.gd, godot/world/ctf_view.gd, godot/tests/ctf_test.gd): the flag stand is on the
   floor near the middle of every CTF map, pickup, the 30 s hold win, the drop on a K.O. (and its lock), the ring-out return,
   the 5:00 fallback clock (total hold time, then K.O.s, then a loss for the player's team), bots that take the flag and finish
   whole matches on their own, the wizard card, and the mode being offline only (never hosted).
   Needs Godot (GODOT env var or the macOS default).   Run: npm run test:godot-ctf */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/ctf_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(CTF|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^CTF ok/m.test(out) && !isFatal(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot ctf test FAILED'); process.exit(1); }
console.log('godot ctf test passes');
