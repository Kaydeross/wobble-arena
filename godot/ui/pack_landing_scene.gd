class_name PackLandingScene
extends Control
## The backdrop of a pack landing page (ui/pack_landing.gd), drawn in code (no image files) behind the whole hub:
##   "kitchen", "xmas", "australia"   the pack's two colours, top to bottom, and nothing else: their scenery is the 3D set in the hero
##                                    band (ui/pack_landing_set.gd). The 2D kitchen, snow globe and suburb this file used to draw are gone.
##   "construction"                   a light overlay over the page's own look: a crane with a swinging hook and a moving hazard tape,
##                                    and drifting dust (CPUParticles2D)
## Performance: nothing is allocated per frame, one redraw per frame while active and animated (Construction only), none while
## hidden / covered. Particles total at most PARTICLE_CAP over the page (the 3D set's count in); `particles` = false (lowest
## graphics tier, headless) builds none, and `animate` = false draws one still frame and never redraws until resized.

const PARTICLE_CAP := 100
const STILL_T := 3.4

var kind := ""
var animate := true
var particles := true
var active := false: set = set_active
var top := Color("#12151a")
var bottom := Color("#3a1810")
var glow := Color("#ff7a1c")
var accent2 := Color("#ffd34a")
var _t := 0.0
var _parts: Array[CPUParticles2D] = []
var _bg_pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _bg_cols := PackedColorArray([Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK])
var _tape := PackedVector2Array([Vector2(0, 10), Vector2(14, 10), Vector2(24, 0), Vector2(10, 0)])
static var _dot: ImageTexture

func _init() -> void:
	name = "LandingScene"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	set_process(false)

func setup(k: String, pal: Dictionary, with_particles: bool, anim: bool) -> void:
	kind = k
	top = pal.get("top", top)
	bottom = pal.get("bottom", bottom)
	glow = pal.get("glow", glow)
	accent2 = pal.get("accent2", accent2)
	var flat := kind != "construction"                 # the 3D packs: colours only
	particles = with_particles and not flat
	animate = anim and not flat
	_clear_particles()
	if particles: _make_particles()
	_rebuild()
	set_active(active)

func _clear_particles() -> void:
	for p: CPUParticles2D in _parts:
		remove_child(p)
		p.queue_free()
	_parts.clear()

## The particle amounts of the nodes this scene owns (the page's budget check).
func particle_total() -> int:
	var n := 0
	for p: CPUParticles2D in _parts: n += p.amount
	return n

func particle_nodes() -> Array[CPUParticles2D]:
	return _parts

static func dot_texture() -> ImageTexture:
	if _dot == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var d := Vector2(x - 7.5, y - 7.5).length() / 8.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 1.6, 0.0, 1.0)))
		_dot = ImageTexture.create_from_image(img)
	return _dot

func _mk(amount: int, ramp: Array, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Fx%d" % _parts.size()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.texture = dot_texture()
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(100, 4)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	g.colors = PackedColorArray(ramp)
	p.color_ramp = g
	add_child(p)
	_parts.append(p)
	return p

func _make_particles() -> void:
	if kind != "construction": return
	var p := _mk(14, [Color(1, 0.85, 0.35, 0), Color(1, 0.82, 0.3, 0.45), Color(1, 0.78, 0.25, 0.3), Color(1, 0.78, 0.25, 0)], 6.0)
	p.direction = Vector2(-1, -0.15)
	p.spread = 35.0
	p.gravity = Vector2(0, 3)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 30.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	_place_particles()

func _place_particles() -> void:
	for p: CPUParticles2D in _parts:
		p.position = Vector2(size.x + 10.0, size.y * 0.55)
		p.emission_rect_extents = Vector2(4, size.y * 0.3)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rebuild()
		_place_particles()

func set_active(on: bool) -> void:
	active = on
	for p: CPUParticles2D in _parts:
		var go := on and animate
		if go and not p.emitting: p.restart()
		p.emitting = go
	set_process(on and animate)
	if on: queue_redraw()

func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	_t += dt
	queue_redraw()

## The time the picture is drawn at: running, or one good still frame.
func now() -> float:
	return _t if animate else STILL_T

func _rebuild() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0: return
	_bg_pts[0] = Vector2(0, 0)
	_bg_pts[1] = Vector2(w, 0)
	_bg_pts[2] = Vector2(w, h)
	_bg_pts[3] = Vector2(0, h)
	_bg_cols[0] = top
	_bg_cols[1] = top
	_bg_cols[2] = bottom
	_bg_cols[3] = bottom

func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0: return
	if kind == "construction": _draw_construction()
	else: draw_polygon(_bg_pts, _bg_cols)

func _draw_construction() -> void:
	var t := now()
	var w := size.x
	var h := size.y
	var steel := Color(0.78, 0.85, 0.9, 0.2)
	var yel := Color(1.0, 0.76, 0.1, 0.34)
	var tx := w * 0.88
	var jy := h * 0.07
	draw_rect(Rect2(tx - 5.0, jy, 10.0, h * 0.4), steel)                      # tower
	draw_line(Vector2(w * 0.5, jy), Vector2(w * 0.98, jy), steel, 6.0)       # jib
	draw_rect(Rect2(tx - 14.0, jy - 16.0, 28.0, 16.0), yel)                   # cab
	draw_rect(Rect2(w * 0.96, jy + 3.0, 20.0, 18.0), steel)                   # counterweight
	var trol := w * 0.64 + sin(t * 0.3) * w * 0.06
	var sw := sin(t * 1.1) * 0.12
	draw_set_transform(Vector2(trol, jy + 4.0), sw, Vector2.ONE)
	var cable := h * 0.2 + sin(t * 0.4) * h * 0.03
	draw_line(Vector2.ZERO, Vector2(0, cable), steel, 2.0)
	draw_rect(Rect2(-14, cable, 28, 18), yel)                                 # the load
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the hazard tape along the bottom edge, crawling
	var off := fmod(t * 14.0, 28.0)
	var n := int(w / 28.0) + 3
	for i in n:
		draw_set_transform(Vector2(float(i) * 28.0 - 28.0 + off, h - 10.0), 0.0, Vector2.ONE)
		draw_colored_polygon(_tape, Color(1.0, 0.76, 0.1, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
