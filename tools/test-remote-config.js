'use strict';
/* Headless policy/config test: bundled fallback, malformed remote values, semver gate and ad caps. Starts the real server
   and checks /api/config. Run: npm run test:godot-remote-config */
const { spawnSync } = require('child_process');
const path = require('path');
const srv = require('../server');
(async () => {
  const server = await srv.start(0);
  const url = 'http://127.0.0.1:' + server.address().port;
  const cfg = await (await fetch(url + '/api/config')).json();
  if (!cfg || cfg.schema !== 1 || typeof cfg.ads !== 'object') throw new Error('/api/config did not return a config object');
  // tester_unlock: false by default, a real boolean on the wire, and the TESTER_UNLOCK environment variable overrides the file
  const had = process.env.TESTER_UNLOCK;
  delete process.env.TESTER_UNLOCK;
  if (cfg.tester_unlock !== false) throw new Error('/api/config tester_unlock must default to false');
  for (const [env, want] of [['1', true], ['true', true], ['yes', true], ['0', false], ['nope', false]]) {
    process.env.TESTER_UNLOCK = env;
    const c = await (await fetch(url + '/api/config')).json();
    if (c.tester_unlock !== want) throw new Error('TESTER_UNLOCK=' + env + ' should give tester_unlock ' + want);
  }
  if (had === undefined) delete process.env.TESTER_UNLOCK; else process.env.TESTER_UNLOCK = had;
  const godot = process.env.GODOT || 'godot';
  const r = spawnSync(godot, ['--headless', '--path', path.join(__dirname, '..', 'godot'), '--script', 'res://tests/remote_config_test.gd', '--', '--no-save'], { encoding: 'utf8', timeout: 60000 });
  const out = (r.stdout || '') + (r.stderr || '');
  process.stdout.write(out);
  if (r.status !== 0 || !/^REMOTE_CONFIG ok/m.test(out)) throw new Error('remote config test failed');
  console.log('remote config test passes');
  await srv.stop();
})().catch(async e => { console.error('FAIL', e); try { await srv.stop(); } catch (_) {} process.exit(1); });
