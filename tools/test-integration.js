'use strict';
/* Godot offline vertical slice: a headless 30 s match on 'arena' (scripted player + 3 bots, crates, SMG) with
   checks for K.O./respawn, HP range, finite positions and node leaks. Run: npm run test:godot-integration */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/integration_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 240000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(MATCH|FIGHTER|NODES|INTEGRATION|FAIL)/.test(l));
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /^INTEGRATION ok/m.test(out) && errs.length === 0;
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot integration test FAILED'); process.exit(1); }
console.log('godot integration test passes');
