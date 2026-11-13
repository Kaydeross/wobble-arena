class_name FxSystem
extends Node3D
## Combat visual effects (docs/GRAPHICS.md "Effects"), PRESENTATION ONLY: reads Combat events and fighter states,
## never writes sim state and never draws from the global RNG (its own RandomNumberGenerator), so a match plays the
## same with effects on or off (godot/tests/fx_test.gd compares sim hashes).
##
## Everything is pooled: five MultiMesh pools (one draw call each) with a hard cap per effects level, simulated on the
## CPU into one packed buffer per frame (no nodes, no allocations per event; when a pool is full the oldest slot is
## recycled), a small pool of Label3D damage numbers, and the ambient specks.
##   bits     little icosahedra: puffs, dust, sparks, footsteps (opaque, shrink out)
##   chips    tumbling flat boxes: KO confetti, debris, shell casings
##   blobs    soft alpha spheres: fireballs, smoke, flames, muzzle flashes
##   rings    flat ground rings (shaders/fx_ring.gdshader): shockwaves, landings, bounce pads, K.O.s
##   streaks  stretched alpha boxes along a direction: dash streaks, spark streaks, tracers
## Level (Settings "effects": auto = the Tier, low / medium / high): LOW minimal (small caps, fewer particles, no
## specks, no shells or spark streaks), MID moderate, HIGH full. Trails live in world/trails.gd, squash / stretch and
## the hitstop pose freeze in actors/fighter_juice.gd.

const CAPS := {
	"bits": [96, 320, 720],
	"chips": [24, 120, 240],
	"blobs": [16, 56, 112],
	"rings": [6, 16, 32],
	"streaks": [16, 64, 128],
}
const LABELS := [10, 20, 28]
const SPECK_N := [0, 36, 72]
const DENSITY := [0.4, 0.75, 1.0]
const DMG_LIFE := 0.9
const DUST := Color(0.95, 0.91, 0.83)

## Damage-number colour and size per body part (Combat.body_part; docs/DAMAGE.md). "" = whole body (splash, flame).
## The same colours tint the impact sparks (one look for "where it struck").
const PART_COL := {"head": Color(1, 0.35, 0.25), "torso": Color(1, 0.95, 0.4), "arms": Color(0.55, 0.85, 1), "legs": Color(0.75, 0.8, 0.9)}
const PART_SIZE := {"head": 56, "torso": 44, "arms": 40, "legs": 38}
## web SPECKS: kind -> [colour, rise speed (negative falls), sideways drift]
const SPECKS := {
	"pollen": [0xfff2a8, 0.35, 0.6], "snow": [0xffffff, -2.2, 0.4], "ember": [0xff8a2e, 2.4, 0.5], "petal": [0xffb3c8, -0.9, 1.3],
	"bubble": [0xb8f0ff, 1.1, 0.5], "wisp": [0xa8ffb8, 0.5, 0.9], "confetti": [0xffffff, -1.5, 0.9], "dust": [0xe9d9b0, 0.12, 1.0],
	"star": [0xcfe6ff, 0.08, 0.3],
}
const CONFETTI := [0xff6b9a, 0xffd23f, 0x4fe0cf, 0x7aa8ff, 0xb48cff]

var lv := 2                         ## effects level this match (0 LOW, 1 MID, 2 HIGH)
var world: Node                     ## the World (views, sim, cam); may be null in tests
var pools := {}                     ## name -> Pool
var rng := RandomNumberGenerator.new()
var _labels: Array = []             ## {node, life, vel}
var _label_i := 0
var _watch := {}                    ## FighterState -> {g, vy, sp, vx, vz, foot}
var _specks: Specks

## The effects level: Settings "effects" (auto | low | medium | high), auto = the graphics tier.
static func level() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var st: Node = tree.root.get_node_or_null("Settings") if tree and tree.root else null
	var v := str(st.call("get_value", "effects", "auto")) if st else "auto"
	match v:
		"low": return 0
		"medium": return 1
		"high": return 2
	return MapBuilder.gfx_q()

func _init(p_level := -1) -> void:
	name = "Fx"
	rng.seed = 0x5eed
	lv = p_level if p_level >= 0 else level()
	var opaque := _material(false, false)
	var alpha := _material(true, true)
	var ring := ShaderMaterial.new()
	ring.shader = load("res://shaders/fx_ring.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.orientation = PlaneMesh.FACE_Y
	pools["bits"] = Pool.new(self, CAPS["bits"][lv], Pool.BITS, LowPoly.ico(0.5, 0), opaque)
	pools["chips"] = Pool.new(self, CAPS["chips"][lv], Pool.CHIPS, LowPoly.box(1.0, 0.14, 0.62), _material(false, true))
	pools["blobs"] = Pool.new(self, CAPS["blobs"][lv], Pool.BLOBS, LowPoly.ico(1.0, 1), alpha)
	pools["rings"] = Pool.new(self, CAPS["rings"][lv], Pool.RINGS, quad, ring)
	pools["streaks"] = Pool.new(self, CAPS["streaks"][lv], Pool.STREAKS, LowPoly.box(1.0, 1.0, 1.0), alpha)
	for i in LABELS[lv]:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.pixel_size = 0.006
		l.outline_size = 12
		l.visible = false
		add_child(l)
		_labels.append({"node": l, "life": 0.0, "vel": Vector3(0, 1.6, 0)})
	if SPECK_N[lv] > 0:
		_specks = Specks.new(SPECK_N[lv], rng)
		add_child(_specks)

static func _material(transparent: bool, cull_off: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.disable_fog = false
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## A new match: drop every live effect, set the map's ambient specks.
func clear() -> void:
	for p: Pool in pools.values(): p.clear()
	for x: Dictionary in _labels:
		x["life"] = 0.0; (x["node"] as Label3D).visible = false
	_watch.clear()

func setup_map(id: String, map: Dictionary) -> void:
	if _specks == null: return
	var env: Dictionary = map.get("env", {}) if map.get("env") is Dictionary else {}
	var kind := str(MapBuilder.look(id).get("specks", env.get("speck", "pollen")))
	if not SPECKS.has(kind): kind = "pollen"
	var col := int(env.get("speckColor", SPECKS[kind][0]))
	_specks.configure(kind, col, SPECKS[kind], CONFETTI if kind == "confetti" else [])

## Live particles in every pool (tests, integration budget).
func live_count() -> int:
	var n := 0
	for p: Pool in pools.values(): n += p.n
	for x: Dictionary in _labels:
		if x["life"] > 0.0: n += 1
	return n

## {pool: {n, cap, peak, spawned, recycled}} (tests).
func stats() -> Dictionary:
	var out := {}
	for k: String in pools:
		var p: Pool = pools[k]
		out[k] = {"n": p.n, "cap": p.cap, "peak": p.peak, "spawned": p.spawned, "recycled": p.recycled}
	var ln := 0
	for x: Dictionary in _labels:
		if x["life"] > 0.0: ln += 1
	out["labels"] = {"n": ln, "cap": _labels.size(), "peak": ln, "spawned": 0, "recycled": 0}
	out["specks"] = {"n": _specks.count if _specks else 0, "cap": SPECK_N[lv], "peak": 0, "spawned": 0, "recycled": 0}
	return out

## Particle count for this level (at least 1).
func cnt(n: int) -> int:
	return maxi(1, int(round(n * DENSITY[lv])))

func _rv(spd: float, up := 0.2) -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(up, 1.2), rng.randf_range(-1, 1)).normalized() * spd * rng.randf_range(0.4, 1.0)

# ================================================================ effect builders

## The web game's puff: little bits thrown out (and along `dir`, the Air Blower gusts), falling and shrinking.
func puff(at: Vector3, col: Color, n: int, spd: float, dir: Array = []) -> void:
	var p: Pool = pools["bits"]
	for i in cnt(n):
		var d := _rv(spd)
		if dir.size() == 3:
			d = (Vector3(dir[0], dir[1], dir[2]) * 1.6 + d.normalized() * 0.35).normalized() * spd * rng.randf_range(0.6, 1.0)
		p.add(at, d, rng.randf_range(0.3, 0.6), 0.16, 0.01, col, col, 9.0, 0.0)

## landDust: a soft ring of dust thrown out flat along the ground.
func dust(at: Vector3, n: int, spd: float, col := DUST) -> void:
	var p: Pool = pools["bits"]
	var k := cnt(n)
	for i in k:
		var a := float(i) / k * TAU + rng.randf_range(-0.2, 0.2)
		var sp := spd * rng.randf_range(0.6, 1.2)
		p.add(at + Vector3(cos(a), 0, sin(a)) * 0.35, Vector3(cos(a) * sp, rng.randf_range(0.3, 1.0), sin(a) * sp),
			rng.randf_range(0.35, 0.55), 0.2, 0.02, col, col, 2.5, 3.0)

func ring(at: Vector3, col: Color, r: float, life := 0.45, alpha := 0.7) -> void:
	var c := Color(col.r, col.g, col.b, alpha)
	(pools["rings"] as Pool).add(at, Vector3.ZERO, life, r * 0.15, r, c, c, 0.0, 0.0)

func blob(at: Vector3, vel: Vector3, life: float, s0: float, s1: float, c0: Color, c1: Color, grav := 0.0) -> void:
	(pools["blobs"] as Pool).add(at, vel, life, s0, s1, c0, c1, grav, 0.0)

## A stretched streak along `dir` (unit): `len` long, `w` wide, drifting with `vel`.
func streak(at: Vector3, dir: Vector3, len: float, w: float, col: Color, life: float, vel := Vector3.ZERO) -> void:
	(pools["streaks"] as Pool).add(at, vel, life, len, w, col, col, 0.0, 0.0, dir)

## Tumbling flat chips (confetti, debris, shells): `cols` picked in turn.
func chips(at: Vector3, cols: Array, n: int, spd: float, size: float, life: float, grav: float, drag := 1.5) -> void:
	var p: Pool = pools["chips"]
	for i in n:
		var c: Color = cols[i % cols.size()]
		var ax := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(6.0, 14.0)
		p.add(at, _rv(spd, 0.5), life * rng.randf_range(0.8, 1.2), size, size, c, c, grav, drag, ax)

## Impact sparks: part-coloured bits (and spark streaks above LOW), count and speed scaled by the damage / force.
func sparks(at: Vector3, col: Color, dmg: float, force: float) -> void:
	var p: Pool = pools["bits"]
	var n := cnt(clampi(3 + int(dmg / 5.0), 3, 16))
	var spd := 3.0 + clampf(force, 0.0, 20.0) * 0.35
	var hot := col.lerp(Color.WHITE, 0.45)
	for i in n:
		p.add(at, _rv(spd, -0.4), rng.randf_range(0.2, 0.42), 0.11 + minf(dmg, 60.0) * 0.0015, 0.01, hot if i % 2 else col, col, 12.0, 1.0)
	if lv >= 1:
		for i in clampi(n / 3, 1, 5):
			var d := _rv(1.0, -0.3).normalized()
			streak(at + d * 0.2, d, rng.randf_range(0.3, 0.55) * (1.0 + minf(dmg, 60.0) / 60.0), 0.035, Color(hot.r, hot.g, hot.b, 0.95), 0.12, d * spd * 0.6)

## The K.O. pop: a shockwave ring and colourful sparkles (koBurst), plus the death puffs.
func ko_burst(at: Vector3) -> void:
	puff(at + Vector3(0, 1.6, 0), Color(1, 0.89, 0.48), 12, 6.0)
	puff(at + Vector3(0, 1.0, 0), Color.WHITE, 6, 4.0)
	ring(at + Vector3(0, 0.1, 0), Color.hex(0xfff1b8ff), 3.2)
	for c: int in [0xff6fb5, 0x6fe3ff, 0xfff176, 0xb48cff]:
		puff(at + Vector3(0, 1.3, 0), Color.hex((c << 8) | 0xff), 3, 7.0)

## K.O. confetti in the killer's colour (with lighter / darker tones and white).
func confetti(at: Vector3, col: Color) -> void:
	var cols := [col, col.lightened(0.35), Color.WHITE, col.darkened(0.25), Color.hex(0xffd23fff)]
	chips(at, cols, [10, 26, 44][lv], 7.5, 0.3, 1.5, 7.0, 2.2)
	if lv >= 1: ring(at + Vector3(0, -1.2, 0), col.lightened(0.3), 2.4, 0.4, 0.6)

## explode(): white core, orange middle, red outside, a ground shockwave, rising smoke, debris and sparks.
func explosion(pos: Vector3, gy: float, rad: float) -> void:
	for i in [2, 5, 9][lv]:                       # smoke rising and swelling (first: the pool draws in spawn order,
		var off := Vector3(rng.randf_range(-1, 1) * rad * 0.3, rng.randf_range(0.3, 0.9), rng.randf_range(-1, 1) * rad * 0.3)   # the fire on top)
		blob(pos + off, Vector3(rng.randf_range(-1, 1) * 1.2, rng.randf_range(2.5, 4.5), rng.randf_range(-1, 1) * 1.2),
			rng.randf_range(1.0, 1.7), rad * 0.08, rad * 0.5, Color(0.42, 0.46, 0.5, 0.42), Color(0.3, 0.32, 0.35, 0.3), -0.6)
	var layers := [[0xfff6c8, 0.95, 0.2, 0.55], [0xffb13b, 0.85, 0.42, 0.9], [0xff5a1f, 0.6, 0.6, 1.05]]
	if lv == 0: layers = [layers[1], layers[2]]
	for b: Array in layers:
		var c := Color.hex((int(b[0]) << 8) | 0xff); c.a = b[1]
		blob(pos, Vector3.ZERO, b[2], rad * b[3] * 0.2, rad * b[3], c, Color(c.r, c.g * 0.6, c.b * 0.4, c.a))
	if lv == 2:                                   # a few offset fireballs: a lumpier blast
		for i in 4:
			var o := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.8), rng.randf_range(-1, 1)) * rad * 0.35
			blob(pos + o, o * 1.5, rng.randf_range(0.3, 0.45), rad * 0.15, rad * 0.5, Color(1, 0.7, 0.25, 0.8), Color(0.55, 0.2, 0.08, 0.6))
	ring(Vector3(pos.x, gy + 0.08, pos.z), Color.hex(0xffe9b0ff), rad * 1.25, 0.5, 0.85)
	if lv >= 1: ring(Vector3(pos.x, gy + 0.1, pos.z), Color.hex(0xffffffff), rad * 0.8, 0.25, 0.6)
	chips(pos, [Color.hex(0x3a3f48ff), Color.hex(0x5a4a3aff), Color.hex(0x2a2a2eff)], [4, 8, 14][lv], 9.0, 0.2, 1.1, 18.0, 0.6)
	puff(pos, Color.hex(0xffd27aff), 14, 11.0)
	if lv >= 1:
		for i in [0, 6, 10][lv]:
			var d := _rv(1.0, -0.2).normalized()
			streak(pos + d * rad * 0.3, d, rng.randf_range(0.6, 1.2), 0.05, Color(1, 0.85, 0.45, 0.9), 0.18, d * 14.0)

## flameFx: yellow, then orange, then dark red, swelling and drifting up as it burns out.
func flame(pos: Vector3, vel: Vector3, life: float) -> void:
	blob(pos, vel, life, 0.16 * 0.6, 0.16 * 2.4, Color(1, 0.89, 0.48, 0.85), Color(0.54, 0.16, 0.08, 0.5), -2.5)

## Rocket exhaust smoke.
func smoke_puff(pos: Vector3) -> void:
	blob(pos, Vector3(0, 0.8, 0), rng.randf_range(0.35, 0.6), 0.14, 0.4, Color(0.6, 0.62, 0.65, 0.55), Color(0.45, 0.47, 0.5, 0.2))

## Muzzle flash (a hot blob and a few sparks forward) and, above LOW, a shell casing flicked out to the side.
func muzzle(at: Vector3, dir: Vector3, key: String) -> void:
	var big := key in ["shotgun", "sniper", "mammoth", "revolver"]
	blob(at, Vector3.ZERO, 0.06, 0.12, 0.3 if big else 0.2, Color(1, 0.96, 0.7, 1.0), Color(1, 0.6, 0.2, 0.6))
	var p: Pool = pools["bits"]
	for i in cnt(3):
		var d := (dir + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.3, 0.3))).normalized()
		p.add(at, d * rng.randf_range(4.0, 8.0), 0.12, 0.07, 0.01, Color(1, 0.85, 0.4), Color(1, 0.85, 0.4), 4.0, 0.0)
	if lv >= 1 and key != "flame" and key != "blower" and key != "glove":
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-4: side = Vector3.RIGHT
		side = side.normalized()
		var col := Color.hex(0xd8463aff) if key == "shotgun" else Color.hex(0xd9a441ff)
		var ax := Vector3(rng.randf_range(-1, 1), 1, rng.randf_range(-1, 1)).normalized() * 18.0
		(pools["chips"] as Pool).add(at - dir * 0.25, side * rng.randf_range(2.0, 3.0) + Vector3(0, 2.6, 0), 0.6, 0.09, 0.09, col, col, 18.0, 0.5, ax)

## Dash: streaks along the dash, a ring at the feet and a puff.
func dash(at: Vector3, dir: Vector3) -> void:
	if dir.length_squared() < 1e-4: dir = Vector3.FORWARD
	dir = dir.normalized()
	for i in [2, 5, 8][lv]:
		var o := Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.7, 0.7), rng.randf_range(-0.45, 0.45))
		streak(at + o - dir * 0.6, dir, rng.randf_range(1.2, 2.4), 0.07, Color(0.9, 0.96, 1.0, 0.9), rng.randf_range(0.2, 0.3), dir * 3.0)
	ring(at + Vector3(0, -0.85, 0), Color(0.8, 0.92, 1.0), 1.8, 0.35)
	puff(at, Color(0.85, 0.92, 1.0), 6, 3.5)

## Slam / hard landing shockwave.
func slam(at: Vector3) -> void:
	ring(at + Vector3(0, 0.08, 0), Color(1, 0.97, 0.88), 3.6, 0.45, 0.85)
	if lv >= 1: ring(at + Vector3(0, 0.1, 0), DUST, 2.0, 0.3, 0.6)
	dust(at + Vector3(0, 0.08, 0), 12, 4.5)

func dmg_number(at: Vector3, dmg: float, part: String, pct: int = 0) -> void:
	var x: Dictionary = _labels[_label_i % _labels.size()]          # the oldest one when all are up
	_label_i += 1
	var l: Label3D = x["node"]
	l.text = str(int(round(dmg))) + ("\n%+d%%" % pct if pct != 0 else "")
	l.font_size = PART_SIZE.get(part, 44)
	l.modulate = PART_COL.get(part, Color(1, 0.95, 0.4))
	l.position = at
	l.visible = true
	x["life"] = DMG_LIFE

func tracer(o: Vector3, e: Vector3) -> void:
	var len := o.distance_to(e)
	if len < 0.05: return
	streak((o + e) * 0.5, (e - o) / len, len, 0.035, Color(1, 0.93, 0.6, 1.0), 0.06)

# ================================================================ Combat events

func on_event(e: Dictionary) -> void:
	var f: FighterState = e.get("f") if e.get("f") is FighterState else null
	match String(e["type"]):
		"dmg_number":
			if f: dmg_number(Vector3(f.head_x, f.head_y + 0.5, f.head_z), float(e["dmg"]), String(e.get("part", "head" if e["head"] else "")), int(e.get("pct", 0)))
		"hit":
			if f: _on_hit(e, f)
		"ko_burst":
			if f: ko_burst(Vector3(f.phys.px, f.phys.py, f.phys.pz))
		"ko":
			_on_ko(e)
		"tracer":
			tracer(Vector3(e["ox"], e["oy"], e["oz"]), Vector3(e["ex"], e["ey"], e["ez"]))
		"crate_land":
			var c: Dictionary = e["crate"]
			puff(Vector3(c["x"], c["gy"] + 0.3, c["z"]), Color(1, 0.82, 0.29), 10, 5.0)
			if lv >= 1: ring(Vector3(c["x"], c["gy"] + 0.06, c["z"]), Color(1, 0.86, 0.45), 1.6, 0.35)
		"puff":
			if str(e.get("kind", "")) == "dash":
				dash(Vector3(e["x"], e["y"], e["z"]), _dash_dir(e))
			else:
				puff(Vector3(e["x"], e["y"], e["z"]), Color.hex((int(e.get("color", 0xffffff)) << 8) | 0xff), int(e.get("n", 4)),
					float(e.get("spd", 3.0)), e.get("dir", []))
		"pad":
			if f:
				var at := Vector3(f.phys.px, 0.15, f.phys.pz)
				puff(at, Color(0.62, 0.96, 0.92), 6, 3.0)
				ring(at, Color(0.62, 0.96, 0.92), 2.2, 0.4, 0.8)
				if lv >= 1: ring(at + Vector3(0, 0.05, 0), Color.WHITE, 1.2, 0.25, 0.7)
		"shot":
			if f:
				var d := Vector3(f.arm_x, f.arm_y, f.arm_z)
				if d.length_squared() < 1e-4: d = Vector3(sin(f.yaw), 0, cos(f.yaw))
				muzzle(Vector3(f.hand_x, f.hand_y, f.hand_z) + d.normalized() * 0.55, d.normalized(), str(e.get("key", "")))

func _dash_dir(e: Dictionary) -> Vector3:
	if e.has("dx"): return Vector3(float(e["dx"]), 0, float(e["dz"]))
	if world == null: return Vector3.ZERO
	var at := Vector3(e["x"], e["y"], e["z"])
	var best: FighterState = null
	var bd := 4.0
	for st: FighterState in world.views:                 # the katana dash: whoever stands there
		var d := Vector3(st.phys.px, st.phys.py + 1.0, st.phys.pz).distance_to(at)
		if d < bd: bd = d; best = st
	return Vector3(best.phys.vx, 0, best.phys.vz) if best else Vector3.ZERO

func _on_hit(e: Dictionary, f: FighterState) -> void:
	var dmg := float(e.get("dmg", 0.0))
	var force := float(e.get("force", 0.0))
	var part := String(e.get("part", ""))
	var col: Color = PART_COL.get(part, Color(1, 0.95, 0.8))
	var at := Vector3(e["x"], e["y"], e["z"]) if e.has("x") else Vector3(f.chest_x, f.chest_y, f.chest_z)
	puff(Vector3(f.chest_x, f.chest_y, f.chest_z), Color(1, 0.95, 0.8), 4, 3.0)
	sparks(at, col, dmg, force)
	if part == "head" and lv >= 1:
		ring(at, col, 0.9, 0.2, 0.8)
	if world == null: return
	var me: FighterState = world.sim.player
	var a: FighterState = e.get("attacker") if e.get("attacker") is FighterState else null
	if f == me or a == me:
		if dmg >= 6.0: world.hitstop(2 if dmg < 20.0 else (3 if dmg < 40.0 else 4))
		var s := 0.0
		if f == me: s = clampf(0.06 + dmg * 0.002, 0.06, 0.16)
		elif a.slam: s = 0.14
		elif a.swing >= 0.0: s = 0.08
		else: s = clampf(dmg * 0.0015, 0.0, 0.06)
		world.add_shake(s)

func _on_ko(e: Dictionary) -> void:
	var k: FighterState = e.get("killer")
	var v: FighterState = e.get("victim")
	if v == null or v.phys.py < -2.0: return
	var col := Color(1, 0.85, 0.3)
	if world != null and k != null and world.views.has(k):
		col = Color.hex((int(world.views[k].look.get("color", 0xffd23f)) << 8) | 0xff)
	confetti(Vector3(v.phys.px, v.phys.py + 1.3, v.phys.pz), col)
	if world != null and (k == world.sim.player or v == world.sim.player):
		world.add_shake(0.18)
		if k == world.sim.player: world.hitstop(4)

# ================================================================ fighter motion (landings, footsteps, stops)

## Dust where fighters land hard, skid to a stop or sprint; a shockwave when a slam lands. Reads the states only.
func watch(views: Dictionary, dt: float) -> void:
	if dt <= 0.0: return
	var me: FighterState = world.sim.player if world != null else null
	for st: FighterState in views:
		if st.left or st.dead: _watch.erase(st); continue
		var p := st.phys
		var sp := Vector2(p.vx, p.vz).length()
		if not _watch.has(st):
			_watch[st] = {"g": p.grounded, "vy": p.vy, "sp": sp, "vx": p.vx, "vz": p.vz, "foot": 0.0, "slam": false}
			continue
		var w: Dictionary = _watch[st]
		var feet := Vector3(p.px, p.py + 0.08, p.pz)
		if p.grounded and not w["g"]:
			var v := -float(w["vy"])
			if w["slam"] or st.slam:
				slam(feet)
				if st == me: world.add_shake(0.14)
			elif v > 7.0:
				dust(feet, mini(12, 4 + int(v * 0.45)), 2.6)
				if v > 11.0:
					ring(feet, DUST, 1.4 + v * 0.05, 0.4, 0.55)
					if st == me: world.add_shake(minf(0.1, v * 0.006))
		elif not p.grounded and w["g"] and p.vy > 4.0 and lv >= 1:
			dust(feet, 5, 1.4)
		elif p.grounded and w["g"]:
			var drop := float(w["sp"]) - sp
			if float(w["sp"]) > 7.0 and drop > 3.0:              # a sudden stop: skid dust forward
				var d := Vector3(float(w["vx"]), 0, float(w["vz"])).normalized()
				puff(feet + d * 0.4, DUST, 5, 2.5, [d.x, 0.15, d.z])
			if sp > 9.0 and lv >= 1:                             # sprinting: little footstep puffs
				w["foot"] = float(w["foot"]) - dt
				if w["foot"] <= 0.0:
					w["foot"] = 0.24
					var back := -Vector3(p.vx, 0, p.vz).normalized()
					var bits: Pool = pools["bits"]
					for i in 2:
						bits.add(feet + back * 0.3, back * rng.randf_range(0.6, 1.4) + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.5, 1.2), rng.randf_range(-0.5, 0.5)),
							0.35, 0.16, 0.02, DUST, DUST, 2.0, 2.5)
		w["g"] = p.grounded; w["vy"] = p.vy; w["sp"] = sp; w["vx"] = p.vx; w["vz"] = p.vz
		w["slam"] = st.slam and st.swing >= 0.0

# ================================================================ per frame

func update(dt: float, cam_pos: Vector3) -> void:
	for p: Pool in pools.values(): p.update(dt)
	for x: Dictionary in _labels:
		if x["life"] <= 0.0: continue
		x["life"] -= dt
		var l: Label3D = x["node"]
		if x["life"] <= 0.0:
			l.visible = false; continue
		l.modulate.a = clampf(x["life"] / DMG_LIFE * 1.5, 0.0, 1.0)
		l.position += x["vel"] * dt
	if _specks: _specks.update(dt, cam_pos)


## One MultiMesh pool simulated on the CPU (see the class header). Live particles are packed at the front
## (swap-remove), so the buffer is written for live ones only and visible_instance_count = n.
class Pool extends RefCounted:
	enum { BITS, CHIPS, BLOBS, RINGS, STREAKS }
	var cap := 0
	var n := 0
	var peak := 0
	var spawned := 0
	var recycled := 0
	var mode := BITS
	var mm: MultiMesh
	var mmi: MultiMeshInstance3D
	var buf := PackedFloat32Array()
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var ax := PackedVector3Array()
	var life := PackedFloat32Array()
	var maxl := PackedFloat32Array()
	var sa := PackedFloat32Array()
	var sb := PackedFloat32Array()
	var grav := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var c0 := PackedColorArray()
	var c1 := PackedColorArray()
	var _next := 0
	var _drawn := -1

	func _init(parent: Node3D, p_cap: int, p_mode: int, mesh: Mesh, mat: Material) -> void:
		cap = p_cap; mode = p_mode
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = cap
		mm.visible_instance_count = 0
		mm.custom_aabb = AABB(Vector3(-1000, -300, -1000), Vector3(2000, 900, 2000))   # never culled (CPU-placed instances)
		buf.resize(cap * 16)
		pos.resize(cap); vel.resize(cap); ax.resize(cap)
		life.resize(cap); maxl.resize(cap); sa.resize(cap); sb.resize(cap); grav.resize(cap); drag.resize(cap)
		c0.resize(cap); c1.resize(cap)
		mmi = MultiMeshInstance3D.new()
		mmi.name = ["Bits", "Chips", "Blobs", "Rings", "Streaks"][mode]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)

	func clear() -> void:
		n = 0
		mm.visible_instance_count = 0
		_drawn = 0

	## life (s), a / b: size from -> to (STREAKS: length, width), colour from -> to, gravity (+ = falls), drag (1/s),
	## axis (CHIPS: spin axis x rate, STREAKS: direction).
	func add(p: Vector3, v: Vector3, l: float, a: float, b: float, col: Color, col_end: Color, g: float, d: float, axis := Vector3.ZERO) -> void:
		if cap <= 0: return
		var i := n
		if n < cap:
			n += 1
		else:
			i = _next % cap; _next += 1; recycled += 1
		pos[i] = p; vel[i] = v; ax[i] = axis
		life[i] = l; maxl[i] = l; sa[i] = a; sb[i] = b; grav[i] = g; drag[i] = d
		c0[i] = col; c1[i] = col_end
		spawned += 1
		peak = maxi(peak, n)

	func _kill(i: int) -> void:
		n -= 1
		if i == n: return
		pos[i] = pos[n]; vel[i] = vel[n]; ax[i] = ax[n]; life[i] = life[n]; maxl[i] = maxl[n]
		sa[i] = sa[n]; sb[i] = sb[n]; grav[i] = grav[n]; drag[i] = drag[n]; c0[i] = c0[n]; c1[i] = c1[n]

	func update(dt: float) -> void:
		if n == 0:
			if _drawn != 0:
				mm.visible_instance_count = 0; _drawn = 0
			return
		var i := 0
		while i < n:
			life[i] -= dt
			if life[i] <= 0.0:
				_kill(i); continue
			if dt > 0.0:
				var v := vel[i]
				v.y -= grav[i] * dt
				if drag[i] > 0.0: v *= maxf(0.0, 1.0 - drag[i] * dt)
				vel[i] = v
				pos[i] += v * dt
			i += 1
		for j in n:
			var k := 1.0 - life[j] / maxl[j]
			var o := j * 16
			var p := pos[j]
			var x := Vector3.RIGHT
			var y := Vector3.UP
			var z := Vector3.BACK
			var c := c0[j]
			match mode:
				BITS:
					var s := lerpf(sa[j], sb[j], k * k)
					x = Vector3(s, 0, 0); y = Vector3(0, s, 0); z = Vector3(0, 0, s)
				CHIPS:
					var s2 := sa[j] * (1.0 if k < 0.7 else (1.0 - k) / 0.3)
					var a := ax[j]
					var rate := a.length()
					var bs := Basis(a / rate, (maxl[j] - life[j]) * rate) if rate > 1e-4 else Basis()
					x = bs.x * s2; y = bs.y * s2; z = bs.z * s2
				BLOBS, RINGS:
					var ke := 1.0 - (1.0 - k) * (1.0 - k)
					var s3 := lerpf(sa[j], sb[j], ke)
					x = Vector3(s3, 0, 0); y = Vector3(0, s3, 0); z = Vector3(0, 0, s3)
					c = c0[j].lerp(c1[j], k)
					c.a *= (1.0 - k * k) if mode == BLOBS else (1.0 - k)
				STREAKS:
					var d := ax[j]
					var side := d.cross(Vector3.UP)
					if side.length_squared() < 1e-4: side = d.cross(Vector3.RIGHT)
					side = side.normalized()
					var w := sb[j]
					x = side * w; y = side.cross(d).normalized() * w; z = d * sa[j] * (1.0 - k * 0.6)
					c.a *= 1.0 - k
			buf[o] = x.x; buf[o + 1] = y.x; buf[o + 2] = z.x; buf[o + 3] = p.x
			buf[o + 4] = x.y; buf[o + 5] = y.y; buf[o + 6] = z.y; buf[o + 7] = p.y
			buf[o + 8] = x.z; buf[o + 9] = y.z; buf[o + 10] = z.z; buf[o + 11] = p.z
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
		mm.buffer = buf
		mm.visible_instance_count = n
		_drawn = n


## Ambient specks drifting around the camera (web backdrop.specks: pollen, snow, embers, petals, bubbles, wisps,
## confetti, dust, stars), one MultiMesh. MID / HIGH only.
class Specks extends MultiMeshInstance3D:
	var count := 0
	var rise := 0.35
	var drift := 0.6
	var t := 0.0
	var pts := PackedVector3Array()
	var ph := PackedFloat32Array()
	var mm: MultiMesh
	var _rng: RandomNumberGenerator

	func _init(p_n: int, p_rng: RandomNumberGenerator) -> void:
		name = "Specks"
		count = p_n
		_rng = p_rng
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = LowPoly.ico(0.09, 0)
		mm.instance_count = count
		mm.custom_aabb = AABB(Vector3(-1000, -300, -1000), Vector3(2000, 900, 2000))
		multimesh = mm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.disable_fog = true
		material_override = m
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pts.resize(count); ph.resize(count)
		for i in count:
			pts[i] = Vector3(_rng.randf_range(-40, 40), _rng.randf_range(0, 24), _rng.randf_range(-40, 40))
			ph[i] = _rng.randf_range(0, 6)
		configure("pollen", 0xfff2a8, [0xfff2a8, 0.35, 0.6], [])

	func configure(_kind: String, col: int, sk: Array, multi: Array) -> void:
		rise = float(sk[1]); drift = float(sk[2])
		for i in count:
			var c: int = int(multi[i % multi.size()]) if not multi.is_empty() else col
			mm.set_instance_color(i, Color.hex((int(c) << 8) | 0xff))

	func update(dt: float, cp: Vector3) -> void:
		t += dt
		for i in count:
			var p := pts[i]
			p.y += rise * dt
			p.x += sin(t * 0.8 + ph[i]) * drift * dt
			p.z += cos(t * 0.6 + ph[i]) * drift * dt
			if p.y > 26.0: p.y = 0.0
			if p.y < 0.0: p.y = 26.0
			if p.x - cp.x > 40.0: p.x -= 80.0
			elif p.x - cp.x < -40.0: p.x += 80.0
			if p.z - cp.z > 40.0: p.z -= 80.0
			elif p.z - cp.z < -40.0: p.z += 80.0
			pts[i] = p
			mm.set_instance_transform(i, Transform3D(Basis(), p))
