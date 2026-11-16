class_name RubbleView
extends Node3D
## Throwable rubble, presentation only (docs/DAMAGE.md "Ledge cling and throwable rubble"): one small box mesh per logical
## chunk the Rubble logic (logic/rubble.gd) owns. A resting chunk sits on the floor, a thrown one tumbles through the air
## and a held one is hidden (the thrower shows it through the toast; nothing is attached to the hand, so the view's cost
## stays one mesh per chunk). The sim decides every position and hit; nothing here touches gameplay or the game's RNG.
##
##   var view := RubbleView.new(); map_node.add_child(view); view.setup(sim)
##   view.update_view()   # per rendered frame, from World.present
##
## Meshes are pooled by chunk id and freed with the map node (World.load_map rebuilds it).

var sim: MatchSim = null
var _nodes := {}                 ## chunk id -> MeshInstance3D
var _spin := {}                  ## chunk id -> Vector3 (visual tumble)
var _mats := {}                  ## colour int -> Material
var _unit: BoxMesh = null
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	name = "RubbleView"
	_rng.randomize()

func setup(p_sim: MatchSim) -> void:
	sim = p_sim

func chunk_count() -> int:
	return _nodes.size()

func update_view() -> void:
	if sim == null or sim.rubble == null:
		for n: MeshInstance3D in _nodes.values():
			if is_instance_valid(n): n.queue_free()
		_nodes.clear(); _spin.clear()
		return
	var live := {}
	for raw: Variant in sim.rubble.chunks:
		var c: Dictionary = raw
		var id := int(c["id"])
		if str(c["state"]) == "held": continue
		live[id] = true
		var node: MeshInstance3D = _nodes.get(id)
		if node == null or not is_instance_valid(node):
			node = _make(c)
			_nodes[id] = node
			_spin[id] = Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-6, 6), _rng.randf_range(-9, 9))
		node.position = Vector3(float(c["x"]), float(c["y"]), float(c["z"]))
		if str(c["state"]) == "fly":
			var spin: Vector3 = _spin.get(id, Vector3.ZERO)
			node.rotation += spin * 0.016
		else:
			node.rotation = Vector3(0.0, float(id) * 1.7, 0.0)
	for id: Variant in _nodes.keys():
		if live.has(int(id)): continue
		var n: MeshInstance3D = _nodes[id]
		if is_instance_valid(n): n.queue_free()
		_nodes.erase(id); _spin.erase(id)

func _make(c: Dictionary) -> MeshInstance3D:
	if _unit == null:
		_unit = BoxMesh.new()
		_unit.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = _unit
	mi.material_override = _mat(int(c.get("color", 0xffffff)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s := float(c.get("size", 0.4))
	mi.scale = Vector3.ONE * s
	add_child(mi)
	return mi

func _mat(color: int) -> Material:
	var key := str(color)
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = MapBuilder.hex(color)
	m.roughness = 0.95
	_mats[key] = m
	return m
