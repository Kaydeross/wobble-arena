extends SceneTree
## Ghost interpolation parity and buffer tests (WP 1.0-B).
## 1. Replays the snapshot stream written by tools/net-interp-reference.js (which runs the web game's own netStep
##    lines) through NetMatch.interp and compares every step: that function is still the <= 0.2 s fallback.
## 2. Exercises SnapshotBuffer, the bounded 100 ms interpolation buffer the guest now draws remote fighters from.
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
	if worst > 1e-9 or moved <= 10.0:
		print("FAIL extrapolation parity")
		quit(1); return
	var bad := _buffer_tests()
	if bad != "":
		print("FAIL " + bad)
		quit(1); return
	print("BUFFER bounded_interpolation fallback_no_backwards ok")
	quit(0)

## The reference's snapshot as an `S` entry (what actually arrives).
func _entry(d: Dictionary) -> Dictionary:
	return {"id": 1, "x": d["x"], "y": d["y"], "z": d["z"], "vx": d["vx"], "vy": d["vy"], "vz": d["vz"], "yaw": 0, "ax": 0, "ay": 0, "az": 1,
		"w": "spatula", "hp": 100, "d": 0, "g": d["g"], "sq": 0, "iv": 0, "lv": 0, "el": 0}

## SnapshotBuffer acceptance tests: interpolation between two snapshots, the bounded history, the hold before the
## first pair, the late/out-of-order drop and the <=0.2 s extrapolation fallback signal. Returns "" when all pass.
func _buffer_tests() -> String:
	# 1. interpolation used when the buffer has a snapshot on both sides of render_time = now - DELAY
	var b := SnapshotBuffer.new()
	if not b.push(0.0, {"x": 0.0, "y": 0.0, "z": 0.0}) or not b.push(0.1, {"x": 10.0, "y": 2.0, "z": -4.0}):
		return "snapshot push rejected"
	var p := b.sample(0.15)                                   # render_t 0.05: halfway between the pair
	if p.is_empty() or absf(float(p[0]) - 5.0) > 1e-6 or absf(float(p[1]) - 1.0) > 1e-6 or absf(float(p[2]) + 2.0) > 1e-6:
		return "buffer did not interpolate the pair: %s" % [p]
	# 2. bounded: the history never grows past MAX, however many snapshots arrive
	var big := SnapshotBuffer.new()
	for i in 500:
		big.push(i * 0.02, {"x": float(i), "y": 0.0, "z": 0.0})
	if big.size() != SnapshotBuffer.MAX:
		return "buffer holds %d snapshots (want %d)" % [big.size(), SnapshotBuffer.MAX]
	# 3. before the first pair brackets render_time the earliest position is held (no backwards jump at a rejoin)
	var early := SnapshotBuffer.new()
	early.push(1.0, {"x": 3.0, "y": 0.5, "z": -2.0})
	var hold := early.sample(1.05)
	if hold.is_empty() or absf(float(hold[0]) - 3.0) > 1e-6:
		return "buffer did not hold the earliest snapshot: %s" % [hold]
	# 4. late / out-of-order snapshots are dropped and can never move the drawn position backwards
	var stream := SnapshotBuffer.new()
	var last_x := -INF
	for i in 200:
		var t := i * (1.0 / 30.0)
		if not stream.push(t, {"x": t, "y": 0.0, "z": 0.0}):
			return "ordered snapshot rejected at %d" % i
		if i == 100 and stream.push(t - 0.01, {"x": -100.0, "y": 0.0, "z": 0.0}):
			return "late snapshot was accepted"
		var at := stream.sample(t + 0.05)                    # render_time sits between the previous and newest snapshot
		if at.is_empty():
			return "buffer did not bracket the render time at %d" % i
		if float(at[0]) < last_x - 1e-9:
			return "late snapshot moved the ghost backwards at %d" % i
		last_x = maxf(last_x, float(at[0]))
	if absf(last_x - (199.0 * (1.0 / 30.0) - 0.05)) > 1e-6:
		return "buffered position drifted (%.6f)" % last_x
	# 5. a late / missing snapshot asks for the fallback ([] = extrapolate) and NetMatch.interp caps it at 0.2 s
	if not stream.sample(100.0).is_empty():
		return "a stale buffer should ask for the extrapolation fallback"
	var e := {"x": 0.0, "y": 0.0, "z": 0.0, "vx": 1.0, "vy": 0.0, "vz": 0.0, "g": 1, "rt": 0.0}
	var pos := [0.0, 0.0, 0.0]
	for i in 400:                                             # ~3.3 s without snapshots
		pos = NetMatch.interp(pos, e, 0.3 + i / 120.0, 0.0, 1.0 / 120.0)
	if float(pos[0]) > 0.200001 or float(pos[0]) < 0.199:
		return "extrapolation fallback is not capped at %.3f s: x=%.6f" % [NetMatch.PREDICT_MAX, pos[0]]
	# 6. malformed entries are refused, not crashed on
	if SnapshotBuffer.new().push(0.0, {"x": "bad", "z": 0.0}):
		return "a malformed snapshot was accepted"
	if not SnapshotBuffer.new().sample(1.0).is_empty():
		return "an empty buffer returned a position"
	return ""
