#!/usr/bin/env node
/*
 * Read-only balance table generator for docs/BALANCE_REVIEW.md.
 *
 *   node tools/balance-tables.js            # every table
 *   node tools/balance-tables.js weapons    # weapons | classes | drops | modes | bosses
 *
 * It only reads the shipped JSON (shared/*.json, godot/data/extra/**) and prints markdown
 * tables. It never writes a file, never touches gameplay data and is deliberately not in
 * package.json. The numbers in the review were computed with this script; the review's
 * prose also uses the game logic (godot/logic/*.gd) for timings the JSON does not carry.
 *
 * Assumptions (documented in the review):
 *  - TTK@150/200 = body/torso hits, no headshots, no reload for the first magazine unless the
 *    kill needs one (then the magazine + reload is simulated), no missed shots.
 *  - Burst pools (weapon_tuning.json `burst`) are simulated as n shots, then one charge back
 *    every `regen` s.
 *  - Shotguns/nailguns use every pellet; bows/shurikens/typhoons/clusters assume every
 *    projectile from one trigger hits the same target (ideal volley).
 *  - The bow's trigger cycle is nock 0.28 + draw 0.45 (cycle 0.73, inferred); boomerang and
 *    typhoon are gated by their return flight (1.3 s / 1.2 s, inferred, marked [i]).
 *  - Flame/blower damage is continuous (see `special` rows).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const read = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));

const W = read('shared/weapons.json');
const EXTRA_W = read('godot/data/extra/construction/weapons.json');
const ALL_W = Object.assign({}, W, EXTRA_W);
const TUNED = read('godot/data/extra/weapon_tuning.json').weapons || {};
const CLASSES = Object.assign({}, read('shared/classes.json'), read('godot/data/extra/classes.json'));
const MODES = Object.assign({}, read('shared/modes.json'), read('godot/data/extra/modes.json'));
const DROPS = read('shared/drops.json');
const RATES = read('shared/crate-rates.json');
const DIFFS = read('shared/difficulties.json');
const STAGES = read('godot/data/extra/construction/stages.json');
const CONSTRUCTION_MODES = read('godot/data/extra/construction/modes.json');

const HP = 150; // the review's reference health (web lobby option)
const HP_DEFAULT = 200; // Godot offline / web default
const AK_TUNED_DPS = (6 / 0.1); // reference weapon for class TTD: AK-47 body, offline tuning
const I = { bow: 0.73, boomerang: 1.3, typhoon: 1.2 }; // inferred trigger cycles [i]

const num = (v, d = 1) => (v == null || Number.isNaN(v) ? '—' : Number(v).toFixed(d).replace(/\.0$/, ''));
const mult = (v) => (v == null ? '—' : '×' + Number(v).toFixed(2).replace(/0$/, '').replace(/\.$/, ''));
const sum = (a) => a.reduce((s, v) => s + v, 0);
const dual = (a, b, d = 1) => (b == null || b === a ? num(a, d) : num(a, d) + '→' + num(b, d));

function merged(key, tuned) {
  const base = ALL_W[key];
  if (!base) return null;
  if (!tuned || !TUNED[key]) return Object.assign({}, base);
  return Object.assign({}, base, TUNED[key]);
}

const MULTI = { shotgun: (w) => w.pellets || 1, nailgun: (w) => w.pellets || 1, bow: () => 2, shuriken: () => 2, typhoon: () => 3, cluster: () => 3 };
function perTrigger(key, w) {
  const type = String(w.type || '');
  if (type === 'melee') return w.dmg || 0;
  if (type === 'gun' || type === 'rocket' || type === 'glauncher' || type === 'knife' || type === 'shuriken' ||
      type === 'typhoon' || type === 'boomerang' || type === 'snake' || type === 'ball' || type === 'bow') {
    const n = (MULTI[key] || (() => 1))(w);
    return (w.dmg || 0) * n;
  }
  return w.dmg || 0;
}
function headMul(key, w) {
  const t = String(w.type || '');
  if (t === 'gun') return w.headMul || 2;
  if (t === 'bow' || t === 'knife' || t === 'shuriken' || t === 'typhoon') return 1.8;
  if (t === 'boomerang') return 1.5;
  return null; // melee: 1.5 offline zones only (web has no melee headshot)
}
function reloadDur(w) {
  if (!w.mag) return 0;
  if (w.rtype === 'shell') return 0.35 + w.mag * (w.perRound || 0.3) + 0.3; // Combat.start_reload
  return w.reload || 0;
}
function ammoLabel(w) {
  if (!w.ammo) return '∞';
  return w.mag ? `${w.ammo} (mag ${w.mag})` : `${w.ammo}`;
}
function sustainDps(key, w) {
  const pt = perTrigger(key, w);
  const cd = I[key] || w.cooldown || 0;
  if (!pt || !cd) return null;
  if (w.burst) return pt / Math.max(cd, w.burst.regen || cd);
  if (w.mag) return (w.mag * pt) / (w.mag * cd + reloadDur(w));
  return pt / cd;
}
function ttk(key, w, hp) {
  const pt = perTrigger(key, w);
  if (!pt) return null;
  const need = Math.ceil(hp / pt);
  const cd = I[key] || w.cooldown || 0;
  const burstN = w.burst ? w.burst.n : Infinity;
  const regen = w.burst ? w.burst.regen : 0;
  let mag = w.mag || Infinity;
  let ammo = Infinity; // TTK is cadence only; "Dmg/pickup" shows whether one pickup can do it
  let t = 0, fired = 0;
  for (let i = 0; i < need; i++) {
    if (i > 0) {
      if (fired >= burstN) t += Math.max(cd, regen); // burst pool empty: one charge back per regen
      else t += cd;
    }
    fired++;
    if (w.mag) {
      mag--;
      if (i < need - 1 && mag <= 0) { t += reloadDur(w); mag = Math.min(w.mag, ammo); }
    }
  }
  return t;
}
function special(key, w) {
  const s = [];
  if (key === 'flame') s.push('direct 31.7 + burn 5.5 ≈ 37 DPS');
  if (key === 'anglegrinder') s.push('direct 18.8 + burn ≈ 24 DPS; one pickup ≈ 70 max');
  if (key === 'blower') s.push('shared: no damage; tuned 41.7 DPS, one tank ≈ 149 max');
  if (key === 'glove') s.push('pure knockback (0 damage)');
  if (key === 'net') s.push('no damage: 4.5 s pin (2.5 tuned)');
  if (key === 'mammoth') s.push('head 230 shared (one-shot) / 120 tuned');
  if (key === 'bow') s.push('2 arrows, full draw; cycle 0.73 [i]');
  if (key === 'boomerang') s.push('can hit twice per throw; cycle 1.3 [i]');
  if (key === 'typhoon') s.push('3 blades pierce; return-gated cycle 1.2 [i]');
  if (w.style) s.push(w.style);
  if (w.pellets) s.push(`${w.pellets} pellets`);
  if (w.dual) s.push('dual');
  if (w.burst) s.push(`burst ${w.burst.n}/${w.burst.regen}s`);
  if (w.spinup) s.push(`spin-up ${w.spinup}s`);
  if (w.burn) s.push(`burn ${w.burn}s`);
  if (w.trap) s.push(`trap ${w.trap}s`);
  if (w.radius) s.push(`splash r${w.radius}`);
  if (w.bomblets) s.push(`+${w.bomblets} bomblets`);
  if (w.throwable) s.push('throwable');
  if (w.headMul) s.push(`headMul ${w.headMul}`);
  return s.join(', ') || '—';
}
function table(headers, rows) {
  console.log('| ' + headers.join(' | ') + ' |');
  console.log('| ' + headers.map(() => '---').join(' | ') + ' |');
  for (const r of rows) console.log('| ' + r.join(' | ') + ' |');
}

function weapons() {
  console.log('\n### WEAPONS (cell = shared → Godot offline tuned; a single number means both use it)\n');
  table(['Weapon', 'Key', 'Type', 'Dmg/trigger', 'Head×', 'Cd', 'TTK@150', 'DPS burst', 'DPS sustain', 'Ammo (mag)', 'Dmg/pickup', 'Range', 'Force (max)', 'Move×', 'Notes'], Object.keys(ALL_W)
    .filter((k) => !k.startsWith('_'))
    .sort((a, b) => (ALL_W[a].type === 'melee' ? 0 : 1) - (ALL_W[b].type === 'melee' ? 0 : 1) || a.localeCompare(b))
    .map((k) => {
      const a = merged(k, false), b = merged(k, true);
      const ptA = perTrigger(k, a), ptB = perTrigger(k, b);
      const ttA = ttk(k, a, HP), ttB = ttk(k, b, HP);
      const dpsA = ptA / (I[k] || a.cooldown), dpsB = ptB / (I[k] || b.cooldown);
      const susA = sustainDps(k, a), susB = sustainDps(k, b);
      return [a.name, k, a.type, dual(ptA, ptB), headMul(k, a) ? '×' + headMul(k, a) : '—',
        dual(a.cooldown, b.cooldown, 2),
        ttA == null ? 'n/a' : dual(ttA, ttB, 2),
        dual(dpsA, dpsB), susA == null ? '—' : dual(susA, susB),
        ammoLabel(a), a.ammo ? dual(a.ammo * ptA, b.ammo * ptB, 0) : '∞',
        a.range ? dual(a.range, b.range, 0) : '—',
        num(a.force) + (a.maxForce ? '(' + num(a.maxForce) + ')' : '') + (b.force !== a.force || b.maxForce !== a.maxForce ? '→' + num(b.force) + (b.maxForce ? '(' + num(b.maxForce) + ')' : '') : ''),
        dual(a.speedMul, b.speedMul, 2), special(k, a)];
    }));
  console.log('\n### OVERLAY FIELDS THAT DO NOT CHANGE DPS/TTK (control, feel, draw time)\n');
  console.log('speedMul / spread / bloom / wobble / swapCd / recoil / shake only; full field list with shared vs tuned values is in godot/data/extra/weapon_tuning.json and docs/DAMAGE.md.\n');
}

function classes() {
  console.log('\n### CLASSES (EHP = 200 x hp; TTD vs tuned AK-47 body 60 DPS)\n');
  table(['Class', 'Key', 'EHP', 'TTD@200/@150', 'Spd m/s', 'Acc', 'Air', 'Jump', 'KB×', 'Dmg×', 'Rate×', 'Reload×', 'Ammo×', 'Extra'],
    Object.keys(CLASSES).filter((k) => !k.startsWith('_')).map((k) => {
      const c = CLASSES[k];
      const extra = c.price ? `price ${c.price}` : c.unlock ? `unlock: ${c.unlock.text}` : (c.hidden ? 'secret' : '—');
      return [c.name, k, num(200 * c.hp, 0), `${num(200 * c.hp / AK_TUNED_DPS, 2)}/${num(150 * c.hp / AK_TUNED_DPS, 2)}`,
        num(7.5 * c.spd, 2), num(c.acc, 2), num(c.air, 2), num(c.jump, 2), num(c.kb, 2), num(c.dmg, 2),
        num(c.rate, 2), num(c.reload, 2), num(c.ammo, 2), extra];
    }));
}

function drops() {
  const base = DROPS.base;
  const mods = ['classic', 'melee', 'guns', 'ninja', 'explosive', 'mega', 'giant', 'construction'];
  console.log('\n### CRATE POOL WEIGHTS (normal weapon state; heal and power-ups included)\n');
  for (const m of mods) {
    const allow = DROPS.allow[m] || [];
    const rows = allow.filter((k) => base[k]).map((k) => [k, base[k]]);
    const tot = sum(rows.map((r) => r[1]));
    const top = rows.slice().sort((a, b) => b[1] - a[1]).slice(0, 6)
      .map(([k, v]) => `${k} ${(100 * v / tot).toFixed(1)}%`).join(', ');
    console.log(`${m}: ${rows.length} keys, total weight ${tot.toFixed(2)}; heal ${(100 * base.heal / tot).toFixed(1)}%; power-ups ` +
      `${(100 * sum(['speed', 'rage', 'shield'].map((k) => base[k] || 0)) / tot).toFixed(1)}%; top: ${top}`);
  }
  console.log('\n### CRATE RATES (Pickups.update: uniform 3..5 s x rate; max 10 live crates, 45 s lifetime)\n');
  table(['Rate', 'Multiplier', 'Interval (s)', 'Crates/min (uncapped)'],
    Object.keys(RATES).map((k) => [k, RATES[k], `${num(3 * RATES[k], 2)}–${num(5 * RATES[k], 2)}`, num(60 / (4 * RATES[k]))]));
}

function modes() {
  console.log('\n### MODES\n');
  table(['Mode', 'Teams', 'HP', 'Lives', 'Limit', 'Grav', 'Dmg×', 'KB×', 'Crate pool', 'Mutator'], Object.keys(MODES).filter((k) => !k.startsWith('_')).map((k) => {
    const m = MODES[k] || {};
    const pre = m.preset || {};
    const t = m.teams || 0;
    const mut = [];
    if (m.dmgMul) mut.push(`dmg ×${m.dmgMul}`);
    if (m.kbMul) mut.push(`kb ×${m.kbMul}`);
    if (m.ladder) mut.push('weapon ladder');
    if (m.chaos) mut.push('chaos events');
    if (m.trap) mut.push('pillars');
    if (m.flexTeams) mut.push('flex teams');
    return [m.name || k, t ? t + 'v' + t : (pre.ffa ? 'FFA' : '—'), num(pre.hp || (k === 'explosive' ? 300 : 200), 0),
      num(m.lives || 0, 0), num(pre.limit ?? 0, 0), num(pre.grav ?? 1, 2), m.dmgMul || 1, m.kbMul || 1,
      m.dropsAs || (DROPS.allow[k] ? 'own' : m.dropAllow ? 'dropAllow' : '—'), mut.join(', ') || '—'];
  }));
}

function bosses() {
  const diffs = STAGES.difficulties;
  console.log('\n### BOSSES (solo class inheritance: bruiser; co-op: kid — see review)\n');
  table(['#', 'Boss', 'Table hp', 'Easy/Normal/Nightmare HP', 'Walk solo/co-op (m/s)', 'Weapon (reach)', 'DPS vs player P1 (solo/co-op)', 'Force/topple', 'Ability', 'Crew'],
    STAGES.stages.filter((s) => s.boss).map((s, si) => {
      const b = s.bots[0], dd = DIFFS[b.difficulty];
      const hp = {};
      for (const d of ['easy', 'normal', 'nightmare']) {
        const df = diffs[d];
        hp[d] = 200 * Math.min(b.hp, Math.max(b.hp * df.hp_mul, df.boss_hp_floor));
      }
      const spd = dd.speed * b.speed;
      const w = ALL_W[b.weapon] || {};
      const df = diffs.normal;
      const scale = dd.dmg * b.dmg_scale * df.dmg_mul;
      const dpsSolo = w.dmg ? w.dmg * scale * 1.12 * 0.95 / w.cooldown : 0;
      const dpsCoop = w.dmg ? w.dmg * scale * 0.92 * 1.05 / w.cooldown : 0;
      const reach = w.tip ? (w.tip * (/giant_scale/.test(JSON.stringify(s.events)) ? 2.2 : 1)) : w.range;
      return [si + 2, b.name, `${b.hp}×`, `${num(hp.easy, 0)} / ${num(hp.normal, 0)} / ${num(hp.nightmare, 0)}`,
        `${num(spd * 0.88, 2)} / ${num(spd * 1.22, 2)}`,
        `${b.weapon}${w.tip ? ' (reach ' + num(reach, 2) + ')' : ''}`,
        num(dpsSolo) + ' / ' + num(dpsCoop), w.force == null ? '—' : num(w.force) + '/' + (w.topple || 0),
        (s.events || []).map((e) => e.type).join(', '),
        (s.bots || []).length + ' (' + (s.bots || []).map((x) => x.name).join(', ') + ')'];
    }));
  console.log('\n### ARCADE CREW / HP FLOORS');
  for (const d of ['easy', 'normal', 'nightmare']) {
    const df = diffs[d];
    console.log(`${d}: hp×${df.hp_mul}, floors ${df.hp_floor}/${df.boss_hp_floor}, dmg×${df.dmg_mul}, speed×${df.speed_mul}, ` +
      `events×${df.event_mul}, lives ${df.lives}, coins×${df.coin_mul}`);
  }
}

const which = (process.argv[2] || 'all').toLowerCase();
const sections = { weapons, classes, drops, modes, bosses };
if (which === 'all') for (const k in sections) sections[k]();
else if (sections[which]) sections[which]();
else { console.error('usage: node tools/balance-tables.js [all|weapons|classes|drops|modes|bosses]'); process.exit(2); }
