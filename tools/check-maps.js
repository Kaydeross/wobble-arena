'use strict';
/*
  Arena sanity checker. Reads shared/maps.json (the real collision geometry) and applies the game's own movement constants
  (R 0.45, STEP 0.55, FH 2.3, jump 9.2 / GRAV 24) on a 0.25 m grid to answer:
    - are spawns / bot starts / crate spots on something to stand on (and not inside a wall)?
    - can every spawn walk/jump/climb to every other spawn, and back?
    - are there pits a fighter can fall into and never leave?  platforms nobody can reach?
  node tools/check-maps.js [mapId ...]     report (exit 1 on errors)      --quiet only prints problems
  Used by `npm test` (errors only).
*/
const fs = require('fs'), path = require('path');
const maps = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'shared', 'maps.json'), 'utf8'));
const R = 0.45, STEP = 0.55, FH = 2.3, GRAV = 24, JUMP = 9.2;
const JUMP_UP = 2.2;                      // apex 1.76 + STEP 0.55 (you can clip a box top while still rising), a little margin
const G = 0.25;
const SKIP = new Set(['test', 'practice', 'pillars', 'pillars2', 'custom', 'shrink', 'squeeze']);   // dev maps, geometry-less or moving-floor maps

function analyse(id) {
  const m = maps[id], g = m.geometry, errs = [], warns = [], info = {};
  const S = g.boxes.map(b => ({ minX: b.x - b.w / 2, maxX: b.x + b.w / 2, minZ: b.z - b.d / 2, maxZ: b.z + b.d / 2, top: b.y + b.h, bottom: b.y }));
  if (!S.length) return { errs, warns, info };
  let x0 = 1e9, x1 = -1e9, z0 = 1e9, z1 = -1e9;
  for (const s of S) { x0 = Math.min(x0, s.minX); x1 = Math.max(x1, s.maxX); z0 = Math.min(z0, s.minZ); z1 = Math.max(z1, s.maxZ); }
  for (const p of (m.spawns || []).concat(m.bots || [], (m.drops || []))) { x0 = Math.min(x0, p[0] - 2); x1 = Math.max(x1, p[0] + 2); z0 = Math.min(z0, p[1] - 2); z1 = Math.max(z1, p[1] + 2); }
  const W = Math.ceil((x1 - x0) / G) + 1, H = Math.ceil((z1 - z0) / G) + 1;
  const cx = i => x0 + i * G, cz = j => z0 + j * G;
  // bucket solids per coarse cell for speed
  const BK = 4, bw = Math.ceil(W * G / BK) + 1, bh = Math.ceil(H * G / BK) + 1, buckets = Array.from({ length: bw * bh }, () => []);
  S.forEach((s, k) => { for (let bx = Math.floor((s.minX - R - x0) / BK); bx <= Math.floor((s.maxX + R - x0) / BK); bx++) for (let bz = Math.floor((s.minZ - R - z0) / BK); bz <= Math.floor((s.maxZ + R - z0) / BK); bz++) if (bx >= 0 && bz >= 0 && bx < bw && bz < bh) buckets[bx + bz * bw].push(k); });
  const near = (x, z) => buckets[Math.floor((x - x0) / BK) + Math.floor((z - z0) / BK) * bw] || [];
  // standable heights at a point (the same expanded-by-R footprint collide() uses)
  function heights(x, z) {
    const cov = [];
    for (const k of near(x, z)) { const s = S[k]; if (x > s.minX - R && x < s.maxX + R && z > s.minZ - R && z < s.maxZ + R) cov.push(s); }
    const out = [];
    for (const c of cov) {
      const h = c.top; let ok = true;
      for (const o of cov) {
        if (o === c || o.top <= h + 1e-6) continue;
        if (o.bottom > 0.05 && h + FH <= o.bottom) continue;          // it is a ceiling you walk under
        ok = false; break;
      }
      if (ok && c.bottom > 0.05) { for (const o of cov) if (o !== c && o.top > c.top - 1e-6 && o.bottom > 0.05 && o.bottom < h + FH && o.bottom >= c.top - 1e-6) { ok = false; break; } }   // a ceiling too low to stand under
      if (ok && !out.includes(h)) out.push(h);
    }
    return out.sort((a, b) => a - b);
  }
  const hs = new Array(W * H); let nodes = 0;
  const nodeBase = new Int32Array(W * H + 1);
  for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) { const l = heights(cx(i), cz(j)); hs[i + j * W] = l; nodeBase[i + j * W] = nodes; nodes += l.length; }
  nodeBase[W * H] = nodes;
  const nodeOf = (i, j, h) => { if (i < 0 || j < 0 || i >= W || j >= H) return -1; const l = hs[i + j * W]; for (let k = 0; k < l.length; k++) if (Math.abs(l[k] - h) < 1e-6) return nodeBase[i + j * W] + k; return -1; };
  const nodeI = new Int32Array(nodes), nodeH = new Float32Array(nodes);
  for (let c = 0; c < W * H; c++) hs[c].forEach((h, k) => { nodeI[nodeBase[c] + k] = c; nodeH[nodeBase[c] + k] = h; });
  // landing node when dropping at (x,z) from height y: highest standable height <= y + STEP
  const landing = (x, z, y) => { const i = Math.round((x - x0) / G), j = Math.round((z - z0) / G); if (i < 0 || j < 0 || i >= W || j >= H) return -1; const l = hs[i + j * W]; let best = -1; for (let k = 0; k < l.length; k++) if (l[k] <= y + STEP + 1e-6) best = k; return best < 0 ? -1 : nodeBase[i + j * W] + best; };
  // edges (forward adjacency, with a flag for ladders / pads so bots can be modelled)
  const adj = Array.from({ length: nodes }, () => []);
  const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
  let voidEdges = 0;
  for (let n = 0; n < nodes; n++) {
    const c = nodeI[n], i = c % W, j = (c - i) / W, h = nodeH[n];
    for (const [di, dj] of DIRS) {
      const ni = i + di, nj = j + dj; if (ni < 0 || nj < 0 || ni >= W || nj >= H) continue;
      const l = hs[ni + nj * W]; let down = -1;
      for (let k = 0; k < l.length; k++) {
        if (l[k] <= h + STEP + 1e-6) down = k;
        else if (l[k] <= h + JUMP_UP) adj[n].push(nodeBase[ni + nj * W] + k);
      }
      if (down >= 0) adj[n].push(nodeBase[ni + nj * W] + down); else if (!l.length) voidEdges++;
    }
  }
  const nbots = nodes;                                       // bots do not use ladders; keep ladder/pad edges tagged
  const special = [];                                        // { from, to, kind }
  for (const L of g.ladders) {
    const sx = L.x + L.nx * 0.55, sz = L.z + L.nz * 0.55, tx = L.x - L.nx * 0.4, tz = L.z - L.nz * 0.4;
    const base = [], top = [];
    for (let n = 0; n < nodes; n++) {
      const c = nodeI[n], i = c % W, j = (c - i) / W, x = cx(i), z = cz(j), h = nodeH[n];
      if (Math.abs(x - sx) < 0.8 && Math.abs(z - sz) < 0.8 && h >= L.y0 - 0.4 && h < L.y1 - 0.1) base.push(n);
      if (Math.hypot(x - tx, z - tz) < 0.6 && h > L.y1 - 0.7 && h < L.y1 + 0.2) top.push(n);
    }
    if (!base.length) warns.push('ladder at ' + L.x + ',' + L.z + ' has no floor to step on from');
    if (!top.length) warns.push('ladder at ' + L.x + ',' + L.z + ' tops out on nothing');
    for (const b of base) for (const t of top) special.push({ from: b, to: t, kind: 'ladder' });
  }
  for (const P of g.bouncePads) {
    const reach = (P.power * P.power) / (2 * GRAV), air = 2 * P.power / GRAV, dist = Math.min(11, 7.5 * air * 0.85);
    const base = [];
    for (let n = 0; n < nodes; n++) { const c = nodeI[n], i = c % W, j = (c - i) / W; if (nodeH[n] < 0.7 && Math.hypot(cx(i) - P.x, cz(j) - P.z) < P.r) base.push(n); }
    if (!base.length) warns.push('bounce pad at ' + P.x + ',' + P.z + ' is not on a floor');
    for (let n = 0; n < nodes; n++) { const c = nodeI[n], i = c % W, j = (c - i) / W; if (nodeH[n] <= reach - 0.4 && Math.hypot(cx(i) - P.x, cz(j) - P.z) < dist) for (const b of base.slice(0, 1)) special.push({ from: b, to: n, kind: 'pad' }); }
  }
  const leaps = [];
  // players (not bots) can also leap a gap of up to ~3.8 m from an edge to a surface at about the same height or lower
  const GAP = 3.8, gr = Math.ceil(GAP / G);
  for (let n = 0; n < nodes; n++) {
    const c = nodeI[n], i = c % W, j = (c - i) / W, h = nodeH[n];
    let edge = false;
    for (const [di, dj] of DIRS) { const ni = i + di, nj = j + dj; if (ni < 0 || nj < 0 || ni >= W || nj >= H) { edge = true; break; } if (!hs[ni + nj * W].some(v => v <= h + STEP + 1e-6)) { edge = true; break; } }
    if (!edge) continue;
    for (let dj = -gr; dj <= gr; dj++) for (let di = -gr; di <= gr; di++) {
      if (di * di + dj * dj > gr * gr) continue;
      const ni = i + di, nj = j + dj; if (ni < 0 || nj < 0 || ni >= W || nj >= H) continue;
      for (const v of hs[ni + nj * W]) if (v <= h + 0.4) leaps.push([n, nodeBase[ni + nj * W] + hs[ni + nj * W].indexOf(v)]);
    }
  }
  const adjP = adj.map(a => a.slice());                      // player (ladders + pads)
  const adjB = adj.map(a => a.slice());                      // bots (pads only)
  for (const [f, t] of leaps) adjP[f].push(t);
  for (const e of special) { adjP[e.from].push(e.to); if (e.kind === 'pad') adjB[e.from].push(e.to); }
  // starting points
  const startY = m.spawnY || 4;
  const spots = [];
  const addSpot = (kind, p, idx, y) => {
    const n = landing(p[0], p[1], y);
    const hereTop = S.filter(s => (s.bottom <= 0.05 || s.bottom < y + FH) && p[0] > s.minX - R && p[0] < s.maxX + R && p[1] > s.minZ - R && p[1] < s.maxZ + R).reduce((a, s) => Math.max(a, s.top), -9);
    if (n < 0) { errs.push(kind + ' ' + idx + ' (' + p[0] + ',' + p[1] + ') has nothing to stand on' + (hereTop > -9 ? ' (inside a ' + hereTop + ' m high solid)' : ' (void)')); return; }
    if (nodeH[n] < hereTop - STEP - 1e-6 && kind !== 'drop') warns.push(kind + ' ' + idx + ' (' + p[0] + ',' + p[1] + ') lands at ' + nodeH[n] + ' m next to a ' + hereTop + ' m wall: gets shoved out sideways');
    spots.push({ kind, idx, n, p, h: nodeH[n] });
  };
  (m.spawns || []).forEach((p, i) => addSpot('spawn', p, i, startY));
  addSpot('player', m.player, 0, p3(m.player, 0.01));
  (m.bots || []).forEach((p, i) => addSpot('bot', p, i, p[2] !== undefined ? p[2] : (m.spawnY || 0.01)));
  function p3(p, d) { return p[2] !== undefined ? p[2] : (m.spawnY || d); }
  (m.drops || []).forEach((p, i) => {            // a crate rests at the height given (3rd number, default 0) regardless of what is there
    const gy = p[2] || 0; let top = -9; for (const s of S) if (s.bottom < gy + 0.5 && p[0] > s.minX && p[0] < s.maxX && p[1] > s.minZ && p[1] < s.maxZ) top = Math.max(top, s.top);
    if (top < -8) { errs.push('crate spot ' + i + ' (' + p[0] + ',' + p[1] + ') hangs over the void'); return; }
    if (Math.abs(top - gy) > 0.06) {
      const msg = 'crate spot ' + i + ' (' + p[0] + ',' + p[1] + ') is set to height ' + gy + ' but the surface there is ' + +top.toFixed(2) + (top > gy ? ' (sunk into a block)' : ' (floating)');
      if (m.only === 'lowg' && top < gy) { /* low-gravity maps hang crates in the air on purpose */ } else if (Math.abs(top - gy) >= 0.5) errs.push(msg); else warns.push(msg);
    }
    const n = landing(p[0], p[1], gy + 0.05); if (n < 0) return; spots.push({ kind: 'drop', idx: i, n, p, h: nodeH[n] });
  });
  // spawn fairness
  const sp = spots.filter(s => s.kind === 'spawn');
  if (sp.length >= 2) {
    let mind = 1e9, pair = '';
    for (let a = 0; a < sp.length; a++) for (let b = a + 1; b < sp.length; b++) { const d = Math.hypot(sp[a].p[0] - sp[b].p[0], sp[a].p[1] - sp[b].p[1]); if (d < mind) { mind = d; pair = a + '-' + b; } }
    info.minSpawnGap = +mind.toFixed(1); if (mind < 5) warns.push('spawns ' + pair + ' only ' + mind.toFixed(1) + ' m apart');
    const hsx = sp.map(s => s.h); if (Math.max(...hsx) - Math.min(...hsx) > 3) warns.push('spawn heights differ by ' + (Math.max(...hsx) - Math.min(...hsx)).toFixed(1) + ' m (high ground advantage)');
  }
  // reachability
  const bfs = (adjL, seeds) => { const seen = new Uint8Array(nodes), q = []; for (const s of seeds) if (!seen[s]) { seen[s] = 1; q.push(s); } for (let h = 0; h < q.length; h++) for (const t of adjL[q[h]]) if (!seen[t]) { seen[t] = 1; q.push(t); } return seen; };
  const spawnNodes = sp.map(s => s.n);
  if (!spawnNodes.length) return { errs, warns, info };
  const fromP = bfs(adjP, [spawnNodes[0]]), fromB = bfs(adjB, [spawnNodes[0]]);
  for (const s of spots) {
    if (s.kind === 'drop') { if (!fromP[s.n]) errs.push('crate spot ' + s.idx + ' (' + s.p + ') cannot be reached from spawn 0'); else if (!fromB[s.n]) warns.push('crate spot ' + s.idx + ' (' + s.p + ') only reachable by ladder (bots cannot climb)'); }
    else if (!fromP[s.n]) errs.push(s.kind + ' ' + s.idx + ' (' + s.p + ') cannot reach / be reached from spawn 0');
    else if (!fromB[s.n] && s.kind !== 'spawn') warns.push(s.kind + ' ' + s.idx + ' (' + s.p + ') is only reachable by ladder');
  }
  // reverse graph: which nodes can get back to a spawn?  (pits)
  const rev = Array.from({ length: nodes }, () => []);
  for (let n = 0; n < nodes; n++) for (const t of adjP[n]) rev[t].push(n);
  const back = bfs(rev, spawnNodes);
  let trapCells = 0, trapEx = null; for (let n = 0; n < nodes; n++) if (fromP[n] && !back[n]) { trapCells++; if (!trapEx) trapEx = n; }
  if (trapCells) { const c = nodeI[trapEx], i = c % W; warns.push('trap: ' + trapCells + ' reachable spots (' + (trapCells * G * G).toFixed(1) + ' m2) cannot get back out, e.g. ' + cx(i).toFixed(1) + ',' + cz((c - i) / W).toFixed(1) + ' at height ' + nodeH[trapEx].toFixed(2)); }
  // platforms nobody can reach
  const miss = [];
  S.forEach((s, k) => {
    const area = (s.maxX - s.minX) * (s.maxZ - s.minZ); if (area < 1.5 || s.top < 0.2) return;
    let ok = false;
    for (let n = 0; n < nodes && !ok; n++) { if (Math.abs(nodeH[n] - s.top) > 1e-6) continue; const c = nodeI[n], i = c % W, x = cx(i), z = cz((c - i) / W); if (x > s.minX && x < s.maxX && z > s.minZ && z < s.maxZ && fromP[n]) ok = true; }
    let any = false;
    if (!ok) for (let n = 0; n < nodes && !any; n++) { if (Math.abs(nodeH[n] - s.top) > 1e-6) continue; const c = nodeI[n], i = c % W, x = cx(i), z = cz((c - i) / W); if (x > s.minX && x < s.maxX && z > s.minZ && z < s.maxZ) any = true; }
    if (!ok && any) miss.push(g.boxes[k].x + ',' + g.boxes[k].z + ' top ' + s.top.toFixed(1));
  });
  if (miss.length) warns.push(miss.length + ' standable top(s) unreachable: ' + miss.slice(0, 6).join('; ') + (miss.length > 6 ? ' ...' : ''));
  let reach = 0; for (let n = 0; n < nodes; n++) if (fromP[n]) reach++;
  info.area = +(reach * G * G).toFixed(0); info.size = [+(x1 - x0).toFixed(0), +(z1 - z0).toFixed(0)];
  return { errs, warns, info };
}
module.exports = { analyse, maps, SKIP };
if (require.main === module) {
  const args = process.argv.slice(2).filter(a => !a.startsWith('-')), quiet = process.argv.includes('--quiet');
  let nerr = 0, nwarn = 0;
  for (const id of args.length ? args : Object.keys(maps)) {
    if (SKIP.has(id) && !args.length) continue;
    const r = analyse(id); nerr += r.errs.length; nwarn += r.warns.length;
    if (quiet && !r.errs.length) continue;
    console.log((r.errs.length ? 'FAIL ' : r.warns.length ? 'warn ' : 'ok   ') + id.padEnd(11) + JSON.stringify(r.info));
    for (const e of r.errs) console.log('   ERROR ' + e);
    for (const w of r.warns) console.log('   warn  ' + w);
  }
  console.log(nerr + ' errors, ' + nwarn + ' warnings');
  process.exit(nerr ? 1 : 0);
}
