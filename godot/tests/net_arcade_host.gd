extends SceneTree
## Arcade co-op HOST test, headless (run by tools/test-net-host.js scenario "arcade", tests/net_arcade_peer.gd as the
## guest):  godot --headless --path godot --script res://tests/net_arcade_host.gd -- ws://127.0.0.1:PORT/ws --no-save
##
## Opens the Construction hub's "Play co-op" room directly through HostSession (opts `arcade: true`, 2 seats, 1 teammate bot,
## Construction on the generated site, normal difficulty) and starts ALONE: seat 1 is the teammate bot, then the four
## Tradies crew. A Godot guest joins mid-run and takes seat 1 (`bot_to_human`), then the host starts the fight and advances
## the run (`state = "cleared"; next_stage()`), which rebuilds the world and sends stage 2's `start` with `arc.st = 1` and
## a fresh site seed. `am` goes out at ~5 Hz + on every state change all along.
## Prints JSON lines the Node side asserts: HOSTED, START<n>, HOST_STAGE, PEER_IN, HOST_FIGHT, AM_SENT, DONE.

var session := HostSession.new()
var world: Node = null
var starts := 0
var t := 0.0
var t_total := 0.0
var fails := 0
var started := false
var began := false
var advanced := false
var stage_printed := -1
var peer_at := -1.0
var fight_at := -1.0
var stage2_seen := false
var stage2_at := -1.0
var fight2 := false
var finished := false
var peer_out := false
var peer_out_at := -1.0
var _am_script: GDScript = null

## The Arcade run, built from a runtime-loaded script: a static `ArcadeManager` reference would make this test script
## compile the DLC script at --script start-up, before the autoloads it reads exist.
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
	if args.size() < 1:
		push_error("usage: -- URL"); quit(2); return
	Engine.max_fps = 60
	process_frame.connect(_begin.bind(args), CONNECT_ONE_SHOT)

func _begin(args: PackedStringArray) -> void:
	var settings: Node = root.get_node("Settings")
	settings.set_value("class", "wobbler")
	settings.set_value("name", "GodotArcadeHost")
	session.record = true
	session.hosted.connect(func(code: String) -> void: print("HOSTED ", JSON.stringify({"code": code})))
	session.ended.connect(func(r: String) -> void: print("ENDED ", r))
	session.roster_changed.connect(_on_roster)
	session.match_started.connect(_on_start)
	session.status_changed.connect(func(s: String) -> void: print("STATUS ", s))
	var ok := session.begin_host(args[0], {"name": "Arcade co-op", "pub": false, "max": 2, "bots": 1,
		"mode": "construction", "map": "sitegen", "arcade": true, "arcade_diff": "normal", "diff": "normal",
		"dyn": "off", "hp": 200, "grav": 1.0, "kb": 1.0, "crate": "normal", "inf": false, "lim": 0},
		{"name": "GodotArcadeHost", "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "wobbler"})
	if not ok: fail("begin_host refused")

func _on_roster(r: Array) -> void:
	print("ROSTER ", JSON.stringify({"n": r.size(), "started": session.started, "arcade": session.arcade, "mode": session.mode_id}))
	if not started and not session.started:
		started = true
		print("STARTING ", JSON.stringify({"ok": session.start_match()}))

func _on_start(s: Dictionary) -> void:
	starts += 1
	var kinds: Array = []
	for x: Dictionary in s["slots"]: kinds.append(str(x.get("kind", "")))
	var a: Dictionary = s.get("arc", {}) if s.get("arc") is Dictionary else {}
	print("START%d " % starts + JSON.stringify({"n": starts, "map": s["map"], "slots": s["slots"].size(), "kinds": kinds,
		"rules": s["rules"], "arc": a}))
	t = 0.0
	if world != null: return
	world = load("res://world/world.tscn").instantiate()
	world.session = session
	world.start_msg = s
	world.arcade = _new_manager(a, true)
	world.map_id = str(s.get("map", "sitegen"))
	world.mode_id = "construction"
	root.add_child(world)

func _process(dt: float) -> bool:
	t_total += dt
	if t_total > 300.0:
		fail("timeout"); _finish(1); return false
	if world == null:
		session.poll(dt)
		return false
	var m = world.arcade
	var nm: HostMatch = world.net_match as HostMatch
	if m == null or nm == null: return false
	t += dt
	if peer_at < 0.0 and not session.conns.is_empty():
		peer_at = t
		print("PEER_IN ", JSON.stringify({"slot": 1, "seat1_kind": str(session.slots[1].get("kind", "")) if session.slots.size() > 1 else "",
			"seat1_ghost": m.seat(1) != null and m.seat(1).is_ghost, "seat1_player": m.seat(1) != null and m.seat(1).is_player,
			"seats": m.seats.size(), "state": m.state}))
	if fight2 and peer_at >= 0.0 and not peer_out and session.conns.is_empty():
		peer_out = true
		peer_out_at = t
		print("PEER_OUT ", JSON.stringify({"seat1_kind": str(session.slots[1].get("kind", "")) if session.slots.size() > 1 else "",
			"seat1_ghost": m.seat(1) != null and m.seat(1).is_ghost, "seat1_player": m.seat(1) != null and m.seat(1).is_player,
			"seat1_name": str(session.slots[1].get("name", "")) if session.slots.size() > 1 else "",
			"started": session.started, "state": m.state}))
	if peer_at >= 0.0 and not began and t - peer_at > 0.5 and m.stage == 0 and m.state == "intro":
		began = true
		fight_at = t
		m.begin_fight()
		print("HOST_FIGHT ", JSON.stringify({"st": m.stage, "state": m.state, "lives": m.lives}))
	if int(m.stage) != stage_printed:
		stage_printed = int(m.stage)
		print("HOST_STAGE ", JSON.stringify({"st": m.stage, "map": world.map_id, "seed": SiteMap.current_seed,
			"count": m.count(), "seats": m.seats.size(), "enemies": m.enemies.size(),
			"boss": m.boss.net_slot if m.boss != null else -1, "state": m.state, "slots": session.slots.size(),
			"seat1_ghost": m.seat(1) != null and m.seat(1).is_ghost,
			"arc_seed": int((world.start_msg.get("arc", {}) as Dictionary).get("seed", -1))}))
	if began and not advanced and m.stage == 0 and t - fight_at > 1.2:
		advanced = true
		m.state = "cleared"
		m.next_stage()
		print("ADVANCING ", JSON.stringify({"from": 0, "state": "cleared"}))
	if advanced and m.stage == 1 and not stage2_seen:
		stage2_seen = true
		stage2_at = t
	if stage2_seen and not fight2 and m.state == "intro" and t - stage2_at > 0.6:
		fight2 = true
		m.begin_fight()
		print("HOST_FIGHT ", JSON.stringify({"st": m.stage, "state": m.state, "lives": m.lives}))
	if peer_out and t - peer_out_at > 0.6 and not finished:
		finished = true
		var n := 0
		for x: Variant in session.sent:
			if x is Dictionary and x.get("t") == "am": n += 1
		print("AM_SENT ", JSON.stringify({"n": n, "guarded": session.guarded, "relayed": session.relayed, "started": session.started}))
		_finish(0)
	return false

func _finish(code: int) -> void:
	print("DONE ", JSON.stringify({"fails": fails, "starts": starts}))
	session.leave("test done")
	if world != null: world.free(); world = null
	quit(1 if fails > 0 or code != 0 else 0)
