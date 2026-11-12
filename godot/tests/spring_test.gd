extends SceneTree
## Replays the scripted force/target sequence from tools/test-spring.js through Spring2 and compares with the web trace.
## godot --headless --path godot --script res://tests/spring_test.gd -- TRACE_JSON
## Trace rows: [op, args..., x, y, vx, vy] with op 0 = step(dt, k, zeta, fx, fy, tx, ty), op 1 = kick(x, y).

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var trace = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var sp := Spring2.new()
	var worst := 0.0
	var worst_k := -1
	for k in trace.size():
		var r: Array = trace[k]
		var n := r.size()
		if int(r[0]) == 0:
			sp.step(r[1], r[2], r[3], r[4], r[5], r[6], r[7])
		else:
			sp.kick(r[1], r[2])
		var err := maxf(maxf(absf(sp.x - r[n - 4]), absf(sp.y - r[n - 3])), maxf(absf(sp.vx - r[n - 2]), absf(sp.vy - r[n - 1])))
		if err > worst:
			worst = err
			worst_k = k
	print("SPRING ops=%d worst_error=%.12f at op %d" % [trace.size(), worst, worst_k])
	quit(0 if worst < 1e-6 else 1)
