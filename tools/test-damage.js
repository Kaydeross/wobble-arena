'use strict';
/* Body-part damage in Godot (docs/DAMAGE.md): zone geometry, the per-part table on hitscan / knife / arrow / melee /
   splash, and the classic (web-compatible) rule. Classic parity with the JS is test:godot-combat.
   npm run test:godot-damage */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 120000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/damage_test.gd'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(DAMAGE|FAIL)|SCRIPT ERROR|Parse Error/.test(l));
const ok = r.status === 0 && lines.some(l => /^DAMAGE/.test(l)) && !lines.some(l => /^FAIL|SCRIPT ERROR|Parse Error/.test(l));
for (const l of lines.length ? lines : [out.slice(0, 1500)]) console.log('  ' + l);
console.log(ok ? 'godot damage test passes' : 'godot damage test FAILED');
process.exit(ok ? 0 : 1);
