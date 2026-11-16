'use strict';
/* Godot title text-fit audit (godot/tests/title_fit_test.gd, tests/fit_audit.gd): every language of Lang.LANGS at four window sizes,
   the title idle / Construction / opened showcase: no text wider or taller than its control, cropped, overlapping, buttons >= 44 pt.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-title-fit [-- --lang=ja --size=852x393] */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });
const extra = process.argv.slice(2);
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/title_fit_test.gd', '--', '--no-save', ...extra], { encoding: 'utf8', timeout: 900000, maxBuffer: 64 * 1024 * 1024 });
const out = (r.stdout || '') + (r.stderr || '');
console.log(out.split('\n').filter(l => /^(FIT|FAIL)|SCRIPT ERROR/.test(l)).join('\n'));
if (r.status !== 0 || !/^FIT ok/m.test(out) || isFatal(out)) {
  console.log(`title_fit_test FAILED (exit ${r.status}, signal ${r.signal || 'none'})`);
  if (!/^FIT /m.test(out)) console.log(out.trim().split('\n').slice(-50).join('\n'));
  process.exit(1);
}
console.log('godot title fit passes');
