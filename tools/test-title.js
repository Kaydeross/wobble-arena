'use strict';
/* Godot title redesign test (the left menu rail, the 3D stage and the DLC showcase: scripts/main.gd,
   ui/title_showcase.gd, ui/showcase_stage.gd, dlc/dlc_pack_data.gd, docs/TITLE.md): the pack data, every rail route,
   44 pt targets at 852x393 / 667x375 / 390x844, the idle -> open -> swap -> back state machine under spammed input,
   and the "TEST IN SITE YARD" test drive (the right arena and weapons, no ownership, nothing saved). Fails on any
   script error. Needs Godot (GODOT env var or the macOS default).
   Run: npm run test:godot-title */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/title_showcase_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 600000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(TITLE|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n'));
if (r.status !== 0 || !/^TITLE ok/m.test(out) || isFatal(out)) {
  console.log(`title_showcase_test FAILED (exit ${r.status}, signal ${r.signal || 'none'})`);
  const raw = out.trim().split('\n');
  console.log(raw.slice(-50).join('\n'));
  process.exit(1);
}
console.log('godot title test passes');
