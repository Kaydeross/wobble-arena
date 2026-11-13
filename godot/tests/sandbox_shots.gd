extends SceneTree
## Screenshots of Sandbox build mode, a match on a built arena and Lava Pillars (needs a real renderer, opens a window):
##   godot --path godot --resolution 1170x540 --script res://tests/sandbox_shots.gd -- --no-save --out DIR
## Saves DIR/godot-sandbox-build.png, -build-style.png, -match.png and -lavapillars.png (touch layer on, phone safe-area insets).

const FRAME := 1.0 / 60.0
var out_dir := "."

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--out" and k + 1 < a.size(): out_dir = a[k + 1]
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _shot(name: String) -> void:
	for k in 3: await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("godot-sandbox-%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)

func _tick(world: Node, n: int) -> void:
	for k in n:
		world.tick(FRAME)
		if k % 20 == 0: await process_frame

func _run() -> void:
	SafeArea.override = [81.0, 0.0, 81.0, 29.0]
	root.get_node("Settings").set_value("touch_mode", "on")
	var save: Node = root.get_node("Save")
	save.set_sandbox({"custom": {"size": 44, "theme": "grass", "obs": 6, "plat": 2, "pads": 2, "walls": 2, "ice": false, "seed": 7}, "blocks": [], "blockCols": []})
	var world: Node = load("res://world/world.tscn").instantiate()
	world.auto_run = false
	world.build_mode = true
	world.rng_seed = 11
	world.player_class = "wobbler"
	root.add_child(world)
	await process_frame
	await _tick(world, 60)
	var hud: BuildHud = world.build_hud
	var p: FighterState = world.sim.player
	# a little fort: a wall of blue, a red tower, a white step, in front of the camera
	var builds := [[Vector2(-6, 6), 0.0, 2, 1, SandboxLayout.COLORS[2]], [Vector2(-2, 6), 0.0, 2, 1, SandboxLayout.COLORS[2]],
		[Vector2(2, 6), 0.0, 2, 1, SandboxLayout.COLORS[2]], [Vector2(6, 8), 0.0, 1, 4, SandboxLayout.COLORS[1]],
		[Vector2(-8, 10), 0.0, 1, 3, SandboxLayout.COLORS[4]], [Vector2(0, 12), 0.0, 3, 1, SandboxLayout.COLORS[5]],
		[Vector2(0, 12), 2.0, 1, 2, SandboxLayout.COLORS[0]]]
	for b: Array in builds:
		hud.layout.size = b[2]; hud.layout.height = b[3]; hud.layout.color = b[4]
		hud.layout.place(b[0], b[1])
	hud._changed("")
	hud.layout.size = 2; hud.layout.height = 2; hud.layout.color = SandboxLayout.COLORS[3]
	hud._refresh()
	p.phys.place(0.0, 0.2, -2.0); p.yaw = 0.0
	world.cam.yaw = 0.0; world.cam.pitch = -0.32
	await _tick(world, 30)
	world.cam.yaw = 0.0; world.cam.pitch = -0.32
	world.tick(FRAME)
	await _shot("build")
	hud.toggle_style(true)
	await _shot("build-style")
	hud.toggle_style(false)
	hud.play()
	await process_frame
	await process_frame
	await _tick(world, 300)
	for k in 40:                                       # look at the fort
		var q: FighterState = world.sim.player
		world.cam.yaw = atan2(0.0 - q.phys.px, 8.0 - q.phys.pz); world.cam.pitch = -0.18
		world.tick(FRAME)
	await _shot("match")
	world.queue_free()
	await process_frame
	var w2: Node = load("res://world/world.tscn").instantiate()
	w2.auto_run = false
	w2.map_id = "pillars2"
	w2.mode_id = "pillars"
	w2.rng_seed = 21
	root.add_child(w2)
	await process_frame
	await _tick(w2, 200)
	await _shot("lavapillars")
	w2.queue_free()
	await process_frame
	quit(0)
