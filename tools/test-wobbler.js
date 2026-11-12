'use strict';
/* Wobbler (visual character) smoke test: every class built and animated headless through a scripted state sequence;
   checks no errors, no node/material leaks, finite poses and class proportions from shared/classes.json. npm run test:godot-wobbler */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const gd = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', gd, '--import'], { timeout: 120000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', gd, '--script', 'res://tests/wobbler_test.gd', '--', path.join(__dirname, '..', 'shared', 'classes.json')], { encoding: 'utf8', timeout: 120000 });
const out = (r.stdout || '') + (r.stderr || '');
for (const l of out.split('\n')) if (/^(WOBBLER|FAIL)/.test(l)) console.log(l);
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /WOBBLER_RESULT .* fails=0/.test(out) && errs.length === 0;
console.log(ok ? 'wobbler test ok' : 'FAIL'); process.exit(ok ? 0 : 1);
