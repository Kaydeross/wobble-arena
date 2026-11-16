class_name PackLandingSet
extends Node3D
## The 3D set of a pack landing page (ui/pack_landing.gd shows it, ui/pack_landing_stage.gd renders it: ONE SubViewport per page).
## Like the title's Construction showcase (ui/showcase_stage.gd) it is a lit low-poly scene built in code from primitives
## (MeshInstance3D with Box / Cylinder / Sphere / Prism meshes and StandardMaterial3D), with the real dressed Wobbler standing in it
## and the pack's weapon turning beside it. Arena props come from the packs' own generators (KitchenProps, XmasProps, AustraliaProps:
## the box lists the arenas are built from), so a landing page looks like its arena.
##   "kitchen"    a tiled back wall, a stainless prep counter the Wobbler stands BEHIND, pots and utensils swinging on a rail, a stove
##                with glowing burners (emissive + a small flickering OmniLight), an exhaust hood, warm pendant lamps; the weapon turns
##                on a turntable on the counter
##   "xmas"       the Wobbler stands INSIDE a snow globe: a glass sphere (a small fresnel shader), a red base with a gold band and the
##                pack's name, a mini tree and gifts inside, snow falling inside the glass (shake() swirls it), fairy lights on the wall
##   "australia"  a desert suburb: red dirt, a warm sky, a big sun, a corrugated fence, low-poly houses, gum trees, a turning Hills
##                Hoist with washing and a kangaroo (idle bob, ear twitch; shake() makes it hop)
## The set is wide (the hero band is a panorama): the subject sits round the origin (what the stage frames into the band's stage slot),
## the rest of the scenery runs to +-SPAN m behind the band's texts.
## Budgets (tests/pack_landing_test.gd): at most MESH_CAP mesh instances for the whole stage, PARTICLE_CAP particles (0 on the lowest
## graphics tier), no per-frame allocation in animate(). Visual code only: its random numbers come from a local RandomNumberGenerator.

const KINDS: Array[String] = ["kitchen", "xmas", "australia"]
const MESH_CAP := 250
const PARTICLE_CAP := 100
const SPAN := 30.0                      ## the scenery reaches this far left and right of the subject (m, at the subject's depth)
const STILL_T := 2.2                    ## the moment a still picture shows (lowest tier)

const GLASS_SHADER := "shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;
uniform vec4 tint : source_color = vec4(0.78, 0.9, 1.0, 1.0);
void fragment() {
	vec3 n = normalize(NORMAL);
	float f = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 2.4);
	float h = smoothstep(0.90, 0.975, dot(n, normalize(vec3(-0.48, 0.58, 0.66))));
	float h2 = smoothstep(0.972, 0.992, dot(n, normalize(vec3(0.52, -0.42, 0.74)))) * 0.45;
	ALBEDO = mix(tint.rgb, vec3(1.0), clamp(f * 0.55 + h + h2, 0.0, 1.0));
	ALPHA = clamp(0.06 + f * 0.8 + h * 0.75 + h2, 0.0, 1.0);
}"

var kind := ""
var title := ""
var with_fx := true
# ---- what the stage needs to frame and light the set ----
var focus := Vector3(0, 1.5, 0)         ## the point shown in the middle of the band's stage slot
var view_h := 3.5                       ## metres of the scene the slot's height shows (its width shows 1.8 x this)
var pitch := deg_to_rad(6.0)            ## the camera looks this much down
var wob_pos := Vector3.ZERO
var wob_yaw := 0.4
var wob_scale := 1.0
var weapon_pos := Vector3(1, 1.6, 0)    ## the middle of the turning weapon
var weapon_h := 1.5                     ## its longest side (m)
var bg := Color.BLACK
var ambient := Color.WHITE
var ambient_e := 0.6
var key_col := Color.WHITE
var key_e := 1.2
var key_dir := Vector3(0.6, 1.2, 1.0)   ## where the key light stands
var rim_col := Color(1.0, 0.88, 0.7)
var rim_e := 0.6
var shadow := true                      ## the key light may cast the page's one cheap shadow (never on the lowest tier)
# ---- what the tests look at ----
var counter: Node3D                     ## kitchen: the prep counter
var counter_front_z := 0.0              ## its front face (towards the camera)
var counter_back_z := 0.0
var counter_top := 0.0
var globe: MeshInstance3D               ## xmas: the glass
var globe_center := Vector3.ZERO
var globe_radius := 0.0
var kangaroo: Node3D                    ## australia
var hoist_arms: Node3D
var particles: Array[CPUParticles3D] = []

var _rng := RandomNumberGenerator.new()
var _mats := {}
var _cyls := {}
var _ubox: BoxMesh
var _uball: SphereMesh
var _swing: Array[Node3D] = []          ## kitchen: things hanging on the rail; australia: the washing
var _flames: Array[Node3D] = []
var _lamp: OmniLight3D
var _twinkle: Array[StandardMaterial3D] = []
var _star: Node3D
var _snow: CPUParticles3D
var _sun: Node3D
var _far: Array = []                    ## [node, the point it is seen at (in the subject's plane), metres behind it]: see fit()
var _roo_bob: Node3D
var _roo_head: Node3D
var _roo_ears: Array[Node3D] = []
var _roo_tail: Node3D
var _kick := 0.0                        ## 1 right after shake(), back to 0 in about a second

static var _glass: Shader
static var _tex := {}

static func has(k: String) -> bool:
	return KINDS.has(k)

## The set for `k` (a kind of KINDS), built and ready to add to the stage. `pal`: the pack's landing palette (PackLanding.pal),
## `label`: the pack's name (the snow globe's base), `fx`: particles allowed.
static func make(k: String, pal: Dictionary, label: String, fx: bool) -> PackLandingSet:
	var s := PackLandingSet.new()
	s.name = "Set_" + k
	s.kind = k
	s.title = label
	s.with_fx = fx
	s._rng.seed = 20241 + k.hash() % 1000
	s._ubox = BoxMesh.new()
	s._uball = SphereMesh.new()
	s._uball.radius = 0.5
	s._uball.height = 1.0
	s._uball.radial_segments = 12
	s._uball.rings = 6
	match k:
		"kitchen": s._kitchen(pal)
		"xmas": s._xmas(pal)
		"australia": s._australia(pal)
	return s

func particle_total() -> int:
	var n := 0
	for p: CPUParticles3D in particles: n += p.amount
	return n

func set_emitting(on: bool) -> void:
	for p: CPUParticles3D in particles: p.emitting = on

## A tap on the stage: the snow swirls, the burners flare, the kangaroo hops.
func shake() -> void:
	_kick = 1.0

# ---------------------------------------------------------------- building blocks

func _f() -> float:
	return _rng.randf()

static func hexc(h: int) -> Color:
	return Color8((h >> 16) & 0xff, (h >> 8) & 0xff, h & 0xff)

## A cached material: `e` > 0 glows in its own colour, `unlit` ignores the lights (sky, sun).
func _m(col: Color, e := 0.0, unlit := false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [col.to_html(), e, unlit]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if col.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unlit: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if e > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = e
	_mats[key] = m
	return m

func _mi(p: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	p.add_child(mi)
	return mi

func _box(p: Node3D, sz: Vector3, pos: Vector3, col: Color, e := 0.0) -> MeshInstance3D:
	var mi := _mi(p, _ubox, _m(col, e), pos)
	mi.scale = sz
	return mi

func _ball(p: Node3D, sz: Vector3, pos: Vector3, col: Color, e := 0.0) -> MeshInstance3D:
	var mi := _mi(p, _uball, _m(col, e), pos)
	mi.scale = sz
	return mi

func _cyl_mesh(rt: float, rb: float, h: float, segs: int) -> CylinderMesh:
	var key := "%.3f|%.3f|%.3f|%d" % [rt, rb, h, segs]
	if _cyls.has(key): return _cyls[key]
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	_cyls[key] = c
	return c

## An upright cylinder / cone (rt = 0), its middle at `pos`.
func _cyl(p: Node3D, rt: float, rb: float, h: float, pos: Vector3, col: Color, segs := 12, e := 0.0) -> MeshInstance3D:
	return _mi(p, _cyl_mesh(rt, rb, h, segs), _m(col, e), pos)

## A tapered limb from `a` (radius ra) to `b` (radius rb).
func _limb(p: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, col: Color) -> MeshInstance3D:
	var d := b - a
	var l := maxf(d.length(), 0.001)
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var mi := _mi(p, _cyl_mesh(rb, ra, l, 8), _m(col), (a + b) * 0.5)
	mi.basis = Basis(x, y, x.cross(y))
	return mi

## An arena prop of the pack's generator (PackMapKit: boxes {x, z, w, d, h, y, color, glow, ei} in the prop's own frame) as boxes
## under one node at `pos`, turned `yaw` and scaled `s`.
func _prop(p: Node3D, prop: Dictionary, pos: Vector3, yaw := 0.0, s := 1.0) -> Node3D:
	var n := Node3D.new()
	n.name = "Prop_" + str(prop.get("kind", ""))
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3(s, s, s)
	p.add_child(n)
	for b: Dictionary in prop["boxes"]:
		var h := float(b["h"])
		var e := float(b.get("ei", PackMapKit.GLOW_EI)) if b.has("glow") else 0.0
		_box(n, Vector3(float(b["w"]), h, float(b["d"])), Vector3(float(b["x"]), float(b["y"]) + h * 0.5, float(b["z"])), hexc(int(b["color"])), e)
	return n

## A small repeating texture drawn once: "tiles" (light tiles, darker grout), "ridges" (corrugated iron), "planks".
static func pattern(k: String) -> ImageTexture:
	if _tex.has(k): return _tex[k]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := 1.0
			match k:
				"tiles": v = 0.72 if (x < 2 or y < 2) else (1.0 if (x + y) % 9 != 0 else 0.97)
				"ridges": v = 0.78 + 0.22 * sin(float(x) / float(n) * TAU * 4.0)
				"planks": v = 0.7 if x < 2 else (0.9 + 0.1 * float((x / 8) % 2))
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[k] = t
	return t

## A material that wears pattern `k` every `cell` metres, whatever the box (world triplanar).
func _pat(col: Color, k: String, cell: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.albedo_texture = pattern(k)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / cell, 1.0 / cell, 1.0 / cell)
	return m

## Soft particles (billboard dots): `ramp` four colours over the lifetime.
func _fx(p: Node3D, amount: int, life: float, pos: Vector3, ramp: Array, s0: float, s1: float, glow := false) -> CPUParticles3D:
	if not with_fx: return null
	var c := CPUParticles3D.new()
	c.name = "Fx%d" % particles.size()
	c.amount = amount
	c.lifetime = life
	c.preprocess = life
	c.position = pos
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	c.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PackLandingScene.dot_texture()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	if glow: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	c.material_override = m
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	g.colors = PackedColorArray(ramp)
	c.color_ramp = g
	c.scale_amount_min = s0
	c.scale_amount_max = s1
	p.add_child(c)
	particles.append(c)
	return c

## Many copies of one mesh in ONE draw (the fairy lights).
func _multi(p: Node3D, mesh: Mesh, mat: Material, xfs: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
	var n := MultiMeshInstance3D.new()
	n.multimesh = mm
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(n)
	return n

func _no_shadow(n: Node) -> void:
	for c: Node in n.find_children("*", "GeometryInstance3D", true, false): (c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is GeometryInstance3D: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## The round plate the weapon turns over.
func _turntable(p: Node3D, pos: Vector3, col: Color, rim: Color) -> void:
	_cyl(p, 0.5, 0.54, 0.07, pos + Vector3(0, 0.035, 0), col, 16)
	_cyl(p, 0.36, 0.36, 0.02, pos + Vector3(0, 0.08, 0), rim, 16)

# ---------------------------------------------------------------- kitchen

func _kitchen(pal: Dictionary) -> void:
	var KP := KitchenProps
	var glow: Color = pal.get("glow", Color("#ff7a1c"))
	focus = Vector3(0, 1.66, 0)
	view_h = 3.6
	pitch = deg_to_rad(7.0)
	wob_pos = Vector3(-1.4, 0, -0.95)
	wob_yaw = 0.35
	weapon_pos = Vector3(0.55, 1.86, 0.3)
	weapon_h = 1.3
	bg = Color("#15181d")
	ambient = Color(1.0, 0.86, 0.72)
	ambient_e = 0.42
	key_col = Color(1.0, 0.95, 0.86)
	key_e = 0.95
	key_dir = Vector3(-0.5, 1.4, 1.0)
	rim_col = Color(1.0, 0.55, 0.2)
	rim_e = 0.55
	var steel := hexc(KP.STEEL)
	var steel_l := hexc(KP.STEEL_L)
	var steel_d := hexc(KP.STEEL_D)
	var dark := hexc(KP.DARK)
	var rnd := Callable(self, "_f")
	# the room: a dark tiled floor, the white tiled wall, a dark upper wall with a steel shelf
	var floor_mi := _mi(self, _ubox, _pat(Color("#4a4f57"), "tiles", 1.0), Vector3(0, -0.1, 11.0))
	floor_mi.scale = Vector3(SPAN * 2.0 + 44.0, 0.2, 30.0)
	var wall := _mi(self, _ubox, _pat(hexc(KP.TILE), "tiles", 0.5), Vector3(0, 1.7, -2.8))
	wall.scale = Vector3(SPAN * 2.0 + 44.0, 3.6, 0.2)
	_box(self, Vector3(SPAN * 2.0 + 44.0, 12.0, 0.2), Vector3(0, 9.5, -2.78), Color("#262a31"))
	_box(self, Vector3(SPAN * 2.0 + 44.0, 0.09, 0.34), Vector3(0, 3.5, -2.56), steel)
	for n: Node in [floor_mi, wall]: _no_shadow(n)
	# the prep counter the Wobbler stands behind
	counter = Node3D.new()
	counter.name = "Counter"
	counter.position = Vector3(0, 0, 0.3)
	add_child(counter)
	counter_front_z = 0.3 + 0.6
	counter_back_z = 0.3 - 0.6
	counter_top = 1.02
	_box(counter, Vector3(6.9, 0.92, 1.2), Vector3(0, 0.46, 0), steel)
	_box(counter, Vector3(7.1, 0.1, 1.34), Vector3(0, 0.97, 0), steel_l)
	_box(counter, Vector3(6.94, 0.1, 1.16), Vector3(0, 0.05, 0), dark)
	for i in 4:
		var dx := (float(i) - 1.5) * 1.68
		_box(counter, Vector3(1.5, 0.56, 0.04), Vector3(dx, 0.52, 0.61), steel_d)
		_box(counter, Vector3(0.6, 0.05, 0.05), Vector3(dx, 0.7, 0.65), steel_l)
	_box(counter, Vector3(0.95, 0.05, 0.6), Vector3(-2.75, 1.045, 0.05), hexc(KP.WOOD))            # a board with produce
	_ball(counter, Vector3(0.24, 0.22, 0.24), Vector3(-2.95, 1.18, 0.1), hexc(KP.PRODUCE[2]))
	_ball(counter, Vector3(0.22, 0.2, 0.22), Vector3(-2.66, 1.17, -0.02), hexc(KP.PRODUCE[0]))
	_ball(counter, Vector3(0.2, 0.2, 0.2), Vector3(-2.5, 1.17, 0.2), hexc(KP.PRODUCE[1]))
	_cyl(counter, 0.26, 0.23, 0.3, Vector3(-0.35, 1.17, 0.2), hexc(KP.POTS[1]), 14)                # a pot
	_cyl(counter, 0.27, 0.27, 0.03, Vector3(-0.35, 1.335, 0.2), steel_l, 14)
	_ball(counter, Vector3(0.09, 0.07, 0.09), Vector3(-0.35, 1.37, 0.2), dark)
	_turntable(counter, Vector3(weapon_pos.x, 1.02, 0), dark, hexc(KP.FIRE))
	# more islands down the line (the arena's own prep islands)
	for k in 3:
		for s: float in [-1.0, 1.0]:
			_prop(self, KP.island(rnd, 5.2, 1.2), Vector3(s * (7.3 + 6.4 * float(k)), 0, 0.3))
	# along the wall: a sink behind the Wobbler, the stove under its hood, fridges, crates
	var wz := -2.15
	_prop(self, KP.sink(3.0), Vector3(-1.9, 0, wz))
	_prop(self, KP.wall_stove(), Vector3(2.45, 0, wz))
	_prop(self, KP.fridge(), Vector3(5.75, 0, wz - 0.1), -PI * 0.5, 0.9)
	_prop(self, KP.fridge(), Vector3(-5.2, 0, wz - 0.1), -PI * 0.5, 0.9)
	var run := [0, 1, 2, 3, 1, 0]
	for i in run.size():
		for s: float in [-1.0, 1.0]:
			var x := s * (9.6 + 4.7 * float(i))
			match int(run[(i + (1 if s > 0.0 else 0)) % run.size()]):
				0: _prop(self, KP.crates(rnd, 1), Vector3(x, 0, wz), 0.0, 0.8)
				1: _prop(self, KP.wall_stove(), Vector3(x, 0, wz))
				2: _prop(self, KP.sink(3.2), Vector3(x, 0, wz))
				3: _prop(self, KP.fridge(), Vector3(x, 0, wz - 0.1), -PI * 0.5, 0.9)
	# the exhaust hood over the stove
	var hx := 2.45
	_box(self, Vector3(4.0, 0.32, 1.35), Vector3(hx, 2.86, wz + 0.1), steel_l)
	_box(self, Vector3(3.7, 0.05, 1.1), Vector3(hx, 2.68, wz + 0.1), dark)
	_box(self, Vector3(2.7, 0.4, 1.0), Vector3(hx, 3.2, wz), steel)
	_box(self, Vector3(0.9, 9.0, 0.7), Vector3(hx, 7.9, wz - 0.1), steel_d)
	for s: float in [-1.0, 1.0]: _box(self, Vector3(0.5, 0.04, 0.2), Vector3(hx + s * 1.2, 2.66, wz + 0.45), Color(1.0, 0.86, 0.6), 2.2)
	# the burners: glowing rings with flame tongues, a stockpot on one of them
	for i in 2:
		var bx := hx - 1.15 + 1.15 * float(i)
		_cyl(self, 0.36, 0.36, 0.04, Vector3(bx, 1.03, wz), hexc(KP.FIRE), 14, 2.4)
		var fl := Node3D.new()
		fl.name = "Flames%d" % i
		fl.position = Vector3(bx, 1.05, wz)
		add_child(fl)
		for j in 6:
			var a := float(j) / 6.0 * TAU
			var c := _cyl(fl, 0.0, 0.11, 0.6, Vector3(cos(a) * 0.27, 0.3, sin(a) * 0.27), hexc(KP.FIRE_Y) if j % 2 == 0 else glow, 6, 3.0)
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.append(fl)
	_cyl(self, 0.36, 0.36, 0.04, Vector3(hx + 1.15, 1.03, wz), hexc(KP.FIRE), 14, 2.4)
	_cyl(self, 0.4, 0.36, 0.5, Vector3(hx + 1.15, 1.32, wz), hexc(KP.POTS[0]), 14)
	_cyl(self, 0.42, 0.42, 0.04, Vector3(hx + 1.15, 1.59, wz), steel_l, 14)
	_lamp = OmniLight3D.new()
	_lamp.name = "BurnerLight"
	_lamp.light_color = glow
	_lamp.light_energy = 2.2
	_lamp.omni_range = 5.5
	_lamp.position = Vector3(hx - 0.4, 1.7, wz + 0.7)
	add_child(_lamp)
	# the rail with pots and utensils
	var ry := 2.82
	var rz := -2.5
	_box(self, Vector3(5.0, 0.05, 0.05), Vector3(-2.1, ry, rz), steel_l)
	for s: float in [-1.0, 1.0]: _box(self, Vector3(0.06, 0.06, 0.2), Vector3(-2.1 + s * 2.4, ry, rz - 0.1), steel_d)
	var hang := [-4.2, -3.5, -2.85, -2.2, -0.55, 0.05]
	for i in hang.size():
		var pv := Node3D.new()
		pv.name = "Hang%d" % i
		pv.position = Vector3(float(hang[i]), ry, rz + 0.06)
		add_child(pv)
		_box(pv, Vector3(0.025, 0.16, 0.025), Vector3(0, -0.08, 0), steel_d)
		match i % 4:
			0:                                                          # a saucepan, its base to the room
				_box(pv, Vector3(0.05, 0.3, 0.03), Vector3(0, -0.3, 0), dark)
				var pan := _cyl(pv, 0.25, 0.22, 0.12, Vector3(0, -0.68, 0), hexc(KP.POTS[i % KP.POTS.size()]), 14)
				pan.rotation.x = PI * 0.5
			1:                                                          # a ladle
				_box(pv, Vector3(0.035, 0.52, 0.03), Vector3(0, -0.42, 0), steel_l)
				_ball(pv, Vector3(0.2, 0.16, 0.14), Vector3(0, -0.74, 0), steel_l)
			2:                                                          # a frying pan
				_box(pv, Vector3(0.05, 0.36, 0.03), Vector3(0, -0.34, 0), dark)
				var fp := _cyl(pv, 0.3, 0.27, 0.06, Vector3(0, -0.8, 0), dark, 14)
				fp.rotation.x = PI * 0.5
			3:                                                          # a spatula
				_box(pv, Vector3(0.035, 0.46, 0.03), Vector3(0, -0.39, 0), steel_l)
				_box(pv, Vector3(0.17, 0.24, 0.02), Vector3(0, -0.72, 0), steel_l)
		_swing.append(pv)
	# warm pendant lamps over the counters
	for i in 9:
		var lx := -2.9 + 6.2 * float(i - 4)
		_box(self, Vector3(0.03, 9.0, 0.03), Vector3(lx, 7.9, 0.3), dark)
		_cyl(self, 0.08, 0.34, 0.26, Vector3(lx, 3.3, 0.3), dark, 12)
		_ball(self, Vector3(0.2, 0.2, 0.2), Vector3(lx, 3.18, 0.3), Color(1.0, 0.86, 0.55), 3.0)
	var warm := OmniLight3D.new()
	warm.name = "Pendant"
	warm.light_color = Color(1.0, 0.82, 0.55)
	warm.light_energy = 0.7
	warm.omni_range = 7.5
	warm.position = Vector3(-1.4, 3.0, 0.9)
	add_child(warm)
	# steam off the stockpot, sparks off the burners
	var st := _fx(self, 12, 2.4, Vector3(hx + 1.15, 1.65, wz), [Color(1, 1, 1, 0), Color(1, 1, 1, 0.34), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)], 0.25, 0.5)
	if st != null:
		st.direction = Vector3.UP
		st.spread = 14.0
		st.gravity = Vector3(0, 0.12, 0)
		st.initial_velocity_min = 0.3
		st.initial_velocity_max = 0.55
		st.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		st.emission_sphere_radius = 0.2
	var em := _fx(self, 16, 1.6, Vector3(hx - 0.55, 1.3, wz), [Color(1, 0.7, 0.2, 0), Color(1, 0.72, 0.25, 1), Color(1, 0.4, 0.1, 0.8), Color(0.7, 0.15, 0.02, 0)], 0.04, 0.09, true)
	if em != null:
		em.direction = Vector3.UP
		em.spread = 30.0
		em.gravity = Vector3(0, 0.5, 0)
		em.initial_velocity_min = 0.5
		em.initial_velocity_max = 1.3
		em.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		em.emission_box_extents = Vector3(0.9, 0.05, 0.3)

# ---------------------------------------------------------------- xmas

func _cone_tree(p: Node3D, pos: Vector3, h: float, lit: bool) -> Node3D:
	var XP := XmasProps
	var n := Node3D.new()
	n.name = "Tree"
	n.position = pos
	p.add_child(n)
	_cyl(n, 0.09 * h, 0.1 * h, 0.2 * h, Vector3(0, 0.1 * h, 0), hexc(XP.WOOD_D), 8)
	var cols := [XP.GREEN_D, XP.GREEN, XP.GREEN_L]
	for i in 3:
		var r := (0.36 - 0.09 * float(i)) * h
		_cyl(n, 0.0, r, 0.42 * h, Vector3(0, (0.36 + 0.24 * float(i)) * h, 0), hexc(int(cols[i])), 9)
	var star := _ball(n, Vector3(0.11, 0.11, 0.11) * h, Vector3(0, 1.08 * h, 0), hexc(XP.GOLD), 2.2 if lit else 1.0)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if lit: _star = star
	return n

func _gift(p: Node3D, pos: Vector3, sz: Vector3, col: Color, rib: Color, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = "Gift"
	n.position = pos
	n.rotation.y = yaw
	p.add_child(n)
	_box(n, sz, Vector3(0, sz.y * 0.5, 0), col)
	_box(n, Vector3(sz.x * 0.18, sz.y * 1.02, sz.z * 1.02), Vector3(0, sz.y * 0.5, 0), rib)
	_box(n, Vector3(sz.x * 1.02, sz.y * 1.02, sz.z * 0.18), Vector3(0, sz.y * 0.5, 0), rib)
	_ball(n, Vector3(sz.x * 0.34, sz.x * 0.2, sz.z * 0.34), Vector3(0, sz.y + sz.x * 0.06, 0), rib)
	return n

func _xmas(pal: Dictionary) -> void:
	var XP := XmasProps
	var glow: Color = pal.get("glow", Color("#ffd86b"))
	focus = Vector3(0.1, 1.64, 0)
	view_h = 3.8
	pitch = deg_to_rad(5.0)
	globe_center = Vector3(-1.45, 1.7, 0.0)
	globe_radius = 1.5
	wob_pos = Vector3(globe_center.x - 0.12, 0.78, 0.05)
	wob_yaw = 0.3
	wob_scale = 0.74
	weapon_pos = Vector3(2.1, 1.98, 0.1)
	weapon_h = 1.45
	bg = Color("#0a1f17")
	ambient = Color(0.78, 0.87, 1.0)
	ambient_e = 0.62
	key_col = Color(1.0, 0.97, 0.92)
	key_e = 1.15
	key_dir = Vector3(-0.7, 1.3, 1.0)
	rim_col = glow
	rim_e = 0.5
	var rnd := Callable(self, "_f")
	var red := hexc(XP.RED)
	var gold := hexc(XP.GOLD)
	var snow := hexc(XP.SNOW)
	# the workshop: a snowy floor, a plank wall in deep green with a red skirting
	var floor_mi := _box(self, Vector3(SPAN * 2.0 + 44.0, 0.2, 30.0), Vector3(0, -0.1, 11.0), Color("#c4d6e6"))
	var wall := _mi(self, _ubox, _pat(Color("#1d5a3c"), "planks", 2.4), Vector3(0, 6.5, -3.5))
	wall.scale = Vector3(SPAN * 2.0 + 50.0, 13.0, 0.2)
	_box(self, Vector3(SPAN * 2.0 + 50.0, 0.7, 0.12), Vector3(0, 0.35, -3.36), red.darkened(0.25))
	_box(self, Vector3(SPAN * 2.0 + 50.0, 0.08, 0.16), Vector3(0, 0.74, -3.36), gold.darkened(0.1))
	for n: Node in [floor_mi, wall]: _no_shadow(n)
	# fairy lights on the wall: two swags of bulbs in four colours (eight draws), twinkling by colour group
	var bulb := SphereMesh.new()
	bulb.radius = 0.085
	bulb.height = 0.17
	bulb.radial_segments = 6
	bulb.rings = 3
	var cols := [Color("#ff4a4a"), Color("#ffd24a"), Color("#52d273"), Color("#58a8ff")]
	var groups: Array = []
	for i in 8:
		var one: Array[Transform3D] = []
		groups.append(one)
	var wire: Array[Transform3D] = []
	var half := SPAN + 22.0
	for row in 2:
		var seg := 4.0
		var y0 := 4.25 - 0.95 * float(row)
		var off := 2.0 * float(row)
		var n := int(half * 2.0 / 0.55)
		var prev := Vector3.ZERO
		for i in n:
			var x := -half + float(i) * 0.55
			var u := fposmod(x + off, seg) / seg
			var p := Vector3(x, y0 - sin(u * PI) * 0.62, -3.3)
			(groups[(i % 4) + 4 * (((i >> 2) + row) % 2)] as Array[Transform3D]).append(Transform3D(Basis(), p))
			if i > 0 and i % 2 == 0:
				var d := p - prev
				var l := d.length()
				var yv := d / l
				var xv := yv.cross(Vector3.BACK).normalized()
				wire.append(Transform3D(Basis(xv * 0.03, yv * l, Vector3.BACK * 0.03), (p + prev) * 0.5 + Vector3(0, 0.08, -0.03)))
			if i % 2 == 0: prev = p
	for i in 8:
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[i % 4]
		m.emission_enabled = true
		m.emission = cols[i % 4]
		m.emission_energy_multiplier = 2.0
		m.roughness = 1.0
		_twinkle.append(m)
		_multi(self, bulb, m, groups[i])
	_multi(self, _ubox, _m(Color("#0c2a1b")), wire)
	# the room behind the texts: the arena's giant tree, gift stacks, a workbench, shelves, the chimney, drifts and small firs
	_prop(self, XP.tree(rnd), Vector3(9.4, 0, -1.4), 0.0, 0.36)
	_prop(self, XP.chimney(), Vector3(-11.5, 0, -2.5), -PI * 0.5, 0.8)
	_prop(self, XP.bench(5.0), Vector3(-6.3, 0, -2.7))
	_prop(self, XP.shelf(3.2), Vector3(5.2, 0, -2.9))
	_prop(self, XP.shelf(3.2), Vector3(-17.0, 0, -2.9))
	_prop(self, XP.bench(5.0), Vector3(15.5, 0, -2.7))
	for i in 4:
		var s := -1.0 if i % 2 == 0 else 1.0
		_prop(self, XP.gifts(rnd, 2), Vector3(s * (13.0 + 7.5 * float(i >> 1)) + 1.5, 0, -0.9), 0.3 * float(i), 0.42)
		_prop(self, XP.drift(rnd), Vector3(s * (7.0 + 9.0 * float(i >> 1)), 0, -2.9), 0.0, 0.55)
	var firs := [-4.4, 4.6, -8.6, 12.6, -14.6, 19.0, -21.5, 24.5, -27.0]
	for i in firs.size(): _cone_tree(self, Vector3(float(firs[i]), 0, -1.7 - 0.5 * float(i % 2)), 2.3 + 0.5 * float(i % 3), false)
	# ---- the snow globe ----
	var g := Node3D.new()
	g.name = "Globe"
	g.position = Vector3(globe_center.x, 0, globe_center.z)
	add_child(g)
	_cyl(g, 1.42, 1.5, 0.2, Vector3(0, 0.1, 0), red.darkened(0.35), 24)
	_cyl(g, 1.2, 1.38, 0.5, Vector3(0, 0.45, 0), red, 24)
	_cyl(g, 1.39, 1.41, 0.1, Vector3(0, 0.27, 0), gold, 24)
	_cyl(g, 1.22, 1.22, 0.06, Vector3(0, 0.71, 0), gold, 24)
	_cyl(g, 1.1, 1.14, 0.08, Vector3(0, 0.74, 0), snow, 20)                                       # the snow inside
	_ball(g, Vector3(1.5, 0.3, 1.3), Vector3(0.25, 0.76, -0.25), Color.WHITE)
	_cone_tree(g, Vector3(0.66, 0.78, -0.32), 1.05, true)
	_gift(g, Vector3(0.55, 0.78, 0.42), Vector3(0.3, 0.24, 0.3), red, gold, 0.4)
	_gift(g, Vector3(-0.72, 0.78, 0.3), Vector3(0.26, 0.2, 0.26), hexc(XP.BLUE), Color.WHITE, -0.3)
	_gift(g, Vector3(0.82, 0.78, 0.2), Vector3(0.2, 0.16, 0.2), hexc(XP.GREEN), gold, 0.1)
	if title != "":                                                                               # the pack's name on the base
		var lab := Label3D.new()
		lab.name = "BaseName"
		lab.text = title
		lab.font = UiTheme.font(700)
		lab.font_size = 96
		lab.outline_size = 0
		lab.modulate = Color(1.0, 0.9, 0.6)
		lab.shaded = false
		lab.double_sided = false
		var tw := maxf(lab.font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x, 1.0)
		lab.pixel_size = minf(1.7 / tw, 0.3 / 110.0)
		lab.position = Vector3(0, 0.5, 1.31)
		lab.rotation.x = -0.34
		g.add_child(lab)
	if _glass == null:
		_glass = Shader.new()
		_glass.code = GLASS_SHADER
	var gm := ShaderMaterial.new()
	gm.shader = _glass
	gm.render_priority = 2
	var sm := SphereMesh.new()
	sm.radius = globe_radius
	sm.height = globe_radius * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	globe = _mi(self, sm, gm, globe_center)
	globe.name = "Glass"
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cosy := OmniLight3D.new()
	cosy.name = "Cosy"
	cosy.light_color = glow
	cosy.light_energy = 1.1
	cosy.omni_range = 6.0
	cosy.position = globe_center + Vector3(1.2, 0.9, 2.2)
	add_child(cosy)
	# the weapon turns on a big present
	_gift(self, Vector3(weapon_pos.x, 0, weapon_pos.z), Vector3(1.25, 1.0, 1.25), red, gold, 0.25)
	_turntable(self, Vector3(weapon_pos.x, 1.1, weapon_pos.z), hexc(XP.GREEN_D), gold)
	_gift(self, Vector3(0.75, 0, 0.75), Vector3(0.55, 0.42, 0.55), hexc(XP.GREEN), Color.WHITE, -0.5)
	_gift(self, Vector3(3.15, 0, -0.5), Vector3(0.7, 0.55, 0.7), hexc(XP.BLUE), gold, 0.6)
	# the snow inside the glass
	_snow = _fx(self, 44, 3.6, globe_center + Vector3(0, 0.3, 0), [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0)], 0.05, 0.1)
	if _snow != null:
		_snow.name = "Snow"
		_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_snow.emission_sphere_radius = 1.02
		_snow.direction = Vector3(0, -1, 0)
		_snow.spread = 40.0
		_snow.initial_velocity_min = 0.05
		_snow.initial_velocity_max = 0.2
		_snow.gravity = Vector3(0, -0.22, 0)
	# a little snow in the room too
	var room := _fx(self, 30, 6.0, Vector3(0, 6.0, 0.5), [Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)], 0.05, 0.12)
	if room != null:
		room.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		room.emission_box_extents = Vector3(16.0, 0.3, 1.6)
		room.direction = Vector3(0.1, -1, 0)
		room.spread = 12.0
		room.initial_velocity_min = 0.7
		room.initial_velocity_max = 1.2
		room.gravity = Vector3.ZERO

# ---------------------------------------------------------------- australia

func _house(p: Node3D, pos: Vector3, w: float, wall: Color, roof: Color) -> void:
	var n := Node3D.new()
	n.name = "House%d" % p.get_child_count()
	n.position = pos
	p.add_child(n)
	var h := 2.15
	var d := 4.0
	_box(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), wall)
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.7, 1.05, d + 0.6)
	_mi(n, pm, _pat(roof, "ridges", 1.6), Vector3(0, h + 0.52, 0))
	_box(n, Vector3(0.95, 1.8, 0.08), Vector3(-w * 0.2, 0.9, d * 0.5), roof.darkened(0.35))
	_box(n, Vector3(1.3, 0.6, 0.08), Vector3(w * 0.24, 1.72, d * 0.5), Color("#9fd0e6"))
	_box(n, Vector3(0.45, 0.8, 0.45), Vector3(w * 0.3, h + 0.85, -0.6), wall.darkened(0.2))
	_no_shadow(n)

func _gum(p: Node3D, pos: Vector3, h: float) -> void:
	var n := Node3D.new()
	n.name = "Gum%d" % p.get_child_count()
	n.position = pos
	p.add_child(n)
	var lean := (_f() - 0.5) * 0.5
	_limb(n, Vector3.ZERO, Vector3(lean, h * 0.72, 0), 0.19, 0.11, Color("#e3d9c6"))
	_limb(n, Vector3(lean * 0.6, h * 0.45, 0), Vector3(lean * 0.6 - 0.8, h * 0.74, 0.1), 0.09, 0.05, Color("#d8cdb8"))
	var gcols := [Color("#6f9a5f"), Color("#5f8a55"), Color("#86ad6c")]
	_ball(n, Vector3(2.4, 1.5, 2.0), Vector3(lean + 0.3, h * 0.86, 0), gcols[0])
	_ball(n, Vector3(1.8, 1.2, 1.6), Vector3(lean * 0.6 - 1.0, h * 0.8, 0.2), gcols[1])
	_ball(n, Vector3(1.6, 1.1, 1.5), Vector3(lean + 1.2, h * 0.98, -0.2), gcols[2])
	_no_shadow(n)

## A low-poly kangaroo, standing upright, looking along its own +x.
func _roo(p: Node3D, pos: Vector3, yaw: float) -> void:
	var fur := Color("#c07a3c")
	var furd := Color("#96592a")
	var cream := Color("#ecd2a8")
	var ink := Color("#22160e")
	kangaroo = Node3D.new()
	kangaroo.name = "Kangaroo"
	kangaroo.position = pos
	kangaroo.rotation.y = yaw
	p.add_child(kangaroo)
	# the legs and the tail stay on the ground, the body bobs over them
	for s: float in [-1.0, 1.0]:
		_box(kangaroo, Vector3(0.66, 0.1, 0.17), Vector3(0.2, 0.05, s * 0.3), furd)                       # the long feet
		_limb(kangaroo, Vector3(-0.06, 0.1, s * 0.3), Vector3(0.14, 0.5, s * 0.3), 0.07, 0.1, fur)
	_roo_tail = Node3D.new()
	_roo_tail.name = "Tail"
	_roo_tail.position = Vector3(-0.3, 0.62, 0)
	kangaroo.add_child(_roo_tail)
	_limb(_roo_tail, Vector3.ZERO, Vector3(-0.62, -0.4, 0), 0.19, 0.12, fur)
	_limb(_roo_tail, Vector3(-0.62, -0.4, 0), Vector3(-1.3, -0.55, 0), 0.12, 0.045, furd)
	_roo_bob = Node3D.new()
	_roo_bob.name = "Body"
	kangaroo.add_child(_roo_bob)
	for s: float in [-1.0, 1.0]:
		var th := _ball(_roo_bob, Vector3(0.62, 0.74, 0.26), Vector3(0.0, 0.66, s * 0.3), fur)           # the thighs
		th.rotation.z = -0.5
	var haunch := _ball(_roo_bob, Vector3(0.86, 1.0, 0.62), Vector3(-0.08, 0.8, 0), fur)
	haunch.rotation.z = -0.25
	var chest := _ball(_roo_bob, Vector3(0.6, 0.98, 0.5), Vector3(0.22, 1.3, 0), fur)
	chest.rotation.z = -0.38
	var belly := _ball(_roo_bob, Vector3(0.42, 0.9, 0.36), Vector3(0.34, 1.12, 0), cream)
	belly.rotation.z = -0.3
	for s: float in [-1.0, 1.0]:                                                                        # the little arms
		_limb(_roo_bob, Vector3(0.32, 1.42, s * 0.22), Vector3(0.6, 1.18, s * 0.2), 0.07, 0.05, fur)
		_limb(_roo_bob, Vector3(0.6, 1.18, s * 0.2), Vector3(0.72, 0.98, s * 0.17), 0.05, 0.04, furd)
	_roo_head = Node3D.new()
	_roo_head.name = "Head"
	_roo_head.position = Vector3(0.42, 1.66, 0)
	_roo_bob.add_child(_roo_head)
	_limb(_roo_head, Vector3(-0.08, -0.14, 0), Vector3(0.04, 0.2, 0), 0.15, 0.12, fur)                  # the neck
	_ball(_roo_head, Vector3(0.36, 0.33, 0.3), Vector3(0.1, 0.3, 0), fur)
	var snout := _ball(_roo_head, Vector3(0.36, 0.2, 0.2), Vector3(0.3, 0.23, 0), fur)
	snout.rotation.z = -0.2
	_ball(_roo_head, Vector3(0.2, 0.12, 0.16), Vector3(0.38, 0.17, 0), cream)
	_ball(_roo_head, Vector3(0.08, 0.07, 0.1), Vector3(0.48, 0.22, 0), ink)
	for s: float in [-1.0, 1.0]:
		_ball(_roo_head, Vector3(0.06, 0.07, 0.04), Vector3(0.2, 0.36, s * 0.14), ink)
		var ear := Node3D.new()
		ear.name = "Ear%d" % _roo_ears.size()
		ear.position = Vector3(0.02, 0.42, s * 0.1)
		ear.rotation.x = s * 0.3
		_roo_head.add_child(ear)
		_ball(ear, Vector3(0.1, 0.36, 0.15), Vector3(-0.02, 0.17, 0), fur)
		_ball(ear, Vector3(0.04, 0.26, 0.09), Vector3(0.02, 0.17, 0), cream)
		_roo_ears.append(ear)

func _australia(pal: Dictionary) -> void:
	var AP := AustraliaProps
	focus = Vector3(0.1, 1.5, 0)
	view_h = 3.5
	pitch = deg_to_rad(4.0)
	wob_pos = Vector3(-1.75, 0, 0.35)
	wob_yaw = 0.42
	weapon_pos = Vector3(0.3, 1.62, 0.25)
	weapon_h = 1.5
	var sky_top: Color = pal.get("top", Color("#c4481c"))
	var sky_low: Color = pal.get("bottom", Color("#f0a53c"))
	bg = sky_top
	ambient = Color(1.0, 0.88, 0.74)
	ambient_e = 0.66
	key_col = Color(1.0, 0.94, 0.8)
	key_e = 1.3
	key_dir = Vector3(-0.9, 1.5, 1.0)
	rim_col = Color(1.0, 0.6, 0.25)
	rim_e = 0.75
	var rnd := Callable(self, "_f")
	var dirt := Color("#b9532a")
	# red dirt, with darker patches and a few rocks
	var ground := _box(self, Vector3(SPAN * 2.0 + 90.0, 0.2, 70.0), Vector3(0, -0.1, -9.0), dirt)
	_no_shadow(ground)
	for i in 6:
		var px := -SPAN + 11.0 * float(i) + _f() * 3.0
		_no_shadow(_box(self, Vector3(3.0 + _f() * 3.0, 0.02, 0.8 + _f()), Vector3(px, 0.01, -1.6 - _f() * 1.6), dirt.darkened(0.14)))
	for i in 4:
		var rx := -SPAN * 0.8 + 14.5 * float(i) + _f() * 2.0
		if absf(rx) < 3.6: rx += 7.0
		_ball(self, Vector3(0.7 + _f() * 0.5, 0.4 + _f() * 0.2, 0.6), Vector3(rx, 0.12, -0.8 - _f() * 1.8), Color("#8f4a2c"))
	# the warm sky (one unlit sheet with a gradient), the sun and a far mesa
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gr.colors = PackedColorArray([sky_top.darkened(0.12), sky_top.lerp(sky_low, 0.55), sky_low.lightened(0.35)])
	var gt := GradientTexture2D.new()
	gt.gradient = gr
	gt.width = 4
	gt.height = 64
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var skm := StandardMaterial3D.new()
	skm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skm.albedo_texture = gt
	var qm := QuadMesh.new()
	qm.size = Vector2(420.0, 46.0)
	var sky := _mi(self, qm, skm, Vector3(0, 21.0, -40.0))
	sky.name = "Sky"
	_no_shadow(sky)
	_sun = Node3D.new()
	_sun.name = "SunDisc"
	add_child(_sun)
	var sun_at := Vector3(focus.x + 2.25, 2.5, 0)                                                  # low behind the kangaroo
	var sd := _mi(_sun, _cyl_mesh(0.92, 0.92, 0.01, 32), _m(Color("#fff3c2"), 0.0, true), Vector3.ZERO)
	sd.rotation.x = PI * 0.5
	var halo := _mi(_sun, _cyl_mesh(1.5, 1.5, 0.01, 32), _m(Color(1.0, 0.92, 0.6, 0.3), 0.0, true), Vector3(0, 0, -0.02))
	halo.rotation.x = PI * 0.5
	_no_shadow(_sun)
	_far.append([_sun, sun_at, 36.0])
	var mesa := Node3D.new()
	mesa.name = "Mesa"
	add_child(mesa)
	_ball(mesa, Vector3(7.0, 2.4, 1.0), Vector3.ZERO, Color("#a3411f"))
	_ball(mesa, Vector3(4.0, 1.6, 1.0), Vector3(4.2, -0.3, 0.1), Color("#b04a24"))
	_no_shadow(mesa)
	_far.append([mesa, Vector3(focus.x - 8.5, 1.9, 0), 30.0])
	# houses behind the fence, gum trees between them
	var walls := [Color("#efe2c4"), Color("#cfe6dc"), Color("#f2cdb4"), Color("#dfe7f0")]
	var roofs := [Color("#a8452f"), Color("#7f98a8"), Color("#8f5a43"), Color("#5f7f8f")]
	for i in 8:
		var hxp := -SPAN - 2.0 + 9.2 * float(i) + (_f() - 0.5) * 1.5
		if absf(hxp * 0.55 - sun_at.x) < 2.6: hxp -= 5.0                                           # the sun keeps its gap in the street
		_house(self, Vector3(hxp, 0, -10.5 - 1.5 * float(i % 2)), 4.6 + _f() * 1.4, walls[i % 4], roofs[(i + 1) % 4])
	var gums := [-4.3, 8.6, -9.5, 13.5, -17.0, 20.5, -25.5]
	for i in gums.size(): _gum(self, Vector3(float(gums[i]), 0, -6.6 - 1.2 * float(i % 2)), 3.6 + 0.6 * float(i % 3))
	# the corrugated-iron fence (the arena's sheet colours)
	var rng := SiteMap.Rng.new(7)
	var fcols: Array = AP.fence_cols(rng)
	var fw := 3.4
	var nf := int((SPAN * 2.0 + 24.0) / fw)
	var mats := {}
	for i in nf:
		var c := hexc(int(fcols[i % fcols.size()]))
		if not mats.has(c): mats[c] = _pat(c, "ridges", 0.9)
		var sheet := _mi(self, _ubox, mats[c], Vector3(-float(nf) * fw * 0.5 + (float(i) + 0.5) * fw, 0.95, -4.6))
		sheet.scale = Vector3(fw - 0.04, 1.9, 0.08)
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(self, Vector3(float(nf) * fw, 0.1, 0.14), Vector3(0, 1.93, -4.6), hexc(AP.POST))
	# backyard things down the line (the arena's own props, smaller)
	_prop(self, AP.shed(), Vector3(8.4, 0, -3.2), -PI * 0.5, 0.85)
	_prop(self, AP.picnic(rnd), Vector3(-7.4, 0, -2.2), 0.3, 0.8)
	_prop(self, AP.bin(rnd), Vector3(5.0, 0, -3.6))
	_prop(self, AP.bin(rnd), Vector3(-11.6, 0, -3.6))
	_prop(self, AP.esky_stack(rnd), Vector3(13.4, 0, -2.4), 0.2, 0.55)
	_prop(self, AP.kettle(), Vector3(-14.6, 0, -2.0))
	_prop(self, AP.stumps(), Vector3(-4.6, 0, -1.2), 0.5)
	_prop(self, AP.garden_bed(rnd), Vector3(18.6, 0, -3.4), 0.0, 0.8)
	# the Hills Hoist behind the Wobbler: the arena's pole, arms that turn, washing on the lines
	var hp := Vector3(-0.35, 0, -2.7)
	_prop(self, AP.hoist(0.5, 0.0), hp, 0.0, 0.72)
	hoist_arms = Node3D.new()
	hoist_arms.name = "HoistArms"
	hoist_arms.position = hp + Vector3(0, 2.8, 0)
	add_child(hoist_arms)
	var steel := hexc(AP.STEEL)
	var wash := [Color("#e5483f"), Color("#f4f1ea"), Color("#3a8fd6"), Color("#f3c53a"), Color("#4fb36a"), Color("#f4f1ea"), Color("#e86fa5"), Color("#f4f1ea")]
	var R := 2.0
	for i in 4:
		var a := float(i) * PI * 0.5
		var dirv := Vector3(cos(a), 0, sin(a))
		_limb(hoist_arms, Vector3.ZERO, dirv * R + Vector3(0, 0.22, 0), 0.04, 0.03, steel)
		var nxt := Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5))
		for k in 2:
			var u := 0.62 + 0.36 * float(k)
			var pa := dirv * R * u + Vector3(0, 0.22 * u, 0)
			var pb := nxt * R * u + Vector3(0, 0.22 * u, 0)
			_limb(hoist_arms, pa, pb, 0.012, 0.012, hexc(AP.LINE))
			var pv := Node3D.new()
			pv.name = "Wash%d" % _swing.size()
			pv.position = (pa + pb) * 0.5
			pv.rotation.y = -(a + PI * 0.25) + PI * 0.5
			hoist_arms.add_child(pv)
			var cloth := _box(pv, Vector3(0.5 + 0.2 * float(k), 0.5 + 0.12 * float((i + k) % 2), 0.02), Vector3(0, -0.3, 0), wash[(i * 2 + k) % wash.size()])
			cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_swing.append(pv)
	# the weapon turns over an esky
	var ex := weapon_pos.x
	_box(self, Vector3(1.05, 0.52, 0.62), Vector3(ex, 0.26, weapon_pos.z), hexc(AP.COOLERS[0]))
	_box(self, Vector3(1.1, 0.12, 0.67), Vector3(ex, 0.58, weapon_pos.z), hexc(AP.WHITE))
	_box(self, Vector3(0.2, 0.1, 0.03), Vector3(ex, 0.4, weapon_pos.z + 0.32), hexc(AP.STEEL_D))
	_turntable(self, Vector3(ex, 0.64, weapon_pos.z), hexc(AP.STEEL_D), hexc(AP.TRAMP_FRAME))
	# the kangaroo, at the side of the stage and clear of the texts
	_roo(self, Vector3(2.2, 0, -0.35), PI + 0.55)
	# dust in the low sun
	var dust := _fx(self, 18, 7.0, Vector3(0, 1.3, 0.6), [Color(1, 0.95, 0.75, 0), Color(1, 0.93, 0.7, 0.55), Color(1, 0.9, 0.6, 0.4), Color(1, 0.9, 0.6, 0)], 0.05, 0.11)
	if dust != null:
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust.emission_box_extents = Vector3(9.0, 1.2, 1.6)
		dust.direction = Vector3(1, 0.1, 0)
		dust.spread = 30.0
		dust.initial_velocity_min = 0.1
		dust.initial_velocity_max = 0.35
		dust.gravity = Vector3(0, 0.03, 0)

# ---------------------------------------------------------------- running

## The camera stands at `cam`, `d` m from the subject: things far behind it (the sun, the mesa) are built at the size they are
## seen at and put on the camera's ray through the point they belong at, so the band shows them the same at any distance.
func fit(cam: Vector3, d: float) -> void:
	for f: Array in _far:
		var n := f[0] as Node3D
		var k := (d + float(f[2])) / maxf(d, 0.1)
		n.position = cam + ((f[1] as Vector3) - cam) * k
		n.scale = Vector3(k, k, k)

## Poses the set at time `t` (seconds); `dt` = 0 for a still picture.
func animate(t: float, dt: float) -> void:
	_kick = maxf(0.0, _kick - dt * 0.9)
	match kind:
		"kitchen":
			for i in _swing.size(): _swing[i].rotation.z = sin(t * 1.5 + float(i) * 1.7) * (0.07 + 0.12 * _kick)
			for i in _flames.size():
				var fl := _flames[i]
				var k := 0.82 + 0.2 * sin(t * 11.0 + float(i) * 2.1) * sin(t * 4.3 + float(i)) + 0.12 * sin(t * 23.0 + float(i) * 5.0) + 0.9 * _kick
				fl.scale = Vector3(1.0 + 0.06 * sin(t * 9.0 + float(i)), k, 1.0 + 0.06 * cos(t * 7.0 + float(i)))
				fl.rotation.y = t * 0.8 + float(i)
			if _lamp != null: _lamp.light_energy = 2.0 + 0.5 * sin(t * 9.0) * sin(t * 3.7) + 0.25 * sin(t * 21.0) + 2.0 * _kick
		"xmas":
			for i in _twinkle.size(): _twinkle[i].emission_energy_multiplier = 1.5 + 1.3 * sin(t * (1.7 + 0.35 * float(i % 3)) + float(i) * 1.9)
			if _star != null: _star.scale = Vector3.ONE * 0.1155 * (1.0 + 0.12 * sin(t * 3.0))
			if _snow != null:
				var s := _kick * _kick
				_snow.gravity = Vector3(0, lerpf(-0.22, 0.75, s), 0)
				_snow.tangential_accel_min = 3.2 * s
				_snow.tangential_accel_max = 5.0 * s
				_snow.speed_scale = 1.0 + 1.8 * s
		"australia":
			if hoist_arms != null: hoist_arms.rotation.y = t * 0.45
			for i in _swing.size(): _swing[i].rotation.x = sin(t * 2.6 + float(i) * 1.3) * 0.22 + 0.12
			if _roo_bob != null:
				var hop := sin(clampf(1.0 - _kick, 0.0, 0.45) / 0.45 * PI) * 0.5 if _kick > 0.0 else 0.0
				kangaroo.position.y = hop
				_roo_bob.position.y = sin(t * 2.1) * 0.035
				_roo_bob.rotation.z = sin(t * 1.05) * 0.03
				_roo_head.rotation.y = sin(t * 0.6) * 0.3
				_roo_head.rotation.z = sin(t * 0.9 + 1.0) * 0.06
				_roo_tail.rotation.y = sin(t * 1.3) * 0.16
				for i in _roo_ears.size():
					# a quick flick every few seconds, one ear after the other
					var u := fposmod(t + 1.3 * float(i), 2.9)
					var flick := sin(u / 0.36 * TAU) * (1.0 - u / 0.36) if u < 0.36 else 0.0
					_roo_ears[i].rotation.z = flick * 0.5 + 0.9 * _kick * sin(t * 30.0)
					_roo_ears[i].rotation.x = (0.3 if i == 1 else -0.3) + flick * 0.25 * (1.0 if i == 1 else -1.0)
