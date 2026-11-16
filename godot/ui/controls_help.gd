class_name ControlsHelp
extends UiPage
## "Controls": ONE scheme at a time, the one the player is on (input/control_profile.gd), with a small switch at the top
## (Touch | Keyboard | Gamepad) to look at another.
##   Touch     the picture of the touch layout (the real TouchControls positions, mirrored when left-handed) and four how-to lines
##   Keyboard  a board of keycaps in cards: Move / Combat (SHOVE and KICK big and yellow) / Moves / Weapons, Emotes, Pause
##   Gamepad   a drawn controller with a word on every button that does something
## Every key and button is READ from the live bindings (ui/controls_art.gd, ControlProfile), so it stays true if one changes.
## "Training" (top right) starts the guided practice (world/tutorial.gd). Opened from the pause menu and Settings > Controls.

signal training_requested

var pic: Control                       ## the board / picture of the scheme shown (the layout test checks it)
var tab_row: HBoxContainer
var tabs := {}                         ## profile -> toggle button
var pages := {}                        ## profile -> page control
var shown := ""                        ## the profile on screen
var training_b: Button
var can_train := true:                 ## false online (a running room cannot be left for the training)
	set(v):
		can_train = v
		if training_b != null: training_b.visible = v
var match_running: Callable = func() -> bool: return false   ## the pause menu says whether a match is on (asks before leaving)
var _armed := false
var _touch_pic: Control
var _pad_pic: Control
var _kb_holder: DragScroll
var _kb_wrap: Control                  ## plain Control between the scroller and the board: it carries the scaled height, never a width
var _kb_cols := 4                      ## columns of the keyboard board now (3 on a narrow canvas)
var _kb_wide := 0.0                    ## natural width of the 4-column board (decides when to go back to 4)

func _init() -> void:
	super._init()
	name = "ControlsHelp"

func _ready() -> void:
	build_frame("Controls")
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(sp)
	training_b = Button.new()
	training_b.name = "Training"
	training_b.text = "Training"
	training_b.theme_type_variation = &"PrimaryButton"
	training_b.custom_minimum_size = Vector2(190, 62)
	training_b.add_theme_font_size_override("font_size", 22)
	training_b.pressed.connect(_on_training)
	training_b.visible = can_train
	head.add_child(training_b)
	tab_row = HBoxContainer.new()
	tab_row.name = "Tabs"
	tab_row.add_theme_constant_override("separation", UiTheme.SP_3)
	col.add_child(tab_row)
	var g := ButtonGroup.new()
	for p: String in ControlProfile.ALL:
		var b := Button.new()
		b.name = "Tab_" + p
		b.text = ControlProfile.display_name(p)
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(0, 62)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(show_profile.bind(p))
		tab_row.add_child(b)
		tabs[p] = b
	var stack := Control.new()
	stack.name = "Pages"
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.clip_contents = false
	col.add_child(stack)
	_build_touch(stack)
	_build_keyboard(stack)
	_build_pad(stack)
	Settings.changed.connect(func(k: String, _v: Variant) -> void:
		if k == "touch_lefty" and _touch_pic != null: _touch_pic.queue_redraw())
	super._ready()
	JuicyButton.attach_all(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for p: String in tabs: (tabs[p] as Button).text = ControlProfile.display_name(p)
		if visible: _refill.call_deferred()

func _fill_page(p: String) -> Control:
	var c := Control.new()
	c.name = "Page_" + p
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	pages[p] = c
	return c

func _build_touch(stack: Control) -> void:
	var page := _fill_page(ControlProfile.TOUCH)
	stack.add_child(page)
	var mid := HBoxContainer.new()       # the picture on the left (names only), the how-to lines on the right
	mid.name = "Mid"
	mid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mid.add_theme_constant_override("separation", UiTheme.SP_4)
	page.add_child(mid)
	_touch_pic = Picture.new()
	_touch_pic.name = "Picture"
	_touch_pic.size_flags_vertical = SIZE_EXPAND_FILL
	_touch_pic.size_flags_horizontal = SIZE_EXPAND_FILL
	_touch_pic.size_flags_stretch_ratio = 3.0
	_touch_pic.custom_minimum_size = Vector2(0, 200)
	mid.add_child(_touch_pic)
	var how := VBoxContainer.new()
	how.name = "How"
	how.size_flags_horizontal = SIZE_EXPAND_FILL
	how.size_flags_stretch_ratio = 2.0
	how.alignment = BoxContainer.ALIGNMENT_CENTER
	how.add_theme_constant_override("separation", UiTheme.SP_3)
	mid.add_child(how)
	for r: Array in [["Move", "Drag anywhere on the left side"], ["Look", "Drag on the right side · double-tap to aim"],
			["Melee", "Tap to shove · hold to kick"], ["Weapons", "Tap a slot to switch"]]:
		var one := VBoxContainer.new()
		one.add_theme_constant_override("separation", 0)
		how.add_child(one)
		var t := Label.new()
		t.text = r[0]
		t.add_theme_font_size_override("font_size", 20)
		t.add_theme_color_override("font_color", UiTheme.ACCENT)
		one.add_child(t)
		var d := Label.new()
		d.text = r[1]
		d.theme_type_variation = &"MutedLabel"
		d.add_theme_font_size_override("font_size", 16)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(120, 0)
		one.add_child(d)

func _build_keyboard(stack: Control) -> void:
	var page := _fill_page(ControlProfile.KEYBOARD)
	stack.add_child(page)
	_kb_holder = DragScroll.new()
	_kb_holder.name = "Scroll"
	_kb_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kb_holder.resized.connect(_fit_board)
	page.add_child(_kb_holder)
	_kb_wrap = Control.new()
	_kb_wrap.name = "Wrap"
	_kb_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	_kb_holder.add_child(_kb_wrap)

func _build_pad(stack: Control) -> void:
	var page := _fill_page(ControlProfile.GAMEPAD)
	stack.add_child(page)

## (Re)build the keyboard board and the controller from the live bindings.
func _refill() -> void:
	if _kb_holder == null: return
	_set_board(_kb_cols)
	_fit_board.call_deferred()
	var pg: Control = pages[ControlProfile.GAMEPAD]
	if _pad_pic != null: _pad_pic.queue_free()
	_pad_pic = ControlsArt.PadPic.new()
	_pad_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pg.add_child(_pad_pic)
	_set_pic()
	JuicyButton.attach_all(self)

## The board with `n` columns (the old one goes).
func _set_board(n: int) -> void:
	for c in _kb_wrap.get_children(): c.queue_free()
	_kb_cols = n
	var nb := ControlsArt.keyboard_board(n)
	_kb_wrap.add_child(nb)
	if shown == ControlProfile.KEYBOARD: pic = nb

func _board() -> Control:
	for i in range(_kb_wrap.get_child_count() - 1, -1, -1):
		var c := _kb_wrap.get_child(i)
		if not c.is_queued_for_deletion(): return c as Control
	return null

## On a bigger window the board grows to fill the page (up to 1.6x); on a narrow canvas it drops to three columns (and the
## page scrolls up and down): text never goes under 15 px and nothing is cut off sideways.
func _fit_board() -> void:
	if _kb_wrap == null or _board() == null: return
	var avail := _kb_holder.size
	if avail.x <= 0.0 or avail.y <= 0.0: return
	var board := _board()
	board.scale = Vector2.ONE
	board.custom_minimum_size = Vector2.ZERO
	board.size = Vector2.ZERO
	var nat := board.size                                   # a container never goes below its content
	if _kb_cols == 4: _kb_wide = nat.x
	if _kb_cols == 4 and nat.x > avail.x + 0.5:
		_set_board(3)
		_fit_board.call_deferred()
		return
	if _kb_cols == 3 and _kb_wide > 0.0 and _kb_wide <= avail.x:
		_set_board(4)
		_fit_board.call_deferred()
		return
	board.custom_minimum_size = Vector2(maxf(avail.x, nat.x), 0)
	board.size = Vector2.ZERO
	var h1 := maxf(board.size.y, 1.0)
	var k := clampf(minf(avail.x / maxf(nat.x, 1.0), avail.y * 0.97 / h1), 1.0, 1.6)
	board.custom_minimum_size = Vector2(avail.x / k, 0)
	board.size = Vector2.ZERO
	board.position = Vector2.ZERO
	board.scale = Vector2(k, k)
	_kb_wrap.custom_minimum_size = Vector2(0, board.size.y * k)

func _set_pic() -> void:
	match shown:
		ControlProfile.TOUCH: pic = _touch_pic
		ControlProfile.KEYBOARD: pic = _board() if _kb_wrap != null and _board() != null else _kb_holder
		_: pic = _pad_pic

## Show one scheme: its tab pressed, the others hidden.
func show_profile(p: String) -> void:
	if not pages.has(p): return
	shown = p
	for k: String in pages:
		(pages[k] as Control).visible = k == p
		(tabs[k] as Button).set_pressed_no_signal(k == p)
	_set_pic()
	_disarm()
	_fit_board.call_deferred()

func open() -> void:
	super.open()
	_refill()
	show_profile(ControlProfile.current())
	_fit_board.call_deferred()
	get_tree().create_timer(0.05).timeout.connect(_fit_board)                    # and once the page has its size

# ---------------- Training ----------------

func _on_training() -> void:
	if not can_train: return
	if bool(match_running.call()) and not _armed:        # leaving a running match: ask once (the same button again)
		_armed = true
		training_b.text = tr("Leave this match?")
		get_tree().create_timer(3.0).timeout.connect(_disarm)
		return
	_disarm()
	training_requested.emit()
	Tutorial.launch(get_tree())

func _disarm() -> void:
	_armed = false
	if training_b != null: training_b.text = "Training"

## The phone picture: a screen outline at the canvas aspect, the controls where TouchControls puts them, labels.
class Picture extends Control:
	const VS := Vector2(1170, 540)          ## the canvas the touch layer lays out on
	var font: Font
	var _sr := Rect2()

	func _ready() -> void:
		font = UiTheme.font(600)
		resized.connect(queue_redraw)

	## Screen rect inside this control (letterboxed at the canvas aspect).
	func screen() -> Rect2:
		var k := minf(size.x / VS.x, size.y / VS.y)
		var s := VS * k
		return Rect2((size - s) * 0.5, s)

	## Canvas point -> picture point (mirrored when left-handed).
	func _p(sr: Rect2, v: Vector2) -> Vector2:
		var x := v.x
		if bool(Settings.get_value("touch_lefty", false)): x = VS.x - x
		return sr.position + Vector2(x, v.y) * (sr.size.x / VS.x)

	func _btn(b: Array) -> Array:
		var u := TouchControls.UNIT
		var sz: float = float(b[3]) * u
		return [Vector2(VS.x - float(b[4]) * u - sz / 2.0, VS.y - float(b[5]) * u - sz / 2.0), sz / 2.0]

	func _draw() -> void:
		var sr := screen()
		var k := sr.size.x / VS.x
		draw_style_box(UiTheme.box(Color(0.02, 0.07, 0.09, 1.0), 26, Color(1, 1, 1, 0.25), 3), sr.grow(6))
		var mid := sr.position.x + sr.size.x * 0.45
		draw_line(Vector2(mid, sr.position.y + 12), Vector2(mid, sr.end.y - 12), Color(1, 1, 1, 0.12), 2.0)
		var fs := clampi(int(30.0 * k), UiTheme.MIN_FONT + 1, 26)
		var fs2 := UiTheme.MIN_FONT
		var lefty := bool(Settings.get_value("touch_lefty", false))
		var u := TouchControls.UNIT
		var labels: Array = []   ## [anchor point, side (-1 left of it, 1 right), title, sub]
		# move stick
		var sh := Vector2(TouchControls.STICK_R * u + 40.0 * u, VS.y - TouchControls.STICK_R * u - 34.0 * u)
		var sc := _p(sr, sh)
		draw_circle(sc, TouchControls.STICK_R * u * k, Color(1, 1, 1, 0.12))
		draw_arc(sc, TouchControls.STICK_R * u * k, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
		draw_circle(sc, TouchControls.STICK_R * u * k * 0.45, Color(1, 1, 1, 0.55))
		labels.append([sc + Vector2(0, -TouchControls.STICK_R * u * k - 8), 0, "Move", ""])
		# look area
		var lc := _p(sr, Vector2(VS.x * 0.6, VS.y * 0.33))
		_arrows(lc, 60.0 * k)
		labels.append([lc + Vector2(0, 60.0 * k + 8.0), 2, "Look", ""])
		# action buttons
		var cols := {"fire": UiTheme.ACCENT, "jump": Color(0.22, 0.71, 0.66), "melee": Color(0.94, 0.45, 0.35), "context": Color(1, 1, 1, 0.6)}
		var words := {"fire": ["Fire (hold)", ""], "jump": ["Jump", ""], "melee": ["Melee", ""], "context": ["Dash / Reload", ""]}
		var place := {"fire": 2, "jump": -1, "melee": 0, "context": -1}   ## where each label goes: below, left, above
		for b: Array in TouchControls.BUTTONS:
			var br := _btn(b)
			var c := _p(sr, br[0])
			var r: float = br[1] * k
			var col: Color = cols[b[0]]
			if b[0] == "context":
				draw_arc(c, r, 0, TAU, 36, col, 2.0, true)
			else:
				draw_circle(c, r, Color(col.r, col.g, col.b, 0.85))
			var side: int = place[b[0]]
			if lefty and absi(side) == 1: side = -side
			var off := Vector2(side * (r + 6), 0) if absi(side) == 1 else Vector2(0, -r - 4) if side == 0 else Vector2(0, r + 4)
			labels.append([c + off, side, words[b[0]][0], words[b[0]][1]])
		# pause + emote buttons (top corner)
		var ps := TouchControls.PAUSE_SIZE * u
		var pc := _p(sr, Vector2(VS.x - 8.0 * u - ps / 2.0, 6.0 * u + ps / 2.0))
		draw_rect(Rect2(pc - Vector2(ps, ps) * k * 0.5, Vector2(ps, ps) * k), Color(1, 1, 1, 0.25), true)
		draw_rect(Rect2(pc + Vector2(-ps * 0.18, -ps * 0.22) * k, Vector2(ps * 0.12, ps * 0.44) * k), Color.WHITE, true)
		draw_rect(Rect2(pc + Vector2(ps * 0.06, -ps * 0.22) * k, Vector2(ps * 0.12, ps * 0.44) * k), Color.WHITE, true)
		var side2 := -1 if not lefty else 1
		labels.append([pc + Vector2(side2 * (ps * k * 0.5 + 6), 0), side2, "Pause", ""])
		var ec := pc + Vector2(0, ps * k * 1.35)
		draw_circle(ec, ps * k * 0.42, Color(1, 1, 1, 0.25))
		draw_circle(ec + Vector2(-ps * 0.13, -ps * 0.08) * k, ps * 0.05 * k, Color.WHITE)
		draw_circle(ec + Vector2(ps * 0.13, -ps * 0.08) * k, ps * 0.05 * k, Color.WHITE)
		draw_arc(ec + Vector2(0, ps * 0.02) * k, ps * 0.2 * k, 0.3, PI - 0.3, 12, Color.WHITE, 2.0, true)
		labels.append([ec + Vector2(side2 * (ps * k * 0.5 + 6), 0), side2, "Emotes", ""])
		# hotbar
		var hw := 78.0
		var hc := sr.position + Vector2(sr.size.x * 0.5, sr.size.y - 46.0 * k)
		for i in 3:
			var rr := Rect2(hc + Vector2((i - 1.5) * (hw + 8) * k, -hw * 0.5 * k), Vector2(hw, hw) * k)
			draw_style_box(UiTheme.box(Color(1, 1, 1, 0.12 if i else 0.3), int(10 * k), Color(1, 1, 1, 0.4), 2), rr)
		labels.append([hc + Vector2(0, -hw * 0.5 * k - 6), 0, "Weapons", ""])
		_sr = sr
		for l: Array in labels: _label(l[0], int(l[1]), str(l[2]), str(l[3]), fs, fs2)

	func _arrows(c: Vector2, r: float) -> void:
		var col := Color(1, 1, 1, 0.55)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var tip := c + d * r
			draw_line(c + d * r * 0.3, tip, col, 3.0, true)
			var n := Vector2(-d.y, d.x)
			draw_line(tip, tip - d * r * 0.25 + n * r * 0.18, col, 3.0, true)
			draw_line(tip, tip - d * r * 0.25 - n * r * 0.18, col, 3.0, true)

	## A title (and a smaller sub line) next to `at`: side -1 = to its left, 1 = to its right, 0 = centred above,
	## 2 = centred below; kept inside the screen picture.
	func _label(at: Vector2, side: int, title: String, sub: String, fs: int, fs2: int) -> void:
		title = tr(title)   # drawn with draw_string, so it does not translate itself
		sub = tr(sub)
		var w1 := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w2 := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x if sub != "" else 0.0
		var h := fs + (fs2 + 2 if sub != "" else 0)
		var y0 := at.y - h * 0.5 if absi(side) == 1 else at.y - h if side == 0 else at.y
		for i in 2:
			var t := title if i == 0 else sub
			if t == "": continue
			var f := fs if i == 0 else fs2
			var w := w1 if i == 0 else w2
			var x := at.x - w if side == -1 else at.x if side == 1 else at.x - w * 0.5
			x = clampf(x, _sr.position.x + 6.0, maxf(_sr.position.x + 6.0, _sr.end.x - w - 6.0))
			var y := y0 + f * 0.8 + (0.0 if i == 0 else fs + 2.0)
			draw_string_outline(font, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, f, 5, Color(0, 0, 0, 0.75))
			draw_string(font, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color.WHITE if i == 0 else UiTheme.MUTED)
