'use strict';
/*
  First-party, anonymous usage events (docs/ANALYTICS.md, docs/PROTOCOL.md 4.2): POST /api/event.

  No account, no token, no IP is stored. The client sends a random install id (`iid`), and the server keeps only the
  whitelisted event names and size-capped params. Events go into one append-only bucket per UTC day (`ev:YYYY-MM-DD`,
  a JSON array) in the same store accounts.js uses. A bucket holds at most DAY_MAX events (the oldest are dropped)
  and expires after KEEP_DAYS, so storage cannot grow without bound.
*/
const DAY = 86400000;
const LIMITS = { batchMax: 50, perMin: 30, bodyMax: 32 * 1024, dayMax: 20000, keepDays: 30, iid: 40, params: 8, str: 64, errStr: 200, nameMax: 24 };
const NAMES = new Set(['install', 'session_start', 'session_end', 'ftue_step', 'match_start', 'match_end', 'coins_spent', 'online_join_result', 'error']);
const IID_RE = /^[A-Za-z0-9_-]{8,40}$/, KEY_RE = /^[a-z][a-z0-9_]{0,23}$/, TAG_RE = /^[A-Za-z0-9._-]{1,16}$/;
const dayKey = t => 'ev:' + new Date(t).toISOString().slice(0, 10);
const num = v => (typeof v === 'number' && Number.isFinite(v) ? Math.round(v * 100) / 100 : null);

/** Keep up to 8 scalar params: numbers (rounded), booleans, strings (control chars removed, cut to 64; 200 for `error`). Everything else is dropped. */
function cleanParams(p, cap) {
  cap = cap || LIMITS.str;
  const out = {}; let n = 0;
  if (!p || typeof p !== 'object' || Array.isArray(p)) return out;
  for (const k of Object.keys(p)) {
    if (n >= LIMITS.params) break;
    if (!KEY_RE.test(k)) continue;
    const v = p[k];
    if (typeof v === 'string') out[k] = v.replace(/[\u0000-\u001f\u007f​-‏‪-‮]/g, '').slice(0, cap);
    else if (typeof v === 'boolean') out[k] = v;
    else if (num(v) !== null) out[k] = num(v);
    else continue;
    n++;
  }
  return out;
}

function create(store) {
  const rates = new Map();                                            // ip -> {n, t}: batches in the current minute (kept in memory only)
  let chain = Promise.resolve();                                      // appends run one after another, so two batches never overwrite each other
  const limited = ip => {
    const now = Date.now(), r = rates.get(ip);
    if (rates.size > 5000) for (const [k, v] of rates) if (now - v.t > 60000) rates.delete(k);
    if (!r || now - r.t > 60000) { rates.set(ip, { n: 1, t: now }); return false; }
    return ++r.n > LIMITS.perMin;
  };
  async function append(key, rows) {
    let cur = []; try { const raw = await store.get(key); cur = raw ? JSON.parse(raw) : []; } catch (e) { cur = []; }
    if (!Array.isArray(cur)) cur = [];
    cur = cur.concat(rows); if (cur.length > LIMITS.dayMax) cur = cur.slice(cur.length - LIMITS.dayMax);
    await store.set(key, JSON.stringify(cur), { ex: (LIMITS.keepDays + 1) * 86400 });
  }
  /** Validates and stores a batch. Returns { status, body }. The ip is only used for the rate limit and is never stored. */
  async function submit(b, ip) {
    if (limited(ip)) return { status: 429, body: { ok: false, err: 'slow', msg: 'Too many requests.' } };
    if (!b || typeof b !== 'object' || Array.isArray(b)) return { status: 400, body: { ok: false, err: 'shape', msg: 'Send an object.' } };
    if (typeof b.iid !== 'string' || !IID_RE.test(b.iid)) return { status: 400, body: { ok: false, err: 'iid', msg: 'Bad install id.' } };
    if (!Array.isArray(b.events) || !b.events.length || b.events.length > LIMITS.batchMax) return { status: 400, body: { ok: false, err: 'events', msg: 'Send 1 to ' + LIMITS.batchMax + ' events.' } };
    const now = Date.now(), ver = TAG_RE.test(String(b.ver)) ? String(b.ver) : '', plat = TAG_RE.test(String(b.plat)) ? String(b.plat) : '';
    const rows = [];
    for (const e of b.events) {
      if (!e || typeof e !== 'object' || typeof e.n !== 'string' || !NAMES.has(e.n)) return { status: 400, body: { ok: false, err: 'name', msg: 'Unknown event name.' } };
      const t = typeof e.t === 'number' && Number.isFinite(e.t) && Math.abs(e.t - now) < 2 * DAY ? Math.floor(e.t) : now;   // client clock, clamped to near now
      rows.push({ i: b.iid, n: e.n, t, v: ver, o: plat, p: cleanParams(e.p, e.n === 'error' ? LIMITS.errStr : LIMITS.str) });
    }
    const buckets = new Map();
    for (const r of rows) { const k = dayKey(r.t); if (!buckets.has(k)) buckets.set(k, []); buckets.get(k).push(r); }
    const job = chain.then(async () => { for (const [k, v] of buckets) await append(k, v); });
    chain = job.catch(() => {});
    await job;
    return { status: 200, body: { ok: true, n: rows.length } };
  }
  /** Every stored event for the last `days` days (oldest first). Used by tools/report-metrics.js. */
  async function load(days) {
    const out = [], now = Date.now();
    for (let d = days - 1; d >= 0; d--) { try { const raw = await store.get(dayKey(now - d * DAY)); if (raw) out.push(...JSON.parse(raw)); } catch (e) { /* skip a bad bucket */ } }
    return out;
  }
  const H = { 'content-type': 'application/json', 'cache-control': 'no-store', 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type', 'access-control-allow-methods': 'POST, OPTIONS' };
  const reply = (res, status, obj) => { res.writeHead(status, H); res.end(JSON.stringify(obj)); };
  // returns true when it handled the request
  function handle(req, res, ip) {
    if ((req.url || '').split('?')[0] !== '/api/event') return false;
    if (req.method === 'OPTIONS') { res.writeHead(204, H); res.end(); return true; }
    if (req.method !== 'POST') { reply(res, 404, { ok: false, err: 'none', msg: 'Not found.' }); return true; }
    let n = 0, over = false; const parts = [];
    req.on('data', c => { n += c.length; if (n > LIMITS.bodyMax) { over = true; parts.length = 0; return; } if (!over) parts.push(c); });
    req.on('error', () => reply(res, 400, { ok: false, err: 'io', msg: 'Bad request.' }));
    req.on('end', async () => {
      if (over) { reply(res, 413, { ok: false, err: 'big', msg: 'Too big.' }); return; }
      let b; try { b = JSON.parse(Buffer.concat(parts).toString('utf8')); } catch (e) { reply(res, 400, { ok: false, err: 'json', msg: 'Bad JSON.' }); return; }
      try { const r = await submit(b, ip); reply(res, r.status, r.body); }
      catch (e) { console.error('events error:', e && e.message); reply(res, 500, { ok: false, err: 'server', msg: 'The server had a problem.' }); }
    });
    return true;
  }
  return { handle, submit, load, LIMITS };
}

module.exports = { create, NAMES, LIMITS, cleanParams, dayKey };
