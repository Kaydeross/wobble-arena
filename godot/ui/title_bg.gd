extends Control
## Title-screen backdrop: a deep teal vertical gradient, a warm glow behind the logo, low-poly hills along the bottom
## and a few slowly drifting confetti diamonds. Drawn, so it fits any aspect ratio.

const TOP := Color(0.05, 0.16, 0.2)
const BOTTOM := Color(0.09, 0.27, 0.31)
const GLOW := Color(1.0, 0.81, 0.35, 0.22)

## Construction DLC look: 0 = the normal teal title, 1 = a dusk worksite (crane, concrete frame, hazard-striped ground).
var mix := 0.0:
	set(v): mix = v; queue_redraw()
const D_TOP := Color(0.12, 0.10, 0.09)
const D_BOTTOM := Color(0.52, 0.31, 0.11)

var _t := 0.0
var _bits: Array = []
var _glow: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, GLOW)
	g.set_color(1, Color(GLOW.r, GLOW.g, GLOW.b, 0.0))
	g.add_point(0.45, Color(GLOW.r, GLOW.g, GLOW.b, GLOW.a * 0.45))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 256; _glow.height = 256
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 22:
		_bits.append([rng.randf(), rng.randf(), rng.randf_range(4, 9), rng.randf_range(0.01, 0.03), rng.randi_range(0, 2)])

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _draw() -> void:
	var s := size
	var top := TOP.lerp(D_TOP, mix)
	var bot := BOTTOM.lerp(D_BOTTOM, mix)
	var cols := PackedColorArray([top, top, bot, bot])
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]), cols)
	# warm glow behind the logo (radial gradient texture)
	var gr := s.y * 1.1
	draw_texture_rect(_glow, Rect2(Vector2(s.x * 0.22, s.y * 0.1) - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1.0, lerpf(1.0, 0.78, mix), lerpf(1.0, 0.42, mix), lerpf(1.0, 1.3, mix)))
	# confetti
	var pal := [Color(1, 0.81, 0.35, 0.5), Color(0.31, 0.88, 0.81, 0.4), Color(1, 1, 1, 0.25)]
	var dpal := [Color(1.0, 0.6, 0.15, 0.55), Color(1.0, 0.82, 0.1, 0.4), Color(0.9, 0.88, 0.82, 0.28)]
	for b: Array in _bits:
		var p := Vector2(fposmod(float(b[0]) + _t * b[3] * 0.3, 1.0) * s.x, fposmod(b[1] - _t * b[3], 1.0) * s.y)
		var k: float = b[2]
		var a: float = _t * 0.8 + float(b[0]) * 6.0
		var pts := PackedVector2Array()
		for j in 4:
			pts.append(p + Vector2.from_angle(a + j * PI / 2.0) * k * (1.0 if j % 2 == 0 else 0.6))
		draw_colored_polygon(pts, pal[b[4]].lerp(dpal[b[4]], mix))
	# low-poly hills
	var h1 := PackedVector2Array([Vector2(0, s.y), Vector2(0, s.y * 0.8), Vector2(s.x * 0.12, s.y * 0.7), Vector2(s.x * 0.27, s.y * 0.82),
		Vector2(s.x * 0.45, s.y * 0.68), Vector2(s.x * 0.62, s.y * 0.8), Vector2(s.x * 0.8, s.y * 0.66), Vector2(s.x, s.y * 0.78), Vector2(s.x, s.y)])
	draw_colored_polygon(h1, Color(0.07, 0.22, 0.26, 0.9 * (1.0 - mix)))
	var h2 := PackedVector2Array([Vector2(0, s.y), Vector2(0, s.y * 0.9), Vector2(s.x * 0.2, s.y * 0.84), Vector2(s.x * 0.38, s.y * 0.92),
		Vector2(s.x * 0.58, s.y * 0.85), Vector2(s.x * 0.76, s.y * 0.93), Vector2(s.x, s.y * 0.86), Vector2(s.x, s.y)])
	draw_colored_polygon(h2, Color(0.05, 0.17, 0.2, 0.95 * (1.0 - mix)))
	if mix > 0.0: _draw_site(s)

## The worksite (faded in by `mix`), placed in the gaps the title cards leave: a tower crane at the right edge
## swinging a load over the header, a low scaffold, cones and timber above the ground, and a hazard-striped ground strip.
func _draw_site(s: Vector2) -> void:
	var k := Color(0.07, 0.06, 0.06, 0.92 * mix)
	var ground := s.y * 0.935
	# tower crane
	var tx := s.x * 0.965
	var jib_y := s.y * 0.13
	draw_rect(Rect2(tx - 7.0, jib_y, 14.0, ground - jib_y), k)
	for i in 16:   # lattice
		var y0 := jib_y + i * (ground - jib_y) / 16.0
		var y1 := y0 + (ground - jib_y) / 16.0
		draw_line(Vector2(tx - 7.0, y0 if i % 2 == 0 else y1), Vector2(tx + 7.0, y1 if i % 2 == 0 else y0), k, 2.0)
	draw_rect(Rect2(tx - s.x * 0.42, jib_y - 5.0, s.x * 0.45, 10.0), k)                       # jib
	draw_rect(Rect2(tx + 2.0, jib_y - 5.0, s.x * 0.03, 30.0), k)                              # counterweight
	draw_colored_polygon(PackedVector2Array([Vector2(tx - 12.0, jib_y - 5.0), Vector2(tx + 12.0, jib_y - 5.0), Vector2(tx, jib_y - 44.0)]), k)
	var cx := tx - s.x * 0.27
	var hx := cx + sin(_t * 0.9) * 10.0
	var hy := jib_y + s.y * 0.1 + sin(_t * 1.3) * 3.0
	draw_line(Vector2(cx, jib_y + 5.0), Vector2(hx, hy), k, 2.0)
	draw_rect(Rect2(hx - 22.0, hy, 44.0, 24.0), Color(Hazard.YELLOW, 0.95 * mix))             # the hanging load
	draw_rect(Rect2(hx - 22.0, hy + 10.0, 44.0, 5.0), Color(Hazard.BLACK, 0.9 * mix))
	# low scaffold
	var sx := s.x * 0.25
	var sw := s.x * 0.1
	var st := ground - s.y * 0.15
	for f in 3:
		draw_rect(Rect2(sx, st + f * s.y * 0.075 - 3.0, sw, 6.0), k)
	for c in 3:
		draw_rect(Rect2(sx + c * (sw - 6.0) / 2.0, st, 6.0, ground - st), k)
	# stacked timber
	var lx := s.x * 0.55
	for r in 3:
		for c in 3 - r:
			draw_rect(Rect2(lx + c * 34.0 + r * 17.0, ground - 14.0 * (r + 1), 32.0, 12.0), Color(0.36, 0.22, 0.1, 0.95 * mix))
	# traffic cones
	for cxn: float in [0.42, 0.7, 0.8]:
		var bx := s.x * cxn
		draw_rect(Rect2(bx - 14.0, ground - 5.0, 28.0, 5.0), k)
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 11.0, ground - 5.0), Vector2(bx + 11.0, ground - 5.0), Vector2(bx, ground - 36.0)]), Color(1.0, 0.45, 0.1, 0.95 * mix))
		draw_rect(Rect2(bx - 7.0, ground - 20.0, 14.0, 4.0), Color(1, 1, 1, 0.9 * mix))
	# ground with a hazard strip
	draw_rect(Rect2(0, ground, s.x, s.y - ground), Color(0.06, 0.05, 0.05, 0.96 * mix))
	Hazard.stripes(self, Rect2(0, ground, s.x, 12.0), 14.0, _t * 6.0, Color(Hazard.YELLOW, mix), Color(Hazard.BLACK, mix))
