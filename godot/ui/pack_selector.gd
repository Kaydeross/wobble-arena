class_name PackSelector
extends UiPage
## The pack selector: a full-screen deck of the DLC packs (Construction, On Fire, Ho Ho Ho, Hey Mate; the hub's order, from
## PackRegistry / DLCPacks) over the title. Big animated cards (the pack's colour, its drawn PackBadge, name, tagline, three drawn
## weapon silhouettes, OWNED or a padlock and the price), the centred card scaled up, the others dimmed and smaller with parallax
## between the layers, swipe / arrow buttons / page dots / keyboard (left, right, accept) / gamepad, and one big ENTER button:
## PLAY when the pack is owned (its transition plays, ui/pack_transition.gd, and the hub opens at the switch point), UNLOCK PACK
## when it is not (the existing unlock flow: the hub's coins / code card).
## The secret code is NOT here: it stays in Settings > About (seven taps on the version line) and unlocks every pack at once.
##
## Signals (scripts/main.gd connects them):
##   play_requested(pack_id)    an owned pack: the transition has covered the screen, open its hub now
##   unlock_requested(pack_id)  a locked pack: open the hub on it (coins or the code)
## Navigation CLAMPS at both ends (no wrap): the arrow on the end card is dimmed.

signal play_requested(pack_id: String)
signal unlock_requested(pack_id: String)
signal selected(pack_id: String)

const TOUCH := 60.0
const SIDE_SCALE := 0.8
static var _glow: GradientTexture2D

## A soft round glow (white in the middle, clear at the rim), tinted by the caller: no stacked rings, so no banding.
static func glow() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow

const ICONS := {
	"construction": ["hammer", "cone", "nut"],
	"kitchen": ["pan", "cleaver", "flame"],
	"xmas": ["cane", "gift", "star"],
	"australia": ["boomerang", "bat", "jar"],
}

var packs: Array[DLCPackData] = []
var index := 0                       ## the centred pack
var pos := 0.0                       ## the animated position (index units)
var cards: Array = []                ## Card per pack
var stage: Control
var backdrop: Backdrop
var foot: HBoxContainer
var prev_b: Button
var next_b: Button
var enter_b: Button
var dots_row: HBoxContainer
var dots_bar: HBoxContainer
var unit := 1.0                      ## touch-size factor: 1 in landscape, up to 2.45 in portrait (the canvas is 3 px per pt there)
var dots: Array[Button] = []
var coins_chip: PanelContainer
var coins_l: Label
var busy := false                    ## a transition is running (ENTER is ignored)
var last_transition: PackTransition
var _drag := false
var _drag_x := 0.0
var _drag_pos := 0.0
var _drag_moved := 0.0
var _vel := 0.0
var _last_x := 0.0
var _last_ms := 0
var _t := 0.0

func _init() -> void:
	super._init()
	name = "PackSelector"

func _ready() -> void:
	build_frame("Packs")
	backdrop = Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	move_child(backdrop, 1)               # above the opaque Bg, under the safe-area column
	var sp := Control.new()
	sp.name = "Spacer"
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	dots_row = HBoxContainer.new()
	dots_row.name = "Dots"
	dots_row.add_theme_constant_override("separation", 12)
	head.add_child(dots_row)
	_build_chip()
	stage = Control.new()
	stage.name = "Stage"
	stage.size_flags_vertical = SIZE_EXPAND_FILL
	stage.size_flags_horizontal = SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.focus_mode = Control.FOCUS_NONE
	stage.gui_input.connect(_on_stage_input)
	stage.resized.connect(_layout)
	col.add_child(stage)
	dots_bar = HBoxContainer.new()                  # portrait: the page dots get their own row above ENTER
	dots_bar.name = "DotsBar"
	dots_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(dots_bar)
	foot = HBoxContainer.new()
	foot.name = "Foot"
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", UiTheme.SP_4)
	col.add_child(foot)
	prev_b = _arrow("Prev", "‹", -1)
	foot.add_child(prev_b)
	enter_b = Button.new()
	enter_b.name = "Enter"
	enter_b.theme_type_variation = &"PrimaryButton"
	enter_b.custom_minimum_size = Vector2(300, TOUCH)
	enter_b.add_theme_font_override("font", UiTheme.font(700))
	enter_b.pressed.connect(enter)
	foot.add_child(enter_b)
	next_b = _arrow("Next", "›", 1)
	foot.add_child(next_b)
	JuicyButton.attach_all(foot)
	title_l.text = "Packs"
	Save.changed.connect(func() -> void: if visible: refresh())
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	set_process(false)
	reload()
	super._ready()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh.call_deferred()

func _build_chip() -> void:
	coins_chip = PanelContainer.new()
	coins_chip.name = "Coins"
	coins_chip.theme_type_variation = &"ChipPanel"
	coins_chip.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(coins_chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coins_chip.add_child(row)
	row.add_child(LockerScreen.LockerIcon.new("coin", 22))
	coins_l = Label.new()
	coins_l.name = "N"
	coins_l.add_theme_font_size_override("font_size", 20)
	coins_l.add_theme_font_override("font", UiTheme.font(700))
	coins_l.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(coins_l)

func _arrow(n: String, glyph: String, dir: int) -> Button:
	var b := Button.new()
	b.name = n
	b.text = glyph
	b.custom_minimum_size = Vector2(TOUCH, TOUCH)
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_font_override("font", UiTheme.font(700))
	b.pressed.connect(step.bind(dir))
	return b

# ---------------------------------------------------------------- the packs

## Reads the packs again (tests add packs): the hub's order first, then any other valid pack.
func reload() -> void:
	var keep := current_id()
	var all := DLCPacks.all(Content.weapons, Content.maps)
	packs = []
	for id: String in PackRegistry.ids():
		for d: DLCPackData in all:
			if d.pack_id == id: packs.append(d)
	for d: DLCPackData in all:
		if not packs.has(d): packs.append(d)
	for c: Control in cards: c.queue_free()
	cards.clear()
	for b: Button in dots: b.queue_free()
	dots.clear()
	for i in packs.size():
		var c := Card.new(packs[i])
		c.name = "Card_" + packs[i].pack_id
		stage.add_child(c)
		cards.append(c)
		var d := Button.new()
		d.name = "Dot_" + packs[i].pack_id
		d.custom_minimum_size = Vector2(TOUCH, TOUCH)
		d.flat = true
		for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			d.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		d.draw.connect(_draw_dot.bind(d, i))
		d.pressed.connect(go_to.bind(i))
		dots_row.add_child(d)
		dots.append(d)
	index = 0
	for i in packs.size():
		if packs[i].pack_id == keep: index = i
	pos = float(index)
	refresh()

func current_id() -> String:
	return packs[index].pack_id if index >= 0 and index < packs.size() else ""

func current() -> DLCPackData:
	return packs[index] if index >= 0 and index < packs.size() else null

func owned(i: int) -> bool:
	return i >= 0 and i < packs.size() and packs[i].is_unlocked

## Texts and states (read from the profile now, never remembered).
func refresh() -> void:
	if enter_b == null: return
	if coins_l != null: coins_l.text = str(Save.coins)
	for i in cards.size(): (cards[i] as Card).refresh()
	var d := current()
	if d != null:
		var own := d.is_unlocked
		enter_b.text = tr("PLAY") if own else tr("UNLOCK PACK")
		enter_b.tooltip_text = (tr("Open the %s hub") % tr(d.display_name)) if own else (tr("Unlock %s first") % tr(d.display_name))
		enter_b.set("accessibility_name", enter_b.tooltip_text)
		_style_enter(d.accent_color)
	prev_b.disabled = index <= 0
	next_b.disabled = index >= packs.size() - 1
	prev_b.tooltip_text = tr("Previous pack")
	next_b.tooltip_text = tr("Next pack")
	prev_b.set("accessibility_name", prev_b.tooltip_text)
	next_b.set("accessibility_name", next_b.tooltip_text)
	for i in dots.size():
		var nm := tr(packs[i].display_name)
		dots[i].tooltip_text = nm
		dots[i].set("accessibility_name", "%s. %s" % [tr("Pack %d of %d") % [i + 1, packs.size()], nm])
		dots[i].queue_redraw()
	_layout()

func _style_enter(accent: Color) -> void:
	var ink := UiTheme.INK
	var white := Color.WHITE
	var lum := accent.get_luminance()
	var text := ink if lum > 0.42 else white
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var bg := accent
		if st == "hover": bg = accent.lightened(0.12)
		if st == "pressed" or st == "hover_pressed": bg = accent.darkened(0.12)
		var sb := UiTheme.box(bg, UiTheme.RADIUS, accent.darkened(0.4), 3, 6, 5, accent.darkened(0.35))
		if st == "focus":
			sb.draw_center = false
			sb.border_color = Color.WHITE
			sb.border_width_bottom = 3
		enter_b.add_theme_stylebox_override(st, sb)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		enter_b.add_theme_color_override(k, text)

# ---------------------------------------------------------------- navigation

## Moves the centred pack by `dir` (clamped). true = it moved.
func step(dir: int) -> bool:
	return go_to(index + dir)

func go_to(i: int) -> bool:
	if packs.is_empty(): return false
	i = clampi(i, 0, packs.size() - 1)
	if i == index: return false
	index = i
	selected.emit(current_id())
	_sfx("hover", 0.5)
	refresh()
	return true

func open_at(id: String) -> void:
	for i in packs.size():
		if packs[i].pack_id == id: index = i
	pos = float(index)
	busy = false
	open()
	refresh()

func open() -> void:
	super.open()
	refresh()
	if Tier.is_pc() and enter_b != null: enter_b.grab_focus.call_deferred()

func back() -> bool:
	if busy and last_transition != null and is_instance_valid(last_transition): last_transition.skip()
	close()
	return true

## ENTER / PLAY / UNLOCK on the centred pack. An owned pack plays its transition, then the hub opens (play_requested);
## a locked pack goes straight to the unlock flow (unlock_requested).
func enter() -> void:
	var d := current()
	if d == null or busy: return
	var id := d.pack_id
	if not d.is_unlocked:
		unlock_requested.emit(id)
		return
	busy = true
	var host: Node = get_parent() if get_parent() != null else self
	last_transition = PackTransition.play(id, host, _at_switch.bind(id), func() -> void: busy = false)
	if last_transition == null: busy = false

## The screen is covered: the page closes quietly (no `closed`: the owner's title is not what comes next) and the hub opens.
func _at_switch(id: String) -> void:
	visible = false
	play_requested.emit(id)

func _input(e: InputEvent) -> void:
	if not is_visible_in_tree() or busy: return
	if e.is_action_pressed("ui_left") and not e.is_echo():
		get_viewport().set_input_as_handled()
		step(-1)
	elif e.is_action_pressed("ui_right") and not e.is_echo():
		get_viewport().set_input_as_handled()
		step(1)

# ---------------------------------------------------------------- swipe

func _on_stage_input(e: InputEvent) -> void:
	if busy: return
	var spacing := _spacing()
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			_drag = true
			_drag_x = mb.position.x
			_last_x = mb.position.x
			_last_ms = Time.get_ticks_msec()
			_drag_pos = pos
			_drag_moved = 0.0
			_vel = 0.0
		elif _drag:
			_drag = false
			if _drag_moved < 14.0:
				_tap(mb.position)
			else:
				var want := roundi(pos + clampf(-_vel / maxf(1.0, spacing) * 0.18, -0.49, 0.49))      # a flick helps, but never skips a card
				go_to(want)
		stage.accept_event()
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		_drag_moved = maxf(_drag_moved, absf(mm.position.x - _drag_x))
		var now := Time.get_ticks_msec()
		_vel = lerpf(_vel, mm.relative.x / maxf(0.016, (now - _last_ms) / 1000.0), 0.5)
		_last_ms = now
		if _drag_moved >= 14.0:
			pos = clampf(_drag_pos - (mm.position.x - _drag_x) / maxf(1.0, spacing), -0.25, packs.size() - 0.75)
			_layout_cards()
		stage.accept_event()

## A tap on a side card brings it to the middle.
func _tap(at: Vector2) -> void:
	for i in cards.size():
		var c: Card = cards[i]
		if i == index: continue
		if Rect2(c.position + c.size * 0.5 - c.size * c.scale * 0.5, c.size * c.scale).has_point(at):
			go_to(i)
			return

# ---------------------------------------------------------------- layout and idle animation

func _spacing() -> float:
	if cards.is_empty(): return 300.0
	return (cards[0] as Card).size.x * 0.62

func _unit() -> float:
	var vs := size
	return 1.0 if vs.y <= vs.x else clampf(vs.y / maxf(1.0, vs.x) * 1.12, 1.0, 2.45)

func _layout() -> void:
	if stage == null or cards.is_empty() or not is_inside_tree(): return
	unit = _unit()
	var portrait := size.y > size.x
	var u := unit
	# the page's own controls grow with the touch-size factor (portrait)
	back_b.custom_minimum_size = BACK_SIZE * u
	back_b.add_theme_font_size_override("font_size", int(round(22.0 * u)))
	title_l.add_theme_font_size_override("font_size", int(round(34.0 * u)))
	coins_l.add_theme_font_size_override("font_size", int(round(20.0 * u)))
	var avail := size.x - float(safe.get_theme_constant("margin_left") + safe.get_theme_constant("margin_right"))
	var arrow := Vector2(TOUCH, TOUCH) * u
	prev_b.custom_minimum_size = arrow
	next_b.custom_minimum_size = arrow
	prev_b.add_theme_font_size_override("font_size", int(round(36.0 * u)))
	next_b.add_theme_font_size_override("font_size", int(round(36.0 * u)))
	var ew := minf(300.0 * u, avail - 2.0 * (arrow.x + 16.0 * u) - 4.0)
	enter_b.custom_minimum_size = Vector2(maxf(160.0, ew), TOUCH * u)
	enter_b.add_theme_font_size_override("font_size", int(round(26.0 * u)))
	foot.add_theme_constant_override("separation", int(round(16.0 * u)))
	col.add_theme_constant_override("separation", int(round(UiTheme.SP_3 * u)))
	for d: Button in dots: d.custom_minimum_size = arrow
	dots_row.add_theme_constant_override("separation", int(round(12.0 * u)))
	# the dots live in the header (landscape) or in their own row above ENTER (portrait)
	var want: Container = dots_bar if portrait else head
	if dots_row.get_parent() != want:
		dots_row.get_parent().remove_child(dots_row)
		want.add_child(dots_row)
		if not portrait: head.move_child(dots_row, coins_chip.get_index())
	dots_bar.visible = portrait
	var s := stage.size
	if s.x < 10.0 or s.y < 10.0: return
	var wide := s.x / s.y > 1.15
	var h := s.y * 0.96
	var w := minf(s.x * 0.5, h * 1.75) if wide else minf(s.x * 0.8, h * 0.82)
	if not wide: h = minf(h, w * 1.3)
	h = minf(h, s.y * 0.96)
	for c: Card in cards:
		c.size = Vector2(w, h)
		c.pivot_offset = Vector2(w, h) * 0.5
		c.layout(wide, u)
	_layout_cards()
	# the header: the coin chip steps aside when it would not fit
	coins_chip.visible = true
	if head.get_combined_minimum_size().x > maxf(avail, 100.0): coins_chip.visible = false

func _layout_cards() -> void:
	var s := stage.size
	var sp := _spacing()
	for i in cards.size():
		var c: Card = cards[i]
		var d := float(i) - pos
		var ad := absf(d)
		c.visible = ad < 2.2
		if not c.visible: continue
		var near := minf(ad, 1.0)
		var sc := lerpf(1.0, SIDE_SCALE, near)
		var x := s.x * 0.5 + signf(d) * (near * sp + maxf(ad - 1.0, 0.0) * sp * 0.55)
		c.scale = Vector2(sc, sc)
		c.position = Vector2(x - c.size.x * 0.5, (s.y - c.size.y) * 0.5)
		c.modulate = Color(1, 1, 1, lerpf(1.0, 0.62, near) * (1.0 - clampf(ad - 1.6, 0.0, 0.6) / 0.6))
		c.z_index = 10 - int(round(ad * 4.0))
		c.parallax = -d
		c.focus_amount = 1.0 - near
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.pos = pos
	backdrop.queue_redraw()

func _process(dt: float) -> void:
	_t += dt
	var target := float(index)
	if not _drag and not is_equal_approx(pos, target):
		pos = lerpf(pos, target, 1.0 - exp(-dt * 12.0))
		if absf(pos - target) < 0.002: pos = target
		_layout_cards()
	for c: Card in cards:
		if c.visible and c.focus_amount > 0.01: c.tick(_t)
	backdrop.tick(_t, dt, packs)

func _draw_dot(b: Button, i: int) -> void:
	var on := i == index
	var acc := packs[i].accent_color
	var c := b.size * 0.5
	if on:
		b.draw_circle(c, 11.0, Color(acc, 0.28))
		b.draw_circle(c, 8.0, acc)
	else:
		b.draw_circle(c, 6.0, Color(1, 1, 1, 0.38))
	if b.has_focus(): b.draw_arc(c, 17.0, 0.0, TAU, 28, Color.WHITE, 3.0, true)

func _sfx(n: String, vol: float) -> void:
	if Engine.get_main_loop() == null: return
	var a: Node = get_node_or_null("/root/Audio")
	if a != null and a.has_method("play"): a.call("play", n, vol)

# ---------------------------------------------------------------- the weapon silhouettes

## A small drawn silhouette (`kind`) in the square `r` on `ci` (only valid while `ci` is drawing).
static func draw_icon(ci: CanvasItem, kind: String, r: Rect2, col: Color) -> void:
	var s := r.size.x
	var o := r.position
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var steel := Color("#b9c3cc")
	var wood := Color("#c58a4a")
	var dark := Color("#2b2e36")
	match kind:
		"hammer":
			ci.draw_line(P.call(0.5, 0.95), P.call(0.5, 0.3), wood, s * 0.12)
			ci.draw_rect(Rect2(P.call(0.16, 0.12), Vector2(0.68, 0.24) * s), steel)
			ci.draw_rect(Rect2(P.call(0.16, 0.12), Vector2(0.14, 0.24) * s), steel.darkened(0.2))
		"cone":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.08), P.call(0.8, 0.82), P.call(0.2, 0.82)]), Color("#ff7a1a"))
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.42, 0.38), P.call(0.58, 0.38), P.call(0.64, 0.54), P.call(0.36, 0.54)]), Color("#f4f1ea"))
			ci.draw_rect(Rect2(P.call(0.12, 0.8), Vector2(0.76, 0.12) * s), dark)
		"nut":
			var pts := PackedVector2Array()
			for i in 6: pts.append(P.call(0.5 + cos(i * TAU / 6.0) * 0.4, 0.5 + sin(i * TAU / 6.0) * 0.4))
			ci.draw_colored_polygon(pts, steel)
			ci.draw_circle(P.call(0.5, 0.5), s * 0.15, dark)
		"pan":
			ci.draw_line(P.call(0.62, 0.5), P.call(0.97, 0.28), dark.lightened(0.15), s * 0.1)
			ci.draw_circle(P.call(0.4, 0.58), s * 0.34, dark)
			ci.draw_circle(P.call(0.4, 0.58), s * 0.26, Color("#454a55"))
			ci.draw_circle(P.call(0.38, 0.56), s * 0.1, Color("#f6f1e6"))
			ci.draw_circle(P.call(0.38, 0.56), s * 0.045, Color("#ffc21a"))
		"cleaver":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.12, 0.2), P.call(0.74, 0.2), P.call(0.74, 0.7), P.call(0.12, 0.7)]), steel)
			ci.draw_rect(Rect2(P.call(0.74, 0.34), Vector2(0.22, 0.14) * s), wood.darkened(0.3))
			ci.draw_circle(P.call(0.2, 0.3), s * 0.04, dark)
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.04), P.call(0.74, 0.42), P.call(0.78, 0.7), P.call(0.5, 0.94), P.call(0.22, 0.7), P.call(0.28, 0.4), P.call(0.42, 0.5)]), Color("#ff6a1a"))
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.42), P.call(0.64, 0.7), P.call(0.5, 0.88), P.call(0.36, 0.7)]), Color("#ffd23d"))
		"cane":
			var red := Color("#e0353a")
			var white := Color("#f4f1ea")
			ci.draw_line(P.call(0.62, 0.96), P.call(0.62, 0.34), white, s * 0.16)
			ci.draw_arc(P.call(0.4, 0.34), s * 0.22, PI, TAU, 14, white, s * 0.16, true)
			for k in 4: ci.draw_line(P.call(0.55, 0.86 - k * 0.15), P.call(0.69, 0.78 - k * 0.15), red, s * 0.07)
		"gift":
			ci.draw_rect(Rect2(P.call(0.14, 0.38), Vector2(0.72, 0.5) * s), Color("#e0353a"))
			ci.draw_rect(Rect2(P.call(0.1, 0.3), Vector2(0.8, 0.14) * s), Color("#f05a5f"))
			ci.draw_rect(Rect2(P.call(0.45, 0.3), Vector2(0.1, 0.58) * s), Color("#2fa05a"))
			ci.draw_circle(P.call(0.38, 0.22), s * 0.1, Color("#2fa05a"))
			ci.draw_circle(P.call(0.62, 0.22), s * 0.1, Color("#2fa05a"))
		"star":
			var pts2 := PackedVector2Array()
			for i in 10:
				var rr := 0.44 if i % 2 == 0 else 0.19
				pts2.append(P.call(0.5 + cos(-PI / 2.0 + i * PI / 5.0) * rr, 0.54 + sin(-PI / 2.0 + i * PI / 5.0) * rr))
			ci.draw_colored_polygon(pts2, Color("#ffd23d"))
		"boomerang":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.06, 0.3), P.call(0.16, 0.18), P.call(0.5, 0.6), P.call(0.84, 0.18), P.call(0.94, 0.3), P.call(0.58, 0.86), P.call(0.42, 0.86)]), Color("#b8651f"))
			for x in [0.2, 0.34, 0.66, 0.8]: ci.draw_circle(P.call(x, 0.32 + absf(x - 0.5) * 0.0 + (0.1 if x > 0.3 and x < 0.7 else 0.0)), s * 0.03, Color("#fbe9c0"))
		"bat":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.3, 0.04), P.call(0.7, 0.04), P.call(0.66, 0.66), P.call(0.34, 0.66)]), Color("#e6c07a"))
			ci.draw_rect(Rect2(P.call(0.44, 0.64), Vector2(0.12, 0.3) * s), Color("#3d7a4a"))
			ci.draw_line(P.call(0.5, 0.1), P.call(0.5, 0.55), Color("#b8924a"), s * 0.03)
		"jar":
			ci.draw_rect(Rect2(P.call(0.22, 0.28), Vector2(0.56, 0.62) * s), Color("#3b1d10"))
			ci.draw_rect(Rect2(P.call(0.26, 0.14), Vector2(0.48, 0.16) * s), Color("#d8333a"))
			ci.draw_rect(Rect2(P.call(0.28, 0.44), Vector2(0.44, 0.26) * s), Color("#ffcf2a"))
		_:
			ci.draw_circle(r.get_center(), s * 0.3, col)

# ---------------------------------------------------------------- the card

class Card extends Control:
	var data: DLCPackData
	var pid := ""
	var accent := Color("#ffc21a")
	var badge: PackBadge
	var lock: Control
	var name_l: Label
	var tag_l: Label
	var status: HBoxContainer
	var status_icon: Control
	var status_l: Label
	var parallax := 0.0                 ## the card's distance from the middle, in cards (the layers shift against it)
	var focus_amount := 0.0             ## 1 = the centred card
	var wide := true
	var unit := 1.0
	var is_owned := false
	var _t := 0.0
	var rail: Rail
	var _icon_rects: Array[Rect2] = []

	func _init(d: DLCPackData) -> void:
		data = d
		pid = d.pack_id
		accent = d.accent_color
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var f := UiTheme.font(700)
		badge = PackBadge.new(d.badge_kind(), accent, 100.0)
		badge.name = "Badge"
		add_child(badge)
		lock = ConstructionStyle.Padlock.new()
		lock.name = "Lock"
		add_child(lock)
		name_l = Label.new()
		name_l.name = "Name"
		name_l.add_theme_font_override("font", f)
		name_l.add_theme_color_override("font_color", accent.lightened(0.15))
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_l)
		tag_l = Label.new()
		tag_l.name = "Tag"
		tag_l.theme_type_variation = &"MutedLabel"
		tag_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tag_l)
		rail = Rail.new(self)
		add_child(rail)
		status = HBoxContainer.new()
		status.name = "Status"
		status.add_theme_constant_override("separation", 8)
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(status)
		status_l = Label.new()
		status_l.name = "State"
		status_l.add_theme_font_override("font", f)
		status_l.mouse_filter = Control.MOUSE_FILTER_IGNORE

	func refresh() -> void:
		is_owned = data.is_unlocked
		name_l.text = tr(data.display_name).to_upper()
		var info := SetupWizard.mode_short(PackRegistry.mode_of(pid)) if PackRegistry.has(pid) else data.subtitle
		tag_l.text = tr(info)
		for c in status.get_children():
			status.remove_child(c)
			if c != status_l: c.queue_free()
		if is_owned:
			status_icon = LockerScreen.LockerIcon.new("check", 22.0 * unit)
			status.add_child(status_icon)
			status_l.text = tr("Owned").to_upper()
			status_l.add_theme_color_override("font_color", UiTheme.GOOD)
		else:
			status_icon = LockerScreen.LockerIcon.new("coin", 22.0 * unit)
			status.add_child(status_icon)
			status_l.text = str(DlcUnlock.price(pid))
			status_l.add_theme_color_override("font_color", UiTheme.ACCENT)
		status.add_child(status_l)
		badge.set_locked(not is_owned)
		lock.visible = not is_owned
		layout(wide)
		queue_redraw()

	## Positions the words and the badge for a card of this size; `w` = the wide (side by side) arrangement.
	func layout(w: bool, u := 1.0) -> void:
		wide = w
		unit = u
		var W := size.x
		var H := size.y
		if W < 10.0: return
		var pad := clampf(H * 0.07, 12.0, 26.0)
		var strip := H * 0.09 + 16.0
		var bs := clampf(H * 0.5, 56.0, 160.0) if wide else clampf(minf(W * 0.42, H * 0.34), 56.0, 190.0)
		badge.custom_minimum_size = Vector2(bs, bs)
		badge.size = Vector2(bs, bs)
		var tx: float
		var tw: float
		var ty := pad
		_icon_rects.clear()
		var isz := clampf(bs * 0.3, 24.0, 44.0)
		if wide:
			badge.position = Vector2(pad, pad)
			tx = pad + bs + pad
			tw = W - tx - pad
			var iy := pad + bs + pad * 0.6
			for i in 3: _icon_rects.append(Rect2(pad + i * (isz + 6.0) + (bs - 3 * isz - 12.0) * 0.5, iy, isz, isz))
		else:
			badge.position = Vector2((W - bs) * 0.5, pad)
			tx = pad
			tw = W - 2.0 * pad
			ty = pad + bs + pad * 0.5
		var lw := clampf(bs * 0.2, 16.0, 28.0)
		lock.custom_minimum_size = Vector2(lw, lw * 1.2)
		lock.size = lock.custom_minimum_size
		lock.position = badge.position + Vector2(bs - lw * 0.8, bs - lw * 1.1)
		var f := UiTheme.font(700)
		var ns := FitText.size_for(f, name_l.text, int(clampf(H * 0.17, 20.0, 44.0 * unit)), tw, FitText.MIN_SIZE)
		name_l.add_theme_font_size_override("font_size", ns)
		name_l.position = Vector2(tx, ty)
		name_l.size = Vector2(tw, f.get_height(ns))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_CENTER
		var sh := 34.0
		var st_fs := FitText.size_for(f, status_l.text, int(22.0 * unit), tw - 40.0 * unit, FitText.MIN_SIZE)
		status_l.add_theme_font_size_override("font_size", st_fs)
		if status_icon != null: status_icon.custom_minimum_size = Vector2(22.0, 22.0) * unit
		status.size = Vector2.ZERO
		status.size = status.get_combined_minimum_size()
		status.position = Vector2(tx if wide else (W - status.size.x) * 0.5, H - strip - pad * 0.6 - status.size.y)
		# the tagline between the name and the status row (wraps to the lines that fit, never clipped)
		var top := name_l.position.y + name_l.size.y + 4.0
		var room := status.position.y - top - 6.0
		var tf := tag_l.get_theme_font("font")
		var fs := int(24.0 * unit)
		tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_CENTER
		tag_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tag_l.clip_text = false
		var txt := tag_l.text
		while fs > UiTheme.MIN_FONT:
			var lines := int(ceil(FitText.line_width(tf, txt, fs) / maxf(1.0, tw))) + 0
			if lines * tf.get_height(fs) <= room and FitText.line_width(tf, txt, fs) / tw <= 3.4: break
			fs -= 1
		tag_l.add_theme_font_size_override("font_size", fs)
		tag_l.position = Vector2(tx, top)
		tag_l.size = Vector2(tw, maxf(0.0, room))
		tag_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	func tick(t: float) -> void:
		_t = t
		badge.position.y += 0.0
		queue_redraw()

	func _draw() -> void:
		var W := size.x
		var H := size.y
		var body := UiTheme.box(accent.darkened(0.78), 22, accent.darkened(0.15 if focus_amount > 0.5 else 0.45), 4 if focus_amount > 0.5 else 3, 10)
		body.bg_color.a = 0.97
		draw_style_box(body, Rect2(Vector2.ZERO, size))
		# a soft glow behind the badge and the bottom art strip (the pack's own)
		var bc := badge.position + badge.size * 0.5
		var gr := badge.size.x * 1.15
		draw_texture_rect(PackSelector.glow(), Rect2(bc - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(accent, 0.35))
		# the badge bobs (idle) and shifts against the card's distance from the middle (parallax)
		var bob := sin(_t * 2.2 + float(pid.length())) * 3.0 * focus_amount
		badge.position.y = clampf(size.y * 0.07, 12.0, 26.0) + bob if wide else clampf(size.y * 0.07, 12.0, 26.0) + bob
		badge.position.x = (clampf(size.y * 0.07, 12.0, 26.0) if wide else (W - badge.size.x) * 0.5) + parallax * W * 0.07
		lock.position = badge.position + Vector2(badge.size.x - lock.size.x * 0.8, badge.size.y - lock.size.y * 0.9)
		var strip := H * 0.09
		rail.position = Vector2(16.0, H - strip - 14.0)
		rail.size = Vector2(W - 32.0, strip)
		rail.queue_redraw()
		var icons: Array = PackSelector.ICONS.get(pid, ["star", "star", "star"])
		for i in _icon_rects.size():
			var r := _icon_rects[i]
			r.position.x += parallax * W * 0.11 * (1.0 + i * 0.25)
			r.position.y += sin(_t * 2.6 + i * 1.3) * 2.5 * focus_amount
			draw_circle(r.get_center(), r.size.x * 0.62, Color(0, 0, 0, 0.22))
			PackSelector.draw_icon(self, str(icons[i % icons.size()]), r, accent)
		if not is_owned:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.06, 0.08, 0.28))
		# a slow shine sweeping across the centred card
		if focus_amount > 0.5:
			var k := fmod(_t * 0.35, 2.4) - 0.5
			var x0 := W * k
			draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + W * 0.12, 0), Vector2(x0 + W * 0.12 - H * 0.35, H), Vector2(x0 - H * 0.35, H)]), Color(1, 1, 1, 0.045))

	# the rail along the bottom: each pack's own pattern (drawn by the Rail child, which clips it)
	func art(c: CanvasItem, r: Rect2) -> void:
		var W := r.size.x
		var sh := parallax * W * 0.05
		match pid:
			"construction":
				var x := -r.size.y + fmod(sh, r.size.y * 2.0)
				c.draw_rect(r, Color("#14120b"))
				while x < W:
					c.draw_colored_polygon(PackedVector2Array([Vector2(x, r.end.y), Vector2(x + r.size.y * 0.6, r.end.y), Vector2(x + r.size.y * 1.6, r.position.y), Vector2(x + r.size.y, r.position.y)]), Color("#ffc21a"))
					x += r.size.y * 1.6
			"kitchen":
				c.draw_rect(r, Color("#3a1208"))
				var n := int(W / (r.size.y * 0.9)) + 2
				for i in n:
					var fx := i * r.size.y * 0.9 + sh
					var fh := r.size.y * (1.0 + 0.6 * sin(_t * 5.0 + i * 1.7))
					c.draw_colored_polygon(PackedVector2Array([Vector2(fx - r.size.y * 0.45, r.end.y), Vector2(fx, r.end.y - fh), Vector2(fx + r.size.y * 0.45, r.end.y)]), Color("#ff6a1a"))
					c.draw_colored_polygon(PackedVector2Array([Vector2(fx - r.size.y * 0.22, r.end.y), Vector2(fx, r.end.y - fh * 0.62), Vector2(fx + r.size.y * 0.22, r.end.y)]), Color("#ffd23d"))
			"xmas":
				var x2 := -r.size.y * 2.0 + fmod(sh, r.size.y * 2.0)
				c.draw_rect(r, Color("#f4f1ea"))
				while x2 < W:
					c.draw_colored_polygon(PackedVector2Array([Vector2(x2, r.end.y), Vector2(x2 + r.size.y * 0.7, r.end.y), Vector2(x2 + r.size.y * 1.7, r.position.y), Vector2(x2 + r.size.y, r.position.y)]), Color("#e0353a"))
					x2 += r.size.y * 2.0
			"australia":
				c.draw_rect(r, Color("#7a2a12"))
				var pts := PackedVector2Array([Vector2(0, r.end.y)])
				for i in 25: pts.append(Vector2(W * i / 24.0, r.position.y + r.size.y * (0.35 + 0.25 * sin(i * 0.9 + sh * 0.05))))
				pts.append(Vector2(W, r.end.y))
				c.draw_colored_polygon(pts, Color("#d9792b"))
			_:
				c.draw_rect(r, accent.darkened(0.5))


	## The clipped strip along the bottom of a card.
	class Rail extends Control:
		var card: Card
		func _init(c: Card) -> void:
			card = c
			clip_contents = true
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			name = "Rail"
		func _draw() -> void:
			card.art(self, Rect2(Vector2.ZERO, size))
			var fr := UiTheme.box(Color.TRANSPARENT, 9, card.accent.darkened(0.45), 4, 0)
			fr.draw_center = false
			draw_style_box(fr, Rect2(Vector2.ZERO, size))

# ---------------------------------------------------------------- the backdrop

## The page's backdrop: a soft glow in the centred pack's colour that slides with the deck (parallax) and a few motes of that
## pack's weather (embers rise, snow falls, dust drifts, site dust floats). At most 28 circles.
class Backdrop extends Control:
	const N := 28
	var pos := 0.0
	var colors: Array[Color] = []
	var kinds: Array[String] = []
	var _t := 0.0
	var _mx := PackedFloat32Array()
	var _my := PackedFloat32Array()
	var _ms := PackedFloat32Array()
	var _mv := PackedFloat32Array()

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in N:
			_mx.append(rng.randf())
			_my.append(rng.randf())
			_ms.append(rng.randf_range(0.5, 1.0))
			_mv.append(rng.randf_range(0.4, 1.0))

	func tick(t: float, _dt: float, packs: Array[DLCPackData]) -> void:
		_t = t
		colors.clear()
		kinds.clear()
		for d in packs:
			colors.append(d.accent_color)
			kinds.append(d.pack_id)
		queue_redraw()

	func _draw() -> void:
		if colors.is_empty(): return
		var W := size.x
		var H := size.y
		for i in colors.size():
			var w := clampf(1.0 - absf(float(i) - pos), 0.0, 1.0)
			if w <= 0.0: continue
			var cx := W * 0.5 + (float(i) - pos) * W * 0.55
			var rr := maxf(W, H) * 0.62
			draw_texture_rect(PackSelector.glow(), Rect2(cx - rr, H * 0.46 - rr, rr * 2.0, rr * 2.0), false, Color(colors[i], 0.22 * w))
		var near := clampi(roundi(pos), 0, colors.size() - 1)
		var fade := 1.0 - clampf(absf(pos - float(near)) * 2.0, 0.0, 1.0)
		var col := colors[near]
		var kind := kinds[near]
		for i in N:
			var x := _mx[i] * W
			var y := _my[i] * H
			var tt := _t * 0.08 * _mv[i]
			match kind:
				"kitchen":
					y = fmod(_my[i] + 1.0 - tt * 1.2, 1.0) * H
					x += sin(_t * 1.3 + i) * 10.0
					draw_circle(Vector2(x, y), 3.0 * _ms[i], Color(1.0, 0.55, 0.15, 0.4 * fade))
				"xmas":
					y = fmod(_my[i] + tt * 0.9, 1.0) * H
					x += sin(_t * 0.9 + i) * 16.0
					draw_circle(Vector2(x, y), 3.0 * _ms[i], Color(1, 1, 1, 0.45 * fade))
				"australia":
					x = fmod(_mx[i] + tt * 1.1, 1.0) * W
					y += sin(_t * 0.8 + i) * 8.0
					draw_circle(Vector2(x, y), 4.0 * _ms[i], Color(0.95, 0.6, 0.25, 0.28 * fade))
				_:
					y = fmod(_my[i] + 1.0 - tt * 0.6, 1.0) * H
					draw_circle(Vector2(x, y), 3.0 * _ms[i], Color(col, 0.3 * fade))
