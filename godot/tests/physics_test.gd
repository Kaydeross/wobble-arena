extends SceneTree
## Replays the scripted input from tools/physics-reference.js and compares with the web game's trace.
## godot --headless --path godot --script res://tests/physics_test.gd -- MAPS_JSON MAP_ID TRACE_JSON

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var maps = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var trace = JSON.parse_string(FileAccess.get_file_as_string(a[2]))
	var solids := FighterPhysics.solids_from_map(maps[a[1]])
	var f := FighterPhysics.new()
	if a.size() > 3:
		var c: Dictionary = JSON.parse_string(a[3])
		f.speed_mul = c["spd"]; f.accel_mul = c["acc"]; f.air_mul = c["air"]; f.jump_mul = c["jump"]
	f.place(0.0, 0.01, 0.0)
	var worst := 0.0
	var worst_k := -1
	var first_k := -1
	for k in trace.size():
		var row: Array = trace[k]
		f.wish_x = row[7]; f.wish_z = row[8]; f.want_jump = row[9] == 1
		f.step(1.0 / 60.0, solids)
		var err := maxf(maxf(absf(f.px - row[0]), absf(f.py - row[1])), maxf(absf(f.pz - row[2]), maxf(absf(f.vx - row[3]), maxf(absf(f.vy - row[4]), absf(f.vz - row[5])))))
		if int(f.grounded) != int(row[6]): err = maxf(err, 1.0)
		if err > 1e-6 and first_k < 0:
			first_k = k
			print("FIRST diff step %d godot p=(%.4f %.4f %.4f) v=(%.4f %.4f %.4f) g=%d | js p=(%.4f %.4f %.4f) v=(%.4f %.4f %.4f) g=%d" % [k, f.px, f.py, f.pz, f.vx, f.vy, f.vz, int(f.grounded), row[0], row[1], row[2], row[3], row[4], row[5], int(row[6])])
		if err > worst: worst = err; worst_k = k
	print("PHYSICS steps=%d worst_error=%.9f at step %d" % [trace.size(), worst, worst_k])
	quit(0 if worst < 0.0001 else 1)
