'use strict';
/* Gun feel: bloom, arm wobble, stacked-hit knockback, net trap length.
   npm run test:godot-gunfeel */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 120000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/gunfeel_test.gd'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(GUNFEEL|FAIL)|SCRIPT ERROR|Parse Error/.test(l));
const ok = r.status === 0 && lines.some(l => /^GUNFEEL/.test(l)) && !lines.some(l => /^FAIL|SCRIPT ERROR|Parse Error/.test(l));
for (const l of lines.length ? lines : [out.slice(0, 1500)]) console.log('  ' + l);
console.log(ok ? 'godot gunfeel test passes' : 'godot gunfeel test FAILED');
process.exit(ok ? 0 : 1);
