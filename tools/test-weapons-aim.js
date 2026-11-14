'use strict';
/* Weapon use + aim modes: spatula switching (cycle, slot key, touch tile), aim assist on/off, Advanced +25% damage.
   npm run test:godot-weapons-aim */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 120000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/weapons_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(WEAPONS|FAIL)|SCRIPT ERROR|Parse Error/.test(l));
const ok = r.status === 0 && lines.some(l => /^WEAPONS/.test(l)) && !lines.some(l => /^FAIL|SCRIPT ERROR|Parse Error/.test(l));
for (const l of lines.length ? lines : [out.slice(0, 1500)]) console.log('  ' + l);
console.log(ok ? 'godot weapons/aim test passes' : 'godot weapons/aim test FAILED');
process.exit(ok ? 0 : 1);
