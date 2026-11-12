'use strict';
/* Renders a 3D picture of every level (or the ids given) with the game's own thumbnail code and saves PNG/JPEGs. Also a contact sheet check.
   node tools/shoot-maps.js [outDir] [mapId ...]      Needs network (three.js CDN) and playwright chromium. */
const fs = require('fs'), os = require('os'), path = require('path');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-shoot-' + process.pid;
const srv = require('../server');
const { chromium, devices } = require('playwright');
(async () => {
  const out = process.argv[2] || path.join(os.tmpdir(), 'wa-maps'); const only = process.argv.slice(3);
  fs.mkdirSync(out, { recursive: true });
  await srv.start(0);
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 852, height: 393 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true, userAgent: devices['iPhone 15 Pro'].userAgent });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  const html = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');       // the game is one module: expose a few of its functions without touching the file
  const hook = 'window.__wa = { MAPS, loadMap, shot3d, get TT_A0() { return TT_A0; } };\n';
  await page.route(/\/(index\.html)?(\?.*)?$/, r => r.request().url().match(/127\.0\.0\.1:\d+\/(index\.html)?(\?.*)?$/) ? r.fulfill({ contentType: 'text/html', body: html.replace(/<\/script>\s*<\/body>/, hook + '</script></body>') }) : r.continue());
  await page.goto('http://127.0.0.1:' + srv.server.address().port + '/', { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 180000 });
  const ids = await page.evaluate(() => Object.keys(__wa.MAPS));
  let n = 0;
  for (const id of ids) {
    if (only.length && !only.includes(id)) continue;
    const url = await page.evaluate(i => { __wa.loadMap(i); return __wa.shot3d(840, 450, __wa.TT_A0, 0.85); }, id);
    if (!url) { errors.push('no picture for ' + id); continue; }
    fs.writeFileSync(path.join(out, id + '.jpg'), Buffer.from(url.split(',')[1], 'base64')); n++;
  }
  console.log(n + ' pictures in ' + out + (errors.length ? ' errors: ' + errors.join('; ') : ''));
  await browser.close(); await srv.stop(); process.exit(errors.length ? 1 : 0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
