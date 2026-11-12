'use strict';
/* Cross-client test: a Node host bot opens a room, the Godot client joins it headless and must receive `welcome`. Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot */
const { spawn } = require('child_process');
const path = require('path');
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = require('os').tmpdir() + '/wa-godot-' + process.pid;
const srv = require('../server');
const { Client } = require('./wa-client');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
(async () => {
  await srv.start(0);
  const url = 'ws://127.0.0.1:' + srv.server.address().port + '/ws';
  const host = await new Client(url, 'NodeHost').open();
  const id = await host.create(false);
  const out = []; const p = spawn(GODOT, ['--headless', '--path', path.join(__dirname, '..', 'godot'), '--script', 'res://tests/join_test.gd', '--', url, id]);
  p.stdout.on('data', d => out.push(d.toString())); p.stderr.on('data', d => out.push(d.toString()));
  const exited = new Promise(r => p.on('exit', r));
  const hello = await host.wait(m => m.op === 'msg' && m.m.t === 'hello', 20000);
  assert.equal(hello.m.proto, 1, 'hello carries proto'); assert.equal(hello.m.name, 'GodotBot');
  host.to(hello.from, { t: 'welcome', id: 1, name: 'NodeHost room', proto: 1 });
  const code = await exited;
  console.log(out.join('').split('\n').filter(l => /WELCOMED|FAIL|ERROR/.test(l)).join('\n'));
  assert.equal(code, 0, 'godot exit code');
  console.log('godot join test passes'); host.close(); await srv.stop(); process.exit(0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
