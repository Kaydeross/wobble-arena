'use strict';
/* Godot pack landing pages test (ui/pack_landing*.gd, data/extra/<pack>/landing.json): builds and frees for the four packs, texts in five
   languages, the weapon showcase, one SubViewport, the particle budget and tiers, and the hub layout at five phone / tablet sizes.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-pack-landing */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot_4.8-beta4.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/pack_landing_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 600000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(PACKLANDING|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^PACKLANDING ok/m.test(out) || isFatal(out)) {
  console.log(`pack-landing_test FAILED (exit ${r.status}, signal ${r.signal || 'none'})`);
  const raw = out.trim().split('\n');
  console.log(raw.slice(-50).join('\n'));      // last lines: on Linux CI this run dies before its summary line
  process.exit(1);
}
console.log('godot pack-landing test passes');
