'use strict';
/* Controls profile + Controls screen + interactive training test (godot/tests/tutorial_test.gd): the profile per platform and
   its live switching, labels read from the real bindings (rebind and the label changes), the Controls screen shows only the
   active scheme with a Touch | Keyboard | Gamepad switch, the training advances only on the real input for keyboard, gamepad and
   touch (and follows a mid-training device switch, Skip, Replay, Exit), saves nothing, the one-time offer and the HUD hint.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-tutorial */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot_4.8-beta4.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/tutorial_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(TUTORIAL|FAIL|NODES)|ERROR|SCRIPT ERROR|Parse Error/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^TUTORIAL ok/m.test(out) && !isFatal(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 4000)); console.log('godot tutorial test FAILED'); process.exit(1); }
console.log('godot tutorial test passes');
