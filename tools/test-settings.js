'use strict';
/* Godot server-default test (Settings.server_default, Reset to default, wss -> https). Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-settings */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/server_default_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(SERVERDEFAULT|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^SERVERDEFAULT ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 2000)); console.log('godot server default test FAILED'); process.exit(1); }
console.log('godot server default test passes');
