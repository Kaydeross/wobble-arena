'use strict';
/* Godot menu flow test (npm run test:godot-flow): the real relay (REQUIRE_LOGIN=0) and godot/tests/flow_test.gd.
   The Godot side walks the first-run how-to, Title > Play > Wizard > Start, Title > Settings > every section > Back,
   Title > Play online > room browser (unreachable relay, empty list) and prints EMPTY_OK; this side then opens two
   public rooms (one on another game version) with the web-protocol client; Godot lists them, greys the old one out,
   taps the good one and prints JOINED; the host here must see the guest arrive (peer open). Then the pause flows.
   Needs Godot (GODOT env var or the macOS default). */
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const os = require('os');
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-flow-' + process.pid;
const srv = require('../server');
const { Client } = require('./wa-client');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const ERR = /SCRIPT ERROR|^ERROR|Parse Error/;
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });
  await srv.start(0);
  const url = 'ws://127.0.0.1:' + srv.server.address().port + '/ws';
  const g = spawn(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/flow_test.gd', '--', url, '--no-save']);
  const lines = [];
  let buf = '';
  const onData = d => { buf += d.toString(); let i; while ((i = buf.indexOf('\n')) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); lines.push(l); if (/^(FLOW|FAIL|EMPTY_OK|JOINED)|ERROR/.test(l)) console.log(l); } };
  g.stdout.on('data', onData); g.stderr.on('data', onData);
  const exited = new Promise(r => g.on('exit', c => r(c)));
  const waitLine = async (re, ms) => { const t0 = Date.now(); while (!lines.some(l => re.test(l))) { if (Date.now() - t0 > ms) throw new Error('timeout waiting for ' + re); await sleep(50); } };
  let host, old;
  try {
    await waitLine(/^EMPTY_OK/, 120000);
    host = await new Client(url, 'FlowHost').open();
    await host.create(true);
    old = await new Client(url, 'OldHost').open();
    old.tx({ op: 'create', pub: true, info: { name: 'Old Room', host: 'OldHost', mode: 'classic', modeName: 'Classic', map: 'Arena', max: 4, build: 'b70.0' } });
    await old.wait(m => m.op === 'created');
    await waitLine(/^JOINED/, 60000);
    const peer = await host.wait(m => m.op === 'peer' && m.ev === 'open', 5000);
    assert.ok(peer.cid > 0, 'the host sees the Godot guest join');
    const code = await Promise.race([exited, sleep(120000).then(() => 'timeout')]);
    const out = lines.join('\n');
    if (code !== 0 || !/^FLOW ok/m.test(out)) throw new Error('flow test failed (exit ' + code + ')');
    if (ERR.test(out)) throw new Error('script errors');
    console.log('godot flow test passes');
  } catch (e) {
    console.log(lines.filter(l => ERR.test(l)).slice(0, 20).join('\n'));
    console.error(e.message);
    process.exitCode = 1;
    g.kill();
  } finally {
    if (host) host.close();
    if (old) old.close();
    await srv.stop();
    // WebSocket close events can keep Node alive after every assertion has passed.
    process.exit(process.exitCode || 0);
  }
})();
