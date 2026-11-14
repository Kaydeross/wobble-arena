'use strict';
/* Godot reset-game test (npm run test:godot-reset): Settings > About > Reset game (logic/reset_game.gd,
   ui/reset_dialog.gd, ui/settings_screen.gd). Checks the full wipe (DEFAULTS, fresh profile, signed out, caches), that
   the About row is bright red and opens the prompt, that nothing is deleted before the red button (Cancel / Back leave
   everything untouched), that the confirmed press wipes and asks for the title reload (a test seam records it), and the
   --no-save guard that keeps the player's real settings / profile files untouched.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-reset */
const { spawnSync } = require('child_process');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/reset_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 180000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(RESET|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^RESET ok/m.test(out) || /SCRIPT ERROR|^ERROR/m.test(out)) {
  if (!lines.length) console.log(out.slice(0, 3000));
  console.log('reset_test FAILED');
  process.exit(1);
}
console.log('godot reset game test passes');
