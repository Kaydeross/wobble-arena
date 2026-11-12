extends Control
## HUD radar (top right), a port of the web game's drawRadar: map boxes around the player (brighter = taller),
## bounce pads, other fighters (orange above you, purple below, red level; pinned to the rim when out of range)
## and the camera direction, inside a round teal panel with a white rim and a slow sweep.
## `sim` and `yaw` are set by hud.gd.

const D := 124.0
const RANGE := 30.0

var sim: MatchSim
var yaw := 0.0
var _sweep := 0.0
var _mask: Control
var _content: Control
var _ring: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(D, D)
	size = custom_minimum_size
	_mask = _layer("Mask", _draw_mask)
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.size = size
	_content.draw.connect(_draw_content)
	_mask.add_child(_content)
	_ring = _layer("Ring", _draw_ring)

func _layer(n: String, f: Callable) -> Control:
	var c := Control.new()
	c.name = n
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = size
	c.draw.connect(f)
	add_child(c)
	return c

func tick(dt: float) -> void:
	_sweep = fmod(_sweep + dt * 1.6, TAU)
	_content.queue_redraw()

func _draw() -> void:
	# soft drop shadow under the disc
	draw_circle(Vector2(D / 2.0, D / 2.0 + 3.0), D / 2.0 + 2.0, Color(0, 0, 0, 0.25))

func _draw_mask() -> void:
	_mask.draw_circle(Vector2(D, D) / 2.0, D / 2.0 - 1.0, Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.72))

func _draw_ring() -> void:
	var c := Vector2(D, D) / 2.0
	_ring.draw_arc(c, D / 2.0 - 2.0, 0, TAU, 64, Color(1, 1, 1, 0.6), 3.0, true)
	_ring.draw_arc(c, D / 2.0 - 4.5, 0, TAU, 64, Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.9), 2.0, true)
	# N tick
	_ring.draw_line(Vector2(c.x, 3), Vector2(c.x, 10), UiTheme.ACCENT, 3.0, true)

func _draw_content() -> void:
	var r := D / 2.0
	var c := Vector2(r, r)
	var ci := _content
	# range rings
	ci.draw_arc(c, r * 0.5, 0, TAU, 40, Color(1, 1, 1, 0.08), 1.0, true)
	# sweep: a fan of thin wedges that fade behind the leading edge
	var steps := 14
	for i in steps:
		var a0 := _sweep - (i + 1) * 0.06
		var a1 := _sweep - i * 0.06
		var al := 0.16 * (1.0 - float(i) / steps)
		ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r]),
			Color(0.31, 0.88, 0.81, al))
	if sim == null or sim.player == null: return
	var k := r / RANGE
	var p := sim.player.phys
	for b: Dictionary in sim.solids:
		if b["maxX"] < p.px - RANGE or b["minX"] > p.px + RANGE or b["maxZ"] < p.pz - RANGE or b["minZ"] > p.pz + RANGE: continue
		var hh := clampf(float(b["top"]) / 8.0, 0.0, 1.0)
		var col := Color(1, 1, 1, 0.16) if float(b["bottom"]) <= -1.0 else Color((200 + 55 * hh) / 255.0, (210 + 40 * hh) / 255.0, 1.0, 0.3 + 0.35 * hh)
		ci.draw_rect(Rect2(c + Vector2(float(b["minX"]) - p.px, float(b["minZ"]) - p.pz) * k,
			Vector2(float(b["maxX"]) - float(b["minX"]), float(b["maxZ"]) - float(b["minZ"])) * k), col)
	for pd: Dictionary in sim.pads:
		ci.draw_circle(c + Vector2(float(pd["x"]) - p.px, float(pd["z"]) - p.pz) * k, 2.5, Color(0.31, 0.88, 0.81))
	for f: FighterState in sim.fighters:
		if f == sim.player or f.dead: continue
		var d := Vector2(f.phys.px - p.px, f.phys.pz - p.pz) * k
		var edge := d.length() > r - 7.0
		if edge: d = d.normalized() * (r - 7.0)
		var fc := Color(1, 0.7, 0.28) if f.phys.py > p.py + 1.5 else (Color(0.78, 0.49, 1.0) if f.phys.py < p.py - 1.5 else Color(1, 0.36, 0.36))
		if edge: fc.a = 0.6
		ci.draw_circle(c + d, 4.5 if not edge else 3.5, Color(0, 0, 0, 0.35 * fc.a))
		ci.draw_circle(c + d, 3.6 if not edge else 2.8, fc)
	# the player: a white arrow along the camera direction (web: sin/cos of cam.yaw, x right, z down)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var tri := PackedVector2Array([c + fwd * 9.0, c - fwd * 5.0 + side * 5.5, c - fwd * 2.5, c - fwd * 5.0 - side * 5.5])
	ci.draw_colored_polygon(tri, Color.WHITE)
	ci.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), UiTheme.INK, 1.5, true)
