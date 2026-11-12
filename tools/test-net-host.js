'use strict';
/* Cross-play host test (npm run test:godot-nethost):
   Godot hosts a private room on the real relay (REQUIRE_LOGIN=0). A Node guest (tools/wa-client.js) joins,
   gets welcome/roster/start, receives the host's `S` stream (player + bots), sends its own `S` and a scripted
   `h` at the host, then sees `pend`. Checks: create, hello→welcome (proto), start slots, host S ~30 Hz with
   bots, guest hit lowers host hp path (HIT_RECV), pend arrives, no Godot script errors. */
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const os = require('os');
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0';
process.env.DATA_DIR = os.tmpdir() + '/wa-nethost-' + process.pid;
const srv = require('../server');
const { Client, PROTO } = require('./wa-client');
const GODOT = process.env.GODOT || path.join(os.homedir(), 'godot', 'godot');
const DIR = path.join(__dirname, '..', 'godot');
const ERR = /SCRIPT ERROR|^ERROR|Parse Error|leaked/i;

const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });

  await srv.start(0);
  const url = 'ws://127.0.0.1:' + srv.server.address().port + '/ws';
  const lines = [];
  const marks = {};
  const p = spawn(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/net_host_test.gd', '--', url, '--no-save']);
  let buf = '';
  const onData = d => {
    buf += d.toString(); let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const l = buf.slice(0, i); buf = buf.slice(i + 1); lines.push({ at: Date.now(), l });
      const k = l.split(' ')[0]; if (!marks[k]) marks[k] = Date.now();
      if (/^(HOSTED|ROSTER|START|HIT_RECV|MATCH_END|DONE|FAIL|ENDED|STATUS)/.test(l)) console.log(l);
    }
  };
  p.stdout.on('data', onData); p.stderr.on('data', onData);
  const exited = new Promise(r => p.on('exit', r));

  // Wait until Godot has created the room, then join as a guest.
  const t0 = Date.now();
  while (!marks.HOSTED && Date.now() - t0 < 25000) await sleep(50);
  assert.ok(marks.HOSTED, 'Godot hosted a room');
  const hosted = lines.find(x => /^HOSTED code=/.test(x.l));
  const code = hosted.l.split('=')[1].trim();
  assert.ok(/^[A-Z0-9]{5}$/i.test(code), 'room code looks like a private code: ' + code);

  const guest = await new Client(url, 'NodeGuest').open();
  await guest.join(code);
  guest.hello();
  const welcome = await guest.wait(m => m.op === 'msg' && m.m && m.m.t === 'welcome', 15000);
  assert.equal(welcome.m.proto, PROTO, 'welcome carries proto');
  assert.equal(welcome.m.id, 1, 'guest is slot 1');
  const roster = await guest.wait(m => m.op === 'msg' && m.m && m.m.t === 'roster', 8000).catch(() => null);
  const start = await guest.wait(m => m.op === 'msg' && m.m && m.m.t === 'start', 20000);
  assert.ok(Array.isArray(start.m.slots) && start.m.slots.length >= 2, 'start has slots');
  assert.equal(start.m.slots[0].kind, 'human');
  assert.equal(start.m.slots[1].kind, 'human');
  assert.equal(start.m.map, 'arena');
  assert.equal(start.m.rules.mode, 'classic');

  const fromHost = [];
  guest.ws.on('message', d => {
    let m; try { m = JSON.parse(d.toString()); } catch (e) { return; }
    if (m.op === 'msg' && m.m) fromHost.push({ at: Date.now(), m: m.m });
  });

  // Stream guest state; after a bit, hit the host (slot 0).
  const tS = Date.now();
  const stream = setInterval(() => {
    const t = (Date.now() - tS) / 1000;
    guest.toHost({
      t: 'S', l: [{
        id: 1, x: +(3 * Math.cos(0.4 * t)).toFixed(2), y: 0, z: +(3 * Math.sin(0.4 * t)).toFixed(2),
        vx: 0, vy: 0, vz: 0, yaw: 0, ax: 0, ay: 0, az: 1, w: 'spatula', hp: 150, d: 0, g: 1, sq: 0, iv: 0, lv: 0, el: 0,
      }],
    });
  }, 1000 / 30);

  await sleep(2500);
  guest.toHost({ t: 'h', to: 0, vs: 0, from: 1, d: 25, x: 0, y: 0.2, z: 1, f: 4, hd: 0 });

  const pend = await guest.wait(m => m.op === 'msg' && m.m && m.m.t === 'pend', 20000).catch(() => null);
  clearInterval(stream);
  const codeExit = await Promise.race([exited, sleep(12000).then(() => 'hang')]);
  if (codeExit === 'hang') p.kill();
  guest.close();

  const text = lines.map(x => x.l);
  const errs = text.filter(l => ERR.test(l));
  for (const l of errs) console.log('godot:', l);

  const S = fromHost.filter(x => x.m.t === 'S' && x.at > tS + 500 && x.at < tS + 5500);
  const rate = S.length / 5;
  const hasBot = S.some(x => Array.isArray(x.m.l) && x.m.l.some(e => e.id === 2 || e.id === 3));
  const hostEntry = S.map(x => (x.m.l || []).find(e => e.id === 0)).filter(Boolean);
  const sane = hostEntry.every(e => Number.isFinite(e.x) && Number.isFinite(e.z) && e.hp > 0);
  console.log(`host S: ${rate.toFixed(1)} Hz, samples=${S.length}, bots_in_S=${hasBot}, host entries=${hostEntry.length}, pend=${!!pend}, roster=${!!roster}`);

  assert.ok(text.some(l => /^HOSTED code=/.test(l)), 'hosted');
  assert.ok(text.some(l => /^START map=arena/.test(l)), 'started');
  assert.ok(text.some(l => /^HIT_RECV /.test(l)), 'host applied guest hit');
  assert.ok(pend && pend.m.t === 'pend', 'guest saw pend');
  assert.ok(rate >= 20 && rate <= 40, 'host S near 30 Hz: ' + rate);
  assert.ok(hasBot, 'host S includes bot slots');
  assert.ok(sane && hostEntry.length > 10, 'host player S sane');
  assert.ok(!errs.length, 'no Godot errors');
  assert.ok(codeExit === 0, 'godot exit 0, got ' + codeExit);

  console.log('godot net host test passes');
  await srv.stop();
  process.exit(0);
})().catch(e => { console.error('FAIL', e && e.stack || e); process.exit(1); });
