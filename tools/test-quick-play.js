'use strict';
/* Godot Quick play test: QuickPlay.pick() always hands play_offline a valid random offline match (game type, arena,
   class, bot count, bot skill, floor), several seeds give variety, and the title has a Quick play button under Play
   that is inside the safe area and at least 44 pt on the smallest screens (godot/tests/quick_play_test.gd). Needs Godot
   (GODOT env var or the macOS default). Run: npm run test:godot-quick-play */
const { spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/quick_play_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 300000 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(QUICK|FAIL)|ERROR|SCRIPT ERROR/.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^QUICK ok/m.test(out) && !isFatal(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot quick-play test FAILED'); process.exit(1); }
console.log('godot quick-play test passes');
