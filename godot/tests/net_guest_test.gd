extends SceneTree
## Cross-play guest test, headless (run by tools/test-net-guest.js, which hosts the room with a Node bot):
##   godot --headless --path godot --script res://tests/net_guest_test.gd -- ws://127.0.0.1:PORT/ws ROOM --no-save
## Joins as a Scamp ("kid") named GodotGuest, plays the match the host starts in the real World scene (GuestSession +
## NetMatch), walks for 2 s, lands a scripted hit on the host's bot (slot 2) at 4 s, injects forged host-only
## messages on a non-host path at 5 s, votes rematch when the host ends the match, then leaves.
## Prints lines the runner checks: WELCOMED, START, GHOST <slot> x y z, ME x y z hp, HIT_SENT, FORGED, MATCH_END, SENT, DONE.

var session := GuestSession.new()
var world: Node = null
var t := 0.0                     ## seconds since start
var t_total := 0.0
var print_t := 0.0
var hit_sent := false
var forged := false
var forge_checked := false
var forge_d0 := 0
var forge_map := ""
var forge_sim: MatchSim = null
var end_t := -1.0
var fails := 0
var last_hp := -1.0

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
	var settings: Node = root.get_node("Settings")     # the world reads the class/name from Settings
	settings.set_value("class", "kid")
	settings.set_value("name", "GodotGuest")
	session.record = true
	session.welcomed.connect(func(slot: int, room: String) -> void: print("WELCOMED slot=%d room=%s" % [slot, room]))
	session.ended.connect(func(r: String) -> void: print("ENDED ", r))
	session.match_started.connect(_on_start)
	session.begin(args[0], args[1], {"name": "GodotGuest", "skin": "none", "hat": "cone", "color": 0x39b5a8, "cls": "kid"})

func _on_start(s: Dictionary) -> void:
	if world != null: return
	print("START map=%s slots=%d my_slot=%d" % [s["map"], s["slots"].size(), session.slot])
	world = load("res://world/world.tscn").instantiate()
	world.session = session
	world.start_msg = s
	root.add_child(world)

func _process(dt: float) -> bool:
	t_total += dt
	if t_total > 50.0:
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
	if p.hp != last_hp:
		last_hp = p.hp
		print("HP %.1f" % p.hp)
	print_t -= dt
	if print_t <= 0.0:
		print_t = 0.1
		for s: int in nm.ghosts:
			var g: FighterState = nm.ghosts[s]
			if not g.left: print("GHOST %d %.3f %.3f %.3f %d %s" % [s, g.phys.px, g.phys.py, g.phys.pz, int(g.hp), g.name])
		print("ME %.3f %.3f %.3f %.1f" % [p.phys.px, p.phys.py, p.phys.pz, p.hp])
	if t > 4.0 and not hit_sent:
		hit_sent = true
		var bot: FighterState = nm.ghosts.get(2)
		if bot == null: fail("no ghost for the host's bot (slot 2)")
		else:
			var r := sim.combat.hit(bot, 12.0, 0.0, 0.0, 1.0, 3.0, false, p)
			print("HIT_SENT applied=%s" % r.get("applied"))
	if t > 5.0 and not forged:
		forged = true
		forge_d0 = session.dropped
		forge_map = world.map_id
		forge_sim = world.sim
		# messages that did not come from the host (the server only adds `from` on the way TO a host)
		session.net._handle(JSON.stringify({"op": "msg", "from": 3, "m": {"t": "pend", "w": 3}}))
		session.net._handle(JSON.stringify({"op": "msg", "from": 3, "m": {"t": "start", "map": "park", "slots": [{"kind": "human"}, {"kind": "human"}], "rules": {}}}))
	if forged and not forge_checked and t > 5.3:
		forge_checked = true
		var ok: bool = session.dropped == forge_d0 + 2 and not nm.over and world.map_id == forge_map and world.sim == forge_sim
		print("FORGED ignored=%s dropped=%d" % [ok, session.dropped - forge_d0])
		if not ok: fail("forged pend/start were not ignored")
		forge_sim = null
	if nm.over and end_t < 0.0:
		end_t = t
		print("MATCH_END w=%d results=%s" % [nm.winner, world.get("_results") != null])
		session.vote_rematch()
	if end_t >= 0.0 and t - end_t > 0.6:
		print("SENT %s" % [nm.sent_counts])
		print("RECV %s" % [nm.recv_counts])
		print("DONE fails=%d" % fails)
		world.free()                   # (its session signals go with it, so leaving does not open the title scene)
		world = null
		session.leave("test done")
		quit(1 if fails > 0 else 0)
	return false
