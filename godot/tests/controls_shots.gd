extends SceneTree
## Screenshots of the controls work (needs a real renderer; opens a window):
##   godot --path godot --resolution 852x393 --script res://tests/controls_shots.gd -- --no-save --shot controls --profile keyboard --out FILE.png
## --shot  controls | controls-pause (the pause menu's Controls page) | step:<id> (the training at that step) | finish (the
##         finish card) | offer (the first-play card over the title) | hint (a match with the control hint line)
## --profile touch | keyboard | gamepad (pins the control profile; touch also turns the touch layer on)
## --lang  en zh_TW zh_CN ja fr es      --phone  the 44 pt phone UI scale
const FRAME := 1.0 / 60.0

var shot := "controls"
var profile := "keyboard"
var out := "shot.png"
var frames := 40
var CP: GDScript
var world: Node

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--shot" and k + 1 < a.size(): shot = a[k + 1]
		elif a[k] == "--profile" and k + 1 < a.size(): profile = a[k + 1]
		elif a[k] == "--out" and k + 1 < a.size(): out = a[k + 1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--lang" and k + 1 < a.size(): root.get_node("Lang").apply(a[k + 1])
	var st: Node = root.get_node("Settings")
	if "--phone" in a or profile == "touch":
		st.set_value("ui_scale", "normal")
		st.set_value("touch_mode", "on" if profile == "touch" else "auto")
	CP = load("res://input/control_profile.gd")
	CP.set("force", profile)
	if shot == "controls" or shot == "controls-pause":
		if shot == "controls":
			var m: Node = load("res://scenes/main.tscn").instantiate()
			m.auto_intro = false
			m.auto_news = false
			root.add_child(m)
			m.show_settings(true, "controls")
			m.settings.open_help()
		else:
			world = _world(false)
			await _settle(10)
			world.pause_menu.open()
			world._toggle_pause()
			world.pause_menu.open_help()
		frames = 50
	elif shot.begins_with("step:") or shot == "finish":
		world = _world(true)
		await _settle(12)
		var t: Node = world.get("_tut")
		t.set("cheer_time", 0.0)
		var want: String = shot.substr(5) if shot != "finish" else ""
		var n := 0
		while n < 20 and (shot == "finish" or t.call("current_id") != want):
			t.call("skip"); n += 1
			if t.get("is_done"): break
		await _settle(30)
		if want == "fire" or want == "aim": world.input.state.hold("script", "fire", true)
		if want == "aim": world.input.state.aim_toggle = true
		frames = 40
	elif shot == "offer":
		load("res://ui/tutorial_offer.gd").set("test_persist", 1)
		var m: Node = load("res://scenes/main.tscn").instantiate()
		m.auto_intro = false
		m.auto_news = false
		root.add_child(m)
		await _settle(10)
		m.quick_play()
		frames = 30
	elif shot == "hint":
		world = load("res://world/world.tscn").instantiate()
		world.map_id = "arena"; world.bot_count = 3
		root.add_child(world)
		frames = 90
	process_frame.connect(_wait)

func _world(tutorial: bool) -> Node:
	var w: Node
	if tutorial:
		w = load("res://world/tutorial.gd").call("make_world")
	else:
		w = load("res://world/world.tscn").instantiate()
		w.map_id = "arena"; w.bot_count = 2
	root.add_child(w)
	return w

func _settle(n: int) -> void:
	for i in n: await process_frame

func _wait() -> void:
	frames -= 1
	if frames > 0: return
	process_frame.disconnect(_wait)
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("SHOT ", out, " ", img.get_size())
	quit(0)
