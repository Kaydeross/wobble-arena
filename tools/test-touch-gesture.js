'use strict';
/* Godot touch-layer regression test: a missed finger release, a reused finger index, focus loss / cancelled touches
   and the orphan sweep must not leave an action held (godot/tests/touch_test.gd). Needs Godot (GODOT env var or the
   macOS default). Run: npm run test:godot-touch */
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const logPath = path.join(os.tmpdir(), `wobble-touch-${process.pid}.log`);
const logFd = fs.openSync(logPath, 'w');
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/touch_test.gd', '--', '--no-save'], {
  timeout: 180000, stdio: ['ignore', logFd, logFd],
});
fs.closeSync(logFd);
const out = fs.readFileSync(logPath, 'utf8');
fs.unlinkSync(logPath);
const lines = out.split('\n').filter(l => /^(TOUCH|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const fatal = /SCRIPT ERROR|^ERROR: Failed to (load|compile|parse)/m;
const ok = r.status === 0 && /^TOUCH ok/m.test(out) && !fatal.test(out);
if (!ok) {
  if (r.error) console.log(`touch: ${r.error.message}`);
  console.log(out.split('\n').slice(-120).join('\n'));
  console.log('godot touch test FAILED');
  process.exit(1);
}
console.log('godot touch test passes');
