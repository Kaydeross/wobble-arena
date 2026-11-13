'use strict';
/* Renders every Godot sound effect from the web game's real WebAudio engine (public/index.html: SOUNDS, SndVoice,
   SoundManager) to a 16-bit 44.1 kHz mono WAV in godot/audio/sfx/<name>.wav, plus godot/audio/sfx/sfx.json
   ({name: {dur, peak}}, used by tools/test-audio.js). The names are the NAMES list in godot/autoload/audio.gd.
   Like tools/render-music.js it boots server.js, opens the page in Playwright's Chromium and, in the page, builds a
   SoundManager whose init() is tricked into using a stereo 44.1 kHz OfflineAudioContext, so each sound goes through
   the real sfx bus -> master -> compressor -> limiter graph. Math.random is seeded and the sound's pitch variation is
   set to 0 for the render (the WAV is the centre pitch). Master volume 1: Godot applies the player's volume.
   The sound is played with { delay: 0.5 } and cut from the voice start (0.5 + 0.005 s, see SndVoice): Chromium's
   compressor misbehaves for sounds at the very start of an offline render. The stereo render is downmixed to mono
   ((L + R) / 2) and the tail trimmed once the signal stays below 1e-4 (20 ms are kept after the last louder sample).
   Chromium's offline render is not bit-exact between runs, so `--check` only verifies structure: every name has a WAV
   and an sfx.json entry, and the WAV length matches the entry's dur within 1 ms. Re-render only when a sound changes.
   Needs Playwright's Chromium (CHROME_PATH to use a specific binary).
   node tools/render-sfx.js [--check]     (npm run sfx) */
const fs = require('fs'), path = require('path'), os = require('os');

const SR = 44100, LEN = 5, START = 0.5 + 0.005, SILENCE = 1e-4, KEEP = 0.02;
const OUT = path.join(__dirname, '..', 'godot', 'audio', 'sfx');
const JSON_FILE = path.join(OUT, 'sfx.json');

/** The sound names Godot plays: the PackedStringArray NAMES in godot/autoload/audio.gd. */
function names() {
  const src = fs.readFileSync(path.join(__dirname, '..', 'godot', 'autoload', 'audio.gd'), 'utf8');
  const m = /const NAMES[^=]*=\s*\[([^\]]*)\]/.exec(src);
  if (!m) throw new Error('NAMES not found in godot/autoload/audio.gd');
  return [...m[1].matchAll(/"([^"]+)"/g)].map(x => x[1]);
}

function wavBuffer(pcm) {
  const data = Buffer.from(pcm.buffer, pcm.byteOffset, pcm.byteLength), h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVEfmt ', 8); h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(SR, 24); h.writeUInt32LE(SR * 2, 28);
  h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(data.length, 40);
  return Buffer.concat([h, data]);
}

/** Seconds of audio in a 16-bit mono WAV, from its chunk headers. */
function wavSeconds(file) {
  const b = fs.readFileSync(file);
  if (b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') throw new Error('not a WAV');
  let p = 12, rate = 0, ch = 0, bits = 0;
  while (p + 8 <= b.length) {
    const id = b.toString('ascii', p, p + 4), sz = b.readUInt32LE(p + 4);
    if (id === 'fmt ') { ch = b.readUInt16LE(p + 10); rate = b.readUInt32LE(p + 12); bits = b.readUInt16LE(p + 22); }
    if (id === 'data') {
      if (rate !== SR || ch !== 1 || bits !== 16) throw new Error(`expected 16-bit ${SR} Hz mono, got ${bits}-bit ${rate} Hz ${ch} ch`);
      return Math.min(sz, b.length - p - 8) / (ch * bits / 8) / rate;
    }
    p += 8 + sz + (sz & 1);
  }
  throw new Error('no data chunk');
}

function check() {
  const bad = [];
  let meta = {};
  try { meta = JSON.parse(fs.readFileSync(JSON_FILE, 'utf8')); } catch (e) { bad.push('sfx.json missing or unreadable'); }
  const list = names();
  for (const n of list) {
    const f = path.join(OUT, n + '.wav');
    if (!fs.existsSync(f)) { bad.push(n + ': missing ' + n + '.wav'); continue; }
    if (!meta[n]) { bad.push(n + ': no sfx.json entry'); continue; }
    try {
      const s = wavSeconds(f);
      if (Math.abs(s - meta[n].dur) > 0.001) bad.push(`${n}: WAV is ${s.toFixed(4)} s, sfx.json says ${meta[n].dur}`);
    } catch (e) { bad.push(n + ': ' + e.message); }
  }
  if (bad.length) { console.log('sfx check FAILED:\n  ' + bad.join('\n  ')); return false; }
  console.log(`sfx ok: ${list.length} WAVs match sfx.json`);
  return true;
}

async function render() {
  process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-sfx-' + process.pid;
  const srv = require('../server');
  const { chromium } = require('playwright');
  await srv.start(0);
  const url = 'http://127.0.0.1:' + srv.server.address().port + '/';
  const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined });
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 120000 });
  fs.mkdirSync(OUT, { recursive: true });
  const meta = {};
  for (const name of names()) {
    const res = await page.evaluate(async ({ name, SR, LEN, START, SILENCE, KEEP }) => {
      const { SOUNDS, SoundManager } = __wobbleSound, snd = SOUNDS[name];
      if (!snd) return { err: 'no SOUNDS entry ' + name };
      let seed = 0x5eed1234; const real = Math.random, vary = snd.vary;
      Math.random = () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed); x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
      snd.vary = 0;
      try {
        const oc = new OfflineAudioContext(2, SR * LEN, SR), m = new SoundManager(), RealAC = window.AudioContext;
        window.AudioContext = function () { return oc; }; try { m.init(); } finally { window.AudioContext = RealAC; }
        m.setMasterVolume(1); Object.defineProperty(m, 'ready', { get: () => true });
        if (!m.play(name, { delay: 0.5 })) return { err: 'play returned null' };
        const buf = await oc.startRendering(), L = buf.getChannelData(0), R = buf.getChannelData(1);
        const s0 = Math.round(START * SR), n = L.length - s0, mono = new Float32Array(n);
        let last = 0, pk = 0;
        for (let i = 0; i < n; i++) { const v = (L[s0 + i] + R[s0 + i]) / 2; mono[i] = v; const a = Math.abs(v); if (a > pk) pk = a; if (a >= SILENCE) last = i; }
        const len = Math.min(n, last + 1 + Math.round(KEEP * SR)), out = new Int16Array(len);
        for (let i = 0; i < len; i++) out[i] = Math.round(Math.max(-1, Math.min(1, mono[i])) * 32767);
        let bin = ''; const u8 = new Uint8Array(out.buffer); for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
        return { b64: btoa(bin), pk, len };
      } finally { Math.random = real; snd.vary = vary; }
    }, { name, SR, LEN, START, SILENCE, KEEP });
    if (res.err) throw new Error(name + ': ' + res.err);
    const pcm = new Int16Array(new Uint8Array(Buffer.from(res.b64, 'base64')).buffer);
    fs.writeFileSync(path.join(OUT, name + '.wav'), wavBuffer(pcm));
    meta[name] = { dur: +(pcm.length / SR).toFixed(4), peak: +res.pk.toFixed(3) };
    console.log(name.padEnd(10), meta[name].dur.toFixed(4).padStart(7) + ' s', 'peak', meta[name].peak.toFixed(3));
  }
  fs.writeFileSync(JSON_FILE, JSON.stringify(meta, null, 2) + '\n');
  await browser.close(); srv.server.close();
}

if (require.main === module) {
  if (process.argv.includes('--check')) process.exit(check() ? 0 : 1);
  render().then(() => process.exit(0), e => { console.error(e); process.exit(1); });
}
module.exports = { names, wavSeconds, check };
