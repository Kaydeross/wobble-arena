'use strict';
/*
  Exports every map's collision geometry (boxes, ladders, bounce pads) by running each map's build() against recording stubs.
  Writes shared/maps.json. Part of `npm run content` (see export-content.js). Rendering-only decor (meshes) is not exported.
*/
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ROOT = path.join(__dirname, '..');
const SRC = fs.readFileSync(path.join(ROOT, 'public', 'index.html'), 'utf8');

function grab(re, brace) {                                          // text of a `const X = {..};` or `function f(..) {..}` starting at the regex match, brace matched
  const m = re.exec(SRC); if (!m) throw new Error('not found: ' + re);
  let i = SRC.indexOf(m[0].endsWith('=') || /=\s*$/.test(m[0]) ? '' : '', m.index);
  i = m.index + m[0].length; const start = m.index;
  let depth = 0, q = null, seen = false;
  for (; i < SRC.length; i++) {
    const c = SRC[i];
    if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; }
    if (c === '\'' || c === '"' || c === '`') { q = c; continue; }
    if (c === '/' && SRC[i + 1] === '/') { while (SRC[i] !== '\n') i++; continue; }
    if (c === '{' || c === '[' || c === '(') { depth++; seen = true; }
    else if (c === '}' || c === ']' || c === ')') depth--;
    if (seen && depth === 0 && (brace ? c === '}' : (c === '}' || c === ']' || c === ')'))) { i++; if (SRC[i] === ';') i++; break; }
  }
  return SRC.slice(start, i);
}
const mapsStmts = [grab(/^const MAPS = (?=\{)/m)];
{ const re = /^MAPS\.(\w+) = (?=\{)/gm; let m; while ((m = re.exec(SRC))) { const start = m.index; const sub = SRC.slice(start); const save = SRC; mapsStmts.push(grabAt(start)); } }
function grabAt(start) {                                       // statement `MAPS.x = {...};` starting at index `start`
  let i = SRC.indexOf('{', start), depth = 0, q = null;
  for (; i < SRC.length; i++) {
    const c = SRC[i];
    if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; }
    if (c === '\'' || c === '"' || c === '`') { q = c; continue; }
    if (c === '/' && SRC[i + 1] === '/') { while (SRC[i] !== '\n') i++; continue; }
    if (c === '{' || c === '[' || c === '(') depth++;
    else if (c === '}' || c === ']' || c === ')') { depth--; if (depth === 0) { i++; break; } }
  }
  return SRC.slice(start, i) + ';';
}
const mapsSrc = '(function(){' + mapsStmts.join('\n').replace(/^const MAPS = /, 'var MAPS = ') + '\nreturn MAPS;})()';
const stairsSrc = grab(/^function addStairs(?=\()/m, true);

function noop() { const f = function () { return p; }; const p = new Proxy(f, { get: (t, k) => k === Symbol.toPrimitive ? () => 0 : k === 'then' ? undefined : p, apply: () => p, construct: () => p, set: () => true }); return p; }

function run(id) {
  const rec = { boxes: [], ladders: [], bouncePads: [], floorPads: [] };
  const base = {
    addBox: (x, z, w, d, h, color, yBase = 0) => { rec.boxes.push({ x, z, w, d, h, y: yBase, color }); return noop(); },
    addLadder: (x, z, nx, nz, y0, y1) => rec.ladders.push({ x, z, nx, nz, y0, y1 }),
    addBouncePad: (x, z, power = 17) => rec.bouncePads.push({ x, z, r: 1.2, power }),
    addFloorPad: (size, color) => { rec.floorPads.push({ size, color }); return noop(); },
    addPlayerBlock: () => noop(), addDecor: () => noop(),
    Math: Object.assign(Object.create(Math), { random: () => 0.5 }),
    cfg: { custom: { size: 44, theme: 'grass', obs: 10, plat: 4, pads: 3, walls: 4, ice: false, seed: 7 }, mode: 'classic', blocks: [] },
  };
  const sandbox = new Proxy(base, { has: () => true, get: (t, k) => (k in t ? t[k] : (typeof k === 'symbol' ? undefined : noop())), set: (t, k, v) => { t[k] = v; return true; } });
  const ctx = vm.createContext(sandbox);
  vm.runInContext(stairsSrc, ctx);
  const maps = vm.runInContext(mapsSrc, ctx, { timeout: 5000 });
  const m = maps[id];
  const meta = {};
  for (const k of Object.keys(m)) { const v = m[k]; if (typeof v !== 'function' && k !== 'build') meta[k] = v; }
  let ok = true, err = '';
  try { m.build.call(m); } catch (e) { ok = false; err = e.message; }
  return { id, meta, ok, err, geometry: rec };
}
function ids() {
  const sandbox = new Proxy({}, { has: () => true, get: (t, k) => (typeof k === 'symbol' ? undefined : noop()) });
  return Object.keys(vm.runInContext(mapsSrc, vm.createContext(sandbox)));
}
module.exports = function exportMaps() {
  const out = {}, bad = [];
  for (const id of ids()) {
    if (id === 'custom') continue;                         // generated from room settings at run time
    let r; try { r = run(id); } catch (e) { bad.push(id + ': ' + e.message); continue; }
    if (!r.ok) bad.push(id + ': build failed: ' + r.err);
    out[id] = Object.assign({}, r.meta, { geometry: r.geometry });
  }
  return { maps: out, problems: bad };
};
if (require.main === module) { const r = module.exports(); console.log(Object.keys(r.maps).length + ' maps', r.problems.length ? '\nproblems:\n' + r.problems.join('\n') : ''); console.log(JSON.stringify(r.maps.arena && r.maps.arena.geometry.boxes.slice(0, 3))); }
