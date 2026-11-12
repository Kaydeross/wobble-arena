'use strict';
/* Cross-play HOST test (npm run test:godot-host): a Godot client hosts, a web-protocol guest and a Godot guest join.
   - the real server (REQUIRE_LOGIN=0);
   - Godot host (godot/tests/net_host_test.gd): HostSession + the real World headless, 4 seats, 1 bot, K.O. limit 1;
   - web guest (tools/wa-client.js, speaks exactly what public/index.html's guest sends): hello, streams its own `S`
     (walking along x), sends forged messages the host must drop, then kills the host's bot with an `h` (to 0);
   - Godot guest (godot/tests/net_host_peer.gd): GuestSession + World, walks, hits the host's own fighter.
   Checked: roster/welcome/start (slots human,human,human,bot with the bot's name, rules), the host's `S` at ~30 Hz
   with slots 0 and 3, the Godot guest's `S` relayed to the web guest stamped with its slot, guest input moves the
   ghosts on the host, the host's `h` reaches only its victim, the guest's hit on the host lowers its hp, forged
   pend/ko/h/start are dropped (netGuard), the bot K.O. arrives as `ko` and ends the match with `pend` (limit 1),
   rematch votes (rvs) and a second `start`, the web guest leaving turns its seat back into a bot (`slot`), no errors. */
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const os = require('os');
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-nethost-' + process.pid;
const srv = require('../server');
const { Client } = require('./wa-client');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const ERR = /SCRIPT ERROR|^ERROR|Parse Error|leaked/i;
const sleep = ms => new Promise(r => setTimeout(r, ms));

function runGodot(script, args, tag) {
  const p = spawn(GODOT, ['--headless', '--path', DIR, '--script', script, '--', ...args, '--no-save']);
  const out = { p, lines: [], marks: {} };
  let buf = '';
  const onData = d => {
    buf += d.toString(); let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const l = buf.slice(0, i); buf = buf.slice(i + 1); out.lines.push({ at: Date.now(), l });
      const k = l.split(' ')[0]; if (!out.marks[k]) out.marks[k] = Date.now();
      if (process.env.VERBOSE && !/^(GHOST|BOT|ME|SLOTS|HP) /.test(l)) console.log(tag + ': ' + l);
    }
  };
  p.stdout.on('data', onData); p.stderr.on('data', onData);
  out.exited = new Promise(r => p.on('exit', c => r(c)));
  out.waitLine = async (re, ms) => { const t0 = Date.now(); for (;;) { const x = out.lines.find(y => re.test(y.l)); if (x) return x.l; if (Date.now() - t0 > ms) throw new Error(tag + ': timeout waiting for ' + re); await sleep(50); } };
  return out;
}

let host = null, peer = null;
(async () => {
  spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
  await srv.start(0);
  const url = 'ws://127.0.0.1:' + srv.server.address().port + '/ws';

  // 0. the relay is unreachable: a clear error, no hang
  {
    const bad = runGodot('res://tests/net_host_test.gd', ['ws://127.0.0.1:9/ws'], 'bad');
    await bad.waitLine(/^ENDED /, 20000);
    const l = bad.lines.find(x => /^ENDED /.test(x.l)).l;
    console.log('unreachable relay -> ' + l);
    assert.match(l, /Could not reach the game server|did not answer/, 'clear error when the relay is unreachable');
    bad.p.kill();
  }

  host = runGodot('res://tests/net_host_test.gd', [url], 'host');
  const code = (await host.waitLine(/^HOSTED code=/, 30000)).split('=')[1];
  assert.match(code, /^[A-Z2-9]{5}$/, 'private room code');

  // web guest: join + hello
  const web = await new Client(url, 'WebGuest').open();
  await web.join(code); web.hello();
  const welcome = await web.wait(m => m.op === 'msg' && m.m.t === 'welcome', 5000);
  assert.equal(welcome.m.id, 1, 'web guest is slot 1'); assert.equal(welcome.m.proto, 1); assert.equal(welcome.m.name, 'Godot room');
  const roster1 = await web.wait(m => m.op === 'msg' && m.m.t === 'roster', 5000);
  assert.deepEqual(roster1.m.roster.map(r => r.name), ['GodotHost', 'WebGuest'], 'roster after the web guest');
  assert.equal(roster1.m.roster[0].cls, 'bruiser'); assert.equal(roster1.m.max, 4); assert.equal(roster1.m.lim, 1);
  { const l = await new Client(url, 'Lister').open(); l.tx({ op: 'list' }); const r = await l.wait(m => m.op === 'rooms'); assert.ok(!r.rooms.some(x => x.id === code), 'private room is not listed'); l.close(); }

  // Godot guest
  peer = runGodot('res://tests/net_host_peer.gd', [url, code], 'peer');
  const inbox = [];                                          // every room message the web guest gets: {at, m}
  web.ws.on('message', d => { let m; try { m = JSON.parse(d.toString()); } catch (e) { return; } if (m.op === 'msg') inbox.push({ at: Date.now(), m: m.m }); });
  const start = await web.wait(m => m.op === 'msg' && m.m.t === 'start', 40000);
  const tS = Date.now();
  const S0 = start.m;
  console.log('start: ' + JSON.stringify({ slots: S0.slots.map(s => s.kind + ':' + s.name), map: S0.map, limit: S0.limit, rules: S0.rules }));
  assert.deepEqual(S0.slots.map(s => s.kind), ['human', 'human', 'human', 'bot'], 'slots');
  assert.deepEqual(S0.slots.slice(0, 3).map(s => s.name), ['GodotHost', 'WebGuest', 'GodotPeer']);
  assert.ok(/^Bot /.test(S0.slots[3].name), 'the bot has its name');
  assert.equal(S0.slots[2].cls, 'kid', 'the Godot guest class');
  assert.equal(S0.map, 'arena'); assert.equal(S0.limit, 1);
  assert.equal(S0.rules.mode, 'classic'); assert.equal(S0.rules.hp, 200); assert.ok(Number.isInteger(S0.rules.dseed), 'dseed');
  assert.equal(S0.rules.dyn, 'off');

  // stream my own S: walking along x
  const r2 = v => +v.toFixed(2);
  let wx = -8, hpWeb = 200, sent = 0;
  const stream = setInterval(() => {
    const t = (Date.now() - tS) / 1000; const vx = t < 4 ? 3 : 0; wx = Math.min(4, -8 + 3 * Math.min(t, 4));
    // a second entry for slot 0 must be thrown away; the first one is stamped with my slot
    web.toHost({ t: 'S', l: [{ id: 0, x: r2(wx), y: 0, z: 6, vx, vy: 0, vz: 0, yaw: 1.57, ax: 0, ay: 0, az: 1, w: 'spatula', hp: hpWeb, d: 0, g: 1, sq: 0, iv: 0, lv: 0, el: 0 }, { id: 0, x: 0, y: 0, z: 0 }] });
    sent++;
  }, 1000 / 30);

  // the host's hit on me (slot 1) comes to me only
  const h1 = await web.wait(m => m.op === 'msg' && m.m.t === 'h', 15000);
  console.log('host hit: ' + JSON.stringify(h1.m));
  assert.ok(h1.m.to === 1 && h1.m.vs === 1 && h1.m.from === 0 && h1.m.d === 30, 'host h routed to its victim');
  hpWeb = 170;

  // forged messages: the host must drop them
  web.toHost({ t: 'pend', w: 1 });
  web.toHost({ t: 'start', slots: [], map: 'park' });
  web.toHost({ t: 'ko', from: 1, to: 0 });
  web.toHost({ t: 'h', to: 0, vs: 3, from: 0, d: 250, x: 0, y: 0, z: 1, f: 5, hd: 0 });
  web.toHost({ t: 'take', cid: 999 });
  web.toHost({ t: 'sw', id: 3, yaw: 0.5, w: 'spatula' });   // legit, but id is stamped to 1
  await sleep(1500);

  await peer.waitLine(/^HIT0 /, 15000);                       // the Godot guest has hit the host
  const tHit0 = Date.now();
  await sleep(800);
  // kill the host's bot (slot 3): `h` with to 0, until its `ko` comes back
  let ko = null;
  for (let i = 0; i < 20 && !ko; i++) {
    web.toHost({ t: 'h', to: 0, vs: 3, from: 1, d: 9999, x: 0, y: 0.2, z: 1, f: 5, hd: 0 });
    ko = await web.wait(m => m.op === 'msg' && m.m.t === 'ko' && m.m.to === 3, 600).catch(() => null);
  }
  assert.ok(ko && ko.m.from === 1, 'bot K.O. credited to the web guest: ' + JSON.stringify(ko && ko.m));
  const pend = await web.wait(m => m.op === 'msg' && m.m.t === 'pend', 5000);
  assert.equal(pend.m.w, 1, 'K.O. limit 1 reached: the web guest wins');
  web.toHost({ t: 'rv' });
  const rvs = await web.wait(m => m.op === 'msg' && m.m.t === 'rvs', 10000);
  console.log('rvs: ' + JSON.stringify(rvs.m));
  const start2 = await web.wait(m => m.op === 'msg' && m.m.t === 'start', 40000);
  assert.deepEqual(start2.m.slots.map(s => s.kind), ['human', 'human', 'human', 'bot'], 'rematch keeps the players');
  assert.notEqual(start2.m.rules.dseed, S0.rules.dseed, 'fresh arena seed for the rematch');
  clearInterval(stream);

  // what the web guest got during match 1
  const m1 = inbox.filter(x => x.at > tS + 1000 && x.at < tS + 4000);
  const hostS = m1.filter(x => x.m.t === 'S' && x.m.l.some(e => e.id === 0));
  const rate = hostS.length / 3;
  const ids = new Set(hostS.flatMap(x => x.m.l.map(e => e.id)));
  const peerS = m1.filter(x => x.m.t === 'S' && x.m.l.length === 1 && x.m.l[0].id === 2);
  const peerZ = inbox.filter(x => x.m.t === 'S' && x.m.l[0] && x.m.l[0].id === 2 && x.at < tS + 5000).map(x => x.m.l[0].z);
  const hostZ = hostS.map(x => x.m.l.find(e => e.id === 0).z);
  const hostHp = inbox.filter(x => x.m.t === 'S' && x.at > tHit0 + 300 && x.at < tHit0 + 800).map(x => (x.m.l.find(e => e.id === 0) || {}).hp).filter(v => v !== undefined);
  console.log(`host S ${rate.toFixed(1)} Hz ids ${[...ids]}; host walked ${(Math.max(...hostZ) - Math.min(...hostZ)).toFixed(1)} m; peer S ${(peerS.length / 3).toFixed(1)} Hz walked ${(Math.max(...peerZ) - Math.min(...peerZ)).toFixed(1)} m; host hp after peer hit ${hostHp.slice(0, 3)}`);
  assert.ok(rate >= 25 && rate <= 35, 'host S at ~30 Hz (' + rate + ')');
  assert.ok(ids.has(0) && ids.has(3) && !ids.has(1) && !ids.has(2), 'host S carries its own fighter and its bot');
  assert.ok(peerS.length >= 60, 'the Godot guest S is relayed to the web guest (' + peerS.length + ')');
  assert.ok(Math.max(...peerZ) - Math.min(...peerZ) > 3, 'the Godot guest walked');
  assert.ok(Math.max(...hostZ) - Math.min(...hostZ) > 3, 'the host walked');
  const hpL = host.lines.filter(x => /^HP /.test(x.l));
  const hpSeq = [...hpL.filter(x => x.at < tHit0 - 300).slice(-1), ...hpL.filter(x => x.at >= tHit0 - 300 && x.at < tHit0 + 1500)].map(x => +x.l.split(' ')[1]);
  const drops = hpSeq.slice(1).map((v, i) => +(hpSeq[i] - v).toFixed(2));
  console.log('host hp around the Godot guest hit: ' + hpSeq.join(' '));
  assert.ok(hostHp.length && drops.some(d => Math.abs(d - 11.04) < 0.1 || Math.abs(d - 5.52) < 0.1), 'the Godot guest hit (12 x Scamp 0.92, halved while knocked down) lowered the host hp: drops ' + drops);

  // the web guest leaves: its seat turns back into a bot for the others (after the guests have rebuilt the match)
  await sleep(1500);
  web.tx({ op: 'leave' });
  await web.wait(m => m.op === 'left', 5000).catch(() => null);
  web.close();

  const [ch, cp] = await Promise.all([Promise.race([host.exited, sleep(60000).then(() => 'hang')]), Promise.race([peer.exited, sleep(60000).then(() => 'hang')])]);
  if (ch === 'hang') host.p.kill(); if (cp === 'hang') peer.p.kill();
  const ht = host.lines.map(x => x.l), pt = peer.lines.map(x => x.l);
  console.log(ht.filter(l => /^(HOSTED|ROSTER|STARTING|START|HIT1|MATCH_OVER|VOTES|SENT|RECV|GUARDED|DONE|FAIL|ENDED)/.test(l)).map(l => 'host: ' + l).join('\n'));
  console.log(pt.filter(l => /^(WELCOMED|START|HIT0|MATCH_END|SLOT1|SENT|RECV|DONE|FAIL|ENDED)/.test(l)).map(l => 'peer: ' + l).join('\n'));
  const errs = [...ht, ...pt].filter(l => ERR.test(l));
  for (const l of errs) console.log('godot:', l);

  // on the host: the ghosts follow their owners
  const ghost = (lines, s) => lines.filter(x => new RegExp('^GHOST ' + s + ' ').test(x.l) && x.at > tS + 500 && x.at < tS + 5000).map(x => { const f = x.l.split(' '); return { x: +f[2], z: +f[4], hp: +f[5] }; });
  const g1 = ghost(host.lines, 1), g2 = ghost(host.lines, 2), p0 = ghost(peer.lines, 0), p3 = ghost(peer.lines, 3), p1 = ghost(peer.lines, 1);
  const span = (a, k) => a.length ? Math.max(...a.map(v => v[k])) - Math.min(...a.map(v => v[k])) : 0;
  console.log(`host sees web guest x span ${span(g1, 'x').toFixed(1)}, Godot guest z span ${span(g2, 'z').toFixed(1)}; peer sees host z span ${span(p0, 'z').toFixed(1)}, web guest x span ${span(p1, 'x').toFixed(1)}, bot samples ${p3.length}`);
  assert.ok(span(g1, 'x') > 6, 'web guest input moves its fighter on the host');
  assert.ok(span(g2, 'z') > 3, 'Godot guest input moves its fighter on the host');
  assert.ok(span(p0, 'z') > 3 && span(p1, 'x') > 6 && p3.length > 10, 'the Godot guest sees the host, the web guest (relayed) and the bot');
  assert.ok(ht.some(l => /^HIT1 applied=true/.test(l)), 'host hit sent');
  assert.ok(ht.some(l => /^MATCH_OVER w=1/.test(l)), 'host ended the match');
  assert.ok(ht.some(l => /^START n=2 slots=human,human,human,bot/.test(l)), 'host rematch');
  const gl = ht.find(l => /^GUARDED /.test(l)); const guarded = gl ? +gl.split(' ')[1] : 0;
  assert.ok(guarded >= 5, 'forged messages dropped by the guard (' + guarded + ')');
  assert.ok(pt.some(l => /^WELCOMED slot=2/.test(l)), 'Godot guest is slot 2');
  assert.ok(pt.some(l => /^START n=1 map=arena slots=4 my_slot=2 kinds=human,human,human,bot/.test(l)), 'Godot guest started');
  assert.ok(pt.some(l => /^HIT0 applied=true/.test(l)), 'Godot guest hit the host');
  assert.ok(pt.some(l => /^MATCH_END w=1/.test(l)), 'Godot guest got pend');
  assert.ok(pt.some(l => /^START n=2 /.test(l)), 'Godot guest got the rematch');
  assert.ok(pt.some(l => /^SLOT1 kind=bot/.test(l)), 'the web guest seat went back to a bot');
  assert.equal(errs.length, 0, 'no Godot errors');
  assert.equal(ch, 0, 'host exit code'); assert.equal(cp, 0, 'peer exit code');
  console.log('godot net host test passes');
  await srv.stop(); process.exit(0);
})().catch(async e => {
  for (const [n, o] of [['host', host], ['peer', peer]]) if (o) { console.log(o.lines.map(x => x.l).filter(l => !/^(GHOST|ME|BOT|SLOTS|HP) /.test(l)).slice(-40).map(l => n + ': ' + l).join('\n')); try { o.p.kill(); } catch (x) { /* x */ } }
  console.error('FAIL', e.message); try { await srv.stop(); } catch (x) { /* x */ } process.exit(1);
});
