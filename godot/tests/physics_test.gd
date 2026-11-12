extends SceneTree
## Replays the scripted input from tools/physics-reference.js and compares with the web game's trace
## (movement, status effects stun/down/trap/speed/dash-air/dead, ladders, bounce pads).
## godot --headless --path godot --script res://tests/physics_test.gd -- MAPS_JSON MAP_ID TRACE_JSON [CLASS_JSON] [GRAV]
## GRAV = cfg.grav (FighterPhysics.grav_scale; Moon Drift 0.15, used by tools/test-modes.js).

const DT := 1.0 / 60.0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var maps = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var trace = JSON.parse_string(FileAccess.get_file_as_string(a[2]))
	var map: Dictionary = maps[a[1]]
	var solids := FighterPhysics.solids_from_map(map)
	var pads: Array = map["geometry"]["bouncePads"]
	var st := FighterState.new()
	var f := st.phys
	f.set_map(map, map["geometry"]["ladders"])
	f.can_climb = true
	if a.size() > 3:
		var c: Dictionary = JSON.parse_string(a[3])
		f.speed_mul = c["spd"]; f.accel_mul = c["acc"]; f.air_mul = c["air"]; f.jump_mul = c["jump"]
	if a.size() > 4: f.grav_scale = float(a[4])
	f.place(0.0, 0.01, 0.0)
	var worst := 0.0
	var worst_k := -1
	var first_k := -1
	for k in trace.size():
		var row: Array = trace[k]
		if row[17] is Array:
			f.place(row[17][0], row[17][1], row[17][2]); f.grounded = false
		f.wish_x = row[7]; f.wish_z = row[8]; f.want_jump = row[9] == 1; f.climb_in = row[16]
		if row[10] >= 0: st.stun = row[10]
		if row[14] >= 0: st.dash_air_t = row[14]
		st.down_t = row[11]; st.trap_t = row[12]; st.spd_t = row[13]; st.dead = row[15] == 1
		st.pad_cool -= DT              # Combat.timers
		f.step(DT, solids, st)
		f.bounce_pads(pads, st)
		var err := maxf(maxf(absf(f.px - row[0]), absf(f.py - row[1])), maxf(absf(f.pz - row[2]), maxf(absf(f.vx - row[3]), maxf(absf(f.vy - row[4]), absf(f.vz - row[5])))))
		err = maxf(err, maxf(absf(st.stun - row[18]), maxf(absf(st.dash_air_t - row[19]), absf(st.pad_cool - row[20]))))
		if int(f.grounded) != int(row[6]) or int(not f.ladder.is_empty()) != int(row[21]): err = maxf(err, 1.0)
		if err > 1e-6 and first_k < 0:
			first_k = k
			print("FIRST diff step %d godot p=(%.4f %.4f %.4f) v=(%.4f %.4f %.4f) g=%d lad=%d | js p=(%.4f %.4f %.4f) v=(%.4f %.4f %.4f) g=%d lad=%d" % [k, f.px, f.py, f.pz, f.vx, f.vy, f.vz, int(f.grounded), int(not f.ladder.is_empty()), row[0], row[1], row[2], row[3], row[4], row[5], int(row[6]), int(row[21])])
		if err > worst: worst = err; worst_k = k
	print("PHYSICS steps=%d worst_error=%.9f at step %d" % [trace.size(), worst, worst_k])
	quit(0 if worst < 0.0001 else 1)
