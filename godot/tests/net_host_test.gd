extends SceneTree
## Cross-play HOST test, headless (run by tools/test-net-host.js with the real server, a web-protocol guest in Node and
## a second Godot process as a guest, tests/net_host_peer.gd):
##   godot --headless --path godot --script res://tests/net_host_test.gd -- ws://127.0.0.1:PORT/ws --no-save
## Hosts a private room (4 seats, 1 bot, K.O. limit 1) as a Bruiser named GodotHost, starts when two guests are in,
## plays in the real World scene (HostSession + HostMatch), walks for 2 s, lands a scripted hit on slot 1 at 3 s,
## votes rematch when the match is over, and after the rematch waits for the guests to leave.
## Prints: HOSTED, ROSTER, START, GHOST <slot> x y z hp, BOT <slot> x z hp, HP, HIT1, MATCH_OVER, SLOTS, DONE.

var session := HostSession.new()
var world: Node = null
var t := 0.0
var t_total := 0.0
var print_t := 0.0
var starts := 0
var hit1 := false
var over_seen := false
var after_start2 := -1.0
var fails := 0
var last_hp := -1.0
var done := false
var emoted := false

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
	settings.set_value("class", "bruiser")
	settings.set_value("name", "GodotHost")
	session.record = true
	session.hosted.connect(func(code: String) -> void: print("HOSTED code=%s" % code))
	session.ended.connect(func(r: String) -> void: print("ENDED ", r))
	session.roster_changed.connect(_on_roster)
	session.match_started.connect(_on_start)
	session.votes_changed.connect(func(l: Array, n: int) -> void: print("VOTES %d/%d" % [l.size(), n]))
	session.status_changed.connect(func(s: String) -> void: print("STATUS ", s))
	# Team Deathmatch is app-only: with the web guest in the room the match plays Classic (rules.mode, no gmode)
	session.begin_host(args[0], {"name": "Godot room", "pub": false, "max": 4, "bots": 1, "lim": 1, "mode": "tdm", "map": "arena", "dyn": "off",
		"hp": 150, "grav": 1.5, "kb": 0.5, "crate": "fast", "inf": true},
		{"name": "GodotHost", "skin": "none", "hat": "crown", "color": 0x39b5a8, "cls": "bruiser"})

func _on_roster(r: Array) -> void:
	var names: Array = []
	for e: Dictionary in r: names.append("%d:%s:%s" % [e["id"], e["name"], e["cls"]])
	print("ROSTER n=%d %s started=%s match=%s" % [r.size(), " ".join(names), session.started, session.host_match() != null])
	if r.size() == 3 and not session.started and starts == 0:
		print("STARTING ok=%s" % session.start_match())
	if done and r.size() <= 1:
		_finish.call_deferred()

func _on_start(s: Dictionary) -> void:
	starts += 1
	if starts == 1:
		world = load("res://world/world.tscn").instantiate()
		world.session = session
		world.start_msg = s
		root.add_child(world)
	else:
		after_start2 = 0.0
		t = 0.0

func _finish() -> void:
	if world == null: return
	var nm: NetMatch = world.net_match
	print("SENT %s" % [nm.sent_counts if nm else {}])
	print("RECV %s" % [nm.recv_counts if nm else {}])
	print("GUARDED %d RELAYED %d" % [session.guarded, session.relayed])
	print("DONE fails=%d" % fails)
	world.free()
	world = null
	session.leave("test done")
	quit(1 if fails > 0 else 0)

func _process(dt: float) -> bool:
	t_total += dt
	if t_total > 90.0:
		fail("timeout"); quit(1); return false
	if world == null:
		session.poll(dt)
		return false
	var nm: HostMatch = world.net_match as HostMatch
	if nm == null: return false
	t += dt
	if after_start2 >= 0.0:
		after_start2 += dt
		if not done:
			done = true
			var kinds: Array = []
			for x: Dictionary in nm.slots: kinds.append(x["kind"])
			print("START n=%d slots=%s" % [starts, ",".join(kinds)])
		if after_start2 > 25.0: _finish(); return false
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	st.set_move("script", Vector2(0, 1) if t > 0.5 and t < 2.5 else Vector2.ZERO)
	if p.hp != last_hp:
		last_hp = p.hp
		print("HP %.1f" % p.hp)
	print_t -= dt
	if print_t <= 0.0:
		print_t = 0.1
		for s: int in nm.ghosts:
			var g: FighterState = nm.ghosts[s]
			if not g.left: print("GHOST %d %.3f %.3f %.3f %d %s" % [s, g.phys.px, g.phys.py, g.phys.pz, int(g.hp), g.name])
		for s: int in nm.ai:
			var b: FighterState = nm.ai[s]
			print("BOT %d %.3f %.3f %d %s dead=%s" % [s, b.phys.px, b.phys.pz, int(b.hp), b.name, b.dead])
		var kinds: Array = []
		for x: Dictionary in nm.slots: kinds.append(x["kind"])
		print("SLOTS %s" % ",".join(kinds))
	if starts == 1 and t > 3.0 and not hit1:
		hit1 = true
		var g1: FighterState = nm.ghosts.get(1)
		if g1 == null: fail("no ghost for slot 1")
		else:
			p.invuln = 0.0
			var r := sim.combat.hit(g1, 30.0, 0.0, 0.2, 1.0, 5.0, false, p)
			print("HIT1 applied=%s" % r.get("applied"))
	if starts == 1 and t > 3.5 and not emoted:
		emoted = true
		nm.send_emote("clap")
		print("EMOTE_SENT")
	if starts == 1 and nm.over and not over_seen:
		over_seen = true
		print("MATCH_OVER w=%d" % nm.winner)
		session.vote_rematch()
	return false
