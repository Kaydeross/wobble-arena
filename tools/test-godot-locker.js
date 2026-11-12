'use strict';
/* Godot Locker / Shop / emotes test: buy and equip rules, the Locker and Shop screen flow, Wobbler emotes, the in-match emote button and the results rewards.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-locker */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/locker_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 180000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(Locker|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^Locker ok/m.test(out) || /SCRIPT ERROR|^ERROR/m.test(out)) {
  if (!lines.length) console.log(out.slice(0, 2000));
  console.log('locker_test FAILED');
  process.exit(1);
}
console.log('godot locker test passes');
