extends SceneTree
## Renders UI screenshots for visual review (needs a real renderer, opens a window):
##   godot --path godot --resolution 852x393 --script res://tests/ui_shots.gd -- --no-save --shot match --out FILE.png
## Shots: title (scenes/main.tscn), title-online (its Play online panel), title-settings (the gear sheet), wizard-arena /
## wizard-mode / wizard-players / wizard-class / wizard-go (the offline setup wizard pages, ui/setup_wizard.gd), match (offline world with the HUD), touch (same with the touch layer forced on and
## a few fingers down), fps (match with the FPS overlay on), pause (the pause menu), title-construction (the title with the
## wizard on Construction), construction (a Construction match on Site Yard, mid hammer swing). Used by tools/shoot-godot-ui.sh.

const FRAME := 1.0 / 60.0

var shot := "title"
var out := "shot.png"
var frames := 0
var world: Node
var i := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--shot" and k + 1 < a.size(): shot = a[k + 1]
		elif a[k] == "--out" and k + 1 < a.size(): out = a[k + 1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _settings() -> Node:
	return root.get_node("Settings")

func _start() -> void:
	if shot == "title-construction": _settings().set_value("mode", "construction")
	if shot.begins_with("title") or shot.begins_with("wizard"):
		if shot.begins_with("wizard"):   # a fixed setup so the shots are comparable
			for kv in [["offline_map", "arena"], ["mode", "classic"], ["dyn", "random"], ["bots", 3], ["difficulty", "normal"], ["class", "wobbler"]]:
				_settings().set_value(kv[0], kv[1])
		var m: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(m)
		if shot == "title-online":
			m.show_tab(true)
			m.get_node("Safe/Col/Body/Online/Box/Roster").text = "In the room: Alice, Bob"
		elif shot == "title-settings":
			m.show_settings(true)
		elif shot.begins_with("wizard"):
			m.open_wizard(["wizard-arena", "wizard-mode", "wizard-players", "wizard-class", "wizard-go"].find(shot))
		frames = 40
		process_frame.connect(_wait)
		return
	_settings().set_value("touch_mode", "on" if shot == "touch" else "off")
	_settings().set_value("show_fps", shot == "fps")
	world = load("res://world/world.tscn").instantiate()
	world.map_id = "siteyard" if shot == "construction" else "arena"
	if shot == "construction":
		world.mode_id = "construction"
		world.dyn_choice = "off"
	world.auto_run = false
	world.bot_count = 3
	world.player_class = "wobbler"
	world.rng_seed = 777
	world.hp_setting = 200.0
	root.add_child(world)
	if shot != "touch":
		world.touch.visible = false
	process_frame.connect(_frame)

func _wait() -> void:
	frames -= 1
	if frames == 0:
		process_frame.disconnect(_wait)
		_save()

func _nearest(me: FighterState) -> FighterState:
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in world.sim.fighters:
		if f == me or f.dead: continue
		var d := Vector2(f.phys.px - me.phys.px, f.phys.pz - me.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx; e.position = pos; e.pressed = pressed
	world.touch._input(e)

func _frame() -> void:
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	if shot == "construction":
		_hammer_frame(sim, p, st)
		return
	if i == 2:
		sim.combat.pickup(p, "katana")
		sim.combat.pickup(p, "smg")      # the last pickup is the active slot
		if shot != "touch": world.hud.last_touch = false
	var go := Vector2.ZERO
	var fire := false
	var tg := _nearest(p)
	if tg:
		var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		world.cam.yaw = lerp_angle(world.cam.yaw, atan2(d.x, d.y) + 0.25, 0.1)
		world.cam.pitch = -0.12
		go = Vector2(0, 0.7) if d.length() > 9.0 else Vector2.ZERO
		fire = d.length() < 16.0 and i > 120 and i < 330
	st.set_move("script", go)
	st.hold("script", "fire", fire)
	world.tick(FRAME)
	i += 1
	if i == 200:
		world._toast("K.O.!")
	if i == 330 and not p.dead:
		p.hp = sim.combat.max_hp(p) * 0.22   # show the damage trail and the low-health pulse
	if shot == "touch" and i == 340:
		var vs: Vector2 = world.touch.get_viewport_rect().size
		_touch(7, Vector2(vs.x * 0.16, vs.y * 0.72), true)
		var e := InputEventScreenDrag.new()
		e.index = 7; e.position = Vector2(vs.x * 0.16 + 40, vs.y * 0.72 - 50)
		world.touch._input(e)
		_touch(8, world.touch.button_rect(world.touch.BUTTONS[0])[0], true)
	if shot == "pause" and i == 345:
		world._toggle_pause()
	if i == 352:
		process_frame.disconnect(_frame)
		_save()

## Construction: walk up to the nearest bot with the Claw Hammer and save mid swing (or after 12 s).
func _hammer_frame(sim: MatchSim, p: FighterState, st: InputState) -> void:
	if i == 2: world.hud.last_touch = false
	var tg := _nearest(p)
	var go := Vector2.ZERO
	var fire := false
	var dist := 99.0
	if tg:
		var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		dist = d.length()
		world.cam.yaw = lerp_angle(world.cam.yaw, atan2(d.x, d.y) + 0.35, 0.1)
		world.cam.pitch = -0.16
		go = Vector2(0, 1) if dist > 1.7 else Vector2.ZERO
		fire = dist < 2.6 and i > 240
	st.set_move("script", go)
	st.hold("script", "fire", fire)
	world.tick(FRAME)
	i += 1
	if (i > 260 and p.weapon == "hammer" and p.swing > 0.35 and p.swing < 0.6 and dist < 3.0) or i == 720:
		process_frame.disconnect(_frame)
		_save()

func _save() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("SHOT ", out, " ", img.get_size())
	quit(0)
