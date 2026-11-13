'use strict';
/* Runs the web game's REAL movement code (Fighter.physics, Fighter.ladderStep, collide and updatePads, sliced out of public/index.html)
   over a scripted input and writes the trace. The Godot port must reproduce it (tools/test-physics.js compares them).
   node tools/physics-reference.js <map> <out.json> [classId] [grav]   (grav = cfg.grav, e.g. 0.15 = Moon Drift)

   Each trace row: [px, py, pz, vx, vy, vz, grounded,  wx, wz, jump,  stunSet, downT, trapT, spdT, dashSet, dead, climbIn, tele,
                    stun, dashAirT, padCool, onLadder]
   Inputs (columns 7-17) are applied before the step; tele = [x, y, z] teleports first (0 = none); stunSet / dashSet >= 0 set
   stun / dashAirT (physics counts them down), downT / trapT / spdT / dead are held at the given value (Fighter.timers owns them). */
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
const DT = 1 / 60;
function baseInput(k) {                                      // 12 s: run around, jump, stop, run again; status effects in windows
  const a = (k / 90) * Math.PI * 0.7;
  const idle = (k % 240) > 200;
  return {
    wx: idle ? 0 : Math.cos(a), wz: idle ? 0 : Math.sin(a * 1.3), jump: k % 47 === 0,
    stunSet: [60, 300, 520].includes(k) ? 0.45 : -1,
    downT: k >= 350 && k < 420 ? 0.5 : 0,
    trapT: k >= 430 && k < 470 ? 0.5 : 0,
    spdT: k >= 180 && k < 300 ? 3 : 0,
    dashSet: [140, 470, 612].includes(k) ? 0.6 : -1,
    dead: k >= 640 && k < 680,
    climbIn: 0, tele: 0,
  };
}
function idle() { return { wx: 0, wz: 0, jump: false, stunSet: -1, downT: 0, trapT: 0, spdT: 0, dashSet: -1, dead: false, climbIn: 0, tele: 0 }; }
function script(map) {                                       // base run, then every bounce pad and ladder (up to 2 each) is used
  const out = [];
  for (let k = 0; k < 720; k++) out.push(baseInput(k));
  const geo = map.geometry;
  for (const pd of geo.bouncePads.slice(0, 2)) {
    for (let k = 0; k < 150; k++) {                          // drop onto the pad, bounce twice, then walk off it
      const s = idle();
      if (k === 0) s.tele = [pd.x, 0.3, pd.z];
      if (k >= 110) { s.wx = 1; s.wz = 0.2; }
      out.push(s);
    }
  }
  for (const l of geo.ladders.slice(0, 2)) {
    const start = [l.x + l.nx * 1.4, l.y0 + 0.01, l.z + l.nz * 1.4];
    for (let k = 0; k < 360; k++) {
      const s = idle();
      if (k === 0 || k === 150 || k === 260) s.tele = start.slice();
      s.wx = -l.nx; s.wz = -l.nz;                            // walk into the wall: grabs the ladder
      if (k < 150) s.climbIn = 1;                            // climb to the top and step off
      else if (k < 190) s.climbIn = 1;                       // climb a bit...
      else if (k < 260) { s.climbIn = -1; s.wx = 0; s.wz = 0; }     // ...then back down to the floor
      else { s.climbIn = 1; if (k === 285) s.jump = true; if (k === 300) s.stunSet = 0.3; }   // grab again, jump off, get hit
      out.push(s);
    }
  }
  return out;
}
module.exports = function trace(mapId, spawn, cls, grav = 1) {
  const maps = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'shared', 'maps.json'), 'utf8'));
  const map = maps[mapId];
  const solids = map.geometry.boxes.map(b => ({ minX: b.x - b.w / 2, maxX: b.x + b.w / 2, minZ: b.z - b.d / 2, maxZ: b.z + b.d / 2, top: b.y + b.h, bottom: b.y }));
  const ladders = map.geometry.ladders.map(l => Object.assign({}, l));
  const stub = { scale: { set() {} } };
  const pads = map.geometry.bouncePads.map(p => Object.assign({ mesh: stub, core: stub, squash: 0 }, p));
  const code = 'let R = 0.45, STEP = 0.55, FH = 2.3; const GRAV = 24;\n' + block(/^function collide\(f\) /m).replace(/landDust\(f, -f\.vel\.y\)/, '0') + '\n' +
    block(/^function updatePads\(dt\) /m) + '\n' +
    'globalThis.updatePadsFn = updatePads;\n' +
    'globalThis.physicsFn = ' + block(/^  physics\(dt\) /m).replace(/^\s*physics\(dt\)/, 'function (dt)') + ';\n' +
    'globalThis.ladderFn = ' + block(/^  ladderStep\(dt\) /m).replace(/^\s*ladderStep\(dt\)/, 'function (dt)') + ';';
  const mapFlags = {}; if (map.grip !== undefined) mapFlags.grip = map.grip; if (map.ceil !== undefined) mapFlags.ceil = map.ceil;
  const f = { pos: { x: spawn[0], y: spawn[1], z: spawn[2], addScaledVector(v, s) { this.x += v.x * s; this.y += v.y * s; this.z += v.z * s; }, set(x, y, z) { this.x = x; this.y = y; this.z = z; } },
    vel: { x: 0, y: 0, z: 0, set(x, y, z) { this.x = x; this.y = y; this.z = z; } }, wish: { x: 0, z: 0 }, speed: 7.5, cls: Object.assign({ spd: 1, acc: 1, air: 1, jump: 1 }, cls || {}), grounded: false, wantJump: false,
    dead: false, downT: 0, trapT: 0, stun: 0, spdT: 0, dashAirT: 0, padCool: 0, crouchK: 0, isPlayer: true, onLadder: null, climbIn: 0,
    armVel: { y: 0 }, lean: { kick() {} }, head: { kick() {} } };
  const ctx = vm.createContext({ solids, ladders, pads, fighters: [f], MAPS: { m: mapFlags }, currentMap: 'm', cfg: { grav }, settings: { ice: 0.6 },
    clamp: (v, a, b) => Math.max(a, Math.min(b, v)), rand: () => 0, puff() {}, sfx() {}, sfxAt() {}, V: () => null });
  vm.runInContext(code, ctx);
  f.ladderStep = ctx.ladderFn;
  const out = [];
  for (const s of script(map)) {
    if (s.tele) { f.pos.set(s.tele[0], s.tele[1], s.tele[2]); f.vel.set(0, 0, 0); f.onLadder = null; f.grounded = false; }
    f.wish.x = s.wx; f.wish.z = s.wz; f.wantJump = s.jump; f.climbIn = s.climbIn;
    if (s.stunSet >= 0) f.stun = s.stunSet;
    if (s.dashSet >= 0) f.dashAirT = s.dashSet;
    f.downT = s.downT; f.trapT = s.trapT; f.spdT = s.spdT; f.dead = s.dead;
    f.padCool -= DT;                                         // Fighter.timers
    ctx.physicsFn.call(f, DT);
    ctx.updatePadsFn(DT);
    out.push([f.pos.x, f.pos.y, f.pos.z, f.vel.x, f.vel.y, f.vel.z, f.grounded ? 1 : 0, s.wx, s.wz, s.jump ? 1 : 0,
      s.stunSet, s.downT, s.trapT, s.spdT, s.dashSet, s.dead ? 1 : 0, s.climbIn, s.tele,
      f.stun, f.dashAirT, f.padCool, f.onLadder ? 1 : 0]);
  }
  return out;
};
if (require.main === module) {
  const [map, outp, clsId, grav] = process.argv.slice(2);
  const t = module.exports(map, [0, 0.01, 0], clsId ? JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'shared', 'classes.json'), 'utf8'))[clsId] : null, grav ? +grav : 1);
  fs.writeFileSync(outp, JSON.stringify(t));
  console.log('trace', t.length, 'steps; end', t[t.length - 1].slice(0, 3).map(v => v.toFixed(3)).join(','), 'ladder steps', t.filter(r => r[21]).length);
}
