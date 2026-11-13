'use strict';
/* Renders the web game's procedural music (public/index.html SoundManager.note) to seamless Ogg Vorbis loops for the
   Godot client: godot/audio/music/<track>.ogg + music.json ({track: {mood, intensity, bpm, bars, seconds}}).
   Each track is 4 bars of the real scheduler at a fixed mood and intensity, rendered through the real bus graph
   (music bus at full music volume -> compressor -> limiter) in an OfflineAudioContext in Chromium. It renders the
   loop twice and keeps the second pass, so pad releases and arp echoes from the end wrap into the start, and blends
   the render just past the loop into its first 2048 samples: the file loops without a seam. (Chromium's offline render is not bit-exact between runs, so a re-render differs by
   tiny amounts: re-render only when the music changes, and commit the new files.)
   Needs ffmpeg (libvorbis) and Playwright's Chromium (CHROME_PATH to use a specific binary).
   node tools/render-music.js            (npm run music) */
const fs = require('fs'), path = require('path'), os = require('os');
const { spawnSync } = require('child_process');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-music-' + process.pid;
const srv = require('../server');
const { chromium } = require('playwright');

const OUT = path.join(__dirname, '..', 'godot', 'audio', 'music');
const SR = 44100, BARS = 4;
// mood + intensity per track; tempo follows the web formula (match: 112 + 30 * intensity, menu: 88)
const TRACKS = {
  menu: { mood: 'menu', intensity: 0.1 },
  match_low: { mood: 'match', intensity: 0.2 },
  match_mid: { mood: 'match', intensity: 0.5 },
  match_high: { mood: 'match', intensity: 0.85 },
};
const bpmOf = t => t.mood === 'match' ? 112 + t.intensity * 30 : 88;

/** godot/audio/music/<name>.ogg.import: loop on, tempo metadata; keeps the uid of an existing file. */
function writeImport(name, m) {
  const f = path.join(OUT, name + '.ogg.import'), res = 'res://audio/music/' + name + '.ogg';
  const dest = 'res://.godot/imported/' + name + '.ogg-' + require('crypto').createHash('md5').update(res).digest('hex') + '.oggvorbisstr';
  let uid = ''; try { const o = /uid="(uid:\/\/[a-z0-9]+)"/.exec(fs.readFileSync(f, 'utf8')); if (o) uid = o[1]; } catch (e) { /* new file */ }
  if (!uid) { const A = 'abcdefghijklmnopqrstuvwxyz0123456789'; let n = BigInt('0x' + require('crypto').randomBytes(8).toString('hex')) & 0x7fffffffffffffffn; uid = ''; do { uid = A[Number(n % 36n)] + uid; n /= 36n; } while (n > 0n); uid = 'uid://' + uid; }
  fs.writeFileSync(f, `[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\nuid="${uid}"\npath="${dest}"\n\n[deps]\n\nsource_file="${res}"\ndest_files=["${dest}"]\n\n[params]\n\nloop=true\nloop_offset=0.0\nbpm=${m.bpm}\nbeat_count=${m.bars * 4}\nbar_beats=4\n`);
}

(async () => {
  await srv.start(0);
  const url = 'http://127.0.0.1:' + srv.server.address().port + '/';
  const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined });
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 120000 });
  fs.mkdirSync(OUT, { recursive: true });
  const meta = {};
  for (const [name, t] of Object.entries(TRACKS)) {
    const bpm = bpmOf(t), st = 60 / bpm / 4, steps = 16 * BARS, n = Math.round(steps * st * SR);
    const pcm = await page.evaluate(async ({ t, st, steps, n, SR }) => {
      const { SoundManager } = __wobbleSound;
      let seed = 0x5eed1234; const real = Math.random;
      Math.random = () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let x = Math.imul(seed ^ seed >>> 15, 1 | seed); x = x + Math.imul(x ^ x >>> 7, 61 | x) ^ x; return ((x ^ x >>> 14) >>> 0) / 4294967296; };
      try {
        const K = 2048, oc = new OfflineAudioContext(2, n * 2 + K + 64, SR), m = new SoundManager(), RealAC = window.AudioContext;
        window.AudioContext = function () { return oc; }; try { m.init(); } finally { window.AudioContext = RealAC; }
        m.setMasterVolume(1); m.bgmBus.gain.value = 0.34;                     // full music volume (Godot's Music bus scales it)
        m.bgm.mood = t.mood; m.bgm.int = m.bgm.want = t.intensity;
        for (let s = 0; s < steps * 2 + 4; s++) m.note(s, s * st, st);
        const buf = await oc.startRendering(), L = buf.getChannelData(0).slice(n, 2 * n), R = buf.getChannelData(1).slice(n, 2 * n);
        // the seam: what really follows the loop's last sample is the render just past 2n; crossfade it into the
        // loop's first K samples so the wrap lands exactly where the music would have gone
        const L2 = buf.getChannelData(0), R2 = buf.getChannelData(1);
        for (let i = 0; i < K; i++) { const w = i / K; L[i] = L2[2 * n + i] * (1 - w) + L[i] * w; R[i] = R2[2 * n + i] * (1 - w) + R[i] * w; }
        const out = new Int16Array(n * 2); let pk = 0;
        for (let i = 0; i < n; i++) { pk = Math.max(pk, Math.abs(L[i]), Math.abs(R[i])); out[2 * i] = Math.max(-1, Math.min(1, L[i])) * 32767; out[2 * i + 1] = Math.max(-1, Math.min(1, R[i])) * 32767; }
        let bin = ''; const u8 = new Uint8Array(out.buffer); for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
        return { b64: btoa(bin), pk };
      } finally { Math.random = real; }
    }, { t, st, steps, n, SR });
    const raw = path.join(os.tmpdir(), 'wa-music-' + name + '.pcm');
    fs.writeFileSync(raw, Buffer.from(pcm.b64, 'base64'));
    const ogg = path.join(OUT, name + '.ogg');
    const r = spawnSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 's16le', '-ar', String(SR), '-ac', '2', '-i', raw, '-c:a', 'libvorbis', '-q:a', '5', '-map_metadata', '-1', '-fflags', '+bitexact', ogg], { encoding: 'utf8' });
    fs.unlinkSync(raw);
    if (r.status !== 0) throw new Error('ffmpeg failed for ' + name + ': ' + r.stderr);
    meta[name] = { mood: t.mood, intensity: t.intensity, bpm: +bpm.toFixed(3), bars: BARS, seconds: +(n / SR).toFixed(4) };
    console.log(name.padEnd(11), (bpm.toFixed(1) + ' bpm').padEnd(10), (n / SR).toFixed(2) + ' s', 'peak', pcm.pk.toFixed(3), Math.round(fs.statSync(ogg).size / 1024) + ' KB');
  }
  fs.writeFileSync(path.join(OUT, 'music.json'), JSON.stringify(meta, null, 2) + '\n');
  for (const [name, m] of Object.entries(meta)) writeImport(name, m);
  await browser.close(); srv.server.close(); process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
