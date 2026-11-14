'use strict';
/* Godot graphics budget: godot/tests/gfx_bench.gd on each render tier (HIGH = PC / Forward+, MID = phones / Mobile,
   LOW = web / Compatibility), three heavy maps with 10 fighters each, CPU frame time plus draw calls / primitives from
   a windowed run. Fails when a number is over its tier's budget (docs/GRAPHICS.md).
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-gfx
     --headless   no window (CI): CPU numbers only        --tier=mid   one tier only (high | mid | low)
   Windowed runs also check tier parity (godot/tests/gfx_parity.gd): the same views of three maps rendered on MID and
   LOW must have a mean luminance within PARITY_TOL of each other (LOW used to differ by up to 40 %). */
const { spawnSync } = require('child_process');
require('./ensure-fresh')();
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const args = process.argv.slice(2);
const headless = args.includes('--headless');
const only = (args.find(a => a.startsWith('--tier=')) || '').slice(7).toLowerCase();
const TIERS = [
  { name: 'high', tier: 'pc', method: 'forward_plus' },
  { name: 'mid', tier: 'mobile', method: 'mobile' },
  { name: 'low', tier: 'web', method: 'gl_compatibility' },
].filter(t => !only || t.name === only);

spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });
let ok = true;
for (const t of TIERS) {
  const a = (headless ? ['--headless'] : ['--rendering-method', t.method, '--resolution', '1170x540'])
    .concat(['--path', DIR, '--script', 'res://tests/gfx_bench.gd', '--', '--no-save', '--tier=' + t.tier]);
  const r = spawnSync(GODOT, a, { encoding: 'utf8', timeout: 600000 });
  const out = (r.stdout || '') + (r.stderr || '');
  const lines = out.split('\n').filter(l => /^(GFX|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
  console.log(lines.join('\n'));
  const pass = r.status === 0 && /^GFX ok/m.test(out) && !/SCRIPT ERROR/m.test(out);
  if (!pass) { if (!lines.length) console.log(out.slice(0, 3000)); ok = false; }
}
const PARITY_TOL = 0.12;
if (!headless && !only) {
  const lum = {};
  for (const t of TIERS.filter(t => t.name !== 'high')) {
    const r = spawnSync(GODOT, ['--rendering-method', t.method, '--resolution', '1170x540', '--path', DIR, '--script',
      'res://tests/gfx_parity.gd', '--', '--no-save', '--tier=' + t.tier], { encoding: 'utf8', timeout: 300000 });
    const out = (r.stdout || '') + (r.stderr || '');
    for (const m of out.matchAll(/^PARITY (LOW|MID) (\S+) ([\d.]+)/gm)) (lum[m[2]] = lum[m[2]] || {})[m[1]] = +m[3];
    if (r.status !== 0 || /SCRIPT ERROR/.test(out)) { console.log(out.slice(0, 2000)); ok = false; }
  }
  const views = Object.keys(lum);
  if (!views.length) { console.log('FAIL parity: no PARITY lines'); ok = false; }
  for (const v of views) {
    const { MID, LOW } = lum[v];
    const d = (LOW - MID) / MID;
    const bad = !(Math.abs(d) <= PARITY_TOL);
    console.log(`${bad ? 'FAIL ' : ''}PARITY ${v}: MID ${MID} LOW ${LOW} (${(d * 100).toFixed(1)} %)`);
    if (bad) ok = false;
  }
}
if (!ok) { console.log('godot gfx budget FAILED'); process.exit(1); }
console.log('godot gfx budget passes');
