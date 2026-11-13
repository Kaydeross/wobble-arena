'use strict';
/* Dynamic arenas in the real game (Playwright, phone-sized touch screen): for each kind on Sunny Arena the floor really moves,
   the player can walk across the tiles without getting stuck, no page errors; screenshots go to docs/style/dyn-*.png.
   node tools/test-dyn-browser.js        (npm run test:dyn; needs network for three.js and `npx playwright install chromium`) */
const assert = require('assert'), path = require('path'), os = require('os');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-dyn-' + process.pid;
const srv = require('../server');
const { chromium, devices } = require('playwright');
const OUT = process.env.DYN_SHOTS || path.join(__dirname, '..', 'docs', 'style');

async function start(page, kind) {
  await page.evaluate(k => {
    const T = globalThis.__wobbleTest; T.cfg.dyn = k;
    T.setBotCfg({ mode: 'classic', count: 0, behav: 'dummy' }); T.loadMap('arena'); T.play();
  }, kind);
  await page.waitForFunction(() => window.__wa && window.__wa.ui === 'play', null, { timeout: 15000 });
}
const simWait = (page, sec) => page.evaluate(s => new Promise(res => { const T = globalThis.__wobbleTest, end = T.simTime + s; const k = () => (T.simTime >= end ? res() : setTimeout(k, 30)); k(); }), sec);
const tops = page => page.evaluate(() => globalThis.__wobbleTest.solids.map(s => [s.top, s.minX, s.minZ]));
async function walk(page, yaw, ms) {                                  // hold "forward" facing yaw, return distance covered on the ground plane
  const a = await page.evaluate(y => { const w = window.__wa; w.cam.yaw = y; w.keys.KeyW = true; return [w.player.pos.x, w.player.pos.z, globalThis.__wobbleTest.simTime]; }, yaw);
  await simWait(page, ms / 1000);                                     // game time, not wall time (software rendering can run slower than real time)
  const b = await page.evaluate(() => { const w = window.__wa; w.keys.KeyW = false; return [w.player.pos.x, w.player.pos.z, w.player.pos.y]; });
  if (process.env.DYN_TRACE) console.log('walk', yaw.toFixed(2), a.map(v => v.toFixed(2)).join(), '->', b.map(v => v.toFixed(2)).join());
  return { d: Math.hypot(b[0] - a[0], b[1] - a[1]), y: b[2] };
}
(async () => {
  await srv.start(0);
  const url = 'http://127.0.0.1:' + srv.server.address().port + '/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 852, height: 393 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, userAgent: devices['iPhone 15 Pro'].userAgent });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error' && !/favicon|Failed to load resource/.test(m.text())) errors.push(m.text()); });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 240000 });
  await page.waitForTimeout(2000);
  await page.click('#start'); await page.waitForTimeout(800);
  const res = {};
  for (const kind of ['off', 'wobble', 'tilt', 'quake', 'drift']) {
    await start(page, kind);
    const st = await page.evaluate(() => { const d = globalThis.__wobbleTest.dyn; return { kind: d.kind, tiles: d.tiles.length, drift: d.drift.length }; });
    const t0 = await tops(page);
    // the player starts at (0, 8): walk west along z = 8 (clear of boxes), then back east, over several tiles
    const w1 = await walk(page, -Math.PI / 2, 2200), w2 = await walk(page, Math.PI / 2, 2200);
    await simWait(page, 2.6);                                           // ~8 s of match time in total
    const t1 = await tops(page);
    let moved = 0; for (let i = 0; i < Math.min(t0.length, t1.length); i++) moved = Math.max(moved, Math.abs(t1[i][0] - t0[i][0]), Math.abs(t1[i][1] - t0[i][1]), Math.abs(t1[i][2] - t0[i][2]));
    res[kind] = { st, moved: +moved.toFixed(3), walk: [+w1.d.toFixed(1), +w2.d.toFixed(1)], y: +w2.y.toFixed(2) };
    if (kind !== 'off') {
      assert.equal(st.kind, kind, kind + ' runs on arena');
      assert.ok(kind === 'drift' ? st.drift > 0 : st.tiles >= 16, kind + ': tiles / drifting blocks built');
      if (kind !== 'quake') assert.ok(moved > 0.05, kind + ': the arena actually moves (' + moved + ')');   // quake waits 12 s before its first shake
    } else assert.equal(st.tiles, 0, 'steady: no tiles');
    assert.ok(w1.d > 9 && w2.d > 9, kind + ': walked freely across the tiles (' + w1.d.toFixed(1) + ', ' + w2.d.toFixed(1) + ' m)');
    assert.ok(w2.y > -1, kind + ': still on the floor');
    const shot = n => page.screenshot({ path: path.join(OUT, 'dyn-' + n + '.png') });
    const view = (yaw, pitch) => page.evaluate(([y, p]) => { const w = window.__wa; w.cam.yaw = y; w.cam.pitch = p; }, [yaw, pitch]);
    if (kind === 'wobble') { await view(Math.PI * 0.75, -0.55); await page.waitForTimeout(700); await shot('wobble'); }
    if (kind === 'tilt') { await page.evaluate(() => { const T = globalThis.__wobbleTest; T.dyn.t0 -= 3; }); await view(Math.PI * 0.8, -0.55); await page.waitForTimeout(900); await shot('tilt'); }
    if (kind === 'drift') { await view(Math.PI * 1.2, -0.45); await page.waitForTimeout(700); await shot('drift'); }
    if (kind === 'quake') {                                             // jump the clock to just before the first quake, wait for a hole, look at it
      await page.evaluate(() => {                                       // a seed whose first quake opens a hole on this level (some first quakes only shake)
        const T = globalThis.__wobbleTest, d = T.dyn, P = d.plan;
        for (let seed = 1; seed < 2000; seed++) if (d.tiles.some(e => T.dynOffset('quake', seed, 16.5, e.ix, e.iz, P.nx, P.nz, e.mask) < -5)) { d.seed = seed; break; }
        d.t0 = T.simTime - 11.5;
      });
      await page.waitForFunction(() => globalThis.__wobbleTest.dyn.tiles.some(e => e.off < -5), null, { timeout: 15000 });
      const hole = await page.evaluate(() => {                        // stand 8 m from the hole, on the side towards the middle, and look at it
        const T = globalThis.__wobbleTest, w = window.__wa, e = T.dyn.tiles.find(q => q.off < -5), hx = e.mesh.position.x, hz = e.mesh.position.z, l = Math.hypot(hx, hz) || 1;
        const px = hx - hx / l * 8, pz = hz - hz / l * 8; w.player.placeAt(px, pz, 0.6); return [hx - px, hz - pz, e.mask];
      });
      assert.ok(!(hole[2] & 2), 'quake: a hole never opens on a spawn tile');
      await view(Math.atan2(hole[0], hole[1]), -0.5); await page.waitForTimeout(600); await shot('quake');
      await page.waitForFunction(() => !globalThis.__wobbleTest.dyn.tiles.some(e => e.off < -0.5), null, { timeout: 15000 });
      res.quake.closed = true;
    }
  }
  // every level: the plan the game builds from its live geometry matches the one computed from shared/maps.json (what the Godot port loads)
  const SRC = require('fs').readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
  const D = new Function(SRC.slice(SRC.indexOf('/* ==== DYN-PURE BEGIN'), SRC.indexOf('/* ==== DYN-PURE END')) + '\nreturn { dynPlan, dynMapAllowed };')();
  const MAPS = require('../shared/maps.json'); let compared = 0;
  for (const [id, m] of Object.entries(MAPS)) {
    if (!D.dynMapAllowed(id, m)) continue;
    const g = m.geometry, sol = g.boxes.map(q => ({ minX: q.x - q.w / 2, maxX: q.x + q.w / 2, minZ: q.z - q.d / 2, maxZ: q.z + q.d / 2, top: q.y + q.h, bottom: q.y }));
    const want = D.dynPlan(sol, (g.ladders || []).map(l => ({ x: l.x, z: l.z })), (g.bouncePads || []).map(p => ({ x: p.x, z: p.z, r: p.r || 1.2 })), [...(m.spawns || []), ...(m.bots || []), ...(m.player ? [m.player] : [])]);
    const live = await page.evaluate(mid => { const T = globalThis.__wobbleTest; T.cfg.dyn = 'off'; T.loadMap(mid); return T.solids.map(q => [q.minX, q.maxX, q.minZ, q.maxZ, q.top, q.bottom].map(v => +v.toFixed(3)).join()); }, id);
    if (JSON.stringify(live) !== JSON.stringify(sol.map(q => [q.minX, q.maxX, q.minZ, q.maxZ, q.top, q.bottom].map(v => +v.toFixed(3)).join()))) { (res.jsonDiffers = res.jsonDiffers || []).push(id); continue; }   // shared/maps.json misses some helper-built boxes on this level (exporter gap, not dynamics)
    for (const kind of ['wobble', 'drift']) {
      const got = await page.evaluate(([k, mid]) => { const T = globalThis.__wobbleTest; T.cfg.dyn = k; T.setBotCfg({ mode: 'classic', count: 0 }); T.loadMap(mid); const d = T.dyn; return { kind: d.kind, tiles: d.tiles.length, plan: d.plan && { nx: d.plan.nx, nz: d.plan.nz, mask: d.plan.mask, drift: d.plan.drift } }; }, [kind, id]);
      if (kind === 'wobble') {
        assert.equal(got.kind, want.canTile ? 'wobble' : 'off', id + ': tiles iff the plan allows it');
        if (want.canTile) { assert.deepStrictEqual([got.plan.nx, got.plan.nz, got.plan.mask], [want.nx, want.nz, want.mask], id + ': same tile grid/mask as maps.json'); assert.equal(got.tiles, want.nx * want.nz); }
      } else {
        assert.equal(got.kind, want.drift.length ? 'drift' : 'off', id + ': drift iff the plan allows it');
        if (want.drift.length) assert.deepStrictEqual(got.plan.drift, want.drift, id + ': same drifting blocks as maps.json');
      }
      compared++;
    }
  }
  res.plansCompared = compared;
  await page.waitForTimeout(500);
  console.log(JSON.stringify(res));
  await browser.close(); await srv.stop();
  assert.deepStrictEqual(errors, [], 'no page errors');
  console.log('dynamic arena browser test OK, shots in ' + OUT);
  process.exit(0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
