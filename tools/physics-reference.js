'use strict';
/* Runs the web game's REAL movement code (Fighter.physics and collide, sliced out of public/index.html) over a scripted input and writes the trace.
   The Godot port must reproduce it (tools/test-physics.js compares them).  node tools/physics-reference.js <map> <out.json> */
const fs = require('fs'), path = require('path'), vm = require('vm');
const SRC = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
function block(startRe) {                                    // from the match to the end of the brace block that follows
  const m = startRe.exec(SRC); if (!m) throw new Error('not found ' + startRe);
  let i = SRC.indexOf('{', m.index + m[0].length - 1), depth = 0, q = null;
  for (; i < SRC.length; i++) {
    const c = SRC[i];
    if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; }
    if (c === '\'' || c === '"' || c === '`') { q = c; continue; }
    if (c === '/' && SRC[i + 1] === '/') { while (SRC[i] !== '\n') i++; continue; }
    if (c === '{') depth++; else if (c === '}') { depth--; if (depth === 0) return SRC.slice(m.index, i + 1); }
  }
}
function script(t) {                                         // deterministic input over 12 s at 60 Hz: run around, jump, stop, run again
  const k = Math.floor(t * 60);
  const a = (k / 90) * Math.PI * 0.7;
  const idle = (k % 240) > 200;
  return { wx: idle ? 0 : Math.cos(a), wz: idle ? 0 : Math.sin(a * 1.3), jump: k % 47 === 0 };
}
module.exports = function trace(mapId, spawn) {
  const maps = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'shared', 'maps.json'), 'utf8'));
  const solids = maps[mapId].geometry.boxes.map(b => ({ minX: b.x - b.w / 2, maxX: b.x + b.w / 2, minZ: b.z - b.d / 2, maxZ: b.z + b.d / 2, top: b.y + b.h, bottom: b.y }));
  const code = 'let R = 0.45, STEP = 0.55, FH = 2.3; const GRAV = 24;\n' + block(/^function collide\(f\) /m).replace(/landDust\(f, -f\.vel\.y\)/, '0') + '\n' +
    'globalThis.physicsFn = ' + block(/^  physics\(dt\) /m).replace(/^\s*physics\(dt\)/, 'function (dt)') + ';';
  const ctx = vm.createContext({ solids, MAPS: { m: {} }, currentMap: 'm', cfg: { grav: 1 }, settings: { ice: 0.5 }, clamp: (v, a, b) => Math.max(a, Math.min(b, v)) });
  vm.runInContext(code, ctx);
  const f = { pos: { x: spawn[0], y: spawn[1], z: spawn[2], addScaledVector(v, s) { this.x += v.x * s; this.y += v.y * s; this.z += v.z * s; } }, vel: { x: 0, y: 0, z: 0 }, wish: { x: 0, z: 0 }, speed: 7.5, grounded: false, wantJump: false, dead: false, downT: 0, trapT: 0, stun: 0, spdT: 0, dashAirT: 0, crouchK: 0,
    ladderStep: () => false, lean: { kick() {} }, head: { kick() {} } };
  const out = [];
  for (let k = 0; k < 720; k++) {
    const s = script(k / 60); f.wish.x = s.wx; f.wish.z = s.wz; f.wantJump = s.jump;
    ctx.physicsFn.call(f, 1 / 60);
    out.push([f.pos.x, f.pos.y, f.pos.z, f.vel.x, f.vel.y, f.vel.z, f.grounded ? 1 : 0, s.wx, s.wz, s.jump ? 1 : 0]);
  }
  return out;
};
if (require.main === module) { const [map, outp] = process.argv.slice(2); const t = module.exports(map, [0, 0.01, 0]); fs.writeFileSync(outp, JSON.stringify(t)); console.log('trace', t.length, 'steps; end', t[t.length - 1].slice(0, 3).map(v => v.toFixed(3)).join(',')); }
