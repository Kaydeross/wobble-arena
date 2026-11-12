class_name TouchControls
extends Control
## On-screen touch controls, ported from the web game's touch layer (public/index.html ~9154-9247, CSS ~845-855):
## floating move stick on the left 45% (from 14% down), drag on the right side to look, buttons on the right
## (FIRE and JUMP held, the others taps, AIM toggles), pause at the top corner, left-handed mirror, scale/opacity.
## Writes into the shared InputState (source "touch"). Placeholder drawing; the UI pass (Phase 3) restyles it.

signal pause_pressed

## CSS px of the web layout -> canvas units. The web layout is sized for ~390pt-tall phone screens, our canvas is 540 tall.
const UNIT := 1.35
const LOOK_K := 0.0052        ## rad per CSS px (web: 0.0052 * sens)
const STICK_R := 54.0
const MOVE_W := 0.45
const MOVE_TOP := 0.14
## id, label, action, size, distance from the thumb-side edge, distance from the bottom, held (else tap). Same table as TBTN.
const BUTTONS := [
	["fire", "FIRE", "fire", 92, 24, 20, true], ["jump", "JUMP", "jump", 66, 134, 22, true], ["aim", "AIM", "aim", 54, 30, 128, false],
	["swap", "SWAP", "swap", 50, 104, 112, false], ["dash", "DASH", "dash", 54, 176, 92, false], ["reload", "RELOAD", "reload", 54, 222, 18, false],
	["shove", "SHOVE", "shove", 52, 168, 160, false], ["kick", "KICK", "kick", 50, 238, 100, false],
]
const PAUSE_SIZE := 44.0

var state: InputState
var lefty := false
var scale_k := 1.0
var opacity := 0.85

var _touch := {}               ## touch index -> "move" | "look" | "pause" | button id
var _last := {}                ## touch index -> last position (look / fire drag)
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _down := {}                ## button id -> true while pressed
var _insets := [0.0, 0.0, 0.0, 0.0]   ## left, top, right, bottom safe-area insets in canvas units

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	Settings.changed.connect(func(_k, _v): _load_settings())
	get_viewport().size_changed.connect(_update_insets)
	_update_insets()
	visible = wanted()

static func wanted() -> bool:
	var mode := str(Settings.get_value("touch_mode", "auto"))
	return mode == "on" or (mode == "auto" and Tier.touch_default())

func _load_settings() -> void:
	lefty = bool(Settings.get_value("touch_lefty", false))
	scale_k = float(Settings.get_value("touch_scale", 1.0))
	opacity = float(Settings.get_value("touch_opacity", 0.85))
	queue_redraw()

## Safe-area insets (notch, home indicator) from DisplayServer, converted to canvas units. Phones only:
## on desktop the "safe area" is the screen minus the dock, which says nothing about our window.
func _update_insets() -> void:
	_insets = [0.0, 0.0, 0.0, 0.0]
	if not Tier.is_mobile() or DisplayServer.get_name() == "headless":
		queue_redraw(); return
	var sa := DisplayServer.get_display_safe_area()
	var ws := DisplayServer.window_get_size()
	var wp := DisplayServer.window_get_position()
	if ws.x <= 0 or ws.y <= 0 or sa.size.x <= 0:
		return
	var k := get_viewport_rect().size / Vector2(ws)
	_insets = [maxf(0, sa.position.x - wp.x) * k.x, maxf(0, sa.position.y - wp.y) * k.y,
		maxf(0, (wp.x + ws.x) - sa.end.x) * k.x, maxf(0, (wp.y + ws.y) - sa.end.y) * k.y]
	queue_redraw()

func safe_insets() -> Array:
	return _insets

## Button centre and radius in canvas units.
func button_rect(b: Array) -> Array:
	var vs := get_viewport_rect().size
	var u := UNIT * scale_k
	var sz: float = float(b[3]) * u
	var x: float = float(b[4]) * u
	var y: float = float(b[5]) * u
	var cy: float = vs.y - _insets[3] - y - sz / 2.0
	var cx: float = (_insets[0] + x + sz / 2.0) if lefty else (vs.x - _insets[2] - x - sz / 2.0)
	return [Vector2(cx, cy), sz / 2.0]

func pause_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var s := PAUSE_SIZE * UNIT
	var top: float = 6.0 * UNIT + _insets[1]
	var x: float = (8.0 * UNIT + _insets[0]) if lefty else (vs.x - 8.0 * UNIT - _insets[2] - s)
	return Rect2(x, top, s, s)

func _in_move_zone(p: Vector2) -> bool:
	var vs := get_viewport_rect().size
	if p.y < vs.y * MOVE_TOP:
		return false
	return p.x > vs.x * (1.0 - MOVE_W) if lefty else p.x < vs.x * MOVE_W

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if not visible and str(Settings.get_value("touch_mode", "auto")) == "auto":
			visible = true   # a touch screen on a laptop or in a browser: show the controls once it is used
		if not visible or state == null:
			return
		var p: Vector2 = (make_input_local(e) as InputEventScreenTouch).position
		if e.pressed:
			_touch_down(e.index, p)
		else:
			_touch_up(e.index)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and visible and state != null and _touch.has(e.index):
		_touch_move(e.index, (make_input_local(e) as InputEventScreenDrag).position)
		get_viewport().set_input_as_handled()

func _touch_down(i: int, p: Vector2) -> void:
	if pause_rect().grow(6).has_point(p):
		_touch[i] = "pause"
		pause_pressed.emit()
		return
	for b in BUTTONS:
		var r := button_rect(b)
		if p.distance_to(r[0]) <= r[1] + 4.0:
			var id: String = b[0]
			if _down.has(id):
				continue
			_touch[i] = id; _last[i] = p; _down[id] = true
			var action: String = b[2]
			if id == "aim":
				state.aim_toggle = not state.aim_toggle
			elif b[6]:
				state.hold("touch", action, true)
			else:
				state.press(action)
			queue_redraw()
			return
	if _in_move_zone(p) and not _touch.values().has("move"):
		_touch[i] = "move"
		_stick_origin = p; _stick_pos = p
		_update_stick()
	elif not _touch.values().has("look"):
		_touch[i] = "look"; _last[i] = p
	queue_redraw()

func _touch_move(i: int, p: Vector2) -> void:
	var what: String = _touch[i]
	if what == "move":
		var r := STICK_R * UNIT * scale_k
		var d := p - _stick_origin
		if d.length() > r:   # the base follows the thumb when dragged past its edge
			_stick_origin += d * ((d.length() - r) / d.length())
		_stick_pos = p
		_update_stick()
	elif what == "look" or what == "fire":   # hold FIRE and drag to aim
		_look(p - _last[i])
		_last[i] = p
	queue_redraw()

func _touch_up(i: int) -> void:
	if not _touch.has(i):
		return
	var what: String = _touch[i]
	_touch.erase(i); _last.erase(i)
	if what == "move":
		state.set_move("touch", Vector2.ZERO)
		state.hold("touch", "sprint", false)
	elif _down.has(what):
		_down.erase(what)
		for b in BUTTONS:
			if b[0] == what and b[6]:
				state.hold("touch", b[2], false)
	queue_redraw()

func _update_stick() -> void:
	var r := STICK_R * UNIT * scale_k
	var d := (_stick_pos - _stick_origin) / r
	var v := Vector2(d.x, -d.y).limit_length(1.0)   # x = right, y = forward
	state.set_move("touch", v)
	state.hold("touch", "sprint", v.length() > 0.93 and v.y > 0.3)   # push to the edge to sprint

func _look(d: Vector2) -> void:
	var k := LOOK_K * float(Settings.get_value("sens", 1.0)) / UNIT
	var inv := -1.0 if bool(Settings.get_value("invert_y", false)) else 1.0
	state.add_look(-d.x * k, -d.y * k * inv)

## Let go of every touch (pause, leaving the match).
func release_all() -> void:
	for i in _touch.keys():
		_touch_up(i)
	_touch.clear(); _down.clear()
	if state:
		state.aim_toggle = false

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var base := Color(16 / 255.0, 43 / 255.0, 53 / 255.0, 0.5 * opacity)
	var edge := Color(1, 1, 1, 0.6 * opacity)
	for b in BUTTONS:
		var r := button_rect(b)
		var down: bool = _down.has(b[0]) or (b[0] == "aim" and state != null and state.aim_toggle)
		var rad: float = r[1] * (0.9 if _down.has(b[0]) else 1.0)
		draw_circle(r[0], rad, Color(1, 1, 1, 0.65 * opacity) if down else base)
		draw_arc(r[0], rad, 0, TAU, 32, edge, 2.0, true)
		var fs := int(13 * UNIT * scale_k * (1.2 if b[0] == "fire" else 1.0))
		var txt: String = b[1]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, r[0] + Vector2(-w / 2.0, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs,
			Color(16 / 255.0, 43 / 255.0, 53 / 255.0, opacity) if down else Color(1, 1, 1, opacity))
	var pr := pause_rect()
	draw_style_box(_pause_box(), pr)
	var pw := font.get_string_size("II", HORIZONTAL_ALIGNMENT_CENTER, -1, 22).x
	draw_string(font, pr.get_center() + Vector2(-pw / 2.0, 8), "II", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(1, 1, 1, opacity))
	if _touch.values().has("move"):
		var sr := STICK_R * UNIT * scale_k
		draw_circle(_stick_origin, sr, Color(16 / 255.0, 43 / 255.0, 53 / 255.0, 0.35 * opacity))
		draw_arc(_stick_origin, sr, 0, TAU, 40, Color(1, 1, 1, 0.5 * opacity), 2.0, true)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(sr)
		draw_circle(knob, 23.0 * UNIT * scale_k, Color(1, 1, 1, 0.75 * opacity))

func _pause_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(16 / 255.0, 43 / 255.0, 53 / 255.0, 0.55 * opacity)
	sb.border_color = Color(1, 1, 1, 0.5 * opacity)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(12 * UNIT))
	return sb
