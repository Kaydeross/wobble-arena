class_name TouchControls
extends Control
## On-screen touch controls, ported from the web game's touch layer (public/index.html ~9154-9247, CSS ~845-855):
## floating move stick on the left 45% (from 14% down), drag on the right side to look, buttons on the right
## (FIRE and JUMP held, the others taps, AIM toggles), pause at the top corner, left-handed mirror, scale/opacity.
## Writes into the shared InputState (source "touch"). Drawn with vector icons (_draw, no fonts): FIRE and JUMP
## biggest and strongest, then aim/swap/reload, then the rest; buttons dip and brighten while pressed; the stick is
## a ring + knob (a faint ghost marks it at rest). Layout respects left-handed mode, button scale, opacity, safe areas.

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
var _anim := {}                ## button id -> press animation 0..1 (visual only)

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
	_insets = SafeArea.insets(get_viewport())
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
		_anim["pause"] = 1.0
		queue_redraw()
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

func _process(dt: float) -> void:
	# press animation: each button eases toward 1 while held (fast in, slower springy out)
	var busy := false
	for b in BUTTONS:
		var id: String = b[0]
		var on: bool = _down.has(id)
		var a: float = _anim.get(id, 0.0)
		var t := 1.0 if on else 0.0
		if absf(a - t) > 0.001:
			a = move_toward(a, t, dt * (16.0 if on else 7.0))
			_anim[id] = a
			busy = true
	var pa: float = _anim.get("pause", 0.0)
	if pa > 0.0:
		_anim["pause"] = move_toward(pa, 0.0, dt * 5.0)
		busy = true
	if busy:
		queue_redraw()

## Opacity tier: FIRE and JUMP strongest, aim/swap/reload next, the rest lightest.
static func tier_alpha(id: String) -> float:
	match id:
		"fire", "jump": return 1.0
		"aim", "swap", "reload": return 0.86
	return 0.74

func _draw() -> void:
	var ink := Color(0.0627, 0.1686, 0.2078)
	var yel := Color(1.0, 0.812, 0.353)
	for b in BUTTONS:
		var r := button_rect(b)
		var id: String = b[0]
		var a: float = _anim.get(id, 0.0)
		var toggled: bool = id == "aim" and state != null and state.aim_toggle
		var op := opacity * tier_alpha(id)
		var c: Vector2 = r[0]
		var rad: float = r[1] * (1.0 - 0.1 * a)
		var fill: Color
		var icon_c: Color
		if id == "fire":
			fill = Color(yel.r, yel.g, yel.b, 0.88 * op); icon_c = Color(ink.r, ink.g, ink.b, op)
		elif id == "jump":
			fill = Color(0.16, 0.42, 0.47, 0.8 * op); icon_c = Color(1, 1, 1, op)
		else:
			fill = Color(ink.r, ink.g, ink.b, 0.62 * op); icon_c = Color(1, 1, 1, op)
		if toggled:
			icon_c = Color(yel.r, yel.g, yel.b, op)
		fill = fill.lerp(Color(1, 1, 1, fill.a), 0.3 * a)        # brighter while pressed
		draw_circle(c + Vector2(0, 3.0 * (1.0 - a)), rad, Color(0, 0, 0, 0.22 * op))   # soft drop shadow
		if a > 0.01:
			draw_circle(c, rad + 6.0 * a, Color(yel.r, yel.g, yel.b, 0.25 * a * op))  # press glow
		draw_circle(c, rad, fill)
		draw_arc(c + Vector2(0, -rad * 0.08), rad * 0.82, PI * 1.15, PI * 1.85, 24, Color(1, 1, 1, 0.16 * op), rad * 0.12, true)   # top sheen
		var edge := Color(yel.r, yel.g, yel.b, 0.95 * op) if toggled else (Color(ink.r, ink.g, ink.b, 0.5 * op) if id == "fire" else Color(1, 1, 1, 0.55 * op))
		draw_arc(c, rad - 1.0, 0, TAU, 48, edge, 2.5 if not toggled else 3.5, true)
		_icon(id, c, rad * 0.5, icon_c)
	# pause
	var pr := pause_rect()
	var pa: float = _anim.get("pause", 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ink.r, ink.g, ink.b, 0.62 * opacity).lerp(Color(1, 1, 1, 0.6 * opacity), 0.3 * pa)
	sb.border_color = Color(1, 1, 1, 0.55 * opacity)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(14 * UNIT))
	sb.shadow_color = Color(0, 0, 0, 0.2 * opacity); sb.shadow_size = 4; sb.shadow_offset = Vector2(0, 2)
	sb.anti_aliasing = true
	draw_style_box(sb, pr.grow(-3.0 * pa))
	_icon("pause", pr.get_center(), pr.size.x * 0.24, Color(1, 1, 1, opacity))
	# floating stick: a faint ghost where the thumb usually rests, the real ring + knob while held
	var sr := STICK_R * UNIT * scale_k
	var kr := 23.0 * UNIT * scale_k
	if _touch.values().has("move"):
		var v := _stick_pos - _stick_origin
		var sprint := state != null and state.is_held("sprint")
		draw_circle(_stick_origin, sr, Color(ink.r, ink.g, ink.b, 0.4 * opacity))
		draw_arc(_stick_origin, sr, 0, TAU, 56, Color(yel.r, yel.g, yel.b, 0.9 * opacity) if sprint else Color(1, 1, 1, 0.5 * opacity), 3.0, true)
		draw_arc(_stick_origin, sr * 0.55, 0, TAU, 40, Color(1, 1, 1, 0.12 * opacity), 1.5, true)
		if v.length() > 4.0:   # highlight the rim in the push direction
			var ang := v.angle()
			draw_arc(_stick_origin, sr - 4.0, ang - 0.5, ang + 0.5, 16, Color(yel.r, yel.g, yel.b, 0.85 * opacity), 5.0, true)
		var knob := _stick_origin + v.limit_length(sr)
		draw_circle(knob + Vector2(0, 3), kr, Color(0, 0, 0, 0.25 * opacity))
		draw_circle(knob, kr, Color(1, 1, 1, 0.85 * opacity))
		draw_arc(knob, kr - 1.0, 0, TAU, 32, Color(ink.r, ink.g, ink.b, 0.35 * opacity), 2.0, true)
		draw_circle(knob, kr * 0.45, Color(ink.r, ink.g, ink.b, 0.12 * opacity))
	else:
		var gp := stick_home()
		draw_circle(gp, sr, Color(ink.r, ink.g, ink.b, 0.16 * opacity))
		draw_arc(gp, sr, 0, TAU, 56, Color(1, 1, 1, 0.22 * opacity), 2.0, true)
		draw_circle(gp, kr, Color(1, 1, 1, 0.18 * opacity))

## Where the faint stick ghost sits (lower part of the move zone, inside the safe area).
func stick_home() -> Vector2:
	var vs := get_viewport_rect().size
	var sr := STICK_R * UNIT * scale_k
	var y: float = vs.y - _insets[3] - sr - 34.0 * UNIT
	var x: float = _insets[0] + sr + 40.0 * UNIT
	if lefty: x = vs.x - _insets[2] - sr - 40.0 * UNIT
	return Vector2(x, y)

# ---------- vector icons (no fonts / emoji): `s` = half the icon size ----------

func _cap(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(a, b, col, w, true)
	draw_circle(a, w / 2.0, col)
	draw_circle(b, w / 2.0, col)

func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.26)
	match id:
		"fire":   # bullet burst: a spiky star with a hole
			var pts := PackedVector2Array()
			for i in 16:
				var ang := -PI / 2.0 + i * TAU / 16.0
				pts.append(c + Vector2.from_angle(ang) * (s * (1.0 if i % 2 == 0 else 0.55)))
			draw_colored_polygon(pts, col)
			draw_circle(c, s * 0.28, Color(1.0, 0.812, 0.353, col.a))
		"jump":   # up arrow over a ground line
			_cap(c + Vector2(0, s * 0.55), c + Vector2(0, -s * 0.55), w, col)
			_cap(c + Vector2(0, -s * 0.75), c + Vector2(-s * 0.6, -s * 0.1), w, col)
			_cap(c + Vector2(0, -s * 0.75), c + Vector2(s * 0.6, -s * 0.1), w, col)
			_cap(c + Vector2(-s * 0.7, s * 0.95), c + Vector2(s * 0.7, s * 0.95), w * 0.8, col)
		"aim":    # scope reticle
			draw_arc(c, s * 0.75, 0, TAU, 32, col, w * 0.8, true)
			_cap(c + Vector2(0, -s * 1.05), c + Vector2(0, -s * 0.35), w * 0.7, col)
			_cap(c + Vector2(0, s * 1.05), c + Vector2(0, s * 0.35), w * 0.7, col)
			_cap(c + Vector2(-s * 1.05, 0), c + Vector2(-s * 0.35, 0), w * 0.7, col)
			_cap(c + Vector2(s * 1.05, 0), c + Vector2(s * 0.35, 0), w * 0.7, col)
			draw_circle(c, w * 0.45, col)
		"swap":   # two opposite arrows
			_cap(c + Vector2(-s * 0.8, -s * 0.35), c + Vector2(s * 0.7, -s * 0.35), w * 0.8, col)
			_cap(c + Vector2(s * 0.8, -s * 0.35), c + Vector2(s * 0.35, -s * 0.8), w * 0.8, col)
			_cap(c + Vector2(s * 0.8, s * 0.35), c + Vector2(-s * 0.7, s * 0.35), w * 0.8, col)
			_cap(c + Vector2(-s * 0.8, s * 0.35), c + Vector2(-s * 0.35, s * 0.8), w * 0.8, col)
		"reload": # circular arrow
			draw_arc(c, s * 0.7, -PI * 0.35, PI * 1.35, 28, col, w * 0.85, true)
			var tip := c + Vector2.from_angle(-PI * 0.35) * s * 0.7
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-s * 0.05, -s * 0.5), tip + Vector2(s * 0.5, s * 0.08), tip + Vector2(-s * 0.35, s * 0.3)]), col)
		"shove":  # open palm
			var palm := Rect2(c + Vector2(-s * 0.55, -s * 0.1), Vector2(s * 1.1, s * 0.85))
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(int(s * 0.3))
			sb.anti_aliasing = true
			draw_style_box(sb, palm)
			for i in 4:
				var x := palm.position.x + s * 0.14 + i * s * 0.27
				_cap(Vector2(x, palm.position.y + s * 0.1), Vector2(x, palm.position.y - s * (0.6 if i == 1 or i == 2 else 0.45)), s * 0.22, col)
			_cap(Vector2(palm.position.x + s * 0.1, palm.position.y + s * 0.45), Vector2(palm.position.x - s * 0.4, palm.position.y + s * 0.05), s * 0.22, col)
		"kick":   # boot + motion lines
			var boot := PackedVector2Array()
			for q: Vector2 in [Vector2(-0.75, -0.9), Vector2(-0.15, -0.9), Vector2(-0.15, 0.05), Vector2(0.45, 0.2),
					Vector2(0.62, 0.42), Vector2(0.55, 0.75), Vector2(-0.75, 0.75)]:
				boot.append(c + q * s)
			draw_colored_polygon(boot, col)
			boot.append(boot[0])
			draw_polyline(boot, col, 1.5, true)
			_cap(c + Vector2(s * 0.2, -s * 0.6), c + Vector2(s * 0.85, -s * 0.6), w * 0.55, col)
			_cap(c + Vector2(s * 0.35, -s * 0.25), c + Vector2(s * 0.95, -s * 0.25), w * 0.55, col)
		"dash":   # speed lines + chevron
			_cap(c + Vector2(-s * 0.95, -s * 0.4), c + Vector2(-s * 0.35, -s * 0.4), w * 0.6, col)
			_cap(c + Vector2(-s * 1.05, 0), c + Vector2(-s * 0.2, 0), w * 0.6, col)
			_cap(c + Vector2(-s * 0.95, s * 0.4), c + Vector2(-s * 0.35, s * 0.4), w * 0.6, col)
			_cap(c + Vector2(s * 0.1, -s * 0.65), c + Vector2(s * 0.75, 0), w, col)
			_cap(c + Vector2(s * 0.75, 0), c + Vector2(s * 0.1, s * 0.65), w, col)
		"pause":
			_cap(c + Vector2(-s * 0.4, -s * 0.6), c + Vector2(-s * 0.4, s * 0.6), s * 0.42, col)
			_cap(c + Vector2(s * 0.4, -s * 0.6), c + Vector2(s * 0.4, s * 0.6), s * 0.42, col)
