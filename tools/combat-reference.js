'use strict';
/* Runs the web game's REAL combat code (Fighter.hit, topple, kick, melee swing + sweep, fireGun, pickup/reload, timers/respawn,
   thrown knives, sliced out of public/index.html) over a scripted scenario and records the state after every op.
   The Godot port must reproduce it: tools/test-combat.js runs godot/tests/combat_test.gd on the same scenario and compares.

   Determinism: Math.random is replaced by the Park-Miller generator that godot/logic/combat_rng.gd implements
   (state = state * 48271 % 2147483647, exact in doubles). Everything visual (meshes, particles, sounds, HUD) is stubbed
   with no-ops that never call Math.random, so only the gameplay code consumes random numbers, in the same order as Godot.
   Wall raycasts (three.js meshes in the game) are a ray-vs-box slab test here and in Godot (godot/logic/weapons.gd ray_box).

   node tools/combat-reference.js <out.json>   (writes {scenario, states, net}) */
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = path.join(__dirname, '..');
const SRC = fs.readFileSync(path.join(ROOT, 'public', 'index.html'), 'utf8');
const J = f => JSON.parse(fs.readFileSync(path.join(ROOT, 'shared', f), 'utf8'));

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
  throw new Error('unclosed ' + startRe);
}
function line(startRe) { const m = startRe.exec(SRC); if (!m) throw new Error('not found ' + startRe); return SRC.slice(m.index, SRC.indexOf('\n', m.index)); }

/* ---- three.js Vector3, same operation order as three.js r16x ---- */
class Vector3 {
  constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; }
  set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; }
  setY(y) { this.y = y; return this; }
  copy(v) { this.x = v.x; this.y = v.y; this.z = v.z; return this; }
  clone() { return new Vector3(this.x, this.y, this.z); }
  add(v) { this.x += v.x; this.y += v.y; this.z += v.z; return this; }
  sub(v) { this.x -= v.x; this.y -= v.y; this.z -= v.z; return this; }
  addScaledVector(v, s) { this.x += v.x * s; this.y += v.y * s; this.z += v.z * s; return this; }
  multiplyScalar(s) { this.x *= s; this.y *= s; this.z *= s; return this; }
  divideScalar(s) { return this.multiplyScalar(1 / s); }
  dot(v) { return this.x * v.x + this.y * v.y + this.z * v.z; }
  lengthSq() { return this.x * this.x + this.y * this.y + this.z * this.z; }
  length() { return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z); }
  normalize() { return this.divideScalar(this.length() || 1); }
  lerp(v, a) { this.x += (v.x - this.x) * a; this.y += (v.y - this.y) * a; this.z += (v.z - this.z) * a; return this; }
  applyQuaternion(q) {
    const x = this.x, y = this.y, z = this.z, qx = q.x, qy = q.y, qz = q.z, qw = q.w;
    const ix = qw * x + qy * z - qz * y, iy = qw * y + qz * x - qx * z, iz = qw * z + qx * y - qy * x, iw = -qx * x - qy * y - qz * z;
    this.x = ix * qw + iw * -qx + iy * -qz - iz * -qy; this.y = iy * qw + iw * -qy + iz * -qx - ix * -qz; this.z = iz * qw + iw * -qz + ix * -qy - iy * -qx;
    return this;
  }
  distanceTo(v) { const dx = this.x - v.x, dy = this.y - v.y, dz = this.z - v.z; return Math.sqrt(dx * dx + dy * dy + dz * dz); }
}
/* three.js Quaternion (the parts the arm needs) */
class Quaternion {
  constructor() { this.x = 0; this.y = 0; this.z = 0; this.w = 1; }
  set(x, y, z, w) { this.x = x; this.y = y; this.z = z; this.w = w; return this; }
  setFromUnitVectors(a, b) {
    let r = a.x * b.x + a.y * b.y + a.z * b.z + 1;
    if (r < 1e-8) { r = 0; if (Math.abs(a.x) > Math.abs(a.z)) { this.x = -a.y; this.y = a.x; this.z = 0; this.w = r; } else { this.x = 0; this.y = -a.z; this.z = a.y; this.w = r; } }
    else { this.x = a.y * b.z - a.z * b.y; this.y = a.z * b.x - a.x * b.z; this.z = a.x * b.y - a.y * b.x; this.w = r; }
    const l = Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z + this.w * this.w);
    if (l === 0) { this.x = 0; this.y = 0; this.z = 0; this.w = 1; } else { const il = 1 / l; this.x *= il; this.y *= il; this.z *= il; this.w *= il; }
    return this;
  }
}
/* same slab test as Weapons.ray_box in Godot */
function rayBox(o, d, x0, y0, z0, x1, y1, z1) {
  let tmin = -Infinity, tmax = Infinity; const O = [o.x, o.y, o.z], D = [d.x, d.y, d.z], L = [x0, y0, z0], H = [x1, y1, z1];
  for (let a = 0; a < 3; a++) {
    if (D[a] === 0) { if (O[a] < L[a] || O[a] > H[a]) return -1; continue; }
    const inv = 1 / D[a]; let t1 = (L[a] - O[a]) * inv, t2 = (H[a] - O[a]) * inv;
    if (t1 > t2) { const tt = t1; t1 = t2; t2 = tt; }
    if (t1 > tmin) tmin = t1; if (t2 < tmax) tmax = t2; if (tmin > tmax) return -1;
  }
  if (tmax < 0 || tmin < 0) return -1;
  return tmin;
}

const FIGHTER_METHODS = ['get ammo\\(\\)', 'set ammo\\(v\\)', 'equipSlot\\(i\\)', 'clearInventory\\(\\)', 'autoReload\\(\\)', 'startReload\\(\\)', 'cancelReload\\(keepPending\\)',
  'finishReload\\(\\)', 'tickReload\\(dt\\)', 'autoEq\\(i\\)', 'pickup\\(key\\)', 'dropSlot\\(\\)', 'afterSwing\\(\\)', 'spheres\\(\\)', 'timers\\(dt\\)', 'respawn\\(\\)',
  'placeAt\\(x, z, y = 0.01\\)', 'hit\\(dmg, dir, force, head, attacker\\)', 'topple\\(dur, msg\\)', 'startKick\\(yaw\\)', 'kickStep\\(dt\\)', 'katanaTarget\\(yaw\\)',
  'meleeBegin\\(w, yaw\\)', 'meleeTick\\(w, dt, yaw\\)', 'meleeSweep\\(\\)', 'barrelDir\\(out\\)', 'fireGun\\(w\\)'];
const FUNCS = ['function raySphere\\(', 'function aimFromHand\\(', 'function clampToWalls\\(', 'function hasLOS\\(', 'function inSolid\\(', 'function isFriend\\(',
  'function addKo\\(', 'function useAmmo\\(', 'function shove\\(', 'function doKick\\(', 'function throwKnife\\(', 'function releaseKnife\\(', 'function updateKnives\\(',
  'function netNum\\(', 'function netCleanHit\\('];
const LINES = [/^const DOWN = .*/m, /^const GUN_KEYS = .*/m, /^const UZI_SIDE = .*/m, /^const shotSpread = .*/m, /^const BAT_BASE = .*/m, /^const newSt = .*/m, /^const hpOf = .*/m, /^const HIT_MAX = .*/m, /^const BOT_RESPAWN = .*/m, /^const ladderOn = .*/m];

function makeContext() {
  const noop = () => {};
  const ctx = {
    console, Math: Object.create(Math), Infinity, NaN, Set, Map, Object, Array, JSON, Number, Boolean, String,
    WEAPONS: J('weapons.json'), CLASSES: J('classes.json'), MODES: J('modes.json'),
    cfg: { grav: 1, kb: 1, inf: false, mode: 'classic', behav: 'brawl', ffa: true, limit: 0, hp: 200, lives: 0, teams: 0 },
    settings: { autoSwitch: false, killcam: false, ice: 0.6 }, DEVS: {}, net: null, netApply: false, pot: null, shrink: null, matchOver: false,
    simTime: 0, recN: 0, hurtFlash: 0, kcPending: null, stats: { kos: 0, best: 0 }, wallet: { coins: 0 }, fighters: [], knives: [], solids: [], solidMeshes: [],
    MAPS: { m: { spawns: [[0, 0]] } }, currentMap: 'm', cam: { shake: 0, aim: 0, yaw: 0 }, aimPoint: new Vector3(0, 1.5, -20), GIANT: false, NETLOG: [],
    V: (x, y, z) => new Vector3(x, y, z), Vector3,
    clamp: (v, a, b) => Math.max(a, Math.min(b, v)), lerp: (a, b, t) => a + (b - a) * t,
    puff: noop, koBurst: noop, koPop: noop, feedAdd: noop, dmgNumber: noop, toast: noop, sfx: noop, hitMarker: noop, tracer: noop, bulletTracer: noop, bulletHole: noop,
    ejectShell: noop, flameFx: noop, updateCoins: noop, updateKoText: noop, endMatch: noop, ggAdvance: noop, ggGive: noop, eliminate: (f) => { f.elim = true; }, passPotato: noop,
    dashTick: noop, el: () => null, landDust: noop, ringFx: noop, tyInFlight: () => false,
    makeKnifeMesh: () => ({ position: { copy() {} }, lookAt() {}, inner: { rotation: { y: 0 } } }), scene: { add() {}, remove() {} },
    netSend: m => ctx.NETLOG.push(JSON.parse(JSON.stringify(m))),
  };
  ctx.giantOn = () => ctx.GIANT;
  ctx.tmpA = new Vector3(); ctx.tmpB = new Vector3(); ctx.tmpC = new Vector3(); ctx.tmpD = new Vector3(); ctx.tmpE = new Vector3();
  ctx.rand = (a, b) => a + ctx.Math.random() * (b - a);
  ctx.raycaster = {
    o: new Vector3(), d: new Vector3(), far: Infinity,
    set(o, d) { this.o.copy(o); this.d.copy(d); },
    intersectObjects() {
      const out = [];
      for (const b of ctx.solids) { const t = rayBox(this.o, this.d, b.minX, b.bottom, b.minZ, b.maxX, b.top, b.maxZ); if (t >= 0 && t <= this.far) out.push({ distance: t }); }
      return out.sort((a, b) => a.distance - b.distance);
    },
  };
  let code = '"use strict";\n';
  for (const r of LINES) code += line(r) + '\n';
  for (const f of FUNCS) code += block(new RegExp('^' + f, 'm')) + '\n';
  code += 'class FighterBase {\n';
  for (const m of FIGHTER_METHODS) code += block(new RegExp('^  ' + m + ' ', 'm')) + '\n';
  // setWeapon builds meshes in the game; only its gameplay part is kept (same as Combat.set_weapon)
  code += '  setWeapon(key) { this.weapon = key; this.swing = -1; this.batValid = false; this.nocked = false; this.grabT = -1; this.draw = 0; }\n';
  code += '  reloadCleanup() {}\n}\n';
  code += 'globalThis.armQuat = function() { this.arm.quaternion.setFromUnitVectors(DOWN, this.armDir);\n' + block(/^    if \(this\.slot >= 0 && GUN_KEYS\.includes\(this\.weapon\) && !this\.dead\)/m) + '\n};\n';
  code += 'globalThis.FighterBase = FighterBase; globalThis.useAmmo = useAmmo; globalThis.shove = shove; globalThis.doKick = doKick; globalThis.throwKnife = throwKnife;' +
    'globalThis.updateKnives = updateKnives; globalThis.netCleanHit = netCleanHit; globalThis.PROJ = { knife: throwKnife }; globalThis.newSt = newSt; globalThis.hpOf = hpOf; globalThis.BAT_N = BAT_N;';
  vm.createContext(ctx);
  vm.runInContext(code, ctx);
  return ctx;
}
function seedRandom(ctx, seed) { let s = seed; ctx.Math.random = () => (s = s * 48271 % 2147483647, (s - 1) / 2147483646); }

/* ---- fighters ---- */
function mkFighter(ctx, d, i) {
  const f = Object.create(ctx.FighterBase.prototype);
  const kick = (rec) => ({ kick(a, b) { rec[0] += a; rec[1] += b; } });
  Object.assign(f, {
    id: i, isPlayer: !!d.player, isGhost: !!d.ghost, netSlot: d.netSlot, home: d.home || null, team: d.team | 0, lives: d.lives | 0, elim: false, ko: 0, left: false,
    pos: new Vector3(...d.pos), vel: new Vector3(), grounded: d.grounded !== false, yaw: d.yaw || 0, faceYaw: 0,
    hp: 0, dead: false, deathT: 0, fallSide: 1, fellT: false, downT: 0, getupImmune: 0, stun: 0, invuln: 0, flash: 0, shieldT: 0, rageT: 0, spdT: 0, trapT: 0, struggle: 0,
    burn: 0, burnAcc: 0, burner: null, lastAttacker: null, lastHitTime: -99,
    weapon: 'spatula', slots: [null, null, null], slot: -1, returnSlot: null, reloading: false, rlT: 0, rlSlot: -1, rlDur: 1, rlShells: 0, rlLoaded: 0,
    cool: 0, meleeCool: 0, shoveCool: 0, kickCool: 0, padCool: 0, climb: 0, climbBack: 1, lastShotT: -9, hipD: 0, sfxT: -9, uziSide: 0, uziK: [0, 0],
    swing: -1, swingYaw: 0, swingHit: new Set(), batValid: false, batNow: [], batPrev: [], slam: false, stab: false, cyclone: false, assistOn: false, katN: 0, katT: -9,
    kickT: -1, kickYaw: 0, kickResolved: false, kickLeaned: false, throwFn: null, throwT: 0, thrown: false, throwHold: false, knifeT: -1, twirlLen: 1.4,
    dmgScale: d.dmgScale || 1, cls: ctx.CLASSES[d.cls || 'wobbler'], clsId: d.cls || 'wobbler', st: ctx.newSt(), emote: null, fall: { a: 0, v: 0 },
    handPos: new Vector3(), armDir: new Vector3(0, 0, 1), aimTarget: new Vector3(0, 0, 1), shoulderPos: new Vector3(), headPos: new Vector3(), chestPos: new Vector3(), legPos: new Vector3(),
    armVel: new Vector3(), LEAN: [0, 0], HEAD: [0, 0], off: { head: [0, 1.95, 0], chest: [0, 1.22, 0], hand: [0.3, 1.3, 0.4], shoulder: [0.3, 1.55, 0] }, follow: true,
  });
  f.arm = { quaternion: new Quaternion() }; f.armQuat = ctx.armQuat;
  f.lean = kick(f.LEAN); f.head = kick(f.HEAD);
  for (let k = 0; k < ctx.BAT_N; k++) { f.batNow.push(new Vector3()); f.batPrev.push(new Vector3()); }
  f.hp = ctx.hpOf(f);
  return f;
}
/* the animation's points: offsets from the feet; the arm points where it is aimed (follow) or where the op says */
function pose(f) {
  const p = f.pos, o = f.off;
  f.headPos.set(p.x + o.head[0], p.y + o.head[1], p.z + o.head[2]);
  f.chestPos.set(p.x + o.chest[0], p.y + o.chest[1], p.z + o.chest[2]);
  f.handPos.set(p.x + o.hand[0], p.y + o.hand[1], p.z + o.hand[2]);
  f.shoulderPos.set(p.x + o.shoulder[0], p.y + o.shoulder[1], p.z + o.shoulder[2]);
  f.legPos.set(p.x, p.y + 0.5, p.z);
  if (f.follow) f.armDir.copy(f.aimTarget);
  f.armQuat();
}
const FIELD = { shieldT: 1, rageT: 1, downT: 1, trapT: 1, invuln: 1, yaw: 1, hp: 1, stun: 1, burn: 1, getupImmune: 1, cool: 1, kickCool: 1, shoveCool: 1, climb: 1, hipD: 1, dmgScale: 1, lastHitTime: 1, grounded: 1 };

function dump(ctx) {
  const F = ctx.fighters.map(f => {
    const sl = f.slots.map(s => s ? [s.key, s.ammo, s.mag === undefined ? -1 : s.mag, s.pend ? 1 : 0] : null);
    return [f.pos.x, f.pos.y, f.pos.z, f.vel.x, f.vel.y, f.vel.z, f.grounded ? 1 : 0, f.hp, f.dead ? 1 : 0, f.deathT, f.downT, f.getupImmune, f.stun, f.invuln, f.flash,
      f.cool, f.swing, f.kickT, f.weapon || '', f.slot, JSON.stringify(sl), f.reloading ? 1 : 0, f.rlT, f.ko, f.st.hits, f.st.dmg, f.st.taken, f.st.deaths, f.st.heads, f.st.shots,
      f.st.streak, f.st.multi, f.LEAN[0], f.LEAN[1], f.HEAD[0], f.HEAD[1], f.armVel.x, f.armVel.y, f.armVel.z, f.aimTarget.x, f.aimTarget.y, f.aimTarget.z, f.climb, f.fallSide,
      f.throwT, f.knifeT, f.returnSlot === null ? -1 : f.returnSlot, f.lives, f.elim ? 1 : 0, f.melee || 0, f.lastHitTime, f.spin || 0, f.uziSide];
  });
  const K = ctx.knives.map(k => [k.pos.x, k.pos.y, k.pos.z, k.vel.x, k.vel.y, k.vel.z, k.age, k.stuck]);
  const out = { f: F, k: K, net: ctx.NETLOG.slice() }; ctx.NETLOG.length = 0;
  return out;
}

/* ---- ops (the Godot test implements exactly the same) ---- */
function apply(ctx, op) {
  const F = ctx.fighters, f = F[op.f];
  switch (op.op) {
    case 'cfg':
      if (op.key === 'giant') ctx.GIANT = !!op.val;
      else if (op.key === 'net') ctx.net = op.val ? { started: true, host: true, slotKind: op.val.kinds } : null;
      else if (op.key === 'spawns') ctx.MAPS.m = { spawns: op.val, spawnY: op.y };
      else if (op.key === 'solids') ctx.solids = op.val;
      else if (op.key === 'aim') ctx.cam.aim = op.val;
      else if (op.key === 'aimPoint') ctx.aimPoint.set(...op.val);
      else ctx.cfg[op.key] = op.val;
      break;
    case 'set': if (op.key === 'burner') f.burner = F[op.val]; else f[op.key] = op.val; break;
    case 'place': f.pos.set(...op.p); break;
    case 'vel': f.vel.set(...op.v); break;
    case 'pose': Object.assign(f.off, op.off || {}); if (op.arm) { f.follow = false; f.armDir.set(...op.arm); } else f.follow = true; if (op.aim) f.aimTarget.set(...op.aim); break;
    case 'class': f.cls = ctx.CLASSES[op.cls]; f.clsId = op.cls; break;
    case 'hit': F.forEach(pose); f.hit(op.dmg, new Vector3(...op.dir), op.force, !!op.head, op.a >= 0 ? F[op.a] : null); break;
    case 'nethit': { ctx.netApply = true; try { F.forEach(pose); f.hit(op.dmg, new Vector3(...op.dir), op.force, !!op.head, F[op.a]); } finally { ctx.netApply = false; } break; }
    case 'topple': f.topple(op.dur); break;
    case 'pickup': f.pickup(op.key); break;
    case 'equip': f.equipSlot(op.i); break;
    case 'reload': f.startReload(); break;
    case 'placeAt': f.placeAt(op.x, op.z, op.y); break;
    case 'fire': {                                          // playerControl's gun / PROJ lines
      F.forEach(pose);
      const w = ctx.WEAPONS[f.weapon] || ctx.WEAPONS.spatula, p = f;
      if (p.dead || p.downT > 0) break;
      if (w.type === 'gun') {
        const gs = p.slot >= 0 ? p.slots[p.slot] : null;
        if (gs && w.mag && gs.mag !== undefined && !ctx.cfg.inf) { if (gs.mag <= 0 && gs.ammo > 0 && !p.reloading) p.startReload(); }
        if (p.cool <= 0 && p.swing < 0 && !p.reloading) { p.cool = w.cooldown; p.fireGun(w); ctx.useAmmo(p); }
      } else if (ctx.PROJ[w.type]) {
        if (p.cool <= 0 && p.swing < 0) { p.cool = w.cooldown; ctx.PROJ[w.type](p, w); ctx.useAmmo(p); }
      }
      break;
    }
    case 'hold': {                                          // playerControl's gun lines with the fire button held/released (minigun spin-up)
      F.forEach(pose);
      const w = ctx.WEAPONS[f.weapon] || ctx.WEAPONS.spatula, p = f, dt = op.dt, mouse = { l: !!op.held };
      if (!w.spinup) p.spin = 0;
      if (p.dead || p.downT > 0 || w.type !== 'gun') break;
      const gs = p.slot >= 0 ? p.slots[p.slot] : null;
      if (gs && w.mag && gs.mag !== undefined && !ctx.cfg.inf) { if (gs.mag <= 0 && gs.ammo > 0 && !p.reloading) p.startReload(); }
      if (w.spinup) { p.spin = mouse.l ? Math.min(w.spinup, p.spin + dt) : Math.max(0, p.spin - dt * 2); }
      if (mouse.l && p.cool <= 0 && p.swing < 0 && !p.reloading && (!w.spinup || p.spin >= w.spinup)) { p.cool = w.cooldown; p.fireGun(w); ctx.useAmmo(p); }
      break;
    }
    case 'melee': {                                         // playerControl's melee line
      const w = ctx.WEAPONS[f.weapon] || ctx.WEAPONS.spatula, p = f;
      if (w.type !== 'melee' || p.dead || p.downT > 0) break;
      if (p.cool <= 0 && p.swing < 0 && !p.throwFn) { p.meleeBegin(w, op.yaw); p.melee = op.yaw; if (p.slot >= 0) p.ammo -= 1; }
      break;
    }
    case 'kick': ctx.cam.yaw = op.yaw; ctx.doKick(f); break;
    case 'shove': ctx.cam.yaw = op.yaw; ctx.shove(f); break;
    case 'step':
      for (let n = 0; n < op.n; n++) {
        F.forEach(pose);
        for (const g of F) g.timers(op.dt);
        for (const g of F) {                                // swing input (meleeTick) keeps aiming where the swing started
          const w = ctx.WEAPONS[g.weapon] && ctx.WEAPONS[g.weapon].swingTime ? ctx.WEAPONS[g.weapon] : ctx.WEAPONS.spatula;
          if (g.swing >= 0 && !g.dead && g.meleeTick(w, op.dt, g.melee || 0)) g.afterSwing();
        }
        ctx.updateKnives(op.dt);
        ctx.simTime += op.dt;
        F.forEach(pose);
        for (const g of F) g.meleeSweep();
      }
      break;
    default: throw new Error('unknown op ' + op.op);
  }
}

/* ---- the scenario: hand-written blocks plus a seeded storm of hits. Append new weapon blocks at the end of `blocks`. ---- */
function scenario() {
  let s = 12345; const r = () => (s = s * 48271 % 2147483647, (s - 1) / 2147483646);
  const pick = a => a[Math.floor(r() * a.length)], R = (a, b) => +(a + r() * (b - a)).toFixed(4);
  const fighters = [
    { pos: [0, 0, 0], cls: 'wobbler', player: true, netSlot: 0 },
    { pos: [0, 0, 1.6], cls: 'bruiser', netSlot: 1, yaw: 3.1 },
    { pos: [1.2, 0, 1.0], cls: 'kid', netSlot: 2, yaw: 2.2 },
    { pos: [-1.0, 0, 6], cls: 'alien', netSlot: 3, yaw: 3.0 },
    { pos: [4, 0, -3], cls: 'elder', netSlot: 4, yaw: 0.4, dmgScale: 0.8 },
  ];
  const ops = [];
  const step = (n, dt = 1 / 120) => ops.push({ op: 'step', n, dt });
  ops.push({ op: 'cfg', key: 'spawns', val: [[0, 0], [5, 5], [-6, 2], [3, -7]], y: 0.01 });
  ops.push({ op: 'cfg', key: 'solids', val: [{ minX: -20, maxX: 20, minZ: -20, maxZ: 20, top: 0, bottom: -1 }, { minX: -3, maxX: 3, minZ: 12, maxZ: 13, top: 4, bottom: 0 }] });
  for (let i = 0; i < fighters.length; i++) ops.push({ op: 'placeAt', f: i, x: fighters[i].pos[0], z: fighters[i].pos[2], y: 0.01 });
  for (let i = 0; i < fighters.length; i++) ops.push({ op: 'set', f: i, key: 'invuln', val: 0 });
  const blocks = {
    hits() {                                        // Fighter.hit: every modifier, light/heavy, classes, death and respawn
      for (const [m, kb] of [['classic', 1], ['mega', 1], ['giant', 0], ['pillars', 2]]) {
        ops.push({ op: 'cfg', key: 'mode', val: m }, { op: 'cfg', key: 'kb', val: kb });
        for (let k = 0; k < 6; k++) ops.push({ op: 'hit', f: 1 + (k % 4), a: k % 5 === 4 ? -1 : 0, dmg: 3 + k * 4, dir: [0.6, 0.2 * k - 0.3, -0.5], force: k * 2.5, head: k % 3 === 0 ? 1 : 0 });
        step(3);
      }
      ops.push({ op: 'cfg', key: 'mode', val: 'classic' }, { op: 'cfg', key: 'kb', val: 1 });
      ops.push({ op: 'set', f: 0, key: 'rageT', val: 2 }, { op: 'set', f: 1, key: 'shieldT', val: 1.5 }, { op: 'hit', f: 1, a: 0, dmg: 20, dir: [0, 0, 1], force: 9, head: 0 });
      ops.push({ op: 'set', f: 2, key: 'downT', val: 0.8 }, { op: 'hit', f: 2, a: 1, dmg: 16, dir: [1, 0.5, 0], force: 7.9, head: 0 });
      ops.push({ op: 'set', f: 2, key: 'trapT', val: 0.5 }, { op: 'hit', f: 2, a: 1, dmg: 16, dir: [1, 0.5, 0], force: 8, head: 0 });
      step(70);
      ops.push({ op: 'cfg', key: 'teams', val: 2 }, { op: 'set', f: 3, key: 'team', val: 1 }, { op: 'set', f: 4, key: 'team', val: 1 });
      ops.push({ op: 'hit', f: 4, a: 3, dmg: 50, dir: [0, 0, -1], force: 12 }, { op: 'hit', f: 4, a: 0, dmg: 50, dir: [0, 0, -1], force: 12 });
      ops.push({ op: 'cfg', key: 'teams', val: 0 });
      for (let k = 0; k < 8; k++) ops.push({ op: 'hit', f: 3, a: 0, dmg: 60, dir: [0.1, 0.3, 1], force: 14, head: k & 1 });        // K.O. -> deathT -> respawn with invuln
      ops.push({ op: 'hit', f: 2, a: 2, dmg: 500, dir: [0, 1, 0], force: 3 });           // self K.O.
      step(240, 1 / 60); step(400, 1 / 120);
      ops.push({ op: 'hit', f: 3, a: 0, dmg: 10, dir: [1, 0, 0], force: 10 });            // spawn protection
      step(330);
    },
    topple() {                                      // topple + getup immunity, burn, trap struggle, player regen
      ops.push({ op: 'topple', f: 1, dur: 3 }, { op: 'topple', f: 1, dur: 1 }); step(200);
      ops.push({ op: 'topple', f: 1, dur: 1 }); step(130); ops.push({ op: 'topple', f: 1, dur: 0.5 });
      ops.push({ op: 'set', f: 4, key: 'burn', val: 1.3 }, { op: 'set', f: 4, key: 'burner', val: 2 }, { op: 'set', f: 3, key: 'trapT', val: 0.7 });
      step(180);
      ops.push({ op: 'hit', f: 0, a: 1, dmg: 40, dir: [0, 0, -1], force: 6 }); step(700, 1 / 120);
    },
    kickShove() {
      ops.push({ op: 'kick', f: 0, yaw: 0 }); step(80);
      ops.push({ op: 'kick', f: 0, yaw: Math.PI }); step(140);
      ops.push({ op: 'kick', f: 0, yaw: 0.3 }); step(140);
      ops.push({ op: 'shove', f: 0, yaw: 0 }); step(10); ops.push({ op: 'shove', f: 0, yaw: 0 }); step(120); ops.push({ op: 'shove', f: 0, yaw: 0.5 });
    },
    melee() {                                       // spatula and bat swings: the capsule sweep at 3 sub-steps, one hit per target per swing
      for (const i of [0, 1, 2, 3, 4]) ops.push({ op: 'placeAt', f: i, x: [0, 0, 1.0, -1.2, 3][i], z: [0, 1.5, 0.9, 0.7, 3][i], y: 0.01 }, { op: 'set', f: i, key: 'invuln', val: 0 });
      ops.push({ op: 'melee', f: 0, yaw: 0 }); step(160);
      ops.push({ op: 'melee', f: 0, yaw: 0.6 }); step(40); ops.push({ op: 'melee', f: 0, yaw: 0.6 }); step(120);
      ops.push({ op: 'set', f: 0, key: 'grounded', val: false }, { op: 'melee', f: 0, yaw: 0 }); step(90); ops.push({ op: 'set', f: 0, key: 'grounded', val: true });
      ops.push({ op: 'pickup', f: 0, key: 'bat' }, { op: 'melee', f: 0, yaw: -0.2 }); step(200);
      ops.push({ op: 'pickup', f: 1, key: 'bat' }, { op: 'melee', f: 1, yaw: Math.PI }); step(200);
      ops.push({ op: 'cfg', key: 'giant', val: 1 }, { op: 'melee', f: 0, yaw: 0.1 }); step(200); ops.push({ op: 'cfg', key: 'giant', val: 0 });
      ops.push({ op: 'pickup', f: 0, key: 'katana' }, { op: 'melee', f: 0, yaw: 0 }); step(100); ops.push({ op: 'melee', f: 0, yaw: 0 }); step(100);
      for (let k = 0; k < 7; k++) { ops.push({ op: 'pickup', f: 0, key: 'bat' }, { op: 'melee', f: 0, yaw: k * 0.4 }); step(130); }     // the bat breaks after its swings
    },
    smg() {                                         // fireGun: spread, assist, recoil, climb, mag, reload with class rate/reload/ammo
      for (const i of [0, 1, 2, 3, 4]) ops.push({ op: 'placeAt', f: i, x: [0, 0.4, 1.5, -1, 0][i], z: [0, 9, 14, 20, -5][i], y: 0.01 }, { op: 'set', f: i, key: 'invuln', val: 0 });
      ops.push({ op: 'class', f: 0, cls: 'alien' }, { op: 'pickup', f: 0, key: 'smg' }, { op: 'pose', f: 0, aim: [0.02, 0.0, 1] });
      for (let k = 0; k < 70; k++) { ops.push({ op: 'fire', f: 0 }); step(4); }
      ops.push({ op: 'reload', f: 0 }); step(300);
      ops.push({ op: 'class', f: 4, cls: 'elder' }, { op: 'pickup', f: 4, key: 'smg' }, { op: 'pose', f: 4, aim: [0, 0.05, 1] });
      for (let k = 0; k < 40; k++) { ops.push({ op: 'fire', f: 4 }); step(3); }
      ops.push({ op: 'pickup', f: 4, key: 'smg' }, { op: 'set', f: 4, key: 'hipD', val: 0.2 });
      for (let k = 0; k < 20; k++) { ops.push({ op: 'fire', f: 4 }); step(9); }
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.5, 1.2, 9] }, { op: 'pose', f: 0, aim: [0, 0, 1] });
      for (let k = 0; k < 30; k++) { ops.push({ op: 'fire', f: 0 }); step(8); }
    },
    knife() {                                       // thrown knife: wind-up, release, 4 sub-step flight, gravity, wall stick, hit test
      for (const i of [0, 1, 2, 3, 4]) ops.push({ op: 'placeAt', f: i, x: [0, 0.3, 2, -1, -4][i], z: [0, 10, 18, 30, 3][i], y: 0.01 }, { op: 'set', f: i, key: 'invuln', val: 0 });
      ops.push({ op: 'pickup', f: 0, key: 'knife' }, { op: 'pose', f: 0, aim: [0.03, 0.04, 1] });
      for (let k = 0; k < 6; k++) { ops.push({ op: 'fire', f: 0 }); step(110); }
      ops.push({ op: 'pose', f: 0, aim: [0, 0.2, 1] }, { op: 'fire', f: 0 }); step(200);
      ops.push({ op: 'pose', f: 0, aim: [-0.5, 0.1, 0.1] }, { op: 'fire', f: 0 }); step(500);
    },
    guns() {                                        // the other plain hitscan guns: ak, sniper, revolver, mammoth (player = crosshair assist, bot = arm assist)
      const setup = (x1, z1) => {
        for (const i of [0, 1, 2, 3, 4]) ops.push({ op: 'placeAt', f: i, x: [0, x1, x1 + 1.2, -1, 6][i], z: [0, z1, z1 - 5, 9, -5][i], y: 0.01 }, { op: 'set', f: i, key: 'invuln', val: 0 }, { op: 'set', f: i, key: 'hp', val: 400 });
        for (const i of [0, 3]) ops.push({ op: 'set', f: i, key: 'climb', val: 0 });      // the harness has no animate(), which is what settles the recoil climb
        ops.push({ op: 'pose', f: 0, aim: [x1 / -z1, 0.1, -1] });   // targets are at -z (the wall box is at +z 12..13)
      };
      const bot = (key, n, gap) => {                // fighter 3 shoots at fighter 0 with the weapon's own assist
        ops.push({ op: 'pickup', f: 3, key }, { op: 'pose', f: 3, aim: [0.05, 0.0, -1] });
        for (let k = 0; k < n; k++) { ops.push({ op: 'fire', f: 3 }); step(gap); }
      };
      setup(0.3, -10);
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.3, 1.25, -10] });
      ops.push({ op: 'pickup', f: 0, key: 'ak' });
      for (let k = 0; k < 45; k++) { ops.push({ op: 'fire', f: 0 }); step(13); }          // climb, recoil, mag, auto reload
      ops.push({ op: 'class', f: 0, cls: 'bruiser' }, { op: 'pickup', f: 0, key: 'ak' }, { op: 'cfg', key: 'aim', val: 1 });
      for (let k = 0; k < 20; k++) { ops.push({ op: 'fire', f: 0 }); step(13); }          // scoped in: tighter spread
      ops.push({ op: 'cfg', key: 'aim', val: 0 }, { op: 'class', f: 0, cls: 'wobbler' });
      bot('ak', 40, 7);
      setup(0.3, -25);
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.3, 1.95, -25] });                       // head height: the head multiplier
      ops.push({ op: 'pickup', f: 0, key: 'sniper' });
      for (let k = 0; k < 6; k++) { ops.push({ op: 'fire', f: 0 }); step(160); }
      ops.push({ op: 'reload', f: 0 }); step(500);
      ops.push({ op: 'cfg', key: 'aim', val: 1 }, { op: 'fire', f: 0 }); step(200); ops.push({ op: 'cfg', key: 'aim', val: 0 });
      bot('sniper', 6, 165);
      setup(0.3, -14);
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.3, 1.2, -14] });
      ops.push({ op: 'pickup', f: 0, key: 'revolver' });
      for (let k = 0; k < 9; k++) { ops.push({ op: 'fire', f: 0 }); step(80); }
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.3, 1.95, -14] });
      for (let k = 0; k < 6; k++) { ops.push({ op: 'fire', f: 0 }); step(80); }
      ops.push({ op: 'reload', f: 0 }); step(400);
      bot('revolver', 8, 80);
      setup(0.3, -14);
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.3, 1.95, -14] });
      ops.push({ op: 'pickup', f: 0, key: 'mammoth' });
      for (let k = 0; k < 8; k++) { ops.push({ op: 'fire', f: 0 }); step(110); }           // headshots: the head snap and extra shove
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.3, 1.2, -14] });
      for (let k = 0; k < 5; k++) { ops.push({ op: 'fire', f: 0 }); step(110); }
      ops.push({ op: 'cfg', key: 'giant', val: 1 }, { op: 'pickup', f: 0, key: 'mammoth' }, { op: 'fire', f: 0 }); step(120); ops.push({ op: 'cfg', key: 'giant', val: 0 });
      bot('mammoth', 6, 110);
    },
    uziMinigun() {                                  // dual Uzis alternate muzzles; the minigun needs to spin up while the button is held
      for (const i of [0, 1, 2, 3, 4]) ops.push({ op: 'placeAt', f: i, x: [0, 0.2, 1.4, -1, 6][i], z: [0, -11, -16, 9, -5][i], y: 0.01 }, { op: 'set', f: i, key: 'invuln', val: 0 }, { op: 'set', f: i, key: 'hp', val: 400 });
      for (const i of [0, 3]) ops.push({ op: 'set', f: i, key: 'climb', val: 0 });
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.2, 1.2, -11] }, { op: 'pose', f: 0, aim: [0.02, 0.1, -1] });
      ops.push({ op: 'pickup', f: 0, key: 'uzi' });
      for (let k = 0; k < 60; k++) { ops.push({ op: 'fire', f: 0 }); step(4); }
      ops.push({ op: 'pose', f: 0, arm: [0.6, 0.3, -0.74] }, { op: 'cfg', key: 'aimPoint', val: [3, 1.3, -9] });            // arm turned: a different right axis
      for (let k = 0; k < 20; k++) { ops.push({ op: 'fire', f: 0 }); step(4); }
      ops.push({ op: 'pose', f: 0, aim: [0, 1, 0.001] }, { op: 'fire', f: 0 }); step(8); ops.push({ op: 'fire', f: 0 }); step(8);    // arm straight up: three.js' degenerate axis
      ops.push({ op: 'pose', f: 0, aim: [0.02, 0.1, -1] }, { op: 'cfg', key: 'aimPoint', val: [0.2, 1.2, -11] });
      ops.push({ op: 'pickup', f: 3, key: 'uzi' }, { op: 'pose', f: 3, aim: [0.01, 0.0, -1] });
      for (let k = 0; k < 40; k++) { ops.push({ op: 'fire', f: 3 }); step(7); }
      ops.push({ op: 'set', f: 0, key: 'climb', val: 0 }, { op: 'pickup', f: 0, key: 'minigun' });
      for (let k = 0; k < 40; k++) { ops.push({ op: 'hold', f: 0, held: 1, dt: 1 / 120 }); step(1); }     // spinning up: no shots yet
      for (let k = 0; k < 150; k++) { ops.push({ op: 'hold', f: 0, held: 1, dt: 1 / 120 }); step(1); }    // firing
      for (let k = 0; k < 30; k++) { ops.push({ op: 'hold', f: 0, held: 0, dt: 1 / 120 }); step(1); }     // spin decays twice as fast
      for (let k = 0; k < 20; k++) { ops.push({ op: 'hold', f: 0, held: 1, dt: 1 / 120 }); step(1); }
      ops.push({ op: 'set', f: 0, key: 'hipD', val: 0.3 });
      for (let k = 0; k < 100; k++) { ops.push({ op: 'hold', f: 0, held: 1, dt: 1 / 120 }); step(1); }    // hip-carried minigun (barrel tilt)
      ops.push({ op: 'set', f: 0, key: 'hipD', val: 0 });
      for (let k = 0; k < 400; k++) { ops.push({ op: 'hold', f: 0, held: 1, dt: 1 / 120 }); step(1); }    // empties the mag, reloads
      ops.push({ op: 'pickup', f: 3, key: 'minigun' }, { op: 'pose', f: 3, aim: [0.01, 0.0, -1] });
      for (let k = 0; k < 40; k++) { ops.push({ op: 'fire', f: 3 }); step(6); }                           // bots do not spin up
    },
    shotgun() {                                     // pellet circle round the crosshair (rx/ry basis), falloff, hop, shell reload
      for (const i of [0, 1, 2, 3, 4]) ops.push({ op: 'placeAt', f: i, x: [0, 0.2, 1.0, -1, 6][i], z: [0, -6, -9, 9, -5][i], y: 0.01 }, { op: 'set', f: i, key: 'invuln', val: 0 }, { op: 'set', f: i, key: 'hp', val: 400 });
      for (const i of [0, 3]) ops.push({ op: 'set', f: i, key: 'climb', val: 0 });
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.2, 1.2, -6] }, { op: 'pose', f: 0, aim: [0.03, 0.1, -1] }, { op: 'pickup', f: 0, key: 'shotgun' });
      for (const aim of [0, 0.5, 1, 0]) { ops.push({ op: 'cfg', key: 'aim', val: aim }); for (let k = 0; k < 4; k++) { ops.push({ op: 'fire', f: 0 }); step(100); } }
      ops.push({ op: 'reload', f: 0 }); step(100);
      ops.push({ op: 'fire', f: 0 }); step(300);                                                                          // a shot during a shell reload cancels it? (whatever the JS does)
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0, 1.2, -40] }, { op: 'pose', f: 0, aim: [0, 0, -1] }, { op: 'cfg', key: 'aim', val: 0 });
      for (let k = 0; k < 6; k++) { ops.push({ op: 'fire', f: 0 }); step(100); }                                          // looking straight along +z at the far wall side
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0, 1.2, -0.2] });                                                       // a target right at the hand: shoots from the hand
      ops.push({ op: 'fire', f: 0 }); step(100);
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.2, 1.2, -6] }, { op: 'cfg', key: 'aim', val: 0 });
      ops.push({ op: 'pickup', f: 3, key: 'shotgun' }, { op: 'pose', f: 3, aim: [0.01, 0.0, -1] });                       // bots never aim down sights
      for (let k = 0; k < 10; k++) { ops.push({ op: 'fire', f: 3 }); step(100); }
      ops.push({ op: 'pose', f: 3, aim: [0, 1, 0] }, { op: 'fire', f: 3 }); step(100);                                    // straight up: rx falls back to (1,0,0)? only with baseDir.x=z=0
      ops.push({ op: 'cfg', key: 'giant', val: 1 }, { op: 'pickup', f: 0, key: 'shotgun' }, { op: 'pose', f: 0, aim: [0.03, 0.1, -1] }, { op: 'fire', f: 0 }); step(100); ops.push({ op: 'cfg', key: 'giant', val: 0 });
    },
    glove() {                                       // Spring Glove (gun style punch): best target by cone score, LOS, hit direction lifted, topple chance, Giant x2.1 force
      for (const i of [0, 1, 2, 3, 4]) ops.push({ op: 'placeAt', f: i, x: [0, 0.3, -1.1, 0.5, 6][i], z: [0, -3, -2.2, 9, -5][i], y: 0.01 }, { op: 'set', f: i, key: 'invuln', val: 0 }, { op: 'set', f: i, key: 'hp', val: 400 }, { op: 'set', f: i, key: 'downT', val: 0 });
      ops.push({ op: 'cfg', key: 'aimPoint', val: [0.3, 1.2, -3] }, { op: 'pose', f: 0, aim: [0.1, 0.0, -1] }, { op: 'pickup', f: 0, key: 'glove' });
      for (let k = 0; k < 10; k++) { ops.push({ op: 'fire', f: 0 }); step(110); ops.push({ op: 'set', f: 1, key: 'downT', val: 0 }, { op: 'set', f: 2, key: 'downT', val: 0 }, { op: 'set', f: 1, key: 'hp', val: 400 }, { op: 'set', f: 2, key: 'hp', val: 400 }); }
      ops.push({ op: 'pose', f: 0, aim: [1, 0, 0] });                                       // nobody there: swings at air
      ops.push({ op: 'fire', f: 0 }); step(110);
      ops.push({ op: 'pose', f: 0, aim: [-0.7, 0, -0.7] }, { op: 'fire', f: 0 }); step(110);   // off to the side: cone check
      ops.push({ op: 'cfg', key: 'giant', val: 1 }, { op: 'pickup', f: 0, key: 'glove' }, { op: 'pose', f: 0, aim: [0.1, 0.0, -1] }, { op: 'set', f: 1, key: 'downT', val: 0 }, { op: 'fire', f: 0 }); step(110); ops.push({ op: 'cfg', key: 'giant', val: 0 });
      ops.push({ op: 'pickup', f: 3, key: 'glove' }, { op: 'pose', f: 3, aim: [-0.05, 0.0, -1] });  // a bot punching f0 from the front (wall box not in the way)
      for (let k = 0; k < 4; k++) { ops.push({ op: 'fire', f: 3 }); step(110); }
      ops.push({ op: 'class', f: 1, cls: 'bruiser' }, { op: 'pickup', f: 1, key: 'glove' }, { op: 'pose', f: 1, aim: [-0.1, 0.0, 1] }, { op: 'set', f: 1, key: 'dmgScale', val: 1.5 });
      for (let k = 0; k < 4; k++) { ops.push({ op: 'fire', f: 1 }); step(110); }
    },
    melee2() {                                      // mallet, hammer, wirewhip, trident: their own timings, reach, topple chance, breaking
      const reset = () => { for (const i of [0, 1, 2, 3, 4]) ops.push({ op: 'placeAt', f: i, x: [0, 0, 1.0, -1.2, 3][i], z: [0, 1.5, 0.9, 0.7, 3][i], y: 0.01 }, { op: 'set', f: i, key: 'invuln', val: 0 }, { op: 'set', f: i, key: 'hp', val: 400 }, { op: 'set', f: i, key: 'downT', val: 0 }, { op: 'set', f: i, key: 'getupImmune', val: 0 }, { op: 'set', f: i, key: 'cool', val: 0 }); };
      for (const key of ['mallet', 'hammer', 'wirewhip', 'trident']) {
        reset();
        ops.push({ op: 'pickup', f: 0, key });
        for (let k = 0; k < 5; k++) { ops.push({ op: 'melee', f: 0, yaw: [0, 0.5, -0.4, 0.2, 2.5][k] }); step(150); if (k % 2) reset(); }
        ops.push({ op: 'set', f: 0, key: 'grounded', val: false }, { op: 'melee', f: 0, yaw: 0 }); step(130); ops.push({ op: 'set', f: 0, key: 'grounded', val: true });   // in the air: slam
        reset();
        ops.push({ op: 'class', f: 1, cls: 'kid' }, { op: 'pickup', f: 1, key }, { op: 'melee', f: 1, yaw: Math.PI });                    // another class swings too
        step(150);
        ops.push({ op: 'melee', f: 1, yaw: Math.PI }); step(60); ops.push({ op: 'melee', f: 1, yaw: Math.PI }); step(150);               // second press while swinging/cooling
        ops.push({ op: 'class', f: 1, cls: 'bruiser' });
        reset();
        ops.push({ op: 'cfg', key: 'giant', val: 1 }, { op: 'pickup', f: 0, key }, { op: 'melee', f: 0, yaw: 0.1 }); step(180); ops.push({ op: 'cfg', key: 'giant', val: 0 });
        reset();
        for (let k = 0; k < 10; k++) { ops.push({ op: 'pickup', f: 0, key }, { op: 'melee', f: 0, yaw: k * 0.3 }); step(150); if (k % 3 === 2) reset(); }     // breaks after its ammo
      }
      reset(); ops.push({ op: 'pickup', f: 0, key: 'trident' }, { op: 'melee', f: 0, yaw: 0 }); step(30); ops.push({ op: 'hit', f: 0, a: 1, dmg: 20, dir: [0, 0, 1], force: 9 }); step(150);    // interrupted swing
    },
    net() {                                         // hits on a remote fighter become `h` messages; a K.O. sends `ko`
      ops.push({ op: 'cfg', key: 'net', val: { kinds: ['human', 'bot', 'human', 'bot', 'bot'] } }, { op: 'set', f: 2, key: 'isGhost', val: true });
      ops.push({ op: 'hit', f: 2, a: 0, dmg: 12.345678, dir: [0.12345, -0.5, 0.987654], force: 7.777 });
      ops.push({ op: 'hit', f: 2, a: 1, dmg: 12, dir: [0, 0, 1], force: 3 });
      ops.push({ op: 'nethit', f: 3, a: 2, dmg: 30, dir: [0, 0, 1], force: 9, head: 1 });
      ops.push({ op: 'set', f: 1, key: 'invuln', val: 0 }, { op: 'hit', f: 1, a: 0, dmg: 999, dir: [0, 0.3, 1], force: 9 });
      ops.push({ op: 'set', f: 2, key: 'isGhost', val: false }, { op: 'cfg', key: 'net', val: null });
    },
    storm() {                                       // seeded random hits over every class/mode/state combination
      const modes = ['classic', 'mega', 'giant', 'pillars', 'explosive'];
      for (let k = 0; k < 400; k++) {
        if (k % 25 === 0) ops.push({ op: 'cfg', key: 'mode', val: pick(modes) }, { op: 'cfg', key: 'kb', val: pick([0, 0.5, 1, 1.5]) }, { op: 'cfg', key: 'giant', val: r() < 0.3 ? 1 : 0 });
        if (k % 40 === 0) for (let i = 0; i < 5; i++) ops.push({ op: 'class', f: i, cls: pick(['wobbler', 'bruiser', 'kid', 'elder', 'alien']) });
        const v = Math.floor(r() * 5); let a = Math.floor(r() * 6) - 1;
        if (r() < 0.2) ops.push({ op: 'set', f: a < 0 ? 0 : a, key: 'rageT', val: R(0, 1) });
        if (r() < 0.2) ops.push({ op: 'set', f: v, key: 'shieldT', val: R(0, 1) });
        if (r() < 0.15) ops.push({ op: 'set', f: v, key: 'downT', val: R(0, 1.2) });
        if (r() < 0.05) ops.push({ op: 'set', f: v, key: 'yaw', val: R(-3.2, 3.2) });
        ops.push({ op: 'hit', f: v, a, dmg: R(0, 90), dir: [R(-1, 1), R(-0.5, 1), R(-1, 1)], force: pick([R(0, 8), R(8, 30), 8, 9]), head: r() < 0.3 ? 1 : 0 });
        if (r() < 0.1) ops.push({ op: 'topple', f: v, dur: R(0.2, 2.5) });
        if (r() < 0.3) step(1 + Math.floor(r() * 90), pick([1 / 120, 1 / 60]));
      }
    },
  };
  for (const b of Object.keys(blocks)) blocks[b]();
  return { seed: 4242, fighters, ops };
}

function run(sc) {
  const ctx = makeContext(); seedRandom(ctx, sc.seed);
  sc.fighters.forEach((d, i) => ctx.fighters.push(mkFighter(ctx, d, i)));
  const states = [];
  for (const op of sc.ops) { apply(ctx, op); states.push(dump(ctx)); }
  /* net helpers: JS rounding and the hit cleaner over tricky and junk values */
  let s = 777; const r = () => (s = s * 48271 % 2147483647, (s - 1) / 2147483646);
  const vals = [0, 1.005, 2.675, 1.0049999999999999, -1.005, 0.125, -0.125, 0.0005, 1e-7, -1e-7, 123.455, 99.995, 1234567.125, 0.3, 0.1 + 0.2, 4.35, 8.345, -2.5, 2.5, 0.49999999999999994, -0.5];
  for (let k = 0; k < 400; k++) vals.push((r() - 0.5) * Math.pow(10, Math.floor(r() * 8) - 3));
  const fixed = vals.map(v => [v, +v.toFixed(2), +v.toFixed(3), Math.round(v)]);
  const junk = [{ d: 'x', f: null, x: '1.5', y: true, z: [] }, { d: 1e9, f: -5, x: 9, y: -9, z: NaN }, { d: '12.5', f: '200', x: '-3', y: {}, z: undefined }, { d: Infinity, f: -Infinity, x: 1.234, y: -1.999, z: 2 }];
  for (let k = 0; k < 50; k++) junk.push({ d: (r() - 0.2) * 400, f: (r() - 0.2) * 200, x: (r() - 0.5) * 6, y: (r() - 0.5) * 6, z: (r() - 0.5) * 6 });
  const hits = junk.map(m => { const raw = JSON.parse(JSON.stringify(Object.assign({ t: 'h', vs: 1, to: 1, from: 0 }, m))); const c = ctx.netCleanHit(Object.assign({}, raw)); return [raw, [c.d, c.f, c.x, c.y, c.z]]; });
  return { scenario: sc, states, net: { fixed, hits } };
}

/* Godot's JSON parser is not exact for doubles (it can be off by many ulps), so every non-integer number is written as
   "#" + its 16 hex digits (big-endian IEEE 754); godot/tests/combat_test.gd turns them back into the identical double. */
function exactJson(o) {
  return JSON.stringify(o, (k, v) => {
    if (typeof v !== 'number' || (Number.isInteger(v) && Math.abs(v) < 2 ** 53 && !Object.is(v, -0))) return v;
    const b = Buffer.alloc(8); b.writeDoubleBE(v); return '#' + b.toString('hex');
  });
}
module.exports = { run, scenario, exactJson, makeContext, mkFighter, seedRandom, block, line };   // tools/modes-reference.js builds on the same context
if (require.main === module) {
  const out = process.argv[2] || path.join(require('os').tmpdir(), 'wa-combat.json');
  const res = run(scenario());
  fs.writeFileSync(out, exactJson(res));
  console.log('combat reference:', res.states.length, 'ops ->', out);
}
