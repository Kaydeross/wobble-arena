#!/usr/bin/env python3
"""Builds the small CJK fonts the game ships (docs/I18N.md, "Fonts").

Takes Noto Sans CJK Bold (SIL OFL, https://github.com/notofonts/noto-cjk, Sans/SubsetOTF/{TC,SC,JP}/NotoSans*-Bold.otf) and keeps only the
characters the translations use (plus punctuation), so each font is a few hundred KB instead of 5-8 MB. Anything else a player types
(names) still falls back to the device's own fonts.

  python3 tools/subset-fonts.py /path/to/dir/with/NotoSansTC-Bold.otf NotoSansSC-Bold.otf NotoSansJP-Bold.otf
Writes godot/ui/fonts/NotoSans{TC,SC,JP}-Subset.otf and public/fonts/NotoSans{TC,SC,JP}-Subset.woff2.
Run `npm run i18n` first; rerun this when a translation brings in new characters (tools/i18n.js --check tells you).
"""
import json, os, re, sys
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
LANG_OF = {'TC': 'zh_TW', 'SC': 'zh_CN', 'JP': 'ja'}
EXTRA = '，。！？：；、．・·…—–～〜「」『』（）【】《》〈〉“”‘’％＋－×÷＝＞＜≥≤→←↑↓★☆♥♡●○◆◇■□▲△▼▽♪＃＆＊／＠０１２３４５６７８９ー'
src = sys.argv[1] if len(sys.argv) > 1 else '.'

def catalog_chars(lang):
    chars = set(EXTRA)
    with open(os.path.join(ROOT, 'public', 'i18n-data.js'), encoding='utf8') as f:
        txt = f.read()
    data = json.loads(txt[txt.index('=') + 1:].rstrip().rstrip(';'))
    for v in data.values():
        chars.update(v.get(lang, ''))
    for c in LANG_OF.values():
        pass
    for n in ('繁體中文', '简体中文', '日本語'):   # the language picker names
        chars.update(n)
    return ''.join(sorted(c for c in chars if ord(c) > 0x7f))

for region, lang in LANG_OF.items():
    path = os.path.join(src, f'NotoSans{region}-Bold.otf')
    text = catalog_chars(lang)
    opts = subset.Options()
    opts.layout_features = ['*']; opts.notdef_outline = True; opts.name_IDs = [1, 2, 3, 4, 6]; opts.hinting = False
    opts.drop_tables += ['DSIG']
    out_otf = os.path.join(ROOT, 'godot', 'ui', 'fonts', f'NotoSans{region}-Subset.otf')
    out_woff = os.path.join(ROOT, 'public', 'fonts', f'NotoSans{region}-Subset.woff2')
    os.makedirs(os.path.dirname(out_woff), exist_ok=True)
    for out, flavor in ((out_otf, None), (out_woff, 'woff2')):
        font = TTFont(path)
        opts.flavor = flavor
        s = subset.Subsetter(opts); s.populate(text=text); s.subset(font)
        font.flavor = flavor
        font.save(out)
        print(f'{os.path.relpath(out, ROOT)}: {len(text)} chars, {os.path.getsize(out) // 1024} KB')
