'use strict';
/* Integration test of the room server (layer 1). Starts a server on a random port and drives it with the protocol client. */
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0';
process.env.DATA_DIR = require('os').tmpdir() + '/wa-test-' + process.pid;
const srv = require('../server');
const accounts = require('../accounts');
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

  /* ---- room kind: the room list and a join-by-code carry "arcade-coop" vs "pvp" (docs/PROTOCOL.md 1.1, 1.2) ---- */
  { const k = await new Client(url, 'KindHost').open(); await k.op('hi');
    k.tx({ op: 'create', pub: true, info: { name: 'Arcade Test', mode: 'construction', modeName: 'Construction', map: 'Building Site', arcade: true, max: 2 } });
    const cr = await k.wait(m => m.op === 'created');
    h.tx({ op: 'list' }); const l = await h.wait(m => m.op === 'rooms');
    const row = l.rooms.find(r => r.id === cr.id);
    assert.ok(row && row.arcade === true && row.kind === 'arcade-coop' && row.kindName === 'Arcade co-op', 'the room list carries the room kind: ' + JSON.stringify(row));
    const j = await new Client(url, 'WrongKind').open(); await j.op('hi');
    j.tx({ op: 'join', id: cr.id, kind: 'pvp' }); const nj = await j.wait(m => m.op === 'nojoin');
    assert.equal(nj.reason, 'kind', 'a kind mismatch is refused'); assert.equal(nj.kind, 'arcade-coop');
    j.tx({ op: 'join', id: 'ZZZZZ' }); const nn = await j.wait(m => m.op === 'nojoin');
    assert.equal(nn.reason, 'none', 'an unknown code is a different failure from a kind mismatch');
    j.tx({ op: 'join', id: cr.id, kind: 'arcade-coop' }); const jj = await j.wait(m => m.op === 'joined');
    assert.equal(jj.kind, 'arcade-coop', 'the joined reply carries the kind'); assert.equal(jj.arcade, true);
    j.tx({ op: 'leave' }); await j.op('left'); j.close(); k.close();
    // a normal room stays pvp, even if a client tries to claim arcade with a classic mode
    const n = await new Client(url, 'PvpHost').open(); await n.op('hi');
    n.tx({ op: 'create', pub: true, info: { name: 'PvP Test', mode: 'classic', arcade: true } });
    const nc = await n.wait(m => m.op === 'created');
    h.tx({ op: 'list' }); const l2 = await h.wait(m => m.op === 'rooms');
    const nrow = l2.rooms.find(r => r.id === nc.id);
    assert.ok(nrow && nrow.kind === 'pvp' && nrow.arcade === false, 'a classic room can not be labelled Arcade: ' + JSON.stringify(nrow));
    n.close();
  }

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
    assert.equal((await api('POST', '/api/claim', { name: 'N1gg3r' })).status, 400, 'blocked display names are refused');
    assert.equal((await api('POST', '/api/signup', { username: 'PICKLE_7', email: 'p@example.com', password: 'secret1' })).status, 409, 'sign-up respects claimed names');
    const me = await api('GET', '/api/me', null, c1.token); assert.ok(me.ok && me.hasPassword === false);
    assert.equal((await api('POST', '/api/login', { id: 'Pickle_7', password: 'anything' })).status, 401, 'a name-only account cannot log in with a password');
    assert.equal((await api('POST', '/api/password', { old: '', next: 'secret1' }, c1.token)).err, 'nopass');
    assert.equal((await api('POST', '/api/protect', { password: 'abc' }, c1.token)).err, 'password', 'protect needs a 6+ character password');
    assert.equal((await api('POST', '/api/protect', { password: 'secret1' })).status, 401, 'protect needs a login');
    const pr = await api('POST', '/api/protect', { password: 'secret1' }, c1.token);
    assert.ok(pr.ok && /^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$/.test(pr.recovery) && pr.user.hasPassword, 'protect sets a password and gives a recovery code');
    assert.equal((await api('POST', '/api/protect', { password: 'secret2' }, c1.token)).status, 409, 'protect is only for name-only accounts');
    const rep = await api('POST', '/api/report', { target: 'Rude_Randy', room: 'ABCDE', reason: 'harassment', details: 'test report' }, c1.token);
    assert.ok(rep.ok && /^[0-9a-f]{16}$/.test(rep.id), 'an authenticated player can submit a safety report');
    assert.equal((await api('POST', '/api/report', { target: 'Another', room: 'ABCDE', reason: 'spam' }, c1.token)).status, 429, 'reports are rate limited');
    const li = await api('POST', '/api/login', { id: 'pickle_7', password: 'secret1' }); assert.ok(li.ok && li.user.username === 'Pickle_7', 'protected name logs in on another device');
    assert.equal((await api('POST', '/api/save', { data: {} }, c1.token)).status, 404);
    assert.ok((await api('PUT', '/api/save', { data: { wallet: { coins: 5 } } }, c1.token)).ok);
    const c2 = await api('POST', '/api/claim', { name: 'Plain_Pat', data: { wallet: { coins: 9 } } }); assert.equal(c2.t > 0, true, 'claim can carry the guest progress');
    assert.ok((await api('POST', '/api/delete', {}, c2.token)).ok, 'a name-only account can be deleted without a password');
    assert.ok((await api('POST', '/api/claim', { name: 'plain_pat' })).ok, 'a deleted name is free again');

    // Changing a password or resetting it revokes every old session and returns one fresh token.
    const r0 = await api('POST', '/api/claim', { name: 'Revoke_Rita' });
    const rp = await api('POST', '/api/protect', { password: 'first-pass1' }, r0.token);
    const r1 = await api('POST', '/api/login', { id: 'Revoke_Rita', password: 'first-pass1' });
    const rp2 = await api('POST', '/api/password', { old: 'first-pass1', next: 'second-pass2' }, r1.token);
    assert.ok(rp2.ok && /^[0-9a-f]{64}$/.test(rp2.token), 'changing the password returns a replacement session');
    assert.equal((await api('GET', '/api/me', null, r0.token)).status, 401, 'password change revokes older sessions');
    assert.equal((await api('GET', '/api/me', null, r1.token)).status, 401, 'password change revokes the session that made it');
    assert.equal((await api('GET', '/api/me', null, rp2.token)).status, 200, 'the replacement session works');
    const rr = await api('POST', '/api/reset', { id: 'Revoke_Rita', code: rp.recovery, password: 'third-pass3' });
    assert.ok(rr.ok && /^[0-9a-f]{64}$/.test(rr.token), 'reset returns a fresh session');
    assert.equal((await api('GET', '/api/me', null, rp2.token)).status, 401, 'reset revokes every old session');
    assert.equal((await api('GET', '/api/me', null, rr.token)).status, 200, 'the reset session works');
    const rd1 = await api('POST', '/api/login', { id: 'Revoke_Rita', password: 'third-pass3' });
    const rd2 = await api('POST', '/api/login', { id: 'Revoke_Rita', password: 'third-pass3' });
    assert.ok((await api('POST', '/api/delete', { password: 'third-pass3' }, rd1.token)).ok);
    assert.equal((await api('GET', '/api/me', null, rr.token)).status, 401, 'delete revokes all sessions, including another device');
    assert.equal((await api('GET', '/api/me', null, rd2.token)).status, 401, 'delete revokes every token');

    // Cloud timestamps are 64-bit in JavaScript terms: a 32-bit cast must not let an older save overwrite a newer one.
    const ts = await api('POST', '/api/claim', { name: 'Timestamp_Tess', data: { x: 2 } });
    await A.store.set('data:timestamp_tess', JSON.stringify({ t: 2147483650, d: { x: 2 } }));
    const staleTs = await api('PUT', '/api/save', { data: { x: 1 }, base: 2147483647 }, ts.token);
    assert.equal(staleTs.err, 'stale', 'save conflict comparison does not truncate the timestamp to 32 bits');

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
    delete process.env.ACCOUNT_TTL_DAYS; const safe = await A.sweep(); assert.equal(safe.erased, 0, 'idle account deletion is off by default');
    process.env.ACCOUNT_TTL_DAYS = '30'; const sw = await A.sweep(); assert.equal(sw.erased, 2, 'an explicit 30-day TTL erases exactly the two old accounts (counts only)');
    assert.equal(await A.store.get('user:old_olly'), null); assert.equal(await A.store.get('data:old_olly'), null, 'the save is erased'); assert.equal(await A.store.get('email:mo@example.com'), null, 'the email is freed');
    assert.equal(await A.who(old.token), null, 'its token is gone'); assert.equal(await A.store.get('tok:' + old.token), null);
    assert.ok(await rec('Fresh_Fay') && await A.who(fresh.token), 'a 29-day-old account is kept');
    assert.ok((await api('POST', '/api/claim', { name: 'old_olly' })).ok, 'the freed name can be picked by someone else'); assert.ok((await api('POST', '/api/signup', { username: 'Mail_Two', email: 'MO@example.com', password: 'secret1' })).ok, 'and so can the email');
    // accounts made before lastSeen: not erased by the upgrade, they get lastSeen = now
    await A.store.set('user:legacy_lou', JSON.stringify({ u: 'Legacy_Lou', e: 'lou@example.com', p: 'x', r: 'x', c: Date.now() - 400 * DAY, l: Date.now() - 200 * DAY }));
    const mg = await A.sweep(); assert.equal(mg.migrated, 1); const lou = await rec('Legacy_Lou'); assert.ok(lou && Math.abs(lou.s - Date.now()) < 5000, 'legacy account got lastSeen = now');
    assert.equal((await A.sweep()).erased, 0, 'and survives the next sweep'); delete process.env.ACCOUNT_TTL_DAYS;

    /* ---- ranking: GET /api/rank and the authenticated, validated, rate-limited POST /api/rank ---- */
    const rk = ['Rank_Rae', 'Rank_Rob', 'Rank_Rin'];
    const rt = [];
    for (const n of rk) rt.push(await api('POST', '/api/claim', { name: n }));
    assert.ok(rt.every(r => r.ok), 'ranking test accounts');
    const rank = (tok, body) => api('POST', '/api/rank', body, tok);
    const ranks = (q, tok) => api('GET', '/api/rank' + (q || ''), null, tok);
    const sub1 = await rank(rt[0].token, { kos: 40, wins: 7, matches: 12, arcade_best: 3, arcade_diff: 'normal' });
    assert.ok(sub1.ok && sub1.board === 'kos' && sub1.entries[0].name === 'Rank_Rae' && sub1.entries[0].rank === 1 && sub1.you.rank === 1, 'rank submit: ' + JSON.stringify(sub1));
    assert.ok(sub1.stats && sub1.stats.kos === 40 && sub1.stats.arcade.normal === 3, 'the reply carries the stored bests');
    await rank(rt[1].token, { kos: 90, wins: 12, matches: 20, board: 'wins' });
    await rank(rt[2].token, { kos: 10, board: 'kos' });
    const top = await ranks('?board=kos&limit=2');
    assert.ok(top.ok && top.board === 'kos' && top.entries.length === 2, 'GET /api/rank: ' + JSON.stringify(top));
    assert.equal(top.entries[0].name, 'Rank_Rob'); assert.equal(top.entries[0].score, 90); assert.equal(top.entries[0].rank, 1);
    assert.equal(top.entries[1].name, 'Rank_Rae'); assert.equal(top.entries[1].rank, 2);
    assert.ok(top.entries[0].updated > 0, 'each entry carries its updated time');
    const allKos = await ranks('?board=kos&limit=99');
    assert.deepEqual(allKos.entries.map(e => e.name), ['Rank_Rob', 'Rank_Rae', 'Rank_Rin'], 'ordering is score, descending');
    assert.equal(allKos.entries.length, 3);
    const lower = await rank(rt[1].token, { kos: 5, wins: 1, matches: 1 });
    assert.ok(lower.ok && lower.stats.kos === 90 && lower.stats.wins === 12 && lower.stats.matches === 20, 'monotonic: a lower submit leaves the bests alone');
    assert.equal((await ranks('?board=kos')).entries.find(e => e.name === 'Rank_Rob').score, 90, 'the board kept the higher score');
    const arc = await rank(rt[0].token, { arcade_best: 2, arcade_diff: 'nightmare', board: 'arcade' });
    assert.ok(arc.ok && arc.entries[0].name === 'Rank_Rae' && arc.entries[0].score === 6, 'the Arcade score weights the difficulty (2 x nightmare = 6): ' + JSON.stringify(arc.entries));
    await rank(rt[1].token, { arcade_best: 5, arcade_diff: 'easy', board: 'arcade' });
    await rank(rt[2].token, { arcade_best: 3, arcade_diff: 'normal', board: 'arcade' });
    const arcTop = await ranks('?board=arcade');
    assert.deepEqual(arcTop.entries.map(e => e.name), ['Rank_Rae', 'Rank_Rin', 'Rank_Rob'], 'Arcade ordering: ' + JSON.stringify(arcTop.entries));
    assert.deepEqual(arcTop.entries.map(e => e.score), [6, 6, 5]);
    const myRow = await ranks('?board=kos&limit=1', rt[2].token);
    assert.ok(myRow.you && myRow.you.score === 10 && myRow.you.rank === 3, 'a signed-in GET also gets `you`: ' + JSON.stringify(myRow.you));
    const meIn = await ranks('?board=wins', rt[1].token);
    assert.ok(meIn.entries[0].me === true, 'the signed-in player’s row is marked');
    // validation: every number finite, whole and inside its cap; unknown board/difficulty are refused
    for (const body of [{ kos: -1 }, { kos: 1.5 }, { kos: '12' }, { kos: 1e12 }, { wins: null }, { arcade_best: 7 }, { arcade_best: 2, arcade_diff: 'insane' }, {}])
      assert.equal((await rank(rt[0].token, body)).status, 400, 'refused: ' + JSON.stringify(body));
    assert.equal((await rank(rt[0].token, { kos: 1 })).ok, true, 'a rejected body does not use the rate budget');
    assert.equal((await rank('', { kos: 1 })).status, 401, 'ranking needs a login');
    assert.equal((await rank('ab'.repeat(32), { kos: 1 })).status, 401, 'a bogus token is refused');
    assert.equal((await ranks('?board=nope')).status, 400, 'an unknown board is refused');
    assert.equal((await ranks('')).entries.length, 3, 'the board defaults to kos');
    // rate limit: 6 updates per 10 s per account
    const rick = await api('POST', '/api/claim', { name: 'Rate_Rick' });
    for (let i = 0; i < 6; i++) assert.ok((await rank(rick.token, { kos: i + 1 })).ok, 'rank update ' + i + ' inside the window');
    assert.equal((await rank(rick.token, { kos: 7 })).status, 429, 'ranking updates are rate limited');
    assert.equal((await ranks('?board=kos')).entries.find(e => e.name === 'Rate_Rick').score, 6, 'the rate-limited 7th update never reached the board');
  }

  /* ---- the same ranking code paths on the Upstash store: a fake REST endpoint over a Map ---- */
  {
    const mem = new Map(), realFetch = global.fetch;
    global.fetch = async (_url, opt) => {
      let out = null, err = '';
      try {
        const a = JSON.parse(opt.body), c = String(a[0]).toUpperCase();
        if (c === 'GET') out = mem.has(a[1]) ? mem.get(a[1]) : null;
        else if (c === 'SET') { if (a.includes('NX') && mem.has(a[1])) out = null; else { mem.set(a[1], a[2]); out = 'OK'; } }
        else if (c === 'DEL') { mem.delete(a[1]); out = 1; }
        else if (c === 'SCAN') { const m = a[a.indexOf('MATCH') + 1] || '*', pre = m.endsWith('*') ? m.slice(0, -1) : m; out = ['0', [...mem.keys()].filter(k => k.startsWith(pre))]; }
        else err = 'unknown command ' + c;
      } catch (e) { err = e.message; }
      return { ok: !err, json: async () => (err ? { error: err } : { result: out }) };
    };
    try {
      const up = accounts.upstashStore('https://fake.invalid', 'token');
      const AU = accounts.create(up);
      const kim = await AU.routes.claim({ name: 'Cloud_Kim' }, { ip: '9.9.9.9' });
      assert.ok(kim.ok && /^[0-9a-f]{64}$/.test(kim.token), 'claim on the Upstash path');
      const s1 = await AU.routes.rankSubmit({ kos: 21, wins: 3, board: 'kos' }, { token: kim.token });
      assert.ok(s1.ok && s1.entries[0].name === 'Cloud_Kim' && s1.entries[0].score === 21, 'rank submit on the Upstash path: ' + JSON.stringify(s1));
      const l1 = await AU.routes.rankList({ board: 'kos' }, {});
      assert.ok(l1.ok && l1.entries.length === 1 && l1.entries[0].score === 21 && l1.entries[0].rank === 1, 'rank list on the Upstash path');
      let badBoard = null; try { await AU.routes.rankList({ board: 'bogus' }, {}); } catch (e) { badBoard = e; }
      assert.equal(badBoard && badBoard.status, 400, 'the same validation on the Upstash path');
      console.log('ranking Upstash path: ok');
    } finally { global.fetch = realFetch; }
  }
  [g1, g2, ...full].forEach(c => c.close());
  console.log('server integration tests pass'); await srv.stop(); process.exit(0);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
