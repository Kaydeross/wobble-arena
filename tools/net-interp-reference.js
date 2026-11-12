'use strict';
/* Reference for the ghost interpolation of the web game's netStep (public/index.html, the lines from
   `const age = Math.min(0.2` to `g.pos.z += ...`): sliced from the real file and run on a scripted snapshot stream
   (steady run, jump with vy, a jittery arrival pattern, a > 6 m teleport, a stale snapshot past 0.2 s).
   Writes {dt, steps: [{snap|null}], expect: [[x, y, z], ...]} as JSON to the path in argv[2] (stdout without one). */
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8').split('\n');
const a = src.findIndex(l => l.includes('const age = Math.min(0.2, Math.max(0, net.clock - (s.rt || 0)))'));
const b = src.findIndex((l, i) => i > a && l.includes('g.pos.z += (tz - g.pos.z) * k'));
if (a < 0 || b < 0 || b - a > 4) throw new Error('netStep interpolation lines not found in public/index.html');
const body = src.slice(a, b + 1).map(l => l.replace(/\/\/.*$/, '')).join('\n');
const step = new Function('net', 'g', 's', 'dt', body);   // eslint-disable-line no-new-func

const dt = 1 / 120, N = 720;
const steps = [], expect = [];
const net = { clock: 0 }, g = { pos: { x: 0, y: 0, z: 0 } };
let s = null;
for (let i = 0; i < N; i++) {
  const t = i * dt;
  let snap = null;
  const every = i < 240 ? 4 : i < 480 ? (i % 7 === 0 ? 3 : 5) : 4;          // 30 Hz, then jittery arrivals
  if (i % every === 0 && !(i >= 560 && i < 620)) {                          // 0.5 s without snapshots: prediction caps at 0.2 s
    const tele = i >= 400 && i < 420;                                        // a respawn far away: snap
    const air = i >= 300 && i < 360;
    snap = { x: +(tele ? 20 : 3 * Math.cos(t)).toFixed(2), y: +(air ? 1.5 + Math.sin((i - 300) / 60 * Math.PI) : 0).toFixed(2), z: +(tele ? -15 : 4 * t - 3).toFixed(2),
      vx: +(-3 * Math.sin(t)).toFixed(2), vy: air ? +(6 * Math.cos((i - 300) / 60 * Math.PI)).toFixed(2) : 0, vz: 4, g: air ? 0 : 1 };
  }
  if (snap) s = Object.assign({}, snap, { rt: net.clock });                // netHandle stamps the arrival time
  steps.push(snap);
  net.clock += dt;                                                          // netStep
  if (s) step(net, g, s, dt);
  expect.push([g.pos.x, g.pos.y, g.pos.z]);
}
const out = JSON.stringify({ dt, steps, expect });
if (process.argv[2]) fs.writeFileSync(process.argv[2], out); else process.stdout.write(out);
