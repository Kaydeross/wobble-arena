'use strict';
/* Dynamic arenas parity: runs the web game's REAL pure functions (DYN-PURE block sliced out of public/index.html) over a set of
   vectors, then has Godot (godot/logic/dynamics.gd + arena_dyn.gd, via godot/tests/dynamics_test.gd) compute the same and compare:
   hashes / plans exact, floats within 1e-9. Also the tile / drift-block collision over 40 s of 1/120 s steps (expected solids from a
   small mirror of dynBuildTiles / updateDyn below) and Godot-only checks that fighters ride the moving tiles.  npm run test:godot-dynamics */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path'), assert = require('assert');
const SRC = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const a = SRC.indexOf('/* ==== DYN-PURE BEGIN'), b = SRC.indexOf('/* ==== DYN-PURE END');
assert.ok(a > 0 && b > a, 'DYN-PURE block found');
const D = new Function(SRC.slice(a, b) + '\nreturn { DYN_KINDS, dynHash, dynRand, dynRamp, dynMapAllowed, dynResolve, dynOffset, dynDelta, dynPlan };')();
const MAPS = require('../shared/maps.json');

let s = 987654321; const rnd = () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
const u32 = () => Math.floor(rnd() * 4294967296) >>> 0, ri = n => Math.floor(rnd() * n);
const V = { hash: [], rand: [], ramp: [], resolve: [], offset: [], delta: [], maps: {}, sims: [] };
const hin = [[0, 0, 0, 0], [1, 2, 3, 4], [4294967295, 7, 0, 0], [123456789, 3, 5, 1], [0xdeadbeef, 4, 13, 9 * 4096 + 11], [5, 4294967295, 4294967295, 4294967295]];
for (let i = 0; i < 400; i++) hin.push([u32(), ri(8), ri(200), ri(12 * 4096 + 12)]);
for (const h of hin) { V.hash.push([...h, D.dynHash(...h)]); V.rand.push([...h, D.dynRand(...h)]); }
for (const t of [-1, 0, 0.001, 1, 2, 3.999, 4, 4.5, 100]) V.ramp.push([t, D.dynRamp(t)]);
for (const k of [...D.DYN_KINDS, 'bogus']) for (let i = 0; i < 30; i++) { const sd = u32(), ct = rnd() < 0.7, cd = rnd() < 0.7; V.resolve.push([k, sd, ct, cd, D.dynResolve(k, sd, ct, cd)]); }
for (const k of ['wobble', 'tilt', 'quake', 'drift', 'off']) for (let i = 0; i < 1500; i++) {
  const nx = 4 + ri(9), nz = 4 + ri(9), sd = i < 20 ? i : u32();
  const t = i % 3 === 0 ? ri(200 * 64) / 64 : i % 3 === 1 ? 12 + rnd() * 120 : rnd() * 8;        // exact binary times, quake windows, ramp
  const ix = ri(nx), iz = ri(nz), mask = rnd() < 0.15 ? ri(4) : 0;
  V.offset.push([k, sd, t, ix, iz, nx, nz, mask, D.dynOffset(k, sd, t, ix, iz, nx, nz, mask)]);
}
// quake: aim right at the epicentres so the hole curve itself is covered
for (let i = 0; i < 600; i++) {
  const sd = u32(), nx = 10, nz = 10, k = ri(10), t0 = 12 + k * 15 + 3 * D.dynRand(sd, 2, k, 0), lt = rnd() * 6.3;
  const rx = Math.floor(D.dynRand(sd, 3, k, 0) * nx), rz = Math.floor(D.dynRand(sd, 3, k, 1) * nz), ix = Math.min(nx - 1, Math.max(0, rx + ri(3) - 1)), iz = Math.min(nz - 1, Math.max(0, rz + ri(3) - 1));
  V.offset.push(['quake', sd, t0 + lt, ix, iz, nx, nz, 0, D.dynOffset('quake', sd, t0 + lt, ix, iz, nx, nz, 0)]);
}
for (let i = 0; i < 400; i++) { const sd = u32(), t = i % 2 ? rnd() * 100 : ri(100 * 64) / 64 - 1, bi = ri(12); V.delta.push([sd, t, bi, D.dynDelta(sd, t, bi)]); }

const solidsOf = m => m.geometry.boxes.map(q => ({ minX: q.x - q.w / 2, maxX: q.x + q.w / 2, minZ: q.z - q.d / 2, maxZ: q.z + q.d / 2, top: q.y + q.h, bottom: q.y }));
const spawnsOf = m => [...(m.spawns || []), ...(m.bots || []), ...(m.player ? [m.player] : [])];
const planOf = m => D.dynPlan(solidsOf(m), (m.geometry.ladders || []).map(l => ({ x: l.x, z: l.z })), (m.geometry.bouncePads || []).map(p => ({ x: p.x, z: p.z, r: p.r || 1.2 })), spawnsOf(m));
for (const [id, m] of Object.entries(MAPS)) V.maps[id] = { allowed: D.dynMapAllowed(id, m), plan: planOf(m) };

// mirror of dynBuildTiles / dynBuildDrift / updateDyn (collision only, no fighters): the solids list at a few checkpoints
const SIM = 1 / 120;
for (const [id, kind, seed] of [['arena', 'wobble', 11], ['arena', 'tilt', 0xdeadbeef], ['arena', 'quake', 3], ['temple', 'quake', 77], ['arena', 'drift', 5], ['farm', 'drift', 123456], ['arena', 'random', 42], ['capsule', 'tilt', 9]]) {
  const m = MAPS[id], sol = solidsOf(m), P = planOf(m);
  const k = D.dynResolve(kind, seed, P.canTile && D.dynMapAllowed(id, m), P.drift.length > 0 && D.dynMapAllowed(id, m));
  const tiles = [], drift = [];
  if (k === 'drift') P.drift.forEach((d, bi) => drift.push({ s: sol[d.i], axis: d.axis, bi, d: 0 }));
  else if (k !== 'off') {
    const F = sol[P.floor], tw = (F.maxX - F.minX) / P.nx, td = (F.maxZ - F.minZ) / P.nz, ts = [];
    for (let iz = 0; iz < P.nz; iz++) for (let ix = 0; ix < P.nx; ix++) {
      const t = { minX: F.minX + ix * tw, maxX: ix === P.nx - 1 ? F.maxX : F.minX + (ix + 1) * tw, minZ: F.minZ + iz * td, maxZ: iz === P.nz - 1 ? F.maxZ : F.minZ + (iz + 1) * td, top: F.top, bottom: F.bottom };
      ts.push(t); tiles.push({ s: t, ix, iz, mask: P.mask[iz * P.nx + ix], off: 0 });
    }
    sol.splice(P.floor, 1, ...ts);
  }
  const checks = [];
  let simTime = 0;
  for (let n = 1; n <= 40 * 120; n++) {
    simTime += SIM;
    const t = simTime;
    for (const e of drift) { const d = D.dynDelta(seed, t, e.bi), dd = d - e.d; if (dd === 0) continue; e.d = d; if (e.axis === 'x') { e.s.minX += dd; e.s.maxX += dd; } else { e.s.minZ += dd; e.s.maxZ += dd; } }
    for (const e of tiles) { const off = D.dynOffset(k, seed, t, e.ix, e.iz, P.nx, P.nz, e.mask), dy = off - e.off; if (dy === 0) continue; e.off = off; e.s.top += dy; e.s.bottom += dy; }
    if (n % 600 === 0 || n === 1 || n === 7 * 120 + 31) checks.push([n, sol.map(q => [q.minX, q.maxX, q.minZ, q.maxZ, q.top, q.bottom])]);
  }
  V.sims.push({ id, choice: kind, seed, kind: k, nsol: sol.length, checks });
}

const tf = path.join(os.tmpdir(), 'wa-dyn-' + process.pid + '.json');
fs.writeFileSync(tf, JSON.stringify(V));
const gd = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', gd, '--import'], { timeout: 180000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', gd, '--script', 'res://tests/dynamics_test.gd', '--', '--no-save', tf], { encoding: 'utf8', timeout: 180000 });
fs.unlinkSync(tf);
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(DYN|FAIL)|SCRIPT ERROR|^ERROR/.test(l));
console.log(lines.join('\n') || out.slice(0, 2000));
const ok = r.status === 0 && /^DYN ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
console.log(ok ? 'godot dynamics parity ok' : 'godot dynamics test FAILED'); process.exit(ok ? 0 : 1);
