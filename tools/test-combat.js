'use strict';
/* The Godot combat port must reproduce the web game's combat. Runs the real JS (tools/combat-reference.js) over the scripted
   scenario, replays it in Godot (godot/tests/combat_test.gd) and compares every state; then the NetSnapshot round-trip test.
   npm run test:godot-combat */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const { run, scenario, exactJson } = require('./combat-reference');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 120000 });   // registers class_name scripts
const tf = path.join(os.tmpdir(), 'wa-combat-' + process.pid + '.json');
fs.writeFileSync(tf, exactJson(run(scenario())));
let bad = 0;
for (const [name, args, re] of [
  ['parity', ['res://tests/combat_test.gd', '--', path.join(__dirname, '..', 'shared'), tf], /^(COMBAT|NET|FIRST)/],
  ['netsnap', ['res://tests/net_snapshot_test.gd'], /^(NETSNAP|FAIL)/],
]) {
  const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', ...args], { encoding: 'utf8', timeout: 300000 });
  const out = (r.stdout || '') + (r.stderr || '');
  const lines = out.split('\n').filter(l => re.test(l) || /SCRIPT ERROR|Parse Error/.test(l));
  const ok = r.status === 0 && lines.length > 0 && !lines.some(l => /SCRIPT ERROR|Parse Error/.test(l));
  console.log(name.padEnd(8), ok ? 'ok' : 'FAIL'); for (const l of lines.length ? lines : [out.slice(0, 600)]) console.log('  ' + l);
  if (!ok) bad++;
}
fs.unlinkSync(tf);
process.exit(bad ? 1 : 0);
