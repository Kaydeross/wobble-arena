'use strict';
/* Kids mode test (docs/KIDS_MODE.md): godot/tests/kids_test.gd — auto-aim/auto-fire at the nearest enemy in range with
   line of sight (and no fire behind the camera or through a wall), no assist with the setting off, the edge guard,
   half coins and the live Settings toggle + HUD badge. Needs Godot (GODOT env var or the macOS default).
   Run: npm run test:godot-kids */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/kids_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 240000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(KIDS|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^KIDS ok/m.test(out) || /SCRIPT ERROR|^ERROR|Parse Error/.test(out)) {
  if (!lines.length) console.log(out.slice(0, 3000));
  console.log('kids mode test FAILED');
  process.exit(1);
}
console.log('godot kids mode test passes');
