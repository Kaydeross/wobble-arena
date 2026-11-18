extends SceneTree
## Headless fence-camera test (run by tools/test-camera-fence.js):
##   godot --headless --path godot --script res://tests/camera_fence_test.gd -- --no-save
## The pack arenas are walled yards (Backyard BBQ: a 2.8 m corrugated fence). The shared follow camera sits above the
## player's head and behind them, so near the fence the camera ray passed OVER the fence top and the camera ended up
## outside the yard looking in. FollowCamera.follow() now takes the arena `bounds` and keeps the camera inside them.
## Checks every start point plus a ring of spots along the fence, at every yaw, hip and aiming: the camera never leaves
## the fence's inner face. Other (open) arenas pass no bounds and keep their framing byte for byte.

const MARGIN := 0.05
var fails := 0
var FC: GDScript   # FollowCamera needs the autoloads, which a --script compile has not got yet: load it at run time

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	FC = load("res://world/follow_camera.gd")
	root.get_node("Settings").set_value("cam_dist", 1.0)
	var map: Dictionary = PackMaps.generate("backyard_bbq", 424242)
	var solids: Array = FighterPhysics.solids_from_map(map)
	var bounds: Rect2 = FC.arena_bounds(solids)
	check(bounds.size.x > 30.0 and bounds.size.x < 46.0, "bounds found from the fence (%s)" % str(bounds))
	var pts: Array = []
	for p: Array in MatchSim.start_points(map): pts.append(Vector2(p[0], p[1]))
	var w := bounds.end.x - 1.0
	for i in 12:
		var t := lerpf(-w, w, float(i) / 11.0)
		pts.append(Vector2(t, w)); pts.append(Vector2(t, -w)); pts.append(Vector2(w, t)); pts.append(Vector2(-w, t))
	var cam: Camera3D = FC.new()
	root.add_child(cam)
	var worst := 0.0
	var n := 0
	var open_diff := 0
	var open_out := 0
	var max_d := 0.0
	for p: Vector2 in pts:
		for yi in 16:
			for aiming in [false, true]:
				cam.yaw = float(yi) * TAU / 16.0
				cam.pitch = FC.DEFAULT_PITCH
				cam.aim = 1.0 if aiming else 0.0
				cam.follow(0.0, Vector3(p.x, 0.0, p.y), aiming, solids, FC.AIM_FOV, bounds)
				var c := cam.global_position
				var out := maxf(maxf(c.x - bounds.end.x, bounds.position.x - c.x), maxf(c.z - bounds.end.y, bounds.position.y - c.z))
				worst = maxf(worst, out)
				n += 1
				check(out <= MARGIN, "camera outside the fence by %.2f m (spot %s yaw %d aim %s)" % [out, str(p), yi, str(aiming)])
				var open_cam: Camera3D = FC.new()
				root.add_child(open_cam)
				open_cam.yaw = cam.yaw; open_cam.pitch = cam.pitch; open_cam.aim = cam.aim
				open_cam.follow(0.0, Vector3(p.x, 0.0, p.y), aiming, solids)
				var oc := open_cam.global_position
				if not bounds.has_point(Vector2(oc.x, oc.z)): open_out += 1
				if bounds.grow(-0.35).has_point(Vector2(oc.x, oc.z)): max_d = maxf(max_d, oc.distance_to(c))
				if oc.distance_to(c) > 0.001 and bounds.grow(-0.35).has_point(Vector2(open_cam.global_position.x, open_cam.global_position.z)):
					open_diff += 1                 # a camera already inside must not move
				open_cam.free()
	check(open_out > 0, "the test is live: without bounds some cameras do leave the fence")
	check(open_diff == 0, "a camera already inside the yard is untouched (%d moved, max %.3f m)" % [open_diff, max_d])
	check(FC.arena_bounds([{"minX": -20.0, "maxX": 20.0, "minZ": -20.0, "maxZ": 20.0, "bottom": -2.0, "top": 0.0}]).size == Vector2.ZERO, "an open arena (no fence) has no bounds")
	print("CAMERA-FENCE %d cameras, worst overshoot %.2f m; without bounds %d of them end outside the fence" % [n, worst, open_out])
	print("CAMERA-FENCE %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)
