extends SceneTree
## Ragdoll overlay test (docs/RAGDOLL.md): for every class, a classic and a ragdoll wobbler are driven by the same
## scripted states (idle, run, stop, jump + land, swing, kick, hits, topple + get-up, K.O., respawn).
## Checks: the gameplay points read after animate() are bit-identical in both modes (sim untouched); the overlay
## pose is finite and bounded (near the sim position, limbs within length limits); feet stay planted while idle and
## never skate while planted; the weapon grip keeps the sim transform while standing; it steps, collapses and gets
## up. M0 leg wobble (docs/RAGDOLL.md): leg_wobble = 0 reproduces the pre-M0 pose digest bit for bit, > 0 changes the
## legs, the same seed+frames replay exactly, different seeds differ, planted soles never leave the floor, the
## Settings default + live change work. Then a frame-time budget with 8/10 fighters.
## godot --headless --path godot --script res://tests/ragdoll_test.gd -- CLASSES_JSON

const DT := 1.0 / 60.0
const A_END := (330.0 / 60.0 - 1.5) * 1.1     # where the run ends on its circle
const BUDGET_US := 150.0            # overlay per fighter per frame on the dev machine (iPhone 12 ~3x slower)
## SHA-256 of the rendered leg transforms over DIGEST_FRAMES of the scripted states, captured from the build BEFORE
## the M0 leg wobble was added: leg_wobble = 0 must reproduce it exactly (bit-identical regression).
## SHA-256 of the leg pose at `leg_wobble = 0` over the 480 scripted frames, captured from the build before M0. The
## transform maths differs in the last bits between platforms (macOS vs Linux CI), so the digest is platform-scoped:
## macOS was captured from the pre-M0 build; Linux is pinned from the first Linux CI run of this test (a pre-M0 Linux
## build is not available here). A platform without an entry skips only the exact-digest check; determinism, planting and
## the zero/one separation checks still run everywhere.
const ZERO_DIGEST := {
	"macOS": "00cb48fb5026807c00be8e2497c392aad40ec709df77bbf19d91cbab8d1b2535",
	"Linux": "323fea8a14b5dd5d48a4e21ebd185d2c733ef9936713a7cf1196ee2065a26422",
}
const DIGEST_FRAMES := 480
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


# ============================== M0 leg wobble (docs/RAGDOLL.md) ==============================

## A ragdoll wobbler with a pinned gait personality (leg_wobble 0 = the pre-M0 pose).
func _new_wobbler(scene: PackedScene, seed_pin: int, wobble: float) -> Wobbler:
	var w: Wobbler = scene.instantiate()
	root.add_child(w)
	w.rig_mode = "ragdoll"
	w.setup("wobbler", "hoodie", "top", 0x39b5a8)
	w.set_weapon("spatula")
	w.leg_wobble = wobble
	w.gait_seed = seed_pin
	return w


func _hash_v(h: HashingContext, v: Vector3) -> void:
	var a := PackedFloat64Array([v.x, v.y, v.z])
	h.update(a.to_byte_array())


func _hash_xf(h: HashingContext, t: Transform3D) -> void:
	_hash_v(h, t.origin)
	_hash_v(h, t.basis.x)
	_hash_v(h, t.basis.y)
	_hash_v(h, t.basis.z)


func _hash_b(h: HashingContext, b: Basis) -> void:
	_hash_v(h, b.x)
	_hash_v(h, b.y)
	_hash_v(h, b.z)


## The fixed state script the pre-M0 ZERO_DIGEST was captured with: locomotion only (hp constant, so the hit kicks
## at frames 440/452 are deterministic), same dt pattern as the main loop.
func _digest_state(k: int) -> Dictionary:
	var s := {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "class_id": "wobbler",
		"aim": Vector3(0, -0.2, 1), "weapon": "spatula", "swing": -1.0, "kick_t": -1.0, "crouch": 0.0, "hp": 100.0}
	var t := k * DT
	var stop := Vector3(sin(A_END) * 6.0, 0.0, cos(A_END) * 6.0 - 6.0)
	if k < 90:
		pass
	elif k < 330:
		var a := (t - 1.5) * 1.1
		s["pos"] = Vector3(sin(a) * 6.0, 0.0, cos(a) * 6.0 - 6.0)
		s["vel"] = Vector3(cos(a), 0.0, -sin(a)) * 6.6
		s["yaw"] = a + PI / 2.0
		s["wish"] = Vector2(cos(a), -sin(a))
		s["aim"] = Vector3(cos(t * 2.0), -0.2, sin(t * 2.0))
	elif k < 370:
		s["pos"] = stop
		s["yaw"] = A_END + PI / 2.0
	elif k < 410:
		var u := (k - 370) / 40.0
		s["pos"] = stop + Vector3(0, 2.2 * sin(PI * u), 0)
		s["vel"] = Vector3(0, lerpf(9.0, -10.0, u), 0)
		s["grounded"] = false
		s["yaw"] = A_END + PI / 2.0
	else:
		s["pos"] = stop
		s["yaw"] = A_END + PI / 2.0
		if k >= 430 and k < 460:
			s["swing"] = (k - 430) / 30.0 * 1.29
	return s


## SHA-256 of the rendered leg presentation (leg nodes + foot blocks) over the fixed script; the M0 regression probe.
func _leg_digest(w: Wobbler) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for k in DIGEST_FRAMES:
		w.apply_state(_digest_state(k))
		if k == 440 or k == 452:
			w.hit_kick(Vector3(0.8, 0.2, -0.6).normalized(), 14.0)
		var dt := DT if k % 7 else DT * 2.0
		w.animate(dt)
		w.overlay(dt)
		_hash_xf(h, w.legs[0].transform)
		_hash_xf(h, w.legs[1].transform)
		_hash_b(h, w.foot_meshes[0].basis)
		_hash_b(h, w.foot_meshes[1].basis)
	return h.finish().hex_encode()


## Largest visible leg difference between two wobblers (leg node origins/basis and foot block basis).
static func _leg_delta(a: Wobbler, b: Wobbler) -> float:
	var d := 0.0
	for i in 2:
		d = maxf(d, (a.legs[i].transform.origin - b.legs[i].transform.origin).length())
		d = maxf(d, (a.legs[i].basis.y - b.legs[i].basis.y).length())
		d = maxf(d, (a.foot_meshes[i].basis.y - b.foot_meshes[i].basis.y).length())
		d = maxf(d, (a.foot_meshes[i].basis.z - b.foot_meshes[i].basis.z).length())
	return d


## Wobble checks: 0 = the old pose bit for bit, > 0 visibly changes the legs, seeded variety, determinism, feet
## planted (no y-drift, no skate) and the same gameplay points as before.
func _wobble_checks(scene: PackedScene) -> void:
	var w0 := _new_wobbler(scene, 0x51A7, 0.0)
	var d0 := _leg_digest(w0)
	var zero_expected: String = str(ZERO_DIGEST.get(OS.get_name(), ""))
	if zero_expected == "":
		print("RAGDOLL_WOBBLE no zero-digest baseline for %s; exact pre-M0 pose check skipped here" % OS.get_name())
		_check(d0 == _leg_digest(_new_wobbler(scene, 0x51A7, 0.0)), "leg_wobble 0 did not replay exactly")
	else:
		_check(d0 == zero_expected, "leg_wobble 0 is not the pre-M0 pose: %s != %s" % [d0, zero_expected])
	var w1 := _new_wobbler(scene, 0x51A7, 1.0)
	var d1 := _leg_digest(w1)
	_check(d1 != d0, "leg_wobble 1 rendered the same legs as 0")
	var w1b := _new_wobbler(scene, 0x51A7, 1.0)
	_check(_leg_digest(w1b) == d1, "same seed+frames did not replay exactly")
	var w2 := _new_wobbler(scene, 0x77C3, 1.0)
	var d2 := _leg_digest(w2)
	_check(d2 != d1, "different seeds rendered identical legs")
	# lockstep pairs: same seed identical every frame, different seeds apart, 0 vs 1 apart, soles on the floor
	var sa := _new_wobbler(scene, 0x1234, 1.0)
	var sb := _new_wobbler(scene, 0x1234, 1.0)
	var sc := _new_wobbler(scene, 0x9999, 1.0)
	var sz := _new_wobbler(scene, 0x1234, 0.0)
	var same_bad := 0
	var diff_seed := 0.0
	var vs_zero := 0.0
	var foot_err := 0.0
	var skate := 0.0
	var prev: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var prev_planted: Array[bool] = [false, false]
	for k in 360:
		var s: Dictionary = _state(k, "wobbler")[0]
		var dt := DT if k % 7 else DT * 2.0
		for w: Wobbler in [sa, sb, sc, sz]:
			w.apply_state(s)
			w.animate(dt)
			w.overlay(dt)
		for i in 2:
			if sa.legs[i].transform != sb.legs[i].transform or sa.foot_meshes[i].basis != sb.foot_meshes[i].basis:
				same_bad += 1
		diff_seed = maxf(diff_seed, _leg_delta(sa, sc))
		vs_zero = maxf(vs_zero, _leg_delta(sa, sz))
		var pos: Vector3 = s["pos"]
		for i in 2:
			var planted: bool = sa.rag.step_t[i] == RagdollRig.PLANTED and sa.rag.down_k == 0.0
			if planted:
				foot_err = maxf(foot_err, absf(sa.rag.feet[i].y - pos.y))
				if prev_planted[i]:
					skate = maxf(skate, Vector2(sa.rag.feet[i].x - prev[i].x, sa.rag.feet[i].z - prev[i].z).length())
				prev[i] = sa.rag.feet[i]
			prev_planted[i] = planted
	_check(same_bad == 0, "same seed did not reproduce the same leg pose in lockstep (%d components)" % same_bad)
	_check(diff_seed > 0.01, "two seeds at the same phase share one leg pose (delta %f)" % diff_seed)
	_check(vs_zero > 0.01, "leg_wobble 1 does not change the legs vs 0 (delta %f)" % vs_zero)
	_check(foot_err <= 1e-6, "planted sole left the floor by %f" % foot_err)
	_check(skate <= 1e-5, "planted sole skated with wobble on: %f" % skate)
	print("RAGDOLL_WOBBLE zero=%s one=%s seed_delta=%.4f zero_delta=%.4f foot_y=%.10f skate=%.10f same_bad=%d" % [
		d0.substr(0, 16), d1.substr(0, 16), diff_seed, vs_zero, foot_err, skate, same_bad])
	for w: Wobbler in [w0, w1, w1b, w2, sa, sb, sc, sz]:
		w.free()
	var f1: Fighter = load("res://actors/fighter.tscn").instantiate()
	var f2: Fighter = load("res://actors/fighter.tscn").instantiate()
	root.add_child(f1)
	root.add_child(f2)
	var s1 := FighterState.new()
	var s2 := FighterState.new()
	s1.id = 3
	s1.class_id = "wobbler"
	s2.id = 4
	s2.class_id = "wobbler"
	f1.bind(s1, {"skin": "none", "hat": "none", "color": 0x39b5a8})
	f2.bind(s2, {"skin": "none", "hat": "none", "color": 0x39b5a8})
	var seed_id3 := f1.wobbler.gait_identity()
	_check(seed_id3 != f2.wobbler.gait_identity(), "two offline fighter ids got the same gait seed")
	s2.id = 3
	s2.net_slot = 2
	_check(f1.wobbler.gait_identity() != f2.wobbler.gait_identity(), "net_slot 2 and offline id 3 got the same gait seed")
	s2.net_slot = -1
	_check(f1.wobbler.gait_identity() == f2.wobbler.gait_identity(), "same identity + look did not get the same gait seed")
	f1.free()
	f2.free()


## Settings: the shipped default is 0.55 and a live `changed` (the Graphics slider) re-poses the legs immediately.
func _setting_checks(scene: PackedScene) -> void:
	var st: Node = root.get_node_or_null("Settings")
	_check(st != null, "Settings autoload missing")
	if st == null:
		return
	var defs: Dictionary = st.get_script().get_script_constant_map().get("DEFAULTS", {})
	_check(absf(float(defs.get("leg_wobble", -1.0)) - 0.55) < 1e-6, "Settings DEFAULTS leg_wobble is not 0.55")
	st.persist = false
	var prev := float(st.get_value("leg_wobble", 0.55))
	var w: Wobbler = _new_wobbler(scene, 0x2222, prev)
	st.set_value("leg_wobble", 0.9)
	_check(absf(w.leg_wobble - 0.9) < 1e-6, "live leg_wobble change did not reach the wobbler")
	st.set_value("leg_wobble", 0.0)
	_check(w.leg_wobble == 0.0, "live leg_wobble 0 did not reach the wobbler")
	w.free()
	st.set_value("leg_wobble", prev)


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
	_wobble_checks(scene)
	_setting_checks(scene)
	_budget(scene)
	for f in fails:
		print("FAIL ", f)
	print("RAGDOLL_RESULT classes=%d fails=%d" % [nc, fails.size()])
	quit(0 if fails.is_empty() else 1)


## n ragdoll fighters running, fighting and falling: [classic us, overlay us] per fighter-frame at `wobble`.
func _budget_run(scene: PackedScene, n: int, wobble: float) -> Array:
	var ws: Array[Wobbler] = []
	for i in n:
		var w: Wobbler = scene.instantiate()
		root.add_child(w)
		w.rig_mode = "ragdoll"
		w.setup("wobbler", "none", "none", 0x39b5a8)
		w.leg_wobble = wobble
		w.gait_seed = 1000 + i * 7919
		ws.append(w)
	var t_cl := 0
	var t_ov := 0
	var frames := 0
	for k in 900:
		for i in n:
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
				frames += 1
	for w in ws:
		w.free()
	return [float(t_cl) / frames, float(t_ov) / frames]


## 8 fighters (the study's baseline) at wobble 0 / 0.55 and 10 at 0.55: classic animate vs the overlay, microseconds
## per fighter per frame; the M0 wobble must stay in the same order of magnitude and inside the per-fighter budget.
func _budget(scene: PackedScene) -> void:
	var b0: Array = _budget_run(scene, 8, 0.0)
	var b1: Array = _budget_run(scene, 8, 0.55)
	var b10: Array = _budget_run(scene, 10, 0.55)
	print("RAGDOLL_BUDGET classic=%.1fus overlay(wobble 0)=%.1fus overlay(wobble 0.55)=%.1fus per fighter-frame; 8 fighters: %.2f / %.2f ms/frame, 10 fighters: %.2f ms/frame (budget overlay < %.0fus)" % [
		b0[0], b0[1], b1[1], (b0[0] + b0[1]) * 8.0 / 1000.0, (b1[0] + b1[1]) * 8.0 / 1000.0, (b10[0] + b10[1]) * 10.0 / 1000.0, BUDGET_US])
	_check(b1[1] < BUDGET_US, "overlay too slow: %.1f us per fighter-frame" % b1[1])
	_check(b10[1] < BUDGET_US, "overlay too slow with 10 fighters: %.1f us" % b10[1])
