/* Languages for the web game (docs/I18N.md). Loaded before the game as a classic script.
   English text is the key. window.I18N_DATA (public/i18n-data.js, built by tools/i18n.js) = { "English": { zh_TW, zh_CN, ja, fr, es } }.
   - t(s)        the translation of an English string (s itself when there is none)
   - tf(s, ...)  t(s) with printf-style %s %d %.1f %02d filled in, in order: tf('Got %s!', name)
   - A DOM translator rewrites any text node / placeholder / title / aria-label whose whole text is a key, now and for
     everything added or changed later, and redoes it when the language changes. So static markup needs no code at all;
     only text built in JS (concatenation, templates) goes through t() / tf(). */
(function () {
  'use strict';
  const LANGS = [
    { code: 'en', name: 'English', html: 'en' },
    { code: 'zh_TW', name: '繁體中文', html: 'zh-Hant' },
    { code: 'zh_CN', name: '简体中文', html: 'zh-Hans' },
    { code: 'ja', name: '日本語', html: 'ja' },
    { code: 'fr', name: 'Français', html: 'fr' },
    { code: 'es', name: 'Español', html: 'es' },
  ];
  const DATA = window.I18N_DATA || {};
  const KEY = 'wobble_lang';
  let lang = 'en', setting = 'auto';
  const listeners = [];

  function detect(loc) {
    const l = String(loc || '').replace(/-/g, '_').toLowerCase();
    if (l.startsWith('zh')) {
      if (l.includes('hans')) return 'zh_CN';
      if (l.includes('hant') || /_(tw|hk|mo)\b/.test(l)) return 'zh_TW';
      return 'zh_CN';
    }
    for (const c of ['ja', 'fr', 'es']) if (l === c || l.startsWith(c + '_')) return c;
    return 'en';
  }
  const known = c => LANGS.some(l => l.code === c);
  function resolve(s) {
    if (s !== 'auto') return known(s) ? s : 'en';
    try { const q = new URLSearchParams(location.search).get('lang'); if (q) return known(q) ? q : 'en'; } catch (e) { /* no url */ }
    for (const loc of (navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language])) {
      const c = detect(loc); if (c !== 'en') return c;
      if (String(loc).toLowerCase().startsWith('en')) return 'en';
    }
    return 'en';
  }

  function t(s) {
    if (lang === 'en' || typeof s !== 'string') return s;
    const e = DATA[s];
    return (e && e[lang]) || s;
  }
  function tf(s, ...a) {
    let i = 0;
    return t(s).replace(/%([-+ 0#]*)(\d*)(?:\.(\d+))?([sdfxXc%])/g, (m, flags, w, p, c) => {
      if (c === '%') return '%';
      let v = a[i++];
      if (c === 'd') v = String(Math.trunc(Number(v)));
      else if (c === 'f') v = Number(v).toFixed(p === undefined ? 6 : +p);
      else if (c === 'x') v = Math.trunc(Number(v)).toString(16);
      else if (c === 'X') v = Math.trunc(Number(v)).toString(16).toUpperCase();
      else v = String(v);
      if (w && v.length < +w) v = flags.includes('-') ? v.padEnd(+w) : v.padStart(+w, flags.includes('0') && c !== 's' ? '0' : ' ');
      return v;
    });
  }

  // ---------- DOM translator ----------
  const ATTRS = ['placeholder', 'title', 'aria-label', 'alt'];
  const shown = new WeakMap();      // text node -> { src, out }
  const shownAttr = new WeakMap();  // element -> { attr: { src, out } }
  const SKIP = new Set(['SCRIPT', 'STYLE', 'TEXTAREA', 'CANVAS', 'SVG']);

  function trNode(n) {
    const v = n.nodeValue;
    if (!v || !/[A-Za-z]/.test(v)) return;
    const rec = shown.get(n);
    const src = rec && rec.out === v ? rec.src : v;
    const m = /^(\s*)([\s\S]*?)(\s*)$/.exec(src);
    const out = m[1] + t(m[2]) + m[3];
    if (out !== v) { n.nodeValue = out; shown.set(n, { src, out }); }
    else if (rec && rec.out !== v) shown.delete(n);
    else if (lang === 'en' && rec) shown.delete(n);
  }
  function trAttrs(e) {
    for (const a of ATTRS) {
      if (!e.hasAttribute(a)) continue;
      const v = e.getAttribute(a);
      let all = shownAttr.get(e); const rec = all && all[a];
      const src = rec && rec.out === v ? rec.src : v;
      const out = t(src.trim()) === src.trim() ? src : t(src.trim());
      if (out !== v) { e.setAttribute(a, out); if (!all) shownAttr.set(e, all = {}); all[a] = { src, out }; }
    }
  }
  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) { trNode(root); return; }
    if (root.nodeType !== 1 || SKIP.has(root.tagName)) return;
    trAttrs(root);
    for (let c = root.firstChild; c; c = c.nextSibling) walk(c);
  }
  let obs = null;
  function observe() {
    if (obs || typeof MutationObserver === 'undefined') return;
    obs = new MutationObserver(list => {
      for (const m of list) {
        if (m.type === 'characterData') trNode(m.target);
        else if (m.type === 'attributes') trAttrs(m.target);
        else for (const n of m.addedNodes) walk(n);
      }
    });
    obs.observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ATTRS });
  }

  function apply(s) {
    setting = s;
    const c = resolve(s);
    const changed = c !== lang;
    lang = c;
    try { document.documentElement.lang = LANGS.find(l => l.code === c).html; } catch (e) { /* no doc */ }
    if (document.body || document.documentElement) walk(document.documentElement);
    try { if (document.title) document.title = t('Wobblers Arena'); } catch (e) { /* cosmetic */ }
    if (changed) for (const f of listeners) { try { f(c); } catch (e) { /* listener */ } }
  }
  function setLang(s) {
    try { if (s === 'auto') localStorage.removeItem(KEY); else localStorage.setItem(KEY, s); } catch (e) { /* private mode */ }
    apply(s);
  }
  let saved = 'auto';
  try { saved = localStorage.getItem(KEY) || 'auto'; } catch (e) { /* private mode */ }
  apply(saved);
  observe();

  window.I18N = { LANGS, t, tf, detect, resolve, setLang, get lang() { return lang; }, get setting() { return setting; }, onChange: f => listeners.push(f), walk };
  window.t = t; window.tf = tf;
})();
