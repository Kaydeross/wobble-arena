'use strict';
/* Godot combat effects test: godot/tests/fx_test.gd (headless). Pools stay within their caps on every effects level
   and recycle, a seeded match keeps pools / ribbons / labels capped, and the sim hash is identical with effects on and
   off (effects and hitstop are presentation only). Needs Godot (GODOT env var or the macOS default).
   Run: npm run test:godot-fx */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/fx_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(POOL|MATCH|HASH|FX|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^FX ok/m.test(out) && !/SCRIPT ERROR/m.test(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot fx test FAILED'); process.exit(1); }
console.log('godot fx test passes');
