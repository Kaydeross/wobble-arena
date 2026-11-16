'use strict';
/* Pack models and cosmetics test (Kitchen / Xmas / Australia phase B): the 18 pack weapons build bounded models, every pack hat and outfit
   builds on every class, locker.json is consistent and pack-gated. npm run test:godot-pack-models */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const gd = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', gd, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', gd, '--script', 'res://tests/pack_models_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 240000, maxBuffer: 64 << 20 });
const out = (r.stdout || '') + (r.stderr || '');
for (const l of out.split('\n')) if (/^(PACKMODELS|FAIL)/.test(l)) console.log(l);
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /PACKMODELS_RESULT fails=0/.test(out) && errs.length === 0;
console.log(ok ? 'pack models test ok' : 'FAIL'); process.exit(ok ? 0 : 1);
