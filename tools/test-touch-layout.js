'use strict';
/* Godot touch-layout test: the player-movable on-screen buttons and the tablet default (godot/input/touch_controls.gd,
   godot/ui/touch_layout_editor.gd). Checks the "{}" layout keeps the stock phone layout, offsets move and clamp inside
   the safe area at 667x375 / 812x375 / 393x852 / 1024x768 / 1366x1024, left-handed mirroring, the roomier tablet
   default, malformed JSON fallback, and the move-buttons editor (drag, Save, Back, Reset). Needs Godot (GODOT env var
   or the macOS default). Run: npm run test:godot-touch-layout (or node tools/test-touch-layout.js) */
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const logPath = path.join(os.tmpdir(), `wobble-touch-layout-${process.pid}.log`);
const logFd = fs.openSync(logPath, 'w');
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/touch_layout_test.gd', '--', '--no-save'], {
  timeout: 300000, stdio: ['ignore', logFd, logFd],
});
fs.closeSync(logFd);
const out = fs.readFileSync(logPath, 'utf8');
fs.unlinkSync(logPath);
const lines = out.split('\n').filter(l => /^(TOUCHLAYOUT|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const fatal = /SCRIPT ERROR|^ERROR: Failed to (load|compile|parse)/m;
const ok = r.status === 0 && /^TOUCHLAYOUT ok/m.test(out) && !fatal.test(out);
if (!ok) {
  if (r.error) console.log(`touch layout: ${r.error.message}`);
  console.log(out.split('\n').slice(-120).join('\n'));
  console.log('godot touch layout test FAILED');
  process.exit(1);
}
console.log('godot touch layout test passes');
