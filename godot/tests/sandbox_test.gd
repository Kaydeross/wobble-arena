extends SceneTree
## Sandbox (build mode) test, run by tools/test-sandbox.js (npm run test:godot-sandbox):
##   godot --headless --path godot --script res://tests/sandbox_test.gd -- --no-save [--out FILE]
## 1 logic (logic/sandbox_layout.gd): place / remove with the brush, the 150-block cap, arena bounds, someone in the
##   way, aiming (crosshair hit vs in front of the player), the web load() cleaning of cfg.blocks / cfg.custom, and a
##   save round trip through a real profile file (SaveProfile) keeping the rest of the web cfg; --out writes that
##   profile's blob so the runner can load it with the web game's own cfg code.
## 2 play-through: the world in build mode (no bots, no crates, the palette), place blocks with the palette buttons and
##   a touch on the Place button, stand on a block, remove one, Play: a Sandbox match with bots on the arena that has the
##   blocks (meshes and solids), played until the K.O. limit, the results panel's Edit arena back to build mode with
##   the same blocks.

const FRAME := 1.0 / 30.0
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var out := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size(): out = args[i + 1]
	_logic()
	_save_round_trip(out)
	await _play_through()
	print("SANDBOX %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ============================== logic ==============================

func _logic() -> void:
	var L := SandboxLayout.new()
	check(L.count() == 0 and int(L.custom["size"]) == 44 and L.custom["theme"] == "grass", "fresh layout: no blocks, the web defaults")
	# one block on the floor, then one on top of it (stacking by aim height)
	var r := L.place(Vector2(4, 6), 0.0)
	check(r["added"] == [[4, 0, 6]] and L.cols == [SandboxLayout.WEB_YELLOW], "place one block [4, 0, 6] (%s)" % [r])
	r = L.place(Vector2(4, 6), 0.0)
	check((r["added"] as Array).is_empty() and r["why"] == "taken" and L.count() == 1, "the same cell twice adds nothing")
	check(L.column_top(4, 6) == 2.0, "column top 2 m")
	r = L.place(Vector2(4, 6), 2.0)
	check(r["added"] == [[4, 2, 6]], "stack on top")
	# brush: 2x2, 3 high, red
	L.size = 2; L.height = 3; L.color = SandboxLayout.COLORS[1]
	r = L.place(Vector2(-10, -10), 0.0)
	check((r["added"] as Array).size() == 12 and L.count() == 14, "2x2 brush, 3 high = 12 blocks (%d)" % (r["added"] as Array).size())
	check(L.cols.count(SandboxLayout.COLORS[1]) == 12, "brush colour on every new block")
	var cells := L.brush_cells(Vector2(-10, -10))
	check(cells == [Vector2(-10, -10), Vector2(-10, -8), Vector2(-8, -10), Vector2(-8, -8)], "2x2 cells from the anchor (%s)" % [cells])
	# remove with the same brush takes the whole 2x2x3 stack
	var gone := L.remove(L.index_of(-10, 0, -10))
	check(gone.size() == 12 and L.count() == 2, "remove with the brush takes 12 (%d), 2 left" % gone.size())
	L.size = 1; L.height = 1
	check(L.remove(L.index_of(4, 2, 6)).size() == 1 and L.count() == 1, "remove one")
	# bounds: the arena is 44 m, blocks stay a cell inside
	check(not L.in_bounds(22, 0) and L.in_bounds(20, -20), "blocks stay on the floor")
	L.size = 3
	r = L.place(Vector2(20, 0), 0.0)
	check((r["added"] as Array).size() == 6, "a 3x3 brush at the edge only fills the cells on the floor (%d)" % (r["added"] as Array).size())
	L.clear(); L.size = 1
	# somebody in the way (the web check)
	r = L.place(Vector2(0, 0), 0.0, [Vector3(0.4, 0.0, -0.3)])
	check((r["added"] as Array).is_empty() and r["why"] == "blocked", "no block inside a fighter")
	r = L.place(Vector2(0, 0), 4.0, [Vector3(0.4, 0.0, -0.3)])
	check((r["added"] as Array).size() == 1, "a block above their head is fine")
	L.clear()
	# height cap
	r = L.place(Vector2(0, 0), SandboxLayout.MAX_YB + 2.0)
	check((r["added"] as Array).is_empty(), "no blocks above %.0f m" % SandboxLayout.MAX_YB)
	# the 150 cap
	L.size = 3; L.height = 4
	var n := 0
	for gx in range(-18, 19, 6):
		for gz in range(-18, 19, 6):
			n += (L.place(Vector2(gx, gz), 0.0)["added"] as Array).size()
	check(L.count() == SandboxLayout.MAX_BLOCKS and n == SandboxLayout.MAX_BLOCKS and L.full(), "stops at %d blocks (%d)" % [SandboxLayout.MAX_BLOCKS, L.count()])
	r = L.place(Vector2(0, 14), 8.0)
	check(r["why"] == "full", "full says so")
	# aiming: the crosshair hit on the floor 5 m ahead, and on the side of a block
	L.clear(); L.size = 1; L.height = 1
	var pos := Vector3(0, 0, 0)
	var t: Array = L.place_target(Vector3(0.3, 0.0, 5.6), Vector3(0, -0.4, 0.92).normalized(), pos, 0.0)
	check(t[0] == Vector2(0, 6) and t[1] == 0.0, "floor hit 5.6 m ahead -> cell (0, 6) on the floor (%s)" % [t])
	L.place(Vector2(0, 6), 0.0)
	t = L.place_target(Vector3(0.0, 1.0, 5.0), Vector3(0, 0, 1), pos, 0.0)
	check(t[0] == Vector2(0, 4) and t[1] == 0.0, "aiming at a block's side puts the next one in front of it (%s)" % [t])
	check(L.remove_target(Vector3(0.0, 1.0, 5.0), Vector3(0, 0, 1), pos, 0.0) == 0, "remove aims at the block hit")
	t = L.place_target(Vector3.ZERO, Vector3(0, 0, 1), pos, 0.0)
	check(t[0] == Vector2(0, 4) and t[1] == 0.0, "nothing hit: the cell in front of the player (%s)" % [t])
	t = L.place_target(Vector3(0, 0, 80), Vector3(0, 0, 1), pos, 0.0)
	check(t[0] == Vector2(0, 4), "a hit out of reach falls back to the cell in front (%s)" % [t])
	# the web load(): cfg.blocks filtered (3 finite numbers), first 150; cfg.custom key by key
	var dirty := {"custom": {"size": 60, "theme": "night", "seed": 123, "obs": "lots", "ice": 1}, "blocks": [[2, 0, 2], [1, 2], "x", [4, null, 4], [6, 0.0, 6.0], [8, 2, 8, 9]], "blockCols": "nope"}
	var D := SandboxLayout.new(dirty)
	check(D.blocks == [[2, 0, 2], [6, 0, 6]], "web cleaning of cfg.blocks (%s)" % [D.blocks])
	check(int(D.custom["size"]) == 60 and D.custom["theme"] == "night" and int(D.custom["seed"]) == 123 and int(D.custom["obs"]) == 10 and D.custom["ice"] == true, "web cleaning of cfg.custom (%s)" % [D.custom])
	check(D.cols == [SandboxLayout.WEB_YELLOW, SandboxLayout.WEB_YELLOW], "no blockCols: web yellow")
	var many: Array = []
	for i in 200: many.append([i * 2 % 40 - 20, 0, i])
	check(SandboxLayout.clean_blocks(many).size() == 150, "the web keeps the first 150")
	# JSON round trip of the save shape
	var A := SandboxLayout.new()
	A.color = SandboxLayout.COLORS[2]; A.size = 2; A.height = 2
	A.place(Vector2(6, -6), 0.0)
	A.custom["theme"] = "snow"; A.custom["seed"] = 4242
	var js := JSON.stringify(A.to_cfg())
	var B := SandboxLayout.new(JSON.parse_string(js))
	check(B.blocks == A.blocks and B.cols == A.cols and B.custom == A.custom, "JSON round trip keeps blocks, colours and the arena settings")
	check(js.contains('"blocks":[[6,0,-6],[6,2,-6]'), "blocks saved as [x, yBase, z] integers like the web (%s)" % js.substr(0, 120))
	# the map built from it: generated boxes + one 2 m box per block, in its colour
	var base := MapBuilder.custom_map(B.map_cfg(false))
	var m := MapBuilder.custom_map(B.map_cfg())
	var bx: Array = m["geometry"]["boxes"]
	check(bx.size() == (base["geometry"]["boxes"] as Array).size() + B.count(), "custom map has a box per block")
	var last: Dictionary = bx[bx.size() - 1]
	check(int(last["color"]) == SandboxLayout.COLORS[2] and float(last["w"]) == 2.0 and float(last["y"]) == 2.0, "block box in the brush colour (%s)" % [last])
	print("SANDBOX logic checked (%d blocks max, brush %s x %s)" % [SandboxLayout.MAX_BLOCKS, SandboxLayout.SIZES, SandboxLayout.HEIGHTS])

## A real profile file: the layout goes into cfg next to the web game's other cfg keys and comes back after a load.
func _save_round_trip(out: String) -> void:
	var P := "user://sandbox_test_profile.json"
	for f in [P, P + ".bak", P + ".tmp"]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var s := SaveProfile.new()
	s.path = P
	s.persist = true
	s.apply_blob({"v": 64, "cfg": {"mode": "pillars", "count": 5, "hp": 300, "blocks": [[0, 0, 0]]}, "map": "farm", "wallet": {"coins": 777}})
	var L := SandboxLayout.new(s.sandbox_cfg())
	check(L.blocks == [[0, 0, 0]], "a web save's blocks load")
	L.color = SandboxLayout.COLORS[3]; L.height = 2
	L.place(Vector2(-4, 8), 0.0)
	L.custom["theme"] = "candy"
	s.set_sandbox(L.to_cfg())
	var t := SaveProfile.new()
	t.path = P
	t.persist = true
	check(t.load_file() == "file", "profile written and read back")
	var c := t.sandbox_cfg()
	check(c.get("mode") == "pillars" and int(c.get("count", 0)) == 5 and int(c.get("hp", 0)) == 300, "the rest of the web cfg is kept (%s)" % [c])
	var L2 := SandboxLayout.new(c)
	check(L2.blocks == [[0, 0, 0], [-4, 0, 8], [-4, 2, 8]] and L2.cols == [SandboxLayout.WEB_YELLOW, SandboxLayout.COLORS[3], SandboxLayout.COLORS[3]], "blocks and colours back from the file (%s %s)" % [L2.blocks, L2.cols])
	check(L2.custom["theme"] == "candy" and t.coins == 777 and t.get_blob().get("map") == "farm", "arena settings, coins and other keys survive")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(t.get_blob()))
		f.close()
	s.free(); t.free()
	for f2 in [P, P + ".bak", P + ".tmp"]:
		if FileAccess.file_exists(f2): DirAccess.remove_absolute(ProjectSettings.globalize_path(f2))
	print("SANDBOX save round trip checked")

# ============================== play-through ==============================

func _play_through() -> void:
	var save: Node = root.get_node("Save")
	save.set_sandbox({"custom": {"size": 44, "theme": "grass", "obs": 6, "plat": 2, "pads": 2, "walls": 2, "ice": false, "seed": 7}, "blocks": [], "blockCols": []})
	root.get_node("Settings").set_value("touch_mode", "on")
	var world: Node = load("res://world/world.tscn").instantiate()
	world.auto_run = false
	world.build_mode = true
	world.bot_count = 3
	world.rng_seed = 4242
	world.player_class = "bruiser"
	root.add_child(world)
	await process_frame
	var sim: MatchSim = world.sim
	var hud: BuildHud = world.build_hud
	check(hud != null and hud.is_inside_tree(), "build mode shows the palette")
	check(sim.fighters.size() == 1 and sim.pickups.no_crates and sim.combat.mode_id == "sandbox", "build mode: just you, no crates, Sandbox (%d fighters)" % sim.fighters.size())
	check(not world.hud.get_node("Hotbar").visible and not world.hud.get_node("Score").visible, "the match panels make room for the palette")
	var base := sim.solids.size()
	for i in 45: world.tick(FRAME)            # land on the floor
	var p := sim.player
	# face +z, look slightly down: Place puts a block in front
	world.cam.yaw = 0.0; world.cam.pitch = -0.35
	world.tick(FRAME)
	var n: int = hud.place_now()
	check(n == 1 and sim.solids.size() == base + 1 and hud.layout.count() == 1, "Place adds a block and its solid (%d, solids %d -> %d)" % [n, base, sim.solids.size()])
	check(hud.blocks_root.get_child_count() > 0, "the block is drawn")
	# a touch on the Place button (the touch layer must not take it)
	hud.layout_ui()
	var pb: Button = hud.tool_bs["place"]
	var c := pb.get_global_rect().get_center()
	hud.layout.height = 2
	_touch(0, c, true); _touch(0, c, false)
	world.tick(FRAME)
	check(hud.layout.count() >= 2, "a tap on Place builds (%d blocks)" % hud.layout.count())
	check(not world.touch._touch.has(0), "the touch layer did not take the palette tap")
	# Style: a brush and a colour through the panel
	hud.toggle_style(true)
	world.tick(FRAME)
	await process_frame
	hud.layout_ui()
	await process_frame
	var blue: Button = hud.color_bs[SandboxLayout.COLORS[2]]
	_touch(1, blue.get_global_rect().get_center(), true); _touch(1, blue.get_global_rect().get_center(), false)
	check(hud.layout.color == SandboxLayout.COLORS[2], "tap a colour swatch")
	hud.set_brush(2); hud.set_height(1)
	hud.toggle_style(false)
	# walk to the side and build a 2x2 step, then stand on it
	p.phys.place(8.0, 0.2, -8.0); p.yaw = 0.0
	world.cam.yaw = 0.0; world.cam.pitch = -0.3
	for i in 10: world.tick(FRAME)
	n = hud.place_now()
	check(n == 4, "a 2x2 brush puts down 4 (%d)" % n)
	var b0: Array = hud.layout.blocks[hud.layout.count() - 1]
	p.phys.place(float(b0[0]), 4.0, float(b0[2]))
	for i in 40: world.tick(FRAME)
	check(absf(p.phys.py - 2.0) < 0.15 and p.phys.grounded, "you can stand on a block (y %.2f)" % p.phys.py)
	p.phys.place(8.0, 0.2, -8.0); p.yaw = 0.0                  # back where the step was built: aim at it
	world.cam.yaw = 0.0; world.cam.pitch = -0.3
	for i in 20: world.tick(FRAME)
	var before: int = hud.layout.count()
	hud.set_brush(1)
	var rm: int = hud.remove_now()
	check(rm >= 1 and hud.layout.count() == before - rm and sim.solids.size() == base + hud.layout.count(), "Remove takes a block and its solid (%d)" % rm)
	var built: Array = hud.layout.blocks.duplicate(true)
	var cols: Array = hud.layout.cols.duplicate()
	# Play: saved, then a match with bots on this arena
	world.ko_limit = 3
	hud.play()
	check(SandboxLayout.new(save.sandbox_cfg()).blocks == built, "Play saved the arena")
	await process_frame
	await process_frame
	sim = world.sim
	check(not world.build_mode and world.build_hud == null and world.hud.get_node("Hotbar").visible, "Play left build mode")
	check(sim.combat.mode_id == "sandbox" and sim.fighters.size() == 4, "a Sandbox match with 3 bots (%d fighters)" % sim.fighters.size())
	var gen := (MapBuilder.custom_map(SandboxLayout.new(save.sandbox_cfg()).map_cfg(false))["geometry"]["boxes"] as Array).size()
	check(sim.solids.size() == gen + built.size(), "the match arena has every block as a solid (%d = %d + %d)" % [sim.solids.size(), gen, built.size()])
	var mb: Array = sim.map["geometry"]["boxes"]
	check(int(mb[mb.size() - 1]["color"]) == int(cols[cols.size() - 1]), "blocks keep their colour in the match")
	var r := sim.combat.rules
	var st: InputState = world.input.state
	var frames := int(8.0 * 60.0 / FRAME)
	var over_at := -1.0
	var i := 0
	while i < frames:
		p = sim.player
		var tg: FighterState = null
		var bd := 1e9
		for f: FighterState in sim.fighters:
			if f == p or f.dead: continue
			var d := Vector2(f.phys.px - p.phys.px, f.phys.pz - p.phys.pz).length()
			if d < bd: bd = d; tg = f
		var go := Vector2.ZERO
		if tg != null and not p.dead:
			var dv := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
			world.cam.yaw = atan2(dv.x, dv.y); world.cam.pitch = -0.12
			go = Vector2(0, 1) if dv.length() > 1.6 else Vector2.ZERO
			st.hold("script", "fire", dv.length() < 3.0)
			if i % 41 == 0: st.press("kick")
		st.set_move("script", go)
		st.hold("script", "jump", i % 87 < 2)
		world.tick(FRAME)
		if r.match_over and over_at < 0.0:
			over_at = sim.elapsed()
			frames = mini(frames, i + int((ModeRules.END_TIME + 0.5) / FRAME))
		i += 1
	var w := r.winner
	print("SANDBOX match on the built arena: over=%s at=%.0fs winner=%s kos=%d blocks=%d" % [r.match_over, over_at, w.name if w else "-", w.ko if w else 0, built.size()])
	check(r.match_over and w != null and w.ko >= 3, "the test run ended at the K.O. limit")
	check(_find(world._results, "EditArena") != null, "results offer Edit arena")
	world.edit_arena()
	await process_frame
	await process_frame
	check(world.build_mode and world.build_hud != null and world.build_hud.layout.blocks == built and world.sim.fighters.size() == 1, "Edit arena: back to build mode with the same blocks")
	check(world.sim.solids.size() == gen + built.size(), "build mode solids = arena + blocks again")
	world.queue_free()
	await process_frame
	print("SANDBOX play-through checked")

func _find(n: Node, nm: String) -> Node:
	if n == null: return null
	return n.find_child(nm, true, false)

func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx; t.position = root.get_final_transform() * pos; t.pressed = down     # canvas units -> window pixels
	root.push_input(t)
