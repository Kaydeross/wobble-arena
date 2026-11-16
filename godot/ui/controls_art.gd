class_name ControlsArt
extends RefCounted
## The keyboard-and-mouse board and the controller diagram of the Controls screen (ui/controls_help.gd). Both are built
## from the REAL bindings (input/control_profile.gd reads InputMap), so a rebound key shows where it is now.
##   keyboard_board()  four columns of cards with keycaps: Move / Combat (SHOVE and KICK big and yellow) / Moves / Weapons,
##                     Emotes and Pause.
##   PadPic            a drawn controller with a leader line and a word for every button that does something.
## Words come from WORDS (tr() keys); the keys and buttons themselves are never translated.

const KP := ControlProfile.KEYBOARD
const GP := ControlProfile.GAMEPAD
const MINI := 15            ## smallest text, canvas px (UiTheme.MIN_FONT is 14)

## What each action is called next to its key.
const WORDS := {
	"fire": "Fire", "aim": "Aim", "shove": "SHOVE", "kick": "KICK", "jump": "Jump", "sprint": "Sprint", "crouch": "Crouch",
	"dash": "Dash", "recover": "Recover", "reload": "Reload", "signature": "Class move", "swap": "Next weapon", "spatula": "Spatula swing",
	"pause": "Pause", "move_forward": "Move", "slot1": "Switch weapon",
}
const SUBS := {"shove": "Push them back", "kick": "Send them flying", "dash": "Ninja weapons", "recover": "In the air", "spatula": "Quick melee"}

static func _t(s: String) -> String:
	return TranslationServer.translate(s)

# ---------------- keycaps ----------------

## One keycap: a rounded key with a thick bottom lip. `hot` = yellow (SHOVE / KICK), `big` = taller with larger text.
class KeyCap extends Control:
	var text := ""
	var hot := false
	var fs := 16
	var _font: Font
	func _init(t: String, hot_ := false, big := false) -> void:
		text = t
		hot = hot_
		fs = 22 if big else 16
		_font = UiTheme.font(700)
		var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		custom_minimum_size = Vector2(maxf(w + 20.0, 38.0 if big else 32.0), 46.0 if big else 34.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var bg := UiTheme.ACCENT if hot else Color(0.16, 0.33, 0.39)
		var lip := UiTheme.ACCENT_DARK if hot else Color(0.05, 0.14, 0.18)
		draw_style_box(UiTheme.box(bg, 9, lip, 2, 0, 5, lip), Rect2(Vector2.ZERO, size))
		var col := UiTheme.INK if hot else Color.WHITE
		var asc := _font.get_ascent(fs)
		var h := _font.get_height(fs)
		draw_string(_font, Vector2(0, (size.y - 4.0 - h) * 0.5 + asc), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col)

## W A S D (or whatever the four move actions are bound to) as a cluster: the forward key above the other three.
class Cluster extends Control:
	var names: Array = []        ## forward, left, back, right
	const K := 34.0
	func _init(n: Array) -> void:
		names = n
		custom_minimum_size = Vector2(K * 3 + 8, K * 2 + 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 4:
			var cap := KeyCap.new(str(names[i]))
			cap.custom_minimum_size = Vector2(K, K)
			cap.size = Vector2(K, K)
			cap.position = [Vector2(K + 4, 0), Vector2(0, K + 4), Vector2(K + 4, K + 4), Vector2((K + 4) * 2, K + 4)][i]
			add_child(cap)

## One row: the keycaps on the left, the words on the right (and a muted second line when there is one).
static func entry(caps: Array, text: String, sub := "", hot := false, big := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	var cb := HBoxContainer.new()
	cb.name = "Caps"
	cb.add_theme_constant_override("separation", 5)
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cb)
	for c: Variant in caps:
		if c is Control: cb.add_child(c as Control)
		else: cb.add_child(KeyCap.new(str(c), hot, big))
	var tb := VBoxContainer.new()
	tb.name = "Words"
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tb.add_theme_constant_override("separation", 0)
	row.add_child(tb)
	var l := Label.new()
	l.name = "Word"
	l.text = text
	l.add_theme_font_size_override("font_size", 20 if big else 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(70, 0)
	if hot: l.add_theme_color_override("font_color", UiTheme.ACCENT)
	tb.add_child(l)
	if sub != "":
		var s := Label.new()
		s.name = "Sub"
		s.text = sub
		s.theme_type_variation = &"MutedLabel"
		s.add_theme_font_size_override("font_size", MINI)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(70, 0)
		tb.add_child(s)
	return row

## A card: a small yellow title and its entries.
static func group(title: String, hot := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Group_" + title.replace(" ", "")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiTheme.box(Color(0.0627, 0.1686, 0.2078, 0.85), 14, UiTheme.ACCENT if hot else UiTheme.PANEL_EDGE, 3 if hot else 2, 0)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.name = "Rows"
	v.add_theme_constant_override("separation", 7)
	p.add_child(v)
	var t := Label.new()
	t.name = "Title"
	t.text = title
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	return p

static func add(g: PanelContainer, e: Control) -> void:
	(g.get_node("Rows") as VBoxContainer).add_child(e)

static func _caps(action: String) -> Array:
	var n := ControlProfile.names(action, KP)
	return n if not n.is_empty() else ["-"]

static func _word(action: String) -> String:
	return _t(str(WORDS.get(action, action)))

static func _sub(action: String) -> String:
	return _t(str(SUBS[action])) if SUBS.has(action) else ""

## The keyboard and mouse board: columns of cards, every key read from the live bindings. `cols` = 4 (wide windows) or 3
## (a narrow canvas: Weapons and Emotes move under the others and the page scrolls).
static func keyboard_board(cols_n := 4) -> HBoxContainer:
	var board := HBoxContainer.new()
	board.name = "Board"
	board.add_theme_constant_override("separation", UiTheme.SP_3)
	var cols: Array = []
	for i in cols_n:
		var c := VBoxContainer.new()
		c.name = "Col%d" % i
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_stretch_ratio = 1.0
		c.add_theme_constant_override("separation", UiTheme.SP_3)
		board.add_child(c)
		cols.append(c)
	# Move
	var g := group(_t("Move"))
	var fwd: Array = []
	for a: String in ["move_forward", "move_left", "move_back", "move_right"]:
		fwd.append(ControlProfile.name_of(a, KP))
	add(g, entry([Cluster.new(fwd)], _t("Move")))
	add(g, entry([_t("Mouse")], _t("Look around")))
	cols[0].add_child(g)
	var pause_g := group(_t("Pause"))
	add(pause_g, entry(_caps("pause"), _t("Pause")))
	# Combat (SHOVE and KICK are the yellow ones)
	var combat := group(_t("Combat"), true)
	add(combat, entry(_caps("fire"), _word("fire")))
	add(combat, entry(_caps("aim"), _word("aim")))
	add(combat, entry(_caps("shove"), _word("shove"), _sub("shove"), true, true))
	add(combat, entry(_caps("kick"), _word("kick"), _sub("kick"), true, true))
	# Moves
	var moves := group(_t("Moves"))
	for a: String in ["jump", "sprint", "crouch", "dash", "recover", "reload", "signature"]:
		add(moves, entry(_caps(a), _word(a), _sub(a)))
	# Weapons + Emotes
	var weap := group(_t("Weapons"))
	var sl: Array = []
	for a: String in ["slot1", "slot2", "slot3"]:
		var n := ControlProfile.name_of(a, KP)
		if n != "" and not sl.has(n): sl.append(n)
	add(weap, entry(sl if not sl.is_empty() else ["-"], _t("Switch weapon")))
	var wheel: Array = ControlProfile.names("swap_back", KP).slice(0, 1) + ControlProfile.names("swap", KP).slice(0, 1)
	if ControlProfile.wheel_pair():          # the wheel up AND down are the weapon cycle: one keycap for both
		wheel = [_t("Mouse wheel")]
	add(weap, entry(wheel if not wheel.is_empty() else ["-"], _t("Cycle weapons")))
	add(weap, entry(_caps("spatula"), _word("spatula"), _sub("spatula")))
	var emo := group(_t("Emotes"))
	var em: Array = []
	for k: int in EmoteWheel.KEYS: em.append(OS.get_keycode_string(k))
	add(emo, entry(em, _t("Dance")))
	if cols_n >= 4:
		cols[0].add_child(pause_g)
		cols[1].add_child(combat)
		cols[2].add_child(moves)
		cols[3].add_child(weap)
		cols[3].add_child(emo)
	else:
		cols[0].add_child(pause_g)
		cols[0].add_child(emo)
		cols[1].add_child(combat)
		cols[1].add_child(weap)
		cols[2].add_child(moves)
	return board

# ---------------- the controller ----------------

## The pad drawn at the middle, a column of words each side with a leader line to the button. Controls and words come from
## the live bindings: for every pad control the actions bound to it are looked up in the InputMap.
class PadPic extends Control:
	var font: Font
	const VS := Vector2(430, 215)
	## Control id -> its name (as ControlProfile names it), a point on the diagram, the side its word goes to.
	var _items: Array = []

	func _ready() -> void:
		font = UiTheme.font(700)
		resized.connect(queue_redraw)

	func _init() -> void:
		name = "Pad"
		_items = [
			# [name, point, side, colour]
			[ControlProfile.pad_axis_name(_axis(JOY_AXIS_TRIGGER_LEFT)), Vector2(-128, -78), -1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_button_name(JOY_BUTTON_LEFT_SHOULDER), Vector2(-120, -62), -1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_axis_name(_axis(JOY_AXIS_LEFT_X)), Vector2(-92, -20), -1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_button_name(JOY_BUTTON_DPAD_UP), Vector2(-60, 22), -1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_button_name(JOY_BUTTON_LEFT_STICK), Vector2(-100, -10), -1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_button_name(JOY_BUTTON_START), Vector2(26, -22), -1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_button_name(JOY_BUTTON_RIGHT_STICK), Vector2(56, 34), 1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_axis_name(_axis(JOY_AXIS_TRIGGER_RIGHT)), Vector2(128, -78), 1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_button_name(JOY_BUTTON_RIGHT_SHOULDER), Vector2(120, -62), 1, Color(0.8, 0.85, 0.88)],
			[ControlProfile.pad_button_name(JOY_BUTTON_Y), Vector2(92, -38), 1, Color(0.96, 0.75, 0.2)],
			[ControlProfile.pad_button_name(JOY_BUTTON_X), Vector2(72, -18), 1, Color(0.35, 0.6, 0.95)],
			[ControlProfile.pad_button_name(JOY_BUTTON_B), Vector2(112, -18), 1, Color(0.93, 0.35, 0.33)],
			[ControlProfile.pad_button_name(JOY_BUTTON_A), Vector2(92, 2), 1, Color(0.3, 0.8, 0.5)],
			[ControlProfile.pad_axis_name(_axis(JOY_AXIS_RIGHT_X)), Vector2(46, 22), 1, Color(0.8, 0.85, 0.88)],
		]

	static func _axis(a: int) -> InputEventJoypadMotion:
		var e := InputEventJoypadMotion.new()
		e.axis = a
		return e

	## The words for one control: every action whose pad binding is this control's name (plus L3 / R3 for the sticks).
	func words_for(ctrl: String) -> Array:
		var out: Array = []
		var seen := {}
		var order := ["fire", "aim", "shove", "kick", "jump", "reload", "swap", "dash", "signature", "sprint", "crouch", "recover", "pause", "move_forward"]
		for a: String in order:
			if ControlProfile.names(a, GP).has(ctrl):
				var w := str(TranslationServer.translate(str(ControlsArt.WORDS.get(a, a))))
				if not seen.has(w): seen[w] = true; out.append(w)
		if ctrl == str(TranslationServer.translate(ControlProfile.LOOK_STICK)): out.append(str(TranslationServer.translate("Look")))
		return out

	func _draw() -> void:
		var k := minf(size.x / VS.x, size.y / VS.y)
		var o := (size - VS * k) * 0.5 + VS * k * 0.5          # diagram origin = the middle of the pad
		_body(o, k)
		var fs := 18
		var left: Array = []
		var right: Array = []
		for it: Array in _items:
			var w := words_for(str(it[0]))
			if w.is_empty(): continue
			(left if int(it[2]) < 0 else right).append([it, w])
		_column(left, o, k, -1, fs)
		_column(right, o, k, 1, fs)

	func _body(o: Vector2, k: float) -> void:
		var fill := Color(0.11, 0.24, 0.29)
		var edge := Color(1, 1, 1, 0.35)
		# two grips and the body
		for sx: float in [-1.0, 1.0]:
			draw_circle(o + Vector2(sx * 92, 38) * k, 46 * k, fill)
			draw_arc(o + Vector2(sx * 92, 38) * k, 46 * k, 0, TAU, 40, edge, 2.0, true)
		draw_style_box(UiTheme.box(fill, int(40 * k), edge, 2, 0), Rect2(o + Vector2(-120, -52) * k, Vector2(240, 96) * k))
		# triggers / bumpers
		for sx: float in [-1.0, 1.0]:
			draw_style_box(UiTheme.box(Color(0.2, 0.4, 0.46), int(8 * k), edge, 2, 0), Rect2(o + Vector2(sx * 96 - 26, -70) * k, Vector2(52, 16) * k))
		# sticks
		for st: Array in [[Vector2(-92, -20), false], [Vector2(46, 22), false]]:
			draw_circle(o + (st[0] as Vector2) * k, 20 * k, Color(0.05, 0.12, 0.15))
			draw_circle(o + (st[0] as Vector2) * k, 14 * k, Color(0.3, 0.5, 0.56))
		# d-pad
		var dp := o + Vector2(-60, 22) * k
		draw_rect(Rect2(dp + Vector2(-5, -17) * k, Vector2(10, 34) * k), Color(0.05, 0.12, 0.15))
		draw_rect(Rect2(dp + Vector2(-17, -5) * k, Vector2(34, 10) * k), Color(0.05, 0.12, 0.15))
		draw_rect(Rect2(dp + Vector2(-4, -16) * k, Vector2(8, 11) * k), Color(0.7, 0.8, 0.84))
		# face buttons
		for it: Array in _items:
			if (it[3] as Color) != Color(0.8, 0.85, 0.88):
				draw_circle(o + (it[1] as Vector2) * k, 11 * k, it[3])
		# start
		draw_circle(o + Vector2(26, -22) * k, 5 * k, Color(0.7, 0.8, 0.84))

	## A column of words on one side, stacked top to bottom in the order of the buttons' heights, each with a leader line.
	func _column(list: Array, o: Vector2, k: float, side: int, fs: int) -> void:
		list.sort_custom(func(a: Array, b: Array) -> bool: return (a[0][1] as Vector2).y < (b[0][1] as Vector2).y)
		var n := list.size()
		if n == 0: return
		var top := 6.0
		var step := (size.y - 12.0) / float(maxi(n, 1))
		step = minf(step, 62.0)
		var y0 := (size.y - step * n) * 0.5
		var x := 6.0 if side < 0 else size.x - 6.0
		for i in n:
			var it: Array = list[i][0]
			var words: Array = list[i][1]
			var ty := y0 + step * (i + 0.5)
			var tp := o + (it[1] as Vector2) * k
			var title := " · ".join(PackedStringArray(words))
			var chip := str(it[0])
			var hot := words.has(TranslationServer.translate("SHOVE")) or words.has(TranslationServer.translate("KICK"))
			# the word block: [chip] title
			var cw := font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0
			var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var total := cw + 8.0 + tw
			var bx := x if side < 0 else x - total
			var chh := minf(30.0, step - 3.0)
			var rect := Rect2(bx, ty - chh * 0.5, cw, chh)
			var chip_col := UiTheme.ACCENT if hot else Color(0.16, 0.33, 0.39)
			var lead_from := Vector2(bx + total + 4.0, ty) if side < 0 else Vector2(bx - 4.0, ty)
			draw_line(lead_from, tp, Color(1, 1, 1, 0.3) if not hot else Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.8), 2.0, true)
			draw_circle(tp, 4.0, Color.WHITE if not hot else UiTheme.ACCENT)
			draw_style_box(UiTheme.box(chip_col, 8, Color(0.05, 0.14, 0.18) if not hot else UiTheme.ACCENT_DARK, 2, 0, 4, Color(0.05, 0.14, 0.18) if not hot else UiTheme.ACCENT_DARK), rect)
			var asc := font.get_ascent(fs)
			var hh := font.get_height(fs)
			draw_string(font, Vector2(rect.position.x, ty - 2.0 - hh * 0.5 + asc), chip, HORIZONTAL_ALIGNMENT_CENTER, cw, fs, UiTheme.INK if hot else Color.WHITE)
			draw_string_outline(font, Vector2(bx + cw + 8.0, ty - hh * 0.5 + asc), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(bx + cw + 8.0, ty - hh * 0.5 + asc), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.ACCENT if hot else Color.WHITE)
