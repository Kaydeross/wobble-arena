extends SceneTree
## In-match screenshots of the combat effects (docs/style/godot-fx-*.png, tools/shoot-godot-fx.sh). Needs a real
## renderer (opens a window for a moment):
##   godot --path godot --resolution 1280x720 --script res://tests/fx_shots.gd -- --no-save --shot NAME --out FILE.png
## NAME: explosion | confetti | dash | melee | dust. The effect is triggered in front of the player (the effects API or
## a real swing / landing), the frame is grabbed a few frames in.

const FRAME := 1.0 / 60.0
const WARM := 45

var shot := "explosion"
var out := "fx.png"
var world: Node
var i := 0
var fire_at := WARM
var grab_at := WARM + 4
var done := false

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--shot" and k + 1 < a.size(): shot = a[k + 1]
		elif a[k] == "--out" and k + 1 < a.size(): out = a[k + 1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var st := root.get_node("Settings")
	st.set_value("touch_mode", "off")
	st.set_value("show_fps", false)
	st.set_value("effects", "high")
	world = load("res://world/world.tscn").instantiate()
	world.map_id = "park" if shot == "confetti" else "arena"
	world.auto_run = false
	world.bot_count = 1
	world.rng_seed = 31
	world.dyn_choice = "off"
	world.ko_limit = 0
	world.difficulty = "easy"
	root.add_child(world)
	world.touch.visible = false
	world.hud.visible = false
	grab_at = 99999 if shot == "dust" else WARM + {"explosion": 5, "confetti": 9, "dash": 4, "melee": 12}.get(shot, 4)
	process_frame.connect(_frame)

func _front(d: float, up := 0.0, side := 0.0) -> Vector3:
	var p: Vector3 = world.player_pos()
	var y: float = world.cam.yaw
	return p + Vector3(sin(y), 0, cos(y)) * d + Vector3(0, up, 0) + Vector3(-cos(y), 0, sin(y)) * side

func _frame() -> void:
	if done: return
	var sim: MatchSim = world.sim
	var me: FighterState = sim.player
	for f: FighterState in sim.fighters:              # keep the bot out of the way
		if f != me: f.phys.px = 30.0; f.phys.pz = 30.0
	if i == fire_at:
		var fx: FxSystem = world.fx
		match shot:
			"explosion":
				var at := _front(8.0, 1.0, -2.5)
				world.proj_views.explode(at, me.phys.py, 4.0)
			"confetti":
				var at2 := _front(4.2, 1.5, -1.4)
				fx.ko_burst(at2 - Vector3(0, 1.2, 0))
				fx.confetti(at2, Color.hex(0x39b5a8ff))
			"dash":
				fx.dash(_front(5.0, 1.0, -1.8), Vector3(cos(world.cam.yaw), 0, -sin(world.cam.yaw)))
			"melee":
				world.cam.yaw += 0.5
				world.cam.pitch = -0.3
				sim.combat.pickup(me, "katana")
				sim.combat.set_weapon(me, "katana")
				sim.combat.melee_begin(me, "katana", me.face_yaw)
			"dust":
				me.phys.py = 5.0; me.phys.vy = -14.0; me.phys.grounded = false
				world.cam.yaw += 0.6
				world.cam.pitch = -0.35
	if shot == "dust" and i > fire_at and grab_at > 9000 and me.phys.grounded:
		grab_at = i + 4
	world.tick(FRAME)
	i += 1
	if i == grab_at + 1:
		done = true
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("SHOT %s %s" % [shot, out])
		quit(0)
	elif i > 400:
		print("SHOT FAILED %s" % shot)
		quit(1)
