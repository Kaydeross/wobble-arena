'use strict';
/* Godot profile save test (autoload/save.gd): round trip, backup recovery, versioning, web-blob cleaning, coin formula and price parity with public/index.html.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-save */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/save_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 180000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(Save|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^Save ok/m.test(out) || /SCRIPT ERROR|^ERROR/m.test(out)) {
  if (!lines.length) console.log(out.slice(0, 2000));
  console.log('save_test FAILED');
  process.exit(1);
}
console.log('godot save test passes');
