extends RefCounted
## Text-fit audit (used by tests/title_fit_test.gd, tools/test-title-fit.js): walks a UI tree and, for every visible
## Label / Button / RichTextLabel (and the title's drawn pill), measures the translated text with the real font at the real
## size (CJK fallback included) and records a failure when it does not fit its own control, is cropped by a clipping
## ancestor or the screen, overlaps another control, or when a button is under 44 pt. Also notes strings with no translation.

const MIN_TOUCH := 44.0
const MIN_GAP := 8.0           ## canvas px between two texts on one line
const TEXT_ONLY_SKIP := ["Catcher"]

var fails: Array = []          ## {lang, size, path, text, kind, need, avail, ratio}
var untranslated: Dictionary = {}   ## lang -> {english text -> true}
var worst: Dictionary = {}     ## lang -> {ratio, what}
var keys: Dictionary = {}      ## english source strings with translations (res://i18n/strings.json)
var checked := 0

func load_keys() -> void:
	var f := FileAccess.open("res://i18n/strings.json", FileAccess.READ)
	if f: keys = JSON.parse_string(f.get_as_text())

func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a

func _related(a: Node, b: Node) -> bool:
	return a == b or a.is_ancestor_of(b) or b.is_ancestor_of(a)

func _line_w(f: Font, t: String, fs: int) -> float:
	var w := 0.0
	for l in t.split("\n"): w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w

func _fail(lang: String, size: String, root: Node, c: Node, text: String, kind: String, need: float, avail: float) -> void:
	var ratio := need / maxf(avail, 1.0)
	fails.append({"lang": lang, "size": size, "path": str(root.get_path_to(c)), "text": text, "kind": kind, "need": need, "avail": avail, "ratio": ratio})

func _note(lang: String, text: String, need: float, avail: float) -> void:
	var r := need / maxf(avail, 1.0)
	if not worst.has(lang) or r > float(worst[lang].ratio): worst[lang] = {"ratio": r, "what": text}

## Audits everything visible under `root`. `win` = window in points, `cs` = canvas size, `scn` names the scenario.
func audit(root: Node, lang: String, win: Vector2, cs: Vector2, scn: String) -> void:
	var size := "%dx%d %s" % [win.x, win.y, scn]
	var k := win.x / cs.x                     # pt per canvas px
	var vp := Rect2(Vector2.ZERO, cs)
	var items: Array = []                     # [control, text rect]
	var buttons: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children(): stack.append(ch)
		if not (n is Control): continue
		var c := n as Control
		if not c.is_visible_in_tree() or c.size.x < 1.0 or _alpha(c) < 0.1: continue
		if str(c.name) in TEXT_ONLY_SKIP: continue
		if c is BaseButton and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and not (c as BaseButton).disabled and str(c.get_parent().name) != "Proxies" and not c.get_meta("fit_skip_touch", false) and not _is_proxy(c):
			var r := c.get_global_rect()
			if r.size.x * k < MIN_TOUCH - 0.5 or r.size.y * k < MIN_TOUCH - 0.5:
				_fail(lang, size, root, c, _text_of(c), "touch %.0fx%.0f pt" % [r.size.x * k, r.size.y * k], minf(r.size.x, r.size.y) * k, MIN_TOUCH)
			if _visible_part(c, r).size.x > 0.0: buttons.append(c)
		var text := _text_of(c)
		if text == "" or c is LineEdit: continue
		checked += 1
		var shown := text
		_track_translation(lang, text)
		var f := c.get_theme_font("font") if not (c is RichTextLabel) else c.get_theme_font("normal_font")
		var fs := c.get_theme_font_size("font_size") if not (c is RichTextLabel) else c.get_theme_font_size("normal_font_size")
		var need := 0.0
		var avail := c.size.x
		var need_h := 0.0
		var wrap := false
		if c.has_method("text_fit"):     # DlcPill / DontEnterSign: they draw their own text and report what they need
			var tf: Vector2 = c.call("text_fit")
			need = tf.x
			avail = tf.y
		elif c is Label:
			var l := c as Label
			avail -= l.get_theme_stylebox("normal").get_minimum_size().x
			wrap = l.autowrap_mode != TextServer.AUTOWRAP_OFF
			need = _line_w(f, shown, fs)
			if wrap:
				var wh := f.get_multiline_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, maxf(avail, 1.0), fs, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
				need_h = wh.y
				need = minf(need, avail)
				if l.autowrap_mode == TextServer.AUTOWRAP_WORD:    # (smart / arbitrary wrapping also breaks inside a word)
					for w in shown.split(" "): need = maxf(need, f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)   # an unbreakable word
				if l.max_lines_visible > 0 and l.get_line_count() > l.max_lines_visible:
					_fail(lang, size, root, c, shown, "lines cut off (%d > %d)" % [l.get_line_count(), l.max_lines_visible], float(l.get_line_count()), float(l.max_lines_visible))
				if need_h > c.size.y + 1.0: _fail(lang, size, root, c, shown, "wrapped height", need_h, c.size.y)
			else:
				need_h = f.get_height(fs) * (shown.count("\n") + 1)
				if need_h > c.size.y + 1.0 and c.size.y > 1.0: _fail(lang, size, root, c, shown, "height", need_h, c.size.y)
		elif c is Button:
			var b := c as Button
			avail -= b.get_theme_stylebox("normal").get_minimum_size().x
			if b.icon != null and not b.expand_icon: avail -= b.icon.get_width() + b.get_theme_constant("h_separation")
			need = _line_w(f, shown, fs)
		elif c is RichTextLabel:
			var rt := c as RichTextLabel
			if rt.get_content_height() > rt.size.y + 1.0 and not rt.scroll_active: _fail(lang, size, root, c, shown, "rich height", rt.get_content_height(), rt.size.y)
			continue
		else:
			continue
		if not (c is Label): _note(lang, shown, need, avail)    # (a Label sizes itself to its text: only buttons have a fixed room)
		if need > avail + 0.5: _fail(lang, size, root, c, shown, "width", need, avail)
		# where the text really is (alignment), to check clipping by ancestors, the screen and other controls
		var ha: int = (c as Label).horizontal_alignment if c is Label else (HORIZONTAL_ALIGNMENT_CENTER if c is Button else 0)
		var gr := c.get_global_rect()
		var tw := minf(need, avail) if wrap else need
		var tx := gr.position.x
		if ha == HORIZONTAL_ALIGNMENT_CENTER: tx += (gr.size.x - tw) * 0.5
		elif ha == HORIZONTAL_ALIGNMENT_RIGHT: tx = gr.end.x - tw
		var tr_ := Rect2(tx, gr.position.y, tw, gr.size.y)
		var vis := _visible_part(c, Rect2(Vector2(tr_.position.x, gr.position.y), Vector2(tr_.size.x, gr.size.y)))
		if vis.size.x <= 0.0: continue                       # scrolled out of view
		if _in_scroll(c) and (tr_.end.x > vis.end.x + 0.5 or tr_.position.x < vis.position.x - 0.5) and _text_of(c) != "":
			var sp := c.get_parent()
			while sp != null and not (sp is ScrollContainer): sp = sp.get_parent()
			var sr := (sp as ScrollContainer).get_global_rect()
			if tr_.end.x > sr.end.x + 0.5 or tr_.position.x < sr.position.x - 0.5:
				_fail(lang, size, root, c, shown, "wider than its scroll area", tr_.size.x, sr.size.x)
		tr_ = Rect2(vis.position.x if _in_scroll(c) else tr_.position.x, vis.position.y if _in_scroll(c) else tr_.position.y, minf(tr_.size.x, vis.size.x) if _in_scroll(c) else tr_.size.x, vis.size.y if _in_scroll(c) else tr_.size.y)
		if not _in_scroll(c) and not vp.grow(0.5).encloses(Rect2(tr_.position, Vector2(tr_.size.x, 1.0))):
			_fail(lang, size, root, c, shown, "off screen", tr_.end.x, vp.end.x)
		var p := c.get_parent()
		var bp := p
		while bp != null and not (bp is BaseButton): bp = bp.get_parent()
		if bp != null and bp != c:        # text inside a button must lie inside the button
			var br := (bp as Control).get_global_rect()
			if not br.grow(0.5).encloses(Rect2(tr_.position, Vector2(tr_.size.x, 1.0))):
				_fail(lang, size, root, c, shown, "sticks out of button " + str(bp.name), tr_.end.x - br.position.x, br.size.x)
		while p != null:
			if p is Control and ((p as Control).clip_contents or p is ScrollContainer) and not (p is ScrollContainer):
				var pr := (p as Control).get_global_rect()
				if not pr.grow(0.5).encloses(Rect2(tr_.position, Vector2(tr_.size.x, 1.0))):
					_fail(lang, size, root, c, shown, "cropped by " + str(p.name), tr_.end.x, pr.end.x)
				break
			p = p.get_parent()
		items.append([c, tr_])
	# text against text, and text against buttons it is not part of
	for i in items.size():
		var a: Array = items[i]
		for j in range(i + 1, items.size()):
			var b: Array = items[j]
			if _related(a[0], b[0]): continue
			var ra: Rect2 = a[1]
			var rb: Rect2 = b[1]
			if ra.grow(-1.0).intersects(rb.grow(-1.0)):
				_fail(lang, size, root, a[0], _text_of(a[0]), "overlaps '%s'" % _text_of(b[0]), 0.0, 0.0)
			elif ra.grow(MIN_GAP * 0.5).intersects(rb.grow(MIN_GAP * 0.5)) and absf(ra.get_center().y - rb.get_center().y) < minf(ra.size.y, rb.size.y) * 0.5:
				_fail(lang, size, root, a[0], _text_of(a[0]), "too close to '%s' (< %.0f px)" % [_text_of(b[0]), MIN_GAP], 0.0, MIN_GAP)
		for b in buttons:
			if _related(a[0], b): continue
			if (a[1] as Rect2).grow(-1.0).intersects(_visible_part(b as Control, (b as Control).get_global_rect()).grow(-1.0)):
				_fail(lang, size, root, a[0], _text_of(a[0]), "overlaps button %s" % b.name, 0.0, 0.0)

## `r` clipped to the scroll areas it lives in (what is really on screen); a zero-size rect when it is scrolled out of view.
func _visible_part(c: Control, r: Rect2) -> Rect2:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			r = r.intersection((p as ScrollContainer).get_global_rect())
			if r.size.x <= 0.0 or r.size.y <= 0.0: return Rect2()
		p = p.get_parent()
	return r

func _in_scroll(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer: return true
		p = p.get_parent()
	return false

func _is_proxy(c: Control) -> bool:
	var p := c.get_parent()
	return p != null and p.name == "Proxies" or (c is Button and (c as Button).flat and _text_of(c) == "" and c.get_child_count() == 0)

func _text_of(c: Node) -> String:
	var t := ""
	if c.has_method("text_fit"):
		t = str(c.get("label"))
		if c.get("tag") != null and str(c.get("tag")) != "": t += " " + str(c.get("tag"))
	elif c is Label: t = c.tr((c as Label).text)          # (the engine translates a Label / Button text itself)
	elif c is Button: t = c.tr((c as Button).text)
	elif c is RichTextLabel: t = (c as RichTextLabel).text
	return t.strip_edges()

func _track_translation(lang: String, text: String) -> void:
	if lang == "en" or keys.is_empty(): return
	# text is shown already translated; flag English keys that have no entry for this language
	for src: String in keys:
		if src == text and str((keys[src] as Dictionary).get(lang, "")) == "":
			if not untranslated.has(lang): untranslated[lang] = {}
			untranslated[lang][text] = true
	var has_latin := false
	var re := RegEx.new()
	re.compile("[A-Za-z]{4,}")
	has_latin = re.search(text) != null
	if has_latin and not keys.has(text) and lang in ["zh_TW", "zh_CN", "ja"]:
		if not untranslated.has(lang): untranslated[lang] = {}
		untranslated[lang]["(no key) " + text] = true
