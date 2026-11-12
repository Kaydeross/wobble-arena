extends Control
## Title-screen backdrop: a deep teal vertical gradient, a warm glow behind the logo, low-poly hills along the bottom
## and a few slowly drifting confetti diamonds. Drawn, so it fits any aspect ratio.

const TOP := Color(0.05, 0.16, 0.2)
const BOTTOM := Color(0.09, 0.27, 0.31)
const GLOW := Color(1.0, 0.81, 0.35, 0.22)

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
	var cols := PackedColorArray([TOP, TOP, BOTTOM, BOTTOM])
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]), cols)
	# warm glow behind the logo (radial gradient texture)
	var gr := s.y * 1.1
	draw_texture_rect(_glow, Rect2(Vector2(s.x * 0.22, s.y * 0.1) - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false)
	# confetti
	var pal := [Color(1, 0.81, 0.35, 0.5), Color(0.31, 0.88, 0.81, 0.4), Color(1, 1, 1, 0.25)]
	for b: Array in _bits:
		var p := Vector2(fposmod(float(b[0]) + _t * b[3] * 0.3, 1.0) * s.x, fposmod(b[1] - _t * b[3], 1.0) * s.y)
		var k: float = b[2]
		var a: float = _t * 0.8 + float(b[0]) * 6.0
		var pts := PackedVector2Array()
		for j in 4:
			pts.append(p + Vector2.from_angle(a + j * PI / 2.0) * k * (1.0 if j % 2 == 0 else 0.6))
		draw_colored_polygon(pts, pal[b[4]])
	# low-poly hills
	var h1 := PackedVector2Array([Vector2(0, s.y), Vector2(0, s.y * 0.8), Vector2(s.x * 0.12, s.y * 0.7), Vector2(s.x * 0.27, s.y * 0.82),
		Vector2(s.x * 0.45, s.y * 0.68), Vector2(s.x * 0.62, s.y * 0.8), Vector2(s.x * 0.8, s.y * 0.66), Vector2(s.x, s.y * 0.78), Vector2(s.x, s.y)])
	draw_colored_polygon(h1, Color(0.07, 0.22, 0.26, 0.9))
	var h2 := PackedVector2Array([Vector2(0, s.y), Vector2(0, s.y * 0.9), Vector2(s.x * 0.2, s.y * 0.84), Vector2(s.x * 0.38, s.y * 0.92),
		Vector2(s.x * 0.58, s.y * 0.85), Vector2(s.x * 0.76, s.y * 0.93), Vector2(s.x, s.y * 0.86), Vector2(s.x, s.y)])
	draw_colored_polygon(h2, Color(0.05, 0.17, 0.2, 0.95))
