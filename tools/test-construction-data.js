'use strict';
/* Construction DLC Unit A data test: tools schema, extra weapons merge, stages, mode isolation, crate pools, and the DLC
   pack manifest (pack.json: registry, byte-equal legacy merge, malformed manifests under user://, reload).
   Run: npm run test:godot-construction-data */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot_4.8-beta4.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/construction_data_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 240000, maxBuffer: 64 << 20 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(WEAPONS|STAGES|MODES-AND-CRATES|PACKS|JSON-CACHE|PARSES|SMOKE|CONSTRUCTION-DATA|FAIL)/.test(l));
// The pack test deliberately scans a malformed synthetic tree under user://: Godot's JSON parser prints
// "ERROR: Parse JSON failed..." and the loader push_error prints "ERROR: Content: ..." for exactly those manifests. They
// are the behaviour under test, so they are expected here; a real shipped-pack failure is still caught by the test's own
// assertions (registry, section paths, byte-equal tables -> FAIL lines + exit code), not by this whitelist.
const expectedLoaderDiagnostic = /^ERROR: (Parse JSON failed|Content: )/;
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l) && !expectedLoaderDiagnostic.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /^CONSTRUCTION-DATA ok/m.test(out) && errs.length === 0;
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot construction data test FAILED'); process.exit(1); }
console.log('godot construction data test passes');
