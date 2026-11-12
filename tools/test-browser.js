'use strict';
/* Browser smoke test: boots the game on an iPhone-sized landscape screen, checks for script errors and horizontal scrolling, saves a screenshot.
   Needs network (three.js loads from a CDN today) and `npx playwright install chromium`. Run: npm run test:browser */
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = require('os').tmpdir() + '/wa-browser-' + process.pid;
const srv = require('../server');
const { chromium, devices } = require('playwright');
(async () => {
  await srv.start(0);
  const url = 'http://127.0.0.1:' + srv.server.address().port + '/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 852, height: 393 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, userAgent: devices['iPhone 15 Pro'].userAgent });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error' && !/favicon|Failed to load resource/.test(m.text())) errors.push(m.text()); });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 120000 });   // the boot screen builds every level picture: slow without a GPU
  await page.waitForTimeout(3000);
  const info = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, viewport: document.querySelector('meta[name=viewport]').content, hasMenu: !!document.getElementById('menu') }));
  await page.screenshot({ path: process.env.SHOT || require('os').tmpdir() + '/wa-menu.png' });
  console.log(JSON.stringify(info), 'errors:', errors.length);
  assert.ok(info.hasMenu, 'menu element exists');
  assert.ok(/viewport-fit=cover/.test(info.viewport), 'viewport-fit=cover');
  assert.ok(info.sw <= info.cw + 1, 'no horizontal scroll (' + info.sw + ' > ' + info.cw + ')');
  assert.deepEqual(errors, [], 'no script errors');
  await browser.close(); await srv.stop(); console.log('browser smoke test passes'); process.exit(0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
