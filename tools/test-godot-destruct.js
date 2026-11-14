'use strict';
/* Destructible environment mode, milestone M0 (docs/DESTRUCTIBLE.md): the authoring overlay in godot/data/extra/destructible.json
   validates against shared/maps.json, normal (off) matches are byte-identical to the baseline, and on the three authored arenas
   props load with collision, bullets and explosions break them after their hp, a break removes the solid / frees the mesh /
   leaves rubble, broken props stay broken, a fresh load_map rebuilds them, and the World wiring + offline mode gates hold.
   Needs Godot (GODOT env var or the macOS default). Run: node tools/test-godot-destruct.js
   (add to package.json as: "test:godot-destruct": "node tools/test-godot-destruct.js") */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const sync = spawnSync(process.execPath, [path.join(__dirname, 'sync-shared.js'), '--check'], { encoding: 'utf8' });
process.stdout.write(sync.stdout); process.stderr.write(sync.stderr);
if (sync.status !== 0) process.exit(1);
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/destruct_test.gd', '--', '--no-save'],
  { encoding: 'utf8', timeout: 180000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(DESTRUCT|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n') || out.slice(0, 2000));
const ok = r.status === 0 && /^DESTRUCT ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
if (!ok) { console.log('godot destruct test FAILED'); process.exit(1); }
console.log('godot destruct test passes');
