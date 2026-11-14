'use strict';
/* Headless launch-service policy test. Run: npm run test:godot-services */
const { spawnSync } = require('child_process');
const path = require('path');
const godot = process.env.GODOT || 'godot';
const r = spawnSync(godot, ['--headless', '--path', path.join(__dirname, '..', 'godot'), '--script', 'res://tests/services_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 60000 });
process.stdout.write((r.stdout || '') + (r.stderr || ''));
if (r.status !== 0 || !/^SERVICES ok/m.test(r.stdout || '')) { console.error('launch services test FAILED'); process.exit(1); }
console.log('launch services test passes');
