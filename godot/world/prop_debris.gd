class_name PropDebris
extends Node3D
## Breakable props (docs/DESTRUCTIBLE.md), presentation only: a broken prop shatters into small pieces of its own boxes
## that fly out from the hit, bounce, settle on the floor and then sink into the ground and are gone. Decor that stood on
## it (a tree crown, Destruct `crown`) topples over, drops and bursts into pieces of its own colour the same way.
## Nothing here touches the sim: the solid is already gone when the `break` event arrives.
##
##   var debris := PropDebris.new(); map_node.add_child(debris)
##   debris.burst(prop, dir, quality)   # prop = a Destruct.props entry (boxes, bottom, crown...), dir = the hit direction
##
## Pieces are plain MeshInstance3Ds sharing one unit box mesh and one material per colour; they live ~2 s and the total is
## capped (MAX_PIECES), so a whole arena breaking at once stays cheap. Freed with the map node (World.load_map).

const GRAVITY := 20.0
const MAX_PIECES := 240            ## live pieces across every break (older breaks keep theirs, a new one gets fewer)
const PIECE := 0.45                ## target piece edge (m): a box is cut into cells about this size, a random subset flies
const SETTLE_MIN := 1.1            ## seconds a piece tumbles / lies before it starts to sink
const SETTLE_MAX := 1.8
const SINK := 0.7                  ## seconds to sink into the ground and shrink away
const CROWN_FALL := 0.55           ## seconds the crown topples before it bursts

var _pieces: Array = []            ## {node, vel: Vector3, spin: Vector3, half: float, ground: float, t, settle, size: Vector3, rest}
var _crowns: Array = []            ## {node: Node3D pivot, t, axis: Vector3, vy, ground, color: Color, size: Vector3, n}
var _unit: BoxMesh = null
var _mats := {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	name = "PropDebris"
	_rng.randomize()

## Pieces alive now (tests / perf HUD).
func piece_count() -> int:
	return _pieces.size()

func crown_count() -> int:
	return _crowns.size()

## Shatter one broken prop. quality: 0 = LOW (few pieces), 1+ = the full count.
func burst(p: Dictionary, dir: Vector3, quality := 1) -> void:
	var budget := mini(MAX_PIECES - _pieces.size(), 32 if quality >= 1 else 12)
	var bottom := float(p.get("bottom", p.get("y", 0.0)))
	var centre := Vector3(float(p.get("x", 0.0)), bottom + float(p.get("h", 1.0)) * 0.5, float(p.get("z", 0.0)))
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.ZERO
	var boxes: Array = p.get("boxes", [])
	var cells_total := 0
	var plans: Array = []
	for raw: Variant in boxes:
		var b: Dictionary = raw
		var sz := Vector3(float(b["w"]), float(b["h"]), float(b["d"]))
		var n := Vector3i(maxi(1, ceili(sz.x / PIECE)), maxi(1, ceili(sz.y / PIECE)), maxi(1, ceili(sz.z / PIECE)))
		plans.append([b, sz, n])
		cells_total += n.x * n.y * n.z
	var keep := 1.0 if cells_total <= budget else float(budget) / float(maxi(1, cells_total))
	var top := float(p.get("top", bottom + float(p.get("h", 1.0))))
	for plan: Array in plans:
		var b: Dictionary = plan[0]
		var sz: Vector3 = plan[1]
		var n: Vector3i = plan[2]
		var cell := Vector3(sz.x / n.x, sz.y / n.y, sz.z / n.z)
		var o := Vector3(float(b["x"]) - sz.x * 0.5, float(b["y"]), float(b["z"]) - sz.z * 0.5)
		for iy in n.y:
			for ix in n.x:
				for iz in n.z:
					if _pieces.size() >= MAX_PIECES: return
					if keep < 1.0 and _rng.randf() > keep: continue
					var at := o + Vector3((ix + 0.5) * cell.x, (iy + 0.5) * cell.y, (iz + 0.5) * cell.z)
					var size := cell * _rng.randf_range(0.6, 1.0)
					var up := clampf((at.y - bottom) / maxf(0.5, top - bottom), 0.0, 1.0)   # 0 at the foot, 1 at the top
					var out := Vector3(at.x - centre.x, 0.0, at.z - centre.z)
					out = out.normalized() if out.length() > 0.01 else Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
					var vel := out * _rng.randf_range(1.8, 4.2) + flat * _rng.randf_range(1.0, 3.0) * (0.4 + up) \
						+ Vector3(0.0, _rng.randf_range(2.0, 5.0) * (0.5 + up * 0.5), 0.0)
					_add_piece(at, size, _mat(int(b["color"])), vel, bottom)
	var crown: Variant = p.get("crown")
	if crown is MeshInstance3D and is_instance_valid(crown):
		_topple(p, crown as MeshInstance3D, flat, bottom, quality)

func _add_piece(at: Vector3, size: Vector3, mat: Material, vel: Vector3, ground: float) -> void:
	if _unit == null:
		_unit = BoxMesh.new()
		_unit.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = _unit
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = size
	mi.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-PI, PI), _rng.randf_range(-0.3, 0.3))
	add_child(mi)
	_pieces.append({"node": mi, "vel": vel, "spin": Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-6, 6), _rng.randf_range(-9, 9)),
		"half": minf(size.x, minf(size.y, size.z)) * 0.5, "ground": ground, "t": 0.0,
		"settle": _rng.randf_range(SETTLE_MIN, SETTLE_MAX), "size": size, "rest": false})

## The crown (decor that stood on the prop) tips over away from the hit, drops, then bursts into pieces of its colour.
## A copy of its mesh is shown under a pivot at the prop's foot so it rotates about where the trunk stood.
func _topple(p: Dictionary, crown: MeshInstance3D, flat: Vector3, ground: float, quality: int) -> void:
	var foot := Vector3(float(p.get("x", 0.0)), ground, float(p.get("z", 0.0)))
	var pivot := Node3D.new()
	pivot.position = foot
	var copy := MeshInstance3D.new()
	copy.mesh = crown.mesh
	copy.cast_shadow = crown.cast_shadow
	copy.position = -foot             # the crown's vertices are in world space
	pivot.add_child(copy)
	add_child(pivot)
	var away := flat if flat != Vector3.ZERO else Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	var box: AABB = p.get("crown_aabb", AABB(foot, Vector3.ONE))
	_crowns.append({"node": pivot, "t": 0.0, "axis": Vector3.UP.cross(away).normalized(), "vy": 0.0, "ground": ground,
		"color": p.get("crown_color", Color(0.3, 0.6, 0.3)), "box": box, "n": 14 if quality >= 1 else 6})

func _process(delta: float) -> void:
	if _pieces.is_empty() and _crowns.is_empty(): return
	var dt := minf(delta, 0.05)
	var i := _pieces.size() - 1
	while i >= 0:
		if _step_piece(_pieces[i], dt):
			((_pieces[i] as Dictionary)["node"] as Node).queue_free()
			_pieces.remove_at(i)
		i -= 1
	i = _crowns.size() - 1
	while i >= 0:
		if _step_crown(_crowns[i], dt):
			((_crowns[i] as Dictionary)["node"] as Node).queue_free()
			_crowns.remove_at(i)
		i -= 1

## One piece: ballistic + spin until it settles on the floor, then it sinks below the floor while shrinking. True = done.
func _step_piece(q: Dictionary, dt: float) -> bool:
	var node: MeshInstance3D = q["node"]
	if not is_instance_valid(node): return true
	q["t"] = float(q["t"]) + dt
	var t := float(q["t"])
	var settle := float(q["settle"])
	var ground := float(q["ground"])
	var half := float(q["half"])
	if t < settle or (not bool(q["rest"]) and t < settle + 1.5):   # an airborne piece lands before it sinks
		if not bool(q["rest"]):
			var vel: Vector3 = q["vel"]
			vel.y -= GRAVITY * dt
			var pos := node.position + vel * dt
			if pos.y - half < ground:
				pos.y = ground + half
				if absf(vel.y) < 1.2:
					q["rest"] = true
					vel = Vector3.ZERO
				else:
					vel = Vector3(vel.x * 0.55, -vel.y * 0.3, vel.z * 0.55)
					q["spin"] = (q["spin"] as Vector3) * 0.6
			node.position = pos
			q["vel"] = vel
			node.rotation += (q["spin"] as Vector3) * dt
		return false
	if not q.has("sink_t0"): q["sink_t0"] = t
	var k := clampf((t - float(q["sink_t0"])) / SINK, 0.0, 1.0)
	var size: Vector3 = q["size"]
	node.scale = size * (1.0 - k * 0.85)
	node.position.y = ground + half - k * (half * 2.0 + 0.05)   # into the floor
	return k >= 1.0

func _step_crown(c: Dictionary, dt: float) -> bool:
	var node: Node3D = c["node"]
	if not is_instance_valid(node): return true
	c["t"] = float(c["t"]) + dt
	var k := clampf(float(c["t"]) / CROWN_FALL, 0.0, 1.0)
	node.transform.basis = Basis(c["axis"], k * k * 1.25)          # tips over faster and faster
	c["vy"] = float(c["vy"]) - GRAVITY * 0.5 * dt
	node.position.y += float(c["vy"]) * dt
	if k < 1.0: return false
	# burst: pieces of the crown's colour from where it is now
	var box: AABB = c["box"]
	var centre := node.transform * (box.get_center())
	var col: Color = c["color"]
	var mat := _color_mat(col)
	var span := maxf(0.6, maxf(box.size.x, box.size.z) * 0.5)
	for n in int(c["n"]):
		if _pieces.size() >= MAX_PIECES: break
		var off := Vector3(_rng.randf_range(-span, span), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-span, span)) * 0.6
		var s := _rng.randf_range(0.18, 0.34)
		var at := centre + off
		at.y = maxf(at.y, float(c["ground"]) + s)
		_add_piece(at, Vector3(s, s, s), mat, off.normalized() * _rng.randf_range(0.8, 2.2) + Vector3(0, _rng.randf_range(0.5, 2.0), 0),
			float(c["ground"]))
	return true

func _mat(color: int) -> Material:
	return _color_mat(MapBuilder.hex(color))

func _color_mat(col: Color) -> Material:
	var key := col.to_html(false)
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 1.0)
	m.roughness = 0.95
	_mats[key] = m
	return m
