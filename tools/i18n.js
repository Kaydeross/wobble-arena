'use strict';
/*
  Translations (docs/I18N.md): the Godot client and the web game.

  Sources: godot/i18n/src/*.json (both games) and web-i18n/src/*.json (web-only text):
    { "English text": { "zh_TW": "...", "zh_CN": "...", "ja": "...", "fr": "...", "es": "..." } }
  Built files (commit them):
    godot/i18n/strings.json   godot sources                    (autoload Lang)
    public/i18n-data.js       godot sources + web sources      (window.I18N_DATA, public/i18n.js)

  node tools/i18n.js                    merge and validate, write both built files
  node tools/i18n.js --check            exit 1 if a built file is out of date or an entry is invalid (part of npm test)
  node tools/i18n.js --file=NAME.json   validate one source file (godot/i18n/src or web-i18n/src) only, write nothing
  node tools/i18n.js --scan [--web]     list text in the code with no translation yet; --strict exits 1 when a tr()/t() key is missing
*/
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const GODOT = path.join(ROOT, 'godot');
const SRC = path.join(GODOT, 'i18n', 'src');
const OUT = path.join(GODOT, 'i18n', 'strings.json');
const WEB_SRC = path.join(ROOT, 'web-i18n', 'src');
const WEB_OUT = path.join(ROOT, 'public', 'i18n-data.js');
const WEB_HTML = path.join(ROOT, 'public', 'index.html');
const LANGS = ['zh_TW', 'zh_CN', 'ja', 'fr', 'es'];
const args = process.argv.slice(2);
const check = args.includes('--check'), scan = args.includes('--scan'), strict = args.includes('--strict'), web = args.includes('--web');
const only = (args.find(a => a.startsWith('--file=')) || '').slice(7);

// printf-style placeholders in order ("%d", "%s", "%.1f", "%02d", "%%"); both games fill them in order, so every language
// must keep them in the same order.
const holes = s => (s.match(/%[-+ 0#]*\d*(?:\.\d+)?[sdfxXc%]/g) || []).filter(h => h !== '%%');
const braces = s => (s.match(/\{[A-Za-z_][A-Za-z0-9_]*\}/g) || []).sort();

function load(dir, onlyFile) {
  const merged = {}, errors = [], dupes = [];
  let files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith('.json')).sort() : [];
  if (onlyFile) files = files.filter(f => f === onlyFile);
  for (const f of files) {
    let d;
    try { d = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); } catch (e) { errors.push(`${f}: ${e.message}`); continue; }
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

function sorted(merged) {
  const out = {};
  for (const k of Object.keys(merged).sort()) { out[k] = {}; for (const l of LANGS) out[k][l] = merged[k][l]; }
  return out;
}
const serialise = merged => JSON.stringify(sorted(merged), null, 1) + '\n';
const serialiseWeb = merged => '/* Built by tools/i18n.js from godot/i18n/src and web-i18n/src. Do not edit. */\nwindow.I18N_DATA=' + JSON.stringify(sorted(merged)) + ';\n';

function gdFiles(dir, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'tests' && e.name !== '.godot') gdFiles(p, acc); }
    else if (e.name.endsWith('.gd')) acc.push(p);
  }
  return acc;
}
const unesc = s => s.replace(/\\u\{([0-9a-fA-F]+)\}|\\u([0-9a-fA-F]{4})|\\x([0-9a-fA-F]{2})/g, (m, a, b, c) => String.fromCodePoint(parseInt(a || b || c, 16))).replace(/\\(.)/g, (m, c) => ({ n: '\n', t: '\t', '"': '"', "'": "'", '\\': '\\' }[c] ?? c));
const STR = '"((?:[^"\\\\\\n]|\\\\.)*)"';

function doScanGodot(merged) {
  const missingKeys = [], missingText = [];
  const keyRe = new RegExp('(?:\\btr|\\batr|TranslationServer\\.translate)\\(\\s*' + STR, 'g');
  const textRe = new RegExp('\\b(?:text|tooltip_text|placeholder_text|title)\\s*=\\s*' + STR, 'g');
  for (const f of gdFiles(GODOT)) {
    const rel = path.relative(GODOT, f);
    fs.readFileSync(f, 'utf8').split('\n').forEach((line, i) => {
      const code = line.replace(/\s#.*$/, '');
      for (const m of code.matchAll(keyRe)) { const k = unesc(m[1]); if (!(k in merged)) missingKeys.push(`${rel}:${i + 1}  ${JSON.stringify(k)}`); }
      for (const m of code.matchAll(textRe)) {
        const k = unesc(m[1]);
        if (!/[A-Za-z]{2,}/.test(k) || k in merged || /^[A-Za-z0-9_\/. -]+$/.test(k) && !/ /.test(k) && k === k.toLowerCase()) continue;
        missingText.push(`${rel}:${i + 1}  ${JSON.stringify(k)}`);
      }
    });
  }
  return [missingKeys, missingText];
}

// web: t('...') / tf('...', ...) keys in public/index.html (single, double or back-tick quotes, no ${} inside)
function doScanWeb(merged) {
  const missingKeys = [];
  const re = /(?<![\w.$])tf?\(\s*(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"|`([^`$\n]*)`)/g;
  fs.readFileSync(WEB_HTML, 'utf8').split('\n').forEach((line, i) => {
    for (const m of line.matchAll(re)) {
      const raw = m[1] ?? m[2] ?? m[3];
      const k = unesc(raw);
      if (!(k in merged)) missingKeys.push(`public/index.html:${i + 1}  ${JSON.stringify(k)}`);
    }
  });
  return [missingKeys, []];
}

function report(missingKeys, missingText) {
  if (missingKeys.length) console.log(`translation keys with no translation (${missingKeys.length}):\n  ` + missingKeys.join('\n  '));
  if (missingText.length) console.log(`.text literals with no translation (${missingText.length}, advisory):\n  ` + missingText.join('\n  '));
  if (!missingKeys.length && !missingText.length) console.log('every translation key and text literal has a translation');
}

const G = load(SRC, args.some(a => a.startsWith('--file=')) && fs.existsSync(path.join(SRC, only)) ? only : '');
const W = load(WEB_SRC, args.some(a => a.startsWith('--file=')) && fs.existsSync(path.join(WEB_SRC, only)) ? only : '');
const errors = [...G.errors, ...W.errors];
const dupes = [...G.dupes, ...W.dupes];
if (dupes.length && !scan) console.warn(dupes.join('\n'));
if (errors.length) console.error(errors.slice(0, 60).join('\n') + (errors.length > 60 ? `\n... and ${errors.length - 60} more` : ''));
const webMerged = Object.assign({}, W.merged, G.merged);   // a godot entry wins on the (rare) shared key: one wording for both games

if (scan) {
  const [mk, mt] = web ? doScanWeb(webMerged) : doScanGodot(G.merged);
  report(mk, mt);
  process.exit(strict && (mk.length || errors.length) ? 1 : 0);
}
if (only) {
  if (errors.length) process.exit(1);
  console.log(`--file=${only}: ${Object.keys(G.merged).length + Object.keys(W.merged).length} strings ok`);
  process.exit(0);
}
const gText = serialise(G.merged), wText = serialiseWeb(webMerged);
if (check) {
  let bad = errors.length;
  for (const [file, text, label] of [[OUT, gText, 'godot/i18n/strings.json'], [WEB_OUT, wText, 'public/i18n-data.js']]) {
    let cur = ''; try { cur = fs.readFileSync(file, 'utf8'); } catch (e) { /* missing */ }
    if (cur !== text) { console.error(`${label} is out of date. Run: npm run i18n`); bad++; }
  }
  if (bad) process.exit(1);
  console.log(`translations ok: ${Object.keys(G.merged).length} godot + ${Object.keys(W.merged).length} web-only strings x ${LANGS.length} languages`);
} else {
  if (errors.length) process.exit(1);
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, gText);
  fs.writeFileSync(WEB_OUT, wText);
  console.log(`wrote godot/i18n/strings.json (${Object.keys(G.merged).length}) and public/i18n-data.js (${Object.keys(webMerged).length}) x ${LANGS.length} languages`);
}
