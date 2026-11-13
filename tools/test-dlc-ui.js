'use strict';
/* Godot Construction DLC UI test (dlc/construction/*: DlcUnlock, the hub, the title banner, the code field, the layout
   at the iPhone / iPad sizes in English, French and Japanese). Needs Godot (GODOT env var or the macOS default).
   Run: npm run test:godot-dlc-ui */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/dlc_ui_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 600000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(DLC UI|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^DLC UI ok/m.test(out) || /SCRIPT ERROR|^ERROR/m.test(out)) {
  if (!lines.length) console.log(out.slice(0, 3000));
  console.log('dlc_ui_test FAILED');
  process.exit(1);
}
console.log('godot dlc ui test passes');
