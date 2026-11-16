extends SceneTree
## DLC pack arena pictures (needs a real renderer, opens a window):
##   godot --path godot --resolution 1280x720 --script res://tests/pack_map_shots.gd -- --no-save --out DIR [--seeds 1,2] [--maps kitchen_chaos,toy_workshop,backyard_bbq]
## DIR/<map>-<seed>-top.png (straight down), -3q.png (an isometric corner view like the concept art), -low.png (a lower corner view),
## -eye-a.png / -eye-b.png (two views from a fighter's height inside the arena), for an arena with a Hills Hoist -hoist-a.png /
## -hoist-b.png (the same view 0.6 s of sim clock apart: the arms have turned), and -play-a.png / -play-b.png (the in-match camera
## with the fighters, the player walking in from the start after the countdown, and half a second later).

var out_dir := "."
var seeds: Array = [1, 2]
var maps: Array = ["kitchen_chaos", "toy_workshop", "backyard_bbq"]
var world: Node

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size(): out_dir = a[i + 1]
		elif a[i] == "--seeds" and i + 1 < a.size():
			seeds = []
			for s in a[i + 1].split(","): seeds.append(int(s))
		elif a[i] == "--maps" and i + 1 < a.size(): maps = Array(a[i + 1].split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_frame.connect(_go, CONNECT_ONE_SHOT)

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name))
	print("SHOT ", name)

func _frames(n: int) -> void:
	for i in n: await process_frame

func _go() -> void:
	for id: String in maps:
		for sd in seeds: await _shot(id, int(sd))
	quit(0)

func _shot(id: String, sd: int) -> void:
	PackMaps.set_seed(sd)
	world = load("res://world/world.tscn").instantiate()
	world.map_id = id
	world.auto_run = false
	world.bot_count = 3
	world.rng_seed = 777
	world.dyn_choice = "off"
	root.add_child(world)
	world.touch.visible = false
	for n in ["UI", "HUD"]:
		var ui := world.get_node_or_null(n)
		if ui is CanvasItem: (ui as CanvasItem).visible = false
		elif ui is CanvasLayer: (ui as CanvasLayer).visible = false
	world.set_process(false)
	for v in world.views.values(): v.visible = false
	var cam: Camera3D = world.cam
	var env: Environment = world.env_node.environment
	env.fog_depth_begin = 400.0; env.fog_depth_end = 900.0
	cam.fov = 45.0
	cam.look_at_from_position(Vector3(0, 100, 0.01), Vector3.ZERO, Vector3.FORWARD)
	await _frames(12)
	await _save("%s-%d-top.png" % [id, sd])
	cam.fov = 50.0
	cam.look_at_from_position(Vector3(34.0, 36.0, 40.0), Vector3(0, 0.0, 0), Vector3.UP)
	await _frames(6)
	await _save("%s-%d-3q.png" % [id, sd])
	cam.look_at_from_position(Vector3(-30.0, 22.0, 34.0), Vector3(0, 0.0, -2), Vector3.UP)
	await _frames(4)
	await _save("%s-%d-low.png" % [id, sd])
	# from inside, at a fighter's height: from the player's start towards the middle, and across from a far spawn
	var pl: Array = world.sim.map["player"]
	var px := float(pl[0])
	var pz := float(pl[1])
	cam.fov = 70.0
	cam.look_at_from_position(Vector3(px, 3.2, pz + 3.0), Vector3(0.0, 1.2, 0.0), Vector3.UP)
	await _frames(4)
	await _save("%s-%d-eye-a.png" % [id, sd])
	var far: Array = pl
	for s: Array in world.sim.map["spawns"]:
		if Vector2(float(s[0]) - px, float(s[1]) - pz).length() > Vector2(float(far[0]) - px, float(far[1]) - pz).length(): far = s
	cam.look_at_from_position(Vector3(float(far[0]) * 1.12, 4.0, float(far[1]) * 1.12), Vector3(px * 0.3, 0.8, pz * 0.3), Vector3.UP)
	await _frames(4)
	await _save("%s-%d-eye-b.png" % [id, sd])
	for z: Variant in world.sim.map.get("zones", []):
		if not (z is Dictionary) or str((z as Dictionary).get("kind", "")) != "hoist": continue
		var hx := float(z["x"])
		var hz := float(z["z"])
		cam.fov = 60.0
		cam.look_at_from_position(Vector3(hx + 7.5, 5.0, hz + 10.0), Vector3(hx, 1.6, hz), Vector3.UP)
		var t0 := PackZones.clock
		for k in 2:
			PackZones.clock = 1.0 + 0.6 * float(k)          # PackSpinner turns to the sim clock: two moments of the same sweep
			await _frames(4)
			await _save("%s-%d-hoist-%s.png" % [id, sd, "ab"[k]])
		PackZones.clock = t0
		break
	# the match itself: fighters on, the real camera, stepped by hand past the countdown
	for v in world.views.values(): v.visible = true
	cam.fov = 60.0
	cam.yaw = atan2(-px, -pz)                               # the player's own view, turned to face the middle of the arena
	for k in 2:
		for i in (360 if k == 0 else 30):
			world.input.state.set_move("script", Vector2(0.0, 1.0 if i > 200 or k == 1 else 0.0))    # walks in off the fence after GO
			world.tick(1.0 / 60.0)
			if i % 6 == 5: await process_frame
		await _frames(2)
		await _save("%s-%d-play-%s.png" % [id, sd, "ab"[k]])
	world.input.state.set_move("script", Vector2.ZERO)
	world.free()
	world = null
	await _frames(2)
	PackMaps.set_seed(1)
