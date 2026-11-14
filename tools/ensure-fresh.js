'use strict';
/* Preflight for local Godot checks: fetch origin and refuse to run on a checkout that is behind origin/main
   (stale code, stale screenshots), and wipe the Godot import cache when HEAD changed since the last run.
   Skip with FRESH_OK=1 (CI does not need it: it always checks out the tip). */
const { spawnSync } = require('child_process');
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const git = (...a) => spawnSync('git', a, { cwd: ROOT, encoding: 'utf8' });
module.exports = function ensureFresh() {
  if (process.env.CI || process.env.FRESH_OK === '1') return;
  const full = git('rev-parse', 'HEAD').stdout.trim();
  const head = full.slice(0, 7);
  const ref = git('rev-parse', '--abbrev-ref', 'HEAD').stdout.trim();
  const branch = ref && ref !== 'HEAD' ? ref : 'detached';
  // A failed fetch (offline, no origin) must not block local work, but it also means freshness cannot be checked.
  const fetch = git('fetch', '--quiet', 'origin', 'main');
  if (fetch.status !== 0) {
    const why = (fetch.stderr || '').trim().split('\n')[0] || 'no network?';
    console.warn(`fresh check: could not fetch origin/main (${why}); freshness of ${branch}@${head} is not verified.`);
  }
  const counted = parseInt(git('rev-list', '--count', 'HEAD..origin/main').stdout, 10);
  const behind = Number.isFinite(counted) ? counted : 0;     // no origin/main (localhost only): nothing to compare against
  if (behind > 0) {
    console.error(`STALE BUILD: ${branch}@${head} is ${behind} commit(s) behind origin/main. Merge/rebase first (git merge origin/main), or set FRESH_OK=1 to override.`);
    process.exit(2);
  }
  const stamp = path.join(ROOT, 'godot', '.godot', '.last-checked-head');
  let prev = ''; try { prev = fs.readFileSync(stamp, 'utf8'); } catch (e) {}
  if (prev !== full) {
    for (const d of ['imported', 'shader_cache']) fs.rmSync(path.join(ROOT, 'godot', '.godot', d), { recursive: true, force: true });
    try { fs.writeFileSync(stamp, full); } catch (e) {}
  }
  console.log(`fresh check: running on ${branch}@${head} (up to date with origin/main)`);
};
