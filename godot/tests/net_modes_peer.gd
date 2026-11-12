extends SceneTree
## The Godot guest of the online modes / host migration test (tools/test-net-host.js, tests/net_modes_host.gd):
##   godot --headless --path godot --script res://tests/net_modes_peer.gd -- ws://127.0.0.1:PORT/ws ROOM modes|migrate N --no-save
## modes: joins as a Scamp named GodotPeer, prints how it plays every `start` (MODE: the mode it runs, sides, gravity,
##   max health, remote flag), the host's `gm` Chaos events (GM) and that its Chaos event ran (CHAOS_ON), votes rematch
##   after each match and leaves after N matches.
## migrate: when the host leaves, the relay promotes it: it becomes the host (PROMOTED), carries the match on
##   (RESUMED: seats, K.O.s, bot names) and leaves once the web guest has gone. Prints ME x y z all along.

var session: GuestSession = GuestSession.new()
var world: Node = null
var scen := "modes"
var need := 8
var starts := 0
var ends := 0
var t := 0.0
var t_total := 0.0
var print_t := 0.0
var mode_printed := false
var chaos_printed := false
var end_seen := false
var quit_t := -1.0
var resumed := false
var fails := 0

func fail(what: String) -> void:
	fails += 1
	print("FAIL ", what)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- URL ROOMCODE [modes|migrate] [N]"); quit(2); return
	Engine.max_fps = 60
	process_frame.connect(_begin.bind(args), CONNECT_ONE_SHOT)

func _begin(args: PackedStringArray) -> void:
	scen = args[2] if args.size() > 2 and not args[2].begins_with("--") else "modes"
	need = int(args[3]) if args.size() > 3 and args[3].is_valid_int() else 8
	var settings: Node = root.get_node("Settings")
	settings.set_value("class", "kid")
	settings.set_value("name", "GodotPeer")
	_bind(session)
	session.welcomed.connect(func(slot: int, room: String) -> void: print("WELCOMED slot=%d room=%s gdhost=%s" % [slot, room, session.host_gd]))
	session.begin(args[0], args[1], {"name": "GodotPeer", "skin": "none", "hat": "cone", "color": 0x39b5a8, "cls": "kid"})

func _bind(s: GuestSession) -> void:
	s.ended.connect(func(r: String) -> void: print("ENDED ", r))
	s.match_started.connect(_on_start)
	s.match_message.connect(_on_msg)
	s.promoted.connect(_on_promoted)
	s.status_changed.connect(func(x: String) -> void: print("STATUS ", x))

func _on_promoted(hs: GuestSession) -> void:
	print("PROMOTED resuming=%s" % (hs as HostSession).resuming())
	session = hs
	_bind(hs)
	(hs as HostSession).roster_changed.connect(func(r: Array) -> void: print("ROSTER n=%d" % r.size()))

func _on_msg(m: Dictionary) -> void:
	if m.get("t") == "gm" and m.get("k") != "st": print("GM %s %s g=%s" % [m.get("k"), m.get("id"), m.get("g", "-")])
	if m.get("t") == "emote": print("EMOTE %d %s" % [int(m.get("id", -1)), m.get("e")])

func _on_start(s: Dictionary) -> void:
	starts += 1
	var kinds: Array = []
	for x: Dictionary in s["slots"]: kinds.append(x["kind"])
	print("START n=%d map=%s kinds=%s rules=%s rs=%s" % [starts, s["map"], ",".join(kinds), JSON.stringify(s["rules"]), s.get("rs") is Array])
	t = 0.0; mode_printed = false; chaos_printed = false; end_seen = false
	if world == null:
		world = load("res://world/world.tscn").instantiate()
		world.session = session
		world.start_msg = s
		root.add_child(world)

func _process(dt: float) -> bool:
	t_total += dt
	if t_total > 300.0:
		fail("timeout"); quit(1); return false
	if quit_t >= 0.0:
		quit_t -= dt
		if quit_t < 0.0: _done()
		return false
	if world == null:
		session.poll(dt)
		return false
	var nm: NetMatch = world.net_match
	if nm == null: return false
	t += dt
	var sim: MatchSim = world.sim
	var p := sim.player
	var c := sim.combat
	if not mode_printed and t > 0.3:
		mode_printed = true
		print("MODE n=%d mode=%s gmode=%s teams=%d team=%d grav=%.2f maxhp=%.0f remote=%s limit=%d host=%s pos=%.2f,%.2f" % [starts, c.mode_id, nm.gmode,
			c.teams, p.team, p.phys.grav_scale, c.max_hp(p), c.rules.remote, c.rules.limit, nm is HostMatch, p.phys.px, p.phys.pz])
	var ch := c.rules.chaos
	if not ch.is_empty() and (float(ch.get("left", 0.0)) > 0.0 or str(ch.get("last", "")) != "") and not chaos_printed:
		chaos_printed = true                  # running now, or already over (crate rain lasts no time)
		print("CHAOS_ON id=%s last=%s left=%.1f grav=%.2f kb=%.2f" % [ch["id"], ch["last"], ch["left"], p.phys.grav_scale, c.kb_setting])
	print_t -= dt
	if print_t <= 0.0:
		print_t = 0.2
		print("ME %.3f %.3f %.3f %.0f" % [p.phys.px, p.phys.py, p.phys.pz, p.hp])
	if scen == "migrate":
		var st: InputState = world.input.state                # walk off the spawn first, so carrying on is visible
		st.set_move("script", Vector2(1, 0) if starts == 1 and t > 0.5 and t < 1.6 else Vector2.ZERO)
		if nm is HostMatch and not resumed and t > 0.5:
			resumed = true
			var hm := nm as HostMatch
			var parts: Array = []
			for k in hm.slots.size():
				var f := hm.slot_fighter(k)
				parts.append("%s:%s:ko%d" % [hm.slots[k]["kind"], hm.slots[k]["name"], f.ko if f else -1])
			print("RESUMED %s dyn=%.2f kind=%s" % [" ".join(parts), sim.dyn_clock(), sim.dyn.kind])
		if resumed and t > 3.0 and session.roster.size() <= 1: _done()
		return false
	if nm.over and not end_seen:
		end_seen = true
		ends += 1
		print("MATCH_END n=%d w=%d mode=%s" % [ends, nm.winner, c.mode_id])
		if ends >= need: quit_t = 1.5
		else: session.vote_rematch()
	return false

func _done() -> void:
	print("DONE fails=%d" % fails)
	if world != null: world.free(); world = null
	session.leave("test done")
	quit(1 if fails > 0 else 0)
