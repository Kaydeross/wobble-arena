'use strict';
/* Game modes in Godot (docs/COMBAT_PORTING.md, godot/logic/mode_rules.gd):
   1. parity: the web game's real mode code (tools/modes-reference.js) vs godot/tests/modes_parity_test.gd, every state
   2. matches: godot/tests/modes_test.gd plays every ported mode headless with bots until the match ends by its rule.
   npm run test:godot-modes   (MODES_ONLY=<mode> limits step 2 to one mode) */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const { run, scenario, exactJson } = require('./modes-reference');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 180000 });   // registers class_name scripts
const tf = path.join(os.tmpdir(), 'wa-modes-' + process.pid + '.json');
fs.writeFileSync(tf, exactJson(run(scenario())));
let bad = 0;
const only = process.env.MODES_ONLY ? ['--only=' + process.env.MODES_ONLY] : [];
for (const [name, args, re] of [
  ['parity', ['res://tests/modes_parity_test.gd', '--', path.join(__dirname, '..', 'shared'), tf], /^(MODES|FIRST)/],
  ['matches', ['res://tests/modes_test.gd', '--', '--no-save', ...only], /^(MATCH|NODES|MODES|FAIL)/],
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
