'use strict';
/* Godot title text-fit audit (godot/tests/title_fit_test.gd, tests/fit_audit.gd): every language of Lang.LANGS at eight window sizes,
   the title idle / Construction / opened showcase, plus the wizard, Settings, Goals, the online panel, results and pause at two:
   no text wider or taller than its control, cropped, overlapping, buttons >= 44 pt.
   Needs Godot (GODOT env var or the macOS default). Run: npm run test:godot-title-fit [-- --lang=ja --size=852x393]
   The run prints the phase it is in ("FITAT <seconds> <lang> <phase>"). It never hangs a CI job: one language over its budget
   (FIT_LANG_BUDGET_S, default 90 s) fails inside Godot, and the whole run is killed after FIT_TIMEOUT_S (default 300 s); both
   name the phase that was running. */
const { spawn, spawnSync } = require('child_process');
const { isFatal } = require('./godot-log');
const path = require('path');
const GODOT = process.env.GODOT || '/Applications/Godot_4.8-beta4.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const TIMEOUT_S = Number(process.env.FIT_TIMEOUT_S || 300);
spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });
const extra = process.argv.slice(2);
const t0 = Date.now();
const p = spawn(GODOT, ['--headless', '--path', DIR, '--script', 'res://tests/title_fit_test.gd', '--', '--no-save', ...extra]);
let out = '';
let phase = '(not started)';
let timedOut = false;
const take = (d) => {
  out += d;
  const m = out.slice(-4000).match(/^FITAT .*$/gm);
  if (m) phase = m[m.length - 1];
};
p.stdout.setEncoding('utf8').on('data', take);
p.stderr.setEncoding('utf8').on('data', take);
const timer = setTimeout(() => { timedOut = true; p.kill('SIGKILL'); }, TIMEOUT_S * 1000);
p.on('close', (status, signal) => {
  clearTimeout(timer);
  const secs = ((Date.now() - t0) / 1000).toFixed(1);
  console.log(out.split('\n').filter(l => /^(FIT(?!AT)|FAIL)|SCRIPT ERROR/.test(l)).join('\n'));
  const errors = (out.match(/^ERROR/gm) || []).length;
  if (errors) console.log(`${errors} engine ERROR line(s) (not fatal by themselves, see tools/godot-log.js), first: ${out.split('\n').filter(l => /^ERROR/.test(l)).slice(0, 3).join(' | ')}`);
  if (timedOut) console.log(`title_fit_test TIMED OUT after ${TIMEOUT_S} s (FIT_TIMEOUT_S), last phase: ${phase}`);
  if (timedOut || status !== 0 || !/^FIT ok/m.test(out) || isFatal(out)) {
    console.log(`title_fit_test FAILED (exit ${status}, signal ${signal || 'none'}, ${secs} s, last phase: ${phase})`);
    if (!/^FIT (ok|failed)/m.test(out)) console.log(out.trim().split('\n').filter(l => !/^FITAT/.test(l)).slice(-40).join('\n'));
    process.exit(1);
  }
  console.log(`godot title fit passes (${secs} s)`);
});
