extends SceneTree
## HUD / touch-layer / FPS-overlay test (headless). Runs an offline match with the touch layer on and phone safe-area
## insets, and checks: the HUD panels stay inside the safe area and apart from each other, the hotbar stays clear of
## the touch buttons (both hands), the keybind badges hide after a touch, nameplates show at most 3, the kill feed
## and toasts appear, and the FPS overlay follows Settings `show_fps`, F3 and a three-finger tap. Then the same layout
## checks at phone / tablet sizes with the UI scale applied (root window resized, Tier.apply_ui_scale) and every touch
## target (action buttons, pause, emote, hotbar slots) at least 44 pt. Congestion guardrails (docs/UI_REVIEW.md): no HUD label
## below UiTheme.MIN_FONT, the stack under the top edge (toast, team board, mode / spectator line) keeps a gap, and the
## results panel clears the toast and dims the HUD behind it.
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
	_settings().set_value("perf_overlay", true)    # the device readout (ui/perf_overlay.gd) is laid out with the HUD below
	await process_frame
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
	# air recovery: in the air without dash gear the context button becomes RECOVER (same slot, still <= 4 buttons)
	var pl: FighterState = world.sim.player
	pl.phys.place(pl.phys.px, 3.0, pl.phys.pz); pl.phys.grounded = false
	pl.last_hit_time = world.sim.combat.time - 0.5        # knocked: the button offers RECOVER (plain jumps keep RELOAD)
	world.touch._refresh_context()
	check(world.touch.context_action() == "recover", "context button is recover after a knock (%s)" % world.touch.context_action())
	check(world.touch.visible_buttons().size() <= 4, "at most 4 action buttons in the air")
	world.touch.queue_redraw()
	await process_frame
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
	_fonts(hud)
	await _sizes(world, hud)
	_fps()
	# results: the toast goes away (and stays away) and the panel has a dimmed backdrop over the HUD
	hud.toast("K.O.!")
	world._show_offline_results(true, "")
	check(not hud.get_node("Toast").visible, "the results panel clears the HUD toast")
	hud.toast("late toast")
	check(not hud.get_node("Toast").visible, "no toast while the results panel is up")
	check(world.get_node("UI").get_node_or_null("ResultsDim") != null, "the results panel dims the HUD behind it")
	world.free()
	await process_frame
	await _team_layout()
	await _build_layout()
	await _arcade_layout()
	SafeArea.override = []
	print("HUD ok" if fails == 0 else "HUD checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

## No HUD label is smaller than UiTheme.MIN_FONT.
func _fonts(n: Node) -> void:
	for c in n.get_children():
		if c is Label and (c as Label).text != "":
			var fs: int = (c as Label).get_theme_font_size("font_size")
			check(fs >= UiTheme.MIN_FONT, "HUD label '%s' font %d is below %d" % [(c as Label).text, fs, UiTheme.MIN_FONT])
		_fonts(c)

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
	# touch buttons: at most 4 shown, inside the safe area, apart from each other and from the pause button
	check(touch.visible_buttons().size() <= 4, "%s at most 4 action buttons (%s)" % [tag, touch.visible_buttons()])
	var circles := []
	for b: Array in touch.BUTTONS:
		var r: Array = touch.button_rect(b)
		var br := Rect2(r[0] - Vector2(r[1], r[1]), Vector2(r[1], r[1]) * 2.0)
		check(safe.grow(0.5).encloses(br), "%s button %s %s inside safe %s" % [tag, b[0], br, safe])
		check(not br.intersects(touch.pause_rect()), "%s button %s clear of pause" % [tag, b[0]])
		for o: Array in circles:
			check(r[0].distance_to(o[0]) >= r[1] + o[1] + 8.0, "%s button %s apart from the others" % [tag, b[0]])
		circles.append(r)
	for i in 4:
		var sr: Rect2 = touch.hotbar_slot_rect(i)
		check(sr.size.x >= 40.0 and sr.size.y >= 40.0, "%s hotbar slot %d tappable (%s)" % [tag, i, sr])
	# the emote button (ui/emote_wheel.gd): under the pause button, inside the safe area, clear of everything else
	var er: Rect2 = world.emote_wheel.button_rect()
	check(world.emote_wheel.shown(), "%s emote button shown" % tag)
	check(safe.grow(0.5).encloses(er), "%s emote button %s inside safe %s" % [tag, er, safe])
	check(not er.intersects(touch.pause_rect()), "%s emote button clear of pause" % tag)
	for n: String in names:
		check(not er.intersects(rects[n]), "%s emote button %s overlaps %s %s" % [tag, er, n, rects[n]])
	var fd: Control = hud.get_node("Feed")
	check(not er.intersects(Rect2(fd.position, fd.size)), "%s emote button clear of the kill feed" % tag)
	for b: Array in touch.BUTTONS:
		var r2: Array = touch.button_rect(b)
		check(er.get_center().distance_to(r2[0]) >= er.size.x / 2.0 + r2[1] + 6.0, "%s emote button apart from %s" % [tag, b[0]])
	check(touch.visible_buttons().size() <= 4, "%s still at most 4 action buttons" % tag)
	var hb: Control = hud.get_node("Hotbar")
	check(hb.scale.x >= 0.6, "%s hotbar readable (scale %.2f)" % [tag, hb.scale.x])
	_perf_layout(world, hud, safe, rects, er, tag)
	print("HUD layout %s checked" % tag)

## The performance readout (Settings `perf_overlay`): inside the safe area, clear of every HUD panel, the pause and emote
## buttons, the touch buttons, the mode line and team board, the toast and the centre message.
func _perf_layout(world: Node, hud: Control, safe: Rect2, rects: Dictionary, er: Rect2, tag: String) -> void:
	var ov: PerfOverlay = root.get_node_or_null("PerfOverlay")
	check(ov != null, "%s perf readout exists" % tag)
	if ov == null: return
	ov.label.text = PerfOverlay.format({"fps": 60.0, "frame_ms_avg": 16.7, "frame_ms_p95": 17.2, "cpu_ms": 4.1, "gpu_ms": 6.2, "draws": 612, "objects": 1234,
		"tier": "MID", "thermal": "n/a", "mem_mb": 310.0}, "Soak 12:34 / 15:00")     # the widest text it shows
	ov.place()
	var r := ov.rect()
	check(safe.grow(0.5).encloses(r), "%s perf readout %s inside safe %s" % [tag, r, safe])
	for n: String in rects:
		check(not r.intersects(rects[n]), "%s perf readout %s overlaps %s %s" % [tag, r, n, rects[n]])
	var touch: Control = world.touch
	check(not r.intersects(touch.pause_rect()), "%s perf readout clear of pause" % tag)
	check(not r.intersects(er), "%s perf readout clear of the emote button" % tag)
	for b: Array in touch.BUTTONS:
		var c: Array = touch.button_rect(b)
		check(not r.intersects(Rect2(c[0] - Vector2(c[1], c[1]), Vector2(c[1], c[1]) * 2.0)), "%s perf readout clear of %s" % [tag, b[0]])
	for sib: String in ["Feed", "Toast", "Center", "Hint"]:
		var c: Control = hud.get_node_or_null(sib)
		if c != null and c.visible: check(not r.intersects(Rect2(c.position, c.size * c.scale)), "%s perf readout clear of %s" % [tag, sib])
	for sib: String in ["ModeLine", "TeamBoard"]:
		var c: Control = world.get_node("UI").get_node_or_null(sib)
		if c != null and c.visible: check(not r.intersects(Rect2(c.position, c.size * c.scale)), "%s perf readout clear of %s" % [tag, sib])

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

## Phone and tablet sizes (points, safe-area insets in points) at the Auto UI scale of a touch screen: the root window
## is resized and Tier applies UiScale like on a device; the layout checks above run on the scaled canvas, and every
## touch target (action buttons, pause, emote, hotbar slots) must be at least 44 pt.
const SIZES := [
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]], [Vector2(736, 414), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(812, 375), [44.0, 0.0, 44.0, 21.0]], [Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(926, 428), [47.0, 0.0, 47.0, 21.0]], [Vector2(1194, 834), [0.0, 24.0, 0.0, 20.0]],
	[Vector2(1024, 768), [0.0, 20.0, 0.0, 0.0]],
]

func _sizes(world: Node, hud: Control) -> void:
	var tier: Node = root.get_node("Tier")
	tier.force_ui_scale = true
	var size0 := root.size
	var ins0: Array = SafeArea.override
	for c: Array in SIZES:
		var win: Vector2 = c[0]
		root.size = Vector2i(win)
		tier.apply_ui_scale()
		await process_frame
		var vs := root.get_visible_rect().size
		var k := vs.x / win.x          # canvas px per pt
		check(absf(vs.x - UiScale.canvas_size(win).x) <= 1.5, "%s canvas %s matches UiScale %s" % [win, vs, UiScale.canvas_size(win)])
		SafeArea.override = (c[1] as Array).map(func(v: float) -> float: return v * k)
		world.touch._update_insets()
		hud._update_insets()
		var low := INF
		for lefty in [false, true]:
			_settings().set_value("touch_lefty", lefty)
			for i in 3: world.tick(FRAME)
			var tag := "%dx%d %s" % [win.x, win.y, "lefty" if lefty else "right"]
			_layout(world, hud, tag)
			low = minf(low, _taps(world, 1.0 / k, tag))
		print("HUD tap targets %dx%d (canvas %dx%d, scale %.2f): min %.1f pt" % [win.x, win.y, vs.x, vs.y, root.content_scale_factor, low])
	_settings().set_value("touch_lefty", false)
	root.size = size0
	tier.force_ui_scale = false
	root.content_scale_factor = 1.0
	SafeArea.override = ins0
	await process_frame
	world.touch._update_insets()
	hud._update_insets()

## Every touch target in pt (`pt` = pt per canvas px); returns the smallest.
func _taps(world: Node, pt: float, tag: String) -> float:
	var touch: Control = world.touch
	var low := INF
	var sizes := {}
	for id: String in touch.visible_buttons():
		sizes[id] = Vector2.ONE * touch.button_rect(touch.button(id))[1] * 2.0
	sizes["pause"] = touch.pause_rect().size
	sizes["emote"] = world.emote_wheel.button_rect().size
	for i in 4: sizes["slot%d" % i] = touch.hotbar_slot_rect(i).size
	for id: String in sizes:
		var m: float = minf(sizes[id].x, sizes[id].y) * pt
		low = minf(low, m)
		check(m >= 44.0 - 0.05, "%s %s touch target %.1f pt (%s px)" % [tag, id, m, sizes[id]])
	return low

## Team modes: the TeamBoard, the mode line (chaos event / dash), the crate toast and every HUD panel stay inside the
## safe area and never overlap each other or the pause button, with the toast showing (worst case).
func _team_layout() -> void:
	for mode in ["tdm", "chaos"]:
		var world: Node = load("res://world/world.tscn").instantiate()
		world.auto_run = false
		world.mode_id = mode
		world.dyn_choice = "off"
		world.bot_count = 9 if mode == "chaos" else 5
		world.rng_seed = 31
		root.add_child(world)
		await process_frame
		var hud: Control = world.hud
		hud.toast("Crate incoming: Mammoth Sniper Rifle!")
		world.sim.combat.pickup(world.sim.player, "rocket")   # a burst weapon: the mode line also shows its "Shots" pips
		for i in 90:
			world.tick(FRAME)
		var pl: FighterState = world.sim.player
		if not pl.dead and pl.weapon == "rocket":
			check(world.sim.combat.rules.hud_text(pl).contains("Shots"), "%s mode line shows the burst pips" % mode)
		var vs: Vector2 = hud.get_viewport_rect().size
		var ins: Array = SafeArea.override
		var safe := Rect2(Vector2(ins[0], ins[1]), vs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
		var rects := {}
		for n: String in ["Score", "Radar", "Health", "Hotbar", "Toast"]:
			var c: Control = hud.get_node(n)
			if c.visible: rects[n] = Rect2(c.position, c.size * c.scale)
		var board: Control = world.get_node("UI/TeamBoard")
		check(board.visible, "%s team board shown" % mode)
		rects["TeamBoard"] = Rect2(board.position, board.size)
		var ml: Control = world.get_node("UI/ModeLine")
		if ml.visible: rects["ModeLine"] = Rect2(ml.position, ml.size)
		rects["Pause"] = world.touch.pause_rect()
		rects["Emote"] = world.emote_wheel.button_rect()
		# the stack under the top edge: toast, then the team board, then the mode line, each with a gap
		if rects.has("Toast"): check(rects["TeamBoard"].position.y - rects["Toast"].end.y >= 6.0, "%s the team board hangs %.0f px under the toast (need 6)" % [mode, rects["TeamBoard"].position.y - rects["Toast"].end.y])
		if rects.has("ModeLine"): check(rects["ModeLine"].position.y - rects["TeamBoard"].end.y >= 2.0, "%s the mode line keeps clear of the team board" % mode)
		var keys := rects.keys()
		for k: String in keys:
			if k != "Pause" and k != "Toast" or k == "Emote":
				check(safe.grow(0.5).encloses(rects[k]), "%s %s %s inside safe %s" % [mode, k, rects[k], safe])
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				check(not rects[keys[i]].intersects(rects[keys[j]]), "%s: %s %s overlaps %s %s" % [mode, keys[i], rects[keys[i]], keys[j], rects[keys[j]]])
		print("HUD teams %s checked (%s)" % [mode, ", ".join(keys)])
		world.free()
		await process_frame

## Construction Arcade (dlc/construction/arcade_boss_hud.gd): the run strip and the boss bar hang under the toast, between the K.O. panel
## and the radar, and the mode line starts under them; at every phone / tablet size and both handedness settings they stay inside
## the safe area and clear of the HUD panels, the kill feed, the toast, the pause / emote buttons and the touch buttons; the
## labels are at least MIN_FONT and the boss name fits its bar. Three stages: the crew (strip only), the Project Manager (boss bar
## and the arena line from the deadline shrink) and the Client (boss bar).
func _arcade_layout() -> void:
	var AM: GDScript = load("res://dlc/construction/arcade_manager.gd")
	var tier: Node = root.get_node("Tier")
	_settings().set_value("touch_mode", "on")
	root.get_node("Save").dlc["owned"] = true
	var size0 := root.size
	var ins0: Array = SafeArea.override
	tier.force_ui_scale = true
	var n_layouts := 0
	for stage in [0, 4, 5]:
		var world: Node = AM.call("launch", 11)
		world.arcade.stage = stage
		world.arcade.difficulty_override = "easy"
		world.auto_run = false
		world.rng_seed = 31
		root.add_child(world)
		await process_frame
		world.arcade.begin_fight()
		var hud: Control = world.hud
		hud.add_feed(world.sim.player, world.sim.fighters[1], "hammer", false)       # the widest top-right content
		hud.add_feed(null, world.sim.fighters[1], "", true)
		for i in 30: world.tick(FRAME)
		var ah: Control = world.arcade.hud
		check(ah.visible and ah.boss_visible() == (stage > 0), "arcade stage %d: boss bar %s" % [stage + 1, ah.boss_visible()])
		for c: Array in SIZES:
			var win: Vector2 = c[0]
			root.size = Vector2i(win)
			tier.apply_ui_scale()
			await process_frame
			var vs := root.get_visible_rect().size
			var k := vs.x / win.x
			SafeArea.override = (c[1] as Array).map(func(v: float) -> float: return v * k)
			world.touch._update_insets()
			hud._update_insets()
			for lefty in [false, true]:
				_settings().set_value("touch_lefty", lefty)
				hud.toast("Crate incoming: Mammoth Sniper Rifle!")
				world.sim.player.hp = 150.0
				for i in 3: world.tick(FRAME)
				_arcade_checks(world, "arcade s%d %dx%d %s" % [stage + 1, win.x, win.y, "lefty" if lefty else "right"])
				n_layouts += 1
		world.free()
		await process_frame
	_settings().set_value("touch_lefty", false)
	root.size = size0
	tier.force_ui_scale = false
	root.content_scale_factor = 1.0
	SafeArea.override = ins0
	await process_frame
	print("HUD arcade: %d layouts checked (3 stages x %d sizes x 2 hands)" % [n_layouts, SIZES.size()])

func _arcade_checks(world: Node, tag: String) -> void:
	var hud: Control = world.hud
	var ah: Control = world.arcade.hud
	var vs: Vector2 = hud.get_viewport_rect().size
	var ins: Array = SafeArea.override
	var safe := Rect2(Vector2(ins[0], ins[1]), vs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	var r := Rect2(ah.position, ah.size)
	check(safe.grow(0.5).encloses(r), "%s HUD %s inside safe %s" % [tag, r, safe])
	var others := {}
	for n: String in ["Score", "Radar", "Health", "Hotbar", "Toast"]:
		var c: Control = hud.get_node(n)
		if c.visible: others[n] = Rect2(c.position, c.size * c.scale)
	var fd: Control = hud.get_node("Feed")
	if fd.get_child_count() > 0: others["Feed"] = Rect2(fd.position, fd.size)
	var ml: Control = world.get_node("UI/ModeLine")
	if ml.visible: others["ModeLine"] = Rect2(ml.position, ml.size)
	others["Pause"] = world.touch.pause_rect()
	others["Emote"] = world.emote_wheel.button_rect()
	for b: Array in world.touch.BUTTONS:
		var br: Array = world.touch.button_rect(b)
		others["btn " + str(b[0])] = Rect2(br[0] - Vector2(br[1], br[1]), Vector2(br[1], br[1]) * 2.0)
	for n: String in others:
		check(not r.intersects(others[n]), "%s HUD %s overlaps %s %s" % [tag, r, n, others[n]])
	if others.has("Toast"): check(r.position.y - others["Toast"].end.y >= 6.0, "%s the HUD hangs %.0f px under the toast (need 6)" % [tag, r.position.y - others["Toast"].end.y])
	if others.has("ModeLine"): check(others["ModeLine"].position.y - r.end.y >= 2.0, "%s the mode line keeps clear of the HUD" % tag)
	for l: Label in [ah.strip, ah.name_l, ah.pct_l]:
		if l.is_visible_in_tree() and l.text != "":
			var fs: int = l.get_theme_font_size("font_size")
			check(fs >= UiTheme.MIN_FONT, "%s label '%s' font %d below %d" % [tag, l.text, fs, UiTheme.MIN_FONT])
			var tw: float = l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			check(tw <= l.size.x + 0.5, "%s label '%s' (%.0f px) fits its %.0f px box" % [tag, l.text, tw, l.size.x])
	if ah.bar.visible:
		check(ah.name_l.size.x + ah.pct_l.size.x <= ah.bar.size.x, "%s name and percent fit the bar" % tag)

## Sandbox build mode (ui/build_hud.gd): the palette, its status line and the open Style panel stay inside the safe area,
## apart from each other, the touch buttons, the pause and emote buttons and a toast, on a phone (1170 x 540 canvas)
## and a tablet (4:3) shape, right- and left-handed; every tap target is at least 44 pt (60 canvas units).
func _build_layout() -> void:
	var win0 := root.size
	for shape: Vector2i in [Vector2i(1170, 540), Vector2i(720, 540)]:
		root.size = shape
		var world: Node = load("res://world/world.tscn").instantiate()
		world.auto_run = false
		world.build_mode = true
		world.rng_seed = 5
		root.add_child(world)
		await process_frame
		var bh: BuildHud = world.build_hud
		check(bh != null, "build mode palette")
		if bh == null:
			world.free(); continue
		for lefty in [false, true]:
			_settings().set_value("touch_lefty", lefty)
			bh.toggle_style(true)
			world.hud.toast("Blocks cleared")
			world.tick(FRAME)
			await process_frame
			world.tick(FRAME)
			await process_frame
			bh.layout_ui()
			var tag := "%dx%d %s" % [int(bh.get_viewport_rect().size.x), int(bh.get_viewport_rect().size.y), "lefty" if lefty else "right"]
			var vs: Vector2 = bh.get_viewport_rect().size
			var ins: Array = SafeArea.override
			var safe := Rect2(Vector2(ins[0], ins[1]), vs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
			var touch: Control = world.touch
			var rects := {"Palette": bh.bar.get_global_rect(), "Status": bh.status.get_global_rect(), "Style": bh.panel.get_global_rect(),
				"Pause": touch.pause_rect(), "Emote": world.emote_wheel.button_rect()}
			var tst: Control = world.hud.get_node("Toast")
			if tst.visible: rects["Toast"] = Rect2(tst.position, tst.size * tst.scale)
			for b: Array in touch.BUTTONS:
				if not touch.visible_buttons().has(b[0]): continue
				var r: Array = touch.button_rect(b)
				rects["btn_" + str(b[0])] = Rect2(r[0] - Vector2(r[1], r[1]), Vector2(r[1], r[1]) * 2.0)
			for k: String in ["Palette", "Status", "Style"]:
				check(safe.grow(0.5).encloses(rects[k]), "build %s %s %s inside safe %s" % [tag, k, rects[k], safe])
			var keys := rects.keys()
			for i in keys.size():
				for j in range(i + 1, keys.size()):
					if keys[i].begins_with("btn_") and keys[j].begins_with("btn_"): continue
					if keys[i] in ["Pause", "Emote"] and keys[j] in ["Pause", "Emote"]: continue
					check(not rects[keys[i]].intersects(rects[keys[j]]), "%s: %s %s overlaps %s %s" % [tag, keys[i], rects[keys[i]], keys[j], rects[keys[j]]])
			var taps: Array = bh.tool_bs.values() + bh.color_bs.values() + bh.size_bs.values() + bh.height_bs.values()
			for b: Button in taps:
				var r2 := b.get_global_rect()
				check(r2.size.x >= BuildHud.MIN_TAP - 0.5 and r2.size.y >= BuildHud.MIN_TAP - 0.5, "%s %s %s at least 44 pt" % [tag, b.name, r2.size])
			print("HUD build %s checked (%s)" % [tag, ", ".join(keys)])
			bh.toggle_style(false)
		_settings().set_value("touch_lefty", false)
		world.free()
		await process_frame
	root.size = win0
