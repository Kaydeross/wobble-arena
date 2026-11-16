extends RefCounted
## On Fire (kitchen): a KITCHEN IGNITION. The edges of the screen darken like a stove-top at night; a burner ring fades up in the
## middle and its gas jets light one after another in blue; the ring turns orange and a rolling flame spreads from it over the
## whole screen (shaders/pack_flame_wipe.gdshader: heat haze just ahead of the front, blue gas to orange to red). When the screen
## is covered a frying pan eases in over the glow with oil bubbles sizzling and steam rising and the pack's name. The reveal is
## steam and smoke: the fire cools and dissolves with a soft edge (no hard flame edges). Everything eases in and out on
## overlapping envelopes; 54 particles (20 gas jets, 22 embers, 12 steam puffs), one fullscreen shader.

const SHADER := preload("res://shaders/pack_flame_wipe.gdshader")
const N_JETS := 20
const N_EMBERS := 22
const N_STEAM := 12

var cues := [[0.02, "flame", 0.55], [0.36, "flame", 0.5]]
var _rect: ColorRect
var _over: Control
var _mat: ShaderMaterial
var _t: PackTransition
var _glow: GradientTexture2D
var _vign: GradientTexture2D
var _ex := PackedFloat32Array()
var _eb := PackedFloat32Array()
var _ev := PackedFloat32Array()
var _es := PackedFloat32Array()
var _ep := PackedFloat32Array()
var _sx := PackedFloat32Array()
var _sb := PackedFloat32Array()

func _grad(cols: PackedColorArray, offs: PackedFloat32Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	var tx := GradientTexture2D.new()
	tx.gradient = g
	tx.fill = GradientTexture2D.FILL_RADIAL
	tx.fill_from = Vector2(0.5, 0.5)
	tx.fill_to = Vector2(1.0, 0.5)
	tx.width = 128
	tx.height = 128
	return tx

func setup(t: PackTransition) -> void:
	_t = t
	_glow = _grad(PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)]), PackedFloat32Array([0.0, 0.45, 1.0]))
	_vign = _grad(PackedColorArray([Color(0.05, 0.02, 0.02, 0), Color(0.05, 0.02, 0.02, 0.0), Color(0.05, 0.02, 0.02, 0.92)]), PackedFloat32Array([0.0, 0.5, 1.0]))
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = "Flames"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	t.add_child(_rect)
	_over = Control.new()
	_over.name = "Over"
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over)
	t.add_child(_over)
	for i in N_EMBERS:
		_ex.append(t.rng.randf_range(-0.45, 0.45))
		_eb.append(t.rng.randf_range(0.08, 0.7))
		_ev.append(t.rng.randf_range(0.5, 1.0))
		_es.append(t.rng.randf_range(0.6, 1.2))
		_ep.append(t.rng.randf() * TAU)
	for i in N_STEAM:
		_sx.append(t.rng.randf_range(-1.0, 1.0))
		_sb.append(t.rng.randf_range(0.36, 0.62))

func tick(t: PackTransition) -> void:
	if _mat == null: return
	_mat.set_shader_parameter("cover", PackTransition.smooth(PackTransition.seg(t.p, 0.12, 0.5)))
	_mat.set_shader_parameter("reveal", PackTransition.smooth(PackTransition.seg(t.p, 0.5, 1.0)))
	_mat.set_shader_parameter("blue", 1.0 - PackTransition.smooth(PackTransition.seg(t.p, 0.1, 0.36)))
	_mat.set_shader_parameter("ftime", t.p * 5.0)
	_mat.set_shader_parameter("aspect", t.size.x / maxf(1.0, t.size.y))
	_over.queue_redraw()

func draw(_t: PackTransition) -> void:
	pass

func _poly(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() >= 3 and c.a > 0.003: _over.draw_colored_polygon(pts, c)

func _draw_over() -> void:
	var t := _t
	if t == null or t.finished: return
	var E := PackTransition
	var w := t.size.x
	var h := t.size.y
	var u := t.unit()
	var c := t.size * 0.5
	var p := t.p
	# the stove-top veil: the edges of the screen darken first (anticipation), then lift as the steam clears
	var va := E.env(p, 0.0, 0.22, 0.55, 0.85)
	if va > 0.003:
		var s := lerpf(2.2, 1.25, E.smooth(E.seg(p, 0.0, 0.25)))
		_over.draw_texture_rect(_vign, Rect2(c - t.size * s * 0.5, t.size * s), false, Color(1, 1, 1, va))
	# ember glow over the whole middle while the fire burns
	var ga := E.env(p, 0.12, 0.42, 0.55, 0.85)
	if ga > 0.003:
		var gr := u * 0.9
		_over.draw_texture_rect(_glow, Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1.0, 0.45, 0.1, 0.55 * ga))
	# the burner: dark disc, grate bars and 20 gas jets that light one after another, blue then orange
	var ba := E.env(p, 0.0, 0.1, 0.4, 0.58)
	var rr := u * 0.17
	if ba > 0.003:
		_over.draw_circle(c, rr * 1.35, Color(0.03, 0.03, 0.04, 0.7 * ba), true)
		_over.draw_arc(c, rr * 1.2, 0.0, TAU, 40, Color(0.35, 0.36, 0.4, ba), 5.0, true)
		_over.draw_arc(c, rr * 0.55, 0.0, TAU, 28, Color(0.28, 0.29, 0.33, ba), 4.0, true)
		for k in 4:
			var a := k * PI / 4.0 + 0.4
			var d := Vector2(cos(a), sin(a)) * rr * 1.3
			_over.draw_line(c - d, c + d, Color(0.25, 0.26, 0.3, ba), 5.0, true)
		var warm := E.smooth(E.seg(p, 0.14, 0.36))
		for i in N_JETS:
			var ign := E.smooth(E.seg(p, 0.02 + 0.14 * i / float(N_JETS), 0.02 + 0.14 * i / float(N_JETS) + 0.08))
			if ign <= 0.003: continue
			var ang := i * TAU / float(N_JETS)
			var dir := Vector2(cos(ang), sin(ang))
			var nrm := Vector2(-dir.y, dir.x)
			var base := c + dir * rr
			var hgt := ign * (u * 0.035 + u * 0.012 * sin(p * 50.0 + i * 2.1)) * (1.0 + warm * 0.9)
			var col_b := Color(0.35, 0.62, 1.0).lerp(Color(1.0, 0.55, 0.12), warm)
			var col_t := Color(0.85, 0.95, 1.0).lerp(Color(1.0, 0.88, 0.4), warm)
			_poly(PackedVector2Array([base + nrm * u * 0.011, base + dir * hgt, base - nrm * u * 0.011]), Color(col_b, ba * ign))
			_poly(PackedVector2Array([base + nrm * u * 0.005, base + dir * hgt * 0.62, base - nrm * u * 0.005]), Color(col_t, ba * ign))
			_over.draw_texture_rect(_glow, Rect2(base - Vector2(u * 0.04, u * 0.04), Vector2(u * 0.08, u * 0.08)), false, Color(col_b, 0.5 * ba * ign))
	# embers lift off, easing in and out
	for i in N_EMBERS:
		var age := (p - _eb[i]) / 0.32
		if age <= 0.0 or age >= 1.0: continue
		var a2 := sin(age * PI)
		var pos := c + Vector2(_ex[i] * w, u * 0.08 - age * _ev[i] * h * 0.55) + Vector2(sin(_ep[i] + age * 4.0) * u * 0.03, 0)
		var col := Color(1.0, 0.8, 0.3).lerp(Color(1.0, 0.3, 0.05), age)
		var r := u * 0.009 * _es[i]
		_over.draw_texture_rect(_glow, Rect2(pos - Vector2(r * 3.0, r * 3.0), Vector2(r, r) * 6.0), false, Color(col, 0.35 * a2))
		_over.draw_circle(pos, r, Color(col, 0.9 * a2), true)
	# the pan eases in once the screen is covered: sizzling oil, steam and the pack's name
	var pa := E.env(p, 0.3, 0.52, 0.72, 0.9)
	if pa > 0.003:
		var pc := c + Vector2(0, -u * 0.03)
		var s2 := u * 0.0019 * lerpf(0.9, 1.0, E.smooth(E.seg(p, 0.3, 0.6)))
		_over.draw_set_transform(pc, lerpf(-0.12, 0.0, E.smooth(E.seg(p, 0.3, 0.6))), Vector2(s2, s2))
		_pan(pa, p)
		_over.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in N_STEAM:
			var age2 := (p - _sb[i]) / 0.4
			if age2 <= 0.0 or age2 >= 1.0: continue
			var sp := pc + Vector2(_sx[i] * u * 0.16, -u * 0.08 - age2 * u * 0.4)
			var sr := u * (0.05 + 0.08 * age2)
			_over.draw_texture_rect(_glow, Rect2(sp - Vector2(sr, sr), Vector2(sr, sr) * 2.0), false, Color(0.92, 0.92, 0.95, 0.3 * sin(age2 * PI) * pa))
		var na := E.env(p, 0.34, 0.5, 0.64, 0.8)
		t.banner_on(_over, t.label, pc + Vector2(0, u * 0.3), w * 0.8, Color("#ffd23d"), Color("#7a1b08"), na, 1.0, int(u * 0.12))

# the pan around (0, 0), 100-unit radius, at alpha `a`; the oil bubbles breathe with `p`
func _pan(a: float, p: float) -> void:
	var dark := Color(0.15, 0.15, 0.17, a)
	var mid := Color(0.24, 0.24, 0.28, a)
	var rim := Color(0.94, 0.45, 0.23, a)
	_poly(PackedVector2Array([Vector2(60, -14), Vector2(205, -26), Vector2(212, 8), Vector2(60, 24)]), Color(0.11, 0.11, 0.13, a))
	_poly(PackedVector2Array([Vector2(64, -10), Vector2(200, -20), Vector2(204, -6), Vector2(64, 2)]), mid)
	_over.draw_circle(Vector2(190, -10), 6.0, Color(0.72, 0.74, 0.77, a), true)
	_over.draw_circle(Vector2(0, 5), 104.0, Color(0, 0, 0, 0.35 * a), true)
	_over.draw_circle(Vector2.ZERO, 100.0, rim, true)
	_over.draw_circle(Vector2.ZERO, 92.0, dark, true)
	_over.draw_circle(Vector2.ZERO, 74.0, mid, true)
	_over.draw_circle(Vector2.ZERO, 60.0, Color(0.18, 0.18, 0.22, a), true)
	_over.draw_arc(Vector2.ZERO, 82.0, deg_to_rad(200.0), deg_to_rad(260.0), 12, Color(1, 1, 1, 0.3 * a), 7.0, true)
	_over.draw_circle(Vector2(-4, 4), 34.0, Color(0.96, 0.95, 0.9, a), true)
	_over.draw_circle(Vector2(-6, 2), 15.0, Color(1.0, 0.76, 0.1, a), true)
	for i in 6:    # oil bubbles around the egg, each swelling and settling out of step
		var an := i * TAU / 6.0 + 0.5
		var br := 5.0 + 4.0 * (0.5 + 0.5 * sin(p * 22.0 + i * 1.9))
		_over.draw_circle(Vector2(cos(an), sin(an)) * 52.0, br, Color(1.0, 0.8, 0.4, 0.55 * a), true)
