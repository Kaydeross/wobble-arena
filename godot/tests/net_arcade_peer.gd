extends SceneTree
## Arcade co-op GODOT GUEST test, headless (run by tools/test-net-host.js scenario "arcade", tests/net_arcade_host.gd
## hosting):  godot --headless --path godot --script res://tests/net_arcade_peer.gd -- ws://127.0.0.1:PORT/ws ROOM --no-save
##
## Joins a RUNNING Arcade co-op room and takes seat 1 (`welcome`, then the host's mid-match `start` with `arc`). Rebuilds
## every stage from `start.arc`: the same generated site seed, the seat/crew ghosts from the slot table (the boss included
## on stage 2), and the host's `am` display state. Leaves once stage 2's fight is running so the host can finish.
## Prints JSON lines the Node side asserts: JOINED, START<n>, PEER_STAGE, AM, DONE.

var session := GuestSession.new()
var world: Node = null
var starts := 0
var t := 0.0
var t_total := 0.0
var fails := 0
var printed_stage := -1
var last_am := ""
var am_n := 0
var am_fight := false
var stage2 := false
var stage2_at := -1.0
var quit_t := -1.0
var done := false
var _am_script: GDScript = null

## The guest-side run, built from a runtime-loaded script (no static DLC dependency at --script start-up; see the host test).
func _new_manager(a: Dictionary, is_host: bool) -> RefCounted:
	if _am_script == null: _am_script = load("res://dlc/construction/arcade_manager.gd") as GDScript
	var m: RefCounted = _am_script.new()
	m.call("init_online", a, is_host)
	return m

func fail(what: String) -> void:
	fails += 1
	print("FAIL ", what)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- URL ROOMCODE"); quit(2); return
	Engine.max_fps = 60
	process_frame.connect(_begin.bind(args), CONNECT_ONE_SHOT)

func _begin(args: PackedStringArray) -> void:
	var settings: Node = root.get_node("Settings")
	settings.set_value("class", "kid")
	settings.set_value("name", "GodotArcadePeer")
	session.welcomed.connect(func(slot: int, room: String) -> void: print("JOINED ", JSON.stringify({"slot": slot, "room": room, "gdhost": session.host_gd})))
	session.ended.connect(func(r: String) -> void: print("ENDED ", r))
	session.match_started.connect(_on_start)
	session.status_changed.connect(func(s: String) -> void: print("STATUS ", s))
	session.begin(args[0], args[1], {"name": "GodotArcadePeer", "skin": "none", "hat": "cone", "color": 0x39b5a8, "cls": "kid"})

func _on_start(s: Dictionary) -> void:
	starts += 1
	var kinds: Array = []
	for x: Dictionary in s["slots"]: kinds.append(str(x.get("kind", "")))
	var a: Dictionary = s.get("arc", {}) if s.get("arc") is Dictionary else {}
	print("START%d " % starts + JSON.stringify({"n": starts, "map": s["map"], "slots": s["slots"].size(), "kinds": kinds,
		"rules": s["rules"], "arc": a}))
	t = 0.0
	printed_stage = -1
	if world != null: return
	world = load("res://world/world.tscn").instantiate()
	world.session = session
	world.start_msg = s
	world.arcade = _new_manager(a, false)
	world.map_id = str(s.get("map", "sitegen"))
	world.mode_id = "construction"
	root.add_child(world)

func _process(dt: float) -> bool:
	t_total += dt
	if t_total > 300.0:
		fail("timeout"); _done(); return false
	if quit_t >= 0.0:
		quit_t -= dt
		if quit_t < 0.0: _done()
		return false
	if world == null:
		session.poll(dt)
		return false
	var m = world.arcade
	var nm: NetMatch = world.net_match
	if m == null or nm == null: return false
	t += dt
	if int(m.stage) != printed_stage and t > 0.35 and not m.seats.is_empty():
		printed_stage = int(m.stage)
		var a: Dictionary = world.start_msg.get("arc", {}) if world.start_msg.get("arc") is Dictionary else {}
		var crew: Array = a.get("crew", [])
		var crew_ghosts := 0
		for slot: Variant in crew:
			var f: FighterState = nm.slot_fighter(int(slot))
			if f != null and f.is_ghost: crew_ghosts += 1
		var boss := int(a.get("boss", -1))
		var bf: FighterState = nm.slot_fighter(boss) if boss >= 0 else null
		var hf: FighterState = nm.slot_fighter(0)
		print("PEER_STAGE ", JSON.stringify({"n": starts, "st": m.stage, "count": m.count(), "map": world.map_id,
			"seed": SiteMap.current_seed, "my_slot": nm.my_slot, "arc_st": int(a.get("st", -1)), "arc_seed": int(a.get("seed", -1)),
			"seat_count": m.seats.size(), "seat0_is_me": m.seats.size() > 0 and m.seats[0] == nm.sim.player,
			"host_ghost": hf != null and hf.is_ghost, "crew_ghosts": crew_ghosts, "crew_n": crew.size(),
			"boss": boss, "boss_ghost": bf != null and bf.is_ghost, "state": m.state, "lives": m.lives}))
	if not m.am.is_empty() and str(m.am) != last_am:
		last_am = str(m.am)
		am_n += 1
		print("AM ", JSON.stringify({"n": am_n, "st": int(m.am.get("st", -1)), "lv": int(m.am.get("lv", -1)),
			"s": str(m.am.get("s", "")), "dn": m.am.get("dn", []), "hf": float(m.am.get("hf", 0.0)),
			"sh": float(m.am.get("sh", 0.0)), "state": m.state}))
		if str(m.am.get("s", "")) == "fight": am_fight = true
	if starts >= 2 and int(m.stage) == 1 and am_fight and not stage2:
		stage2 = true
		stage2_at = t
	if stage2 and t - stage2_at > 1.5: quit_t = 0.2
	return false

func _done() -> void:
	if done: return
	done = true
	print("DONE ", JSON.stringify({"fails": fails, "starts": starts, "am": am_n, "stage": printed_stage}))
	session.leave("test done")
	if world != null: world.free(); world = null
	quit(1 if fails > 0 else 0)
