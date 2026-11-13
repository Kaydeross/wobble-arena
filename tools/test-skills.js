'use strict';
/* Balance overlay, weapon burst pools, swap draw time and the air recovery (docs/DAMAGE.md "Balance and cooldowns").
   npm run test:godot-skills */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 120000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/skills_test.gd'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(SKILLS|FAIL)|SCRIPT ERROR|Parse Error/.test(l));
const ok = r.status === 0 && lines.some(l => /^SKILLS/.test(l)) && !lines.some(l => /^FAIL|SCRIPT ERROR|Parse Error/.test(l));
for (const l of lines.length ? lines : [out.slice(0, 1500)]) console.log('  ' + l);
console.log(ok ? 'godot skills test passes' : 'godot skills test FAILED');
process.exit(ok ? 0 : 1);
