'use strict';
/* DLC packs data test (On Fire / Ho Ho Ho / Hey Mate, docs/PACKS_BRIEF.md phase A): manifests, weapons, pack modes and
   crate pools, the 6-stage Arcade tables, unknown stage events, i18n keys in 5 languages, and a smoke match per weapon.
   Run: npm run test:godot-packs-data */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/packs_data_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 360000, maxBuffer: 64 << 20 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(STAGES|I18N|SMOKE|PACKS-DATA|FAIL)/.test(l));
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /^PACKS-DATA ok/m.test(out) && errs.length === 0;
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot packs data test FAILED'); process.exit(1); }
console.log('godot packs data test passes');
