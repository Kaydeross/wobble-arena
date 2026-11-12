'use strict';
/* Game modes in Godot (docs/COMBAT_PORTING.md, godot/logic/mode_rules.gd):
   1. parity: the web game's real mode code (tools/modes-reference.js) vs godot/tests/modes_parity_test.gd, every state
      (incl. the Pillars weapon handout and clock: initPillars / pillarGive / updatePillars)
   2. gravity: Moon Drift's gravity 0.15 (cfg.grav) through the real web Fighter.physics (tools/physics-reference.js) on
      its two levels vs godot/tests/physics_test.gd with FighterPhysics.grav_scale 0.15
   3. matches: godot/tests/modes_test.gd plays every ported mode (and the Godot-only tdm / deathmatch / sudden / chaos)
      headless with bots until the match ends by its rule (Pillars, Explosive and Moon Drift too).
   npm run test:godot-modes   (MODES_ONLY=<mode> limits step 2 to one mode) */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const { run, scenario, exactJson } = require('./modes-reference');
const trace = require('./physics-reference');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 180000 });   // registers class_name scripts
const tf = path.join(os.tmpdir(), 'wa-modes-' + process.pid + '.json');
fs.writeFileSync(tf, exactJson(run(scenario())));
let bad = 0;
{                                                  // 2. Moon Drift gravity
  const SHARED = path.join(__dirname, '..', 'shared');
  const CLS = JSON.parse(fs.readFileSync(path.join(SHARED, 'classes.json'), 'utf8'));
  const grav = JSON.parse(fs.readFileSync(path.join(GD, 'data', 'extra', 'modes.json'), 'utf8')).lowg.preset.grav;
  const lines = [];
  let ok = grav === 0.15;
  for (const [map, cid] of [['craterdome', 'wobbler'], ['capsule', 'wobbler'], ['craterdome', 'kid'], ['arena', 'bruiser']]) {
    const gf = path.join(os.tmpdir(), 'wa-grav-' + process.pid + '-' + map + '-' + cid + '.json');
    const t = trace(map, [0, 0.01, 0], CLS[cid], grav);
    fs.writeFileSync(gf, JSON.stringify(t));
    const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/physics_test.gd', '--', path.join(SHARED, 'maps.json'), map, gf, JSON.stringify(CLS[cid]), String(grav)], { encoding: 'utf8', timeout: 60000 });
    fs.unlinkSync(gf);
    const l = (r.stdout + r.stderr).split('\n').find(x => x.startsWith('PHYSICS')) || 'no result';
    const top = Math.max(...t.map(row => row[1]));
    if (!(r.status === 0 && /^PHYSICS/.test(l))) ok = false;
    lines.push('GRAVITY ' + (map + '/' + cid).padEnd(18) + ' grav ' + grav + ' highest ' + top.toFixed(2) + ' m  ' + l);
  }
  console.log('gravity ', ok ? 'ok' : 'FAIL'); for (const l of lines) console.log('  ' + l);
  if (!ok) bad++;
}
const only = process.env.MODES_ONLY ? ['--only=' + process.env.MODES_ONLY] : [];
for (const [name, args, re] of [
  ['parity', ['res://tests/modes_parity_test.gd', '--', path.join(__dirname, '..', 'shared'), tf], /^(MODES|FIRST)/],
  ['matches', ['res://tests/modes_test.gd', '--', '--no-save', ...only], /^(MATCH|SUDDEN|CHAOS|PILLARS|LAVA|LOWG|NODES|MODES|FAIL)/],
]) {
  const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', ...args], { encoding: 'utf8', timeout: 1200000, maxBuffer: 256 * 1024 * 1024 });
  const out = (r.stdout || '') + (r.stderr || '');
  const lines = out.split('\n').filter(l => re.test(l) || /SCRIPT ERROR|Parse Error|leaked/i.test(l));
  const ok = r.status === 0 && lines.length > 0 && !lines.some(l => /SCRIPT ERROR|Parse Error|leaked|^FAIL/i.test(l));
  console.log(name.padEnd(8), ok ? 'ok' : 'FAIL'); for (const l of lines.length ? lines : [out.slice(0, 1500)]) console.log('  ' + l);
  if (!ok) bad++;
}
fs.unlinkSync(tf);
console.log(bad ? 'godot modes test FAILED' : 'godot modes test passes');
process.exit(bad ? 1 : 0);
