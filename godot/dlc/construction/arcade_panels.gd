class_name ArcadePanels
extends RefCounted
## The Arcade run's cards, shown over the frozen match with World.show_panel (the same stage as the results panel): the stage
## intro (name, tagline, the boss' portrait colour), stage clear (time, K.O.s, coins, Next stage / Quit run), stage failed
## (lives left, Retry / Quit), run over and the final victory (the Site Foreman hat). Pure builders: each returns a themed
## PanelContainer whose buttons call the given Callables.

const MIN_W := 420.0

## A fighter's head in its table colour (and the stage's bar colour as the ring): the boss portrait, or the crew side by side.
class Portrait extends Control:
	var cols: Array = []                 ## head colours
	var ring := Color.WHITE
	var crown := false
	func _init() -> void:
		custom_minimum_size = Vector2(76, 76)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var n := maxi(1, cols.size())
		if n == 1:
			_head(size * 0.5 + Vector2(0, 2), size.x * 0.4, Color(cols[0]) if cols.size() > 0 else Color.WHITE, true)
			return
		var r := minf(size.x / (2.0 * n), size.y * 0.36)
		for i in n:
			_head(Vector2(size.x * (i + 0.5) / n, size.y * 0.55), r, Color(cols[i]), false)
	func _head(c: Vector2, r: float, col: Color, big: bool) -> void:
		draw_circle(c, r + 3.0, ring)
		draw_circle(c, r, col)
		var ink := Color(0.1, 0.12, 0.14)
		draw_circle(c + Vector2(-r * 0.34, -r * 0.1), r * 0.12, ink)
		draw_circle(c + Vector2(r * 0.34, -r * 0.1), r * 0.12, ink)
		draw_arc(c + Vector2(0, r * 0.15), r * 0.4, 0.3, PI - 0.3, 10, ink, maxf(2.0, r * 0.08), true)
		var hat := ConstructionStyle.YELLOW
		draw_rect(Rect2(c.x - r * 0.95, c.y - r * 1.02, r * 1.9, r * 0.36), hat)         # a hard hat on every head
		draw_rect(Rect2(c.x - r * 0.55, c.y - r * 1.3, r * 1.1, r * 0.32), hat)
		if big and crown:
			var gold := Color("#ffd700")
			for k in 3:
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.5 + k * r * 0.5 - r * 0.14, c.y - r * 1.3), Vector2(c.x - r * 0.5 + k * r * 0.5, c.y - r * 1.62), Vector2(c.x - r * 0.5 + k * r * 0.5 + r * 0.14, c.y - r * 1.3)]), gold)

static func _frame(card_name: String) -> Array:
	var p := PanelContainer.new()
	p.name = card_name
	p.custom_minimum_size = Vector2(MIN_W, 0)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 8)
	p.add_child(box)
	var tape := ConstructionStyle.Hazard.new()
	tape.name = "Tape"
	tape.custom_minimum_size = Vector2(0, 10)
	box.add_child(tape)
	return [p, box]

static func _title(box: Control, text: String, color := UiTheme.ACCENT) -> Label:
	var l := Label.new()
	l.name = "Title"
	l.theme_type_variation = &"TitleLabel"
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = text
	box.add_child(l)
	return l

static func _line(box: Control, node_name: String, text: String, size := 20, muted := true, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.name = node_name
	if muted: l.theme_type_variation = &"MutedLabel"
	else: l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(MIN_W - 40.0, 0)
	l.text = text
	box.add_child(l)
	return l

static func _button(text: String, node_name: String, primary: bool, cb: Callable, h := 58.0) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary:
		b.theme_type_variation = &"PrimaryButton"
		b.add_theme_font_size_override("font_size", 26)
	else:
		b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b

static func _buttons(box: Control, a: Button, b: Button = null) -> void:
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", 10)
	row.add_child(a)
	if b != null: row.add_child(b)
	box.add_child(row)
	JuicyButton.attach_all(row)

static func _coin_row(box: Control, text: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Coins"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(LockerScreen.LockerIcon.new("coin", 26))
	var c := Label.new()
	c.name = "Earned"
	c.text = text
	c.add_theme_font_override("font", UiTheme.font(700))
	c.add_theme_font_size_override("font_size", 26)
	c.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(c)

# ---------------- the cards ----------------

static func intro(m: ArcadeManager, d: Dictionary, on_start: Callable) -> Control:
	var fr := _frame("ArcadeIntro")
	var p: PanelContainer = fr[0]
	var box: VBoxContainer = fr[1]
	var row := HBoxContainer.new()
	row.name = "Head"
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var pt := Portrait.new()
	pt.name = "Portrait"
	pt.ring = Color.from_rgba8((int(d["hp_bar_color"]) >> 16) & 255, (int(d["hp_bar_color"]) >> 8) & 255, int(d["hp_bar_color"]) & 255)
	for b: Dictionary in d["bots"]:
		var ci := int(b["color"])
		pt.cols.append(Color.from_rgba8((ci >> 16) & 255, (ci >> 8) & 255, ci & 255))
	pt.crown = str((d["bots"] as Array)[0].get("hat", "")) == "crown" and bool(d.get("boss", false))
	pt.custom_minimum_size = Vector2(76.0 if pt.cols.size() <= 1 else 40.0 * pt.cols.size() + 12.0, 76)
	row.add_child(pt)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	var sl := Label.new()
	sl.name = "StageNo"
	sl.theme_type_variation = &"MutedLabel"
	sl.add_theme_font_size_override("font_size", 18)
	sl.text = TranslationServer.translate("Stage %d of %d") % [m.stage + 1, ArcadeManager.count()]
	col.add_child(sl)
	var nl := Label.new()
	nl.name = "StageName"
	nl.theme_type_variation = &"TitleLabel"
	nl.add_theme_color_override("font_color", pt.ring if bool(d.get("boss", false)) else UiTheme.ACCENT)
	nl.text = TranslationServer.translate(str(d["name"]))
	col.add_child(nl)
	_line(box, "Tagline", TranslationServer.translate(str(d["tagline"])), 20)
	var tag := TranslationServer.translate("Final boss") if m.is_last_stage() else (TranslationServer.translate("Boss fight") if bool(d.get("boss", false)) else TranslationServer.translate("Crew fight"))
	_line(box, "Tag", "%s · %s" % [tag, TranslationServer.translate("Lives %d") % m.lives], 18, false, UiTheme.ACCENT)
	if m.first_clear():
		_line(box, "Reward", TranslationServer.translate("First clear: %d coins") % (int(d.get("coin_reward", 0)) + int(d.get("first_clear_bonus", 0))), 18)
	_buttons(box, _button(TranslationServer.translate("Start"), "Start", true, on_start))
	return p

static func clear(m: ArcadeManager, s: Dictionary, on_next: Callable, on_quit: Callable) -> Control:
	var fr := _frame("ArcadeClear")
	var p: PanelContainer = fr[0]
	var box: VBoxContainer = fr[1]
	_title(box, TranslationServer.translate("Stage clear!"))
	_line(box, "StageName", TranslationServer.translate(str(s["name"])), 24, false, Color.WHITE)
	_line(box, "Stats", "%s · %s" % [TranslationServer.translate("Time %s") % ArcadeManager.fmt_time(float(s["time"])), TranslationServer.translate("K.O.s %d") % int(s["kos"])], 20)
	if int(s["coins"]) > 0:
		_coin_row(box, TranslationServer.translate("+%d coins") % int(s["coins"]))
		_line(box, "Bonus", TranslationServer.translate("%d clear + %d first clear bonus") % [int(s["reward"]), int(s["bonus"])], 17)
	else:
		_line(box, "Bonus", TranslationServer.translate("Cleared before: no coins this time"), 17)
	_buttons(box, _button(TranslationServer.translate("Next stage"), "Next", true, on_next), _button(TranslationServer.translate("Quit run"), "Quit", false, on_quit))
	return p

static func failed(m: ArcadeManager, on_retry: Callable, on_quit: Callable) -> Control:
	var fr := _frame("ArcadeFailed")
	var p: PanelContainer = fr[0]
	var box: VBoxContainer = fr[1]
	_title(box, TranslationServer.translate("Stage failed"), Color(1, 0.8, 0.72))
	_line(box, "StageName", TranslationServer.translate(str(m.stage_def()["name"])), 24, false, Color.WHITE)
	_line(box, "Lives", TranslationServer.translate("Lives left: %d") % m.lives, 22, false, UiTheme.ACCENT)
	_line(box, "Hint", TranslationServer.translate("A fresh site, a fresh try."), 18)
	_buttons(box, _button(TranslationServer.translate("Retry stage"), "Retry", true, on_retry), _button(TranslationServer.translate("Quit run"), "Quit", false, on_quit))
	return p

static func over(m: ArcadeManager, on_quit: Callable) -> Control:
	var fr := _frame("ArcadeOver")
	var p: PanelContainer = fr[0]
	var box: VBoxContainer = fr[1]
	_title(box, TranslationServer.translate("Run over"), Color(1, 0.8, 0.72))
	_line(box, "Reached", TranslationServer.translate("You reached stage %d of %d: %s") % [m.stage + 1, ArcadeManager.count(), TranslationServer.translate(str(m.stage_def()["name"]))], 22, false, Color.WHITE)
	if m.run_coins > 0: _coin_row(box, TranslationServer.translate("+%d coins") % m.run_coins)
	_line(box, "Hint", TranslationServer.translate("Out of lives. The site wins this time."), 18)
	_buttons(box, _button(TranslationServer.translate("Back to title"), "Quit", true, on_quit))
	return p

static func won(m: ArcadeManager, on_quit: Callable) -> Control:
	var fr := _frame("ArcadeVictory")
	var p: PanelContainer = fr[0]
	var box: VBoxContainer = fr[1]
	_title(box, TranslationServer.translate("Site cleared!"))
	_line(box, "Sub", TranslationServer.translate("The Client signed off. Every tradie is back on smoko."), 20)
	_coin_row(box, TranslationServer.translate("+%d coins") % m.run_coins)
	var hat := TranslationServer.translate(LockerData.hat_name(ArcadeManager.FOREMAN_HAT))
	if bool(m.victory.get("first", false)):
		_line(box, "Hat", TranslationServer.translate("New hat: %s. Pick it in the Walldrobe") % hat, 19, false, UiTheme.GOOD)
		_line(box, "Bonus", TranslationServer.translate("Includes %d victory bonus coins") % int(m.victory.get("coins", 0)), 17)
	else:
		_line(box, "Hat", TranslationServer.translate("Your %s is already in the Walldrobe") % hat, 19)
	_buttons(box, _button(TranslationServer.translate("Back to title"), "Quit", true, on_quit))
	return p
