class_name ProjectileViews
extends Node3D
## What flies and blows up: rockets, grenades, arrows, nets, knives, shuriken stars, typhoon blades, thrown tridents,
## boomerangs, snakes and snowballs in flight (Weapons.Shot and its Boom / Snake / Ball, Weapons.Proj), nets
## lying on the ground (Weapons.TrapNet), explosions and flames. Pure presentation: World forwards the Combat events
## (on_event) and calls update() every rendered frame; the views read the positions straight from the logic objects.
## Kept cheap for iPhone: shared low-poly meshes and materials, effects fade by scale only (no per-effect
## materials), and a cap on live effects (flames are dropped first).
## With `fx` set (the World does, effects on), blasts, flames, bursts and rocket smoke go to the pooled FxSystem
## (world/fx.gd) instead of nodes here; trails behind the flying things are drawn by world/trails.gd.

const MAX_FX := 150

var _views := {}                   ## Shot / Proj -> Node3D
var _nets := {}                    ## TrapNet -> Node3D
var _fx: Array = []                ## {node, life, max, vel, kind, s0, s1}
var _trail_t := 0.0
var fx: FxSystem = null            ## pooled effects (null: the node effects below)
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
				match _kind(p):
					"net": _burst(n.position, 0xf2ead2, 5, 3.0)
					"ball": _burst(n.position, 0xffffff, 8, 5.0)
					"snake": _burst(n.position, 0x7dff8a, 5, 3.0)
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
		"ball_smash": _burst(Vector3(e["x"], e["y"], e["z"]), 0xffffff, 10, 7.0)

## Which look a flying thing gets: the Shot kind, or the thrown weapon's key for knife-like projectiles.
static func _kind(p: Object) -> String:
	if p is Weapons.Shot: return (p as Weapons.Shot).kind
	var key: String = p.get("key")
	return key if key in ["shuriken", "typhoon", "trident"] else "knife"

# ============================== things in flight ==============================

func _spawn(p: Object) -> void:
	if _views.has(p): return
	var g := Node3D.new()
	var kind := _kind(p)
	var key: String = p.get("key")
	var inner := Node3D.new()                # spinning part (stars, blades, boomerang)
	inner.name = "Inner"
	g.add_child(inner)
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
		"shuriken":                 # two crossed blades and a red hub, lying flat
			for r: float in [PI / 4, -PI / 4]:
				_mi(inner, LowPoly.box(0.62, 0.025, 0.11), mat(0xeef3f7), Vector3.ZERO, Vector3(0, r, 0))
			_mi(inner, LowPoly.cyl(0.08, 0.08, 0.05, 8), mat(0xe3566b))
		"typhoon":                  # a disc with three swept blades (the shuriken's size)
			_mi(inner, LowPoly.cyl(0.19, 0.19, 0.05, 10), mat(0x2d7fb0))
			for k in 3:
				var a := k / 3.0 * TAU
				_mi(inner, LowPoly.box(0.42, 0.02, 0.1), mat(0x7ee8ff), Vector3(cos(a) * 0.3, 0, -sin(a) * 0.3), Vector3(0, a + 0.5, 0))
			inner.scale = Vector3.ONE * 0.62
		"trident":                  # pole along -Z with three prongs at the front
			_mi(g, LowPoly.cyl(0.035, 0.035, 1.6, 5), mat(0x8a5a2b), Vector3(0, 0, 0.2), Vector3(PI / 2, 0, 0))
			for x: float in [-0.09, 0.0, 0.09]:
				_mi(g, LowPoly.box(0.03, 0.03, 0.34), mat(0xffd24a), Vector3(x, 0, -0.75))
			_mi(g, LowPoly.box(0.24, 0.04, 0.04), mat(0xffd24a), Vector3(0, 0, -0.58))
		"boomerang":                # a bent stick lying flat, striped tips, yellow hub
			for sg: float in [-1.0, 1.0]:
				_mi(inner, LowPoly.box(0.62, 0.055, 0.17), mat(0xe8ab5c), Vector3(sg * 0.26, 0, 0.1), Vector3(0, sg * 0.45, 0))
				_mi(inner, LowPoly.box(0.12, 0.06, 0.15), mat(0xe3566b), Vector3(sg * 0.53, 0, 0.24), Vector3(0, sg * 0.45, 0))
			_mi(inner, LowPoly.cyl(0.09, 0.09, 0.075, 8), mat(0xffd24a))
		"snake":                    # head (eyes, tongue) + body segments that follow its path (update)
			var head := _mi(g, LowPoly.ico(0.24, 0), mat(0x4cc25a))
			for sx: float in [-0.1, 0.1]: _mi(head, LowPoly.box(0.06, 0.06, 0.06), mat(0xffd93b), Vector3(sx, 0.12, 0.17))
			_mi(head, LowPoly.box(0.04, 0.02, 0.22), mat(0xe3566b), Vector3(0, -0.02, 0.3))
			head.name = "Head"
			for n in range(1, 8):
				_mi(inner, LowPoly.ico(0.2 - n * 0.012, 0), mat(0x2e7a3a if n % 2 else 0x4cc25a))
			g.set_meta("hist", [])
		"ball":                     # a snowball that grows as it rolls
			_mi(inner, LowPoly.ico(1.0, 1), mat(0xf4fbff))
			g.scale = Vector3.ONE * 0.35
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
		var kind := _kind(p)
		if kind == "ball":
			var b := p as Weapons.Ball
			g.position.y = Weapons.ball_y(b)
			g.scale = Vector3.ONE * b.r
			g.rotation.y = b.heading
			(g.get_child(0) as Node3D).rotation.x += dt * (7.0 if b.rolling else 3.0)
		elif kind == "snake":
			_snake(g, p as Weapons.Snake, dt)
		elif kind == "boomerang":
			var bm := p as Weapons.Boom
			(g.get_child(0) as Node3D).rotation.y += dt * 26.0
			var bank := minf(1.0, bm.age / 0.5) if bm.phase == 0 else 1.0     # leans into the turn
			g.rotation = Vector3(0.25 + 0.55 * bank, bm.h, -0.5 * bank * (1.0 if bm.phase == 0 else -0.6))
			g.scale = Vector3.ONE * 1.15 * (0.5 + bm.age / 0.15 * 0.5 if bm.age < 0.15 else 1.0)
		elif kind == "shuriken" or kind == "typhoon":
			if float(p.get("stuck")) <= 0.0 and vel.length_squared() > 0.01:
				var up2 := Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT
				g.look_at_from_position(pos, pos + vel, up2)
				(g.get_child(0) as Node3D).rotation.y += dt * float(p.get("spin"))
		elif kind == "grenade":
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
		if kind == "rocket" and trail and fx:
			fx.smoke_puff(pos)
		elif kind == "rocket" and trail:
			_add_fx(_mi_fx(LowPoly.ico(0.18, 0), mat(0x8a939c, 0.6), pos), randf_range(0.35, 0.6), Vector3(0, 0.8, 0), "smoke", 0.8, 2.2)
	for t: Object in _nets:                  # the last 0.4 s the net shrinks away
		var tn := t as Weapons.TrapNet
		var k := clampf((tn.life - tn.t) / 0.4, 0.01, 1.0) if tn.t > tn.life - 0.4 else 1.0
		(_nets[t] as Node3D).scale = Vector3.ONE * k
	_update_fx(dt)

## The snake's body follows the head along its recent path (hist, like the web game's 0.045 s samples).
func _snake(g: Node3D, s: Weapons.Snake, dt: float) -> void:
	var hist: Array = g.get_meta("hist")
	var t := float(g.get_meta("ht", 0.0)) - dt
	if t <= 0.0:
		t = 0.045; hist.push_front(g.position)
		if hist.size() > 9: hist.pop_back()
	g.set_meta("ht", t)
	(g.get_node("Head") as Node3D).rotation.y = s.heading
	var segs := g.get_child(0)
	for n in segs.get_child_count():
		var at: Vector3 = hist[mini(n + 1, hist.size() - 1)] if hist.size() > 0 else g.position
		(segs.get_child(n) as Node3D).position = at - g.position

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
	if fx:
		fx.explosion(pos, gy, rad)
		if fx.world != null:                     # camera shake by distance (the web's 0.34 - d * 0.011)
			var d := pos.distance_to(fx.world.cam.global_position)
			fx.world.add_shake(clampf(0.34 - d * 0.011, 0.02, 0.34))
		return
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
	if fx:
		fx.flame(pos, vel, life)
		return
	if _fx.size() >= MAX_FX: return
	_add_fx(_mi_fx(LowPoly.ico(0.16, 0), mat(0xffe27a, 0.85), pos), life, vel, "flame", 0.6, 2.4)

## Little cubes thrown out (puff in the web game).
func _burst(at: Vector3, col: int, n: int, spd: float) -> void:
	if fx:
		fx.puff(at, Color.hex((col << 8) | 0xff), n, spd)
		return
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
