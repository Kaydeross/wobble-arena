'use strict';
/* Cross-play guest test (npm run test:godot-netguest):
   1. Interpolation parity: tools/net-interp-reference.js runs the web game's netStep lines, the Godot NetMatch.interp
      replays the same stream (worst error <= 1e-9).
   2. The real server (REQUIRE_LOGIN=0) + a Node host bot (tools/wa-client.js) that acts like the web host: answers
      hello with welcome/roster/start/crates, streams `S` for its own fighter (slot 0, running a circle) and a bot
      (slot 2), sends `sw`/`k`, a scripted `h` at the Godot guest, then `pend`. The Godot guest (tests/net_guest_test.gd)
      runs the real World headless. Checked here: join + hello (proto, cls), welcome, start, the ghost follows the
      host's stream, the guest's own `S` arrives at ~30 Hz with sane values, the host's `h` lowers the guest's hp,
      the guest's hit on the bot arrives as `h` (to 0, vs 2, from 1), forged pend/start on a non-host path are ignored,
      the rematch vote arrives, no Godot errors. The room is created with an older build string to exercise the
      guest's build retry (the web game bumps NET_BUILD each release; proto decides). */
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-netguest-' + process.pid;
const srv = require('../server');
const { Client } = require('./wa-client');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const ERR = /SCRIPT ERROR|^ERROR|Parse Error|leaked/i;

function interpParity() {
  const ref = path.join(os.tmpdir(), 'wa-interp-' + process.pid + '.json');
  require('child_process').execFileSync(process.execPath, [path.join(__dirname, 'net-interp-reference.js'), ref]);
  const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/net_interp_test.gd', '--', ref], { encoding: 'utf8', timeout: 120000 });
  const out = (r.stdout || '') + (r.stderr || '');
  fs.rmSync(ref, { force: true });
  console.log(out.split('\n').filter(l => /^(INTERP|FAIL)/.test(l)).join('\n'));
  const errs = out.split('\n').filter(l => ERR.test(l));
  assert.ok(r.status === 0 && /^INTERP /m.test(out) && !errs.length, 'interpolation parity\n' + errs.join('\n'));
}

const lines = [];
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
  interpParity();

  await srv.start(0);
  const url = 'ws://127.0.0.1:' + srv.server.address().port + '/ws';
  const host = await new Client(url, 'NodeHost').open();
  const id = await host.create(false, 'b76.0');            // an older web build: the guest must retry without a build
  const fromGuest = [];                                    // {at, m}
  host.ws.on('message', d => { let m; try { m = JSON.parse(d.toString()); } catch (e) { return; } if (m.op === 'msg' && m.from !== undefined) fromGuest.push({ at: Date.now(), m: m.m }); });

  const marks = {};
  const p = spawn(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/net_guest_test.gd', '--', url, id, '--no-save']);
  let buf = '';
  const onData = d => {
    buf += d.toString(); let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const l = buf.slice(0, i); buf = buf.slice(i + 1); lines.push({ at: Date.now(), l });
      const k = l.split(' ')[0]; if (!marks[k]) marks[k] = Date.now();
    }
  };
  p.stdout.on('data', onData); p.stderr.on('data', onData);
  const exited = new Promise(r => p.on('exit', r));

  const hello = await host.wait(m => m.op === 'msg' && m.m.t === 'hello', 30000);
  assert.equal(hello.m.proto, 1, 'hello carries proto 1');
  assert.equal(hello.m.cls, 'kid', 'hello carries the class from Settings');
  assert.equal(hello.m.name, 'GodotGuest'); assert.equal(hello.m.hat, 'cone');
  const cid = hello.from;
  const me = { id: 1, name: hello.m.name, skin: hello.m.skin, hat: hello.m.hat, color: hello.m.color, cls: hello.m.cls };
  host.to(cid, { t: 'welcome', id: 1, name: 'NodeHost room', pub: false, proto: 1 });
  const hostInfo = { id: 0, name: 'NodeHost', skin: 'none', hat: 'none', color: 0x39b5a8, cls: 'bruiser' };
  host.to(cid, { t: 'roster', roster: [hostInfo, me], max: 4, bots: true, lim: 0, bhv: 'brawl', diff: 'normal', modeName: 'Classic', map: 'Sunny Arena' });
  const slots = [Object.assign({ kind: 'human' }, hostInfo), Object.assign({ kind: 'human' }, me), { kind: 'bot', id: 2, name: 'Bot Gus', skin: 'none', hat: 'party', color: 0xf08a3c, cls: 'wobbler' }, { kind: 'empty', id: 3, name: '', skin: 'none', hat: 'none', color: 0 }];
  host.to(cid, { t: 'start', slots, map: 'arena', custom: {}, limit: 0, rules: { mode: 'classic', hp: 200, crate: 'normal', wstate: {}, grav: 1, kb: 1, inf: false } });
  host.to(cid, { t: 'crates', list: [{ cid: 7, key: 'smg', spot: [-14, -14] }] });

  // the host's own fighter runs a circle (r 6, 0.5 rad/s); its bot stands at (6, -4)
  const t0 = Date.now(); const path0 = [];
  const pos = t => ({ x: 6 * Math.cos(0.5 * t), z: 6 * Math.sin(0.5 * t), vx: -3 * Math.sin(0.5 * t), vz: 3 * Math.cos(0.5 * t) });
  const r2 = v => +v.toFixed(2);
  const ent = (sid, q, hp, w) => ({ id: sid, x: r2(q.x), y: 0, z: r2(q.z), vx: r2(q.vx), vy: 0, vz: r2(q.vz), yaw: r2(Math.atan2(q.vx, q.vz)), ax: 0, ay: 0, az: 1, w, hp, d: 0, g: 1, sq: 0, iv: 0, lv: 0, el: 0 });
  const stream = setInterval(() => {
    const t = (Date.now() - t0) / 1000, q = pos(t); path0.push({ at: Date.now(), x: q.x, z: q.z });
    host.to(cid, { t: 'S', l: [ent(0, q, 260, 'spatula'), ent(2, { x: 6, z: -4, vx: 0, vz: 0 }, 200, 'spatula')] });
  }, 1000 / 30);

  while (!marks.START && Date.now() - t0 < 20000) await sleep(50);
  assert.ok(marks.START, 'guest started the match');
  const tS = marks.START;
  const at = async ms => { const w = tS + ms - Date.now(); if (w > 0) await sleep(w); };
  await at(2000); host.to(cid, { t: 'sw', id: 0, yaw: 0.5, w: 'spatula' });
  await at(2300); host.to(cid, { t: 'k', id: 0, yaw: 0.5 });
  await at(3000); const hAt = Date.now(); host.to(cid, { t: 'h', to: 1, vs: 1, from: 2, d: 30, x: 0, y: 0.2, z: 1, f: 5, hd: 0 });
  await at(7000); host.to(cid, { t: 'pend', w: 0 });
  const rv = await host.wait(m => m.op === 'msg' && m.from === cid && m.m.t === 'rv', 8000).catch(() => null);
  host.to(cid, { t: 'rvs', list: [1], total: 2 });
  const code = await Promise.race([exited, sleep(15000).then(() => 'hang')]);
  clearInterval(stream);
  if (code === 'hang') p.kill();
  const text = lines.map(x => x.l);
  console.log(text.filter(l => /^(WELCOMED|START|HIT_SENT|FORGED|MATCH_END|SENT|RECV|DONE|FAIL|ENDED)/.test(l)).join('\n'));
  const errs = text.filter(l => ERR.test(l));
  for (const l of errs) console.log('godot:', l);

  // ghost of slot 0 follows the stream: compare each GHOST line with where the host said it was just before
  const gl = lines.filter(x => /^GHOST 0 /.test(x.l) && x.at > tS + 1000 && x.at < tS + 6500).map(x => { const f = x.l.split(' '); return { at: x.at, x: +f[2], z: +f[4] }; });
  const errsPos = gl.map(g => Math.min(...path0.filter(q => q.at <= g.at && q.at >= g.at - 400).map(q => Math.hypot(q.x - g.x, q.z - g.z)), 99)).sort((a, b) => a - b);
  const med = errsPos[errsPos.length >> 1];
  const xs = gl.map(g => g.x);
  const ghostBot = lines.filter(x => /^GHOST 2 /.test(x.l)).pop();
  // the guest's own S stream
  const S = fromGuest.filter(x => x.m.t === 'S' && x.at > tS + 1000 && x.at < tS + 6000);
  const rate = S.length / 5;
  const e0 = S.length ? S[0].m.l[0] : {};
  const sane = S.every(x => Array.isArray(x.m.l) && x.m.l.length === 1 && x.m.l[0].id === 1 && [x.m.l[0].x, x.m.l[0].y, x.m.l[0].z, x.m.l[0].hp].every(Number.isFinite) && Math.abs(x.m.l[0].x) < 40 && Math.abs(x.m.l[0].z) < 40 && x.m.l[0].hp > 0 && x.m.l[0].hp <= 150 && typeof x.m.l[0].w === 'string');
  const zs = S.map(x => x.m.l[0].z);
  const afterH = fromGuest.filter(x => x.m.t === 'S' && x.at > hAt + 150 && x.at < hAt + 1500).map(x => x.m.l[0].hp);
  const hitOut = fromGuest.find(x => x.m.t === 'h');
  console.log(`ghost: ${gl.length} samples, median error ${med && med.toFixed(3)} m, x range ${(Math.max(...xs) - Math.min(...xs)).toFixed(1)} m; bot ghost: ${ghostBot && ghostBot.l}`);
  console.log(`guest S: ${rate.toFixed(1)} Hz, first ${JSON.stringify(e0)}; walked ${(Math.max(...zs) - Math.min(...zs)).toFixed(1)} m; hp after h: ${afterH.slice(0, 3)}; h out: ${JSON.stringify(hitOut && hitOut.m)}; rv: ${!!rv}`);

  assert.ok(text.some(l => /^WELCOMED slot=1/.test(l)), 'welcomed as slot 1');
  assert.ok(text.some(l => /^START map=arena slots=4 my_slot=1/.test(l)), 'match started');
  assert.ok(gl.length >= 20 && med < 0.5, 'ghost follows the host stream (median error ' + med + ')');
  assert.ok(Math.max(...xs) - Math.min(...xs) > 3, 'ghost moved');
  assert.ok(ghostBot && Math.hypot(+ghostBot.l.split(' ')[2] - 6, +ghostBot.l.split(' ')[4] + 4) < 0.3, 'bot ghost at its stream position');
  assert.ok(!lines.some(x => /^GHOST 3 /.test(x.l)), 'empty slot has no visible ghost');
  assert.ok(rate >= 25 && rate <= 35, 'guest S at ~30 Hz (' + rate + ')');
  assert.ok(sane, 'guest S entries are sane');
  assert.ok(Math.max(...zs) - Math.min(...zs) > 3, 'guest S follows its own movement');
  assert.ok(afterH.length && Math.max(...afterH) <= 120 && Math.min(...afterH) > 100, 'host h took 30 hp off the guest (150 -> 120)');
  assert.ok(hitOut && hitOut.m.to === 0 && hitOut.m.vs === 2 && hitOut.m.from === 1 && hitOut.m.d === 12, 'guest hit on the bot routed to the host');
  assert.ok(fromGuest.some(x => x.m.t === 'ping'), 'guest pings the host');
  assert.ok(text.some(l => /^FORGED ignored=true dropped=2/.test(l)), 'forged pend/start ignored');
  assert.ok(text.some(l => /^MATCH_END w=0 results=true/.test(l)), 'host pend ends the match');
  assert.ok(rv, 'rematch vote sent');
  assert.equal(errs.length, 0, 'no Godot errors');
  assert.equal(code, 0, 'godot exit code');
  console.log('godot net guest test passes');
  host.close(); await srv.stop(); process.exit(0);
})().catch(async e => { console.log(lines.map(x => x.l).filter(l => !/^(GHOST|ME|HP) /.test(l)).slice(0, 60).join('\n')); console.error('FAIL', e.message); try { await srv.stop(); } catch (x) { /* x */ } process.exit(1); });
