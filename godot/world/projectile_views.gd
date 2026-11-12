class_name ProjectileViews
extends Node3D
## What flies and blows up: rockets, grenades, arrows, nets and knives in flight (Weapons.Shot / Weapons.Proj), nets
## lying on the ground (Weapons.TrapNet), explosions and flames. Pure presentation: World forwards the Combat events
## (on_event) and calls update() every rendered frame; the views read the positions straight from the logic objects.
## Kept cheap for iPhone: shared low-poly meshes and materials, effects fade by scale only (no per-effect
## materials), and a cap on live effects (flames are dropped first).

const MAX_FX := 150

var _views := {}                   ## Shot / Proj -> Node3D
var _nets := {}                    ## TrapNet -> Node3D
var _fx: Array = []                ## {node, life, max, vel, kind, s0, s1}
var _trail_t := 0.0
static var _mats := {}

static func mat(c: int, alpha := 1.0) -> StandardMaterial3D:
	var key := "%x:%s" % [c, alpha]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.hex(c << 8 | 0xff)
	m.albedo_color.a = alpha
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

static func _mi(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh; n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position = pos; n.rotation = rot; n.scale = scl
	parent.add_child(n)
	return n

## Drop everything (a new match).
func clear() -> void:
	for n: Node3D in _views.values(): n.queue_free()
	for n: Node3D in _nets.values(): n.queue_free()
	for x: Dictionary in _fx: (x["node"] as Node3D).queue_free()
	_views.clear(); _nets.clear(); _fx.clear()

func on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"projectile": _spawn(e["p"])
		"projectile_end":
			var p: Object = e["p"]
			if _views.has(p):
				var n: Node3D = _views[p]
				if p is Weapons.Shot and (p as Weapons.Shot).kind == "net": _burst(n.position, 0xf2ead2, 5, 3.0)
				n.queue_free(); _views.erase(p)
		"explode": explode(Vector3(e["x"], e["y"], e["z"]), float(e["gy"]), float(e["rad"]))
		"flame":
			flame(Vector3(e["x"], e["y"], e["z"]), Vector3(e.get("vx", 0.0), e.get("vy", 2.0), e.get("vz", 0.0)), float(e["life"]))
		"net_land": _net_land(e["net"])
		"net_end":
			var t: Object = e["net"]
			if _nets.has(t):
				_burst((_nets[t] as Node3D).position + Vector3(0, 0.3, 0), 0xf2ead2, 6, 3.0)
				(_nets[t] as Node3D).queue_free(); _nets.erase(t)
		"net_miss": _burst(Vector3(e["x"], e["y"], e["z"]), 0xf2ead2, 8, 4.0)

# ============================== things in flight ==============================

func _spawn(p: Object) -> void:
	if _views.has(p): return
	var g := Node3D.new()
	var kind := (p as Weapons.Shot).kind if p is Weapons.Shot else "knife"
	var key: String = p.get("key")
	match kind:
		"rocket":                   # glowing warhead with a flame tail (meteor: bigger and redder)
			var big: bool = (p as Weapons.Shot).w.get("big", false)
			_mi(g, LowPoly.ico(0.22, 0), mat(0xff4a1a if big else 0xff8a3d))
			_mi(g, LowPoly.cone(0.16, 0.5, 6), mat(0xffd27a, 0.8), Vector3(0, 0, 0.35), Vector3(PI / 2, 0, 0))
			if big: g.scale = Vector3.ONE * 1.9
		"grenade":
			var cl := key == "cluster"
			_mi(g, LowPoly.ico(0.2, 0), mat(0xe8a33a if cl else 0x4a5560))
			_mi(g, LowPoly.box(0.08, 0.08, 0.08), mat(0xff3b3b), Vector3(0, 0.2, 0))
			g.scale = Vector3.ONE * (0.9 if cl else 1.15)
		"arrow":                    # shaft along -Z (look_at points -Z down the flight)
			_mi(g, LowPoly.box(0.035, 0.035, 1.0), mat(0xd9a066))
			_mi(g, LowPoly.cone(0.06, 0.18, 4), mat(0xc7ccd6), Vector3(0, 0, -0.58), Vector3(-PI / 2, 0, 0))
			_mi(g, LowPoly.box(0.012, 0.12, 0.14), mat(0xe3566b), Vector3(0, 0, 0.42))
			_mi(g, LowPoly.box(0.12, 0.012, 0.14), mat(0xe3566b), Vector3(0, 0, 0.42))
		"net":
			_mi(g, LowPoly.ico(1.0, 1), mat(0xf2ead2, 0.35))
			_mi(g, LowPoly.torus(1.0, 0.05, 4, 16), mat(0xd8cfb4), Vector3.ZERO, Vector3(PI / 2, 0, 0))
			g.scale = Vector3.ONE * 0.3
		_:                          # knife (and other knife-like throws)
			_mi(g, LowPoly.box(0.06, 0.02, 0.42), mat(0xeef3f7), Vector3(0, 0, -0.2))
			_mi(g, LowPoly.box(0.05, 0.05, 0.22), mat(0x6a4a2a), Vector3(0, 0, 0.1))
	add_child(g)
	g.position = Vector3(p.get("px"), p.get("py"), p.get("pz"))
	_views[p] = g

func update(dt: float) -> void:
	_trail_t -= dt
	var trail := _trail_t <= 0.0
	if trail: _trail_t = 0.035
	for p: Object in _views:
		var g: Node3D = _views[p]
		var pos := Vector3(p.get("px"), p.get("py"), p.get("pz"))
		var vel := Vector3(p.get("vx"), p.get("vy"), p.get("vz"))
		g.position = pos
		var kind := (p as Weapons.Shot).kind if p is Weapons.Shot else "knife"
		if kind == "grenade":
			var s := p as Weapons.Shot
			g.rotation.x += dt * 9.0
			var base := 0.9 if s.key == "cluster" else 1.15
			g.scale = Vector3.ONE * base * (1.0 + 0.25 * absf(sin(s.age * 30.0)) if s.fuse - s.age < 0.7 else 1.0)
		elif kind == "net":
			var s2 := p as Weapons.Shot
			g.scale = Vector3.ONE * minf(1.4, 0.3 + s2.age * 3.2)
			g.rotation.y += dt * 7.0
		elif float(p.get("stuck")) <= 0.0 and vel.length_squared() > 0.01:
			var up := Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT
			g.look_at_from_position(pos, pos + vel, up)
		if kind == "rocket" and trail:
			_add_fx(_mi_fx(LowPoly.ico(0.18, 0), mat(0x8a939c, 0.6), pos), randf_range(0.35, 0.6), Vector3(0, 0.8, 0), "smoke", 0.8, 2.2)
	for t: Object in _nets:                  # the last 0.4 s the net shrinks away
		var tn := t as Weapons.TrapNet
		var k := clampf((tn.life - tn.t) / 0.4, 0.01, 1.0) if tn.t > tn.life - 0.4 else 1.0
		(_nets[t] as Node3D).scale = Vector3.ONE * k
	_update_fx(dt)

# ============================== nets on the ground ==============================

func _net_land(t: Weapons.TrapNet) -> void:
	var g := Node3D.new()
	var r := t.radius
	_mi(g, LowPoly.cyl(r, r, 0.03, 16), mat(0xf2ead2, 0.45), Vector3(0, 0.05, 0))
	_mi(g, LowPoly.torus(r, 0.045, 4, 20), mat(0xd8cfb4), Vector3(0, 0.06, 0), Vector3(PI / 2, 0, 0))
	for i in 10:                             # little stones holding the rim down
		var a := i / 10.0 * TAU
		_mi(g, LowPoly.ico(0.12, 0), mat(0x77777c if i % 2 else 0x55555a), Vector3(cos(a) * (r - 0.04), 0.08, sin(a) * (r - 0.04)), Vector3.ZERO, Vector3(1, 0.7, 1))
	for f: FighterState in t.victims:        # a bulge over whoever is lying under it
		_mi(g, LowPoly.ico(0.75, 1), mat(0xf2ead2, 0.35), Vector3(f.phys.px - t.x, 0.35, f.phys.pz - t.z), Vector3(0, f.yaw, 0), Vector3(0.9, 0.55, 1.6))
	add_child(g)
	g.position = Vector3(t.x, t.gy, t.z)
	_nets[t] = g
	_burst(g.position + Vector3(0, 0.3, 0), 0xf2ead2, 8, 5.0)

# ============================== effects ==============================

## explode(): white core, orange middle, red outside, a shockwave ring on the ground, smoke and debris.
func explode(pos: Vector3, gy: float, rad: float) -> void:
	for b: Array in [[0xfff6c8, 0.95, 0.18, 0.55], [0xffb13b, 0.8, 0.38, 0.9], [0xff5a1f, 0.5, 0.55, 1.05]]:
		_add_fx(_mi_fx(LowPoly.ico(1.0, 1), mat(b[0], b[1]), pos), b[2], Vector3.ZERO, "boom", rad * b[3] * 0.2, rad * b[3], true)
	var ring := _mi_fx(LowPoly.torus(1.0, 0.06, 3, 24), mat(0xffe9b0, 0.8), Vector3(pos.x, gy + 0.08, pos.z))
	ring.rotation.x = PI / 2
	_add_fx(ring, 0.5, Vector3.ZERO, "boom", 0.2, rad * 1.25, true)
	for i in 5:
		var off := Vector3(randf_range(-1, 1) * rad * 0.3, randf_range(0, 0.6), randf_range(-1, 1) * rad * 0.3)
		_add_fx(_mi_fx(LowPoly.ico(0.5, 0), mat(0x6b7580, 0.45), pos + off), randf_range(0.9, 1.4),
			Vector3(randf_range(-1, 1) * 1.2, randf_range(2, 4), randf_range(-1, 1) * 1.2), "smoke", 0.7, 1.25)
	_burst(pos, 0xffd27a, 10, 11.0)
	_burst(pos, 0x3a3f48, 6, 7.0)

## A flame puff (flameFx): yellow, then orange, then dark red, swelling and drifting up as it burns out.
func flame(pos: Vector3, vel: Vector3, life: float) -> void:
	if _fx.size() >= MAX_FX: return
	_add_fx(_mi_fx(LowPoly.ico(0.16, 0), mat(0xffe27a, 0.85), pos), life, vel, "flame", 0.6, 2.4)

## Little cubes thrown out (puff in the web game).
func _burst(at: Vector3, col: int, n: int, spd: float) -> void:
	if _fx.size() >= MAX_FX: return
	for i in n:
		var d := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized() * spd * randf_range(0.4, 1.0)
		_add_fx(_mi_fx(LowPoly.box(0.16, 0.16, 0.16), mat(col), at), randf_range(0.3, 0.6), d, "puff", 1.0, 0.05)

func _mi_fx(mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh; n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position = pos
	return n

## s0 -> s1: the scale over the effect's life (`grow`: ease out, for blasts).
func _add_fx(n: Node3D, life: float, vel: Vector3, kind: String, s0: float, s1: float, grow := false) -> void:
	add_child(n)
	n.scale = Vector3.ONE * s0
	_fx.append({"node": n, "life": life, "max": life, "vel": vel, "kind": kind, "s0": s0, "s1": s1, "grow": grow})

func _update_fx(dt: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var x: Dictionary = _fx[i]
		x["life"] -= dt
		var n: Node3D = x["node"]
		if x["life"] <= 0.0:
			n.queue_free(); _fx.remove_at(i); continue
		var k := 1.0 - float(x["life"]) / float(x["max"])     # 0 -> 1 over the life
		if x["grow"]: k = 1.0 - (1.0 - k) * (1.0 - k)
		var s := lerpf(x["s0"], x["s1"], k)
		if x["kind"] == "boom" and k > 0.7: s *= (1.0 - k) / 0.3 + 0.05     # blasts pop out, then vanish
		n.scale = Vector3.ONE * maxf(s, 0.01)
		match x["kind"]:
			"puff": x["vel"] += Vector3(0, -9.0, 0) * dt
			"flame":
				x["vel"] += Vector3(0, 2.5, 0) * dt
				(n as MeshInstance3D).material_override = mat(0xffe27a if k < 0.25 else (0xff8a2b if k < 0.6 else 0x8a2a14), 0.85)
		n.position += x["vel"] * dt
