'use strict';
/*
  Exports the game's content tables from public/index.html into shared/*.json so other clients (the Godot iOS app) read the same numbers.
  The web game keeps its own copy in index.html (no behaviour change); `npm run content:check` fails when shared/ is out of date.

  node tools/export-content.js          write shared/*.json
  node tools/export-content.js --check  exit 1 if shared/*.json differ from the game file
*/
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ROOT = path.join(__dirname, '..');
const SRC = fs.readFileSync(path.join(ROOT, 'public', 'index.html'), 'utf8');

function grab(name) {                                   // the source text of `const NAME = <value>;` (brace matching, string aware)
  const m = new RegExp('^const ' + name + '\\s*=\\s*', 'm').exec(SRC);
  if (!m) throw new Error('not found: ' + name);
  let i = m.index + m[0].length; const start = i;
  let depth = 0, q = null;
  for (; i < SRC.length; i++) {
    const c = SRC[i];
    if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; }
    if (c === '\'' || c === '"' || c === '`') { q = c; continue; }
    if (c === '/' && SRC[i + 1] === '/') { while (SRC[i] !== '\n') i++; continue; }
    if (c === '{' || c === '[' || c === '(') depth++;
    else if (c === '}' || c === ']' || c === ')') depth--;
    else if (c === ';' && depth === 0) break;
  }
  return SRC.slice(start, i);
}
const ctx = vm.createContext({});
const get = (name, deps) => vm.runInContext((deps || '') + '(' + grab(name) + ')', ctx);

const WEAPONS = get('WEAPONS');
const MELEE_KEYS = get('MELEE_KEYS'), GUN_KEYS = get('GUN_KEYS');
const modesRaw = vm.runInContext('const MELEE_KEYS=' + JSON.stringify(MELEE_KEYS) + ',GUN_KEYS=' + JSON.stringify(GUN_KEYS) + ';(' + grab('MODES') + ')', ctx);
const wkeys = Object.keys(WEAPONS);
const plain = (o, name) => { const out = {}; for (const k of Object.keys(o)) { const v = o[k]; if (typeof v === 'function') continue; out[k] = v; } return out; };

const modes = {};
for (const id of Object.keys(modesRaw)) {
  const m = modesRaw[id]; const e = plain(m);
  if (typeof m.allow === 'function') e.allowWeapons = wkeys.filter(k => { try { return !!m.allow(k); } catch (x) { return false; } });
  modes[id] = e;
}
const weapons = {}; for (const k of wkeys) weapons[k] = plain(WEAPONS[k]);

// crate drops (pickCrateKey / spawnDrop ~6086): weights after the DROP_BASE overrides, rarity multipliers, power-up/heal
// labels, and per mode which drop keys MODES[m].allow lets through (power-ups follow PU_MODE, like the wrapper at ~3414)
const dropCode = (() => { const a = SRC.indexOf('const DROP_BASE = {};'), b = SRC.indexOf('const CRATE_MULT'); if (a < 0 || b < a) throw new Error('DROP_BASE block not found'); return SRC.slice(a, b); })();
const DROP_BASE = vm.runInContext('const DROP_POOL = ' + grab('DROP_POOL') + ';\n' + dropCode + 'DROP_BASE', vm.createContext({}));
const PU_MODE = get('PU_MODE');
const dropAllow = {};
for (const id of Object.keys(modesRaw)) dropAllow[id] = Object.keys(DROP_BASE).filter(k => (k === 'speed' || k === 'rage' || k === 'shield') ? (PU_MODE[id] ? PU_MODE[id].includes(k) : true) : (() => { try { return !!modesRaw[id].allow(k); } catch (x) { return false; } })());
const drops = { base: DROP_BASE, mult: get('CRATE_MULT'), heal: get('HEAL_META'), powerups: get('PU_META'), allow: dropAllow };

const out = {
  'weapons.json': weapons,
  'drops.json': drops,
  'modes.json': modes,
  'difficulties.json': get('DIFFS'),
  'crate-rates.json': get('CRATE_RATE'),
  'classes.json': get('CLASSES'),
  'cosmetics.json': { hats: get('HATS'), swatch: get('SWATCH'), skins: get('SKINS') },
};

const mp = require('./export-maps')();
if (mp.problems.length) { console.error('map export problems:\n' + mp.problems.join('\n')); process.exit(1); }
out['maps.json'] = mp.maps;

// numbers are rounded to 6 decimals when written: Math.sin/cos differ in the last digit between Node versions, and the check must pass on any of them
const check = process.argv.includes('--check');
let bad = 0;
fs.mkdirSync(path.join(ROOT, 'shared'), { recursive: true });
for (const f of Object.keys(out)) {
  const text = JSON.stringify(out[f], (k, v) => (typeof v === 'number' && !Number.isInteger(v) ? Math.round(v * 1e6) / 1e6 : v), 1) + '\n', p = path.join(ROOT, 'shared', f);
  if (check) { let cur = ''; try { cur = fs.readFileSync(p, 'utf8'); } catch (e) { /* missing */ } if (cur !== text) { console.error('out of date: shared/' + f); bad++; } }
  else { fs.writeFileSync(p, text); console.log('wrote shared/' + f + ' (' + Object.keys(out[f]).length + ' entries)'); }
}
if (check) { if (bad) { console.error('Run: npm run content'); process.exit(1); } console.log('shared/ is up to date'); }
