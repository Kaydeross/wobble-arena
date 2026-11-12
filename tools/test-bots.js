'use strict';
/* Bot AI in Godot (docs/COMBAT_PORTING.md, godot/logic/bot_brain.gd):
   1. parity: the web game's real botThink (tools/bots-reference.js) vs godot/tests/bots_parity_test.gd, every decision
   2. smoke: godot/tests/bots_smoke_test.gd: every difficulty plays BOTS_MINUTES (default 12) simulated minutes on three
      maps; self ring-outs and stuck spells under thresholds; prints the AI's cost with 10 bots.
   npm run test:godot-bots   (BOTS_MINUTES=2 for a quick run, BOTS_ONLY=<diff> for one difficulty) */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const { run, scenario, exactJson } = require('./bots-reference');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 180000 });   // registers class_name scripts
const tf = path.join(os.tmpdir(), 'wa-bots-' + process.pid + '.json');
fs.writeFileSync(tf, exactJson(run(scenario())));
const smoke = ['--', '--no-save', '--minutes=' + (process.env.BOTS_MINUTES || 12)];
if (process.env.BOTS_ONLY) smoke.push('--only=' + process.env.BOTS_ONLY);
let bad = 0;
for (const [name, args, re] of [
  ['parity', ['res://tests/bots_parity_test.gd', '--', path.join(__dirname, '..', 'shared'), tf], /^(BOTS|FIRST)/],
  ['smoke', ['res://tests/bots_smoke_test.gd', ...smoke], /^(SMOKE|COST|BOTS-SMOKE|FAIL)/],
]) {
  const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', ...args], { encoding: 'utf8', timeout: 3600000, maxBuffer: 256 * 1024 * 1024 });
  const out = (r.stdout || '') + (r.stderr || '');
  const lines = out.split('\n').filter(l => re.test(l) || /SCRIPT ERROR|Parse Error|leaked/i.test(l));
  const ok = r.status === 0 && lines.length > 0 && !lines.some(l => /SCRIPT ERROR|Parse Error|leaked|^FAIL|^FIRST/i.test(l));
  console.log(name.padEnd(8), ok ? 'ok' : 'FAIL'); for (const l of lines.length ? lines : [out.slice(0, 1500)]) console.log('  ' + l);
  if (!ok) bad++;
}
fs.unlinkSync(tf);
console.log(bad ? 'godot bots test FAILED' : 'godot bots test passes');
process.exit(bad ? 1 : 0);
