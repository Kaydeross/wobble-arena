'use strict';
/* Godot server-identity + leaderboard client test (npm run test:godot-ranking, see the package.json line to add):
     "test:godot-ranking": "node tools/test-ranking.js"
   Runs godot/tests/ranking_test.gd headless (no server, no network): ServerInfo classifies Official / Local / Custom
   URLs and explains a wrong-server room code; the ServerBadge chip; the RankingSheet builds rows with mock entries
   (rank/name/score/when, the "you" highlight), switches tabs, shows loading/empty/error states and names the server; the
   Kids-mode note and the guards that refuse a Kids-mode or signed-out ranking submit before it reaches the network.
   Needs Godot (GODOT env var or the macOS default). */
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const assert = require('assert');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');

(async () => {
  // registers class_name scripts (ServerInfo, ServerBadge, RankingSheet, AccountApi) and their .uid files
  spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });
  const r = await new Promise(res => {
    const p = spawn(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/ranking_test.gd', '--', '--no-save']);
    let o = '';
    p.stdout.on('data', d => { o += d; });
    p.stderr.on('data', d => { o += d; });
    const tm = setTimeout(() => p.kill(), 180000);
    p.on('close', c => { clearTimeout(tm); res({ status: c, stdout: o }); });
  });
  const out = r.stdout;
  const lines = out.split('\n').filter(l => /^(ok |FAIL|RANKING)|SCRIPT ERROR|^ERROR|Parse Error/.test(l));
  console.log(lines.join('\n'));
  const failed = lines.filter(l => /^FAIL |SCRIPT ERROR|^ERROR|Parse Error/.test(l));
  let ok = r.status === 0 && /^RANKING ok/m.test(out) && failed.length === 0;
  if (!ok && !lines.length) console.log(out.slice(0, 4000));
  assert.ok(ok, 'godot ranking test failed (exit ' + r.status + ')' + (failed.length ? ': ' + failed[0] : ''));
  console.log('godot ranking test passes');
  process.exit(0);
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
