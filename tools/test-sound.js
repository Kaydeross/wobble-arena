'use strict';
/* Web audio engine test (public/index.html SoundManager). Boots the game in headless Chromium, then:
   - renders every effect in SOUNDS through the real bus graph into an OfflineAudioContext (panned), and checks it
     makes sound, never clips past the compressor (peak < 1), has no NaNs, and frees every voice afterwards;
   - renders 4 bars of the match music at full intensity (peak, NaN);
   - checks the live engine: unlocked by a click, menu music running, mood switch, mute and volume, voices cleaned up.
   Needs network (three.js loads from a CDN). Run: npm run test:sound */
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = require('os').tmpdir() + '/wa-sound-' + process.pid;
const srv = require('../server');
const { chromium } = require('playwright');
(async () => {
  await srv.start(0);
  const url = 'http://127.0.0.1:' + srv.server.address().port + '/';
  const browser = await chromium.launch({ args: ['--autoplay-policy=user-gesture-required'], executablePath: process.env.CHROME_PATH || undefined });
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error' && !/favicon|Failed to load resource/.test(m.text())) errors.push(m.text()); });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 120000 });

  const before = await page.evaluate(() => ({ ctx: !!__wobbleSound.sound.ctx }));
  assert.equal(before.ctx, false, 'no AudioContext before a user gesture');

  // offline renders through the real graph
  const res = await page.evaluate(async () => {
    const { SOUNDS, SoundManager } = __wobbleSound;
    const SR = 44100, out = {};
    const make = len => {
      const oc = new OfflineAudioContext(2, Math.floor(SR * len), SR), m = new SoundManager(), Real = window.AudioContext;
      window.AudioContext = function () { return oc; }; try { m.init(); } finally { window.AudioContext = Real; }
      Object.defineProperty(m, 'ready', { get: () => true });
      return [oc, m];
    };
    const stats = buf => { let pk = 0, nan = 0, l = 0, r = 0; const L = buf.getChannelData(0), R = buf.getChannelData(1);
      for (let i = 0; i < L.length; i++) { if (L[i] !== L[i] || R[i] !== R[i]) nan++; pk = Math.max(pk, Math.abs(L[i]), Math.abs(R[i])); l += L[i] * L[i]; r += R[i] * R[i]; }
      return { pk: +pk.toFixed(3), nan, lr: +(Math.sqrt(l) / Math.max(1e-9, Math.sqrt(r))).toFixed(2) }; };
    for (const n of Object.keys(SOUNDS)) {
      const [oc, m] = make(4); m.setMasterVolume(1);
      const v = m.play(n, { pan: 0.6, delay: 0.5 }); const voices = m.voices;
      const buf = await oc.startRendering(); await new Promise(r => setTimeout(r, 30));
      out[n] = Object.assign(stats(buf), { started: !!v, voices, after: m.voices, left: v ? v.nodes.length : -1 });
    }
    // 4 bars of match music at full intensity
    { const [oc, m] = make(9); m.setMasterVolume(1); m.bgm.mood = 'match'; m.bgm.int = 1; m.bgmBus.gain.value = 0.34; const st = 60 / 142 / 4;
      for (let s = 0; s < 64; s++) m.note(s, 0.05 + s * st, st);
      out.__bgm = stats(await oc.startRendering()); }
    // a burst of 30 overlapping hits must stay under the compressor's ceiling
    { const [oc, m] = make(3); m.setMasterVolume(1); for (let i = 0; i < 30; i++) m.play(['boom', 'shotgun', 'whack', 'mammoth'][i % 4], { delay: 0.5 + i * 0.01 });
      out.__stack = stats(await oc.startRendering()); }
    return out;
  });
  const names = Object.keys(res).filter(n => !n.startsWith('__'));
  console.log('effects:', names.map(n => n + ' ' + res[n].pk).join(', '));
  for (const n of names) {
    const r = res[n];
    assert.ok(r.started, n + ' plays'); assert.equal(r.nan, 0, n + ' has no NaN');
    assert.ok(r.pk > 0.005, n + ' makes sound (peak ' + r.pk + ')'); assert.ok(r.pk < 1, n + ' does not clip (peak ' + r.pk + ')');
    assert.ok(r.lr < 1, n + ' is panned right (L/R ' + r.lr + ')');
    assert.equal(r.after, 0, n + ' frees its voice'); assert.equal(r.left, 0, n + ' disconnects its nodes');
  }
  assert.equal(res.__bgm.nan, 0); assert.ok(res.__bgm.pk > 0.02 && res.__bgm.pk < 1, 'music level ' + res.__bgm.pk);
  assert.equal(res.__stack.nan, 0); assert.ok(res.__stack.pk < 1, 'stacked hits stay under 1 (' + res.__stack.pk + ')');
  console.log('music peak', res.__bgm.pk, '· 30 stacked hits peak', res.__stack.pk);

  // live engine: a click unlocks it, the menu music starts, moods switch on the bar, mute works, voices clean up
  await page.mouse.click(640, 360); await page.waitForTimeout(1500);
  const live = await page.evaluate(async () => {
    const { sound, SOUNDS, sfxAt, camera } = __wobbleSound;
    const o = { state: sound.ctx && sound.ctx.state, bgm: sound.bgm.on, mood: sound.bgm.mood };
    for (const n of Object.keys(SOUNDS)) { const q = camera.position.clone(); q.x += 3; q.z -= 4; sfxAt(n, q); }
    o.playing = sound.voices; await new Promise(r => setTimeout(r, 3500)); o.after = sound.voices;
    sound.startBGM('match'); await new Promise(r => setTimeout(r, 3500)); o.mood2 = sound.bgm.mood;
    sound.setMute(true); o.mutedPlay = sound.play('click'); sound.setMute(false);
    sound.setMasterVolume(0.3); o.vol = sound.vol; sound.stopBGM(0.1); o.stopped = !sound.bgm.on && !sound.bgm.timer;
    return o;
  });
  console.log('live:', JSON.stringify(live));
  assert.equal(live.state, 'running', 'context resumes on a click'); assert.ok(live.bgm, 'menu music plays'); assert.equal(live.mood, 'menu');
  assert.ok(live.playing > 10, 'live effects play'); assert.equal(live.after, 0, 'live voices are freed');
  assert.equal(live.mood2, 'match', 'mood switches'); assert.equal(live.mutedPlay, null, 'muted: nothing plays'); assert.equal(live.vol, 0.3); assert.ok(live.stopped, 'music stops');
  assert.deepEqual(errors, [], 'no page errors');
  console.log('sound test passes');
  await browser.close(); srv.server.close(); process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
