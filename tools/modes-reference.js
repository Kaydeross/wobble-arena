'use strict';
/* Runs the web game's REAL game-mode code (addKo + K.O. limit, teamKo, eliminate, respawn with lives and shrink spots,
   ggGive/ggAdvance, doDash/dashTick, updateShrink; sliced out of public/index.html on top of the combat context of
   tools/combat-reference.js) over a scripted scenario and records the state after every op. The Godot port
   (godot/logic/mode_rules.gd via godot/tests/modes_parity_test.gd) must reproduce it: npm run test:godot-modes.
   Same determinism rules as the combat reference: Park-Miller Math.random, visuals stubbed without random calls.

   node tools/modes-reference.js <out.json> */
const fs = require('fs'), path = require('path'), vm = require('vm');
const { makeContext, mkFighter, seedRandom, block, line, exactJson } = require('./combat-reference');

const FUNCS = ['function teamKo\\(', 'function eliminate\\(', 'function ggGive\\(', 'function ggAdvance\\(', 'function doDash\\(', 'function dashTick\\(', 'function updateShrink\\('];
const LINES = [/^const GG = .*/m, /^const DASH_MAX = .*/m, /^const DASH_GEAR = .*/m, /^const dashGear = .*/m];
/* MAPS.shrink / MAPS.squeeze build(): the `shrink` objects (mesh is visual) */
const SHRINK = {
  shrink: { S0: 64, size: 64, start: 64, min: 16, max: 40, dir: -1, cycle: 0, hold: 5, both: true, D: 64 },
  squeeze: { S0: 80, size: 80, start: 80, min: 22, max: 58, dir: -1, cycle: 0, hold: 5, both: false, D: 36, rate: 34 },
};

function modesContext() {
  const ctx = makeContext();
  Object.assign(ctx, { feedItems: [], ENDS: [], pickups: [], colOf: () => '', nameOf: () => '' });
  let code = '"use strict";\n';
  for (const r of LINES) code += line(r) + '\n';
  for (const f of FUNCS) code += block(new RegExp('^' + f, 'm')) + '\n';
  code += 'endMatch = function (w) { matchOver = true; ENDS.push(w.id); };\n';        // endMatch: only its gameplay half (stats/coins/menu are UI)
  vm.runInContext(code, ctx);
  return ctx;
}

function dump(ctx) {
  const F = ctx.fighters.map(f => [f.pos.x, f.pos.y, f.pos.z, f.vel.x, f.vel.y, f.vel.z, f.grounded ? 1 : 0, f.hp, f.dead ? 1 : 0, f.deathT, f.ko, f.lives,
    f.elim ? 1 : 0, f.team, f.weapon || '', JSON.stringify(f.slots.map(s => s ? [s.key, s.ammo, s.mag === undefined ? -1 : s.mag] : null)), f.slot, f.invuln,
    f.dashN, f.dashRegen, f.dashCd, f.ggRung || 0, f.st.deaths, f.st.streak, f.fallSide, f.dashAirT || 0]);
  const s = ctx.shrink;
  const S = s ? [s.size, s.start, s.dir, s.hold, s.cycle, s.rest === undefined ? -1 : s.rest, s.box.minX, s.box.maxX, s.box.minZ, s.box.maxZ] : null;
  return { f: F, m: [ctx.matchOver ? 1 : 0, ctx.ENDS.join(','), ctx.simTime], s: S };
}

/* ---- ops (godot/tests/modes_parity_test.gd implements exactly the same) ---- */
function apply(ctx, op) {
  const F = ctx.fighters, f = F[op.f];
  switch (op.op) {
    case 'cfg':
      if (op.key === 'spawns') ctx.MAPS.m = Object.assign({}, ctx.MAPS.m, { spawns: op.val, spawnY: op.y });
      else if (op.key === 'solids') ctx.solids = JSON.parse(JSON.stringify(op.val));      // a copy: updateShrink moves the floor box
      else if (op.key === 'matchOver') ctx.matchOver = !!op.val;
      else if (op.key === 'shrink') {
        if (op.val) { ctx.shrink = Object.assign({}, SHRINK[op.val], { box: ctx.solids[0], mesh: { scale: { set() {} }, updateMatrixWorld() {} } }); ctx.MAPS.m.shrinks = true; }
        else { ctx.shrink = null; ctx.MAPS.m.shrinks = false; }
      } else ctx.cfg[op.key] = op.val;
      break;
    case 'set': if (op.key === 'py') f.pos.y = op.val; else f[op.key] = op.val; break;
    case 'placeAt': f.placeAt(op.x, op.z, op.y); break;
    case 'pickup': f.pickup(op.key); break;
    case 'hit': f.hit(op.dmg, new ctx.Vector3(...op.dir), op.force, !!op.head, op.a >= 0 ? F[op.a] : null); break;
    case 'ko': ctx.addKo(F[op.a], f); break;
    case 'respawn': f.respawn(); break;
    case 'dash': ctx.doDash(f, op.ix, op.iz); break;
    case 'step':                                   // simStep's order for these parts: simTime, updateShrink, per-fighter timers
      for (let n = 0; n < op.n; n++) { ctx.simTime += op.dt; ctx.updateShrink(op.dt); for (const g of F) g.timers(op.dt); }
      break;
    default: throw new Error('unknown op ' + op.op);
  }
}

function scenario() {
  const fighters = [
    { pos: [0, 0, 0], cls: 'wobbler', player: true },
    { pos: [3, 0, 1], cls: 'bruiser', yaw: 2.1 },
    { pos: [-2, 0, 4], cls: 'kid', yaw: -1.2 },
    { pos: [5, 0, -3], cls: 'alien', yaw: 0.7 },
    { pos: [-4, 0, -2], cls: 'elder', yaw: 3.0, dmgScale: 0.8 },
  ];
  const ops = [];
  const step = (n, dt = 1 / 120) => ops.push({ op: 'step', n, dt });
  const all = (key, val) => { for (let i = 0; i < fighters.length; i++) ops.push({ op: 'set', f: i, key, val }); };
  const kill = (f, a) => ops.push({ op: 'hit', f, a, dmg: 900, dir: [0.3, 0.4, -0.8], force: 12, head: 0 });
  ops.push({ op: 'cfg', key: 'spawns', val: [[0, 0], [6, 6], [-7, 3], [4, -8], [10, -2]], y: 4 });
  ops.push({ op: 'cfg', key: 'solids', val: [{ minX: -32, maxX: 32, minZ: -32, maxZ: 32, top: 0, bottom: -2 }] });
  for (let i = 0; i < fighters.length; i++) ops.push({ op: 'placeAt', f: i, x: fighters[i].pos[0], z: fighters[i].pos[2], y: 0.01 });
  all('invuln', 0);
  const blocks = {
    teams() {                                     // 2v2+: no friendly fire, no K.O. credit on a friend, team score reaches the limit
      ops.push({ op: 'cfg', key: 'mode', val: 't2' }, { op: 'cfg', key: 'teams', val: 2 }, { op: 'cfg', key: 'limit', val: 3 });
      [0, 0, 1, 1, 1].forEach((t, i) => ops.push({ op: 'set', f: i, key: 'team', val: t }));
      ops.push({ op: 'hit', f: 1, a: 0, dmg: 40, dir: [1, 0, 0], force: 10, head: 0 });       // friend: nothing
      ops.push({ op: 'ko', f: 1, a: 0 });                                                      // a friend's K.O.: no credit
      ops.push({ op: 'hit', f: 2, a: 0, dmg: 30, dir: [0, 0.2, 1], force: 9, head: 1 });
      kill(0, 2); step(10); kill(1, 3); step(10);
      ops.push({ op: 'ko', f: 1, a: 4 });                                                      // team 1 has 3: endMatch(f4)
      kill(3, 0); step(400);                                                                   // after the end: no second endMatch
      ops.push({ op: 'cfg', key: 'matchOver', val: 0 }, { op: 'cfg', key: 'teams', val: 0 }, { op: 'cfg', key: 'limit', val: 2 });
      all('ko', 0); all('invuln', 0);
      ops.push({ op: 'ko', f: 2, a: 3 }, { op: 'ko', f: 1, a: 3 });                         // free for all: own K.O.s reach the limit
      ops.push({ op: 'cfg', key: 'matchOver', val: 0 }, { op: 'cfg', key: 'limit', val: 0 });
      all('ko', 0); all('team', -1); ops.push({ op: 'set', f: 0, key: 'team', val: 0 });
      step(700);
    },
    lives() {                                     // stock: lives tick down on respawn, the last one eliminates, the match ends
      ops.push({ op: 'cfg', key: 'mode', val: 'mega' }, { op: 'cfg', key: 'lives', val: 3 });
      all('lives', 2); all('invuln', 0); all('dead', false);
      for (let i = 0; i < 5; i++) ops.push({ op: 'placeAt', f: i, x: i * 2 - 4, z: 1, y: 0.01 });
      all('invuln', 0);
      kill(3, 4); step(5 * 60 + 5, 1 / 60);       // f3 back with 1 life
      all('invuln', 0);
      kill(3, 4); step(5 * 60 + 5, 1 / 60);       // f3 out (already counted)
      ops.push({ op: 'set', f: 1, key: 'lives', val: 1 }, { op: 'respawn', f: 1 });            // ring-out on the last life: eliminated alive
      ops.push({ op: 'set', f: 2, key: 'ko', val: 3 }, { op: 'set', f: 4, key: 'lives', val: 1 }, { op: 'set', f: 4, key: 'ko', val: 5 });
      all('invuln', 0);
      kill(0, 2); step(3 * 60 + 5, 1 / 60);       // the player is back with 1 life
      all('invuln', 0);
      kill(0, 4); step(3 * 60 + 5, 1 / 60);       // the player is out offline: endMatch(best of the rest: lives, then K.O.s)
      ops.push({ op: 'cfg', key: 'matchOver', val: 0 }, { op: 'cfg', key: 'lives', val: 0 });
      all('elim', false); all('lives', 0); all('ko', 0); all('dead', false); all('deathT', 0);
    },
    ladder() {                                    // Weapon Ladder: start rung, every K.O. a rung up (not while dead), the last rung wins
      ops.push({ op: 'cfg', key: 'mode', val: 'gungame' });
      for (let i = 0; i < 5; i++) ops.push({ op: 'placeAt', f: i, x: 3 - i * 1.5, z: -2, y: 0.01 });
      all('invuln', 0);
      for (let k = 0; k < 5; k++) { ops.push({ op: 'ko', f: 1 + (k % 4), a: 0 }); step(7); }
      ops.push({ op: 'ko', f: 0, a: 2 }, { op: 'set', f: 2, key: 'dead', val: true }, { op: 'ko', f: 0, a: 2 }, { op: 'set', f: 2, key: 'dead', val: false });
      ops.push({ op: 'set', f: 3, key: 'ggRung', val: 9 }, { op: 'respawn', f: 3 });           // respawn gives the current rung
      all('invuln', 0);
      kill(4, 3); step(30);
      for (let k = 0; k < 8; k++) { ops.push({ op: 'ko', f: 1 + (k % 4), a: 0 }); step(3); }   // the player climbs past the top: endMatch
      ops.push({ op: 'ko', f: 1, a: 3 });                                                       // after the end: no more rungs
      ops.push({ op: 'cfg', key: 'matchOver', val: 0 }, { op: 'cfg', key: 'mode', val: 'classic' });
      all('ggRung', 0); all('ko', 0); all('dead', false); all('elim', false); all('deathT', 0);
    },
    dash() {                                      // ninja dash: gear, 3 charges, cooldown, regen, facing fallback, Pillars air time
      ops.push({ op: 'cfg', key: 'mode', val: 'ninja' });
      for (let i = 0; i < 5; i++) ops.push({ op: 'placeAt', f: i, x: i * 3 - 6, z: 5, y: 0.01 });
      ops.push({ op: 'dash', f: 1, ix: 1, iz: 0 });                                            // the ninja start weapon counts as dash gear
      ops.push({ op: 'pickup', f: 0, key: 'katana' }, { op: 'pickup', f: 2, key: 'bat' });
      ops.push({ op: 'dash', f: 0, ix: 3, iz: 4 }, { op: 'dash', f: 0, ix: 1, iz: 0 }, { op: 'dash', f: 2, ix: 1, iz: 0 });
      step(60); ops.push({ op: 'dash', f: 0, ix: -1, iz: 0.5 }); step(60);
      ops.push({ op: 'set', f: 0, key: 'grounded', val: false }, { op: 'dash', f: 0, ix: 0.01, iz: 0.02 }, { op: 'dash', f: 0, ix: 1, iz: 1 });
      step(100); step(500); ops.push({ op: 'dash', f: 0, ix: 0, iz: -1 }); step(300);
      ops.push({ op: 'set', f: 0, key: 'downT', val: 0.5 }, { op: 'dash', f: 0, ix: 1, iz: 0 }); step(80);
      ops.push({ op: 'cfg', key: 'mode', val: 'pillars' }, { op: 'dash', f: 3, ix: 0.2, iz: -1 }, { op: 'dash', f: 4, ix: 0, iz: 0 }); step(40);
      ops.push({ op: 'cfg', key: 'mode', val: 'classic' });
    },
    shrink() {                                    // updateShrink both maps: hold, shrink, rest, grow, hold, everyone-fell reset; respawn spots
      for (const id of ['shrink', 'squeeze']) {
        ops.push({ op: 'cfg', key: 'solids', val: [{ minX: -40, maxX: 40, minZ: -18, maxZ: 18, top: 0, bottom: -2 }] }, { op: 'cfg', key: 'shrink', val: id });
        all('dead', false); all('elim', false);
        step(70 * 60, 1 / 60);
        for (let i = 0; i < 5; i++) ops.push({ op: 'respawn', f: i });
        step(25 * 60, 1 / 60);
        all('dead', true); all('deathT', 99);
        step(90 * 60, 1 / 60);                    // at the smallest with everyone down: back at half size
        for (let i = 0; i < 5; i++) ops.push({ op: 'respawn', f: i });
        ops.push({ op: 'cfg', key: 'matchOver', val: 1 }); step(30); ops.push({ op: 'cfg', key: 'matchOver', val: 0 });
        step(20 * 60, 1 / 60);
        ops.push({ op: 'cfg', key: 'shrink', val: '' });
      }
    },
  };
  for (const b of Object.keys(blocks)) blocks[b]();
  return { seed: 9191, fighters, ops };
}

function run(sc) {
  const ctx = modesContext(); seedRandom(ctx, sc.seed);
  sc.fighters.forEach((d, i) => { const f = mkFighter(ctx, d, i); f.root = { visible: true }; f.dashN = 3; f.dashRegen = 0; f.dashCd = 0; ctx.fighters.push(f); });
  const states = [];
  for (const op of sc.ops) { apply(ctx, op); states.push(dump(ctx)); }
  return { scenario: sc, states };
}

module.exports = { run, scenario, exactJson };
if (require.main === module) {
  const out = process.argv[2] || path.join(require('os').tmpdir(), 'wa-modes.json');
  const res = run(scenario());
  fs.writeFileSync(out, exactJson(res));
  const last = res.states[res.states.length - 1];
  console.log('modes reference:', res.states.length, 'ops ->', out, 'ends:', last.m[1]);
}
