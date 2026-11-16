class_name PackLandingScene
extends Control
## The animated backdrop of a pack landing page (ui/pack_landing.gd), drawn in code (no image files) behind the hub:
##   "kitchen"      dark stainless kitchen: tile wall, an exhaust hood, utensils swaying on a rail, a row of gas burners at the
##                  bottom whose flames flicker, steam wisps and rising embers (CPUParticles2D)
##   "xmas"         toy workshop: deep green and red, a string of twinkling lights, fir trees, snow drift, two gift stacks with
##                  bobbing bows and falling snow (CPUParticles2D)
##   "australia"    sunny backyard: warm sky, a big sun with slow rays, hills, a turning Hills Hoist with fluttering washing,
##                  a boomerang that arcs across now and then, a corrugated-iron fence, drifting dust
##   "construction" a light overlay over the page's own look: a crane with a swinging hook and a moving hazard tape
## Performance: nothing is allocated per frame (the polygons are built once and moved with draw_set_transform), one redraw per frame
## while active, none while hidden / covered. Particles total at most PARTICLE_CAP over the page; `particles` = false (lowest
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
var hero := Rect2()                     ## the hero band's rectangle in this control's space (set by PackLanding): the scene's ground line is its bottom edge
var lockup := Rect2()                   ## the title lockup's rectangle (the glow / sparkle sits behind it)
var stage := Rect2()                    ## the 3D stage's rectangle (the props stand beside / behind it)
var fg_origin := Vector2.ZERO           ## the foreground layer's origin in this control's space (set by PackLanding)
var base_text := ""                     ## the name on the snow globe's base
var _shake := 0.0
var _t := 0.0
var _parts: Array[CPUParticles2D] = []
var _bg_pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _bg_cols := PackedColorArray([Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK])
var _heat_pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _heat_cols := PackedColorArray([Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK])
var _grid := PackedVector2Array()
var _ridges := PackedVector2Array()
var _garland := PackedVector2Array()
var _ground := PackedVector2Array()
var _ground_line := PackedVector2Array()
var _ground_cols := PackedColorArray()
var _hills := PackedVector2Array()
var _wisp := PackedVector2Array()
var _wisp_cols := PackedColorArray()
var _flame := PackedVector2Array([Vector2(0, 0), Vector2(-11, -6), Vector2(-13, -18), Vector2(-8, -31), Vector2(-3, -43), Vector2(2, -58), Vector2(4, -43), Vector2(9, -30), Vector2(13, -16), Vector2(11, -6)])
var _tree := PackedVector2Array([Vector2(0, 0), Vector2(-40, 0), Vector2(-22, -30), Vector2(-32, -30), Vector2(-14, -62), Vector2(-24, -62), Vector2(0, -110), Vector2(24, -62), Vector2(14, -62), Vector2(32, -30), Vector2(22, -30), Vector2(40, 0)])
var _ray := PackedVector2Array([Vector2(0, 0), Vector2(-30, -400), Vector2(30, -400)])
var _k_leg := PackedVector2Array([Vector2(-2, -26), Vector2(12, -30), Vector2(18, -10), Vector2(26, 0), Vector2(-8, 0)])
var _k_tail := PackedVector2Array([Vector2(8, -14), Vector2(40, -2), Vector2(42, 2), Vector2(12, -4)])
var _k_snout := PackedVector2Array([Vector2(-12, -72), Vector2(-24, -66), Vector2(-10, -63)])
var _k_ear := PackedVector2Array([Vector2(-3, 0), Vector2(0, -15), Vector2(3, 0)])
var _roof := PackedVector2Array([Vector2(-1.2, 0), Vector2(0, -0.8), Vector2(1.2, 0)])
var _pot := PackedVector2Array([Vector2(-9, 0), Vector2(9, 0), Vector2(7, 14), Vector2(-7, 14)])
var _tape := PackedVector2Array([Vector2(0, 10), Vector2(14, 10), Vector2(24, 0), Vector2(10, 0)])
var _cloth := PackedVector2Array([Vector2(0, 0), Vector2(14, 0), Vector2(14, 20), Vector2(0, 20)])
var _wash_cols := PackedColorArray([Color("#e5483f"), Color("#f4f1ea"), Color("#3a8fd6"), Color("#f3c53a"), Color("#4fb36a"), Color("#f4f1ea")])
var _bulb_cols := PackedColorArray([Color("#ff4a4a"), Color("#ffd24a"), Color("#52d273"), Color("#58a8ff")])
static var _dot: ImageTexture

func _init() -> void:
	name = "LandingScene"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	set_process(false)
	_wisp.resize(9)
	for a: float in [0.0, 0.1, 0.15, 0.15, 0.12, 0.09, 0.06, 0.03, 0.0]: _wisp_cols.append(Color(1, 1, 1, a))

func setup(k: String, pal: Dictionary, with_particles: bool, anim: bool) -> void:
	kind = k
	top = pal.get("top", top)
	bottom = pal.get("bottom", bottom)
	glow = pal.get("glow", glow)
	accent2 = pal.get("accent2", accent2)
	particles = with_particles
	animate = anim
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
	match kind:
		"kitchen":
			var p := _mk(28, [Color(1, 0.6, 0.15, 0), Color(1, 0.62, 0.18, 0.95), Color(1, 0.35, 0.08, 0.6), Color(0.6, 0.1, 0.02, 0)], 2.8)
			p.direction = Vector2(0, -1)
			p.spread = 28.0
			p.gravity = Vector2(0, -12)
			p.initial_velocity_min = 40.0
			p.initial_velocity_max = 120.0
			p.scale_amount_min = 0.25
			p.scale_amount_max = 0.6
		"xmas":
			var p := _mk(56, [Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(0.92, 0.96, 1, 0.8), Color(1, 1, 1, 0)], 6.0)
			p.direction = Vector2(0.18, 1)
			p.spread = 22.0
			p.gravity = Vector2(0, 0)
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 120.0
			p.scale_amount_min = 0.35
			p.scale_amount_max = 0.95
			p.angle_max = 360.0
		"australia":
			var p := _mk(14, [Color(1, 0.95, 0.7, 0), Color(1, 0.93, 0.65, 0.5), Color(1, 0.9, 0.6, 0.35), Color(1, 0.9, 0.6, 0)], 7.0)
			p.direction = Vector2(1, -0.2)
			p.spread = 40.0
			p.gravity = Vector2(0, -2)
			p.initial_velocity_min = 8.0
			p.initial_velocity_max = 26.0
			p.scale_amount_min = 0.3
			p.scale_amount_max = 0.8
		"construction":
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
	var gy := ground_y()
	var hh := hero_h()
	for p: CPUParticles2D in _parts:
		match kind:
			"kitchen":
				p.position = Vector2(size.x * 0.5, gy - 6.0)
				p.emission_rect_extents = Vector2(size.x * 0.46, 4)
				p.initial_velocity_max = clampf(hh * 0.9, 70.0, 150.0)
			"xmas":
				p.position = Vector2(size.x * 0.5, -8.0)
				p.emission_rect_extents = Vector2(size.x * 0.56, 4)
			"australia":
				p.position = Vector2(-10.0, size.y * 0.6)
				p.emission_rect_extents = Vector2(4, size.y * 0.3)
			"construction":
				p.position = Vector2(size.x + 10.0, size.y * 0.55)
				p.emission_rect_extents = Vector2(4, size.y * 0.3)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rebuild()
		_place_particles()

## The hero band moved or changed size: the ground line follows it.
func set_hero(h: Rect2, l: Rect2, st: Rect2) -> void:
	stage = st
	if h == hero and l == lockup: return
	var moved := h.end.y != hero.end.y or h.size.x != hero.size.x or h.position.x != hero.position.x
	hero = h
	lockup = l
	if moved:
		_rebuild()
		_place_particles()
	queue_redraw()

## The y of the ground line: the bottom of the hero band (the cards stand under it), or near the page bottom without a band.
func ground_y() -> float:
	if hero.size.y > 40.0: return hero.end.y - 4.0
	return size.y - clampf(size.y * 0.05, 18.0, 34.0) - 2.0

func hero_h() -> float:
	return hero.size.y if hero.size.y > 40.0 else size.y * 0.3

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
	_shake = maxf(0.0, _shake - dt * 0.6)
	_t += dt
	queue_redraw()

## A tap on the snow globe: the snow inside swirls for a moment.
func shake() -> void:
	_shake = 1.0

## The time the picture is drawn at: running, or one good still frame.
func now() -> float:
	return _t if animate else STILL_T

# ---------------- geometry built once per size ----------------

func _rebuild() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0: return
	var gy := ground_y()
	_bg_pts[0] = Vector2(0, 0)
	_bg_pts[1] = Vector2(w, 0)
	_bg_pts[2] = Vector2(w, h)
	_bg_pts[3] = Vector2(0, h)
	_bg_cols[0] = top
	_bg_cols[1] = top
	_bg_cols[2] = bottom
	_bg_cols[3] = bottom
	var hy := gy - hero_h() * 1.1
	_heat_pts[0] = Vector2(0, hy)
	_heat_pts[1] = Vector2(w, hy)
	_heat_pts[2] = Vector2(w, gy + 30.0)
	_heat_pts[3] = Vector2(0, gy + 30.0)
	var c0 := Color(glow.r, glow.g, glow.b, 0.0)
	_heat_cols[0] = c0
	_heat_cols[1] = c0
	_heat_cols[2] = Color(glow.r, glow.g, glow.b, 0.34)
	_heat_cols[3] = Color(glow.r, glow.g, glow.b, 0.34)
	_grid.clear()
	_ridges.clear()
	_garland.clear()
	_ground.clear()
	_ground_line.clear()
	_hills.clear()
	match kind:
		"kitchen":
			var x := 0.0
			while x < w:
				_grid.append(Vector2(x, 0))
				_grid.append(Vector2(x, h))
				x += 64.0
			var y := 0.0
			while y < h:
				_grid.append(Vector2(0, y))
				_grid.append(Vector2(w, y))
				y += 40.0
		"xmas":
			for i in 49:
				var u := float(i) / 48.0
				_garland.append(Vector2(u * w, 8.0 + absf(sin(u * PI * 3.0)) * 26.0))
			for i in 41:
				var u := float(i) / 40.0
				_ground.append(Vector2(u * w, gy - 8.0 - sin(u * PI * 5.0) * 5.0 - sin(u * PI * 11.0) * 2.0))
			_ground_line = _ground.duplicate()
			_ground.append(Vector2(w, h))
			_ground.append(Vector2(0, h))
			_ground_cols.resize(_ground.size())
			for i in _ground.size(): _ground_cols[i] = Color(0.88, 0.93, 1.0, 0.97) if i < 41 else Color(0.36, 0.46, 0.68, 0.97)
		"australia":
			for i in 33:
				var u := float(i) / 32.0
				_hills.append(Vector2(u * w, gy - hero_h() * 0.55 - sin(u * PI * 2.0 + 0.6) * hero_h() * 0.18 - sin(u * PI * 5.0) * hero_h() * 0.05))
			_hills.append(Vector2(w, h))
			_hills.append(Vector2(0, h))
			var fx := 0.0
			var fh := fence_h()
			while fx < w:
				_ridges.append(Vector2(fx, gy - fh))
				_ridges.append(Vector2(fx, gy + 4.0))
				fx += 8.0

func fence_h() -> float:
	return clampf(hero_h() * 0.24, 22.0, 54.0)

# ---------------- drawing ----------------

func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0: return
	match kind:
		"kitchen": _draw_kitchen()
		"xmas": _draw_xmas()
		"australia": _draw_australia()
		"construction": _draw_construction()

func _bg() -> void:
	draw_polygon(_bg_pts, _bg_cols)

func _glow_at(p: Vector2, r: float, c: Color, a: float) -> void:
	draw_circle(p, r, Color(c.r, c.g, c.b, a * 0.35))
	draw_circle(p, r * 0.72, Color(c.r, c.g, c.b, a * 0.5))
	draw_circle(p, r * 0.45, Color(c.r, c.g, c.b, a))

func _draw_kitchen() -> void:
	var t := now()
	var w := size.x
	var h := size.y
	var gy := ground_y()
	var hh_band := hero_h()
	var fs := clampf(hh_band / 150.0, 0.5, 1.3) * 0.62
	_bg()
	draw_multiline(_grid, Color(1, 1, 1, 0.032), 1.0)
	# the exhaust hood over the middle
	var hw := minf(w * 0.34, 460.0)
	var hh := clampf(h * 0.085, 30.0, 58.0)
	var cx := w * 0.5
	draw_colored_polygon(_hood(cx, hw, hh), Color(0.46, 0.49, 0.54, 0.55))
	draw_rect(Rect2(cx - hw * 0.5 - 34.0, hh, hw + 68.0, 5.0), Color(0.72, 0.76, 0.82, 0.55))
	_glow_at(Vector2(cx - hw * 0.28, hh + 8.0), 26.0, Color(1, 0.82, 0.5), 0.16)
	_glow_at(Vector2(cx + hw * 0.28, hh + 8.0), 26.0, Color(1, 0.82, 0.5), 0.16)
	# utensils on a rail
	draw_line(Vector2(0, 4), Vector2(w, 4), Color(0.7, 0.74, 0.8, 0.45), 4.0)
	for i in 7:
		var x := w * (0.05 + 0.9 * float(i) / 6.0)
		var ang := sin(t * 1.25 + float(i) * 1.7) * 0.08
		draw_set_transform(Vector2(x, 4), ang, Vector2.ONE)
		var l := 26.0 + 14.0 * float(i % 3)
		var col := Color(0.78, 0.82, 0.88, 0.42)
		draw_line(Vector2.ZERO, Vector2(0, l), col, 2.0)
		match i % 4:
			0: draw_circle(Vector2(0, l + 12.0), 12.0, col)                       # ladle
			1: draw_arc(Vector2(0, l + 14.0), 11.0, 0.0, TAU, 14, col, 2.0)       # whisk
			2: draw_rect(Rect2(-8, l, 16, 24), col)                               # spatula
			3:
				draw_line(Vector2(-4, l), Vector2(-9, l + 26.0), col, 3.0)       # tongs
				draw_line(Vector2(4, l), Vector2(9, l + 26.0), col, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_polygon(_heat_pts, _heat_cols)
	if stage.size.x > 10.0: _kitchen_back(t)
	# the ember glow behind the title lockup
	if lockup.size.x > 10.0:
		var fl := 0.5 + 0.5 * sin(t * 6.0) * sin(t * 2.3 + 1.0)
		var lc := lockup.get_center()
		_glow_at(Vector2(lc.x, lc.y), lockup.size.x * (0.55 + 0.04 * fl), glow, 0.10 + 0.07 * fl)
	# the row of burners on the counter, along the bottom of the hero band
	var base := gy
	draw_rect(Rect2(0, gy, w, h - gy), Color(0.34, 0.36, 0.4, 0.97))
	draw_rect(Rect2(0, gy, w, 3.0), Color(0.85, 0.88, 0.93, 0.75))
	var n := clampi(int(w / 190.0), 3, 7)
	for i in n:
		var bx := w * (float(i) + 0.5) / float(n)
		var ph := float(i) * 2.1
		var fl := 0.5 + 0.5 * sin(t * 7.0 + ph) * sin(t * 3.1 + ph * 0.6)
		_glow_at(Vector2(bx, base - 30.0 * fs), 150.0 * fs * (1.0 + 0.06 * fl), glow, 0.09 + 0.04 * fl)
		draw_rect(Rect2(bx - 56.0 * fs, base - 5.0, 112.0 * fs, 7.0), Color(0.06, 0.06, 0.07, 0.95))
		for j in 7:
			var a := float(j) / 7.0 * TAU
			var fx := bx + cos(a) * 40.0 * fs
			var fy := base - 3.0 + sin(a) * 6.0 * fs
			var fk := 0.75 + 0.25 * sin(t * 9.0 + ph + float(j) * 1.9) + 0.12 * sin(t * 17.0 + float(j) * 3.1 + ph)
			var sway := sin(t * 5.0 + float(j) + ph) * 0.12 + cos(a) * 0.25
			draw_set_transform(Vector2(fx, fy), sway, Vector2(fs * (1.25 + 0.14 * sin(t * 11.0 + float(j))), fs * fk * 1.1))
			draw_colored_polygon(_flame, Color(1.0, 0.36, 0.06, 0.9))
			draw_set_transform(Vector2(fx, fy), sway * 1.2, Vector2(fs * 0.9, fs * fk * 0.78))
			draw_colored_polygon(_flame, Color(1.0, 0.7, 0.16, 0.95))
			draw_set_transform(Vector2(fx, fy), sway * 1.4, Vector2(fs * 0.46, fs * fk * 0.4))
			draw_colored_polygon(_flame, Color(1.0, 0.95, 0.7, 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# steam
	for i in 4:
		var sx := w * (0.15 + 0.23 * float(i))
		var span := hh_band * 0.95
		var y0 := base - 40.0 * fs
		for j in 9:
			var u := float(j) / 8.0
			_wisp[j] = Vector2(sx + sin(t * 0.9 + float(j) * 0.75 + float(i) * 2.2) * 16.0 * u + u * 8.0, y0 - u * span)
		draw_polyline_colors(_wisp, _wisp_cols, 7.0 + 2.0 * float(i % 2), true)

func _hood(cx: float, hw: float, hh: float) -> PackedVector2Array:
	_wisp_hood[0] = Vector2(cx - hw * 0.5, 0)
	_wisp_hood[1] = Vector2(cx + hw * 0.5, 0)
	_wisp_hood[2] = Vector2(cx + hw * 0.5 + 34.0, hh)
	_wisp_hood[3] = Vector2(cx - hw * 0.5 - 34.0, hh)
	return _wisp_hood

var _wisp_hood := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

func _bow(p: Vector2, s: float, col: Color, t: float, ph: float) -> void:
	var k := 1.0 + 0.07 * sin(t * 2.4 + ph)
	var r := 9.0 * s * k
	draw_circle(p + Vector2(-r * 0.9, 0), r, col)
	draw_circle(p + Vector2(r * 0.9, 0), r, col)
	draw_circle(p, r * 0.55, col.darkened(0.25))

func _gift(base: Vector2, bw: float, bh: float, col: Color, rib: Color, t: float, ph: float, bow: bool) -> void:
	draw_rect(Rect2(base.x - bw * 0.5, base.y - bh, bw, bh), col)
	draw_rect(Rect2(base.x - bw * 0.5, base.y - bh, bw, 4.0), col.lightened(0.2))
	draw_rect(Rect2(base.x - 5.0, base.y - bh, 10.0, bh), rib)
	draw_rect(Rect2(base.x - bw * 0.5, base.y - bh * 0.55, bw, 8.0), rib)
	if bow: _bow(Vector2(base.x, base.y - bh - 2.0 + sin(t * 2.4 + ph) * 2.0), bw / 46.0, rib, t, ph)

func _draw_xmas() -> void:
	var t := now()
	var w := size.x
	var h := size.y
	var gy := ground_y()
	var hb := hero_h()
	_bg()
	_glow_at(Vector2(w * 0.86, h * 0.17), h * 0.16, Color(1, 0.9, 0.6), 0.05)
	# fir trees at both sides, standing on the drift
	var ts := clampf(hb / 150.0, 0.6, 1.6) * 1.9
	for side in 2:
		var tx := w * (0.035 if side == 0 else 0.965)
		draw_set_transform(Vector2(tx, gy), 0.0, Vector2(ts, ts))
		draw_colored_polygon(_tree, Color(0.04, 0.22, 0.13, 0.95))
		for j in 7:
			var oc := _bulb_cols[(j + side) % 4]
			var b := 0.5 + 0.5 * sin(t * 2.0 + float(j) * 1.3 + float(side) * 2.0)
			draw_circle(Vector2(-16.0 + float(j) * 5.0, -22.0 - float((j * 37) % 70)), 3.0, Color(oc.r, oc.g, oc.b, 0.35 + 0.65 * b))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# sparkle behind the title lockup
	if lockup.size.x > 10.0:
		var lc := lockup.get_center()
		_glow_at(lc, lockup.size.x * 0.5, Color(1, 0.88, 0.5), 0.07)
		for i in 5:
			var sp := lockup.position + Vector2(lockup.size.x * (0.12 + 0.19 * float(i)), lockup.size.y * (0.2 + 0.6 * float((i * 3) % 5) / 4.0))
			var b := maxf(0.0, sin(t * 2.6 + float(i) * 1.9))
			var r := 2.0 + 6.0 * b
			draw_line(sp - Vector2(r, 0), sp + Vector2(r, 0), Color(1, 0.95, 0.75, b), 1.6)
			draw_line(sp - Vector2(0, r), sp + Vector2(0, r), Color(1, 0.95, 0.75, b), 1.6)
	# the snow drift along the bottom of the hero band and the gifts on it
	draw_polygon(_ground, _ground_cols)
	draw_polyline(_ground_line, Color(1, 1, 1, 0.9), 3.0, true)
	if stage.size.x > 10.0:
		_globe_back(t)
	else:
		var gs := clampf(hb / 150.0, 0.45, 1.2) * 0.72
		_gift(Vector2(w * 0.3, gy - 4.0), 54.0 * gs, 40.0 * gs, Color("#d63a3a"), Color("#f4e8c0"), t, 0.0, true)
		_gift(Vector2(w * 0.6, gy - 4.0), 50.0 * gs, 36.0 * gs, Color("#f2c230"), Color("#d63a3a"), t, 3.0, true)
	# the string of lights
	draw_polyline(_garland, Color(0.05, 0.22, 0.13, 0.95), 7.0, true)
	draw_polyline(_garland, Color(0.14, 0.45, 0.25, 0.9), 3.0, true)
	for i in 22:
		var gp := _garland[int(float(i) / 21.0 * 48.0)]
		var bc := _bulb_cols[i % 4]
		var b := 0.5 + 0.5 * sin(t * 2.3 + float(i) * 1.7)
		draw_circle(gp + Vector2(0, 7), 11.0, Color(bc.r, bc.g, bc.b, 0.1 + 0.18 * b))
		draw_circle(gp + Vector2(0, 7), 4.6, bc.darkened(0.45 - 0.45 * b))

func _draw_australia() -> void:
	var t := now()
	var w := size.x
	var h := size.y
	var gy := ground_y()
	var hb := hero_h()
	_bg()
	var sp := Vector2(w * 0.82, minf(h * 0.2, gy - hb * 0.6))
	var sr := clampf(hb * 0.42, 34.0, 90.0)
	_glow_at(sp, sr * 3.4, glow, 0.07)
	for i in 14:
		draw_set_transform(sp, t * 0.05 + float(i) * TAU / 14.0, Vector2(1, clampf(h / 540.0, 0.6, 1.2)))
		draw_colored_polygon(_ray, Color(glow.r, glow.g, glow.b, 0.075 + 0.03 * sin(t * 0.7 + float(i))))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(sp, sr, Color(1.0, 0.95, 0.7, 0.95))
	draw_circle(sp, sr * 0.82, Color(1.0, 0.98, 0.85, 1.0))
	draw_colored_polygon(_hills, Color(0.64, 0.27, 0.12, 0.55))
	if lockup.size.x > 10.0:
		_glow_at(lockup.get_center(), lockup.size.x * 0.55, Color(1.0, 0.85, 0.5), 0.06)
	_draw_suburb(t, gy, hb)
	# the Hills Hoist, behind the fence
	var fh := fence_h()
	var px := stage.get_center().x if stage.size.x > 10.0 else w * 0.5
	var pb := gy
	var pt := gy - hb * 0.74
	var rad := clampf(stage.size.x * 0.4 if stage.size.x > 10.0 else hb * 0.5, 44.0, 120.0)
	draw_line(Vector2(px, pb), Vector2(px, pt), Color(0.32, 0.2, 0.12, 0.9), 5.0)
	for i in 4:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var a := t * 0.35 + float(i) * TAU / 4.0
		var tip := Vector2(px + cos(a) * rad, pt + sin(a) * rad * 0.22 - absf(cos(a)) * 6.0)
		draw_line(Vector2(px, pt), tip, Color(0.25, 0.16, 0.1, 0.9), 3.0)
		if i % 2 == 0:
			for j in 4:
				var u := 0.3 + 0.18 * float(j)
				var cp := Vector2(px, pt).lerp(tip, u)
				draw_set_transform(cp + Vector2(0, 2), sin(t * 3.0 + float(j) * 1.4 + float(i)) * 0.16, Vector2(1, 1))
				draw_rect(Rect2(-6, 0, 12, 18), _wash_cols[(i + j) % 6])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_kangaroo(t, gy)
	# the boomerang: one flight every 10 seconds
	var u := fmod(t, 10.0) / 3.4
	if u < 1.0:
		var bp := Vector2(lerpf(-40.0, w + 40.0, u), gy - hb * 0.7 - sin(u * PI) * hb * 0.35)
		draw_set_transform(bp, t * 13.0, Vector2(1.2, 1.2))
		draw_line(Vector2(-22, 9), Vector2(0, -7), Color(0.42, 0.24, 0.1, 0.98), 7.0)
		draw_line(Vector2(0, -7), Vector2(22, 9), Color(0.42, 0.24, 0.1, 0.98), 7.0)
		draw_line(Vector2(-18, 6), Vector2(0, -8), Color(0.8, 0.45, 0.2, 0.9), 2.0)
		draw_line(Vector2(0, -8), Vector2(18, 6), Color(0.8, 0.45, 0.2, 0.9), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the corrugated-iron fence along the bottom of the hero band
	draw_rect(Rect2(0, gy + 4.0, w, h - gy), Color(0.62, 0.27, 0.13, 1.0))                              # the red dirt
	draw_rect(Rect2(0, gy - fh, w, fh + 4.0), Color(0.46, 0.5, 0.52, 0.96))
	draw_multiline(_ridges, Color(1, 1, 1, 0.16), 3.0)
	draw_rect(Rect2(0, gy - fh, w, 5.0), Color(0.3, 0.33, 0.36, 0.95))
	draw_rect(Rect2(0, gy - fh * 0.5, w, 3.0), Color(0.62, 0.3, 0.14, 0.4))

# ---------------- xmas: the snow globe ----------------

func _globe_geom() -> Vector3:
	return Vector3(stage.position.x + stage.size.x * 0.296, stage.position.y + stage.size.y * 0.47, stage.size.y * 0.48)

func _globe_back(t: float) -> void:
	var g := _globe_geom()
	var c := Vector2(g.x, g.y)
	var r := g.z
	draw_circle(c, r, Color(0.7, 0.85, 1.0, 0.16))
	draw_circle(c, r * 0.8, Color(0.75, 0.88, 1.0, 0.07))
	# the little drift, the tree and the gifts inside
	draw_set_transform(c + Vector2(0, r * 0.74), 0.0, Vector2(r * 0.86, r * 0.2))
	draw_circle(Vector2.ZERO, 1.0, Color(0.92, 0.96, 1.0, 0.95))
	draw_set_transform(c + Vector2(r * 0.52, r * 0.78), 0.0, Vector2(r * 0.0075, r * 0.0075))
	draw_colored_polygon(_tree, Color(0.1, 0.45, 0.24, 1.0))
	for j in 3: draw_circle(Vector2(-10.0 + float(j) * 10.0, -24.0 - float(j % 2) * 24.0), 3.5, _bulb_cols[(j + 1) % 4].lightened(0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var gk := r / 60.0
	_gift(c + Vector2(-r * 0.62, r * 0.8), 20.0 * gk, 16.0 * gk, Color("#d63a3a"), Color("#f4e8c0"), t, 0.0, true)
	_gift(c + Vector2(-r * 0.4, r * 0.82), 15.0 * gk, 12.0 * gk, Color("#3a7fd6"), Color("#f4f1ea"), t, 2.0, false)
	# the base, with the pack's name on it
	var bt := c.y + r * 0.84
	var bh := stage.end.y - bt + r * 0.14
	draw_rect(Rect2(c.x - r * 0.9, bt, r * 1.8, bh), Color(0.62, 0.1, 0.12, 1.0))
	draw_rect(Rect2(c.x - r * 0.9, bt, r * 1.8, 3.0), Color(0.95, 0.78, 0.3, 1.0))
	draw_rect(Rect2(c.x - r * 0.9, bt + bh - 3.0, r * 1.8, 3.0), Color(0.4, 0.06, 0.08, 1.0))
	var fs := int(clampf(bh * 0.55, 10.0, 22.0))
	if base_text != "" and bh >= 14.0:
		var font: Font = ThemeDB.fallback_font
		var tw := font.get_string_size(base_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw <= r * 1.6: draw_string(font, Vector2(c.x - tw * 0.5, bt + bh * 0.5 + fs * 0.35), base_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.65))
	# the swirling snow inside the glass
	var sp := 0.35 + _shake * 4.0
	for i in 16:
		var a := float(i) * 2.4 + t * sp * (0.6 + 0.4 * float(i % 3))
		var rr := r * (0.25 + 0.7 * fmod(float(i) * 0.37, 1.0)) * 0.92
		var p := c + Vector2(cos(a) * rr, sin(a * 0.7 + float(i)) * rr * 0.9 - _shake * 6.0 * sin(t * 9.0 + float(i)))
		draw_circle(p, 1.6 + float(i % 3) * 0.7, Color(1, 1, 1, 0.85))

# ---------------- kitchen: the interior ----------------

func _kitchen_back(t: float) -> void:
	var S := stage
	var wall := Rect2(S.position.x - 6.0, S.position.y - 4.0, S.size.x + 12.0, S.size.y * 0.82)
	draw_rect(wall, Color(0.72, 0.74, 0.78, 0.30))
	var x := wall.position.x
	while x < wall.end.x:
		draw_line(Vector2(x, wall.position.y), Vector2(x, wall.end.y), Color(1, 1, 1, 0.12), 1.0)
		x += 20.0
	var y := wall.position.y
	while y < wall.end.y:
		draw_line(Vector2(wall.position.x, y), Vector2(wall.end.x, y), Color(1, 1, 1, 0.12), 1.0)
		y += 20.0
	# a pot rail with pots and a ladle, swaying a little
	draw_line(Vector2(wall.position.x, wall.position.y + 4.0), Vector2(wall.end.x, wall.position.y + 4.0), Color(0.8, 0.83, 0.88, 0.8), 3.0)
	for i in 4:
		var px := wall.position.x + wall.size.x * (0.1 + 0.27 * float(i)) + (24.0 if i == 3 else 0.0)
		var ll := 8.0 + 8.0 * float(i % 2)
		draw_set_transform(Vector2(px, wall.position.y + 4.0), sin(t * 1.4 + float(i)) * 0.06, Vector2.ONE * clampf(S.size.y / 110.0, 0.7, 1.6))
		draw_line(Vector2.ZERO, Vector2(0, ll), Color(0.85, 0.88, 0.92, 0.9), 1.5)
		if i % 2 == 0:
			draw_set_transform(Vector2(px, wall.position.y + 4.0 + ll * clampf(S.size.y / 110.0, 0.7, 1.6)), sin(t * 1.4 + float(i)) * 0.06, Vector2.ONE * clampf(S.size.y / 110.0, 0.7, 1.6))
			draw_colored_polygon(_pot, Color(0.62, 0.65, 0.7, 0.95))
			draw_rect(Rect2(-12, 1, 3, 3), Color(0.3, 0.3, 0.33))
		else:
			draw_circle(Vector2(0, ll + 6.0), 6.0, Color(0.8, 0.83, 0.88, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the warm hanging light
	var lx := S.position.x + S.size.x * 0.52
	var ly := wall.position.y + 2.0
	var cone := wall.size.y * 0.95
	draw_colored_polygon(_cone(lx, ly, cone), Color(1.0, 0.82, 0.45, 0.10 + 0.02 * sin(t * 3.0)))
	draw_rect(Rect2(lx - 9.0, ly, 18.0, 10.0), Color(0.15, 0.15, 0.17, 0.95))
	_glow_at(Vector2(lx, ly + 12.0), 22.0, Color(1.0, 0.85, 0.5), 0.35)
	# the stove on the counter (right), burners glowing
	var cy := S.position.y + S.size.y * 0.80
	var sw := S.size.x * 0.2
	var sx := S.end.x - sw - 4.0
	draw_rect(Rect2(sx, cy - S.size.y * 0.13, sw, S.size.y * 0.13), Color(0.1, 0.1, 0.12, 0.96))
	var fk := 0.7 + 0.3 * sin(t * 9.0)
	var fsx := clampf(S.size.y / 400.0, 0.2, 0.6)
	for i in 2:
		var fx := sx + sw * (0.3 + 0.4 * float(i))
		_glow_at(Vector2(fx, cy - S.size.y * 0.16), S.size.y * 0.2, glow, 0.18)
		draw_set_transform(Vector2(fx, cy - S.size.y * 0.13), 0.0, Vector2(fsx, fsx * fk))
		draw_colored_polygon(_flame, Color(1.0, 0.45, 0.1, 0.95))
		draw_set_transform(Vector2(fx, cy - S.size.y * 0.13), 0.0, Vector2(fsx * 0.55, fsx * fk * 0.7))
		draw_colored_polygon(_flame, Color(1.0, 0.85, 0.3, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _cone(lx: float, ly: float, cone: float) -> PackedVector2Array:
	_lamp_quad[0] = Vector2(lx - 5.0, ly + 10.0)
	_lamp_quad[1] = Vector2(lx + 5.0, ly + 10.0)
	_lamp_quad[2] = Vector2(lx + cone * 0.55, ly + cone)
	_lamp_quad[3] = Vector2(lx - cone * 0.55, ly + cone)
	return _lamp_quad

var _lamp_quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

# ---------------- australia: the desert suburb ----------------

func _draw_suburb(t: float, gy: float, hb: float) -> void:
	var fh := fence_h()
	var base := gy - fh
	var hs := clampf(hb * 0.2, 14.0, 44.0)
	for i in 6:
		var hx := size.x * (0.05 + 0.17 * float(i)) + float(i % 2) * 12.0
		if stage.size.x > 10.0 and hx > stage.position.x - hs and hx < stage.end.x + hs: continue    # the stage keeps its own space
		var wall_col := Color(0.93, 0.86, 0.72, 0.9) if i % 2 == 0 else Color(0.82, 0.9, 0.86, 0.9)
		draw_rect(Rect2(hx - hs, base - hs * 0.8, hs * 2.0, hs * 0.8), wall_col)
		draw_set_transform(Vector2(hx, base - hs * 0.8), 0.0, Vector2(hs, hs))
		draw_colored_polygon(_roof, Color(0.55, 0.2, 0.12, 0.95))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(hx - hs * 0.55, base - hs * 0.55, hs * 0.35, hs * 0.3), Color(0.3, 0.45, 0.55, 0.9))
	# two gum trees
	for i in 2:
		var tx := (stage.position.x - 14.0) if i == 0 else (stage.end.x + 18.0)
		if stage.size.x <= 10.0: tx = size.x * (0.3 + 0.35 * float(i))
		var th := hb * (0.62 if i == 0 else 0.5)
		draw_line(Vector2(tx, base + 2.0), Vector2(tx + 3.0, base - th), Color(0.82, 0.78, 0.7, 0.95), 5.0)
		var sw := sin(t * 0.8 + float(i)) * 2.0
		draw_circle(Vector2(tx + sw, base - th), th * 0.3, Color(0.38, 0.5, 0.36, 0.92))
		draw_circle(Vector2(tx - th * 0.22 + sw, base - th * 0.8), th * 0.22, Color(0.34, 0.46, 0.32, 0.92))
		draw_circle(Vector2(tx + th * 0.24 + sw, base - th * 0.85), th * 0.22, Color(0.42, 0.54, 0.38, 0.92))

func _draw_kangaroo(t: float, gy: float) -> void:
	var gx := size.x * 0.86
	var gyy := gy - 6.0
	var k := clampf(hero_h() / 140.0, 0.5, 1.3)
	if stage.size.x > 10.0:
		gx = stage.position.x + stage.size.x * 0.86
		gyy = stage.end.y - 4.0
		k = clampf(stage.size.y / 150.0, 0.5, 1.4)
	var bob := sin(t * 1.8) * 2.0 * k
	var body := Color(0.72, 0.45, 0.22, 1.0)
	var dark := Color(0.55, 0.32, 0.15, 1.0)
	draw_set_transform(Vector2(gx, gyy), 0.0, Vector2(k, k))
	draw_colored_polygon(_k_tail, dark)
	draw_colored_polygon(_k_leg, dark)
	draw_set_transform(Vector2(gx + 4.0 * k, gyy - (40.0 + bob) * k), -0.25, Vector2(13.0 * k, 22.0 * k))
	draw_circle(Vector2.ZERO, 1.0, body)
	draw_set_transform(Vector2(gx + 2.0 * k, gyy - (36.0 + bob) * k), -0.25, Vector2(7.0 * k, 14.0 * k))
	draw_circle(Vector2.ZERO, 1.0, Color(0.9, 0.78, 0.6, 1.0))
	var hr := sin(t * 1.1) * 0.1
	draw_set_transform(Vector2(gx, gyy - bob * k), hr, Vector2(k, k))
	draw_circle(Vector2(-8, -70), 6.5, body)
	draw_colored_polygon(_k_snout, body)
	draw_circle(Vector2(-10, -72), 1.4, Color(0.1, 0.07, 0.05))
	draw_set_transform(Vector2(gx - 5.0 * k, gyy - (75.0 + bob) * k), hr + sin(t * 3.0) * 0.08, Vector2(k, k))
	draw_colored_polygon(_k_ear, dark)
	draw_set_transform(Vector2(gx + 0.0 * k, gyy - (75.0 + bob) * k), hr * 0.5, Vector2(k, k))
	draw_colored_polygon(_k_ear, body)
	draw_set_transform(Vector2(gx, gyy - bob * k), 0.0, Vector2(k, k))
	draw_line(Vector2(-4, -52), Vector2(-13, -44), dark, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------- the foreground layer (over the 3D stage) ----------------

func draw_foreground(ci: CanvasItem) -> void:
	if stage.size.x < 10.0: return
	var S := Rect2(stage.position - fg_origin, stage.size)
	match kind:
		"xmas":
			var g := _globe_geom()
			var c := Vector2(g.x, g.y) - fg_origin
			var r := g.z
			ci.draw_arc(c, r, 0.0, TAU, 40, Color(0.85, 0.93, 1.0, 0.55), 3.0, true)
			ci.draw_arc(c, r * 0.86, PI * 1.12, PI * 1.5, 14, Color(1, 1, 1, 0.8), 4.0, true)
			ci.draw_arc(c, r * 0.86, PI * 1.58, PI * 1.64, 4, Color(1, 1, 1, 0.8), 4.0, true)
			ci.draw_circle(c + Vector2(r * 0.55, -r * 0.5), 2.5, Color(1, 1, 1, 0.8))
		"kitchen":
			var top := S.position.y + S.size.y * 0.80
			ci.draw_rect(Rect2(S.position.x - 6.0, top, S.size.x + 12.0, S.size.y * 0.24), Color(0.5, 0.53, 0.58, 1.0))
			ci.draw_rect(Rect2(S.position.x - 6.0, top, S.size.x + 12.0, 4.0), Color(0.88, 0.9, 0.94, 1.0))
			ci.draw_rect(Rect2(S.position.x - 6.0, top + 4.0, S.size.x + 12.0, 3.0), Color(0.3, 0.32, 0.36, 0.7))
			var dx := S.position.x - 6.0
			while dx < S.end.x + 6.0:
				ci.draw_line(Vector2(dx, top + 8.0), Vector2(dx, S.end.y + 8.0), Color(0.3, 0.32, 0.36, 0.6), 1.5)
				dx += maxf(30.0, S.size.x * 0.24)

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
