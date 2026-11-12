'use strict';
/* Weapon models test: every weapon in shared/weapons.json builds (non-empty, sane bounds, Tip marker where the JS has one)
   and can be equipped on a Wobbler for a few frames. npm run test:godot-weapons */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const gd = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', gd, '--import'], { timeout: 120000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', gd, '--script', 'res://tests/weapon_models_test.gd', '--', path.join(__dirname, '..', 'shared', 'weapons.json')], { encoding: 'utf8', timeout: 120000 });
const out = (r.stdout || '') + (r.stderr || '');
for (const l of out.split('\n')) if (/^(WEAPONS|FAIL)/.test(l)) console.log(l);
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /WEAPONS_RESULT fails=0/.test(out) && errs.length === 0;
console.log(ok ? 'weapon models test ok' : 'FAIL'); process.exit(ok ? 0 : 1);
