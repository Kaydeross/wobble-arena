'use strict';
/*
  Translations for the Godot client (docs/I18N.md).

  The sources are godot/i18n/src/*.json: { "English text": { "zh_TW": "...", "zh_CN": "...", "ja": "...", "fr": "...", "es": "..." } }.
  The game loads one merged file, godot/i18n/strings.json (autoload Lang).

  node tools/i18n.js           merge src/*.json -> strings.json (and validate)
  node tools/i18n.js --check   exit 1 if strings.json is out of date or an entry is invalid (part of npm test)
  node tools/i18n.js --file=NAME.json   validate one source file only (no output written)
  node tools/i18n.js --scan    list text in the code that has no translation yet (advisory; exit 0)
  node tools/i18n.js --scan --strict   the same, but exit 1 when a tr("...") / TranslationServer.translate("...") key is missing
*/
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const GODOT = path.join(ROOT, 'godot');
const SRC = path.join(GODOT, 'i18n', 'src');
const OUT = path.join(GODOT, 'i18n', 'strings.json');
const LANGS = ['zh_TW', 'zh_CN', 'ja', 'fr', 'es'];
const args = process.argv.slice(2);
const check = args.includes('--check'), scan = args.includes('--scan'), strict = args.includes('--strict');

// printf-style placeholders in order ("%d", "%s", "%.1f", "%02d", "%%"); GDScript's % operator is positional, so every
// language must keep them in the same order.
const holes = s => (s.match(/%[-+ 0#]*\d*(?:\.\d+)?[sdfxXc%]/g) || []).filter(h => h !== '%%');
const braces = s => (s.match(/\{[A-Za-z_][A-Za-z0-9_]*\}/g) || []).sort();

function load() {
  const merged = {}, errors = [], dupes = [];
  const only = (args.find(a => a.startsWith('--file=')) || '').slice(7);
  const files = only ? [only] : fs.existsSync(SRC) ? fs.readdirSync(SRC).filter(f => f.endsWith('.json')).sort() : [];
  for (const f of files) {
    let d;
    try { d = JSON.parse(fs.readFileSync(path.join(SRC, f), 'utf8')); } catch (e) { errors.push(`${f}: ${e.message}`); continue; }
    for (const [k, v] of Object.entries(d)) {
      if (k in merged) { if (JSON.stringify(merged[k]) !== JSON.stringify(v)) dupes.push(`${f}: "${k}" is also in an earlier file (that one wins)`); continue; }
      merged[k] = v;
    }
  }
  for (const [k, v] of Object.entries(merged)) {
    if (typeof v !== 'object' || v === null) { errors.push(`"${k}": not an object`); continue; }
    for (const l of LANGS) {
      const t = v[l];
      if (typeof t !== 'string' || t.trim() === '') { errors.push(`"${k}": missing ${l}`); continue; }
      if (holes(t).join(' ') !== holes(k).join(' ')) errors.push(`"${k}": ${l} has different % placeholders: "${t}"`);
      if (braces(t).join() !== braces(k).join()) errors.push(`"${k}": ${l} has different {names}: "${t}"`);
      if ((t.match(/\n/g) || []).length !== (k.match(/\n/g) || []).length) errors.push(`"${k}": ${l} has a different number of line breaks`);
    }
    for (const l of Object.keys(v)) if (!LANGS.includes(l)) errors.push(`"${k}": unknown language ${l}`);
  }
  return { merged, errors, files, dupes };
}

function serialise(merged) {
  const out = {};
  for (const k of Object.keys(merged).sort()) { out[k] = {}; for (const l of LANGS) out[k][l] = merged[k][l]; }
  return JSON.stringify(out, null, 1) + '\n';
}

function gdFiles(dir, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'tests' && e.name !== '.godot') gdFiles(p, acc); }
    else if (e.name.endsWith('.gd')) acc.push(p);
  }
  return acc;
}
const unesc = s => s.replace(/\\(.)/g, (m, c) => ({ n: '\n', t: '\t', '"': '"', "'": "'", '\\': '\\' }[c] ?? c));
const STR = '"((?:[^"\\\\\\n]|\\\\.)*)"';

function doScan(merged) {
  const missingKeys = [], missingText = [];
  const keyRe = new RegExp('(?:\\btr|\\batr|TranslationServer\\.translate)\\(\\s*' + STR, 'g');
  const textRe = new RegExp('\\b(?:text|tooltip_text|placeholder_text|title)\\s*=\\s*' + STR, 'g');
  for (const f of gdFiles(GODOT)) {
    const rel = path.relative(GODOT, f);
    const lines = fs.readFileSync(f, 'utf8').split('\n');
    lines.forEach((line, i) => {
      const code = line.replace(/\s#.*$/, '');
      for (const m of code.matchAll(keyRe)) { const k = unesc(m[1]); if (!(k in merged)) missingKeys.push(`${rel}:${i + 1}  ${JSON.stringify(k)}`); }
      for (const m of code.matchAll(textRe)) {
        const k = unesc(m[1]);
        if (!/[A-Za-z]{2,}/.test(k) || k in merged || /^[A-Za-z0-9_\/. -]+$/.test(k) && !/ /.test(k) && k === k.toLowerCase()) continue;
        missingText.push(`${rel}:${i + 1}  ${JSON.stringify(k)}`);
      }
    });
  }
  if (missingKeys.length) console.log(`tr() keys with no translation (${missingKeys.length}):\n  ` + missingKeys.join('\n  '));
  if (missingText.length) console.log(`.text literals with no translation (${missingText.length}, advisory):\n  ` + missingText.join('\n  '));
  if (!missingKeys.length && !missingText.length) console.log('every tr() key and text literal has a translation');
  return missingKeys.length;
}

const { merged, errors, files, dupes } = load();
if (dupes.length) console.warn(dupes.join('\n'));
if (errors.length) { console.error(errors.slice(0, 60).join('\n') + (errors.length > 60 ? `\n... and ${errors.length - 60} more` : '')); }
if (scan) {
  const n = doScan(merged);
  process.exit(strict && (n || errors.length) ? 1 : 0);
}
if (args.some(a => a.startsWith('--file='))) {
  if (errors.length) process.exit(1);
  console.log(`${args.find(a => a.startsWith('--file='))}: ${Object.keys(merged).length} strings ok`);
  process.exit(0);
}
const text = serialise(merged);
if (check) {
  let cur = ''; try { cur = fs.readFileSync(OUT, 'utf8'); } catch (e) { /* missing */ }
  let bad = errors.length;
  if (cur !== text) { console.error('godot/i18n/strings.json is out of date. Run: npm run i18n'); bad++; }
  if (bad) process.exit(1);
  console.log(`translations ok: ${Object.keys(merged).length} strings x ${LANGS.length} languages (${files.length} files)`);
} else {
  if (errors.length) process.exit(1);
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, text);
  console.log(`wrote godot/i18n/strings.json: ${Object.keys(merged).length} strings x ${LANGS.length} languages`);
}
