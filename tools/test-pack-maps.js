'use strict';
/* DLC packs phase C offline: the Kitchen, Xmas and Australia procedural arenas (seeds 1..8: schema, box budget, spawns on walkable
   floor and off hazards, SiteNav flood fill, hazards, ice gating, stage events, 20 s bot matches). Run: npm run test:godot-pack-maps */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot_4.8-beta4.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/pack_maps_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 420000, maxBuffer: 64 << 20 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(PACKMAPS|FAIL)/.test(l));
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /^PACKMAPS ok/m.test(out) && errs.length === 0;
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot pack maps test FAILED'); process.exit(1); }
console.log('godot pack maps test passes');
