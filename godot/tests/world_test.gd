extends SceneTree
## Headless world test (run by tools/test-world.js):
##   godot --headless --path godot --script res://tests/world_test.gd -- --no-save
## 1. Autoloads are present and Content loaded every data file.
## 2. MapBuilder builds every map in maps.json without errors; solids count == geometry.boxes count.
## 4. Touch controls write move / held buttons / look into the shared InputState.
## 3. world.tscn on 'arena' and 'practice': 5 s of scripted input at SIM = 1/120; the player lands, stays on the floor
##    (never below it, never falls out) and is grounded when the input stops.

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	# autoloads are added to the root before the first frame; run the checks then
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var content := root.get_node_or_null("Content")
	check(content != null and root.has_node("Tier") and root.has_node("Settings"), "autoloads Content/Tier/Settings registered")
	if content == null:
		quit(1); return
	for k in ["weapons", "modes", "classes", "cosmetics", "difficulties", "crate_rates", "maps"]:
		check(not (content.get(k) as Dictionary).is_empty(), "Content." + k + " loaded")
	print("TIER ", root.get_node("Tier").tier_name())

	var n := 0
	for id in content.map_ids():
		var m: Dictionary = content.get_map(id)
		if PillarsMap.IDS.has(id): m = PillarsMap.complete(m)     # its boxes come from PillarsMap, not the export
		var node := MapBuilder.build(id)
		var want: int = m["geometry"]["boxes"].size()
		check(node.solids.size() == want, "%s solids %d != boxes %d" % [id, node.solids.size(), want])
		check(node.get_child_count() > 0, id + " has visuals")
		node.free()
		n += 1
	print("MAPS built=%d" % n)

	for id in ["arena", "practice"]:
		_sim_map(id)
	_touch_test()

	print("WORLD %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

## Scripted input: (seconds, move right, move forward, jump, sprint, look yaw per second)
const SCRIPT := [
	[0.6, 0.0, 0.0, false, false, 0.0],     # drop onto the floor
	[0.8, 0.0, 1.0, false, false, 0.0],     # walk forward
	[0.6, 1.0, 0.0, false, false, 0.0],     # strafe right
	[0.5, 0.0, 1.0, true, false, 1.5],      # bunny-hop while turning
	[0.7, -1.0, -0.4, false, false, 0.0],   # back-left
	[0.6, 0.0, 1.0, false, true, -2.0],     # sprint and turn
	[0.4, 0.0, 0.0, true, false, 0.0],      # jump in place
	[0.8, 0.0, 0.0, false, false, 0.0],     # stand still
]

func _sim_map(id: String) -> void:
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = id
	world.auto_run = false
	world.bot_count = 0   # movement only: no bots in the way
	world.dyn_choice = "off"   # steady floor: this checks the player stays at y = 0 (moving floors: tests/dynamics_test.gd)
	root.add_child(world)
	var sim: float = world.SIM
	var floor_y := 0.0
	var spawn: Vector3 = world.player_pos()
	var landed_at := -1.0
	var min_y_after_land := INF
	var steps := 0
	var st: InputState = world.input.state
	for seg in SCRIPT:
		st.set_move("script", Vector2(seg[1], seg[2]))
		st.hold("script", "jump", seg[3])
		st.hold("script", "sprint", seg[4])
		var k := int(round(float(seg[0]) / sim))
		for i in k:
			world.cam.add_look(Vector2(float(seg[5]) * sim, 0.0))
			world.sim_step(sim)
			steps += 1
			if landed_at < 0.0 and world.phys.grounded:
				landed_at = steps * sim
			if landed_at >= 0.0:
				min_y_after_land = minf(min_y_after_land, world.phys.py)
	var t := steps * sim
	check(absf(t - 5.0) < 0.02, "%s simulated %.2f s" % [id, t])
	check(landed_at >= 0.0 and landed_at < 0.5, "%s lands (at %.3f s)" % [id, landed_at])
	check(world.falls == 0, "%s never falls out (%d falls)" % [id, world.falls])
	check(min_y_after_land >= floor_y - 1e-6, "%s never sinks below the floor (min y %.4f)" % [id, min_y_after_land])
	check(world.phys.grounded and absf(world.phys.py - floor_y) < 1e-6, "%s ends grounded on the floor (y %.4f)" % [id, world.phys.py])
	var moved := Vector2(world.phys.px - spawn.x, world.phys.pz - spawn.z).length()
	check(moved > 2.0, "%s player moved (%.2f m)" % [id, moved])
	# a frame of the presentation path (camera follow, HUD) must not error
	world._process(1.0 / 60.0)
	check(world.cam.global_position.y > world.phys.py, "%s camera above the player" % id)
	print("SIM %s steps=%d landed=%.3fs end=(%.2f, %.3f, %.2f) moved=%.2fm min_y=%.4f" % [id, steps, landed_at, world.phys.px, world.phys.py, world.phys.pz, moved, min_y_after_land])
	world.free()

func _touch(tc: Control, i: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i; e.position = pos; e.pressed = pressed
	tc._input(e)

func _drag(tc: Control, i: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i; e.position = pos
	tc._input(e)

func _touch_test() -> void:
	var world: Node = load("res://world/world.tscn").instantiate()
	world.auto_run = false
	world.bot_count = 0
	root.add_child(world)
	var tc: Control = world.touch
	var st: InputState = world.input.state
	tc.visible = true
	var vs := tc.get_viewport_rect().size
	# left stick: press in the move zone, drag up past the edge -> full forward + sprint
	var o := Vector2(vs.x * 0.2, vs.y * 0.7)
	_touch(tc, 0, o, true)
	_drag(tc, 0, o + Vector2(0, -200))
	check(st.move().y > 0.99 and st.is_held("sprint"), "touch stick forward + sprint (move %s)" % st.move())
	# FIRE held while the stick is held (multi-touch)
	var fire: Array = tc.button_rect(tc.BUTTONS[0])
	_touch(tc, 1, fire[0], true)
	check(st.is_held("fire"), "touch FIRE held")
	_touch(tc, 1, fire[0], false)
	check(not st.is_held("fire"), "touch FIRE released")
	_touch(tc, 0, o, false)
	check(st.move() == Vector2.ZERO and not st.is_held("sprint"), "touch stick released")
	# at most 4 action buttons; MELEE: a tap shoves, a hold or a flick kicks
	check(tc.BUTTONS.size() <= 4, "at most 4 touch action buttons (%d)" % tc.BUTTONS.size())
	var melee: Array = tc.button_rect(tc.button("melee"))
	_touch(tc, 2, melee[0], true); _touch(tc, 2, melee[0], false)
	check(st.consume("shove") and not st.consume("shove") and not st.consume("kick"), "touch MELEE tap = one shove")
	_touch(tc, 2, melee[0], true); tc._process(0.4)
	check(st.consume("kick") and not st.consume("kick"), "touch MELEE hold = one kick")
	_touch(tc, 2, melee[0], false)
	check(not st.consume("shove"), "touch MELEE hold does not also shove")
	_touch(tc, 2, melee[0], true); _drag(tc, 2, melee[0] + Vector2(0, -60)); _touch(tc, 2, melee[0] + Vector2(0, -60), false)
	check(st.consume("kick") and not st.consume("shove"), "touch MELEE flick = kick")
	# context button: hidden empty-handed, RELOAD with a gun, DASH with a ninja weapon
	var sim: MatchSim = world.sim
	var p := sim.player
	tc._process(0.016)
	check(tc.context_action() == "" and tc.visible_buttons().size() == 3, "context button hidden empty-handed (%s)" % [tc.visible_buttons()])
	sim.combat.pickup(p, "smg")
	var gs: Dictionary = p.current_slot()
	gs["mag"] = 3
	tc._process(0.016)
	check(tc.context_action() == "reload", "context button = RELOAD with a gun (%s)" % tc.context_action())
	var ctx: Array = tc.button_rect(tc.button("context"))
	_touch(tc, 3, ctx[0], true); _touch(tc, 3, ctx[0], false)
	check(st.consume("reload") and not st.consume("reload"), "touch RELOAD tap = one press")
	sim.combat.pickup(p, "katana")
	for i in 3:
		if p.slots[i] != null and p.slots[i]["key"] == "katana": sim.combat.equip_slot(p, i)
	tc._process(0.016)
	var want_dash: bool = sim.combat.rules.dash_gear(p)
	check(tc.context_action() == ("dash" if want_dash else ""), "context button follows the katana (%s)" % tc.context_action())
	# hotbar: tap a slot equips it, tap the slot in hand swaps back, swipe cycles
	world.tick(1.0 / 60.0)
	var smg_i := -1
	var kat_i := -1
	for i in 3:
		if p.slots[i] != null and p.slots[i]["key"] == "smg": smg_i = i
		if p.slots[i] != null and p.slots[i]["key"] == "katana": kat_i = i
	var r0: Rect2 = tc.hotbar_slot_rect(smg_i)
	check(r0.size.x > 20.0, "hotbar slot has a touch area (%s)" % r0)
	_touch(tc, 5, r0.get_center(), true); _touch(tc, 5, r0.get_center(), false)
	check(st.peek("slot%d" % (smg_i + 1)), "tap on a hotbar slot equips it")
	world.tick(1.0 / 60.0)
	check(p.slot == smg_i, "smg in hand after the slot tap (%d)" % p.slot)
	_touch(tc, 5, r0.get_center(), true); _touch(tc, 5, r0.get_center(), false)
	check(st.consume("slot%d" % (kat_i + 1)), "tap on the slot in hand swaps back to the last weapon")
	var r1: Rect2 = tc.hotbar_slot_rect(1)
	_touch(tc, 5, r1.get_center(), true); _drag(tc, 5, r1.get_center() + Vector2(80, 0)); _touch(tc, 5, r1.get_center() + Vector2(80, 0), false)
	check(st.consume("swap"), "swipe across the hotbar cycles weapons")
	while st.consume("slot1") or st.consume("slot2") or st.consume("slot3"): pass
	# AIM: double-tap the look area toggles the scope; one tap does not
	st.aim_toggle = false
	var ap := Vector2(vs.x * 0.62, vs.y * 0.3)
	_touch(tc, 6, ap, true); _touch(tc, 6, ap, false)
	check(not st.aiming(), "one tap on the look area does not aim")
	_touch(tc, 6, ap, true); _touch(tc, 6, ap, false)
	check(st.aiming(), "double-tap on the look area toggles AIM on")
	_touch(tc, 6, ap, true); _touch(tc, 6, ap, false)
	_touch(tc, 6, ap, true); _touch(tc, 6, ap, false)
	check(not st.aiming(), "double-tap again toggles AIM off")
	# drag on the right half (away from the buttons) turns the camera: drag right -> yaw decreases
	st.take_look()
	var lp := Vector2(vs.x * 0.6, vs.y * 0.2)
	_touch(tc, 4, lp, true); _drag(tc, 4, lp + Vector2(100, 0)); _touch(tc, 4, lp + Vector2(100, 0), false)
	var look := st.take_look()
	check(look.x < -0.3 and absf(look.y) < 1e-6, "touch look drag (%s)" % look)
	# left-handed layout mirrors the buttons
	root.get_node("Settings").set_value("touch_lefty", true)
	var fire_l: Array = tc.button_rect(tc.BUTTONS[0])
	check(fire_l[0].x < vs.x * 0.5, "left-handed FIRE on the left")
	var melee_l: Array = tc.button_rect(tc.button("melee"))
	check(melee_l[0].x < vs.x * 0.5, "left-handed MELEE on the left")
	root.get_node("Settings").set_value("touch_lefty", false)
	print("TOUCH ok" if fails == 0 else "TOUCH checks failed")
	world.free()
