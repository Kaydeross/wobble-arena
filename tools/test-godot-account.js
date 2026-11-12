'use strict';
/* Godot accounts + cloud save test (npm run test:godot-account): starts the real server (REQUIRE_LOGIN=0, a temp
   DATA_DIR, nothing touches ./data), makes a web-shaped account the way public/index.html would (signup with a
   snapshot() blob), then runs godot/tests/account_test.gd headless against it: offline, sign up, debounced push,
   second device, stale conflict (Use cloud / Keep this device), guest sign-in choice, change password, recovery code
   reset, the web account loading and syncing back, delete account, expired login. Afterwards checks on the server
   that the web account got the Godot change and kept its web-only keys. Needs Godot (GODOT env var or the macOS default). */
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0';
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'wa-account-'));
const srv = require('../server');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');

(async () => {
  spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
  await srv.start(0);
  const base = 'http://127.0.0.1:' + srv.server.address().port;
  const api = async (method, p, body, token) => { const r = await fetch(base + p, { method, headers: Object.assign({ 'content-type': 'application/json' }, token ? { authorization: 'Bearer ' + token } : {}), body: body ? JSON.stringify(body) : undefined }); return Object.assign({ status: r.status }, await r.json()); };
  // a web player's save (snapshot() shape: v, cfg, look, map, sens, set, stats, wallet)
  const webUser = 'webby' + (process.pid % 1000), webPass = 'webpass1';
  const blob = { v: 64, cfg: { mode: 'ffa', count: 3, hp: 200 }, look: { color: 0x39b5a8, hat: 'crown', skin: 'none', cls: 'kid' }, map: 'arena', sens: 1.1, floppy: 1, set: { vol: 0.4, killcam: true },
    stats: { kos: 7, best: 3, wins: 2, matches: 9, secs: 321.5, deaths: 4, onl: 1, hits: 40, hist: [{ m: 'Classic', map: 'Arena', ko: 3, d: 1, w: 1, o: 0 }] },
    wallet: { coins: 2222, owned: ['wobble', 'dab'], slots: ['wobble', 'dab', null], skins: ['none'], codes: [], daily: { d: 0, s: 0 } } };
  const su = await api('POST', '/api/signup', { username: webUser, email: webUser + '@example.com', password: webPass, data: blob });
  assert.ok(su.ok && su.t > 0, 'web signup: ' + JSON.stringify(su));

  // (spawn, not spawnSync: the server runs in this process and must keep answering)
  const r = await new Promise(res => {
    const p = spawn(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/account_test.gd', '--', '--no-save', '--api=' + base, '--web=' + webUser + ':' + webPass]);
    let o = ''; p.stdout.on('data', d => { o += d; if (process.env.VERBOSE) process.stdout.write(d); }); p.stderr.on('data', d => { o += d; });
    const tm = setTimeout(() => p.kill(), 240000);
    p.on('close', c => { clearTimeout(tm); res({ status: c, stdout: o }); });
  });
  const out = r.stdout;
  const lines = out.split('\n').filter(l => /^(ok |FAIL|ACCOUNT|WEB_COINS)|SCRIPT ERROR|^ERROR/.test(l));
  console.log(lines.join('\n'));
  let ok = r.status === 0 && /^ACCOUNT ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
  if (!ok && !lines.length) console.log(out.slice(0, 3000));

  // the web account on the server: the Godot change arrived, web-only keys kept
  const m = /^WEB_COINS=(\d+)/m.exec(out);
  if (m) {
    const li = await api('POST', '/api/login', { id: webUser, password: webPass });
    const d = li.data || {};
    console.log('server: web account coins ' + (d.wallet && d.wallet.coins) + ', cfg ' + JSON.stringify(d.cfg) + ', set ' + JSON.stringify(d.set));
    if (!(d.wallet && d.wallet.coins === +m[1] && d.cfg && d.cfg.mode === 'ffa' && d.set && d.set.vol === 0.4 && d.sens === 1.1 && d.look.hat === 'crown')) { console.log('FAIL the web account on the server'); ok = false; }
  } else ok = false;
  await srv.stop();
  try { fs.rmSync(process.env.DATA_DIR, { recursive: true, force: true }); } catch (e) { /* x */ }
  if (!ok) { console.log('godot account test FAILED'); process.exit(1); }
  console.log('godot account test passes');
  process.exit(0);
})().catch(async e => { console.error('FAIL', e.message); try { await srv.stop(); } catch (x) { /* x */ } process.exit(1); });
