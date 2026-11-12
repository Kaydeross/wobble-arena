extends SceneTree
## Ghost interpolation parity: replays the snapshot stream written by tools/net-interp-reference.js (which runs the
## web game's own netStep lines) through NetMatch.interp and compares every step.
##   godot --headless --path godot --script res://tests/net_interp_test.gd -- /path/to/reference.json

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var ref: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if args.size() > 0 else null
	if not (ref is Dictionary):
		print("FAIL no reference"); quit(1); return
	var dt := float(ref["dt"])
	var steps: Array = ref["steps"]
	var expect: Array = ref["expect"]
	var clock := 0.0
	var g := [0.0, 0.0, 0.0]
	var s: Variant = null
	var rt := 0.0
	var worst := 0.0
	var moved := 0.0
	for i in steps.size():
		if steps[i] is Dictionary:
			var e: Dictionary = NetSnapshot.decode_entry(_entry(steps[i]))
			if e.is_empty(): print("FAIL snapshot rejected at %d" % i); quit(1); return
			s = e; rt = clock
		clock += dt
		if s != null:
			var before: Array = g
			g = NetMatch.interp(g, s, clock, rt, dt)
			moved += absf(g[0] - before[0]) + absf(g[2] - before[2])
		for k in 3:
			worst = maxf(worst, absf(float(g[k]) - float(expect[i][k])))
	print("INTERP steps=%d worst_error=%s moved=%.1f" % [steps.size(), String.num_scientific(worst), moved])
	quit(0 if worst <= 1e-9 and moved > 10.0 else 1)

## The reference's snapshot as an `S` entry (what actually arrives).
func _entry(d: Dictionary) -> Dictionary:
	return {"id": 1, "x": d["x"], "y": d["y"], "z": d["z"], "vx": d["vx"], "vy": d["vy"], "vz": d["vz"], "yaw": 0, "ax": 0, "ay": 0, "az": 1,
		"w": "spatula", "hp": 100, "d": 0, "g": d["g"], "sq": 0, "iv": 0, "lv": 0, "el": 0}
