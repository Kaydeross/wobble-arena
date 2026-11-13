class_name Trails
extends MeshInstance3D
## Ribbon trails, PRESENTATION ONLY (docs/GRAPHICS.md "Effects"): melee swing trails (a blade-wide ribbon from the
## grip to the weapon tip along the swing arc, read from the fighter state's shoulder point and swing target, for the
## swing, in the weapon's colour) and projectile trails (arrows, rockets, shuriken, typhoon blades, boomerangs, knives,
## tridents: a camera-facing ribbon behind the flying thing). All ribbons are rebuilt into ONE ImmediateMesh per
## frame (one draw call), fading by age; a hard cap on live ribbons and on samples per ribbon per effects level
## (LOW: melee only, 4 ribbons; MID 12; HIGH 24). Ribbon objects are pooled and reused.

const RIBBONS := [4, 12, 24]
const SAMPLES := [8, 12, 18]
const MELEE_LIFE := 0.2              ## s a melee sample stays
const PROJ_LIFE := {"rocket": 0.4, "arrow": 0.22, "knife": 0.16, "shuriken": 0.2, "typhoon": 0.24, "boomerang": 0.26, "trident": 0.22}
const PROJ_COL := {"rocket": Color(1, 0.72, 0.35, 0.7), "arrow": Color(1, 1, 1, 0.55), "knife": Color(0.9, 0.95, 1, 0.5),
	"shuriken": Color(0.8, 0.95, 1, 0.55), "typhoon": Color(0.5, 0.92, 1, 0.65), "boomerang": Color(1, 0.85, 0.45, 0.6),
	"trident": Color(1, 0.86, 0.35, 0.55)}
const PROJ_W := {"rocket": 0.16, "arrow": 0.05, "knife": 0.06, "shuriken": 0.12, "typhoon": 0.16, "boomerang": 0.16, "trident": 0.07}
## weapon length from the grip, per melee key (the visible tip, wobbler units x class size)
const REACH := {"katana": 1.3, "trident": 1.6, "bat": 1.05, "mallet": 1.0, "hammer": 0.95, "wirewhip": 1.4, "typhoon": 1.2, "spatula": 0.85}

var lv := 2
var im := ImmediateMesh.new()
var live := {}                      ## source key (FighterState / projectile object) -> Ribbon
var _free: Array = []               ## pooled Ribbon objects
var created := 0                    ## Ribbon objects ever made (tests: stays <= cap)
var dropped := 0                    ## new trails refused at the cap (tests)
var _mat: StandardMaterial3D

func _init(p_level := -1) -> void:
	name = "Trails"
	lv = p_level if p_level >= 0 else FxSystem.level()
	mesh = im
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1000, -300, -1000), Vector3(2000, 900, 2000))

func cap() -> int:
	return RIBBONS[lv]

func clear() -> void:
	for r: Ribbon in live.values(): _free.append(r)
	live.clear()
	im.clear_surfaces()

func _ribbon(key: Object, col: Color, life: float) -> Ribbon:
	var r: Ribbon = live.get(key)
	if r != null:
		r.alive = true
		return r
	if live.size() >= RIBBONS[lv]:
		dropped += 1
		return null
	if _free.is_empty():
		r = Ribbon.new(SAMPLES[lv]); created += 1
	else:
		r = _free.pop_back(); r.reset()
	r.col = col; r.life = life; r.alive = true
	live[key] = r
	return r

## Per frame: sample the sources (fighters mid-swing, projectiles in flight), age the samples, rebuild the mesh.
## `frozen` (hitstop) holds every ribbon as it is.
func update(dt: float, world: Node, cam_pos: Vector3, frozen := false) -> void:
	if frozen or dt <= 0.0:
		return
	for r: Ribbon in live.values(): r.alive = false
	var sim: MatchSim = world.sim
	for f: FighterState in world.views:
		if f.left or f.dead or f.swing < 0.0 or f.swing > 1.05: continue
		var w := sim.combat.wdata(f.weapon) if f.weapon != "" else {}
		var typ := str(w.get("type", "melee"))
		if typ != "melee" and typ != "typhoon": continue
		var key := f.weapon if f.weapon != "" else "spatula"
		var col := Color.hex((int(w.get("color", 0xffffff)) << 8) | 0xff).lerp(Color.WHITE, 0.15)
		col.a = 0.9 if f.slam else 0.8
		var r := _ribbon(f, col, MELEE_LIFE)
		if r == null: continue
		var size := 1.0
		var v: Fighter = world.views[f]
		if v and v.wobbler: size = float(v.wobbler.cls.get("size", 1.0)) * v.scale.x
		# the swing arc (the sim's swing target, aim_*) from the shoulder: the visible arm lags it on a spring, the
		# blade's sweep reads better along the target arc
		var sh := Vector3(f.shoulder_x, f.shoulder_y, f.shoulder_z)
		var d := Vector3(f.aim_x, f.aim_y, f.aim_z)
		if d.length_squared() < 1e-4: d = Vector3(f.arm_x, f.arm_y, f.arm_z)
		if d.length_squared() < 1e-4: continue
		d = d.normalized()
		r.push(sh + d * 0.75 * size, sh + d * (0.85 + float(REACH.get(key, 1.0))) * size)
	if lv >= 1 and world.get("proj_views") != null:
		var pv: ProjectileViews = world.proj_views
		for p: Object in pv._views:
			var kind := ProjectileViews._kind(p)
			if not PROJ_LIFE.has(kind): continue
			if p.get("stuck") != null and float(p.get("stuck")) > 0.0: continue
			var g: Node3D = pv._views[p]
			var r := _ribbon(p, PROJ_COL[kind], PROJ_LIFE[kind])
			if r == null: continue
			var pos := g.global_position
			var vel := Vector3(p.get("vx"), p.get("vy"), p.get("vz"))
			var side := vel.cross(cam_pos - pos)
			if side.length_squared() < 1e-6: side = Vector3.UP
			side = side.normalized() * PROJ_W[kind] * (1.9 if kind == "rocket" and g.scale.x > 1.5 else 1.0)
			r.push(pos + side, pos - side)
	var gone: Array = []
	for k: Object in live:
		var r: Ribbon = live[k]
		r.age(dt)
		if not r.alive and r.n == 0: gone.append(k)
	for k: Object in gone:
		_free.append(live[k]); live.erase(k)
	_build()

func _build() -> void:
	im.clear_surfaces()
	var any := false
	for r: Ribbon in live.values():
		if r.n >= 2: any = true; break
	if not any: return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	for r: Ribbon in live.values():
		for j in r.n - 1:                          # 0 = newest
			var k0 := 1.0 - r.t[j] / r.life
			var k1 := 1.0 - r.t[j + 1] / r.life
			var ca := Color(r.col.r, r.col.g, r.col.b, r.col.a * k0)
			var cb := Color(r.col.r, r.col.g, r.col.b, r.col.a * k1)
			var cb_tip := Color(cb.r, cb.g, cb.b, cb.a * 0.15)       # the inner edge fades: a soft blade arc
			var ca_tip := Color(ca.r, ca.g, ca.b, ca.a * 0.15)
			im.surface_set_color(ca_tip); im.surface_add_vertex(r.a[j])
			im.surface_set_color(ca); im.surface_add_vertex(r.b[j])
			im.surface_set_color(cb); im.surface_add_vertex(r.b[j + 1])
			im.surface_set_color(ca_tip); im.surface_add_vertex(r.a[j])
			im.surface_set_color(cb); im.surface_add_vertex(r.b[j + 1])
			im.surface_set_color(cb_tip); im.surface_add_vertex(r.a[j + 1])
	im.surface_end()

## Triangles drawn this frame (bench).
func tri_count() -> int:
	var t := 0
	for r: Ribbon in live.values(): t += maxi(0, r.n - 1) * 2
	return t


## One ribbon: a ring of (a, b) edge samples, newest first, each with its age.
class Ribbon extends RefCounted:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	var t := PackedFloat32Array()
	var n := 0
	var maxn := 0
	var col := Color.WHITE
	var life := 0.2
	var alive := false

	func _init(p_max: int) -> void:
		maxn = p_max
		a.resize(maxn); b.resize(maxn); t.resize(maxn)

	func reset() -> void:
		n = 0

	func push(pa: Vector3, pb: Vector3) -> void:
		var m := mini(n + 1, maxn)
		for i in range(m - 1, 0, -1):
			a[i] = a[i - 1]; b[i] = b[i - 1]; t[i] = t[i - 1]
		a[0] = pa; b[0] = pb; t[0] = 0.0
		n = m

	func age(dt: float) -> void:
		for i in n: t[i] += dt
		while n > 0 and t[n - 1] >= life: n -= 1
