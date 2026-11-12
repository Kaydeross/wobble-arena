extends SceneTree
## Online modes / host migration HOST test, headless (run by tools/test-net-host.js with the real server, a guest in
## Node and a second Godot process, tests/net_modes_peer.gd):
##   godot --headless --path godot --script res://tests/net_modes_host.gd -- ws://127.0.0.1:PORT/ws modes|migrate --no-save
## modes: hosts a private room (4 seats, 1 bot, K.O. limit 3) whose guests are all Godot clients (`gd`), plays every
##   app-only mode of MODES in turn (set_rules between matches, rematch votes), forces the first Chaos event early,
##   prints MATCH_OVER per mode and ALL_MODES at the end, then waits for the guests to leave.
## migrate: hosts a Classic room on a Wobble floor; once the web guest (slot 2) has a K.O. it leaves the room (the
##   relay then promotes the Godot guest, which carries the match on). Prints ME / LEAVING.

const MODES := [["tdm", "arena"], ["deathmatch", "arena"], ["sudden", "arena"], ["chaos", "arenaxl"], ["pillars", "pillars"],
	["explosive", "arena"], ["lowg", "craterdome"], ["gungame", "arena"]]

var session := HostSession.new()
var world: Node = null
var scen := "modes"
var mi := 0
var starts := 0
var t := 0.0
var t_total := 0.0
var print_t := 0.0
var over_seen := false
var chaos_forced := false
var done := false
var fails := 0

func fail(what: String) -> void:
	fails += 1
	print("FAIL ", what)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("usage: -- URL [modes|migrate]"); quit(2); return
	Engine.max_fps = 60
	process_frame.connect(_begin.bind(args), CONNECT_ONE_SHOT)

func _begin(args: PackedStringArray) -> void:
	scen = args[1] if args.size() > 1 and not args[1].begins_with("--") else "modes"
	var settings: Node = root.get_node("Settings")
	settings.set_value("class", "wobbler")
	settings.set_value("name", "GodotHost")
	session.hosted.connect(func(code: String) -> void: print("HOSTED code=%s" % code))
	session.ended.connect(func(r: String) -> void: print("ENDED ", r))
	session.status_changed.connect(func(s: String) -> void: print("STATUS ", s))
	session.roster_changed.connect(_on_roster)
	session.match_started.connect(_on_start)
	var opts := {"name": "Godot modes", "pub": false, "max": 4, "bots": 1, "lim": 3, "mode": MODES[0][0], "map": MODES[0][1], "dyn": "off",
		"hp": 150, "kb": 1.5, "crate": "fast"}
	if scen == "migrate":
		opts = {"name": "Godot migrate", "pub": false, "max": 4, "bots": 1, "lim": 0, "mode": "classic", "map": "arena", "dyn": "wobble"}
	session.begin_host(args[0], opts, {"name": "GodotHost", "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "wobbler"})

func _on_roster(r: Array) -> void:
	var names: Array = []
	for e: Dictionary in r: names.append("%d:%s:%s" % [e["id"], e["name"], "gd" if e.has("gd") else "web"])
	print("ROSTER n=%d %s mode=%s started=%s" % [r.size(), " ".join(names), session.mode_id, session.started])
	if r.size() == 3 and not session.started and starts == 0:
		print("STARTING ok=%s" % session.start_match())
	if done and r.size() <= 1:
		_finish.call_deferred()

func _on_start(s: Dictionary) -> void:
	starts += 1
	print("START n=%d map=%s limit=%d rules=%s" % [starts, s["map"], s["limit"], JSON.stringify(s["rules"])])
	t = 0.0; over_seen = false; chaos_forced = false
	if world == null:
		world = load("res://world/world.tscn").instantiate()
		world.session = session
		world.start_msg = s
		root.add_child(world)

func _finish() -> void:
	if world == null: return
	print("GUARDED %d RELAYED %d" % [session.guarded, session.relayed])
	print("DONE fails=%d" % fails)
	world.free()
	world = null
	session.leave("test done")
	quit(1 if fails > 0 else 0)

func _process(dt: float) -> bool:
	t_total += dt
	if t_total > 300.0:
		fail("timeout"); quit(1); return false
	if world == null:
		session.poll(dt)
		return false
	var nm: HostMatch = world.net_match as HostMatch
	if nm == null: return false
	t += dt
	var sim: MatchSim = world.sim
	var r := sim.combat.rules
	if scen == "migrate":
		print_t -= dt
		if print_t <= 0.0:
			print_t = 0.2
			print("ME %.3f %.3f %.3f" % [sim.player.phys.px, sim.player.phys.py, sim.player.phys.pz])
		var g2: FighterState = nm.ghosts.get(2)
		if (t > 3.0 and g2 != null and g2.ko >= 1) or t > 20.0:
			print("LEAVING t=%.1f ko2=%d dyn=%.2f" % [t, g2.ko if g2 else -1, sim.dyn_clock()])
			world.free(); world = null
			session.leave("test done")
			quit(0)
		return false
	if session.mode_id == "chaos" and t > 0.3 and not chaos_forced and not r.chaos.is_empty():
		chaos_forced = true
		r.chaos["next"] = 0.0                 # the first event now (its warning, then the event)
	if nm.over and not over_seen:
		over_seen = true
		var w := nm.slot_fighter(nm.winner)
		var kos: Array = []
		for k in nm.slots.size():
			var f := nm.slot_fighter(k)
			kos.append(f.ko if f else -1)
		print("MATCH_OVER mode=%s w=%d team=%d teams=%d kos=%s" % [sim.combat.mode_id, nm.winner, w.team if w else -9, sim.combat.teams, kos])
		mi += 1
		if mi < MODES.size():
			session.set_rules({"mode": MODES[mi][0], "map": MODES[mi][1]})
			session.vote_rematch()
		elif not done:
			done = true
			print("ALL_MODES")
	return false
