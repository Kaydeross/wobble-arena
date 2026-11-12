'use strict';
/* Practice Range / Test Map in Godot (godot/logic/practice_range.gd, docs/COMBAT_PORTING.md):
   1. parity: the web game's real rangeBot (sliced out of public/index.html) drives the ten Practice Range dummies over a
      scripted 12 s (the player walks about, dummies get K.O.'d / knocked down in windows, the movers slide on their paths;
      positions integrate wish * speed * dt the same way on both sides) vs PracticeRange.range_bot in
      godot/tests/range_test.gd: wish, facing, speed, mover clock, every step.
   2. matches: godot/tests/range_test.gd plays the Practice Range mode headless: 10 Wobbler dummies on their spots that
      never fight back, the movers move and the still ones stay, a K.O.'d dummy pops back up at home, the weapon rack
      (12 on the Practice Range, every weapon on the Test Map) can be picked up and comes back, and a range map forces
      its dummies in Classic too.
   npm run test:godot-range */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path'), vm = require('vm');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const ROOT = path.join(__dirname, '..'), GD = path.join(ROOT, 'godot');
const SRC = fs.readFileSync(path.join(ROOT, 'public', 'index.html'), 'utf8');
function block(startRe) {                                    // from the match to the end of the brace block that follows
  const m = startRe.exec(SRC); if (!m) throw new Error('not found ' + startRe);
  let i = SRC.indexOf('{', m.index + m[0].length - 1), depth = 0, q = null;
  for (; i < SRC.length; i++) {
    const c = SRC[i];
    if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; }
    if (c === '\'' || c === '"' || c === '`') { q = c; continue; }
    if (c === '/' && SRC[i + 1] === '/') { while (SRC[i] !== '\n') i++; continue; }
    if (c === '{') depth++; else if (c === '}') { depth--; if (depth === 0) return SRC.slice(m.index, i + 1); }
  }
}

const DT = 1 / 120, STEPS = 1440;
function rangeTrace() {
  const maps = JSON.parse(fs.readFileSync(path.join(ROOT, 'shared', 'maps.json'), 'utf8'));
  const m = maps.practice;
  const vec = () => ({ x: 0, y: 0, z: 0, set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; }, normalize() { return this; } });
  const mk = (x, z) => ({ pos: { x, y: 0, z }, wish: vec(), aimTarget: vec(), yaw: 0, faceYaw: 0, dead: false, downT: 0, mt: 0, speed: 2.2, swing: -1, target: null, wantJump: true, stiff: 0 });
  const player = mk(m.player[0], m.player[1]);
  const bots = m.bots.map(b => mk(b[0], b[1]));
  const ctx = vm.createContext({ Math, MAPS: { practice: m }, currentMap: 'practice', bots, player });
  vm.runInContext(block(/^function rangeBot\(b, dt\) /m) + '\nglobalThis.rangeBot = rangeBot;', ctx);
  const rows = [];
  for (let k = 0; k < STEPS; k++) {
    const t = k * DT;
    player.pos.x = Math.sin(t * 0.7) * 12; player.pos.z = 14 - t * 2.5;            // the player walks down the range
    bots.forEach((b, i) => {
      b.dead = (i === 6 && k >= 300 && k < 450) || (i === 2 && k >= 800 && k < 1000);   // K.O.'d: no turning, no sliding
      b.downT = (i === 8 && k >= 500 && k < 620) ? 0.5 : 0;                            // knocked down
      b.yaw = b.faceYaw;
      ctx.rangeBot(b, DT);
      b.pos.x += b.wish.x * b.speed * DT; b.pos.z += b.wish.z * b.speed * DT;
    });
    rows.push([player.pos.x, player.pos.z, bots.map(b => [b.wish.x, b.wish.z, b.faceYaw, b.speed, b.mt, b.pos.x, b.pos.z, b.dead ? 1 : 0, b.downT, b.swing, b.wantJump ? 1 : 0])]);
  }
  return rows;
}

spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 180000 });   // registers class_name scripts
const tf = path.join(os.tmpdir(), 'wa-range-' + process.pid + '.json');
fs.writeFileSync(tf, JSON.stringify({ dt: DT, rows: rangeTrace() }));
const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/range_test.gd', '--', '--no-save', tf], { encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
fs.unlinkSync(tf);
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(PARITY|FIRST|RANGE|NODES|FAIL)/.test(l) || /SCRIPT ERROR|Parse Error|leaked/i.test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^RANGE ok/m.test(out) && !lines.some(l => /SCRIPT ERROR|Parse Error|leaked|^FAIL/i.test(l));
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot range test FAILED'); process.exit(1); }
console.log('godot range test passes');
