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
  const cl = await page.evaluate(() => {                      // every class: stats apply to a fighter and the HP rules use the fighter's own max
    const { CLASSES, CLASS_IDS, hpOf, player, look, cfg, myInfo, cleanInfo, renderLocker, showPage, setLockTab } = globalThis.__wobbleTest; const giantOn = () => false;
    const out = {}; const base = cfg.hp * (giantOn() ? 2 : 1);
    for (const id of CLASS_IDS) { player.setClass(id); out[id] = { hp: hpOf(player), want: base * CLASSES[id].hp, id: player.clsId }; }
    player.setClass('nonsense'); out.bad = player.clsId;
    look.cls = 'alien'; const inf = myInfo(); out.net = inf.cls; out.clean = cleanInfo({ name: 'x', cls: 'zzz' }, 1).cls; out.cleanOld = cleanInfo({ name: 'x' }, 1).cls;
    setLockTab('class'); renderLocker(); out.cards = document.querySelectorAll('#lclass .clspick').length;
    player.setClass('wobbler'); look.cls = 'wobbler';
    return out;
  });
  for (const id of Object.keys(require('../shared/classes.json'))) assert.ok(cl[id] && Math.abs(cl[id].hp - cl[id].want) < 1e-9 && cl[id].id === id, 'class ' + id + ' applies');
  assert.equal(cl.bad, 'wobbler', 'unknown class falls back'); assert.equal(cl.net, 'alien', 'class is sent in hello'); assert.equal(cl.clean, 'wobbler'); assert.equal(cl.cleanOld, 'wobbler'); assert.equal(cl.cards, 5, 'locker shows 5 classes');
  await page.click('#start'); await page.waitForTimeout(800);
  await page.evaluate(() => { const t = globalThis.__wobbleTest; t.showPage('locker'); t.setLockTab('class'); t.renderLocker(); });
  await page.evaluate(() => document.getElementById('lclass').scrollIntoView({ block: 'start' }));
  await page.waitForTimeout(500);
  await page.screenshot({ path: process.env.SHOT_CLASS || require('os').tmpdir() + '/wa-classes.png' });
  assert.ok(info.hasMenu, 'menu element exists');
  assert.ok(/viewport-fit=cover/.test(info.viewport), 'viewport-fit=cover');
  assert.ok(info.sw <= info.cw + 1, 'no horizontal scroll (' + info.sw + ' > ' + info.cw + ')');
  assert.deepEqual(errors, [], 'no script errors');
  await browser.close(); await srv.stop(); console.log('browser smoke test passes'); process.exit(0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
