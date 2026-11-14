'use strict';
/* Destructible environment mode, M1 "all maps" (docs/DESTRUCTIBLE.md): the config overlay in
   godot/data/extra/destructible.json validates against shared/maps.json, normal (off) matches are byte-identical to the
   baseline, and EVERY supported arena map gets ~half of its eligible cover boxes as breakables (seeded per match, same
   seed = same set, another seed = another set). The pick is WEIGHTED to usable cover: close to the map's play centre,
   free-standing (open sides), visible from the surrounding floor and at fighter height - an enclosed or far-corner box
   is almost never chosen, a never-visible one is never chosen while visible cover exists. It never picks ground / roofs /
   boundary walls / stairs / spawns / ladders / pads / enclosed boxes.
   Breakables load with collision and a bright accent frame, a non-breaking hit emits prop_hit (chips + dust + tap sound)
   and advances the visible damage tier, bullets + melee + flame + explosions break them after their hp, a break removes
   the solid / hides the mesh (recycled) / leaves rubble, broken components stay broken, then respawn after the config's
   randomised ~2 minute delay with collision + mesh back (fade-in) and can be broken again through several cycles without
   node leaks. World wiring is tested through the REAL match path: the Setup Wizard toggle writes Settings, the launched
   world reads it, and the world's own player fires the real gun at every selected component until it breaks (break
   reaches the presentation layer, HUD count drops, respawn restores it). Offline gates (Practice Range / Sandbox /
   generated / shrinking levels) hold and a zero-breakable level says "Breakables: 0" in the HUD.
   Needs Godot (GODOT env var or the macOS default). Run: node tools/test-godot-destruct.js
   (add to package.json as: "test:godot-destruct": "node tools/test-godot-destruct.js") */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const sync = spawnSync(process.execPath, [path.join(__dirname, 'sync-shared.js'), '--check'], { encoding: 'utf8' });
process.stdout.write(sync.stdout); process.stderr.write(sync.stderr);
if (sync.status !== 0) process.exit(1);
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 240000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/destruct_test.gd', '--', '--no-save'],
  { encoding: 'utf8', timeout: 600000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(DESTRUCT|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n') || out.slice(0, 2000));
// "ERROR: Destruct: <config problem>" is the intentionally provoked fail-safe path (the test proves a bad config adds no
// props and never breaks the match); any other script error / engine error still fails the run.
const unexpected = out.split('\n').some(l => /SCRIPT ERROR/.test(l) || (/^ERROR/.test(l) && !/^ERROR: Destruct: /.test(l)));
const ok = r.status === 0 && /^DESTRUCT ok/m.test(out) && !unexpected;
if (!ok) { console.log('godot destruct test FAILED'); process.exit(1); }
console.log('godot destruct test passes');
