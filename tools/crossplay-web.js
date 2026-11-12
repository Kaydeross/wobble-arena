'use strict';
/* Real cross-play smoke test: the WEB game hosts (headless Chromium via Playwright, match started at once with bots),
   the Godot client joins from its title screen (`-- --join=CODE --server=URL`) and plays for a few seconds.
   Checks: the web host turned a bot slot into Godot's human slot, receives Godot's `S` (ghost moving, sane hp),
   Godot's hp drops after the host lands a hit on its ghost, and neither side logs errors.
   Needs network (three.js loads from a CDN) and `npx playwright install chromium`. Run: node tools/crossplay-web.js */
const assert = require('assert');
const path = require('path');
const { spawn } = require('child_process');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = require('os').tmpdir() + '/wa-xplay-' + process.pid;
const srv = require('../server');
const { chromium } = require('playwright');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  await srv.start(0);
  const port = srv.server.address().port;
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1000, height: 600 } })).newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error' && !/favicon|Failed to load resource/.test(m.text())) errors.push(m.text()); });
  const benign = e => /pointer lock/i.test(e);                                  // headless Chromium has no pointer lock
  await page.goto('http://127.0.0.1:' + port + '/', { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 120000 });
  await page.click('#start'); await sleep(500);
  await page.evaluate(() => globalThis.__wobbleTest.netHost({ auto: true, name: 'Web room' }));
  await page.waitForFunction(() => { const n = globalThis.__wobbleTest.getNet(); return n && n.code && n.started; }, null, { timeout: 20000 });
  const code = await page.evaluate(() => globalThis.__wobbleTest.getNet().code);
  console.log('web room', code);

  let out = '';
  const g = spawn(GODOT, ['--headless', '--path', path.join(__dirname, '..', 'godot'), '--max-fps', '60', '--quit-after', '960', '--', '--no-save',
    '--join=' + code, '--server=ws://127.0.0.1:' + port + '/ws', '--name=GodotMac']);
  g.stdout.on('data', d => out += d); g.stderr.on('data', d => out += d);
  const exited = new Promise(r => g.on('exit', r));

  await page.waitForFunction(() => { const n = globalThis.__wobbleTest.getNet(); return n.slots && n.slots[1] && n.slots[1].kind === 'human' && n.ghosts[1] && n.ghosts[1].ns; }, null, { timeout: 30000 });
  const a = await page.evaluate(() => { const n = globalThis.__wobbleTest.getNet(), gh = n.ghosts[1]; return { name: n.slots[1].name, cls: n.slots[1].cls, x: gh.pos.x, z: gh.pos.z, hp: gh.ns.hp }; });
  await sleep(1500);
  const hit = await page.evaluate(() => {                     // the host's player whacks Godot's ghost: an `h` goes to Godot
    const t = globalThis.__wobbleTest, n = t.getNet(), gh = n.ghosts[1], d = gh.pos.clone().set(0, 0.2, 1);
    gh.invuln = 0; return gh.hit(25, d, 5, false, t.player);
  });
  await sleep(1500);
  const b = await page.evaluate(() => { const n = globalThis.__wobbleTest.getNet(), gh = n.ghosts[1]; return { x: gh.pos.x, z: gh.pos.z, hp: gh.ns.hp, age: n.clock - gh.ns.rt }; });
  console.log('web sees godot:', JSON.stringify(a), '->', JSON.stringify(b), 'hit sent:', hit);
  await exited;
  const gerr = out.split('\n').filter(l => /SCRIPT ERROR|^ERROR|Parse Error/.test(l));
  for (const l of gerr) console.log('godot:', l);
  for (const e of errors) console.log('web:', e);
  assert.equal(a.name, 'GodotMac'); assert.ok(a.hp > 0 && a.hp <= 200, 'sane hp');
  assert.ok(b.age < 0.5, 'S keeps arriving');
  assert.ok(b.hp < a.hp, 'the web host\'s hit lowered Godot\'s hp (' + a.hp + ' -> ' + b.hp + ')');
  assert.equal(gerr.length, 0, 'no Godot errors'); assert.deepEqual(errors.filter(e => !benign(e)), [], 'no web errors');
  console.log('web <-> godot cross-play smoke test passes');
  await browser.close(); await srv.stop(); process.exit(0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
