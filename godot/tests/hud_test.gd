extends SceneTree
## HUD / touch-layer / FPS-overlay test (headless). Runs an offline match with the touch layer on and phone safe-area
## insets, and checks: the HUD panels stay inside the safe area and apart from each other, the hotbar stays clear of
## the touch buttons (both hands), the keybind badges hide after a touch, nameplates show at most 3, the kill feed
## and toasts appear, and the FPS overlay follows Settings `show_fps`, F3 and a three-finger tap.
##   godot --headless --path godot --script res://tests/hud_test.gd -- --no-save   (npm run test:godot-ui)

const FRAME := 1.0 / 60.0
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _settings() -> Node:
	return root.get_node("Settings")

func _run() -> void:
	SafeArea.override = [81.0, 0.0, 81.0, 29.0]   # iPhone landscape notch + home indicator, canvas units
	_settings().set_value("touch_mode", "on")
	var world: Node = load("res://world/world.tscn").instantiate()
	world.auto_run = false
	world.bot_count = 5
	world.rng_seed = 99
	root.add_child(world)
	await process_frame
	var hud: Control = world.hud
	check(world.touch.visible, "touch layer on")
	for i in 240:
		world.tick(FRAME)
	await process_frame
	for lefty in [false, true]:
		_settings().set_value("touch_lefty", lefty)
		world.tick(FRAME)
		_layout(world, hud, "lefty" if lefty else "right")
	_settings().set_value("touch_lefty", false)
	# badges: shown after a key press, hidden after a touch
	var k := InputEventKey.new(); k.keycode = KEY_A; k.pressed = true
	root.window_input.emit(k)
	world.tick(FRAME)
	check(hud.get_node("Hotbar").show_keys, "keybind badges after a key press")
	var t := InputEventScreenTouch.new(); t.index = 0; t.position = Vector2(600, 100); t.pressed = true
	root.window_input.emit(t)
	world.tick(FRAME)
	check(not hud.get_node("Hotbar").show_keys, "keybind badges hidden after a touch")
	t = InputEventScreenTouch.new(); t.index = 0; t.position = Vector2(600, 100); t.pressed = false
	root.window_input.emit(t)
	# nameplates: at most 3
	check(hud.get_node("Nameplates")._plates.size() <= 3, "at most 3 nameplates (%d)" % hud.get_node("Nameplates")._plates.size())
	# feed + toast
	var sim: MatchSim = world.sim
	hud.add_feed(sim.player, sim.fighters[1], "smg", false)
	hud.add_feed(null, sim.fighters[2], "", true)
	hud.toast("K.O.!")
	world.tick(FRAME)
	check(hud.get_node("Feed").get_child_count() >= 2, "kill feed entries")
	check(hud.get_node("Toast").visible, "toast shows")
	hud._toast_t = 0.01
	world.tick(FRAME)
	check(not hud.get_node("Toast").visible, "toast hides when its time is up")
	_fps()
	SafeArea.override = []
	world.free()
	print("HUD ok" if fails == 0 else "HUD checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _layout(world: Node, hud: Control, tag: String) -> void:
	var vs: Vector2 = hud.get_viewport_rect().size
	var ins: Array = SafeArea.override
	var safe := Rect2(Vector2(ins[0], ins[1]), vs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	var names := ["Score", "Radar", "Health", "Hotbar"]
	var rects := {}
	for n: String in names:
		var c: Control = hud.get_node(n)
		var r := Rect2(c.position, c.size * c.scale)
		rects[n] = r
		check(safe.grow(0.5).encloses(r), "%s %s %s inside safe %s" % [tag, n, r, safe])
	for i in names.size():
		for j in range(i + 1, names.size()):
			check(not rects[names[i]].intersects(rects[names[j]]), "%s %s overlaps %s" % [tag, names[i], names[j]])
	var touch: Control = world.touch
	check(not rects["Score"].intersects(touch.pause_rect()) and not rects["Radar"].intersects(touch.pause_rect()), "%s pause button clear of the HUD" % tag)
	for b: Array in touch.BUTTONS:
		var r: Array = touch.button_rect(b)
		var br := Rect2(r[0] - Vector2(r[1], r[1]), Vector2(r[1], r[1]) * 2.0)
		check(not rects["Hotbar"].intersects(br), "%s hotbar clear of %s" % [tag, b[0]])
		check(not rects["Health"].intersects(br), "%s health clear of %s" % [tag, b[0]])
	var hb: Control = hud.get_node("Hotbar")
	check(hb.scale.x >= 0.6, "%s hotbar readable (scale %.2f)" % [tag, hb.scale.x])
	print("HUD layout %s checked" % tag)

func _fps() -> void:
	var ov: CanvasLayer = root.get_node("FpsOverlay")
	_settings().set_value("show_fps", false)
	check(not ov.visible, "fps overlay off by default")
	_settings().set_value("show_fps", true)
	check(ov.visible, "fps overlay follows show_fps")
	var k := InputEventKey.new(); k.keycode = KEY_F3; k.pressed = true
	root.window_input.emit(k)
	check(not ov.visible and not bool(_settings().get_value("show_fps")), "F3 toggles the overlay off")
	# three-finger tap
	for i in 3:
		var t := InputEventScreenTouch.new(); t.index = 10 + i; t.pressed = true
		root.window_input.emit(t)
	for i in 3:
		var t := InputEventScreenTouch.new(); t.index = 10 + i; t.pressed = false
		root.window_input.emit(t)
	check(ov.visible, "three-finger tap toggles the overlay on")
	_settings().set_value("show_fps", false)
	var st: Vector2 = ov.stats(PackedFloat64Array([1.0 / 60.0, 1.0 / 60.0, 1.0 / 20.0, 1.0 / 60.0]))
	check(absf(st.y - 20.0) < 0.01 and st.x > 30.0 and st.x < 60.0, "avg / 1%% low stats (%s)" % st)
