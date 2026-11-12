extends SceneTree
## WeaponModels test: every weapon key in shared/weapons.json builds a non-empty model with a sane bounding box and the
## Tip marker the JS records (flame, net, revolver, mammoth); an unknown key gives the grey block; every weapon is
## equipped on a Wobbler for a few frames.
## godot --headless --path godot --script res://tests/weapon_models_test.gd -- WEAPONS_JSON

const TIP_KEYS := ["flame", "net", "revolver", "mammoth"]
var fails: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func _count_meshes(n: Node) -> int:
	var k := 1 if n is MeshInstance3D and (n as MeshInstance3D).mesh != null else 0
	for c in n.get_children():
		k += _count_meshes(c)
	return k


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var keys: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0])).keys()
	_check(keys.size() == WeaponModels.KEYS.size(), "weapons.json has %d keys, WeaponModels.KEYS %d" % [keys.size(), WeaponModels.KEYS.size()])
	var w: Wobbler = preload("res://actors/wobbler.tscn").instantiate()
	root.add_child(w)
	var states := {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": Vector3(0, -0.5, 0.8)}
	for key in keys:
		_check(WeaponModels.KEYS.has(key), "%s missing from WeaponModels.KEYS" % key)
		var m := WeaponModels.build(key)
		var n := _count_meshes(m)
		var bb := WeaponModels.bounds(m)
		var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		_check(n >= 3 or key == "bat" or key == "blower", "%s: only %d meshes" % [key, n])
		_check(n > 0, "%s: empty" % key)
		_check(longest >= 0.5 and longest <= 4.0, "%s: bbox longest side %.2f out of range" % [key, longest])
		_check(bb.position.y > -3.2 and bb.end.y < 1.5, "%s: bbox y %.2f..%.2f outside the hand's reach" % [key, bb.position.y, bb.end.y])
		_check(m.has_node("Tip") == (key in TIP_KEYS), "%s: Tip marker mismatch" % key)
		var generic := WeaponModels.build(key)
		_check(generic.get_child_count() == m.get_child_count(), "%s: build not deterministic" % key)
		generic.free()
		m.free()
		w.set_weapon(key)
		for f in 5:
			w.apply_state(states)
			w.animate(1.0 / 60.0)
		_check(w.weapon == key, "%s: set_weapon did not stick" % key)
	var u := WeaponModels.build("no_such_weapon")
	_check(u.get_child_count() == 2, "unknown key should give the 2-block placeholder")
	u.free()
	print("WEAPONS checked=%d" % keys.size())
	for f in fails:
		print("FAIL ", f)
	print("WEAPONS_RESULT fails=%d" % fails.size())
	quit(0 if fails.is_empty() else 1)
