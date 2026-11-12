'use strict';
/* Sandbox (build mode) test: godot/logic/sandbox_layout.gd + godot/ui/build_hud.gd + the custom arena.
   1. godot/tests/sandbox_test.gd: place / remove / brush / 150 cap / web cleaning / profile round trip, then a headless
      play-through (build with the palette, stand on a block, remove, Play a bot match on the arena, Edit arena).
   2. web parity: the profile blob Godot saved is loaded with the web game's own cfg.custom / cfg.blocks lines
      (taken from public/index.html), and must give the same arena (Godot's extra cfg.blockCols is ignored there).
   npm run test:godot-sandbox */
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const GD = path.join(__dirname, '..', 'godot');
spawnSync(GODOT, ['--headless', '--path', GD, '--import'], { timeout: 180000 });   // registers class_name scripts
const outFile = path.join(os.tmpdir(), 'wa-sandbox-' + process.pid + '.json');
const r = spawnSync(GODOT, ['--headless', '--path', GD, '--script', 'res://tests/sandbox_test.gd', '--', '--no-save', '--out', outFile], { encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
const out = (r.stdout || '') + (r.stderr || '');
const lines = out.split('\n').filter(l => /^(SANDBOX|FAIL)|SCRIPT ERROR|Parse Error|leaked/i.test(l));
let bad = r.status !== 0 || !/^SANDBOX ok/m.test(out) || /SCRIPT ERROR|Parse Error/.test(out);
console.log('godot   ', bad ? 'FAIL' : 'ok'); for (const l of lines.length ? lines : [out.slice(0, 2000)]) console.log('  ' + l);
// web parity: run the web load() lines for cfg.custom and cfg.blocks on Godot's blob
try {
  const html = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
  const lc = html.split('\n').find(l => l.includes('if (d.cfg.custom) {'));
  const lb = html.split('\n').find(l => l.includes('if (Array.isArray(d.cfg.blocks)) cfg.blocks ='));
  const themes = html.match(/const CUSTOM_THEMES = \{([\s\S]*?)\n\};/)[1].match(/^\s*(\w+):/gm).map(s => s.trim().slice(0, -1));
  const d = JSON.parse(fs.readFileSync(outFile, 'utf8'));
  const cfg = { custom: { size: 44, theme: 'grass', obs: 10, plat: 4, pads: 3, walls: 4, ice: false, seed: 7 }, blocks: [] };
  const CUSTOM_THEMES = Object.fromEntries(themes.map(k => [k, {}]));
  new Function('d', 'cfg', 'CUSTOM_THEMES', lc + '\n' + lb)(d, cfg, CUSTOM_THEMES);
  const want = d.cfg.blocks, cols = d.cfg.blockCols;
  const ok = JSON.stringify(cfg.blocks) === JSON.stringify(want) && cfg.blocks.length === 3 && cfg.custom.theme === 'candy' && Array.isArray(cols) && cols.length === want.length;
  console.log('web load', ok ? 'ok' : 'FAIL', '  blocks', JSON.stringify(cfg.blocks), 'theme', cfg.custom.theme, 'blockCols', JSON.stringify(cols));
  if (!ok) bad = true;
} catch (e) { console.log('web load FAIL', e.message); bad = true; }
try { fs.unlinkSync(outFile); } catch (e) { /* none */ }
console.log(bad ? 'godot sandbox test FAILED' : 'godot sandbox test passes');
process.exit(bad ? 1 : 0);
