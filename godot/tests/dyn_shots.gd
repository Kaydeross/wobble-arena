extends SceneTree
## One screenshot per dynamic arena kind on Sunny Arena (needs a real renderer, opens a window):
##   godot --path godot --resolution 1600x900 --script res://tests/dyn_shots.gd -- --no-save --out DIR
## Saves DIR/godot-dyn-wobble.png, -tilt.png, -quake.png (while a hole is open) and -drift.png.

const FRAME := 1.0 / 60.0
const KINDS := ["wobble", "tilt", "quake", "drift"]
const SEED := 4242

var out_dir := "."
var k := 0
var world: Node
var frames_left := 0
var look_at := Vector2.INF        ## (x, z) the camera turns to: the quake hole / the first drifting block

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size(): out_dir = a[i + 1]
	process_frame.connect(_next, CONNECT_ONE_SHOT)

## Match time worth a picture: wobble/drift mid-swing, tilt at full lean, quake while a hole is fully open.
func _time_for(kind: String, d: ArenaDyn) -> float:
	if kind == "tilt": return 9.0
	if kind != "quake": return 7.5
	var t := 12.0
	while t < 80.0:
		for e: Dictionary in d.tiles:
			if Dynamics.offset("quake", d.seed, t, e["ix"], e["iz"], d.plan["nx"], d.plan["nz"], e["mask"]) <= -29.0:
				look_at = Vector2((e["s"].minX + e["s"].maxX) * 0.5, (e["s"].minZ + e["s"].maxZ) * 0.5)
				return t + 0.5
		t += 0.1
	return 20.0

func _next() -> void:
	if world: world.free()
	if k >= KINDS.size():
		quit(0); return
	world = load("res://world/world.tscn").instantiate()
	world.map_id = "arena"
	world.auto_run = false
	world.bot_count = 3
	world.rng_seed = SEED
	world.dyn_choice = KINDS[k]
	root.add_child(world)
	world.touch.visible = false
	var sim: MatchSim = world.sim
	look_at = Vector2.INF
	if KINDS[k] == "drift":
		var s0: Dictionary = sim.dyn.drift[0]["s"]
		look_at = Vector2((s0.minX + s0.maxX) * 0.5, (s0.minZ + s0.maxZ) * 0.5)
	var t := _time_for(KINDS[k], sim.dyn)
	while sim.dyn_clock() < t - 0.5: world.sim_step(world.SIM)
	world.cam.yaw = PI * 0.75; world.cam.pitch = -0.6
	frames_left = 30
	process_frame.connect(_frame)

func _frame() -> void:
	world.cam.pitch = -0.6
	if look_at != Vector2.INF:
		var p: Vector3 = world.player_pos()
		world.cam.yaw = atan2(look_at.x - p.x, look_at.y - p.z)
	world.tick(FRAME)
	frames_left -= 1
	if frames_left > 0: return
	process_frame.disconnect(_frame)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("godot-dyn-%s.png" % KINDS[k])
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path, " kind=", world.sim.dyn.kind, " t=", snappedf(world.sim.dyn_clock(), 0.01))
	k += 1
	_next.call_deferred()
