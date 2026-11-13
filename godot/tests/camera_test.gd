extends SceneTree
## Headless follow-camera test (run by tools/test-camera.js):
##   godot --headless --path godot --script res://tests/camera_test.gd -- --no-save
## Auto-centre (world/follow_camera.gd): with a manual yaw/pitch offset the camera holds still for the first
## cam_center_dist metres of walking, then eases (no overshoot) to behind the direction of travel; a held stick keeps
## walking straight while the camera turns under it (no feedback loop); a held look touch, aiming or the setting off stop
## it; sprinting centres faster.

const FRAME := 1.0 / 60.0
const QUIET := 4.5     ## metres walked with no recentring (cam_center_dist is 5)
const SETTLE := 0.03   ## rad: converged
const OVERSHOOT := 0.02

var fails := 0
var settings: Node

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	settings = root.get_node("Settings")
	settings.set_value("cam_auto_center", true)
	settings.set_value("cam_center_dist", 5.0)
	var walk := _walk("offset", 1.2, Vector2.ZERO, 34.0, {})
	_walk("strafe", PI / 2.0, Vector2(1, 0), 34.0, {})
	_walk("backpedal", -2.2, Vector2.ZERO, 34.0, {})
	var sprint := _walk("sprint", 1.2, Vector2.ZERO, 38.0, {"sprint": true})
	check(sprint["settle_t"] > 0.0 and sprint["settle_t"] < walk["settle_t"], "sprint centres faster (%.2f s vs %.2f s)" % [sprint["settle_t"], walk["settle_t"]])
	_walk("drag", 1.0, Vector2.ZERO, 12.0, {"drag": true})
	_walk("aim", 1.0, Vector2.ZERO, 8.0, {"aim": true})
	settings.set_value("cam_auto_center", false)
	_walk("off", 1.0, Vector2.ZERO, 12.0, {"off": true})
	settings.set_value("cam_auto_center", true)
	print("CAMERA %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _heading(v: Vector2) -> float:
	return atan2(v.x, v.y)

## One scenario on a fresh world: land, turn the camera `offset` rad away from the walk direction (a manual look), hold
## one stick vector and walk `metres`. `stick` = Vector2.ZERO picks the stick that walks down the range.
func _walk(name: String, offset: float, stick: Vector2, metres: float, opt: Dictionary) -> Dictionary:
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = "practice"   # a 96 m range: room to walk straight
	world.auto_run = false
	world.bot_count = 0
	world.dyn_choice = "off"
	root.add_child(world)
	var st: InputState = world.input.state
	var cam: Variant = world.cam   # untyped: FollowCamera needs the autoloads, which a --script compile has not got yet
	for i in 45: world.tick(FRAME)                 # drop onto the floor
	var p0: Vector3 = world.player_pos()
	var dir := Vector2(0.3, -1).normalized()     # down the range (spawn 0, 14)
	var head := _heading(dir)
	if stick == Vector2.ZERO:
		stick = Vector2(sin(offset), cos(offset))  # (right, forward) of `dir` seen from a camera turned `offset`
	# manual look: camera yaw = head + offset (strafe: the stick's own angle), pitch off the default
	var want_yaw := head + offset if stick != Vector2(1, 0) else head + PI / 2.0
	st.add_look(wrapf(want_yaw - cam.yaw, -PI, PI), 0.35)
	world.tick(FRAME)
	var yaw0: float = cam.yaw
	var pitch0: float = cam.pitch
	var tc: Control = world.touch
	if opt.has("drag"):
		tc.visible = true
		var e := InputEventScreenTouch.new()
		e.index = 3; e.position = tc.get_viewport_rect().size * Vector2(0.6, 0.2); e.pressed = true
		tc._input(e)
		check(tc.look_held(), name + ": look touch held")
	if opt.has("aim"): st.hold("script", "aim", true)
	if opt.has("sprint"): st.hold("script", "sprint", true)
	st.set_move("script", stick)
	var start: Vector3 = world.player_pos()
	var walked := 0.0
	var prev := start
	var e0 := wrapf(head - yaw0, -PI, PI)
	var max_over := 0.0
	var quiet_drift := 0.0
	var max_dev := 0.0
	var max_head_dev := 0.0
	var settle_t := -1.0
	var center_t := -1.0
	var t := 0.0
	var phase2 := false        # aim: released, walking on
	var walked2 := 0.0
	var guard := 0
	while walked < metres and guard < 1200:
		guard += 1
		world.tick(FRAME)
		t += FRAME
		var p: Vector3 = world.player_pos()
		var step := Vector2(p.x - prev.x, p.z - prev.z).length()
		walked += step
		if phase2: walked2 += step
		prev = p
		var err := wrapf(head - cam.yaw, -PI, PI)
		if not phase2 and walked < QUIET or opt.has("drag") or opt.has("off") or (opt.has("aim") and not phase2):
			quiet_drift = maxf(quiet_drift, maxf(absf(wrapf(cam.yaw - yaw0, -PI, PI)), absf(cam.pitch - pitch0)))
		if phase2 and walked2 < QUIET:
			quiet_drift = maxf(quiet_drift, absf(wrapf(cam.yaw - yaw0, -PI, PI)))
		max_over = maxf(max_over, -signf(e0) * err)
		if cam.centering and center_t < 0.0: center_t = t
		if center_t >= 0.0 and settle_t < 0.0 and absf(err) < SETTLE: settle_t = t - center_t
		if walked > 1.0:   # held stick: straight line along `dir`, velocity heading steady
			var rel := Vector2(p.x - start.x, p.z - start.z)
			max_dev = maxf(max_dev, absf(rel.x * dir.y - rel.y * dir.x))
			var v := Vector2(world.phys.vx, world.phys.vz)
			if v.length() > 1.0: max_head_dev = maxf(max_head_dev, absf(wrapf(_heading(v) - head, -PI, PI)))
		if opt.has("aim") and not phase2 and walked >= metres * 0.5:
			st.hold("script", "aim", false)        # let go of aim, keep walking: another full distance before it centres
			phase2 = true
			yaw0 = cam.yaw
			metres = walked + 30.0
	var err_end := wrapf(head - cam.yaw, -PI, PI)
	print("CAM %-8s walked=%.1fm t=%.2fs yaw_err0=%.2f end=%.3f pitch=%.3f over=%.4f quiet=%.5f dev=%.3fm head_dev=%.3f settle=%.2fs" % [
		name, walked, t, e0, err_end, cam.pitch, max_over, quiet_drift, max_dev, max_head_dev, settle_t])
	check(walked >= metres - 0.5, "%s: walked %.1f m (blocked?)" % [name, walked])
	check(quiet_drift < 1e-4, "%s: camera held still while it must not centre (drift %.5f)" % [name, quiet_drift])
	check(max_dev < 0.15 and max_head_dev < 0.03, "%s: held stick walks straight (lateral %.3f m, heading %.3f rad)" % [name, max_dev, max_head_dev])
	if opt.has("drag") or opt.has("off"):
		check(not cam.centering, name + ": no auto-centre")
	else:
		check(absf(err_end) < SETTLE, "%s: yaw converged behind the travel direction (err %.3f)" % [name, err_end])
		check(absf(cam.pitch - -0.2) < SETTLE, "%s: pitch back to default (%.3f)" % [name, cam.pitch])
		check(max_over < OVERSHOOT, "%s: overshoot %.4f rad" % [name, max_over])
	if name == "strafe":   # a yaw written from outside (tests, kill cam) drops the latched stick basis
		cam.yaw = 0.5
		world.tick(FRAME)
		check(absf(cam.move_basis() - 0.5) < 1e-6, "outside yaw write re-latches the stick basis (%.3f)" % cam.move_basis())
	st.set_move("script", Vector2.ZERO)
	st.hold("script", "aim", false); st.hold("script", "sprint", false)
	if opt.has("drag"): tc.release_all()
	world.free()
	return {"settle_t": settle_t}
