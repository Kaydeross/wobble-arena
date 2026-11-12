'use strict';
/* Touch test: on an iPhone-sized landscape screen a tap on PLAY starts a match without Pointer Lock, a stick drag moves the player,
   FIRE and the look area drive the same input state as the mouse, and the pause button returns to the menu. Screenshots go to $SHOTS (default: the temp dir).
   Needs network (three.js CDN) and `npx playwright install chromium`. Run: npm run test:touch */
const assert = require('assert'), os = require('os'), path = require('path'), fs = require('fs');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-touch-' + process.pid;
const srv = require('../server');
const { chromium, devices } = require('playwright');
const SHOTS = process.env.SHOTS || os.tmpdir(); fs.mkdirSync(SHOTS, { recursive: true });
(async () => {
  await srv.start(0);
  const url = 'http://127.0.0.1:' + srv.server.address().port + '/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 852, height: 393 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, userAgent: devices['iPhone 15 Pro'].userAgent });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 180000 });
  await page.waitForTimeout(2500);
  const shot = n => page.screenshot({ path: path.join(SHOTS, n + '.png') });
  const cdp = await ctx.newCDPSession(page);
  const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((p, i) => ({ x: p[0], y: p[1], id: p[2] === undefined ? i : p[2] })) });
  const center = async id => page.evaluate(i => { const r = document.getElementById(i).getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }, id);
  { const [sx, sy] = await center('start'); await page.touchscreen.tap(sx, sy); }   // the title screen: tap PLAY
  await page.waitForFunction(() => document.getElementById('menu').style.display === 'flex', null, { timeout: 15000 });
  await page.waitForTimeout(800);
  await shot('touch-home');
  const [px, py] = await center('go-practice'); await page.touchscreen.tap(px, py);   // tap PRACTICE: starts a match with no Pointer Lock
  await page.waitForFunction(() => window.__wa && window.__wa.ui === 'play', null, { timeout: 15000 });
  const st = await page.evaluate(() => ({ locked: window.__wa.locked, plock: !!document.pointerLockElement, touchUi: getComputedStyle(document.getElementById('touch')).display, ptouch: document.body.classList.contains('ptouch') }));
  assert.ok(st.locked && !st.plock, 'match runs without pointer lock'); assert.equal(st.touchUi, 'block', 'touch controls are shown'); assert.ok(st.ptouch, 'keyboard hints are hidden after a touch');
  await page.waitForTimeout(2500);                                                // let the player land
  await shot('touch-hud');
  // stick drag: left thumb, up = forward
  const p0 = await page.evaluate(() => ({ x: __wa.player.pos.x, z: __wa.player.pos.z }));
  await touch('touchStart', [[130, 300]]); for (let i = 1; i <= 6; i++) await touch('touchMove', [[130, 300 - i * 12]]);
  await page.waitForTimeout(250); await shot('touch-stick');
  await page.waitForTimeout(700);
  const mv = await page.evaluate(() => ({ f: !!__wa.keys[Object.keys(__wa.keys).find(k => k === 'KeyW')], x: __wa.player.pos.x, z: __wa.player.pos.z }));
  await touch('touchEnd', []);
  const moved = Math.hypot(mv.x - p0.x, mv.z - p0.z);
  assert.ok(mv.f, 'stick up holds the forward key'); assert.ok(moved > 1, 'stick drag moves the player (' + moved.toFixed(2) + ' m)');
  await page.waitForTimeout(200);
  assert.ok(!(await page.evaluate(() => !!__wa.keys.KeyW)), 'releasing the stick releases the key');
  // look: drag on the right half
  const y0 = await page.evaluate(() => __wa.cam.yaw);
  await touch('touchStart', [[500, 120]]); for (let i = 1; i <= 5; i++) await touch('touchMove', [[500 + i * 20, 120]]); await touch('touchEnd', []);
  assert.ok(Math.abs((await page.evaluate(() => __wa.cam.yaw)) - y0) > 0.2, 'dragging on the right half turns the camera');
  // FIRE
  const [fx, fy] = await center('tb-fire'); await touch('touchStart', [[fx, fy]]); await page.waitForTimeout(100);
  assert.ok(await page.evaluate(() => !!__wa.keys.Mouse0), 'FIRE holds the attack input'); await shot('touch-fire'); await touch('touchEnd', []); await page.waitForTimeout(100);
  assert.ok(!(await page.evaluate(() => !!__wa.keys.Mouse0)), 'FIRE releases');
  // left-handed layout mirrors the buttons and the stick area
  const fx0 = (await center('tb-fire'))[0];
  await page.evaluate(() => { __wa.TC.lefty = true; __wa.tcLayout(); }); await page.waitForTimeout(200);
  const fx1 = (await center('tb-fire'))[0]; await shot('touch-lefty');
  assert.ok(fx0 > 600 && fx1 < 250, 'left-handed layout moves FIRE to the left (' + fx0 + ' -> ' + fx1 + ')');
  await page.evaluate(() => { __wa.TC.lefty = false; __wa.tcLayout(); });
  // pause button back to the menu
  const [bx, by] = await center('tb-pause'); await page.touchscreen.tap(bx, by);
  await page.waitForFunction(() => window.__wa.ui === 'lobby' && !window.__wa.locked, null, { timeout: 5000 });
  await page.waitForTimeout(800); await shot('touch-pause-menu');
  assert.deepEqual(errors, [], 'no script errors');
  await browser.close(); await srv.stop(); console.log('touch test passes'); process.exit(0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
