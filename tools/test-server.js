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

  { const odd = await new Client(url, 'Odd').open(); odd.tx({ op: 'join', id, build: 'b999.0' }); const j = await odd.wait(m => m.op === 'joined' || m.op === 'nojoin'); assert.equal(j.op, 'joined', 'a different build number can still join (the host checks proto)'); odd.tx({ op: 'leave' }); await odd.op('left'); odd.close(); await h.wait(m => m.op === 'peer' && m.ev === 'open'); await h.wait(m => m.op === 'peer' && m.ev === 'close'); }
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

  { const mk = (h, a) => ({ headers: h, socket: { remoteAddress: a } }), spoof = { 'x-forwarded-for': '6.6.6.6, 9.9.9.9', 'cf-connecting-ip': '1.2.3.4' };   // client-supplied header first, proxy-appended last
    delete process.env.TRUST_PROXY; assert.equal(srv.ipOf(mk(spoof, '10.0.0.2')), '10.0.0.2', 'proxy headers ignored by default (limits cannot be spoofed)');
    process.env.TRUST_PROXY = '1'; assert.equal(srv.ipOf(mk(spoof, '10.0.0.2')), '9.9.9.9', 'TRUST_PROXY=1 uses the last x-forwarded-for entry, not the spoofable first one'); assert.equal(srv.ipOf(mk({}, '10.0.0.2')), '10.0.0.2', 'no header falls back to the socket');
    process.env.TRUST_PROXY = 'cloudflare'; assert.equal(srv.ipOf(mk(spoof, '10.0.0.2')), '1.2.3.4', 'cloudflare mode uses cf-connecting-ip'); assert.equal(srv.ipOf(mk({ 'x-forwarded-for': '7.7.7.7' }, '10.0.0.2')), '7.7.7.7');
    delete process.env.TRUST_PROXY; }

  /* ---- accounts: claim a name, protect it, lastSeen, the 30-day sweep ---- */
  { const base = 'http://127.0.0.1:' + srv.server.address().port, A = srv.accounts, DAY = 86400000;
    const api = async (m, p, body, tok) => { const r = await fetch(base + p, { method: m, headers: Object.assign({ 'content-type': 'application/json' }, tok ? { authorization: 'Bearer ' + tok } : {}), body: body ? JSON.stringify(body) : undefined }); return Object.assign({ status: r.status }, await r.json()); };
    const rec = async n => JSON.parse(await A.store.get('user:' + n.toLowerCase()));
    const put = async (n, f) => { const u = await rec(n); f(u); await A.store.set('user:' + n.toLowerCase(), JSON.stringify(u)); };
    const c1 = await api('POST', '/api/claim', { name: 'Pickle_7' });
    assert.ok(c1.ok && /^[0-9a-f]{64}$/.test(c1.token) && c1.user.username === 'Pickle_7' && c1.user.hasPassword === false && !c1.recovery, 'claim returns a token and a password-less user');
    assert.equal((await api('POST', '/api/claim', { name: 'pickle_7' })).status, 409, 'a name is unique, case-insensitively');
    assert.equal((await api('POST', '/api/claim', { name: 'PICKLE_7' })).err, 'username');
    assert.equal((await api('POST', '/api/claim', { name: 'ab' })).status, 400, 'name rules are the same as sign-up');
    assert.equal((await api('POST', '/api/claim', { name: 'Admin' })).status, 400, 'reserved names are refused');
    assert.equal((await api('POST', '/api/signup', { username: 'PICKLE_7', email: 'p@example.com', password: 'secret1' })).status, 409, 'sign-up respects claimed names');
    const me = await api('GET', '/api/me', null, c1.token); assert.ok(me.ok && me.hasPassword === false);
    assert.equal((await api('POST', '/api/login', { id: 'Pickle_7', password: 'anything' })).status, 401, 'a name-only account cannot log in with a password');
    assert.equal((await api('POST', '/api/password', { old: '', next: 'secret1' }, c1.token)).err, 'nopass');
    assert.equal((await api('POST', '/api/protect', { password: 'abc' }, c1.token)).err, 'password', 'protect needs a 6+ character password');
    assert.equal((await api('POST', '/api/protect', { password: 'secret1' })).status, 401, 'protect needs a login');
    const pr = await api('POST', '/api/protect', { password: 'secret1' }, c1.token);
    assert.ok(pr.ok && /^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$/.test(pr.recovery) && pr.user.hasPassword, 'protect sets a password and gives a recovery code');
    assert.equal((await api('POST', '/api/protect', { password: 'secret2' }, c1.token)).status, 409, 'protect is only for name-only accounts');
    const li = await api('POST', '/api/login', { id: 'pickle_7', password: 'secret1' }); assert.ok(li.ok && li.user.username === 'Pickle_7', 'protected name logs in on another device');
    assert.equal((await api('POST', '/api/save', { data: {} }, c1.token)).status, 404);
    assert.ok((await api('PUT', '/api/save', { data: { wallet: { coins: 5 } } }, c1.token)).ok);
    const c2 = await api('POST', '/api/claim', { name: 'Plain_Pat', data: { wallet: { coins: 9 } } }); assert.equal(c2.t > 0, true, 'claim can carry the guest progress');
    assert.ok((await api('POST', '/api/delete', {}, c2.token)).ok, 'a name-only account can be deleted without a password');
    assert.ok((await api('POST', '/api/claim', { name: 'plain_pat' })).ok, 'a deleted name is free again');

    // lastSeen: written on use, but at most once an hour
    const c3 = await api('POST', '/api/claim', { name: 'Seen_Sam' });
    await put('Seen_Sam', u => { u.s = Date.now() - 2 * 3600000; });
    const s0 = (await rec('Seen_Sam')).s; await api('GET', '/api/me', null, c3.token); const s1 = (await rec('Seen_Sam')).s;
    assert.ok(s1 > s0 + 3600000, 'a visit after more than an hour updates lastSeen');
    await new Promise(r => setTimeout(r, 15)); await api('GET', '/api/me', null, c3.token); await api('PUT', '/api/save', { data: { a: 1 } }, c3.token); assert.equal((await rec('Seen_Sam')).s, s1, 'further calls within the hour do not rewrite it');
    await put('Seen_Sam', u => { u.s = Date.now() - 2 * 3600000; }); const s2 = (await rec('Seen_Sam')).s; assert.ok(await A.who(c3.token)); assert.ok((await rec('Seen_Sam')).s > s2 + 3600000, 'the relay auth op (who) counts as a visit');

    // sweep: 31 days gone, 29 days kept; tokens and saves go with the name
    const old = await api('POST', '/api/claim', { name: 'Old_Olly', data: { x: 1 } }), fresh = await api('POST', '/api/claim', { name: 'Fresh_Fay', data: { x: 1 } });
    const em = await api('POST', '/api/signup', { username: 'Mail_Mo', email: 'mo@example.com', password: 'secret1' });
    await put('Old_Olly', u => { u.s = Date.now() - 31 * DAY; }); await put('Fresh_Fay', u => { u.s = Date.now() - 29 * DAY; }); await put('Mail_Mo', u => { u.s = Date.now() - 40 * DAY; });
    process.env.ACCOUNT_TTL_DAYS = '0'; const off = await A.sweep(); assert.equal(off.erased, 0, 'ACCOUNT_TTL_DAYS=0 disables the sweep'); assert.ok(await rec('Old_Olly'));
    delete process.env.ACCOUNT_TTL_DAYS; const sw = await A.sweep(); assert.equal(sw.erased, 2, 'the sweep erased exactly the two accounts unused for 31 and 40 days (counts only)');
    assert.equal(await A.store.get('user:old_olly'), null); assert.equal(await A.store.get('data:old_olly'), null, 'the save is erased'); assert.equal(await A.store.get('email:mo@example.com'), null, 'the email is freed');
    assert.equal(await A.who(old.token), null, 'its token is gone'); assert.equal(await A.store.get('tok:' + old.token), null);
    assert.ok(await rec('Fresh_Fay') && await A.who(fresh.token), 'a 29-day-old account is kept');
    assert.ok((await api('POST', '/api/claim', { name: 'old_olly' })).ok, 'the freed name can be picked by someone else'); assert.ok((await api('POST', '/api/signup', { username: 'Mail_Two', email: 'MO@example.com', password: 'secret1' })).ok, 'and so can the email');
    // accounts made before lastSeen: not erased by the upgrade, they get lastSeen = now
    await A.store.set('user:legacy_lou', JSON.stringify({ u: 'Legacy_Lou', e: 'lou@example.com', p: 'x', r: 'x', c: Date.now() - 400 * DAY, l: Date.now() - 200 * DAY }));
    const mg = await A.sweep(); assert.equal(mg.migrated, 1); const lou = await rec('Legacy_Lou'); assert.ok(lou && Math.abs(lou.s - Date.now()) < 5000, 'legacy account got lastSeen = now');
    assert.equal((await A.sweep()).erased, 0, 'and survives the next sweep'); }
  [g1, g2, ...full].forEach(c => c.close());
  console.log('server integration tests pass'); await srv.stop(); process.exit(0);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
