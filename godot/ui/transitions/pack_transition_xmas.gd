extends RefCounted
## Ho Ho Ho (xmas): snow swirls round the screen while two halves of green wrapping paper close like a present, a red ribbon
## runs down and across, a bow pops on the crossing (with sparkles and a gift tag carrying the pack's name), and the whole
## parcel unwraps again: the bow spins away, the ribbons slide off, the paper opens like curtains. 48 flakes and 14 sparkles.

const N_FLAKES := 40
const N_SPARKS := 14
const RED := Color("#d92f3b")
const RED_DK := Color("#9c1d28")
const GREEN := Color("#1b6b3a")
const GREEN_DK := Color("#114a29")
const GOLD := Color("#f6c445")
const SNOW := Color("#f4f8ff")

var cues := [[0.08, "clink", 0.35], [0.34, "pickup", 0.5], [0.5, "clink", 0.5], [0.66, "pickup", 0.4]]
var _frost: GradientTexture2D
var _fa := PackedFloat32Array()   # flake: base angle
var _fr := PackedFloat32Array()   # flake: base radius (0..1 of the diagonal)
var _fs := PackedFloat32Array()   # flake: size
var _fw := PackedFloat32Array()   # flake: swirl speed
var _sx := PackedFloat32Array()   # sparkle: x offset (-1..1 around the bow)
var _sy := PackedFloat32Array()
var _sb := PackedFloat32Array()   # sparkle: birth p
var _ss := PackedFloat32Array()

func setup(t: PackTransition) -> void:
	for i in N_FLAKES:
		_fa.append(t.rng.randf() * TAU)
		_fr.append(sqrt(t.rng.randf()))
		_fs.append(t.rng.randf_range(0.5, 1.0))
		_fw.append(t.rng.randf_range(0.6, 1.2))
	for i in N_SPARKS:
		_sx.append(t.rng.randf_range(-1.0, 1.0))
		_sy.append(t.rng.randf_range(-1.0, 1.0))
		_sb.append(t.rng.randf_range(0.34, 0.6))
		_ss.append(t.rng.randf_range(0.5, 1.0))

func tick(_t: PackTransition) -> void:
	pass

func draw(t: PackTransition) -> void:
	var w := t.size.x
	var h := t.size.y
	var u := t.unit()
	var ctr := t.size * 0.5
	var cv := PackTransition.smooth(t.cover())
	var rv := PackTransition.smooth(t.reveal())
	# ---- the paper: two halves closing (cover) and opening like curtains (reveal), a little late behind the ribbon
	var close_k := PackTransition.smooth(PackTransition.seg(t.p, 0.0, 0.44))
	var open_k := PackTransition.smooth(PackTransition.seg(t.p, 0.58, 1.0))
	var half := w * 0.5
	var lx := half * close_k - half * open_k                      # right edge of the left panel (0 = off the left side, w/2 = at the seam)
	var rx := w - half * close_k + half * open_k                  # left edge of the right panel
	if close_k > 0.001 and open_k < 0.999:
		_paper(t, Rect2(lx - half, 0.0, half, h), true)
		_paper(t, Rect2(rx, 0.0, half, h), false)
	# ---- the ribbon cross
	var rw := u * 0.13
	var vgrow := PackTransition.smooth(PackTransition.seg(t.p, 0.14, 0.46))
	var vshrink := PackTransition.smooth(PackTransition.seg(t.p, 0.54, 0.86))
	var y0 := h * vshrink
	var y1 := h * vgrow
	if y1 - y0 > 1.0: _ribbon_v(t, Rect2(ctr.x - rw * 0.5, y0, rw, y1 - y0))
	var hgrow := PackTransition.smooth(PackTransition.seg(t.p, 0.22, 0.5))
	var hshrink := PackTransition.smooth(PackTransition.seg(t.p, 0.56, 0.9))
	var x0 := w * hshrink
	var x1 := w * hgrow
	if x1 - x0 > 1.0: _ribbon_h(t, Rect2(x0, ctr.y - rw * 0.5, x1 - x0, rw))
	# ---- the bow pops on the crossing and spins away on the unwrap
	var pop := PackTransition.smooth(PackTransition.seg(t.p, 0.32, 0.54))      # a gentle swell, no overshoot
	var away := PackTransition.seg(t.p, 0.5, 0.82)
	var bs := pop * (1.0 - PackTransition.smooth(away)) * u * 0.0036
	if bs > 0.01:
		var rot: float = (1.0 - pop) * -0.6 + PackTransition.smooth(away) * 2.2
		var lift := Vector2(0, -PackTransition.smooth(away) * u * 0.25)
		t.draw_set_transform(ctr + lift, rot, Vector2(bs, bs))
		_bow(t)
		t.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# the gift tag with the pack's name, hanging from the knot
		var ta := PackTransition.env(t.p, 0.4, 0.54, 0.58, 0.7)
		if ta > 0.01:
			var tc := ctr + Vector2(u * 0.3, u * 0.2) + lift
			t.draw_set_transform(tc, -0.12, Vector2(ta, ta))
			var tw := minf(w * 0.5, u * 0.9)
			var th := u * 0.2
			t.draw_line(Vector2(-tw * 0.5 - u * 0.24, -u * 0.18), Vector2(-tw * 0.5 + 6.0, 0), GOLD, 3.0, true)
			t.draw_rect(Rect2(-tw * 0.5 - 4.0, -th * 0.5 - 4.0, tw + 8.0, th + 8.0), Color(0, 0, 0, 0.25))
			t.draw_rect(Rect2(-tw * 0.5, -th * 0.5, tw, th), Color("#fbf4e4"))
			t.draw_rect(Rect2(-tw * 0.5, -th * 0.5, tw, th * 0.12), RED)
			t.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			t.banner(t.label, tc + Vector2(0, th * 0.06).rotated(-0.12), tw * 0.9, GREEN_DK, Color(0, 0, 0, 0), ta, 1.0, int(th * 0.55))
	# ---- sparkles around the bow
	for i in N_SPARKS:
		var age := (t.p - _sb[i]) / 0.18
		if age < 0.0 or age > 1.0: continue
		var tw2 := sin(age * PI)
		t.sparkle(ctr + Vector2(_sx[i], _sy[i]) * u * 0.42, u * 0.05 * _ss[i] * tw2, Color(1.0, 0.95, 0.65, tw2))
	# ---- snow swirl (in front of everything): flakes spiral round the middle; calm at the switch point
	var swirl := sin(t.p * PI)          # strongest mid-way
	var edge_k := PackTransition.smooth(PackTransition.seg(t.p, 0.0, 0.14)) * (1.0 - PackTransition.smooth(PackTransition.seg(t.p, 0.86, 1.0)))
	# the frosty snow-globe vignette closes in softly and opens last
	var fa := PackTransition.env(t.p, 0.0, 0.42, 0.66, 1.0)
	if fa > 0.003:
		if _frost == null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			g.colors = PackedColorArray([Color(0.85, 0.95, 1, 0), Color(0.85, 0.95, 1, 0.0), Color(0.82, 0.93, 1, 0.9)])
			_frost = GradientTexture2D.new()
			_frost.gradient = g
			_frost.fill = GradientTexture2D.FILL_RADIAL
			_frost.fill_from = Vector2(0.5, 0.5)
			_frost.fill_to = Vector2(1.0, 0.5)
			_frost.width = 128
			_frost.height = 128
		var fs := lerpf(2.6, 1.3, PackTransition.smooth(PackTransition.seg(t.p, 0.0, 0.45)))
		t.draw_texture_rect(_frost, Rect2(ctr - t.size * fs * 0.5, t.size * fs), false, Color(1, 1, 1, fa))
	var diag := sqrt(w * w + h * h) * 0.5
	for i in N_FLAKES:
		var prog := t.p * _fw[i]
		var ang := _fa[i] + prog * 4.2 * (0.4 + _fr[i])
		var rad := diag * _fr[i] * (1.15 - 0.55 * sin(clampf(t.p, 0.0, 1.0) * PI) * (1.0 - _fr[i] * 0.4))
		var pos := ctr + Vector2(cos(ang) * rad * 1.1, sin(ang) * rad * 0.8)
		var r := u * 0.012 * (0.7 + _fs[i])
		var a := (0.3 + 0.6 * swirl) * edge_k
		if i % 5 == 0: _flake(t, pos, r * 2.6, ang, Color(SNOW, a))
		else: t.draw_circle(pos, r, Color(SNOW, a), true)

func _paper(t: PackTransition, r: Rect2, left: bool) -> void:
	var u := t.unit()
	t.draw_rect(r, GREEN)
	# candy-cane stripes, diagonal, low contrast
	var sw := u * 0.09
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(x, r.end.y)
		var b := Vector2(x + r.size.y, r.position.y)
		var q := PackedVector2Array([a, a + Vector2(sw * 0.5, 0), b + Vector2(sw * 0.5, 0), b])
		_clip_draw(t, q, r, Color(GREEN_DK, 0.55))
		x += sw * 2.0
	# little white stars on a lattice
	var step := u * 0.16
	var row := 0
	var yy := r.position.y + step * 0.5
	while yy < r.end.y:
		var xx := r.position.x + step * (0.5 if row % 2 == 0 else 1.0)
		while xx < r.end.x - 4.0:
			if xx > r.position.x + 4.0: t.sparkle(Vector2(xx, yy), u * 0.025, Color(1, 1, 1, 0.55))
			xx += step
		yy += step * 0.5
		row += 1
	# the seam edge (the side that meets in the middle)
	var ex := r.end.x if left else r.position.x
	t.draw_rect(Rect2(ex - (4.0 if left else 0.0), 0.0, 4.0, t.size.y), GREEN_DK)
	t.draw_rect(Rect2(ex - (10.0 if left else -6.0), 0.0, 4.0, t.size.y), Color(1, 1, 1, 0.18))

# draws polygon `q` intersected with the rect `r` by clipping to a simple convex rect (Sutherland-Hodgman against 4 sides)
func _clip_draw(t: PackTransition, q: PackedVector2Array, r: Rect2, c: Color) -> void:
	var pts := q
	for side in 4:
		var out := PackedVector2Array()
		var n := pts.size()
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			var ina := _inside(a, r, side)
			var inb := _inside(b, r, side)
			if ina: out.append(a)
			if ina != inb: out.append(_isect(a, b, r, side))
		pts = out
		if pts.size() < 3: return
	t.poly(pts, c)

func _inside(p: Vector2, r: Rect2, side: int) -> bool:
	match side:
		0: return p.x >= r.position.x
		1: return p.x <= r.end.x
		2: return p.y >= r.position.y
	return p.y <= r.end.y

func _isect(a: Vector2, b: Vector2, r: Rect2, side: int) -> Vector2:
	var k := 0.0
	match side:
		0: k = (r.position.x - a.x) / (b.x - a.x)
		1: k = (r.end.x - a.x) / (b.x - a.x)
		2: k = (r.position.y - a.y) / (b.y - a.y)
		_: k = (r.end.y - a.y) / (b.y - a.y)
	return a.lerp(b, k)

func _ribbon_v(t: PackTransition, r: Rect2) -> void:
	t.draw_rect(Rect2(r.position.x + 3.0, r.position.y, r.size.x, r.size.y), Color(0, 0, 0, 0.25))
	t.draw_rect(r, RED)
	t.draw_rect(Rect2(r.position.x, r.position.y, r.size.x * 0.14, r.size.y), RED_DK)
	t.draw_rect(Rect2(r.end.x - r.size.x * 0.14, r.position.y, r.size.x * 0.14, r.size.y), RED_DK)
	t.draw_rect(Rect2(r.position.x + r.size.x * 0.4, r.position.y, r.size.x * 0.16, r.size.y), Color(1, 1, 1, 0.22))
	t.draw_rect(Rect2(r.position.x + r.size.x * 0.22, r.position.y, 2.0, r.size.y), GOLD)
	t.draw_rect(Rect2(r.end.x - r.size.x * 0.22 - 2.0, r.position.y, 2.0, r.size.y), GOLD)

func _ribbon_h(t: PackTransition, r: Rect2) -> void:
	t.draw_rect(Rect2(r.position.x, r.position.y + 3.0, r.size.x, r.size.y), Color(0, 0, 0, 0.25))
	t.draw_rect(r, RED)
	t.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.14), RED_DK)
	t.draw_rect(Rect2(r.position.x, r.end.y - r.size.y * 0.14, r.size.x, r.size.y * 0.14), RED_DK)
	t.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.4, r.size.x, r.size.y * 0.16), Color(1, 1, 1, 0.22))
	t.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.22, r.size.x, 2.0), GOLD)
	t.draw_rect(Rect2(r.position.x, r.end.y - r.size.y * 0.22 - 2.0, r.size.x, 2.0), GOLD)

# the bow around (0, 0), about 200 units wide
func _bow(t: PackTransition) -> void:
	# two tails
	t.poly(PackedVector2Array([Vector2(-8, 10), Vector2(-70, 118), Vector2(-40, 112), Vector2(-24, 138), Vector2(14, 20)]), RED_DK)
	t.poly(PackedVector2Array([Vector2(8, 10), Vector2(70, 118), Vector2(40, 112), Vector2(24, 138), Vector2(-14, 20)]), RED)
	# the two loops
	for s in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 24:
			var a := i * TAU / 24.0
			var lx := cos(a) * 62.0
			var ly := sin(a) * 38.0
			var rot: float = s * 0.5
			var q := Vector2(lx * cos(rot) - ly * sin(rot), lx * sin(rot) + ly * cos(rot))
			pts.append(Vector2(s * 66.0, -22.0) + q)
		t.poly(pts, RED if s > 0 else RED_DK)
		var inner := PackedVector2Array()
		for i in 24:
			var a2 := i * TAU / 24.0
			var lx2 := cos(a2) * 34.0
			var ly2 := sin(a2) * 17.0
			var rot2: float = s * 0.5
			inner.append(Vector2(s * 66.0, -22.0) + Vector2(lx2 * cos(rot2) - ly2 * sin(rot2), lx2 * sin(rot2) + ly2 * cos(rot2)))
		t.poly(inner, Color(0.55, 0.08, 0.14, 0.9))
	# the knot
	t.draw_circle(Vector2(0, 0), 32.0, RED_DK, true)
	t.draw_circle(Vector2(-3, -3), 27.0, RED, true)
	t.draw_circle(Vector2(-10, -10), 8.0, Color(1, 1, 1, 0.35), true)

# a six-armed snowflake
func _flake(t: PackTransition, c: Vector2, r: float, rot: float, col: Color) -> void:
	for k in 3:
		var a := rot + k * PI / 3.0
		var d := Vector2(cos(a), sin(a)) * r
		t.draw_line(c - d, c + d, col, maxf(1.5, r * 0.14), true)
