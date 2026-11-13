'use strict';
/* Construction DLC Unit A data test: tools schema, extra weapons merge, stages, mode isolation, crate pools.
   Run: npm run test:godot-construction-data */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/construction_data_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 240000, maxBuffer: 64 << 20 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(WEAPONS|STAGES|MODES-AND-CRATES|SMOKE|CONSTRUCTION-DATA|FAIL)/.test(l));
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /^CONSTRUCTION-DATA ok/m.test(out) && errs.length === 0;
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot construction data test FAILED'); process.exit(1); }
console.log('godot construction data test passes');
