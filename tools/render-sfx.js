'use strict';
/* Renders every Godot sound effect (tools/sfx-recipes.js: the web game's original tone / noise SFX table) offline to a
   16-bit 44.1 kHz mono WAV in godot/audio/sfx/<name>.wav. The SFX table is sliced from the real page and run with
   sample-by-sample versions of the WebAudio nodes it uses (see docs/AUDIO.md):
     tone(f0, f1, dur, type, vol, delay): band-limited OscillatorNode (sine/triangle/square/sawtooth, Fourier series
       normalised like WebAudio's built-in waves) with an exponential frequency ramp f0 -> max(20, f1) over dur,
       GainNode vol -> 0.001 exponential ramp over dur, stopped at dur + 0.03.
     noise(dur, vol, freq, delay): the 0.7 s white-noise buffer started at offset 0.15 s (JS: random 0..0.3), through
       a lowpass BiquadFilterNode (Q = 1 dB, Audio EQ Cookbook as in the WebAudio spec), same gain envelope.
   Everything is summed through the master gain (0.9; the player's volume is applied by Godot) and clamped to +-1 like
   the browser's destination. Deterministic (seeded noise), so `--check` can verify the committed WAVs.
   node tools/render-sfx.js [--check]     (--json prints {name: {dur, peak}} for tools/test-audio.js) */
const fs = require('fs'), path = require('path');

const SR = 44100;
const MASTER = 0.9;
const NOISE_LEN = 0.7, NOISE_OFFSET = 0.15;
const OUT = path.join(__dirname, '..', 'godot', 'audio', 'sfx');

/** The SFX table from the web game, as {name: recipe()} taking our tone/noise. */
function loadTable(tone, noise) {
  const html = fs.readFileSync(path.join(__dirname, 'sfx-recipes.js'), 'utf8');
  const a = html.indexOf('const SFX = {');
  const b = html.indexOf('\n};', a);
  if (a < 0 || b < 0) throw new Error('SFX table not found in tools/sfx-recipes.js');
  return new Function('tone', 'noise', html.slice(a, b + 3) + '\nreturn SFX;')(tone, noise);
}

/** Records the calls a recipe makes (no audio). */
function recipeOf(name) {
  const calls = [];
  const SFX = loadTable(
    (f0, f1, dur, type = 'sine', vol = 0.25, delay = 0) => calls.push({ k: 'tone', f0, f1, dur, type, vol, delay }),
    (dur, vol = 0.25, freq = 1500, delay = 0) => calls.push({ k: 'noise', dur, vol, freq, delay }));
  SFX[name]();
  return calls;
}
function names() { return Object.keys(loadTable(() => {}, () => {})); }

/** Length the JS sound lasts: the latest node stop (start + dur + 0.03). The noise source may end earlier when the
    0.7 s buffer runs out (boom); the tone parts are always the longest anyway. */
function jsDuration(calls) {
  let end = 0;
  for (const c of calls) end = Math.max(end, c.delay + c.dur + 0.03);
  return end;
}

// Fourier coefficients (sine terms) of WebAudio's built-in periodic waves.
function coef(type, n) {
  switch (type) {
    case 'sine': return n === 1 ? 1 : 0;
    case 'square': return n % 2 ? 4 / (Math.PI * n) : 0;
    case 'sawtooth': return (n % 2 ? 2 : -2) / (Math.PI * n);
    case 'triangle': return n % 2 ? 8 * (((n - 1) / 2) % 2 ? -1 : 1) / (Math.PI * Math.PI * n * n) : 0;
  }
  throw new Error('unknown oscillator type ' + type);
}
const MAXH = 256;
const COEF = {}, NORM = {};
for (const t of ['sine', 'square', 'sawtooth', 'triangle']) {
  COEF[t] = new Float64Array(MAXH + 1);
  for (let n = 1; n <= MAXH; n++) COEF[t][n] = coef(t, n);
  // WebAudio normalises a periodic wave to peak 1: measure the peak of the full series once.
  let pk = 0;
  for (let i = 0; i < 4096; i++) {
    const th = 2 * Math.PI * i / 4096; let v = 0;
    for (let n = 1; n <= MAXH; n++) v += COEF[t][n] * Math.sin(n * th);
    pk = Math.max(pk, Math.abs(v));
  }
  NORM[t] = 1 / pk;
}

const expRamp = (v0, v1, x) => v0 * Math.pow(v1 / v0, Math.min(1, Math.max(0, x)));

function renderTone(buf, c) {
  const start = Math.round(c.delay * SR), len = Math.round((c.dur + 0.03) * SR);
  const f1 = Math.max(20, c.f1), co = COEF[c.type], nm = NORM[c.type];
  let ph = 0;
  for (let i = 0; i < len && start + i < buf.length; i++) {
    const t = i / SR, x = t / c.dur;
    const f = expRamp(c.f0, f1, x);
    const g = expRamp(c.vol, 0.001, x);
    // Band-limited: only harmonics below Nyquist (fade the top one in so the count changing does not click).
    const lim = SR / 2 / f, nh = Math.min(MAXH, Math.floor(lim));
    const th = 2 * Math.PI * ph, s1 = Math.sin(th), c2 = 2 * Math.cos(th);
    let sp = 0, sn = s1, v = 0;
    for (let n = 1; n <= nh; n++) {
      let a = co[n];
      if (n === nh) a *= Math.min(1, lim - nh + 0.0001);
      v += a * sn;
      const nx = c2 * sn - sp; sp = sn; sn = nx;
    }
    buf[start + i] += v * nm * g;
    ph += f / SR; ph -= Math.floor(ph);
  }
}

function lcg(seed) { let s = seed >>> 0; return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; }; }

function renderNoise(buf, c, rnd) {
  const nb = new Float64Array(Math.floor(SR * NOISE_LEN));
  for (let i = 0; i < nb.length; i++) nb[i] = rnd() * 2 - 1;
  // Lowpass biquad, WebAudio flavour: Q in dB.
  const w0 = 2 * Math.PI * c.freq / SR, alpha = Math.sin(w0) / (2 * Math.pow(10, 1 / 20)), cw = Math.cos(w0);
  const a0 = 1 + alpha, b0 = (1 - cw) / 2 / a0, b1 = (1 - cw) / a0, b2 = b0, a1 = -2 * cw / a0, a2 = (1 - alpha) / a0;
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  const start = Math.round(c.delay * SR), off = Math.round(NOISE_OFFSET * SR);
  const len = Math.min(Math.round((c.dur + 0.03) * SR), nb.length - off);
  for (let i = 0; i < len && start + i < buf.length; i++) {
    const x = nb[off + i];
    const y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    buf[start + i] += y * expRamp(c.vol, 0.001, i / SR / c.dur);
  }
}

function render(name) {
  const calls = recipeOf(name);
  const dur = jsDuration(calls);
  const buf = new Float64Array(Math.round(dur * SR));
  let seed = 0;
  for (const ch of name) seed = (seed * 31 + ch.charCodeAt(0)) >>> 0;
  const rnd = lcg(seed || 1);
  for (const c of calls) c.k === 'tone' ? renderTone(buf, c) : renderNoise(buf, c, rnd);
  let peak = 0, clipped = 0;
  for (let i = 0; i < buf.length; i++) {
    let v = buf[i] * MASTER;
    if (Math.abs(v) > 1) { clipped++; v = Math.sign(v); }
    buf[i] = v; peak = Math.max(peak, Math.abs(v));
  }
  return { buf, dur, peak, clipped };
}

function wav(buf) {
  const n = buf.length, b = Buffer.alloc(44 + n * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(SR, 24); b.writeUInt32LE(SR * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
  b.write('data', 36); b.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) b.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(buf[i] * 32767))), 44 + i * 2);
  return b;
}

module.exports = { names, recipeOf, jsDuration, render, SR };

if (require.main === module) {
  const check = process.argv.includes('--check'), json = process.argv.includes('--json');
  const info = {};
  let stale = 0;
  if (!check && !json) fs.mkdirSync(OUT, { recursive: true });
  for (const n of names()) {
    const r = render(n), data = wav(r.buf), file = path.join(OUT, n + '.wav');
    info[n] = { dur: r.dur, peak: r.peak };
    if (check) {
      if (!fs.existsSync(file) || !fs.readFileSync(file).equals(data)) { stale++; console.log('stale:', path.relative(process.cwd(), file)); }
    } else if (!json) {
      fs.writeFileSync(file, data);
      console.log(n.padEnd(9), r.dur.toFixed(3) + ' s', 'peak ' + r.peak.toFixed(3), r.clipped ? r.clipped + ' samples clipped' : '', (data.length / 1024).toFixed(1) + ' KB');
    }
  }
  if (json) console.log(JSON.stringify(info));
  if (check) { if (stale) { console.log('run: node tools/render-sfx.js'); process.exit(1); } console.log('sfx wavs up to date (' + Object.keys(info).length + ')'); }
}
