'use strict';
/* Godot pack selector, pack transition and tester-switch test (ui/pack_selector.gd, ui/pack_transition.gd, DlcUnlock.dev_code_allowed) at the phone / tablet / portrait sizes in five languages.
   Needs Godot (GODOT env var or the macOS default).
   Run: npm run test:godot-pack-selector */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/pack_selector_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 600000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(PACK SELECTOR|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^PACK SELECTOR ok/m.test(out) || isFatal(out)) {
  console.log(`pack_selector_test FAILED (exit ${r.status}, signal ${r.signal || 'none'})`);
  const raw = out.trim().split('\n');
  console.log(raw.slice(-50).join('\n'));      // last lines: on Linux CI this run dies before its summary line
  process.exit(1);
}
console.log('godot pack-selector test passes');
