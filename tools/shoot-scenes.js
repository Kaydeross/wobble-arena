'use strict';
/* Visual review shots: the same scenes every time, so a graphics change can be compared before/after.
   node tools/shoot-scenes.js [outDir] [suffix]      e.g. node tools/shoot-scenes.js /tmp/shots before
   Phone = iPhone 15 Pro landscape (852x393 @2x, touch). Tablet = 1280x720 @1x touch (bigger frame, easier to judge detail).
   Needs network (three.js CDN) and `npx playwright install chromium`. Software rendering: slow, but the picture is what WebGL draws. */
const fs = require('fs'), os = require('os'), path = require('path');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-scenes-' + process.pid;
const srv = require('../server');
const { chromium, devices } = require('playwright');
const OUT = process.argv[2] || path.join(os.tmpdir(), 'wa-scenes'), SUF = process.argv[3] ? '-' + process.argv[3] : '';
fs.mkdirSync(OUT, { recursive: true });

async function run(browser, url, name, vp, scale) {
  const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: scale, isMobile: true, hasTouch: true, userAgent: devices['iPhone 15 Pro'].userAgent });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 240000 });
  await page.waitForTimeout(2500);
  const shot = n => page.screenshot({ path: path.join(OUT, name + '-' + n + SUF + '.png') });
  const center = async id => page.evaluate(i => { const r = document.getElementById(i).getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }, id);
  await shot('1-title');
  { const [x, y] = await center('start'); await page.touchscreen.tap(x, y); }
  await page.waitForFunction(() => document.getElementById('menu').style.display === 'flex', null, { timeout: 15000 });
  await page.waitForTimeout(1200); await shot('2-home');
  // Sunny Arena match with bots
  await page.evaluate(() => { const T = globalThis.__wobbleTest; T.setBotCfg({ mode: 'classic', count: 5 }); T.loadMap('arena'); T.play(); });
  await page.waitForFunction(() => window.__wa && window.__wa.ui === 'play', null, { timeout: 15000 });
  await page.waitForTimeout(4000); await shot('3-arena-match');
  await page.evaluate(() => { const c = window.__wa.cam; c.yaw += 2.3; c.pitch = -0.12; }); await page.waitForTimeout(1500); await shot('4-arena-view2');
  await page.evaluate(() => { const p = window.__wa.player; p.hit(35, { x: 0, y: 0.2, z: 1, clone() { return this; } }, 6, false, null); }).catch(() => {});
  await page.waitForTimeout(120); await shot('5-arena-hit');
  // Practice Range
  { const [x, y] = await center('tb-pause'); await page.touchscreen.tap(x, y); }
  await page.waitForFunction(() => window.__wa.ui === 'lobby', null, { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(800);
  await page.evaluate(() => document.getElementById('pz-menu').onclick());       // leave the match for the home page
  await page.waitForTimeout(1200);
  { const [x, y] = await center('go-practice'); await page.touchscreen.tap(x, y); }
  await page.waitForFunction(() => window.__wa.ui === 'play', null, { timeout: 15000 });
  await page.waitForTimeout(4000); await shot('6-practice');
  await page.evaluate(() => { const c = window.__wa.cam; c.yaw += 3.1; }); await page.waitForTimeout(1200); await shot('7-practice-view2');
  // Locker (class tab)
  { const [x, y] = await center('tb-pause'); await page.touchscreen.tap(x, y); }
  await page.waitForTimeout(1000);
  await page.evaluate(() => { const T = globalThis.__wobbleTest; T.setLockTab('class'); T.showPage('locker'); T.renderLocker(); });
  await page.waitForTimeout(2500); await shot('8-locker');
  await ctx.close();
  return errors;
}
(async () => {
  await srv.start(0);
  const url = 'http://127.0.0.1:' + srv.server.address().port + '/';
  const browser = await chromium.launch();
  const errs = [];
  errs.push(...await run(browser, url, 'phone', { width: 852, height: 393 }, 2));
  if (!process.env.PHONE_ONLY) errs.push(...await run(browser, url, 'tablet', { width: 1280, height: 720 }, 1));
  console.log('shots in ' + OUT + (errs.length ? '\nerrors: ' + errs.join('; ') : ''));
  await browser.close(); await srv.stop(); process.exit(errs.length ? 1 : 0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
