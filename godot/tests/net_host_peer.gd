extends SceneTree
## The Godot guest of the host test (tools/test-net-host.js): joins the Godot host's room as a Scamp named GodotPeer,
## walks for 2 s, hits the host's own fighter (slot 0) at 4.5 s, votes rematch when the host's `pend` ends the match,
## and after the rematch waits until the web guest's seat turned back into a bot, then leaves.
##   godot --headless --path godot --script res://tests/net_host_peer.gd -- ws://127.0.0.1:PORT/ws ROOM --no-save
## Prints: WELCOMED, START, GHOST <slot> x y z hp, ME x y z hp, HIT0, MATCH_END, START2, SLOT1, DONE.

var session := GuestSession.new()
var world: Node = null
var t := 0.0
var t_total := 0.0
var print_t := 0.0
var starts := 0
var hit0 := false
var end_seen := false
var t2 := -1.0
var fails := 0

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
	settings.set_value("name", "GodotPeer")
	session.welcomed.connect(func(slot: int, room: String) -> void: print("WELCOMED slot=%d room=%s" % [slot, room]))
	session.ended.connect(func(r: String) -> void: print("ENDED ", r))
	session.match_started.connect(_on_start)
	session.match_message.connect(func(m: Dictionary) -> void:
		if m.get("t") == "slot": print("SLOTMSG %s" % JSON.stringify(m))
		if m.get("t") == "emote": print("EMOTE %d %s" % [int(m.get("id", -1)), m.get("e")]))
	session.begin(args[0], args[1], {"name": "GodotPeer", "skin": "none", "hat": "cone", "color": 0x39b5a8, "cls": "kid"})

func _on_start(s: Dictionary) -> void:
	starts += 1
	var kinds: Array = []
	var names: Array = []
	for x: Dictionary in s["slots"]:
		kinds.append(x["kind"]); names.append(x["name"])
	print("START n=%d map=%s slots=%d my_slot=%d kinds=%s names=%s mode=%s" % [starts, s["map"], s["slots"].size(), session.slot, ",".join(kinds), "|".join(names), s["rules"].get("mode")])
	if starts == 1:
		world = load("res://world/world.tscn").instantiate()
		world.session = session
		world.start_msg = s
		root.add_child(world)
	else:
		t2 = 0.0

func _process(dt: float) -> bool:
	t_total += dt
	if t_total > 90.0:
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
	st.set_move("script", Vector2(0, 1) if starts == 1 and t > 0.5 and t < 2.5 else Vector2.ZERO)
	print_t -= dt
	if print_t <= 0.0:
		print_t = 0.1
		for s: int in nm.ghosts:
			var g: FighterState = nm.ghosts[s]
			if not g.left: print("GHOST %d %.3f %.3f %.3f %d %s" % [s, g.phys.px, g.phys.py, g.phys.pz, int(g.hp), g.name])
		print("ME %.3f %.3f %.3f %.1f" % [p.phys.px, p.phys.py, p.phys.pz, p.hp])
	if starts == 1 and t > 4.5 and not hit0:
		hit0 = true
		var h: FighterState = nm.ghosts.get(0)
		if h == null: fail("no ghost for the host (slot 0)")
		else:
			var r := sim.combat.hit(h, 12.0, 0.0, 0.0, 1.0, 3.0, false, p)
			print("HIT0 applied=%s" % r.get("applied"))
	if nm.over and not end_seen:
		end_seen = true
		print("MATCH_END w=%d" % nm.winner)
		session.vote_rematch()
	if t2 >= 0.0:
		t2 += dt
		if starts >= 2 and t2 < 0.05: print("START2")
		var s1: Dictionary = nm.slots[1] if nm.slots.size() > 1 else {}
		if str(s1.get("kind", "")) == "bot" or t2 > 15.0:
			print("SLOT1 t2=%.2f" % t2)
			print("SLOT1 kind=%s name=%s" % [s1.get("kind", "?"), s1.get("name", "?")])
			print("SENT %s" % [nm.sent_counts])
			print("RECV %s" % [nm.recv_counts])
			print("DONE fails=%d" % fails)
			world.free()
			world = null
			session.leave("test done")
			quit(1 if fails > 0 else 0)
	return false
