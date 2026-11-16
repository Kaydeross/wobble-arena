extends RefCounted
## Hey Mate (australia): a sunset rolls across the screen. Three layers of dusty earth sweep in (the dark far layer leads and
## trails, then a dusty orange one, then the body, a sunset gradient from plum through red and orange to gold). Once the screen
## is covered a low sun swells over gum-tree hills with soft rays and heat shimmer lines. A boomerang crosses in one smooth
## curve, spinning, its ghost trail fading gradually. Everything eases in and out on overlapping envelopes; 24 dust puffs.

const N_DUST := 24
const RAYS := 16
const SUN := Color("#ffd24a")
const DUST := [Color("#6f2418"), Color("#b8452a")]       # the two outer layers: far, mid
const SKY := [[0.0, Color("#3d1a45")], [0.38, Color("#b8372f")], [0.62, Color("#f2802a")], [0.82, Color("#ffc94a")], [1.0, Color("#e8923a")]]

var cues := [[0.06, "swing", 0.5], [0.22, "swing", 0.35], [0.44, "slap", 0.6], [0.68, "swing", 0.35]]
var _dx := PackedFloat32Array()
var _dy := PackedFloat32Array()
var _db := PackedFloat32Array()
var _ds := PackedFloat32Array()
var _jag := PackedFloat32Array()
var _glow: GradientTexture2D

func setup(t: PackTransition) -> void:
	for i in N_DUST:
		_dx.append(t.rng.randf_range(-0.1, 0.1))
		_dy.append(t.rng.randf())
		_db.append(t.rng.randf_range(0.02, 0.9))
		_ds.append(t.rng.randf_range(0.6, 1.2))
	for i in 3 * 17:
		_jag.append(t.rng.randf_range(-1.0, 1.0))
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 128
	_glow.height = 128

func tick(_t: PackTransition) -> void:
	pass

func _sky(fy: float) -> Color:
	for i in SKY.size() - 1:
		var a: Array = SKY[i]
		var b: Array = SKY[i + 1]
		if fy <= float(b[0]):
			return (a[1] as Color).lerp(b[1] as Color, clampf((fy - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0))
	return SKY[SKY.size() - 1][1]

# x of the wipe front at height fy (0..1 from the top) for sweep amount k (0..1), layer l (0 far .. 2 body)
func _edge(t: PackTransition, k: float, fy: float, l: int, phase: int) -> float:
	var w := t.size.x
	var slant := t.size.y * 0.5
	var lag := l * 0.08 if phase == 0 else (2 - l) * 0.08       # the dark far layer leads and trails (the outer skin of the dust cloud)
	var kk := PackTransition.smooth(clampf((k - lag) / (1.0 - 0.16), 0.0, 1.0))
	var base := lerpf(-slant * 0.5 - w * 0.02, w + slant + w * 0.08, kk)
	var idx := l * 17 + clampi(int(fy * 16.0 + 0.5), 0, 16)
	return base + (fy - 0.5) * slant * 2.0 * -0.35 + _jag[idx] * t.unit() * 0.035

func _band(t: PackTransition, l: int) -> void:
	var lead := t.cover()
	var trail := t.reveal()
	if lead <= 0.0: return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in 17:
		var fy := i / 16.0
		right.append(Vector2(_edge(t, lead, fy, l, 0), fy * t.size.y))
		left.append(Vector2(_edge(t, trail, fy, l, 1) if trail > 0.0 else -t.size.x * 0.5 - t.size.y, fy * t.size.y))
	if l < 2:
		var pts := PackedVector2Array()
		for q in left: pts.append(q)
		for i in range(16, -1, -1): pts.append(right[i])
		t.poly_safe(pts, DUST[l])
	else:     # the body: a vertical sunset gradient, one quad per step with per-vertex colour
		for i in 16:
			var c0 := _sky(i / 16.0)
			var c1 := _sky((i + 1) / 16.0)
			t.draw_polygon(PackedVector2Array([left[i], left[i + 1], right[i + 1], right[i]]), PackedColorArray([c0, c1, c1, c0]))

func _glow_at(t: PackTransition, c: Vector2, r: float, col: Color) -> void:
	t.draw_texture_rect(_glow, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)

func draw(t: PackTransition) -> void:
	var E := PackTransition
	var w := t.size.x
	var h := t.size.y
	var u := t.unit()
	var p := t.p
	for l in 3: _band(t, l)
	# ---- once covered: sun, rays, hills, heat shimmer (one envelope, eased both ways)
	var sa := E.env(p, 0.36, 0.52, 0.52, 0.66)
	if sa > 0.003:
		var sc := Vector2(w * 0.5, h * 0.64)
		var sr := u * 0.2 * lerpf(0.85, 1.0, E.smooth(E.seg(p, 0.36, 0.6)))
		var rot := p * 0.9
		var rr := sqrt(w * w + h * h)
		for i in RAYS:
			var a0 := rot + i * TAU / RAYS
			var a1 := a0 + TAU / RAYS * 0.45
			t.poly(PackedVector2Array([sc, sc + Vector2(cos(a0), sin(a0)) * rr, sc + Vector2(cos(a1), sin(a1)) * rr]), Color(1.0, 0.85, 0.4, 0.12 * sa))
		_glow_at(t, sc, sr * 3.2, Color(1.0, 0.7, 0.25, 0.55 * sa))
		t.draw_circle(sc, sr, Color(SUN, sa), true)
		t.draw_circle(sc, sr * 0.8, Color("#fff0a8", sa), true)
		# rolling hills (a dark silhouette along the bottom)
		var hills := PackedVector2Array([Vector2(0, h)])
		for i in 33:
			var x := w * i / 32.0
			hills.append(Vector2(x, h * 0.84 + sin(x / w * 7.0 + 0.6) * h * 0.03 + sin(x / w * 17.0) * h * 0.012))
		hills.append(Vector2(w, h))
		t.poly(hills, Color(0.2, 0.07, 0.1, 0.85 * sa))
		# heat shimmer: faint wavy lines drifting over the lower half
		for k in 7:
			var pts := PackedVector2Array()
			var y0 := h * (0.52 + k * 0.055)
			for i in 41:
				var x2 := w * i / 40.0
				pts.append(Vector2(x2, y0 + sin(x2 * 0.025 + p * 14.0 + k * 1.7) * u * 0.009))
			t.draw_polyline(pts, Color(1.0, 0.95, 0.75, 0.13 * sa), 3.0, true)
	# ---- the boomerang: one smooth bezier crossing, spinning, its trail fading gradually
	var bk := E.smooth(E.seg(p, 0.04, 0.66))
	if bk > 0.0 and bk < 1.0:
		var fade := E.smooth(E.seg(bk, 0.0, 0.1)) * (1.0 - E.smooth(E.seg(bk, 0.9, 1.0)))
		for g in range(9, 0, -1):
			var gk := clampf(bk - g * 0.022, 0.0, 1.0)
			var ga := 0.45 * pow(1.0 - g / 10.0, 2.0) * fade
			t.draw_set_transform(_boom_pos(t, gk), p * 26.0 - g * 0.35, Vector2.ONE * u * 0.0024 * (1.0 - g * 0.025))
			_boomerang(t, Color(1.0, 0.93, 0.7, ga), true)
		t.draw_set_transform(_boom_pos(t, bk), p * 26.0, Vector2.ONE * u * 0.0026)
		_boomerang(t, Color(1, 1, 1, fade), false)
		t.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ---- dust puffs along the front, soft in and out
	for i in N_DUST:
		var age := (p - _db[i]) / 0.34
		if age <= 0.0 or age >= 1.0: continue
		var front := _edge(t, t.cover() if p < 0.5 else t.reveal(), _dy[i], 2 if p < 0.5 else 0, 0 if p < 0.5 else 1)
		var pos := Vector2(front + _dx[i] * w - age * u * 0.18, _dy[i] * h - age * u * 0.1)
		var r := u * 0.035 * _ds[i] * (0.6 + age)
		_glow_at(t, pos, r * 1.6, Color(0.92, 0.62, 0.34, 0.5 * sin(age * PI)))
	# ---- the name
	var na := E.env(p, 0.36, 0.52, 0.56, 0.7)
	t.banner(t.label, Vector2(w * 0.5, h * 0.4), w * 0.84, Color.WHITE, Color("#5a1d0a"), na, lerpf(0.94, 1.0, E.smooth(E.seg(p, 0.36, 0.55))), int(u * 0.2))

func _boom_pos(t: PackTransition, k: float) -> Vector2:
	var w := t.size.x
	var h := t.size.y
	var p0 := Vector2(-w * 0.12, h * 0.8)
	var p1 := Vector2(w * 0.25, h * 0.02)
	var p2 := Vector2(w * 0.75, h * 0.02)
	var p3 := Vector2(w * 1.12, h * 0.72)
	var m := 1.0 - k
	return p0 * m * m * m + p1 * 3.0 * m * m * k + p2 * 3.0 * m * k * k + p3 * k * k * k

# the boomerang around (0, 0): two bent arms, ~170 units across; `ghost` draws one flat colour
func _boomerang(t: PackTransition, tint: Color, ghost: bool) -> void:
	var wood := Color("#c9772f") if not ghost else tint
	var dark := Color("#7d3f14") if not ghost else tint
	if not ghost:
		wood.a = tint.a
		dark.a = tint.a
	var pts := PackedVector2Array([Vector2(-85, -45), Vector2(-70, -62), Vector2(-5, -22), Vector2(62, -62), Vector2(85, -45), Vector2(30, 28), Vector2(0, 40), Vector2(-30, 28)])
	t.poly(pts, dark)
	var inner := PackedVector2Array([Vector2(-78, -48), Vector2(-68, -57), Vector2(-5, -14), Vector2(60, -57), Vector2(78, -48), Vector2(28, 20), Vector2(0, 31), Vector2(-28, 20)])
	t.poly(inner, wood)
	if not ghost:
		for x in [-55.0, -30.0, 0.0, 30.0, 55.0]:
			t.draw_circle(Vector2(x * 0.86, -36.0 + absf(x) * 0.28 + (14.0 if x == 0.0 else 0.0)), 5.0, Color(0.98, 0.91, 0.75, tint.a), true)
