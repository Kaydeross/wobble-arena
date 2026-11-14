extends SceneTree
## Random starting spot test (headless): MatchSim.setup(.., random_start = true) starts the player on one of the map's
## own safe points (its fixed player point + spawns + bot spots, deduplicated), on the floor (never inside a solid or
## under it) and at least 2 m from the void; different matches give different spots; random_start = false restores the
## old fixed spot, and -1 (auto) keeps the fixed spot in a test run (--no-save), which is what protects bot parity.
## Every arena the game plays is checked, the generated ones included (Sandbox, Building Site, Pillars, Lava Pillars).
##   godot --headless --path godot --script res://tests/start_spots_test.gd -- --no-save   (npm run test:godot-start-spots)

const RANDOM_MAPS := ["arena", "park", "ice", "temple", "rooftops", "tower", "dojo", "summit", "volcano", "crossroads",
	"blast", "siteyard", "pillars", "pillars2"]
var fails := 0
var content: Node

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	content = root.get_node("Content")
	check(MatchSim.start_randomised(true) and not MatchSim.start_randomised(false), "the flag itself forces random on / off")
	var test_run := OS.get_cmdline_user_args().has("--no-save")
	check(test_run, "the runner passes --no-save")
	check(not MatchSim.start_randomised(-1), "auto (with --no-save) keeps the old fixed spot: bot parity is safe")
	_every_map()
	_variety()
	_fixed()
	print("START-SPOTS %s" % ("ok" if fails == 0 else "FAILED %d" % fails))
	quit(0 if fails == 0 else 1)

## A map ready to play: the generated levels are built the way World.load_map builds them.
func _map(id: String) -> Dictionary:
	if id == "custom": return MapBuilder.custom_map({})
	if id == SiteMap.ID: return SiteMap.generate(424242)
	if PillarsMap.IDS.has(id):
		var m: Dictionary = PillarsMap.complete(content.get_map("pillars"))
		return PillarsMap.lava_entry(m) if id == "pillars2" else m
	return (content.get_map(id) as Dictionary).duplicate(true)   # (the test tags it with _id / _mode)

func _sim(map: Dictionary, random_start: Variant, rng_seed := 0) -> MatchSim:
	var sim := MatchSim.new()
	if rng_seed > 0: sim.combat.rng = CombatRng.new(rng_seed)
	sim.configure(str(map.get("_mode", "classic")), -1)
	sim.setup(str(map.get("_id", "arena")), map, map.get("geometry", {}).get("ladders", []), map.get("geometry", {}).get("bouncePads", []),
		"wobbler", PlayerControl.new(InputState.new()), 3, "normal", random_start)
	return sim

## Is `y` over the map's own design points (the player point, spawns or bot spots)?
func _on_a_map_point(map: Dictionary, x: float, z: float) -> bool:
	for p: Array in MatchSim.start_points(map):
		if absf(float(p[0]) - x) < 0.001 and absf(float(p[1]) - z) < 0.001: return true
	return false

## An independent safety check: not inside a solid, standing on a floor, and a 2 m ring out has floor under it too.
func _safe(solids: Array, x: float, z: float, y: float, ring_out_y: float) -> bool:
	var floor_y := -INF
	for b: Dictionary in solids:
		var inside := x > float(b["minX"]) + 0.01 and x < float(b["maxX"]) - 0.01 and z > float(b["minZ"]) + 0.01 \
			and z < float(b["maxZ"]) - 0.01 and float(b["bottom"]) + 0.01 < y and y < float(b["top"]) - 0.01
		if inside: return false
		if x >= float(b["minX"]) and x <= float(b["maxX"]) and z >= float(b["minZ"]) and z <= float(b["maxZ"]) \
				and float(b["top"]) <= y + 0.5 and float(b["top"]) > ring_out_y: floor_y = maxf(floor_y, float(b["top"]))
	if floor_y == -INF or absf(y - floor_y) > 0.5: return false
	for i in 24:
		var a := float(i) * PI / 12.0
		var sx := x + cos(a) * MatchSim.START_MARGIN
		var sz := z + sin(a) * MatchSim.START_MARGIN
		var supported := false
		for b: Dictionary in solids:
			if sx >= float(b["minX"]) and sx <= float(b["maxX"]) and sz >= float(b["minZ"]) and sz <= float(b["maxZ"]) \
					and float(b["top"]) <= y + 0.5 and float(b["top"]) > ring_out_y:
				supported = true; break
		if not supported: return false
	return true

## Every arena: with random_start = true the player stands on a safe one of the map's points; the range maps keep their
## scripted spots (their dummies and racks are placed relative to it) and always have one.
func _every_map() -> void:
	var ids: Array = content.maps.keys()
	ids.sort()
	var checked := 0
	for id: String in ids:
		var map := _map(id)
		map["_id"] = id
		if id == "pillars" or id == "pillars2": map["_mode"] = "pillars"
		var is_range := PracticeRange.is_range(map)
		var sim := _sim(map, true, 11)
		var p := sim.player
		var x := p.phys.px
		var z := p.phys.pz
		var y := p.phys.py
		var ring := float(map.get("lavaY", MatchSim.RING_OUT_Y))
		if is_range:
			var pp: Array = map.get("player", [0, 0])
			check(absf(x - float(pp[0])) < 0.001 and absf(z - float(pp[1])) < 0.001, "%s: the range keeps its fixed spot" % id)
		else:
			check(_on_a_map_point(map, x, z), "%s: the player starts on one of the map's own points (%.2f, %.2f)" % [id, x, z])
			check(_safe(sim.solids, x, z, y, ring), "%s: the random start (%.2f, %.2f, %.2f) is on the floor, 2 m from the void" % [id, x, z, y])
			check(y > ring, "%s: the player is above the ring-out line (%.2f > %.2f)" % [id, y, ring])
			# facing the middle of the arena
			var want := atan2(-x, -z)
			check(absf(wrapf(p.yaw - want, -PI, PI)) < 0.01, "%s: the player faces the middle (%.3f vs %.3f)" % [id, p.yaw, want])
		checked += 1
		sim.dispose()
	check(checked == ids.size(), "every arena checked (%d)" % checked)
	print("START-SPOTS maps: %d arenas" % checked)

## The same arena over several matches: more than one spot shows up (the dedicated RNG is seeded from the real time).
func _variety() -> void:
	var map := _map("arena")
	map["_id"] = "arena"
	var seen := {}
	var wide := 0
	for i in 16:
		var sim := _sim(map, true, i + 1)
		var x := sim.player.phys.px
		var z := sim.player.phys.pz
		var key := "%.2f,%.2f" % [x, z]
		check(_on_a_map_point(map, x, z), "variety match %d: on a map point (%.1f, %.1f)" % [i, x, z])
		seen[key] = true
		wide = maxi(wide, MatchSim.start_points(map).size())
		sim.dispose()
	check(seen.size() > 1, "16 matches roll more than one starting spot (%s of %d candidates)" % [seen.keys(), wide])
	print("START-SPOTS variety: %d spots in 16 matches" % seen.size())

## random_start = false (and -1 in a test run) restores the old fixed player spot, facing forward (PI), y = 0.01.
func _fixed() -> void:
	var map := _map("arena")
	map["_id"] = "arena"
	var pp: Array = map.get("player", [0, 0])
	for flag: Variant in [false, -1]:
		var sim := _sim(map, flag, 5)
		var p := sim.player
		check(absf(p.phys.px - float(pp[0])) < 0.001 and absf(p.phys.pz - float(pp[1])) < 0.001,
			"random_start %s keeps the fixed spot (%.2f, %.2f)" % [flag, p.phys.px, p.phys.pz])
		check(absf(p.phys.py - 0.01) < 0.001, "random_start %s keeps y 0.01 (%.2f)" % [flag, p.phys.py])
		check(absf(wrapf(p.yaw - PI, -PI, PI)) < 0.01, "random_start %s keeps facing forward (%.3f)" % [flag, p.yaw])
		sim.dispose()
	# the fixed run and the random run both still place the bots (the player spot only moves the 5 m exclusion)
	for flag: Variant in [false, true]:
		var sim := _sim(map, flag, 5)
		check(sim.fighters.size() == 4 and sim.fighters[1].phys.py > -25.0, "random_start %s: the bots still spawn" % flag)
		sim.dispose()
