'use strict';
/* Shareable result card (WP 0.6-C, docs/SHARE.md): godot/tests/result_card_test.gd builds a card from a
   Save.finish_match() summary, writes a 1080x1920 PNG under user://share/, and checks that the Share control follows
   Share.has_provider() while a fake provider receives the card path. Needs Godot (GODOT env var or the macOS default).
   Run: npm run test:godot-result-card */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/result_card_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 180000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(CARD|SHARE|NODES|FAIL)|SCRIPT ERROR|^ERROR: Failed/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^CARD ok/m.test(out) && !/^FAIL/m.test(out) && !isFatal(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot result card test FAILED'); process.exit(1); }
console.log('godot result card test passes');
