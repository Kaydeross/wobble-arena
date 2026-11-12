extends SceneTree
## Cross-play host test, headless (run by tools/test-net-host.js, which joins as a Node guest):
##   godot --headless --path godot --script res://tests/net_host_test.gd -- ws://127.0.0.1:PORT/ws [--no-save]
## Creates a private room, welcomes the guest, starts Classic on arena, walks, applies a guest `h` on the host
## player, ends the match (`pend`), then leaves. Prints: HOSTED, ROSTER, START, HOST_POS, HIT_RECV, MATCH_END, DONE.

var session := HostSession.new()
var world: Node = null
var t := 0.0
var t_total := 0.0
var print_t := 0.0
var started := false
var ended_match := false
var fails := 0

func fail(what: String) -> void:
	fails += 1
	print("FAIL ", what)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- URL"); quit(2); return
	Engine.max_fps = 60
	process_frame.connect(_begin.bind(args), CONNECT_ONE_SHOT)

func _begin(args: PackedStringArray) -> void:
	var settings: Node = root.get_node("Settings")
	settings.set_value("class", "bruiser")
	settings.set_value("name", "GodotHost")
	session.record = true
	session.welcomed.connect(func(_slot: int, _room: String) -> void: print("HOSTED code=%s" % session.room_code))
	session.ended.connect(func(r: String) -> void: print("ENDED ", r))
	session.roster_changed.connect(func(r: Array) -> void:
		print("ROSTER n=%d" % r.size())
		if r.size() >= 2 and not started and session.phase == HostSession.Phase.LOBBY:
			started = true
			session.start_match())
	session.match_started.connect(_on_start)
	session.match_message.connect(func(m: Dictionary) -> void:
		if m.get("t") == "h": print("HIT_RECV ", m))
	session.begin(args[0], {"name": "GodotHost", "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "bruiser"}, "", {
		"pub": false, "room_name": "GodotHost room", "max": 4, "bots": true, "map": "arena", "mode": "classic", "hp": 200.0,
	})

func _on_start(s: Dictionary) -> void:
	if world != null: return
	print("START map=%s slots=%d" % [s["map"], s["slots"].size()])
	world = load("res://world/world.tscn").instantiate()
	world.session = session
	world.start_msg = s
	root.add_child(world)

func _process(dt: float) -> bool:
	t_total += dt
	if t_total > 40.0:
		fail("timeout"); quit(1); return false
	if world == null:
		session.poll(dt)
		return false
	var nm: NetMatch = world.net_match
	if nm == null: return false
	t += dt
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	st.set_move("script", Vector2(0, 1) if t > 0.5 and t < 2.5 else Vector2.ZERO)
	print_t -= dt
	if print_t <= 0.0:
		print_t = 0.2
		print("HOST_POS %.3f %.3f %.3f %.1f" % [p.phys.px, p.phys.py, p.phys.pz, p.hp])
		for s: int in nm.ai:
			var b: FighterState = nm.ai[s]
			print("BOT %d %.3f %.3f %.1f" % [s, b.phys.px, b.phys.pz, b.hp])
	if t > 6.0 and not ended_match and not nm.over:
		ended_match = true
		sim.combat.rules.end_match(p)
	if nm.over and t > 6.5:
		print("MATCH_END w=%d" % nm.winner)
		var sent_s := 0
		var sent_pend := false
		for m: Dictionary in session.sent:
			if m.get("t") == "S": sent_s += 1
			if m.get("t") == "pend": sent_pend = true
		print("SENT S=%d pend=%s" % [sent_s, sent_pend])
		print("DONE code=%s hp=%.1f host=%s" % [session.room_code, p.hp, nm.is_host])
		session.leave("test done")
		quit(0 if fails == 0 else 1)
		return true
	return false
