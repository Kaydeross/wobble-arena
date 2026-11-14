'use strict';
/* Godot leaderboard client + server end-to-end test (npm run test:godot-ranking; the package.json script already is
   "test:godot-ranking": "node tools/test-ranking.js").
   Part 1, the REAL server (`server.js`, temp DATA_DIR, random port) over the REST API: create/sign up accounts, POST
   /api/rank, read the boards back, assert ordering / `you` / 401 / stats validation, and that an unknown /api/* route
   answers JSON 404 "Not found." (never the static-file text). Two fake "old server" endpoints answer /api/rank the way
   an older build does (plain-text 404) and the way the new server's guard does (JSON 404).
   Part 2, `godot/tests/ranking_test.gd` headless: server identity + every RankingSheet state (no network), then with
   --api/--token the real board read, the "you below the top N" record, the client helper's Sync (POST /api/rank via
   AccountApi), the plain-text-404 / JSON-404 unsupported states and the offline state. The runner reads the server
   back after Godot exits to prove the client's Sync reached it.
   Needs Godot (GODOT env var or the macOS default). */
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');
const http = require('http');
const assert = require('assert');

process.env.REQUIRE_LOGIN = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'wa-rank-'));
const srv = require('../server');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');

const listen = handler => new Promise(res => {
  const s = http.createServer(handler);
  s.listen(0, '127.0.0.1', () => res({ server: s, base: 'http://127.0.0.1:' + s.address().port }));
});
const closeAll = (...servers) => Promise.all(servers.map(s => new Promise(r => s.close(r))));

async function godotTest(args) {
  return new Promise(res => {
    const p = spawn(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/ranking_test.gd', '--', '--no-save', ...args]);
    let o = '';
    p.stdout.on('data', d => { o += d; });
    p.stderr.on('data', d => { o += d; });
    const tm = setTimeout(() => p.kill(), 300000);
    p.on('close', c => { clearTimeout(tm); res({ status: c, stdout: o }); });
  });
}

(async () => {
  // registers class_name scripts (ServerInfo, ServerBadge, RankingSheet, AccountApi) and their .uid files
  spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });

  // fake old servers: an older server.js lets /api/rank fall through to its static-file handler (plain-text "not found");
  // a server that has the JSON 404 guard but not the rank route answers {ok:false, err:"none"}. Both read as "too old".
  const oldText = await listen((req, res) => { res.writeHead(404, { 'content-type': 'text/plain' }); res.end('not found'); });
  const oldJson = await listen((req, res) => { res.writeHead(404, { 'content-type': 'application/json' }); res.end(JSON.stringify({ ok: false, err: 'none', msg: 'Not found.' })); });

  await srv.start(0);
  const base = 'http://127.0.0.1:' + srv.server.address().port;
  const api = async (method, p, body, token) => {
    const r = await fetch(base + p, { method, headers: Object.assign({ 'content-type': 'application/json' }, token ? { authorization: 'Bearer ' + token } : {}), body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await r.text();
    let data = null; try { data = JSON.parse(text); } catch (e) { /* not JSON */ }
    return { status: r.status, type: String(r.headers.get('content-type') || ''), text, data: data || {} };
  };
  const rank = (body, tok) => api('POST', '/api/rank', body, tok);
  const board = (q, tok) => api('GET', '/api/rank' + q, undefined, tok);

  // ---- REST: sign up / sign in, POST the scores, read them back
  const A = await api('POST', '/api/signup', { username: 'Live_Ace', email: 'live_ace@example.com', password: 'secret1' });
  assert.ok(A.data.ok && /^[0-9a-f]{64}$/.test(A.data.token), 'sign-up A: ' + A.text);
  const B = await api('POST', '/api/signup', { username: 'Live_Bo', email: 'live_bo@example.com', password: 'secret1' });
  assert.ok(B.data.ok && /^[0-9a-f]{64}$/.test(B.data.token), 'sign-up B: ' + B.text);
  const login = await api('POST', '/api/login', { id: 'Live_Ace', password: 'secret1' });
  assert.ok(login.data.ok && /^[0-9a-f]{64}$/.test(login.data.token), 'sign-in with the account name and password: ' + login.text);
  const aTok = login.data.token;

  const s1 = await rank({ kos: 340, wins: 12, matches: 20, arcade_best: 2, arcade_diff: 'nightmare', board: 'kos' }, aTok);
  assert.equal(s1.status, 200, 'rank submit status: ' + s1.text);
  assert.ok(s1.data.ok && s1.data.board === 'kos', 'rank submit: ' + s1.text);
  assert.deepEqual({ rank: s1.data.you.rank, score: s1.data.you.score }, { rank: 1, score: 340 }, 'the submit reply carries `you`: ' + JSON.stringify(s1.data.you));
  assert.equal(s1.data.stats.kos, 340); assert.equal(s1.data.stats.wins, 12); assert.equal(s1.data.stats.arcade.nightmare, 2);
  const readA = await board('?board=kos&limit=20', aTok);
  assert.equal(readA.status, 200); assert.ok(readA.data.ok, 'GET board: ' + readA.text);
  assert.equal(readA.data.entries[0].name, 'Live_Ace'); assert.equal(readA.data.entries[0].score, 340);
  assert.equal(readA.data.entries[0].rank, 1); assert.equal(readA.data.entries[0].me, true);
  assert.equal(readA.data.you.rank, 1); assert.ok(readA.data.entries[0].updated > 0, 'entries carry their updated time');

  const sB = await rank({ kos: 100, wins: 1, matches: 2 }, B.data.token);
  assert.ok(sB.data.ok && sB.data.you.rank === 2, 'B is second: ' + sB.text);
  const readB = await board('?board=kos&limit=20', B.data.token);
  assert.deepEqual(readB.data.entries.slice(0, 2).map(e => e.score), [340, 100], 'ordering is score descending');
  assert.equal(readB.data.entries[1].name, 'Live_Bo'); assert.equal(readB.data.entries[1].me, true);
  assert.deepEqual({ rank: readB.data.you.rank, score: readB.data.you.score }, { rank: 2, score: 100 }, 'a signed-in read gets `you`');

  const noTok = await rank({ kos: 1 }, '');
  assert.equal(noTok.status, 401, 'a submit without a login is refused');
  assert.equal(noTok.data.err, 'auth'); assert.ok(/application\/json/.test(noTok.type));
  const junk = await rank({ kos: 'lots' }, aTok);
  assert.equal(junk.status, 400, 'a junk stat is refused'); assert.equal(junk.data.err, 'stats');

  // ---- unknown /api/* routes are JSON 404s, never the static-file text (the client's "server too old" signal)
  const nope = await api('GET', '/api/nope');
  assert.equal(nope.status, 404, 'unknown /api route is a 404');
  assert.ok(/application\/json/.test(nope.type), 'unknown /api route answers JSON: ' + nope.type);
  assert.deepEqual({ ok: nope.data.ok, err: nope.data.err, msg: nope.data.msg }, { ok: false, err: 'none', msg: 'Not found.' }, 'the JSON 404 body: ' + nope.text);
  const missing = await api('POST', '/api/rank/extra', {});
  assert.equal(missing.status, 404); assert.ok(/application\/json/.test(missing.type), 'an unknown /api sub-path is JSON too');

  // ---- filler accounts: the Godot account stays below the shown top 20, so its own record must come from `you`
  for (let i = 0; i < 20; i++) {
    const c = await api('POST', '/api/claim', { name: 'Fill_' + String(i).padStart(2, '0') });
    assert.ok(c.data.ok, 'filler claim ' + i + ': ' + c.text);
    const rs = await rank({ kos: 1000 - i * 10 }, c.data.token);
    assert.ok(rs.data.ok, 'filler rank ' + i + ': ' + rs.text);
  }
  const C = await api('POST', '/api/signup', { username: 'GodotE2E', email: 'godot_e2e@example.com', password: 'secret1' });
  assert.ok(C.data.ok && /^[0-9a-f]{64}$/.test(C.data.token), 'Godot account sign-up: ' + C.text);
  const top = await board('?board=kos&limit=20');
  assert.equal(top.data.entries.length, 20, 'GET limit=20 fills the board');
  assert.ok(!top.data.entries.some(e => e.name === 'GodotE2E'), 'the Godot account is not on the board yet');

  // ---- Godot: static client checks + live fetch/sync/old-server/offline
  const r = await godotTest(['--api=' + base, '--token=' + C.data.token, '--old=' + oldText.base, '--oldjson=' + oldJson.base]);
  const out = r.stdout;
  const lines = out.split('\n').filter(l => /^(ok |FAIL|RANKING)|SCRIPT ERROR|^ERROR|Parse Error/.test(l));
  console.log(lines.join('\n'));
  const failed = lines.filter(l => /^FAIL |SCRIPT ERROR|^ERROR|Parse Error/.test(l));
  let ok = r.status === 0 && /^RANKING ok/m.test(out) && failed.length === 0;
  if (!ok && !lines.length) console.log(out.slice(0, 4000));
  assert.ok(ok, 'godot ranking test failed (exit ' + r.status + ')' + (failed.length ? ': ' + failed[0] : ''));
  console.log('godot ranking client test passes (states + live fetch/sync)');

  // ---- read the server back: the client's Sync really stored the career totals it showed
  const after = await board('?board=kos&limit=20', C.data.token);
  assert.equal(after.data.you.score, 11, 'the Godot client Sync reached the server (you.score 11): ' + JSON.stringify(after.data.you));
  assert.ok(after.data.you.rank > 20, 'the synced record is still below the shown top 20 (rank ' + after.data.you.rank + ')');
  assert.ok(!after.data.entries.some(e => e.name === 'GodotE2E'), 'so the own record could only come from `you`');
  const all = await board('?board=kos&limit=100', C.data.token);
  assert.ok(all.data.entries.some(e => e.name === 'GodotE2E' && e.score === 11), 'the stored best is on the board');
  const wins = await board('?board=wins', C.data.token);
  assert.equal(wins.data.you.score, 3, 'the same Sync posted the local wins too');

  await srv.stop();
  await closeAll(oldText.server, oldJson.server);
  try { fs.rmSync(process.env.DATA_DIR, { recursive: true, force: true }); } catch (e) { /* best effort */ }
  console.log('leaderboard e2e (real server, temp store): ordering / you / 401 / JSON 404 / client Sync pass');
  process.exit(0);
})().catch(async e => {
  console.error('FAIL', e.message);
  try { await srv.stop(); } catch (x) { /* x */ }
  try { fs.rmSync(process.env.DATA_DIR, { recursive: true, force: true }); } catch (x) { /* x */ }
  process.exit(1);
});
