'use strict';
/* Godot pre-match countdown test (godot/tests/countdown_test.gd): with countdown_force the 3 / 2 / 1 / GO! locks the
   match (the player, the bots and the sim clock all stay put), the fight starts on the GO! frame and then runs
   normally, and a default headless run has no countdown at all. Needs Godot (GODOT env var or the macOS default).
   Run: node tools/test-countdown.js   (add to package.json: "test:godot-countdown": "node tools/test-countdown.js") */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/countdown_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(COUNTDOWN|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^COUNTDOWN ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot countdown test FAILED'); process.exit(1); }
console.log('godot countdown test passes');
