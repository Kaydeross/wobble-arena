#!/usr/bin/env node
'use strict';
/*
  Prints product metrics from the stored anonymous usage events (docs/ANALYTICS.md): D1/D3/D7 retention, sessions per day,
  median session length, matches per session, the FTUE funnel and the top errors.

  node tools/report-metrics.js [--days=30]   read the events from the same store the server uses: Upstash when
                                             UPSTASH_REDIS_REST_URL / _TOKEN are set, else DATA_DIR (default ./data/db.json)
  node tools/report-metrics.js --selftest    check the maths against a built-in fixture (no store, no network)
*/
const path = require('path');
const DAY = 86400000;
const day = t => new Date(t).toISOString().slice(0, 10);
const dayNo = t => Math.floor(t / DAY);
const median = a => { if (!a.length) return null; const s = a.slice().sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };

/** events: [{i, n, t, p}]; now: ms. Pure, so the selftest can feed it a fixture. */
function compute(events, now) {
  const first = new Map(), active = new Map();                          // install id -> first active day number; -> Set of active day numbers
  for (const e of events) {
    const d = dayNo(e.t);
    if (!first.has(e.i) || d < first.get(e.i)) first.set(e.i, d);
    if (!active.has(e.i)) active.set(e.i, new Set());
    active.get(e.i).add(d);
  }
  const today = dayNo(now), retention = {};
  for (const n of [1, 3, 7]) {
    let eligible = 0, back = 0;
    for (const [iid, d0] of first) if (d0 + n <= today) { eligible++; if (active.get(iid).has(d0 + n)) back++; }   // only cohorts old enough to be measured
    retention['D' + n] = { eligible, returned: back, rate: eligible ? back / eligible : null };
  }
  const perDay = {}; let sessions = 0, matches = 0; const lengths = [], steps = {}, errs = new Map();
  for (const e of events) {
    if (e.n === 'session_start') { sessions++; perDay[day(e.t)] = (perDay[day(e.t)] || 0) + 1; }
    else if (e.n === 'session_end' && e.p && Number.isFinite(e.p.secs)) lengths.push(e.p.secs);
    else if (e.n === 'match_start') matches++;
    else if (e.n === 'ftue_step' && e.p && e.p.step) { if (!steps[e.p.step]) steps[e.p.step] = new Set(); steps[e.p.step].add(e.i); }
    else if (e.n === 'error' && e.p) { const k = String(e.p.text || '') + ' @ ' + String(e.p.at || '?'); const c = errs.get(k) || { n: 0, iids: new Set() }; c.n++; c.iids.add(e.i); errs.set(k, c); }
  }
  const days = Object.keys(perDay).length;
  return {
    installs: first.size, events: events.length, retention,
    sessionsPerDay: { total: sessions, days, avg: days ? sessions / days : null, byDay: perDay },
    medianSessionSecs: median(lengths),
    matchesPerSession: sessions ? matches / sessions : null,
    ftue: Object.fromEntries(['intro_shown', 'intro_done', 'intro_skipped', 'first_match_start', 'first_match_end'].map(s => [s, steps[s] ? steps[s].size : 0])),
    topErrors: [...errs].sort((a, b) => b[1].n - a[1].n).slice(0, 10).map(([k, v]) => ({ error: k, count: v.n, installs: v.iids.size })),
  };
}

const pct = r => (r.rate === null ? 'n/a (no cohort old enough)' : (r.rate * 100).toFixed(1) + '%  (' + r.returned + ' of ' + r.eligible + ')');
const f1 = v => (v === null ? 'n/a' : (Math.round(v * 10) / 10).toString());
function print(m) {
  const out = ['Events: ' + m.events + ', installs seen: ' + m.installs, '',
    'Retention', ...['D1', 'D3', 'D7'].map(k => '  ' + k + ': ' + pct(m.retention[k])), '',
    'Sessions per day: avg ' + f1(m.sessionsPerDay.avg) + ' over ' + m.sessionsPerDay.days + ' day(s), ' + m.sessionsPerDay.total + ' total',
    ...Object.keys(m.sessionsPerDay.byDay).sort().map(d => '  ' + d + ': ' + m.sessionsPerDay.byDay[d]),
    'Median session length: ' + (m.medianSessionSecs === null ? 'n/a' : f1(m.medianSessionSecs) + ' s'),
    'Matches per session: ' + f1(m.matchesPerSession), '',
    'FTUE funnel (installs that reached each step)', ...Object.entries(m.ftue).map(([k, v]) => '  ' + k.padEnd(18) + v), '',
    'Top errors', ...(m.topErrors.length ? m.topErrors.map(e => '  ' + e.count + 'x (' + e.installs + ' install' + (e.installs === 1 ? '' : 's') + ')  ' + e.error) : ['  none'])];
  console.log(out.join('\n'));
}

function selftest() {
  const assert = require('assert'), now = Date.UTC(2026, 0, 10, 12), at = (d, h) => Date.UTC(2026, 0, d, h || 10);
  const ev = (i, n, t, p) => ({ i, n, t, p: p || {} });
  const E = [
    ev('a', 'install', at(1)), ev('a', 'session_start', at(1)), ev('a', 'ftue_step', at(1), { step: 'intro_shown' }), ev('a', 'ftue_step', at(1), { step: 'intro_done' }), ev('a', 'match_start', at(1)), ev('a', 'ftue_step', at(1), { step: 'first_match_start' }), ev('a', 'session_end', at(1), { secs: 100 }),
    ev('a', 'session_start', at(2)), ev('a', 'match_start', at(2)), ev('a', 'session_end', at(2), { secs: 300 }),            // a: back on D1
    ev('a', 'session_start', at(8)),                                                                                           // a: back on D7
    ev('b', 'install', at(1)), ev('b', 'session_start', at(1)), ev('b', 'ftue_step', at(1), { step: 'intro_shown' }), ev('b', 'ftue_step', at(1), { step: 'intro_skipped' }), ev('b', 'session_end', at(1), { secs: 200 }),   // b: never back
    ev('c', 'install', at(4)), ev('c', 'session_start', at(4)), ev('c', 'session_start', at(7)),                               // c: back on D3 only
    ev('d', 'install', at(10)), ev('d', 'session_start', at(10)),                                                              // d: too new to measure
    ev('b', 'error', at(1), { text: 'Invalid access', at: 'a.gd:3' }), ev('c', 'error', at(4), { text: 'Invalid access', at: 'a.gd:3' }), ev('c', 'error', at(4), { text: 'Other', at: 'b.gd:9' }),
  ];
  const m = compute(E, now);
  assert.equal(m.installs, 4);
  assert.deepEqual([m.retention.D1.eligible, m.retention.D1.returned], [3, 1], 'D1: a, b, c are old enough, only a came back');   // d (day 10) is not
  assert.deepEqual([m.retention.D3.eligible, m.retention.D3.returned], [3, 1], 'D3: c came back');
  assert.deepEqual([m.retention.D7.eligible, m.retention.D7.returned], [2, 1], 'D7: a came back on day 8');
  assert.equal(m.sessionsPerDay.total, 7); assert.equal(m.sessionsPerDay.days, 6); assert.equal(m.sessionsPerDay.byDay['2026-01-01'], 2);
  assert.equal(m.medianSessionSecs, 200, 'median of 100, 300, 200');
  assert.equal(m.matchesPerSession, 2 / 7);
  assert.deepEqual(m.ftue, { intro_shown: 2, intro_done: 1, intro_skipped: 1, first_match_start: 1, first_match_end: 0 });
  assert.equal(m.topErrors[0].count, 2); assert.equal(m.topErrors[0].installs, 2); assert.equal(m.topErrors.length, 2);
  const empty = compute([], now); assert.equal(empty.retention.D1.rate, null); assert.equal(empty.medianSessionSecs, null);
  console.log('report-metrics selftest ok');
}

(async () => {
  const args = process.argv.slice(2);
  if (args.includes('--selftest')) return selftest();
  const days = Math.max(1, Math.min(31, Number((args.find(a => a.startsWith('--days=')) || '').slice(7)) || 30));
  const accounts = require(path.join(__dirname, '..', 'accounts.js'));
  const store = accounts.makeStore();
  const events = await require(path.join(__dirname, '..', 'events.js')).create(store).load(days);
  console.log('Store: ' + store.kind + ', last ' + days + ' day(s)\n');
  print(compute(events, Date.now()));
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
