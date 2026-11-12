'use strict';
/* Integration test of the room server (layer 1). Starts a server on a random port and drives it with the protocol client. */
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0';
process.env.DATA_DIR = require('os').tmpdir() + '/wa-test-' + process.pid;
const srv = require('../server');
const { Client } = require('./wa-client');
(async () => {
  await srv.start(0);
  const url = 'ws://127.0.0.1:' + srv.server.address().port + '/ws';
  const [h, g1, g2] = await Promise.all(['Host', 'G1', 'G2'].map(n => new Client(url, n).open()));
  await Promise.all([h, g1, g2].map(c => c.op('hi')));

  const id = await h.create(false);
  assert.match(id, /^[A-Z2-9]{5}$/, 'private room code');
  await g1.join(id.toLowerCase());                                  // codes are case-insensitive
  assert.equal((await h.op('peer')).ev, 'open');
  g1.hello();
  const hello = await h.wait(m => m.op === 'msg' && m.m.t === 'hello');
  assert.equal(hello.from, g1.cid); assert.equal(hello.m.proto, 1);
  h.to(g1.cid, { t: 'welcome', id: 1, name: 'r', proto: 1 });
  assert.equal((await g1.wait(m => m.op === 'msg')).m.t, 'welcome');

  await g2.join(id); await h.op('peer');
  h.toAll({ t: 'roster', roster: [] }, g1.cid);                     // except g1
  assert.equal((await g2.wait(m => m.op === 'msg')).m.t, 'roster');
  assert.ok(!g1.inbox.some(m => m.op === 'msg'), 'except was honoured');

  g1.toAll({ t: 'pend', w: 1 });                                    // guests can not broadcast
  g2.toHost({ t: 's', id: 2, x: 1 });
  assert.equal((await h.wait(m => m.op === 'msg')).from, g2.cid, 'server stamps the guest cid');
  assert.ok(!g2.inbox.some(m => m.op === 'msg'), 'guest broadcast ignored');

  const pubId = await (async () => { const p = await new Client(url, 'Pub').open(); const i = await p.create(true); h.tx({ op: 'list' }); const l = await h.wait(m => m.op === 'rooms'); assert.ok(l.rooms.some(r => r.id === i && r.pub), 'public room listed'); assert.ok(!l.rooms.some(r => r.id === id), 'private room hidden'); p.close(); return i; })();

  h.close();                                                         // host leaves: longest-standing guest is promoted, the other re-joins
  assert.equal((await g1.op('promoted')).id, id);
  assert.equal((await g2.op('rehost')).id, id);
  assert.equal((await g1.wait(m => m.op === 'peer')).ev, 'open');

  g2.tx({ op: 'join', id }); assert.equal((await g2.op('nojoin')).reason, 'inroom');
  const full = await Promise.all([1, 2, 3].map(() => new Client(url, 'X').open()));
  await full[0].join(id); await full[1].join(id);
  full[2].tx({ op: 'join', id }); assert.equal((await full[2].op('nojoin')).reason, 'full', 'room of 4 is full');

  [g1, g2, ...full].forEach(c => c.close());
  console.log('server integration tests pass'); await srv.stop(); process.exit(0);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
