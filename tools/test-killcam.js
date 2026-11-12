'use strict';
/* Godot kill-cam test (world/kill_cam.gd): ring-buffer recording, a fast K.O. starts a side-on slow-mo replay, the match
   is frozen meanwhile, the camera ends back on the follow camera, tap to skip, cooldown / setting / team modes.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-killcam */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/killcam_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(KC|KILLCAM|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^KILLCAM ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 2000)); console.log('godot kill cam test FAILED'); process.exit(1); }
console.log('godot kill cam test passes');
