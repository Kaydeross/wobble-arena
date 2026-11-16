'use strict';
/* Balance telemetry runner (docs/BALANCE_TELEMETRY.md): plays many bot-vs-bot offline matches headless
   (godot/tests/balance_match.gd, one match per Godot process) and prints Markdown balance tables.
     npm run balance -- --matches 200 --out balance.md
   Options: --matches N (200)  --jobs N (CPUs-1, max 8)  --bots N (4 bots + the player's seat, also a bot = 5 fighters)  --seconds N (90)  --mode id (classic)
            --maps a,b,c (arena,rooftops,temple)  --seed BASE (1)  --out file.md  --json raw.json  --selftest
   Tooling only: no dependencies, nothing here touches the game. */
const { spawn, spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
const ROOT = path.join(__dirname, '..');
const CLASSES = ['wobbler', 'bruiser', 'kid', 'elder', 'alien'];
const TIMEOUT_MS = 120000;
const OUTLIER_HI = 1.5, OUTLIER_LO = 0.5, MIN_KOS = 10;   // flag only groups with at least MIN_KOS K.O.s

function parseArgs(argv) {
  const o = { matches: 200, jobs: Math.max(1, Math.min(8, os.cpus().length - 1)), bots: 4, seconds: 90, mode: 'classic',
    maps: ['arena', 'rooftops', 'temple'], seed: 1, out: '', json: '', selftest: false, weapon: '' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i], v = () => argv[++i];
    if (a === '--matches') o.matches = +v(); else if (a === '--jobs') o.jobs = Math.max(1, +v());
    else if (a === '--bots') o.bots = +v(); else if (a === '--seconds') o.seconds = +v();
    else if (a === '--mode') o.mode = v(); else if (a === '--maps') o.maps = v().split(',').filter(Boolean);
    else if (a === '--seed') o.seed = +v(); else if (a === '--out') o.out = v(); else if (a === '--json') o.json = v();
    else if (a === '--weapon') o.weapon = v(); else if (a === '--selftest') o.selftest = true;
    else { console.error('unknown option ' + a); process.exit(2); }
  }
  return o;
}

/* The plan for match i: its seed, map and the class of every seat. Seats rotate through all classes, so each class
   appears equally often (exactly, when matches x bots is a multiple of the class count). */
function plan(o) {
  const out = [];
  for (let i = 0; i < o.matches; i++) {
    const classes = [];
    for (let s = 0; s <= o.bots; s++) classes.push(CLASSES[(i * (o.bots + 1) + i + s) % CLASSES.length]);   // bots + the player's seat; +i also rotates who sits in seat 0
    out.push({ i, seed: o.seed + i, map: o.maps[i % o.maps.length], classes });
  }
  return out;
}

function runOne(p, o) {
  return new Promise(resolve => {
    const args = ['--headless', '--path', GD, '--script', 'res://tests/balance_match.gd', '--', '--no-save',
      `--seed=${p.seed}`, `--bots=${o.bots}`, `--seconds=${o.seconds}`, `--mode=${o.mode}`, `--map=${p.map}`, `--classes=${p.classes.join(',')}`];
    if (o.weapon) args.push(`--weapon=${o.weapon}`);
    const c = spawn(GODOT, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '', done = false;
    const fin = r => { if (!done) { done = true; clearTimeout(t); resolve(r); } };
    const t = setTimeout(() => { c.kill('SIGKILL'); fin({ ok: false, why: 'timeout', plan: p }); }, TIMEOUT_MS);
    c.stdout.on('data', d => { out += d; }); c.stderr.on('data', d => { out += d; });
    c.on('error', e => fin({ ok: false, why: e.message, plan: p }));
    c.on('close', code => {
      const line = out.split('\n').find(l => l.startsWith('BALANCE '));
      if (!line) return fin({ ok: false, why: 'no BALANCE line (exit ' + code + ')', plan: p });
      try { fin({ ok: true, res: JSON.parse(line.slice(8)), plan: p }); } catch (e) { fin({ ok: false, why: 'bad JSON', plan: p }); }
    });
  });
}

async function pool(items, jobs, fn, tick) {
  const results = new Array(items.length); let next = 0, done = 0;
  await Promise.all(Array.from({ length: Math.min(jobs, items.length) }, async () => {
    while (next < items.length) { const k = next++; results[k] = await fn(items[k]); tick && tick(++done, items.length, results[k]); }
  }));
  return results;
}

const pct = (a, b) => isFinite(a) && b > 0 ? (100 * a / b).toFixed(1) + '%' : '-';
const f2 = x => (isFinite(x) ? x.toFixed(2) : '-');
const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : NaN;

/* results: array of parsed BALANCE objects (successful matches only). */
function aggregate(results) {
  const cls = {}, wep = {};
  const C = id => cls[id] || (cls[id] = { id, app: 0, kos: 0, deaths: 0, falls: 0, dmg: 0, hits: 0, wins: 0, secs: 0, crates: 0 });
  const W = id => wep[id] || (wep[id] = { id, kos: 0, ttk: [], picks: 0 });
  let totalKos = 0, fighterSecs = 0, crates = 0, fighters = 0, totalRingouts = 0, firstKos = [];
  for (const r of results) {
    const secs = r.seconds_simulated;
    r.fighters.forEach((f, i) => {
      const c = C(f.class_id);
      c.app++; c.kos += f.kos; c.deaths += f.deaths; c.falls += f.falls; c.dmg += f.dmg; c.hits += f.hits; c.secs += secs; c.crates += f.crates_picked;
      if (r.winner === i) c.wins++;
      totalKos += f.kos; fighterSecs += secs; crates += f.crates_picked; fighters++;
      for (const [k, n] of Object.entries(f.weapon_picks || {})) W(k).picks += n;
    });
    totalRingouts += r.total_ringouts;
    if (r.first_ko_time != null) firstKos.push(r.first_ko_time);
    for (const e of r.ko_events || []) { const w = W(e.wkey || 'spatula'); w.kos++; w.ttk.push(e.ttk); }
  }
  const classes = Object.values(cls).sort((a, b) => a.id.localeCompare(b.id));
  const weapons = Object.values(wep).sort((a, b) => b.kos - a.kos || a.id.localeCompare(b.id));
  const weaponKos = weapons.reduce((s, w) => s + w.kos, 0);
  const flag = (share, even, kos) => kos < MIN_KOS ? 'low n' : share > OUTLIER_HI * even ? 'OUTLIER high' : share < OUTLIER_LO * even ? 'OUTLIER low' : '';
  const classRows = classes.map(c => {
    const share = totalKos ? c.kos / totalKos : 0, even = 1 / classes.length;
    return { id: c.id, appearances: c.app, kosPerMatch: c.kos / c.app, koShare: share, deathsPerMatch: c.deaths / c.app,
      kd: c.deaths ? c.kos / c.deaths : NaN, ringoutRate: c.deaths ? c.falls / c.deaths : NaN, dmgPerMatch: c.dmg / c.app,
      winRate: c.app ? c.wins / c.app : NaN, flag: flag(share, even, c.kos) };
  });
  const weaponRows = weapons.map(w => {
    const share = weaponKos ? w.kos / weaponKos : 0, even = 1 / weapons.length;
    return { id: w.id, kos: w.kos, koShare: share, avgTtk: mean(w.ttk), picks: w.picks, pickRate: fighterSecs ? w.picks / (fighterSecs / 60) : NaN,
      kosPerPick: w.picks ? w.kos / w.picks : NaN, flag: flag(share, even, w.kos) };
  });
  return { classRows, weaponRows, matches: results.length, fighters, totalKos, totalRingouts, cratesPerFighterMin: fighterSecs ? crates / (fighterSecs / 60) : NaN,
    avgFirstKo: mean(firstKos), avgKosPerMatch: results.length ? totalKos / results.length : NaN, secs: fighterSecs };
}

function table(head, rows) { return ['| ' + head.join(' | ') + ' |', '|' + head.map(() => '---').join('|') + '|', ...rows.map(r => '| ' + r.join(' | ') + ' |')].join('\n'); }

function markdown(agg, meta) {
  const L = [];
  L.push('# Balance telemetry', '');
  if (meta) {
    L.push(`- Matches: ${agg.matches} ok${meta.failed ? `, **${meta.failed} FAILED**` : ''} of ${meta.requested}  (${meta.bots} bots + player seat, ${meta.seconds} s sim each, mode ${meta.mode}, maps ${meta.maps.join('/')})`);
    L.push(`- Seeds: ${meta.seed}..${meta.seed + meta.requested - 1}`);
    L.push(`- Date: ${meta.date}   Commit: ${meta.commit}   Godot: ${meta.godot}   Wall time: ${meta.wall}`);
    L.push('');
  }
  L.push('## Per class', '');
  L.push(table(['Class', 'Appearances', 'K.O.s/match', 'K.O. share', 'Deaths/match', 'K/D', 'Ring-out rate', 'Dmg/match', 'Win rate', 'Flag'],
    agg.classRows.map(c => [c.id, c.appearances, f2(c.kosPerMatch), pct(c.koShare, 1), f2(c.deathsPerMatch), f2(c.kd), pct(c.ringoutRate, 1), c.dmgPerMatch.toFixed(0), pct(c.winRate, 1), c.flag])));
  L.push('', '## Per weapon (by the weapon in hand at the K.O.)', '');
  L.push(table(['Weapon', 'K.O.s', 'K.O. share', 'Avg TTK (s)', 'Picks', 'Picks/fighter-min', 'K.O.s/pick', 'Flag'],
    agg.weaponRows.map(w => [w.id, w.kos, pct(w.koShare, 1), f2(w.avgTtk), w.picks, f2(w.pickRate), f2(w.kosPerPick), w.flag])));
  L.push('', '## Crates and pace', '');
  L.push(`- Crate pick rate: ${f2(agg.cratesPerFighterMin)} crates per fighter per minute (all crates incl. health / power-ups)`);
  L.push(`- K.O.s per match: ${f2(agg.avgKosPerMatch)}; ring-outs per match: ${f2(agg.totalRingouts / agg.matches)}; average first K.O. at ${f2(agg.avgFirstKo)} s`);
  const out = [...agg.classRows.map(c => ['class', c]), ...agg.weaponRows.map(w => ['weapon', w])].filter(([, r]) => r.flag.startsWith('OUTLIER'));
  L.push('', '## Flags', '');
  if (out.length) for (const [k, r] of out) L.push(`- **${r.flag}**: ${k} \`${r.id}\` has ${pct(r.koShare, 1)} of K.O.s`);
  else L.push('- No class or weapon is an OUTLIER (K.O. share within 0.5x-1.5x of the even share).');
  L.push('', '_TTK = seconds from the killer\'s latest respawn (or match start) or previous K.O., whichever is later, to the K.O.; see docs/BALANCE_TELEMETRY.md._', '');
  return L.join('\n');
}

function selftest() {
  const mk = (cls, kos, deaths, falls, dmg, extra) => Object.assign({ class_id: cls, kos, deaths, falls, hits: 5, dmg, crates_picked: 2, weapon_picks: {} }, extra);
  const fx = [
    { seconds_simulated: 60, total_ringouts: 2, first_ko_time: 10, winner: 0, fighters: [mk('kid', 6, 3, 1, 100, { weapon_picks: { bat: 2 } }), mk('alien', 2, 4, 1, 60)],
      ko_events: [{ wkey: 'bat', ttk: 10 }, { wkey: 'bat', ttk: 20 }, { wkey: 'spatula', ttk: 30 }, { wkey: 'spatula', ttk: 10 }, { wkey: 'bat', ttk: 6 }, { wkey: 'bat', ttk: 8 }, { wkey: 'spatula', ttk: 4 }, { wkey: 'spatula', ttk: 4 }] },
    { seconds_simulated: 60, total_ringouts: 0, first_ko_time: 20, winner: -1, fighters: [mk('kid', 2, 2, 0, 40, { weapon_picks: { bat: 1 } }), mk('alien', 2, 2, 0, 50)],
      ko_events: [{ wkey: 'spatula', ttk: 20 }, { wkey: 'spatula', ttk: 20 }, { wkey: 'bat', ttk: 20 }, { wkey: 'bat', ttk: 20 }] },
  ];
  const a = aggregate(fx), kid = a.classRows.find(c => c.id === 'kid'), al = a.classRows.find(c => c.id === 'alien'), bat = a.weaponRows.find(w => w.id === 'bat');
  const bad = [];
  const eq = (name, got, want) => { if (Math.abs(got - want) > 1e-9) bad.push(`${name}: got ${got}, want ${want}`); };
  eq('matches', a.matches, 2); eq('totalKos', a.totalKos, 12);
  eq('kid app', kid.appearances, 2); eq('kid kos/match', kid.kosPerMatch, 4); eq('kid share', kid.koShare, 8 / 12);
  eq('kid K/D', kid.kd, 8 / 5); eq('kid ringout', kid.ringoutRate, 1 / 5); eq('kid dmg', kid.dmgPerMatch, 70); eq('kid win', kid.winRate, 0.5);
  eq('alien share', al.koShare, 4 / 12); eq('alien win', al.winRate, 0);
  eq('bat kos', bat.kos, 6); eq('bat avg ttk', bat.avgTtk, (10 + 20 + 6 + 8 + 20 + 20) / 6); eq('bat picks', bat.picks, 3); eq('bat pickrate', bat.pickRate, 3 / (240 / 60));
  eq('crates/min', a.cratesPerFighterMin, 8 / 4);
  eq('first ko avg', a.avgFirstKo, 15);
  // kid 66.7% of K.O.s vs even 50% -> 1.33x: not an outlier; with 3 classes it would be 2x -> outlier
  if (kid.flag !== 'low n') bad.push('kid flag should be low n (8 K.O.s < ' + MIN_KOS + ')');
  const big = aggregate([{ seconds_simulated: 60, total_ringouts: 0, first_ko_time: 5, winner: 0, ko_events: [],
    fighters: [mk('kid', 30, 5, 0, 1), mk('alien', 5, 5, 0, 1), mk('elder', 5, 5, 0, 1)] }]);
  const flags = Object.fromEntries(big.classRows.map(c => [c.id, c.flag]));
  if (flags.kid !== 'OUTLIER high') bad.push('kid should be OUTLIER high, got ' + flags.kid);
  if (flags.alien !== 'low n') bad.push('alien flag ' + flags.alien);
  const md = markdown(a, null);
  if (!/\| kid \| 2 \| 4\.00 \| 66\.7% /.test(md)) bad.push('markdown kid row missing');
  const p = plan({ matches: 10, bots: 4, maps: ['a', 'b', 'c'], seed: 1 }), cnt = {};
  p.forEach(m => m.classes.forEach(c => { cnt[c] = (cnt[c] || 0) + 1; }));
  if (Object.values(cnt).some(n => n !== 10)) bad.push('class rotation uneven ' + JSON.stringify(cnt));
  if (bad.length) { console.error('balance tool selftest FAILED\n  ' + bad.join('\n  ')); process.exit(1); }
  console.log('balance tool selftest passes');
}

async function main() {
  const o = parseArgs(process.argv.slice(2));
  if (o.selftest) return selftest();
  const t0 = Date.now();
  spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 180000 });   // registers class_name scripts
  const ver = (spawnSync(GODOT, ['--version'], { encoding: 'utf8' }).stdout || '').trim();
  const git = (...a) => (spawnSync('git', a, { cwd: ROOT, encoding: 'utf8' }).stdout || '').trim();
  const dirty = git('status', '--porcelain', '--', 'godot', 'shared') ? '+dirty' : '';
  const plans = plan(o);
  console.error(`balance: ${o.matches} matches, ${o.jobs} jobs, ${o.bots} bots, ${o.seconds} s, maps ${o.maps.join(',')}`);
  const runs = await pool(plans, o.jobs, p => runOne(p, o), (d, n, r) => {
    if (!r.ok) console.error(`  match ${r.plan.i} (seed ${r.plan.seed}, ${r.plan.map}) failed: ${r.why}`);
    if (d % 10 === 0 || d === n) console.error(`  ${d}/${n} done (${((Date.now() - t0) / 1000).toFixed(0)} s)`);
  });
  const good = runs.filter(r => r.ok).map(r => r.res), failed = runs.length - good.length;
  const wallS = (Date.now() - t0) / 1000;
  if (!good.length) { console.error('balance: every match failed'); process.exit(1); }
  const agg = aggregate(good);
  const md = markdown(agg, { requested: o.matches, failed, bots: o.bots, seconds: o.seconds, mode: o.mode, maps: o.maps, seed: o.seed,
    date: new Date().toISOString().slice(0, 10), commit: git('rev-parse', '--short', 'HEAD') + dirty, godot: ver, wall: `${Math.floor(wallS / 60)} m ${Math.round(wallS % 60)} s` });
  if (o.json) fs.writeFileSync(o.json, JSON.stringify({ options: o, failed, results: good }, null, 1));
  if (o.out) { fs.writeFileSync(o.out, md); console.error('balance: wrote ' + o.out); } else console.log(md);
  process.exit(failed && failed === runs.length ? 1 : 0);
}

if (require.main === module) main(); else module.exports = { aggregate, markdown, plan, parseArgs };
