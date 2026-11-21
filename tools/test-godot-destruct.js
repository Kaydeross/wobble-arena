'use strict';
/* Destructible environment mode, M1 "all maps" (docs/DESTRUCTIBLE.md): the config overlay in
   godot/data/extra/destructible.json validates against shared/maps.json, normal (off) matches are byte-identical to the
   baseline, and EVERY supported arena map gets ~half of its eligible cover boxes as breakables (seeded per match, same
   seed = same set, another seed = another set). The pick is WEIGHTED to usable cover: close to the map's play centre,
   free-standing (open sides), visible from the surrounding floor and at fighter height - an enclosed or far-corner box
   is almost never chosen, a never-visible one is never chosen while visible cover exists. It never picks ground / roofs /
   boundary walls / stairs / spawns / ladders / pads / enclosed boxes.
   Breakables are part of every offline arena match (no option) and look exactly like the map's own boxes (no accent
   frame); decor on a trunk (a tree crown) is lifted out of the merged decor and goes with it. They load with collision,
   a non-breaking hit emits prop_hit (chips + dust + tap sound) and advances the visible damage tier, bullets + melee +
   flame + explosions break them after their hp, a break removes the solid / hides the mesh (recycled) and shatters
   into debris pieces that sink into the ground, broken components stay broken, then respawn after the config's
   randomised ~2 minute delay with collision + mesh back (fade-in) and can be broken again through several cycles without
   node leaks. They run together with a moving floor (never a drifting block). World wiring is tested through the REAL
   match path: the world's own player fires the real gun at every selected component until it breaks (break reaches the
   presentation layer, respawn restores it). Offline gates (Practice Range / Sandbox / generated / shrinking levels) hold.
   Needs Godot (GODOT env var or the macOS default). Run: node tools/test-godot-destruct.js
   (add to package.json as: "test:godot-destruct": "node tools/test-godot-destruct.js") */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot_4.8-beta4.app/Contents/MacOS/Godot';
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
// PropDebris is visible and sane (tests/prop_debris_test.gd): pieces exist, are visible, in bounds, above ground, then sink away
const r2 = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/prop_debris_test.gd', '--', '--no-save'],
  { encoding: 'utf8', timeout: 600000 });
const out2 = (r2.stdout || '') + (r2.stderr || '');
console.log(out2.split('\n').filter(l => /^(PROPDEBRIS|FAIL)|SCRIPT ERROR/.test(l)).join('\n'));
if (r2.status !== 0 || !/^PROPDEBRIS ok/m.test(out2) || /SCRIPT ERROR/.test(out2)) { console.log('prop debris test FAILED'); process.exit(1); }
// Ledge cling + throwable rubble (docs/DAMAGE.md "Ledge cling and throwable rubble"; tests/ledge_rubble_test.gd)
const r3 = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/ledge_rubble_test.gd', '--', '--no-save'],
  { encoding: 'utf8', timeout: 600000 });
const out3 = (r3.stdout || '') + (r3.stderr || '');
console.log(out3.split('\n').filter(l => /^(LEDGE_RUBBLE|FAIL)|SCRIPT ERROR/.test(l)).join('\n'));
if (r3.status !== 0 || !/^LEDGE_RUBBLE ok/m.test(out3) || /SCRIPT ERROR/.test(out3)) { console.log('ledge/rubble test FAILED'); process.exit(1); }
// Online breakable cover (docs/PROTOCOL.md 6.5; tests/net_destruct_test.gd: host + guest Worlds in one process)
const r4 = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/net_destruct_test.gd', '--', '--no-save'],
  { encoding: 'utf8', timeout: 600000 });
const out4 = (r4.stdout || '') + (r4.stderr || '');
console.log(out4.split('\n').filter(l => /^(NETDESTRUCT|FAIL)|SCRIPT ERROR/.test(l)).join('\n'));
if (r4.status !== 0 || !/^NETDESTRUCT ok/m.test(out4) || /SCRIPT ERROR/.test(out4)) { console.log('online destruct test FAILED'); process.exit(1); }
console.log('godot destruct test passes');
