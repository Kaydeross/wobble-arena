extends SceneTree
## Wobbler (visual) smoke test: builds every class with outfits and hats, drives apply_state/animate through a scripted
## sequence (run, jump, land, swing, kick, crouch, hits, knock-down, KO, trapped, invulnerable), and checks that nothing
## leaks, every pose value stays finite and the class proportions match shared/classes.json.
## godot --headless --path godot --script res://tests/wobbler_test.gd -- CLASSES_JSON

const FRAMES := 900
var fails: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func _finite_v(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _finite_b(b: Basis) -> bool:
	return _finite_v(b.x) and _finite_v(b.y) and _finite_v(b.z)


func _count_nodes(n: Node) -> int:
	var k := 1
	for ch in n.get_children():
		k += _count_nodes(ch)
	return k


## scripted FighterState for frame k (60 Hz)
func _state(k: int, cid: String) -> Dictionary:
	var t := k / 60.0
	var a := t * 1.3
	var s := {"pos": Vector3(sin(a) * 4.0, 0.0, cos(a) * 4.0), "yaw": a + PI / 2, "grounded": true, "class_id": cid,
		"aim": Vector3(cos(t), -0.3, sin(t)), "weapon": "spatula", "swing": -1.0, "kick_t": -1.0, "crouch": 0.0}
	s["vel"] = Vector3(cos(a), 0.0, -sin(a)) * 5.2
	var ph := k % 450
	if ph >= 60 and ph < 100:                          # jump: up, then falling fast, then land
		var u := (ph - 60) / 40.0
		s["grounded"] = false
		s["vel"].y = lerpf(8.0, -9.0, u)
		s["pos"].y = 2.0 * sin(PI * u)
	elif ph >= 120 and ph < 150:
		s["swing"] = (ph - 120) / 30.0 * 1.29
	elif ph >= 160 and ph < 200:
		s["kick_t"] = (ph - 160) / 40.0
	elif ph >= 210 and ph < 240:
		s["crouch"] = 1.0
		s["vel"] = Vector3.ZERO
		s["flash"] = 0.12 * (1.0 - (ph - 210) / 30.0)
	elif ph >= 250 and ph < 300:
		s["down_t"] = 1.0
		s["vel"] = Vector3.ZERO
	elif ph >= 300 and ph < 370:
		s["dead"] = true
		s["weapon"] = null
		s["vel"] = Vector3.ZERO
	elif ph >= 370 and ph < 400:
		s["trap"] = true
	elif ph >= 400:
		s["invuln"] = true
		s["weapon"] = "ak" if ph < 420 else "spatula"   # a gun built on first equip
	return s


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var classes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var skins := ["none", "hoodie", "skater", "chef", "suit", "sporty", "robot"]   # robot: colours only (no builder yet)
	var hats := ["none", "party", "top", "crown", "prop", "halo", "viking"]
	var scene: PackedScene = load("res://actors/wobbler.tscn")
	var ci := 0
	for cid in classes:
		var c: Dictionary = classes[cid]
		var w: Wobbler = scene.instantiate()
		root.add_child(w)
		w.setup(cid, skins[ci % skins.size()], hats[ci % hats.size()], 0x39b5a8)
		w.set_weapon("spatula")
		w.set_weapon(null)
		w.set_weapon("spatula")
		# proportions from classes.json
		var wide: float = c.get("wide", 1.0)
		var deep := 1.0 + (wide - 1.0) * 0.5
		_check(is_equal_approx(w.neck.scale.x, c.get("head", 1.0)), "%s head scale %s" % [cid, w.neck.scale])
		_check(w.torso.scale.is_equal_approx(Vector3(wide, 1, deep)), "%s torso scale %s" % [cid, w.torso.scale])
		_check(is_equal_approx(w.arm_l.position.x, 0.52 * wide) and is_equal_approx(w.shoulder.position.x, -0.52 * wide), "%s shoulders" % cid)
		w.apply_state({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "grounded": true})
		for i in 5:
			w.animate(1.0 / 60.0)
		var sz: float = c.get("size", 1.0)
		_check(absf(w.rig.basis.get_scale().y - sz) < 1e-3 and absf(w.rig.basis.get_scale().x - sz) < 1e-3, "%s size %s want %s" % [cid, w.rig.basis.get_scale(), sz])
		_check(absf(w.neck.basis.get_scale().x - float(c.get("head", 1.0))) < 1e-6, "%s neck pose scale" % cid)
		if c.has("skin"):
			var want := Color.hex(int(c["skin"]) << 8 | 0xff)
			_check((w.head_mesh.material_override as StandardMaterial3D).albedo_color.is_equal_approx(want), "%s skin tint" % cid)
		# swapping looks must not leak nodes or materials
		var nodes0 := _count_nodes(w)
		var mats0 := w._mats.size()
		for k in 6:
			w.set_skin(skins[(ci + k + 1) % skins.size()])
			w.set_hat(hats[(ci + k + 2) % hats.size()])
			w.set_class(classes.keys()[(ci + k) % classes.size()])
		w.setup(cid, skins[ci % skins.size()], hats[ci % hats.size()], 0x39b5a8)
		_check(_count_nodes(w) == nodes0, "%s nodes after look swaps %d != %d" % [cid, _count_nodes(w), nodes0])
		_check(w._mats.size() == mats0, "%s materials after look swaps %d != %d" % [cid, w._mats.size(), mats0])
		# scripted states
		var nodes1 := _count_nodes(w)
		var max_lean := 0.0
		var saw_flash := false
		var nodes_mid := -1
		for k in FRAMES:
			w.apply_state(_state(k, cid))
			if k % 97 == 50:
				w.hit_kick(Vector3(sin(k), 0.3, cos(k)).normalized(), 14.0)
			w.animate(1.0 / 60.0 if k % 5 else 1.0 / 30.0)
			max_lean = maxf(max_lean, absf(w.lean.x) + absf(w.lean.y))
			saw_flash = saw_flash or w._flash_k > 0.05
			if k == 449:
				nodes_mid = _count_nodes(w)
			var ok := _finite_v(w.rig.position) and _finite_b(w.rig.basis) and _finite_b(w.body.basis) and _finite_b(w.neck.basis) \
				and _finite_b(w.arm.basis) and _finite_v(w.arm.position) and _finite_v(w.arm_dir) and _finite_b(w.legs[0].basis) \
				and _finite_b(w.legs[1].basis) and _finite_b(w.arm_l.basis) and is_finite(w.lean.x + w.lean.y + w.head.x + w.head.y + w.fall_a)
			if not ok:
				_check(false, "%s non-finite pose at frame %d" % [cid, k])
				break
		# the AK (holder + its WeaponModels tree) is built once on first equip, then nothing else may appear
		var ak := WeaponModels.build("ak")
		var ak_nodes := 1 + _count_nodes(ak)
		ak.free()
		_check(nodes_mid == nodes1 + ak_nodes and _count_nodes(w) == nodes_mid, "%s nodes during animation %d -> %d -> %d" % [cid, nodes1, nodes_mid, _count_nodes(w)])
		_check(absf(w.arm_dir.length() - 1.0) < 1e-6, "%s arm_dir not unit" % cid)
		_check(max_lean > 0.05 and max_lean < 5.0, "%s lean range %f" % [cid, max_lean])
		_check(saw_flash, "%s hit flash never lit" % cid)
		print("WOBBLER %-8s nodes=%d meshes=%d mats=%d max_lean=%.3f ok" % [cid, _count_nodes(w), w.mesh_count(), w._mats.size(), max_lean])
		w.free()
		ci += 1
	for f in fails:
		print("FAIL ", f)
	print("WOBBLER_RESULT classes=%d fails=%d" % [ci, fails.size()])
	quit(0 if fails.is_empty() else 1)
