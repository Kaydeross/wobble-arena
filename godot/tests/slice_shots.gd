extends SceneTree
## Renders frames of a scripted offline match for visual review (needs a real renderer, opens a window):
##   godot --path godot --resolution 1600x900 --script res://tests/slice_shots.gd -- --no-save --out DIR
## Drives the world like tests/integration_test.gd (1/60 s per rendered frame) and saves
## DIR/godot-slice-melee.png, -smg.png and -wide.png. Used by tools/shoot-godot-slice.sh.

const FRAME := 1.0 / 60.0
const SHOTS := {300: "melee", 840: "smg", 1500: "wide"}   ## frame -> name

var world: Node
var out_dir := "."
var i := 0
var crate := {}
var have_smg := false

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--out" and k + 1 < a.size(): out_dir = a[k + 1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	world = load("res://world/world.tscn").instantiate()
	world.map_id = "arena"
	world.auto_run = false
	world.bot_count = 3
	world.player_class = "bruiser"
	world.rng_seed = 4242
	world.hp_setting = 100.0
	root.add_child(world)
	world.touch.visible = false
	process_frame.connect(_frame)

func _nearest(me: FighterState) -> FighterState:
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in world.sim.fighters:
		if f == me or f.dead: continue
		var d := Vector2(f.phys.px - me.phys.px, f.phys.pz - me.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

func _frame() -> void:
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	var go := Vector2.ZERO
	var fire := false
	if i == 480: crate = sim.pickups.spawn_drop("smg")
	if not crate.is_empty() and not have_smg:
		var c := Vector2(crate["x"] - p.phys.px, crate["z"] - p.phys.pz)
		world.cam.yaw = lerp_angle(world.cam.yaw, atan2(c.x, c.y), 0.2)
		go = Vector2(0, 1)
		have_smg = p.weapon == "smg"
	else:
		var tg := _nearest(p)
		if tg:
			var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
			world.cam.yaw = lerp_angle(world.cam.yaw, atan2(d.x, d.y), 0.2)
			world.cam.pitch = -0.15 if i < 1410 else -0.55      # look down over the arena for the wide shot
			var melee: bool = sim.combat.wdata(p.weapon if p.weapon != "" else "spatula").get("type", "") == "melee"
			var reach := 1.6 if melee else 6.0
			go = Vector2(0, 1) if d.length() > reach else Vector2.ZERO
			fire = d.length() < reach + 1.0
	st.set_move("script", go)
	st.hold("script", "fire", fire)
	world.tick(FRAME)
	i += 1
	if SHOTS.has(i):
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := out_dir.path_join("godot-slice-%s.png" % SHOTS[i])
		img.save_png(path)
		print("SHOT ", path)
	if i > 1500:
		process_frame.disconnect(_frame)
		quit(0)
