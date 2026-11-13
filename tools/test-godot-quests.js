'use strict';
/* Godot coin goals test (logic/quests.gd, the save "quests" key, the results line, the Goals screen).
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-quests */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/quests_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 180000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(Quests|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^Quests ok/m.test(out) || /SCRIPT ERROR|^ERROR/m.test(out)) {
  if (!lines.length) console.log(out.slice(0, 2000));
  console.log('quests_test FAILED');
  process.exit(1);
}
console.log('godot quests test passes');
