'use strict';
/* Godot maps audit: every map in godot/data/maps.json (plus the generated custom level) builds, matches the web
   export (solids, ladders, pads), has its spawns on solid ground and its web decor / look; custom levels match the web
   game's MAPS.custom.build for a few settings; every wizard mode lists only real, allowed maps.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-maps   (--verbose prints the AUDIT table) */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path'), vm = require('vm');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const ROOT = path.join(__dirname, '..'), DIR = path.join(ROOT, 'godot');
const verbose = process.argv.includes('--verbose');

// the web game's custom level generator, run on stubs
function customRef(cfgs) {
  const SRC = fs.readFileSync(path.join(ROOT, 'public', 'index.html'), 'utf8');
  const a = SRC.indexOf('const ringPts = '), a2 = SRC.indexOf('\n', a);
  const b = SRC.indexOf('const CUSTOM_THEMES = {'), c = SRC.indexOf('for (const [k, c] of Object.entries({ arena:', b);
  if (a < 0 || b < 0 || c < 0) throw new Error('MAPS.custom not found in public/index.html');
  const src = SRC.slice(a, a2) + '\n' + SRC.slice(b, c).replace(/^MAPS\.custom = /m, 'var CUSTOM = ').replace(/^let blockRefs/m, 'var blockRefs') + '\nCUSTOM;';
  return cfgs.map(cc => {
    const rec = { boxes: [], pads: [] };
    const ctx = vm.createContext({
      Math, Object, Array, Set,
      addBox: (x, z, w, d, h, color, y = 0) => { rec.boxes.push({ x, z, w, d, h, y, color }); return {}; },
      addFloorPad: () => ({}), addBouncePad: (x, z) => rec.pads.push({ x, z }),
      solids: [], scene: { remove() {} }, mapObjs: [], solidMeshes: [], cfg: { custom: cc, blocks: [] },
    });
    const m = vm.runInContext(src, ctx);
    m.build();
    return { cfg: cc, boxes: rec.boxes, pads: rec.pads, spawns: m.spawns, grip: m.grip !== undefined };
  });
}

const cfgs = [{}, { size: 60, theme: 'desert', obs: 16, plat: 6, pads: 5, walls: 6, seed: 123 }, { size: 32, theme: 'night', obs: 4, plat: 1, pads: 1, walls: 2, ice: true, seed: 99991 }];
const ref = path.join(os.tmpdir(), 'wa-custom-ref-' + process.pid + '.json');
fs.writeFileSync(ref, JSON.stringify(customRef(cfgs)));
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });
const r = spawnSync(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/maps_test.gd', '--', '--no-save', '--ref', ref], { encoding: 'utf8', timeout: 240000 });
fs.unlinkSync(ref);
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => (verbose ? /^(AUDIT|CUSTOM|MODE|MAPS|FAIL)|ERROR/ : /^(CUSTOM|MAPS|FAIL)|ERROR/).test(l));
console.log(lines.join('\n'));
const ok = r.status === 0 && /^MAPS ok/m.test(out) && !/SCRIPT ERROR|^ERROR/m.test(out);
if (!ok) { if (!lines.length) console.log(out.slice(0, 3000)); console.log('godot maps test FAILED'); process.exit(1); }
console.log('godot maps test passes');
