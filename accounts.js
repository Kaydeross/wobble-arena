'use strict';
/*
  Wobblers Arena accounts: sign up, log in, log out and cloud saves.

  Where the data lives:
    - if UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN are set (a free Upstash database): there. It survives restarts and redeploys.
    - otherwise in a file (./data/db.json, or DATA_DIR). Fine on your own computer. On Render's free plan that file is wiped every redeploy.

  Names: POST /api/claim makes a password-less account from just a name (add a password later with /api/protect). An account nobody used for
  ACCOUNT_TTL_DAYS (default 0 = never) is erased by a sweep (startup and every 6 hours), which frees the name; `s` on the user record is lastSeen.
  A positive TTL is an explicit operator choice. Store purchases must never be attached to an account that can expire silently.

  Passwords are never stored: only a salted scrypt hash. Logging in gives a random token that the game keeps in the browser.
*/
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

/* ---------------- storage ---------------- */
function upstashStore(url, token) {
  url = url.replace(/\/+$/, '');
  const cmd = async arr => {
    const r = await fetch(url, { method: 'POST', headers: { Authorization: 'Bearer ' + token, 'content-type': 'application/json' }, body: JSON.stringify(arr) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || j.error) throw new Error('store: ' + (j.error || r.status));
    return j.result;
  };
  return {
    kind: 'upstash',
    async get(k) { const v = await cmd(['GET', k]); return v === undefined ? null : v; },
    async set(k, v, o) { o = o || {}; const a = ['SET', k, v]; if (o.nx) a.push('NX'); if (o.ex) a.push('EX', String(o.ex)); return (await cmd(a)) === 'OK'; },
    async del(k) { await cmd(['DEL', k]); },
    async scan(prefix) {                                              // every key that starts with `prefix`
      const out = []; let cur = '0';
      do { const r = await cmd(['SCAN', cur, 'MATCH', prefix.replace(/[\\*?\[\]]/g, '\\$&') + '*', 'COUNT', '500']); cur = String(r[0]); for (const k of r[1]) out.push(k); } while (cur !== '0');
      return out;
    },
  };
}
function fileStore(dir) {
  const file = path.join(dir, 'db.json'); let db = {}, timer = null;
  try { db = JSON.parse(fs.readFileSync(file, 'utf8')) || {}; } catch (e) { db = {}; }
  const flush = () => {
    timer = null;
    try { fs.mkdirSync(dir, { recursive: true }); const tmp = file + '.tmp'; fs.writeFileSync(tmp, JSON.stringify(db)); fs.renameSync(tmp, file); } catch (e) { console.error('could not write the accounts file:', e.message); }
  };
  const later = () => { if (!timer) timer = setTimeout(flush, 400); if (timer.unref) timer.unref(); };
  const live = k => { const e = db[k]; if (!e) return null; if (e.e && e.e < Date.now()) { delete db[k]; return null; } return e; };
  return {
    kind: 'file',
    flush,
    async get(k) { const e = live(k); return e ? e.v : null; },
    async set(k, v, o) { o = o || {}; if (o.nx && live(k)) return false; db[k] = { v, e: o.ex ? Date.now() + o.ex * 1000 : 0 }; later(); return true; },
    async del(k) { delete db[k]; later(); },
    async scan(prefix) { return Object.keys(db).filter(k => k.startsWith(prefix) && live(k)); },
  };
}
function makeStore() {
  const u = process.env.UPSTASH_REDIS_REST_URL, t = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (u && t) return upstashStore(u, t);
  return fileStore(process.env.DATA_DIR || path.join(__dirname, 'data'));
}

/* ---------------- helpers ---------------- */
const TOKEN_DAYS = 365, SAVE_MAX = 250 * 1024;
const DAY = 86400000, TOUCH_MS = 3600000, SWEEP_MS = 6 * 3600000;       // lastSeen is written at most once an hour per account; the sweep runs every 6 hours
const ttlDays = () => { const n = Number(process.env.ACCOUNT_TTL_DAYS); return process.env.ACCOUNT_TTL_DAYS !== undefined && process.env.ACCOUNT_TTL_DAYS !== '' && isFinite(n) && n >= 0 ? n : 0; };   // 0 = never erase
const RESERVED = new Set(['admin', 'administrator', 'mod', 'moderator', 'owner', 'staff', 'support', 'guest', 'system', 'server', 'wobble', 'wobblearena', 'root', 'null', 'undefined']);
const USER_RE = /^[A-Za-z0-9_]{3,16}$/, EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,}$/;
const BLOCKED_NAME_TERMS = ['nigger', 'nigga', 'faggot', 'retard', 'rape', 'hitler', 'nazi', 'kkk', 'porn', 'whore', 'slut'];
function nameKey(s) {
  return String(s || '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase()
    .replace(/[013457@$]/g, c => ({ '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's' })[c])
    .replace(/[^a-z]/g, '');
}
function badName(s) { const k = nameKey(s); return BLOCKED_NAME_TERMS.some(term => k.includes(term)); }
function filterDisplayName(s) {
  const clean = String(s || '').replace(/[\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e]/g, '').trim().slice(0, 24);
  return badName(clean) ? 'Player' : clean;
}
const scrypt = (pw, salt) => new Promise((res, rej) => crypto.scrypt(pw, salt, 64, { N: 16384, r: 8, p: 1 }, (e, k) => (e ? rej(e) : res(k))));
async function hashPw(pw) { const salt = crypto.randomBytes(16); return 's1$' + salt.toString('hex') + '$' + (await scrypt(pw, salt)).toString('hex'); }
async function checkPw(pw, stored) {
  const [v, s, h] = String(stored || '').split('$'); if (v !== 's1' || !s || !h) return false;
  const k = await scrypt(pw, Buffer.from(s, 'hex')), b = Buffer.from(h, 'hex');
  return k.length === b.length && crypto.timingSafeEqual(k, b);
}
const RC_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const newRecovery = () => { const b = crypto.randomBytes(16); let o = ''; for (let i = 0; i < 16; i++) { o += RC_CHARS[b[i] % RC_CHARS.length]; if (i % 4 === 3 && i < 15) o += '-'; } return o; };       // 16 letters and numbers, shown as XXXX-XXXX-XXXX-XXXX
const cleanRecovery = c => String(c || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
const newToken = () => crypto.randomBytes(32).toString('hex');
const lname = u => String(u).toLowerCase();

class Fail extends Error { constructor(status, err, msg) { super(msg); this.status = status; this.err = err; } }

function create(store) {
  store = store || makeStore();
  const fails = new Map();                                            // ip or account -> {n, t}: failed log-ins in the last 10 minutes
  const WINDOW = 10 * 60 * 1000;
  const failCount = k => { const f = fails.get(k); if (!f) return 0; if (Date.now() - f.t > WINDOW) { fails.delete(k); return 0; } return f.n; };
  const addFail = k => { const f = fails.get(k); if (f && Date.now() - f.t <= WINDOW) f.n++; else fails.set(k, { n: 1, t: Date.now() }); };
  const signups = new Map();                                          // ip -> {n, t}: sign-ups in the last hour
  const lastSave = new Map();                                         // account -> time of the last save (one a second at most)
  const reports = new Map();                                          // account -> time of its last safety report (one per 10 s)
  const rankRates = new Map();                                        // account -> {n, t}: ranking updates in the current window

  /* ---------------- ranking (docs/PROTOCOL.md 4.1) ----------------
     The account record keeps each player's lifetime best (`u.rk`) and is only ever raised, never lowered. Each board has
     one small cache key (`rank:<board>`) with the top RANK.top entries; a submit updates the player's record and then
     merges the new score into those caches. A GET is a single store read. This works the same on both store kinds
     (file and Upstash) because it only uses get/set. */
  const RANK = {
    boards: ['kos', 'wins', 'arcade'],
    top: 100, defaultLimit: 20, maxLimit: 100,
    statsMax: 10000000, stageMax: 6,
    diffs: ['easy', 'normal', 'nightmare'], diffWeight: { easy: 1, normal: 2, nightmare: 3 },
    windowMs: 10000, perWindow: 6,
    key: b => 'rank:' + b,
  };
  const boardArg = b => { const s = String(b === undefined || b === null ? '' : b).trim(); return RANK.boards.includes(s) ? s : null; };
  const limitArg = n => { const v = n === undefined || n === null || n === '' ? RANK.defaultLimit : Number(n); return Number.isFinite(v) ? Math.max(1, Math.min(RANK.maxLimit, Math.floor(v))) : RANK.defaultLimit; };
  const isStat = v => typeof v === 'number' && Number.isFinite(v) && Number.isInteger(v);
  const int0 = v => (Number.isFinite(Number(v)) ? Math.max(0, Math.floor(Number(v))) : 0);
  function optStat(v, name, cap) {
    if (v === undefined || v === null) return null;
    if (!isStat(v) || v < 0 || v > cap) throw new Fail(400, 'stats', name + ' must be a whole number from 0 to ' + cap + '.');
    return v;
  }
  function readStats(b) {
    const out = {};
    for (const k of ['kos', 'wins', 'matches']) { const v = optStat(b[k], k, RANK.statsMax); if (v !== null) out[k] = v; }
    const stage = optStat(b.arcade_best, 'arcade_best', RANK.stageMax);
    if (stage !== null) {
      const d = String(b.arcade_diff === undefined || b.arcade_diff === null ? 'normal' : b.arcade_diff);
      if (!RANK.diffs.includes(d)) throw new Fail(400, 'stats', 'arcade_diff must be easy, normal or nightmare.');
      out.arcade_best = stage; out.arcade_diff = d;
    }
    if (!Object.keys(out).length) throw new Fail(400, 'stats', 'Send kos, wins, matches or arcade_best.');
    return out;
  }
  /** One number per board so the three boards share the sort/view code. Arcade is the furthest stage weighted by difficulty. */
  function rankScore(u, board) {
    const rk = (u && u.rk && typeof u.rk === 'object') ? u.rk : {};
    if (board === 'kos') return int0(rk.kos);
    if (board === 'wins') return int0(rk.wins);
    const a = (rk.arcade && typeof rk.arcade === 'object') ? rk.arcade : {};
    let best = 0;
    for (const d of RANK.diffs) best = Math.max(best, int0(a[d]) * RANK.diffWeight[d]);
    return best;
  }
  function rankCompare(a, b) {
    return (b.score - a.score) || ((a.t || 0) - (b.t || 0)) || String(a.name).localeCompare(String(b.name)) || String(a.l).localeCompare(String(b.l));
  }
  async function readBoard(board) {
    try { const raw = await store.get(RANK.key(board)); const o = raw ? JSON.parse(raw) : null; return o && Array.isArray(o.top) ? o.top : []; } catch (e) { return []; }
  }
  const writeBoard = (board, top) => store.set(RANK.key(board), JSON.stringify({ t: Date.now(), top: top.slice(0, RANK.top) }));
  function rankOf(top, l, score, at) {
    const i = top.findIndex(e => e && e.l === l);
    if (i >= 0) return { rank: i + 1, score: top[i].score, updated: top[i].t || 0 };
    let better = 0;
    for (const e of top) if (e && e.score > score) better++;
    return { rank: better + 1, score, updated: at || 0, estimated: true };   // below the cached top: position is a lower bound
  }
  function rankView(top, limit, me) {
    return top.slice(0, limit).map((e, i) => {
      const out = { rank: i + 1, name: String(e.name || 'Player'), score: int0(e.score), updated: int0(e.t) };
      if (me && e.l === me) out.me = true;
      return out;
    });
  }


  const getUser = async l => { const v = await store.get('user:' + l); try { return v ? JSON.parse(v) : null; } catch (e) { return null; } };
  const putUser = (l, u) => store.set('user:' + l, JSON.stringify(u));
  async function issue(l) { const t = newToken(); await store.set('tok:' + t, l, { ex: TOKEN_DAYS * 86400 }); return t; }
  async function revokeSessions(l) {
    for (const k of await store.scan('tok:')) if ((await store.get(k)) === l) await store.del(k);
  }
  async function who(token) {                                          // token -> account record, or null; counts as a visit (lastSeen)
    if (typeof token !== 'string' || !/^[0-9a-f]{64}$/.test(token)) return null;
    const l = await store.get('tok:' + token); if (!l) return null;
    const u = await getUser(l); if (!u) return null;
    const now = Date.now(); if (!(now - (u.s || 0) < TOUCH_MS)) { u.s = now; await putUser(l, u); }   // not on every request: once an hour at most
    return { l, u };
  }
  const pub = u => ({ username: u.u, email: u.e || '', created: u.c, hasPassword: !!u.p });
  const newSignups = ip => { const s = signups.get(ip); if (s && Date.now() - s.t < 3600000 && s.n >= 40) throw new Fail(429, 'slow', 'Too many new accounts from this network. Try again in a while.'); return s; };
  const countSignup = (ip, s) => { if (s && Date.now() - s.t < 3600000) s.n++; else signups.set(ip, { n: 1, t: Date.now() }); };
  const needPass = a => { if (!a.u.p) throw new Fail(400, 'nopass', 'This name has no password yet. Protect it with a password first.'); };
  async function loadData(l) { const v = await store.get('data:' + l); try { return v ? JSON.parse(v) : null; } catch (e) { return null; } }

  async function eraseUser(l, u) { await revokeSessions(l); await store.del('user:' + l); if (u.e) await store.del('email:' + lname(u.e)); await store.del('data:' + l); }
  /* Erase accounts nobody has used for an explicitly enabled ACCOUNT_TTL_DAYS (default 0 = never): the account, its saves and its tokens.
     Accounts from before lastSeen existed get lastSeen = now the first time, so nobody is erased by the upgrade. Returns counts only. */
  async function sweepAccounts(now) {
    now = now || Date.now(); const ttl = ttlDays(); const out = { checked: 0, erased: 0, migrated: 0 };
    const gone = new Set();
    for (const k of await store.scan('user:')) {
      const l = k.slice(5), u = await getUser(l); if (!u) continue; out.checked++;
      if (!u.s) { u.s = now; await putUser(l, u); out.migrated++; continue; }
      if (ttl > 0 && now - u.s > ttl * DAY) { await eraseUser(l, u); gone.add(l); out.erased++; }
    }
    if (gone.size) for (const k of await store.scan('tok:')) { const l = await store.get(k); if (gone.has(l)) await store.del(k); }
    lastSave.forEach((_, l) => { if (gone.has(l)) lastSave.delete(l); });
    return out;
  }
  let sweepTimer = null;
  function startSweeps() {
    if (sweepTimer) return;
    const run = () => sweepAccounts().then(r => { if (r.erased || r.migrated) console.log('accounts sweep: ' + r.checked + ' checked, ' + r.erased + ' erased (unused for ' + ttlDays() + ' days), ' + r.migrated + ' given a first lastSeen'); }, e => console.error('accounts sweep failed:', e && e.message));
    run(); sweepTimer = setInterval(run, SWEEP_MS); if (sweepTimer.unref) sweepTimer.unref();
  }
  function stopSweeps() { if (sweepTimer) clearInterval(sweepTimer); sweepTimer = null; }

  const routes = {
    async signup(b, ctx) {
      const un = String(b.username || '').trim(), em = String(b.email || '').trim(), pw = String(b.password || '');
      if (!USER_RE.test(un)) throw new Fail(400, 'username', 'Usernames are 3 to 16 letters, numbers or underscores.');
      if (RESERVED.has(lname(un))) throw new Fail(400, 'username', 'That username isn\'t allowed. Pick another one.');
      if (badName(un)) throw new Fail(400, 'username', 'That username isn\'t allowed. Pick another one.');
      if (em.length > 100 || !EMAIL_RE.test(em)) throw new Fail(400, 'email', 'That email doesn\'t look right. Check it and try again.');
      if (pw.length < 6 || pw.length > 72) throw new Fail(400, 'password', 'Passwords need 6 to 72 characters.');
      const s = newSignups(ctx.ip);
      const l = lname(un), le = lname(em);
      if (await store.get('user:' + l)) throw new Fail(409, 'username', 'That username is taken. Pick another one.');
      const rc = newRecovery();
      const user = { u: un, e: em, p: await hashPw(pw), r: await hashPw(cleanRecovery(rc)), c: Date.now(), l: Date.now(), s: Date.now() };
      if (!(await store.set('user:' + l, JSON.stringify(user), { nx: true }))) throw new Fail(409, 'username', 'That username is taken. Pick another one.');
      if (!(await store.set('email:' + le, l, { nx: true }))) { await store.del('user:' + l); throw new Fail(409, 'email', 'That email already has an account. Try logging in.'); }
      let t = 0;
      if (b.data && typeof b.data === 'object') { const j = JSON.stringify(b.data); if (j.length <= SAVE_MAX) { t = Date.now(); await store.set('data:' + l, JSON.stringify({ t, d: b.data })); } }
      countSignup(ctx.ip, s);
      return { ok: true, token: await issue(l), user: pub(user), data: t ? b.data : null, t, recovery: rc };
    },
    async claim(b, ctx) {                                                 // just pick a name: a password-less account (add one later with /api/protect)
      const un = String(b.name || b.username || '').trim();
      if (!USER_RE.test(un)) throw new Fail(400, 'username', 'Usernames are 3 to 16 letters, numbers or underscores.');
      if (RESERVED.has(lname(un))) throw new Fail(400, 'username', 'That username isn\'t allowed. Pick another one.');
      if (badName(un)) throw new Fail(400, 'username', 'That username isn\'t allowed. Pick another one.');
      const s = newSignups(ctx.ip), l = lname(un);
      if (await store.get('user:' + l)) throw new Fail(409, 'username', 'That username is taken. Pick another one.');
      const now = Date.now(), user = { u: un, e: '', p: '', r: '', c: now, l: now, s: now };
      if (!(await store.set('user:' + l, JSON.stringify(user), { nx: true }))) throw new Fail(409, 'username', 'That username is taken. Pick another one.');
      let t = 0;
      if (b.data && typeof b.data === 'object') { const j = JSON.stringify(b.data); if (j.length <= SAVE_MAX) { t = now; await store.set('data:' + l, JSON.stringify({ t, d: b.data })); } }
      countSignup(ctx.ip, s);
      return { ok: true, token: await issue(l), user: pub(user), data: t ? b.data : null, t };
    },
    async protect(b, ctx) {                                               // put a password on a name-only account so it can log in on another device
      const a = await who(ctx.token); if (!a) throw new Fail(401, 'auth', 'Please log in again.');
      if (a.u.p) throw new Fail(409, 'has', 'This account already has a password. Use change password.');
      const pw = String(b.password || ''); if (pw.length < 6 || pw.length > 72) throw new Fail(400, 'password', 'Passwords need 6 to 72 characters.');
      const rc = newRecovery(); a.u.p = await hashPw(pw); a.u.r = await hashPw(cleanRecovery(rc)); await putUser(a.l, a.u);
      return { ok: true, recovery: rc, user: pub(a.u) };
    },
    async login(b, ctx) {
      const id = String(b.id || '').trim(), pw = String(b.password || '');
      if (!id || !pw) throw new Fail(400, 'missing', 'Type your username (or email) and password.');
      const l0 = id.includes('@') ? await store.get('email:' + lname(id)) : lname(id);
      if (failCount('ip:' + ctx.ip) >= 40 || failCount('acc:' + l0) >= 8) throw new Fail(429, 'slow', 'Too many wrong tries. Wait 10 minutes and try again.');
      const u = l0 ? await getUser(l0) : null;
      if (!u || !(await checkPw(pw, u.p))) { addFail('ip:' + ctx.ip); if (l0) addFail('acc:' + l0); throw new Fail(401, 'wrong', 'Wrong username or password. Check them and try again.'); }
      fails.delete('acc:' + l0); u.l = u.s = Date.now(); await putUser(l0, u);
      const d = await loadData(l0);
      return { ok: true, token: await issue(l0), user: pub(u), data: d ? d.d : null, t: d ? d.t : 0 };
    },
    async me(b, ctx) {
      const a = await who(ctx.token); if (!a) throw new Fail(401, 'auth', 'Please log in again.');
      const d = await loadData(a.l);
      await store.set('tok:' + ctx.token, a.l, { ex: TOKEN_DAYS * 86400 });                // every visit renews the login, so people who keep playing stay logged in
      return { ok: true, user: pub(a.u), data: d ? d.d : null, t: d ? d.t : 0, hasRecovery: !!a.u.r, hasPassword: !!a.u.p };
    },
    async save(b, ctx) {
      const a = await who(ctx.token); if (!a) throw new Fail(401, 'auth', 'Please log in again.');
      if (!b.data || typeof b.data !== 'object') throw new Fail(400, 'data', 'Nothing to save.');
      const j = JSON.stringify(b.data); if (j.length > SAVE_MAX) throw new Fail(413, 'big', 'That save is too big.');
      const now = Date.now(), last = lastSave.get(a.l) || 0; if (now - last < 800) throw new Fail(429, 'fast', 'Saving too fast. Wait a moment and try again.');
      const cur = await loadData(a.l);
      const base = Number(b.base);
      const curT = Number(cur && cur.t);
      if (cur && b.base !== undefined && Number.isFinite(base) && Number.isFinite(curT) && base < curT && !b.force)
        return { ok: false, err: 'stale', msg: 'This account was saved on another device.', data: cur.d, t: cur.t };
      lastSave.set(a.l, now);
      await store.set('data:' + a.l, JSON.stringify({ t: now, d: b.data }));
      return { ok: true, t: now };
    },
    async logout(b, ctx) { if (ctx.token && /^[0-9a-f]{64}$/.test(ctx.token)) await store.del('tok:' + ctx.token); return { ok: true }; },
    async password(b, ctx) {
      const a = await who(ctx.token); if (!a) throw new Fail(401, 'auth', 'Please log in again.');
      needPass(a); const np = String(b.next || '');
      if (np.length < 6 || np.length > 72) throw new Fail(400, 'password', 'Passwords need 6 to 72 characters.');
      if (failCount('acc:' + a.l) >= 8) throw new Fail(429, 'slow', 'Too many wrong tries. Wait 10 minutes and try again.');
      if (!(await checkPw(String(b.old || ''), a.u.p))) { addFail('acc:' + a.l); throw new Fail(401, 'wrong', 'That password is wrong.'); }
      a.u.p = await hashPw(np); await putUser(a.l, a.u);
      await revokeSessions(a.l);
      return { ok: true, token: await issue(a.l) };
    },
    async recovery(b, ctx) {                                              // make a new recovery code (needs the password); the old one stops working
      const a = await who(ctx.token); if (!a) throw new Fail(401, 'auth', 'Please log in again.'); needPass(a);
      if (failCount('acc:' + a.l) >= 8) throw new Fail(429, 'slow', 'Too many wrong tries. Wait 10 minutes and try again.');
      if (!(await checkPw(String(b.password || ''), a.u.p))) { addFail('acc:' + a.l); throw new Fail(401, 'wrong', 'That password is wrong.'); }
      const rc = newRecovery(); a.u.r = await hashPw(cleanRecovery(rc)); await putUser(a.l, a.u);
      return { ok: true, recovery: rc };
    },
    async reset(b, ctx) {                                                 // forgot the password: username or email + recovery code + a new password
      const id = String(b.id || '').trim(), code = cleanRecovery(b.code), np = String(b.password || '');
      if (!id || !code) throw new Fail(400, 'missing', 'Type your username (or email) and your recovery code.');
      if (np.length < 6 || np.length > 72) throw new Fail(400, 'password', 'Passwords need 6 to 72 characters.');
      const l0 = id.includes('@') ? await store.get('email:' + lname(id)) : lname(id);
      if (failCount('ip:' + ctx.ip) >= 20 || failCount('acc:' + l0) >= 6) throw new Fail(429, 'slow', 'Too many wrong tries. Wait 10 minutes and try again.');
      const u = l0 ? await getUser(l0) : null;
      if (!u || !u.r || !(await checkPw(code, u.r))) { addFail('ip:' + ctx.ip); if (l0) addFail('acc:' + l0); throw new Fail(401, 'wrong', 'That username and recovery code don\'t match. Check the code (letters and numbers, no mix-ups between O and 0).'); }
      fails.delete('acc:' + l0);
      const rc = newRecovery(); u.p = await hashPw(np); u.r = await hashPw(cleanRecovery(rc)); u.l = u.s = Date.now(); await putUser(l0, u);
      await revokeSessions(l0);
      const d = await loadData(l0);
      return { ok: true, token: await issue(l0), user: pub(u), data: d ? d.d : null, t: d ? d.t : 0, recovery: rc };
    },
    async remove(b, ctx) {
      const a = await who(ctx.token); if (!a) throw new Fail(401, 'auth', 'Please log in again.');
      if (failCount('acc:' + a.l) >= 8) throw new Fail(429, 'slow', 'Too many wrong tries. Wait 10 minutes and try again.');
      if (a.u.p && !(await checkPw(String(b.password || ''), a.u.p))) { addFail('acc:' + a.l); throw new Fail(401, 'wrong', 'That password is wrong.'); }   // a name-only account has no password to ask for
      await eraseUser(a.l, a.u);
      return { ok: true };
    },
    async report(b, ctx) {
      const a = await who(ctx.token); if (!a) throw new Fail(401, 'auth', 'Please log in again.');
      const now = Date.now(), last = reports.get(a.l) || 0;
      if (now - last < 10000) throw new Fail(429, 'slow', 'You just sent a report. Wait a moment before sending another.');
      const rawTarget = String(b.target || '').replace(/[\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e]/g, '').trim().slice(0, 24);
      const target = badName(rawTarget) ? '[filtered name]' : filterDisplayName(rawTarget), room = String(b.room || '').replace(/[^A-Za-z0-9]/g, '').slice(0, 16);
      const reason = String(b.reason || 'other'), details = String(b.details || '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 240);
      if (!rawTarget || target === 'Player' || !['harassment', 'name', 'cheating', 'spam', 'other'].includes(reason))
        throw new Fail(400, 'report', 'Choose a player and a reason.');
      const id = crypto.randomBytes(8).toString('hex');
      reports.set(a.l, now);
      await store.set('mod:' + now + ':' + id, JSON.stringify({ reporter: a.l, target, room, reason, details, at: now }), { ex: 90 * 86400 });
      return { ok: true, id };
    },
    /* GET /api/rank?board=kos|wins|arcade&limit=N: the top scores (public; a valid token also gets `you`). */
    async rankList(b, ctx) {
      if (b.board !== undefined && boardArg(b.board) === null) throw new Fail(400, 'board', 'board must be kos, wins or arcade.');
      const board = boardArg(b.board) || 'kos', limit = limitArg(b.limit);
      const top = await readBoard(board);
      let you = null, me = '';
      if (ctx.token) {
        const a = await who(ctx.token);
        if (a) { me = a.l; you = rankOf(top, a.l, rankScore(a.u, board), int0(a.u.rk && a.u.rk.at)); }
      }
      return { ok: true, board, entries: rankView(top, limit, me), you };
    },
    /* POST /api/rank: store this account's lifetime best (only ever raised) and return the board it asked for.
       Body: {kos?, wins?, matches?, arcade_best?, arcade_diff?, board?, limit?}. */
    async rankSubmit(b, ctx) {
      const a = await who(ctx.token); if (!a) throw new Fail(401, 'auth', 'Please log in again.');
      if (b.board !== undefined && boardArg(b.board) === null) throw new Fail(400, 'board', 'board must be kos, wins or arcade.');
      const stats = readStats(b);                                                       // validate first: junk never uses the rate budget
      const now = Date.now(), rl = rankRates.get(a.l);
      if (rl && now - rl.t < RANK.windowMs) {
        if (rl.n >= RANK.perWindow) throw new Fail(429, 'slow', 'Ranking updates too fast. Wait a few seconds and try again.');
        rl.n++;
      } else rankRates.set(a.l, { n: 1, t: now });
      const old = (a.u.rk && typeof a.u.rk === 'object') ? a.u.rk : {};
      const oldArc = (old.arcade && typeof old.arcade === 'object') ? old.arcade : {};
      const rk = { kos: int0(old.kos), wins: int0(old.wins), matches: int0(old.matches), at: int0(old.at),
        arcade: { easy: int0(oldArc.easy), normal: int0(oldArc.normal), nightmare: int0(oldArc.nightmare) } };
      if (stats.kos !== undefined) rk.kos = Math.max(rk.kos, stats.kos);                 // monotonic: never decrease
      if (stats.wins !== undefined) rk.wins = Math.max(rk.wins, stats.wins);
      if (stats.matches !== undefined) rk.matches = Math.max(rk.matches, stats.matches);
      if (stats.arcade_best !== undefined) rk.arcade[stats.arcade_diff] = Math.max(rk.arcade[stats.arcade_diff], stats.arcade_best);
      rk.at = now;
      a.u.rk = rk;
      await putUser(a.l, a.u);
      for (const board of RANK.boards) {
        const score = rankScore(a.u, board);
        if (score <= 0) continue;
        const top = await readBoard(board), i = top.findIndex(e => e && e.l === a.l);
        if (i >= 0 && int0(top[i].score) >= score) continue;                             // no change: keep its earlier `updated` time
        const next = top.filter(e => e && e.l !== a.l);
        next.push({ l: a.l, name: filterDisplayName(a.u.u), score, t: now });
        next.sort(rankCompare);
        await writeBoard(board, next);
      }
      const board = boardArg(b.board) || 'kos', limit = limitArg(b.limit);
      const top = await readBoard(board);
      return { ok: true, board, entries: rankView(top, limit, a.l), you: rankOf(top, a.l, rankScore(a.u, board), rk.at),
        stats: { kos: rk.kos, wins: rk.wins, matches: rk.matches, arcade: { easy: rk.arcade.easy, normal: rk.arcade.normal, nightmare: rk.arcade.nightmare } } };
    },
  };
  const map = { '/api/signup': ['POST', 'signup'], '/api/claim': ['POST', 'claim'], '/api/protect': ['POST', 'protect'], '/api/login': ['POST', 'login'], '/api/me': ['GET', 'me'], '/api/save': ['PUT', 'save'], '/api/logout': ['POST', 'logout'], '/api/password': ['POST', 'password'], '/api/recovery': ['POST', 'recovery'], '/api/reset': ['POST', 'reset'], '/api/delete': ['POST', 'remove'], '/api/report': ['POST', 'report'], '/api/rank': { GET: 'rankList', POST: 'rankSubmit' } };

  const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type, authorization', 'access-control-allow-methods': 'GET, POST, PUT, OPTIONS', 'access-control-max-age': '86400' };
  const reply = (res, status, obj) => { res.writeHead(status, Object.assign({ 'content-type': 'application/json', 'cache-control': 'no-store' }, CORS)); res.end(JSON.stringify(obj)); };
  function readBody(req) {
    return new Promise((res, rej) => {
      let n = 0, over = false; const parts = [];
      req.on('data', c => { n += c.length; if (n > 5 * 1024 * 1024) { req.destroy(); return; } if (n > SAVE_MAX + 4096) { over = true; parts.length = 0; return; } if (!over) parts.push(c); });
      req.on('end', () => { if (over) { rej(new Fail(413, 'big', 'That save is too big.')); return; } try { res(parts.length ? JSON.parse(Buffer.concat(parts).toString('utf8')) : {}); } catch (e) { rej(new Fail(400, 'json', 'Couldn\'t read that request. Try again.')); } });
      req.on('error', () => rej(new Fail(400, 'io', 'Couldn\'t read that request. Try again.')));
    });
  }
  // returns true when it handled the request
  function handle(req, res, ip) {
    const url = (req.url || '').split('?')[0];
    if (!url.startsWith('/api/')) return false;
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS); res.end(); return true; }
    const r = map[url];
    const name = Array.isArray(r) ? (r[0] === req.method ? r[1] : '') : (r && typeof r === 'object' ? (r[req.method] || '') : '');
    if (!name) { reply(res, 404, { ok: false, err: 'none', msg: 'Not found.' }); return true; }
    const auth = String(req.headers.authorization || ''), token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
    (async () => {
      try {
        const q = (req.url || '').split('?')[1] || '';
        const b = req.method === 'GET' ? Object.fromEntries(new URLSearchParams(q)) : await readBody(req);   // GET query: board/limit for /api/rank
        const out = await routes[name](b, { ip, token }); reply(res, out.ok === false ? 409 : 200, out);
      }
      catch (e) {
        if (e instanceof Fail) reply(res, e.status, { ok: false, err: e.err, msg: e.message });
        else { console.error('accounts error:', e && e.message); reply(res, 500, { ok: false, err: 'server', msg: 'The server had a problem. Try again in a moment.' }); }
      }
    })();
    return true;
  }
  return { handle, who, store, kind: store.kind, routes, sweep: sweepAccounts, startSweeps, stopSweeps, TOUCH_MS };
}

module.exports = { create, makeStore, fileStore, upstashStore, badName, filterDisplayName };
