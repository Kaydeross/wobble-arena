'use strict';
/* Spring2 parity: runs the web game's REAL Spring2 class (sliced out of public/index.html) over a scripted force/target/kick sequence,
   then replays it in Godot (godot/logic/spring.gd). Worst error must be < 1e-6.  npm run test:godot-spring */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path'), vm = require('vm');
const SRC = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
function block(startRe) {                                    // from the match to the end of the brace block that follows (same slicer as physics-reference.js)
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
const ctx = vm.createContext({});
vm.runInContext(block(/^class Spring2 /m) + '\nglobalThis.Spring2 = Spring2;', ctx);
// scripted sequence shaped like what Fighter.animate feeds the lean/head springs (stiffness 95/f and 60/f, zeta 0.28/0.2,
// acceleration forces, clamped targets) over each class's wobble, with mixed dt (60 Hz frames, 120 Hz sim, a hitch) plus kicks
const sp = new ctx.Spring2(), rows = [];
let seed = 12345; const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
const WOB = Object.values(JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'shared', 'classes.json'), 'utf8'))).map(c => c.wob);
for (let k = 0; k < 4000; k++) {
  if (k % 97 === 13) { const ix = (rnd() - 0.5) * 8, iy = (rnd() - 0.5) * 8; sp.kick(ix, iy); rows.push([1, ix, iy, sp.x, sp.y, sp.vx, sp.vy]); continue; }
  const dt = k % 500 === 250 ? 0.1 : (k % 3 === 0 ? 1 / 120 : 1 / 60), f = 2.2 * WOB[Math.floor(k / 4000 * WOB.length)];
  const head = k % 2 === 1, kk = (head ? 60 : 95) / f, z = head ? 0.2 : 0.28;
  const a = Math.sin(k * 0.05) * 40 + (rnd() - 0.5) * 30, b = Math.cos(k * 0.031) * 25;
  const tx = head ? 0 : Math.max(-0.45, Math.min(0.45, Math.sin(k * 0.01) * 0.6)), ty = head ? 0 : Math.max(-0.4, Math.min(0.4, Math.cos(k * 0.013) * 0.5));
  const fx = -a * (head ? 0.9 : 0.45), fy = -b * (head ? 0.9 : 0.45);
  sp.step(dt, kk, z, fx, fy, tx, ty); rows.push([0, dt, kk, z, fx, fy, tx, ty, sp.x, sp.y, sp.vx, sp.vy]);
}
const tf = path.join(os.tmpdir(), 'wa-spring-' + process.pid + '.json');
fs.writeFileSync(tf, JSON.stringify(rows));
const gd = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', gd, '--import'], { timeout: 120000 });   // registers class_name scripts
const r = spawnSync(GODOT, ['--headless', '--path', gd, '--script', 'res://tests/spring_test.gd', '--', tf], { encoding: 'utf8', timeout: 60000 });
const out = (r.stdout || '') + (r.stderr || ''), line = out.split('\n').find(l => l.startsWith('SPRING'));
console.log(line || ('no result: ' + out.slice(0, 400)));
const ok = !!line && r.status === 0;
console.log(ok ? 'spring parity ok' : 'FAIL'); process.exit(ok ? 0 : 1);
