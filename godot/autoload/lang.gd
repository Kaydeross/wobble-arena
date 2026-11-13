extends Node
## Languages (autoload `Lang`). The game is written in English; English text is the message id, so a Label whose text is
## "Settings" shows the translation of "Settings" with no code at all. Strings that are built at run time use tr() on the
## whole sentence (see docs/I18N.md). Translations: res://i18n/strings.json (built from i18n/src/*.json by tools/i18n.js):
## { "English text": { "zh_TW": "...", "zh_CN": "...", "ja": "...", "fr": "...", "es": "..." } }.
## Settings `lang`: "auto" (the device's language, English when we do not have it) or one of the codes in LANGS.

signal language_changed(code: String)

const STRINGS_PATH := "res://i18n/strings.json"
const FONT_PATH := "res://ui/fonts/Fredoka-Variable.ttf"
## code -> {name: shown in the picker, always in the language itself (never translated), bundled: the game's own CJK font
## (ui/fonts, Noto Sans CJK Bold cut down to the characters the translations use: tools/subset-fonts.py), fonts: the
## device's fonts, tried after it for anything else (names players type), best match for that language first}
const LANGS := [
	{"code": "en", "name": "English", "fonts": []},
	{"code": "zh_TW", "name": "繁體中文", "bundled": "res://ui/fonts/NotoSansTC-Subset.otf", "fonts": ["PingFang TC", "Noto Sans CJK TC", "Noto Sans TC", "Microsoft JhengHei", "Source Han Sans TC", "Droid Sans Fallback"]},
	{"code": "zh_CN", "name": "简体中文", "bundled": "res://ui/fonts/NotoSansSC-Subset.otf", "fonts": ["PingFang SC", "Noto Sans CJK SC", "Noto Sans SC", "Microsoft YaHei", "Source Han Sans SC", "Droid Sans Fallback"]},
	{"code": "ja", "name": "日本語", "bundled": "res://ui/fonts/NotoSansJP-Subset.otf", "fonts": ["Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans CJK JP", "Noto Sans JP", "Yu Gothic", "Meiryo", "Source Han Sans JP", "Droid Sans Fallback"]},
	{"code": "fr", "name": "Français", "fonts": []},
	{"code": "es", "name": "Español", "fonts": []},
]

var code := "en"                   ## the language in use (a code from LANGS, never "auto")
var _loaded := false

func _ready() -> void:
	load_strings()
	Settings.changed.connect(_on_setting)
	apply(str(Settings.get_value("lang")))

func _on_setting(key: String, value: Variant) -> void:
	if key == "lang": apply(str(value))

## Registers every translation with the TranslationServer (once).
func load_strings(path: String = STRINGS_PATH) -> void:
	if _loaded: return
	_loaded = true
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Lang: %s is missing, the game stays in English" % path)
		return
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK or not (j.data is Dictionary):
		push_warning("Lang: %s is not valid json" % path)
		return
	var by_lang := {}
	for l: Dictionary in LANGS:
		if l.code != "en":
			var t := Translation.new()
			t.locale = l.code
			by_lang[l.code] = t
	for src: String in (j.data as Dictionary):
		var per: Dictionary = j.data[src]
		for c: String in by_lang:
			var s := str(per.get(c, ""))
			if s != "": (by_lang[c] as Translation).add_message(src, s)
	for c: String in by_lang:
		TranslationServer.add_translation(by_lang[c])

## The language code for a Settings value: "auto" = the device's language.
static func resolve(setting: String, os_locale: String = "") -> String:
	if setting != "auto":
		return setting if is_known(setting) else "en"
	if OS.get_cmdline_user_args().has("--no-save") and _cmdline_lang() == "":
		return "en"   # tests (and screenshots) stay in English unless they ask: --lang=ja
	var forced := _cmdline_lang()
	if forced != "": return forced if is_known(forced) else "en"
	return detect(os_locale if os_locale != "" else OS.get_locale())

static func _cmdline_lang() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="): return a.substr(7)
	return ""

## "zh_Hant_HK" -> zh_TW, "zh-CN" -> zh_CN, "ja_JP" -> ja, "fr_CA" -> fr, "es_MX" -> es, anything else -> en.
static func detect(os_locale: String) -> String:
	var l := os_locale.replace("-", "_").to_lower()
	if l.begins_with("zh"):
		if l.contains("hans"): return "zh_CN"
		if l.contains("hant") or l.contains("_tw") or l.contains("_hk") or l.contains("_mo"): return "zh_TW"
		return "zh_CN"
	for c: String in ["ja", "fr", "es"]:
		if l == c or l.begins_with(c + "_"): return c
	return "en"

static func is_known(c: String) -> bool:
	for l: Dictionary in LANGS:
		if l.code == c: return true
	return false

## Switches the language now: every Control re-translates itself, the font gets the right CJK fallback.
func apply(setting: String) -> void:
	var c := resolve(setting)
	TranslationServer.set_locale(c)
	_set_fonts(c)
	var changed := c != code
	code = c
	if changed: language_changed.emit(c)

## Fredoka has Latin letters only. In a CJK language the UI font gets the bundled Noto Sans CJK subset for that language first,
## then the other two, then the device's own fonts for any other character (names players type). In en / fr / es there are no
## fallbacks at all: every fallback costs shaping time on every label, and the language picker (the only CJK text left) gets
## its own font, see cjk_fonts(). The subsets report Fredoka's line metrics (tools/subset-fonts.py), so no line gets taller.
func _set_fonts(c: String) -> void:
	var base: FontFile = load(FONT_PATH)
	if base == null: return
	var def: Dictionary = {}
	for l: Dictionary in LANGS:
		if l.code == c: def = l
	var fb: Array[Font] = []
	if def.has("bundled"):
		var order: Array = [str(def.bundled)]
		for l: Dictionary in LANGS:
			if l.has("bundled") and not order.has(l.bundled): order.append(l.bundled)
		for path: String in order:
			if ResourceLoader.exists(path):
				var f := load(path) as Font
				if f != null: fb.append(f)
		var names: Array = def.get("fonts", [])
		if not names.is_empty():
			var sys := SystemFont.new()
			sys.font_names = PackedStringArray(names)
			sys.font_weight = 700
			fb.append(sys)
	base.fallbacks = fb

## The three bundled CJK fonts (a glyph missing in one is taken from the next), for text that shows CJK whatever the language is:
## the language picker's own names.
static func cjk_fonts() -> Array[Font]:
	var out: Array[Font] = []
	for l: Dictionary in LANGS:
		if l.has("bundled") and ResourceLoader.exists(l.bundled):
			var f := load(l.bundled) as Font
			if f != null: out.append(f)
	return out

## (code, native name) of every language, for pickers.
static func list() -> Array:
	var out: Array = []
	for l: Dictionary in LANGS: out.append([l.code, l.name])
	return out
