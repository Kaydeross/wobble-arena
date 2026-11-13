'use strict';
/* Godot UI test: the title screen keeps every control inside the safe area and apart at iPhone landscape/portrait
   and desktop sizes; the HUD, touch layer and FPS overlay build and update headless. Needs Godot (GODOT env var or
   the macOS default). Run: npm run test:godot-ui */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
let failed = false;
for (const t of ['ui_layout_test', 'hud_test']) {
  // The full multilingual/resolution matrix now includes the 44 pt Small layout and takes close to
  // five minutes on a cold GitHub runner. Keep the same coverage, but leave headroom for that host.
  const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', `res://tests/${t}.gd`, '--', '--no-save'], { encoding: 'utf8', timeout: 600000 });
  const out = (r.stdout || '') + (r.stderr || '');
  const lines = out.split('\n').filter(l => /^(UI|HUD|FAIL)|ERROR|SCRIPT ERROR/.test(l));
  console.log(lines.join('\n'));
  const ok = r.status === 0 && /^(UI|HUD) ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
  if (!ok) { if (!lines.length) console.log(out.slice(0, 2000)); console.log(`${t} FAILED`); failed = true; }
}
if (failed) process.exit(1);
console.log('godot ui test passes');
