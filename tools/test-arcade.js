'use strict';
/* Construction DLC Arcade boss rush, headless: a scripted player clears all six stages through the real ArcadeManager,
   lives / retry / run over, the stage events and boss phases, coins once per first clear, the saved records and the Site
   Foreman hat, and that a Classic match afterwards is unaffected. Needs Godot (GODOT env var or the macOS default).
   Run: npm run test:godot-arcade */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/arcade_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 900000, maxBuffer: 64 << 20 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(FULL RUN|NODES|ARCADE|FAIL)/.test(l));
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /^ARCADE ok/m.test(out) && errs.length === 0;
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot arcade test FAILED'); process.exit(1); }
console.log('godot arcade test passes');
