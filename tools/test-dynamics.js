'use strict';
/* Dynamic arenas: checks the pure functions (DYN-PURE block sliced out of public/index.html, the same code the game runs) against
   the level data in shared/maps.json. No browser. node tools/test-dynamics.js [--table]   (--table prints the support table for docs/DYNAMICS.md) */
const fs = require('fs'), path = require('path'), assert = require('assert');
const SRC = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
const a = SRC.indexOf('/* ==== DYN-PURE BEGIN'), b = SRC.indexOf('/* ==== DYN-PURE END');
assert.ok(a > 0 && b > a, 'DYN-PURE block found');
const D = new Function(SRC.slice(a, b) + '\nreturn { DYN_KINDS, dynHash, dynRand, dynRamp, dynMapAllowed, dynResolve, dynOffset, dynDelta, dynPlan };')();
const MAPS = require('../shared/maps.json');
const STEP = 0.55;
let checks = 0; const ok = (c, m) => { checks++; assert.ok(c, m); };

// hash: fixed vectors (the Godot port must print the same numbers)
const VEC = [[0, 0, 0, 0], [1, 2, 3, 4], [4294967295, 7, 0, 0], [123456789, 3, 5, 1]].map(v => D.dynHash(...v));
ok(VEC.every(h => Number.isInteger(h) && h >= 0 && h < 2 ** 32), 'hash is uint32');
ok(D.dynHash(1, 2, 3, 4) === VEC[1], 'hash is deterministic');

// offsets: zero at t = 0 (ramp), deterministic, in range; anchored tiles never move
const KINDS = ['wobble', 'tilt', 'quake'];
for (const kind of KINDS) for (const seed of [1, 99, 0xdeadbeef]) {
  ok(D.dynOffset(kind, seed, 0, 1, 2, 10, 10, 0) === 0, kind + ' offset 0 at t=0');
  ok(D.dynOffset(kind, seed, 37.3, 3, 4, 10, 10, 0) === D.dynOffset(kind, seed, 37.3, 3, 4, 10, 10, 0), kind + ' deterministic');
  ok(D.dynOffset(kind, seed, 37.3, 3, 4, 10, 10, 1) === 0, kind + ' anchored tile stays');
}
ok(D.dynOffset('off', 5, 10, 0, 0, 4, 4, 0) === 0 && D.dynOffset('drift', 5, 10, 0, 0, 4, 4, 0) === 0, 'off / drift leave the floor alone');
ok(D.dynDelta(5, 0, 0) === 0, 'drift starts at 0');

// adjacent tiles (incl. diagonal neighbours) never differ by a step or more, for many grid sizes and a long scan of t
for (const kind of ['wobble', 'tilt']) for (const [nx, nz] of [[4, 4], [5, 9], [9, 9], [10, 10], [12, 7], [12, 12]]) for (const seed of [3, 77, 4242, 0x9e3779b9]) {
  let worst = 0, amp = 0;
  for (let t = 0; t < 120; t += 0.37) {
    const g = []; for (let iz = 0; iz < nz; iz++) for (let ix = 0; ix < nx; ix++) g.push(D.dynOffset(kind, seed, t, ix, iz, nx, nz, 0));
    for (let iz = 0; iz < nz; iz++) for (let ix = 0; ix < nx; ix++) {
      const v = g[iz * nx + ix]; amp = Math.max(amp, Math.abs(v));
      for (const [dx, dz] of [[1, 0], [0, 1], [1, 1], [1, -1]]) { const jx = ix + dx, jz = iz + dz; if (jx < nx && jz >= 0 && jz < nz) worst = Math.max(worst, Math.abs(v - g[jz * nx + jx])); }
    }
  }
  ok(worst < STEP, kind + ' ' + nx + 'x' + nz + ' seed ' + seed + ': neighbour difference ' + worst.toFixed(3) + ' < ' + STEP);
  ok(amp <= (kind === 'wobble' ? 0.3 : 0.5) + 1e-9 && amp > 0.1, kind + ' amplitude in range (' + amp.toFixed(3) + ')');
}
// quake: only shakes (|x| <= 0.05) or holes; nothing before 12 s; holes are 3x3-local and come back
for (const seed of [1, 2, 3, 1234, 0xffffffff]) {
  let holes = 0;
  for (let t = 0; t < 200; t += 0.05) for (let iz = 0; iz < 10; iz++) for (let ix = 0; ix < 10; ix++) {
    const v = D.dynOffset('quake', seed, t, ix, iz, 10, 10, 0);
    if (t < 12) ok(v === 0, 'quake: still for the first 12 s');
    ok(v >= -30 - 1e-9 && v <= 0.05 + 1e-9, 'quake offset in range');
    if (v < -0.06) holes++;
    ok(D.dynOffset('quake', seed, t, ix, iz, 10, 10, 2) >= -0.05 - 1e-9, 'quake: no-hole tiles never sink');
  }
  ok(holes > 0, 'quake seed ' + seed + ' opens holes');
}
// drift range
for (let t = 0; t < 100; t += 0.5) ok(Math.abs(D.dynDelta(77, t, 3)) <= 2 + 1e-9, 'drift within 2 m');
// random picks a real kind from the seed, only among what the map supports
const seen = new Set();
for (let seed = 0; seed < 400; seed++) {
  const k = D.dynResolve('random', seed, true, true); seen.add(k); ok(['wobble', 'tilt', 'quake', 'drift'].includes(k), 'random -> real kind');
  ok(D.dynResolve('random', seed, true, true) === k, 'random is seeded');
  ok(D.dynResolve('random', seed, false, true) === 'drift', 'random on a drift-only map');
  ok(['wobble', 'tilt', 'quake'].includes(D.dynResolve('random', seed, true, false)), 'random on a tile-only map');
}
ok(seen.size === 4, 'random reaches every kind');
ok(D.dynResolve('random', 1, false, false) === 'off' && D.dynResolve('bogus', 1, true, true) === 'off' && D.dynResolve('drift', 1, true, false) === 'off', 'unknown / unsupported -> off');

// every level: plan from the collision data; quake holes never under a spawn (whole match, so also the first 10 s)
const rows = [];
for (const [id, m] of Object.entries(MAPS)) {
  const g = m.geometry, sol = g.boxes.map(q => ({ minX: q.x - q.w / 2, maxX: q.x + q.w / 2, minZ: q.z - q.d / 2, maxZ: q.z + q.d / 2, top: q.y + q.h, bottom: q.y }));
  const spawns = [...(m.spawns || []), ...(m.bots || []), ...(m.player ? [m.player] : [])];
  const allowed = D.dynMapAllowed(id, m);
  const P = D.dynPlan(sol, (g.ladders || []).map(l => ({ x: l.x, z: l.z })), (g.bouncePads || []).map(p => ({ x: p.x, z: p.z, r: p.r || 1.2 })), spawns);
  const tile = allowed && P.canTile, drift = allowed && P.drift.length > 0;
  rows.push([id, m.name, tile ? 'wobble, tilt, quake' : '-', drift ? 'drift (' + P.drift.length + ')' : '-', tile ? P.nx + 'x' + P.nz : '-']);
  if (!tile) continue;
  const F = sol[P.floor], tw = (F.maxX - F.minX) / P.nx, td = (F.maxZ - F.minZ) / P.nz;
  for (const sp of spawns) {
    const ix = Math.floor((sp[0] - F.minX) / tw), iz = Math.floor((sp[1] - F.minZ) / td);
    if (ix < 0 || ix >= P.nx || iz < 0 || iz >= P.nz) continue;
    ok(P.mask[iz * P.nx + ix] & 2, id + ': spawn tile is marked no-hole');
    for (const seed of [11, 222, 3333]) for (let t = 0; t < 60; t += 0.1) ok(D.dynOffset('quake', seed, t, ix, iz, P.nx, P.nz, P.mask[iz * P.nx + ix]) > -0.06, id + ': no hole under spawn ' + sp);
  }
  for (const d of P.drift) ok(d.i !== P.floor && (d.axis === 'x' || d.axis === 'z'), id + ': drift entry sane');
}
if (process.argv.includes('--table')) { console.log('| Map | Name | Floor kinds | Drift | Grid |\n|---|---|---|---|---|'); for (const r of rows) console.log('| `' + r[0] + '` | ' + r.slice(1).join(' | ') + ' |'); console.log('hash vectors', VEC.join(', ')); }
console.log('dynamics OK (' + checks + ' checks, ' + rows.filter(r => r[2] !== '-' || r[3] !== '-').length + ' levels move)');
