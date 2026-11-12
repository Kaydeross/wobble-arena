extends SceneTree
## The Practice Range (run by tools/test-range.js):
##   godot --headless --path godot --script res://tests/range_test.gd -- --no-save TRACE_JSON
## 1. PARITY: replays the web rangeBot trace (ten Practice Range dummies, the player walking about, K.O. / knock-down
##    windows) through PracticeRange.range_bot and compares wish, facing, speed, mover clock and position every step.
## 2. The Practice Range mode in world.tscn: 10 Wobbler dummies on the map's spots (home), they never attack, the movers
##    slide and the still ones stay, a K.O.'d dummy is back at home with full health 1.2 s later, the 12-weapon rack is
##    laid out, a taken rack weapon is in the hand and back on the rack 2.5 s later; the Test Map lays out every weapon;
##    a range map in Classic still gets its dummies. No node leaks.

const FRAME := 1.0 / 30.0
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var path := ""
	for s: String in a:
		if s.ends_with(".json"): path = s
	if path != "": _parity(path)
	else: print("FAIL no trace (run through tools/test-range.js)"); fails += 1
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	await _practice("practice", "practice")
	await _practice("practice", "test")
	await _practice("classic", "practice")
	await process_frame
	await process_frame
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("NODES before=%d after=%d orphans=%d" % [nodes0, nodes1, orphans])
	check(nodes1 <= nodes0 and orphans == 0, "no node leak (%d -> %d, %d orphans)" % [nodes0, nodes1, orphans])
	print("RANGE %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------------- 1. rangeBot parity ----------------

func _parity(path: String) -> void:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var dt := float(ref["dt"])
	var m: Dictionary = root.get_node("Content").get_map("practice")
	var rcfg: Dictionary = m["range"]
	var player := FighterState.new()
	player.phys.px = float(m["player"][0]); player.phys.pz = float(m["player"][1])
	var bots: Array = []
	var brains: Array = []
	for b: Array in m["bots"]:
		var f := FighterState.new()
		f.phys.px = float(b[0]); f.phys.pz = float(b[1]); f.phys.speed = PracticeRange.DUMMY_SPEED
		f.phys.want_jump = true
		bots.append(f); brains.append(BotBrain.new({}, "normal"))
	var worst := 0.0
	var first := ""
	var rows: Array = ref["rows"]
	for k in rows.size():
		var row: Array = rows[k]
		player.phys.px = float(row[0]); player.phys.pz = float(row[1])
		for i in bots.size():
			var b: FighterState = bots[i]
			var want: Array = row[2][i]
			b.dead = int(want[7]) == 1; b.down_t = float(want[8])
			b.yaw = b.face_yaw
			PracticeRange.range_bot(b, i, player, rcfg, dt, brains[i])
			b.phys.px += b.phys.wish_x * b.phys.speed * dt; b.phys.pz += b.phys.wish_z * b.phys.speed * dt
			var mine := [b.phys.wish_x, b.phys.wish_z, b.face_yaw, b.phys.speed, brains[i].mt, b.phys.px, b.phys.pz, 1 if b.dead else 0, b.down_t, b.swing, 1 if b.phys.want_jump else 0]
			for j in mine.size():
				var e := absf(float(mine[j]) - float(want[j]))
				if e > worst: worst = e
				if e > 1e-9 and first == "": first = "FIRST diff step %d dummy %d field %d: godot %s js %s" % [k, i, j, mine[j], want[j]]
	if first != "": print(first)
	print("PARITY rangeBot steps=%d dummies=%d worst_error=%s" % [rows.size(), bots.size(), String.num_scientific(worst)])
	check(worst <= 1e-9, "rangeBot matches the web game")

# ---------------- 2. the mode in the world ----------------

func _practice(mode: String, map: String) -> void:
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = map
	world.mode_id = mode
	world.auto_run = false
	world.bot_count = 3
	world.rng_seed = 4242
	world.dyn_choice = "off"
	root.add_child(world)
	var sim: MatchSim = world.sim
	var c := sim.combat
	var p := sim.player
	var tag := "%s/%s" % [mode, map]
	var mdata: Dictionary = sim.map
	var spots: Array = mdata["bots"]
	var movers: Dictionary = mdata["range"].get("movers", {})
	var bots: Array = sim.fighters.slice(1)
	check(not c.brawl and bots.size() == int(mdata["range"]["count"]), "%s: %d dummies, not brawlers (%d, brawl %s)" % [tag, int(mdata["range"]["count"]), bots.size(), c.brawl])
	for i in bots.size():
		var b: FighterState = bots[i]
		check(b.class_id == "wobbler" and b.home != null and absf(b.phys.px - float(spots[i][0])) < 0.01 and absf(b.phys.pz - float(spots[i][1])) < 0.01,
			"%s: dummy %d is a Wobbler at its spot %s (%s, %.1f %.1f)" % [tag, i, spots[i], b.class_id, b.phys.px, b.phys.pz])
	var rack := PracticeRange.rack(map, c, sim.pickups.drops.get("base", {}))
	var crates := sim.pickups.list.size()
	check(crates == rack.size() and crates == (12 if map == "practice" else 29), "%s: the weapon rack is laid out (%d crates, rack %d)" % [tag, crates, rack.size()])
	check(c.rules.hud_text(p).begins_with("Practice"), "%s: the HUD says Practice (%s)" % [tag, c.rules.hud_text(p)])
	# 4 s: the movers slide, the still ones stay, nobody attacks the player
	var hp0 := p.hp
	var start: Array = []
	for b: FighterState in bots: start.append(Vector2(b.phys.px, b.phys.pz))
	var travel: Array = []; travel.resize(bots.size()); travel.fill(0.0)
	for k in int(4.0 / FRAME):
		world.tick(FRAME)
		for i in bots.size():
			var b: FighterState = bots[i]
			travel[i] = maxf(travel[i], Vector2(b.phys.px, b.phys.pz).distance_to(start[i]))
	var moved := 0
	var still_ok := true
	for i in bots.size():
		if movers.has(str(i)):
			if travel[i] > 3.0: moved += 1
		elif travel[i] > 0.5: still_ok = false
	check(moved == movers.size(), "%s: every mover slides (%d of %d)" % [tag, moved, movers.size()])
	check(still_ok, "%s: the still dummies stay put %s" % [tag, travel])
	check(p.hp >= hp0 and int(p.st["taken"]) == 0 and not p.dead, "%s: the dummies never fight back" % tag)
	# a K.O.'d dummy pops back up at home
	var d: FighterState = bots[1]
	d.invuln = 0.0
	c.hit(d, 9999.0, 0.0, 0.0, -1.0, 6.0, false, p)
	check(d.dead and p.ko == 1, "%s: the dummy is K.O.'d and the player gets the K.O." % tag)
	var back := -1.0
	for k in int(3.0 / FRAME):
		world.tick(FRAME)
		if back < 0.0 and not d.dead: back = (k + 1) * FRAME
	check(back > 0.0 and back < 1.6 and d.hp >= c.max_hp(d) - 0.01, "%s: back up after %.2f s with full health" % [tag, back])
	check(absf(d.phys.px - float(d.home[0])) < 0.6 and absf(d.phys.pz - float(d.home[1])) < 0.6, "%s: back at home (%.1f %.1f vs %s)" % [tag, d.phys.px, d.phys.pz, d.home])
	# take a rack weapon: in the hand, then back on the rack 2.5 s later
	var e: Array = rack[1]
	p.phys.place(float(e[1]), 0.01, float(e[2]))
	world.tick(FRAME)
	var held := false
	for sl: Variant in p.slots: if sl != null and sl["key"] == e[0]: held = true
	check(held, "%s: walked onto the %s on the rack and got it" % [tag, e[0]])
	check(sim.pickups.list.size() == crates - 1 and sim.pickups.perm_q.size() == 1, "%s: the rack spot is empty for now" % tag)
	p.phys.place(float(mdata["player"][0]), 0.01, float(mdata["player"][1]))     # the start: away from the rack
	for k in int(3.0 / FRAME): world.tick(FRAME)
	var again := false
	for q: Dictionary in sim.pickups.list:
		if q["key"] == e[0] and absf(q["x"] - float(e[1])) < 0.01 and absf(q["z"] - float(e[2])) < 0.01: again = true
	check(again and sim.pickups.list.size() == crates, "%s: the %s is back on the rack" % [tag, e[0]])
	print("RANGE %-17s dummies=%d movers=%d/%d rack=%d back_up=%.2fs" % [tag, bots.size(), moved, movers.size(), crates, back])
	world.queue_free()
	await process_frame
