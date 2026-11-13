'use strict';
/* Construction DLC unit B offline: the generated Building Site (seeds 1..200: schema, counts, spawn clearance, machines >= 6 m
   apart, every platform reachable, determinism), MapBuilder.build('sitegen'), the nine tool models, the PPE (hard hats and the
   hi-vis vest) and a short Construction match on a generated site. Run: npm run test:godot-site-map */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/site_map_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 420000, maxBuffer: 64 << 20 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(SITEMAP|FAIL)/.test(l));
const errs = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
for (const l of errs) console.log('godot:', l);
const ok = r.status === 0 && /^SITEMAP ok/m.test(out) && errs.length === 0;
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot site map test FAILED'); process.exit(1); }
console.log('godot site map test passes');
