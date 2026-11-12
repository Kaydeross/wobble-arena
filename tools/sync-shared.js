'use strict';
/*
  Copies shared/*.json (the source of truth) into godot/data/ so the Godot app can read them as res://data/*.json
  (an exported app cannot reach ../shared). godot/data/ is committed.

  node tools/sync-shared.js          copy shared/*.json -> godot/data/
  node tools/sync-shared.js --check  exit 1 if godot/data/ differs from shared/ (part of npm test)
*/
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'shared'), DST = path.join(ROOT, 'godot', 'data');
const check = process.argv.includes('--check');
const files = fs.readdirSync(SRC).filter(f => f.endsWith('.json')).sort();
let bad = 0;
if (!check) fs.mkdirSync(DST, { recursive: true });
for (const f of files) {
  const text = fs.readFileSync(path.join(SRC, f), 'utf8'), p = path.join(DST, f);
  let cur = null; try { cur = fs.readFileSync(p, 'utf8'); } catch (e) { /* missing */ }
  if (check) { if (cur !== text) { console.error('out of date: godot/data/' + f); bad++; } }
  else if (cur !== text) { fs.writeFileSync(p, text); console.log('wrote godot/data/' + f); }
}
const extra = fs.existsSync(DST) ? fs.readdirSync(DST).filter(f => f.endsWith('.json') && !files.includes(f)) : [];
for (const f of extra) {
  if (check) { console.error('not in shared/: godot/data/' + f); bad++; }
  else { fs.unlinkSync(path.join(DST, f)); console.log('removed godot/data/' + f); }
}
if (check) { if (bad) { console.error('Run: npm run sync'); process.exit(1); } console.log('godot/data/ is up to date'); }
