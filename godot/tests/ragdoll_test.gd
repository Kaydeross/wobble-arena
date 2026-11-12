extends SceneTree
## Ragdoll overlay test (docs/RAGDOLL.md): for every class, a classic and a ragdoll wobbler are driven by the same
## scripted states (idle, run, stop, jump + land, swing, kick, hits, topple + get-up, K.O., respawn).
## Checks: the gameplay points read after animate() are bit-identical in both modes (sim untouched); the overlay
## pose is finite and bounded (near the sim position, limbs within length limits); feet stay planted while idle and
## never skate while planted; the weapon grip keeps the sim transform while standing; it steps, collapses and gets
## up. Then a frame-time budget with 8 fighters.
## godot --headless --path godot --script res://tests/ragdoll_test.gd -- CLASSES_JSON

const DT := 1.0 / 60.0
const A_END := (330.0 / 60.0 - 1.5) * 1.1     # where the run ends on its circle
const BUDGET_US := 150.0            # overlay per fighter per frame on the dev machine (iPhone 12 ~3x slower)
var fails: Array[String] = []
var _seen := {}


func _check(ok: bool, msg: String) -> void:
	var key := msg.get_slice(" ", 0) + msg.get_slice(" ", 1) + msg.get_slice(" ", 2)   # one line per kind of failure
	if not ok and not _seen.has(key):
		_seen[key] = true
		fails.append(msg)


static func _fv(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _fx(t: Transform3D) -> bool:
	return _fv(t.origin) and _fv(t.basis.x) and _fv(t.basis.y) and _fv(t.basis.z)


## scripted FighterState for frame k: [state, phase name]
func _state(k: int, cid: String) -> Array:
	var s := {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "class_id": cid,
		"aim": Vector3(0, -0.2, 1), "weapon": "spatula", "swing": -1.0, "kick_t": -1.0, "crouch": 0.0, "hp": 100.0}
	var t := k * DT
	var ph := "idle"
	var stop := Vector3(sin(A_END) * 6.0, 0.0, cos(A_END) * 6.0 - 6.0)
	if k < 90:
		pass
	elif k < 330:                                     # run a circle (speed 6.6), the aim sweeping
		ph = "run"
		var a := (t - 1.5) * 1.1
		s["pos"] = Vector3(sin(a) * 6.0, 0.0, cos(a) * 6.0 - 6.0)
		s["vel"] = Vector3(cos(a), 0.0, -sin(a)) * 6.6
		s["yaw"] = a + PI / 2.0
		s["wish"] = Vector2(cos(a), -sin(a))
		s["aim"] = Vector3(cos(t * 2.0), -0.2, sin(t * 2.0))
	elif k < 370:                                     # stop dead: hips overshoot, feet catch up
		ph = "stop"
		s["pos"] = stop
		s["yaw"] = A_END + PI / 2.0
	elif k < 410:                                     # jump and land hard
		ph = "jump"
		var u := (k - 370) / 40.0
		s["pos"] = stop + Vector3(0, 2.2 * sin(PI * u), 0)
		s["vel"] = Vector3(0, lerpf(9.0, -10.0, u), 0)
		s["grounded"] = false
		s["yaw"] = A_END + PI / 2.0
	elif k < 520:
		ph = "fight"
		s["pos"] = stop
		s["yaw"] = A_END + PI / 2.0
		if k >= 430 and k < 460:
			s["swing"] = (k - 430) / 30.0 * 1.29
		if k >= 470 and k < 510:
			s["kick_t"] = (k - 470) / 40.0
		s["hp"] = 100.0 - (20.0 if k >= 445 else 0.0)
	elif k < 640:                                     # toppled 1 s, then gets up
		ph = "down" if k < 580 else "getup"
		s["pos"] = stop + Vector3((k - 520) * 0.02, 0, 0)
		s["yaw"] = A_END + PI / 2.0
		s["down_t"] = 1.0 - (k - 520) / 60.0 if k < 580 else 0.0
		s["fall_side"] = 1.0
		s["hp"] = 80.0
	elif k < 760:                                     # K.O.
		ph = "dead"
		s["pos"] = stop + Vector3(1.2, 0, 0)
		s["yaw"] = A_END + PI / 2.0
		s["dead"] = true
		s["weapon"] = null
		s["fall_side"] = -1.0
		s["hp"] = 0.0
	else:                                             # respawn far away, idle
		ph = "respawn"
		s["pos"] = Vector3(20.0, 1.0, 20.0)
		s["hp"] = 100.0
	return [s, ph]


func _points(w: Wobbler) -> Array:
	return [w.hand.global_position, w.arm_dir, w.arm.global_position, w.head_mesh.global_position, w.torso.global_position]


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)       # the root is only inside the tree once the loop runs


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var classes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var scene: PackedScene = load("res://actors/wobbler.tscn")
	var nc := 0
	for cid in classes:
		var size := float(classes[cid].get("size", 1.0))
		var wa: Wobbler = scene.instantiate()
		var wb: Wobbler = scene.instantiate()
		root.add_child(wa)
		root.add_child(wb)
		wb.rig_mode = "ragdoll"
		for w: Wobbler in [wa, wb]:
			w.setup(cid, "hoodie", "top", 0x39b5a8)
			w.set_weapon("spatula")
		var idle_move := 0.0
		var skate := 0.0
		var max_pel := {"idle": 0.0, "run": 0.0, "down": 0.0, "dead": 0.0}
		var max_leg := 0.0
		var max_grip_err := 0.0
		var saw_down := false
		var got_up := false
		var steps0 := 0
		var prev_feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
		var prev_planted: Array[bool] = [false, false]
		var mismatch := 0
		for k in 900:
			var sp: Array = _state(k, cid)
			var s: Dictionary = sp[0]
			var ph: String = sp[1]
			for w: Wobbler in [wa, wb]:
				w.apply_state(s)
			if k == 440 or k == 452:
				for w: Wobbler in [wa, wb]:
					w.hit_kick(Vector3(0.8, 0.2, -0.6).normalized(), 14.0)
			var dt := DT if k % 7 else DT * 2.0
			wa.animate(dt)
			wb.animate(dt)
			if k % 50 == 25:                              # a zero-dt present must still read the classic pose
				wb.animate(0.0)
			var pa := _points(wa)
			var pb := _points(wb)
			for i in pa.size():
				if pa[i] != pb[i]:
					mismatch += 1
			var grip := wb.arm.transform * wb.hand.transform
			wb.overlay(dt)
			var r := wb.rag
			var pos: Vector3 = s["pos"]
			var ok := _fx(wb.rig.transform) and _fx(wb.body.transform) and _fx(wb.neck.transform) and _fx(wb.arm.transform) \
				and _fx(wb.arm_l.transform) and _fx(wb.legs[0].transform) and _fx(wb.legs[1].transform) and _fx(wb.hand.transform) \
				and _fv(r.pelvis_w) and _fv(r.head_w) and _fv(r.feet[0]) and _fv(r.feet[1]) and _fv(r.hand_off)
			if not ok:
				_check(false, "%s non-finite at frame %d (%s)" % [cid, k, ph])
				break
			var pel := Vector2(r.pelvis_w.x - pos.x, r.pelvis_w.z - pos.z).length()
			var bucket := "down" if ph == "down" else ("dead" if ph == "dead" else ("run" if ph == "run" else "idle"))
			max_pel[bucket] = maxf(max_pel[bucket], pel)
			_check(r.head_w.distance_to(pos) < 3.0 * size, "%s head far from sim at %d: %s" % [cid, k, r.head_w - pos])
			_check(absf(r.hand_off.distance_to(r.shoulder_off_w) - 0.78 * size) < 1e-3, "%s off arm length at %d" % [cid, k])
			_check(r.arm_k > 0.2 and r.arm_k < 2.0, "%s aim arm stretch %f at %d" % [cid, r.arm_k, k])   # runaway check
			var sl := wb.arm_sleeve.basis.get_scale().y
			_check(sl > 0.45 / 0.85 - 1e-4 and sl < 1.3 / 0.85 + 1e-4, "%s sleeve length %f at %d" % [cid, sl, k])
			if r.down_k == 0.0 and ph != "jump":
				for i in 2:
					max_leg = maxf(max_leg, r.leg_k[i])
					_check(r.feet[i].y >= pos.y - 1e-3, "%s foot under the floor at %d" % [cid, k])
				if r.aim_free == 0.0:
					max_grip_err = maxf(max_grip_err, (wb.arm.transform * wb.hand.transform).origin.distance_to(grip.origin))
			if ph == "idle" and k > 60 and k < 90 or ph == "respawn" and k > 840:
				for i in 2:
					idle_move = maxf(idle_move, r.feet[i].distance_to(prev_feet[i]))
			for i in 2:
				var planted := r.step_t[i] == RagdollRig.PLANTED
				if planted and prev_planted[i] and r.down_k == 0.0 and k != 760:
					skate = maxf(skate, Vector2(r.feet[i].x - prev_feet[i].x, r.feet[i].z - prev_feet[i].z).length())
				prev_planted[i] = planted
				prev_feet[i] = r.feet[i]
			if ph == "run" and k == 329:
				steps0 = r.steps
			if ph == "down" and k == 575:
				saw_down = r.down_k == 1.0 and r.head_w.y - pos.y < 0.9 * size
			if k == 639:
				got_up = r.down_k == 0.0 and r.head_w.y - pos.y > 1.5 * size
		_check(mismatch == 0, "%s gameplay points differ between classic and ragdoll (%d)" % [cid, mismatch])
		_check(idle_move < 1e-5, "%s feet moved while idle: %f" % [cid, idle_move])
		_check(skate < 1e-5, "%s planted foot skated: %f" % [cid, skate])
		_check(steps0 >= 12, "%s too few steps while running: %d" % [cid, steps0])
		_check(max_pel["idle"] < 0.5 * size and max_pel["run"] < 0.6 * size, "%s hips strayed standing: %s" % [cid, max_pel])
		_check(max_pel["down"] < 1.0 * size and max_pel["dead"] < 1.0 * size, "%s body strayed while down: %s" % [cid, max_pel])
		_check(max_leg < 1.25, "%s leg over-stretched: %f" % [cid, max_leg])
		_check(max_grip_err < 1e-4, "%s weapon grip left the sim hand: %f" % [cid, max_grip_err])
		_check(saw_down, "%s never collapsed" % cid)
		_check(got_up, "%s never got up" % cid)
		print("RAGDOLL %-8s steps=%d skate=%.6f idle=%.6f pel=%.2f/%.2f/%.2f leg=%.2f grip=%.6f mismatch=%d" % [cid, steps0, skate, idle_move,
			max_pel["run"], max_pel["down"], max_pel["dead"], max_leg, max_grip_err, mismatch])
		wa.free()
		wb.free()
		nc += 1
	_budget(scene)
	for f in fails:
		print("FAIL ", f)
	print("RAGDOLL_RESULT classes=%d fails=%d" % [nc, fails.size()])
	quit(0 if fails.is_empty() else 1)


## 8 fighters running, fighting and falling: classic animate vs the overlay, microseconds per fighter per frame.
func _budget(scene: PackedScene) -> void:
	var ws: Array[Wobbler] = []
	for i in 8:
		var w: Wobbler = scene.instantiate()
		root.add_child(w)
		w.rig_mode = "ragdoll"
		w.setup("wobbler", "none", "none", 0x39b5a8)
		ws.append(w)
	var t_cl := 0
	var t_ov := 0
	var n := 0
	for k in 900:
		for i in 8:
			var s: Dictionary = _state((k + i * 97) % 900, "wobbler")[0]
			s["pos"] += Vector3(i * 3.0, 0, 0)
			var w := ws[i]
			var t0 := Time.get_ticks_usec()
			w.apply_state(s)
			w.animate(DT)
			var t1 := Time.get_ticks_usec()
			w.overlay(DT)
			var t2 := Time.get_ticks_usec()
			if k >= 60:
				t_cl += t1 - t0
				t_ov += t2 - t1
				n += 1
	var cl := float(t_cl) / n
	var ov := float(t_ov) / n
	print("RAGDOLL_BUDGET classic=%.1fus overlay=%.1fus per fighter-frame; 8 fighters: %.2f ms/frame (budget overlay < %.0fus)" % [cl, ov, (cl + ov) * 8.0 / 1000.0, BUDGET_US])
	_check(ov < BUDGET_US, "overlay too slow: %.1f us per fighter-frame" % ov)
	for w in ws:
		w.free()
