'use strict';
/* The Godot movement port must reproduce the web game's movement. Runs the real JS physics for a few maps and replays the same input in Godot. npm run test:godot-physics */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const trace = require('./physics-reference');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
let bad = 0;
spawnSync(GODOT, ['--headless', '--path', path.join(__dirname, '..', 'godot'), '--import'], { timeout: 120000 });   // registers class_name scripts
for (const map of (process.env.MAPS || 'arena,ice,temple,tower,fortress').split(',')) {
  const spawn = [0, 0.01, 0], tf = path.join(os.tmpdir(), 'wa-trace-' + map + '.json');
  fs.writeFileSync(tf, JSON.stringify(trace(map, spawn)));
  const r = spawnSync(GODOT, ['--headless', '--path', path.join(__dirname, '..', 'godot'), '--script', 'res://tests/physics_test.gd', '--', path.join(__dirname, '..', 'shared', 'maps.json'), map, tf], { encoding: 'utf8', timeout: 60000 });
  const ok = /^PHYSICS/m.test(r.stdout + r.stderr) && r.status === 0;
  const line = (r.stdout + r.stderr).split('\n').find(l => l.startsWith('PHYSICS')) || ('no result: ' + (r.stderr || r.stdout).slice(0, 300));
  console.log(map.padEnd(10), line, ok ? 'ok' : 'FAIL'); if (!ok) bad++;
}
process.exit(bad ? 1 : 0);
