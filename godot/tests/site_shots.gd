extends SceneTree
## Building Site pictures (needs a real renderer, opens a window):
##   godot --path godot --resolution 1280x720 --script res://tests/site_shots.gd -- --no-save --out DIR [--seeds 1,2,3,4,5] [--what sites|tools|ppe|all]
## sites: DIR/site-<seed>-top.png and site-<seed>-3q.png for each seed (the generated 'sitegen' map in a Construction world)
## tools: DIR/tools-models.png (the nine DLC tools on their own) and DIR/tools-held.png (nine tradies holding them)
## ppe:   DIR/ppe.png (the three hard hats and the hi-vis vest, front and back)

var out_dir := "."
var seeds: Array = [1, 2, 3, 4, 5]
var what := "all"
var world: Node
var stage: Node3D

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size(): out_dir = a[i + 1]
		elif a[i] == "--what" and i + 1 < a.size(): what = a[i + 1]
		elif a[i] == "--seeds" and i + 1 < a.size():
			seeds = []
			for s in a[i + 1].split(","): seeds.append(int(s))
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_frame.connect(_go, CONNECT_ONE_SHOT)

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name))
	print("SHOT ", name)

func _frames(n: int) -> void:
	for i in n: await process_frame

func _go() -> void:
	if what == "all" or what == "sites":
		for sd in seeds: await _site(int(sd))
	if what == "all" or what == "tools":
		await _tools()
	if what == "all" or what == "ppe":
		await _ppe()
	quit(0)

func _site(sd: int) -> void:
	SiteMap.set_seed(sd)
	world = load("res://world/world.tscn").instantiate()
	world.map_id = SiteMap.ID
	world.mode_id = "construction"
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
	cam.look_at_from_position(Vector3(0, 118, 0.01), Vector3.ZERO, Vector3.FORWARD)
	await _frames(12)
	await _save("site-%d-top.png" % sd)
	cam.fov = 56.0
	cam.look_at_from_position(Vector3(sin(0.6) * 62.0, 44.0, cos(0.6) * 62.0), Vector3(0, 3.0, 0), Vector3.UP)
	await _frames(6)
	await _save("site-%d-3q.png" % sd)
	world.free()
	world = null
	await _frames(2)
	SiteMap.set_seed(1)

func _stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.hex(0xbfe3f2ff)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.hex(0xdfe9eeff)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	stage.add_child(sun)
	sun.look_at_from_position(Vector3(2.2, 3.8, 1.2), Vector3.ZERO, Vector3.UP)

func _tools() -> void:
	_stage()
	var cam := Camera3D.new()
	cam.fov = 30
	stage.add_child(cam)
	cam.current = true
	var keys: Array = WeaponModels.DLC_KEYS
	for i in keys.size():
		var holder := Node3D.new()
		holder.position = Vector3((i % 3 - 1) * 3.2, (1 - i / 3) * 3.4, 0)
		holder.rotation.y = deg_to_rad(-55)
		holder.rotation.z = deg_to_rad(18)
		stage.add_child(holder)
		var m := WeaponModels.build(keys[i])
		var bb := WeaponModels.bounds(m)
		m.position = -bb.get_center()
		holder.add_child(m)
	cam.look_at_from_position(Vector3(0, 0, 20.5), Vector3(0, 0, 0), Vector3.UP)
	await _frames(6)
	await _save("tools-models.png")
	# nine tradies holding them
	for c in stage.get_children():
		if c is Node3D and c != cam: c.queue_free()
	await _frames(2)
	var hats := ["hardhat", "hardhat_white", "hardhat_orange"]
	var ws: Array[Wobbler] = []
	for i in keys.size():
		var w: Wobbler = load("res://actors/wobbler.tscn").instantiate()
		stage.add_child(w)
		w.position = Vector3((i % 3 - 1) * 3.4, -(i / 3 - 1) * 3.2 - 1.2, 0)
		w.set_skin("builder")
		w.set_hat(hats[i % 3])
		w.set_weapon(keys[i])
		ws.append(w)
	for f in 20:
		for i in ws.size():
			ws[i].apply_state({"pos": ws[i].position, "vel": Vector3.ZERO, "yaw": deg_to_rad(25), "grounded": true, "aim": Vector3(0.5, -0.45, 0.8).normalized(), "weapon": keys[i]})
			ws[i].animate(1.0 / 60.0)
		await process_frame
	cam.look_at_from_position(Vector3(2.0, 3.0, 17.0), Vector3(0, -0.4, 0), Vector3.UP)
	await _frames(2)
	await _save("tools-held.png")
	stage.queue_free()
	await _frames(2)

func _ppe() -> void:
	_stage()
	var cam := Camera3D.new()
	cam.fov = 28
	stage.add_child(cam)
	cam.current = true
	var hats := ["hardhat", "hardhat_white", "hardhat_orange"]
	var ws: Array[Wobbler] = []
	for row in 2:
		for i in 3:
			var w: Wobbler = load("res://actors/wobbler.tscn").instantiate()
			stage.add_child(w)
			w.position = Vector3((i - 1) * 2.4, -row * 3.0, 0)
			w.set_skin("builder")
			w.set_hat(hats[i])
			ws.append(w)
	for f in 20:
		for i in ws.size():
			ws[i].apply_state({"pos": ws[i].position, "vel": Vector3.ZERO, "yaw": 0.35 if i < 3 else PI - 0.35, "grounded": true, "aim": Vector3(0, -0.5, 0.8)})
			ws[i].animate(1.0 / 60.0)
		await process_frame
	cam.look_at_from_position(Vector3(0, -0.6, 17.0), Vector3(0, -0.6, 0), Vector3.UP)
	await _frames(2)
	await _save("ppe.png")
