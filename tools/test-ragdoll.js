'use strict';
/* Ragdoll overlay test (docs/RAGDOLL.md): sim points unchanged, pose finite and bounded, feet planted, get-up,
   frame-time budget. npm run test:godot-ragdoll */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const gd = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', gd, '--import'], { timeout: 120000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', gd, '--script', 'res://tests/ragdoll_test.gd', '--', path.join(__dirname, '..', 'shared', 'classes.json')], { encoding: 'utf8', timeout: 120000 });
const out = (r.stdout || '') + (r.stderr || '');
for (const l of out.split('\n')) if (/^(RAGDOLL|FAIL)/.test(l)) console.log(l);
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /RAGDOLL_RESULT .* fails=0/.test(out) && errs.length === 0;
console.log(ok ? 'ragdoll test ok' : 'FAIL'); process.exit(ok ? 0 : 1);
