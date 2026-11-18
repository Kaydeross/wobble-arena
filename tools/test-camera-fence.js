'use strict';
/* Godot fence-camera test: the follow camera stays inside a walled yard. Run: npm run test:godot-camera-fence */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const sync = spawnSync(process.execPath, [path.join(__dirname, 'sync-shared.js'), '--check'], { encoding: 'utf8' });
process.stdout.write(sync.stdout); process.stderr.write(sync.stderr);
if (sync.status !== 0) process.exit(1);
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/camera_fence_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(CAMERA-FENCE|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^CAMERA-FENCE ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 2000)); console.log('godot camera-fence test FAILED'); process.exit(1); }
console.log('godot camera-fence test passes');
