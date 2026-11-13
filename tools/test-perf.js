'use strict';
/* Godot performance-tools test: PerfStats maths, the readout only exists while its setting is on, and a 10 s soak run
   writes a CSV with the right columns and ends with the summary card (godot/tests/perf_test.gd). The readout-versus-HUD
   layout check is part of test:godot-ui. Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-perf */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/perf_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(PERF|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^PERF ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot perf test FAILED'); process.exit(1); }
console.log('godot perf test passes');
