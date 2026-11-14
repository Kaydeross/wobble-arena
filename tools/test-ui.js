'use strict';
/* Godot UI test: the title screen keeps every control inside the safe area and apart at iPhone landscape/portrait
   and desktop sizes; the HUD, touch layer and FPS overlay build and update headless. Needs Godot (GODOT env var or
   the macOS default). Run: npm run test:godot-ui */
const { spawnSync } = require('child_process');
require('./ensure-fresh')();
const fs = require('fs');
const os = require('os');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
let failed = false;
for (const t of ['ui_layout_test', 'hud_test', 'enemy_indicators_test']) {
  // The full multilingual/resolution matrix now includes the 44 pt Small layout and takes close to
  // five minutes on a cold GitHub runner. Keep the same coverage, but leave headroom for that host.
  const logPath = path.join(os.tmpdir(), `wobble-${t}-${process.pid}.log`);
  const logFd = fs.openSync(logPath, 'w');
  const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', `res://tests/${t}.gd`, '--', '--no-save'], {
    timeout: 600000, stdio: ['ignore', logFd, logFd],
  });
  fs.closeSync(logFd);
  const out = fs.readFileSync(logPath, 'utf8');
  fs.unlinkSync(logPath);
  const lines = out.split('\n').filter(l => /^(UI|HUD|FAIL)|ERROR|SCRIPT ERROR/.test(l));
  console.log(lines.slice(-160).join('\n'));
  // Godot's headless font cache can report shutdown-only resource counts after a successful
  // test. Treat those as diagnostics; only parser/load failures invalidate the run.
  const fatal = /SCRIPT ERROR|^ERROR: Failed to (load|compile|parse)/m;
  const ok = r.status === 0 && /^(UI|HUD) ok/m.test(out) && !fatal.test(out);
  if (!ok) {
    if (r.error) console.log(`${t}: ${r.error.message}`);
    console.log(out.split('\n').slice(-120).join('\n'));
    console.log(`${t} FAILED`);
    failed = true;
  }
}
if (failed) process.exit(1);
console.log('godot ui test passes');
