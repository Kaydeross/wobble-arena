'use strict';
/* Runs the web game's REAL bot AI (botThink, pickTarget, botWants, botGround, botPillarHop, doDash/dashTick, sliced out of
   public/index.html on top of the combat context of tools/combat-reference.js) over a scripted scenario and records the
   bots' decisions after every op: target, aim error, reaction timer, wish direction, jumps, the stuck watchdog, edge
   avoidance, crate choice, firing / kicking / swinging. godot/logic/bot_brain.gd (via godot/tests/bots_parity_test.gd)
   must reproduce it: npm run test:godot-bots.
   There is no physics in either harness: fighters only move by `place` ops, so a bot pushing for a second without
   moving trips the stuck watchdog, and `wantJump` is recorded and cleared every frame (as the physics step would use it).
   Same determinism rules as the combat reference: Park-Miller Math.random, visuals stubbed without random calls.

   node tools/bots-reference.js <out.json> */
const fs = require('fs'), path = require('path'), vm = require('vm');
const { makeContext, mkFighter, seedRandom, block, line, exactJson } = require('./combat-reference');

const FUNCS = ['function botWants\\(', 'function pickTarget\\(', 'function botGround\\(', 'function botPillarHop\\(', 'function botThink\\(',
  'function doDash\\(', 'function dashTick\\('];
const LINES = [/^const BOT_AIM_ERR = .*/m, /^const BOT_PREF = .*/m, /^const BOT_GRAB = .*/m, /^const BOT_GUNS = .*/m, /^const PU_META = .*/m,
  /^const DASH_MAX = .*/m, /^const DASH_GEAR = .*/m, /^const dashGear = .*/m, /^const pillarAt = .*/m, /^const pillarNear = .*/m];
const METHODS = ['quickMelee\\(yaw\\)', 'canReloadNow\\(\\)'];

function botsContext() {
  const ctx = makeContext();
  Object.assign(ctx, { pickups: [], SHOW: { on: false }, JUMPS: [] });
  ctx.MAPS.m = { spawns: [[0, 0]], wander: 14 };
  ctx.MAPS.pillars = { spawns: [] };
  let code = '"use strict";\n';
  code += block(/^const DIFFS = /m) + ';\n';
  for (const r of LINES) code += line(r) + '\n';
  for (const f of FUNCS) code += block(new RegExp('^' + f, 'm')) + '\n';
  for (const m of METHODS) { const b = block(new RegExp('^  ' + m + ' ', 'm')).trim(); const name = b.slice(0, b.indexOf('(')); code += `FighterBase.prototype.${name} = function ${b};\n`; }
  code += 'globalThis.botThink = botThink; globalThis.DIFFS = DIFFS;\n';
  vm.runInContext(code, ctx);
  return ctx;
}

function mkBot(ctx, d, i) {
  const f = mkFighter(ctx, d, i);
  Object.assign(f, { wish: new ctx.Vector3(), wantJump: false, aiT: d.aiT || 1, wander: null, thinkT: 0, target: null, jumpT: 0, aimOff: new ctx.Vector3(),
    strafe: d.strafe || 1, los: false, burst: 0, stuckT: 0, dashN: 3, dashRegen: 0, dashCd: 0, speed: 4.4 });
  return f;
}

const r6 = v => v;
function dump(ctx) {
  const F = ctx.fighters.map(f => [f.pos.x, f.pos.z, f.hp, f.dead ? 1 : 0, f.cool, f.kickCool, f.kickT, f.swing, f.weapon || '', f.slot, f.draw || 0, f.nocked ? 1 : 0,
    f.vel.x, f.vel.z, f.dashN, f.reloading ? 1 : 0,
    ...(f.isPlayer ? [] : [f.wish.x, f.wish.z, f.faceYaw, f.target ? f.target.id : -1, f.aimOff.x, f.aimOff.y, f.aimOff.z, f.thinkT, f.aiT,
      f.wander ? f.wander.x : 999, f.wander ? f.wander.z : 999, f.jumpT, f.stuckT, f.escapeT || 0, f.giveT || 0, f.wdT || 0, f.strafe, f.los ? 1 : 0, f.burst,
      f.aimTarget.x, f.aimTarget.y, f.aimTarget.z, f.hopT || 0, f.hopN || 0, ctx.JUMPS[f.id] || 0])]);
  return { f: F, c: ctx.pickups.length, t: ctx.simTime };
}

/* ---- ops (godot/tests/bots_parity_test.gd implements exactly the same) ---- */
function apply(ctx, op) {
  const F = ctx.fighters, f = F[op.f];
  const pose = g => {
    const p = g.pos, o = g.off;
    g.headPos.set(p.x + o.head[0], p.y + o.head[1], p.z + o.head[2]);
    g.chestPos.set(p.x + o.chest[0], p.y + o.chest[1], p.z + o.chest[2]);
    g.handPos.set(p.x + o.hand[0], p.y + o.hand[1], p.z + o.hand[2]);
    g.shoulderPos.set(p.x + o.shoulder[0], p.y + o.shoulder[1], p.z + o.shoulder[2]);
    g.legPos.set(p.x, p.y + 0.5, p.z);
    g.armDir.copy(g.aimTarget); g.armQuat();
  };
  switch (op.op) {
    case 'cfg':
      if (op.key === 'solids') ctx.solids = op.val;
      else if (op.key === 'spawns') { ctx.MAPS.m.spawns = op.val; ctx.MAPS.pillars.spawns = op.val; }
      else if (op.key === 'wander') ctx.MAPS.m.wander = op.val;
      else if (op.key === 'edgeGuard') ctx.MAPS.m.edgeGuard = !!op.val;
      else ctx.cfg[op.key] = op.val;
      break;
    case 'set': if (op.key === 'grounded') f.grounded = !!op.val; else f[op.key] = op.val; break;
    case 'place': f.pos.set(...op.p); break;
    case 'vel': f.vel.set(...op.v); break;
    case 'pickup': f.pickup(op.key); break;
    case 'crate': ctx.pickups.push({ key: op.key, x: op.x, z: op.z, gy: op.gy, grounded: true }); break;
    case 'nocrates': ctx.pickups.length = 0; break;
    case 'think':
      for (let n = 0; n < op.n; n++) {
        F.forEach(pose);
        for (const b of F) if (!b.isPlayer) { ctx.botThink(b, op.dt); if (b.wantJump) { ctx.JUMPS[b.id] = (ctx.JUMPS[b.id] || 0) + 1; b.wantJump = false; } }
        for (const g of F) g.timers(op.dt);
        ctx.updateRockets(op.dt); ctx.updateGrenades(op.dt); ctx.updateKnives(op.dt); ctx.updateBoomerangs(op.dt); ctx.updateArrows(op.dt); ctx.updateSnakes(op.dt); ctx.updateBalls(op.dt); ctx.updateNets(op.dt);
        ctx.simTime += op.dt;
        F.forEach(pose);
        for (const g of F) g.meleeSweep();
        for (const g of F) if (g.grabT >= 0) { g.grabT += op.dt; if (g.grabT > 0.28) { g.grabT = -1; g.nocked = true; } }
      }
      break;
    default: throw new Error('unknown op ' + op.op);
  }
}

/* ---- the scenario ---- */
const FLOOR = { minX: -15, maxX: 15, minZ: -15, maxZ: 15, top: 0, bottom: -1 };
const WALL = { minX: -3, maxX: 3, minZ: 6, maxZ: 7, top: 3, bottom: 0 };
const LEDGE = { minX: -12, maxX: -8, minZ: -12, maxZ: -8, top: 1.2, bottom: 0 };
const ISLAND = { minX: 25, maxX: 35, minZ: -5, maxZ: 5, top: 0, bottom: -1 };
const PIL = [[0, -14], [13.3, -4.3], [8.2, 11.3], [-8.2, 11.3], [-13.3, -4.3]];        // five pillars in a ring (gaps ~ 8 m)
function scenario() {
  let s = 99991; const r = () => (s = s * 48271 % 2147483647, (s - 1) / 2147483646);
  const R = (a, b) => +(a + r() * (b - a)).toFixed(3), pick = a => a[Math.floor(r() * a.length)];
  const fighters = [
    { pos: [0, 0, 0], cls: 'wobbler', player: true },
    { pos: [5, 0, 5], cls: 'bruiser', aiT: 1.5, strafe: 1 },
    { pos: [-6, 0, 3], cls: 'kid', aiT: 0.7, strafe: -1 },
    { pos: [8, 0, -6], cls: 'alien', aiT: 2.2, strafe: 1 },
    { pos: [-4, 0, -9], cls: 'elder', aiT: 0.2, strafe: -1 },
  ];
  const ops = [];
  const think = (n, dt = 1 / 120) => ops.push({ op: 'think', n, dt });
  const place = (i, x, z, y = 0) => ops.push({ op: 'place', f: i, p: [x, y, z] });
  const reset = () => { for (let i = 0; i < 5; i++) ops.push({ op: 'set', f: i, key: 'invuln', val: 0 }, { op: 'set', f: i, key: 'hp', val: 400 }, { op: 'set', f: i, key: 'downT', val: 0 }, { op: 'set', f: i, key: 'stun', val: 0 }, { op: 'set', f: i, key: 'dead', val: false }, { op: 'set', f: i, key: 'grounded', val: true }, { op: 'vel', f: i, v: [0, 0, 0] }); };
  ops.push({ op: 'cfg', key: 'solids', val: [FLOOR, WALL, LEDGE, ISLAND] }, { op: 'cfg', key: 'spawns', val: [[0, 0], [6, -6], [-7, 4], [3, 9]] }, { op: 'cfg', key: 'wander', val: 13 });
  ops.push({ op: 'cfg', key: 'hp', val: 400 });
  reset();
  const blocks = {
    diffs() {                                       // spatula brawl at every difficulty: targets, reaction, aim error, kicks, swings, hops, watchdog
      for (const diff of ['easy', 'normal', 'hard', 'insane']) {
        ops.push({ op: 'cfg', key: 'diff', val: diff });
        reset();
        place(1, 1.2, 1.0); place(2, -1.5, 0.5); place(3, 7, -7); place(4, -4, -11);
        think(150);
        place(0, 3, -3); place(1, 3.5, -1.5);
        think(150);
        place(0, -10, -10, 1.2);                    // the player up on the ledge: bots below jump up to it
        place(2, -10, -6.8); think(120);
        place(0, 0, 0); reset(); think(90);
      }
    },
    guns() {                                        // every ported ranged weapon type: range keeping, strafing, line-up, bursts, reloads, min distance, the bow draw
      ops.push({ op: 'cfg', key: 'diff', val: 'hard' });
      for (const key of ['smg', 'ak', 'sniper', 'minigun', 'revolver', 'shotgun', 'flame', 'glove', 'mammoth', 'uzi', 'rocket', 'meteor', 'glauncher', 'cluster', 'net', 'bow', 'knife', 'shuriken', 'typhoon', 'boomerang', 'snake', 'snow', 'trident', 'bat', 'katana']) {
        reset();
        place(0, 0, 0); place(1, 0.3, -12); place(2, 9, 2); place(3, -3, 9.5); place(4, 2, -3);
        for (const i of [1, 2, 3, 4]) ops.push({ op: 'pickup', f: i, key });
        if (key === 'minigun') ops.push({ op: 'set', f: 1, key: 'hipD', val: 0.2 });
        think(130);
        place(1, 0.2, -4); place(2, 13, 1);
        think(130);
        ops.push({ op: 'set', f: 1, key: 'hipD', val: 0 });
      }
    },
    crates() {                                      // crates: weapons only empty-handed, power-ups, heals when hurt; reach, height, BOT_GRAB, close target
      for (const diff of ['easy', 'insane']) {
        ops.push({ op: 'cfg', key: 'diff', val: diff });
        reset();
        for (const i of [1, 2, 3, 4]) ops.push({ op: 'set', f: i, key: 'slot', val: -1 }, { op: 'set', f: i, key: 'weapon', val: 'spatula' }, { op: 'set', f: i, key: 'slots', val: [null, null, null] });
        place(0, -13, 13); place(1, 6, 6); place(2, -6, -2); place(3, 8, -8); place(4, 0, 12);
        ops.push({ op: 'crate', key: 'smg', x: 10, z: 8, gy: 0 }, { op: 'crate', key: 'heal', x: -8, z: -3, gy: 0 }, { op: 'crate', key: 'speed', x: 9, z: -12, gy: 0 },
          { op: 'crate', key: 'rocket', x: 2, z: 13, gy: 3 }, { op: 'crate', key: 'shield', x: -14, z: -14, gy: 0 });
        ops.push({ op: 'set', f: 2, key: 'hp', val: 150 });
        think(200);
        ops.push({ op: 'pickup', f: 1, key: 'ak' }, { op: 'set', f: 2, key: 'hp', val: 400 });
        think(200);
        ops.push({ op: 'nocrates' });
      }
    },
    edges() {                                       // edge awareness: turn away from the void, stop, no jump without somewhere to land
      ops.push({ op: 'cfg', key: 'diff', val: 'insane' });
      reset();
      place(0, 30, 0);                              // the player across the void on the island
      place(1, 13.5, 0); place(2, 14.2, 13.8); place(3, 12, -14.2); place(4, -14.5, 0);
      think(240);
      place(1, 14.4, 2); ops.push({ op: 'vel', f: 1, v: [4, 0, 0] }); think(60);
      place(0, 0, 0); ops.push({ op: 'cfg', key: 'diff', val: 'hard' }); place(1, 13, 13); place(2, -13, -13);
      think(200);
    },
    teams() {                                       // teams: friends are never targets; not FFA: only the player
      ops.push({ op: 'cfg', key: 'diff', val: 'normal' }, { op: 'cfg', key: 'teams', val: 2 });
      for (const [i, t] of [[0, 0], [1, 0], [2, 1], [3, 1], [4, 0]]) ops.push({ op: 'set', f: i, key: 'team', val: t });
      reset(); place(0, 0, 0); place(1, 1, 1); place(2, 1.5, -1); place(3, -6, 2); place(4, 5, -5);
      think(200);
      ops.push({ op: 'cfg', key: 'teams', val: 0 }, { op: 'cfg', key: 'ffa', val: false });
      for (let i = 0; i < 5; i++) ops.push({ op: 'set', f: i, key: 'team', val: 0 });
      think(200);
      ops.push({ op: 'cfg', key: 'ffa', val: true }, { op: 'cfg', key: 'behav', val: 'dummy' });      // dummies: only the player, wander, no attacks
      think(200);
      ops.push({ op: 'cfg', key: 'behav', val: 'brawl' });
    },
    ninja() {                                       // ninja weapons dash toward a target 6..26 m away
      ops.push({ op: 'cfg', key: 'mode', val: 'ninja' }, { op: 'cfg', key: 'diff', val: 'insane' });
      reset(); place(0, 0, 0); place(1, 10, 10); place(2, -12, 8); place(3, 12, -12); place(4, -3, -14);
      for (const i of [1, 2, 3, 4]) ops.push({ op: 'pickup', f: i, key: ['katana', 'knife', 'katana', 'knife'][i - 1] }, { op: 'set', f: i, key: 'dashN', val: 3 });
      for (let k = 0; k < 6; k++) { think(100); place(1 + (k % 4), R(-12, 12), R(-12, 12)); }
      ops.push({ op: 'cfg', key: 'mode', val: 'classic' });
    },
    pillars() {                                     // pillars: stop at the edge, walk to the edge facing the next pillar, jump and dash across
      const pills = PIL.map(([x, z]) => ({ minX: x - 3.5, maxX: x + 3.5, minZ: z - 3.5, maxZ: z + 3.5, top: 10, bottom: -20 }));
      ops.push({ op: 'cfg', key: 'solids', val: pills }, { op: 'cfg', key: 'spawns', val: PIL }, { op: 'cfg', key: 'edgeGuard', val: 1 }, { op: 'cfg', key: 'mode', val: 'pillars' }, { op: 'cfg', key: 'wander', val: 26 });
      reset();
      for (let i = 0; i < 5; i++) place(i, PIL[i][0], PIL[i][1], 10);
      think(200);
      for (const i of [1, 2]) ops.push({ op: 'set', f: i, key: 'grounded', val: false }, { op: 'set', f: i, key: 'hopT', val: 1.2 }, { op: 'set', f: i, key: 'hopY0', val: 10 }, { op: 'set', f: i, key: 'hopTo', val: 0 }, { op: 'set', f: i, key: 'escapeT', val: -1 }, { op: 'set', f: i, key: 'hopN', val: i === 1 ? 0 : 1 }, { op: 'set', f: i, key: 'dashN', val: 3 }, { op: 'set', f: i, key: 'dashCd', val: 0 });
      place(1, PIL[1][0] - 3, PIL[1][1] - 2, 11); place(2, PIL[2][0], PIL[2][1] - 4, 10.8);
      think(40);
      reset();
      ops.push({ op: 'pickup', f: 3, key: 'smg' }, { op: 'pickup', f: 4, key: 'bow' });
      think(300);
      ops.push({ op: 'cfg', key: 'solids', val: [FLOOR, WALL, LEDGE, ISLAND] }, { op: 'cfg', key: 'spawns', val: [[0, 0], [6, -6], [-7, 4], [3, 9]] }, { op: 'cfg', key: 'edgeGuard', val: 0 },
        { op: 'cfg', key: 'mode', val: 'classic' }, { op: 'cfg', key: 'wander', val: 13 });
      reset(); for (let i = 0; i < 5; i++) place(i, [0, 5, -6, 8, -4][i], [0, 5, 3, -6, -9][i]);
    },
    storm() {                                       // seeded chaos: difficulty, positions, states, weapons, crates
      const keys = ['smg', 'ak', 'rocket', 'glauncher', 'net', 'bow', 'knife', 'bat', 'shotgun', 'sniper', 'flame', 'katana', 'shuriken', 'typhoon', 'boomerang', 'snake', 'snow'];
      for (let k = 0; k < 160; k++) {
        if (k % 20 === 0) { ops.push({ op: 'cfg', key: 'diff', val: pick(['easy', 'normal', 'hard', 'insane']) }); reset(); }
        const i = Math.floor(r() * 5);
        const roll = r();
        if (roll < 0.35) place(i, R(-14, 14), R(-14, 14), r() < 0.1 ? 1.2 : 0);
        else if (roll < 0.45 && i > 0) ops.push({ op: 'pickup', f: i, key: pick(keys) });
        else if (roll < 0.52) ops.push({ op: 'set', f: i, key: 'stun', val: R(0, 0.5) });
        else if (roll < 0.58) ops.push({ op: 'set', f: i, key: 'downT', val: R(0, 0.6) });
        else if (roll < 0.64) ops.push({ op: 'vel', f: i, v: [R(-5, 5), 0, R(-5, 5)] });
        else if (roll < 0.70) ops.push({ op: 'set', f: i, key: 'grounded', val: r() < 0.5 });
        else if (roll < 0.74) ops.push({ op: 'crate', key: pick(['heal', 'speed', 'smg', 'bow']), x: R(-14, 14), z: R(-14, 14), gy: 0 });
        else if (roll < 0.76) ops.push({ op: 'nocrates' });
        else if (roll < 0.80) ops.push({ op: 'set', f: i, key: 'hp', val: R(20, 400) });
        think(1 + Math.floor(r() * 60), pick([1 / 120, 1 / 60]));
      }
    },
  };
  for (const b of Object.keys(blocks)) blocks[b]();
  return { seed: 31337, fighters, ops };
}

function run(sc) {
  const ctx = botsContext(); seedRandom(ctx, sc.seed);
  sc.fighters.forEach((d, i) => ctx.fighters.push(mkBot(ctx, d, i)));
  ctx.player = ctx.fighters[0];
  const states = [];
  for (const op of sc.ops) { apply(ctx, op); states.push(dump(ctx)); }
  return { scenario: sc, states };
}

module.exports = { run, scenario, exactJson };
if (require.main === module) {
  const out = process.argv[2] || path.join(require('os').tmpdir(), 'wa-bots.json');
  const res = run(scenario());
  fs.writeFileSync(out, exactJson(res));
  console.log('bots reference:', res.states.length, 'ops ->', out);
}
