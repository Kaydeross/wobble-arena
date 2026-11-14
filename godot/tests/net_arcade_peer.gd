extends SceneTree
## Arcade co-op GODOT GUEST test, headless (run by tools/test-net-host.js scenario "arcade", tests/net_arcade_host.gd
## hosting):  godot --headless --path godot --script res://tests/net_arcade_peer.gd -- ws://127.0.0.1:PORT/ws ROOM [mode]
##
## mode "main" (default): joins a RUNNING Arcade co-op room and takes seat 1 (`welcome`, then the host's mid-match `start`
## with `arc`). Rebuilds every stage from `start.arc`: the same generated site seed, the seat/crew ghosts from the slot
## table (the boss included on stage 2), and the host's `am` display state. Checks the guest half of M1/M3: the HUD names
## the stage and shows the boss bar at the host's fraction; a downed `am` pins seat 1 (no local respawn) and the host's
## revive `am.rv` puts it back at the host's spot/health; a clear `am` pays this player's OWN save exactly once (and a
## retry pays 0); `am.sh` sets the shrinking floor. Leaves once stage 2's fight is running so the host can drop the seat.
##
## mode "rejoin": joins the SAME running room again after that drop. It must get the current stage's `start` (arc.st/seed)
## and seat 1 back as a human (`slots[1].kind == "human"`, its own class). Then the host wins and leaves: it prints the
## victory it paid on its own save and, last, the run-over reason World/ArcadeManager give when the host leaves.
##
## Prints JSON lines the Node side asserts: JOINED, START<n>, PEER_STAGE, AM, DOWNED, REVIVED, GUEST_SAVE, GUEST_CARD,
## PEER_HUD, SHRINK, GUEST_VICTORY, HOSTLEFT, DONE.

var session := GuestSession.new()
var world: Node = null
var mode := "main"
var starts := 0
var t := 0.0
var t_total := 0.0
var fails := 0
var printed_start := 0
var am_n := 0
var last_am := ""
var downed_seen := false
var revived_seen := false
var last_paid_cn := 0
var card_seen := ""
var hud_printed := false
var shrink_printed := false
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
		push_error("usage: -- URL ROOMCODE [main|rejoin]"); quit(2); return
	Engine.max_fps = 60
	process_frame.connect(_begin.bind(args), CONNECT_ONE_SHOT)

func _begin(args: PackedStringArray) -> void:
	if args.size() > 2: mode = str(args[2])
	var settings: Node = root.get_node("Settings")
	settings.set_value("class", "kid")
	settings.set_value("name", "GodotArcadePeer")
	session.welcomed.connect(func(slot: int, room: String) -> void: print("JOINED ", JSON.stringify({"slot": slot, "room": room, "gdhost": session.host_gd, "mode": mode})))
	session.ended.connect(_on_ended)
	session.promoted.connect(_on_promoted)
	session.match_started.connect(_on_start)
	session.status_changed.connect(func(s: String) -> void: print("STATUS ", s))
	session.begin(args[0], args[1], {"name": "GodotArcadePeer", "skin": "none", "hat": "cone", "color": 0x39b5a8, "cls": "kid"})

## The room is over: the host left the Arcade run (M5 is cut: no migration inside a run), so the run-over reason must say
## so, not the generic "the host left the room".
func _on_ended(reason: String) -> void:
	print("ENDED ", reason)
	if mode != "rejoin" or done: return
	var mapped := reason
	if world != null and is_instance_valid(world) and world.arcade != null:
		mapped = str(world.arcade.end_reason(reason))
	print("HOSTLEFT ", JSON.stringify({"reason": mapped, "raw": reason}))
	quit_t = 0.0

## The relay promoted me when the host left (it does not send `hostgone` when someone is still in the room). An Arcade
## run does not migrate (M5 is cut): the run is over, and the promoted room is closed.
func _on_promoted(_hs: GuestSession) -> void:
	if mode != "rejoin" or done: return
	var mapped := "The host left. The Arcade run is over."
	if world != null and is_instance_valid(world) and world.arcade != null:
		mapped = str(world.arcade.end_reason("The host left the room."))
	print("HOSTLEFT ", JSON.stringify({"reason": mapped, "raw": "promoted"}))
	quit_t = 0.0

func _on_start(s: Dictionary) -> void:
	starts += 1
	var kinds: Array = []
	for x: Dictionary in s["slots"]: kinds.append(str(x.get("kind", "")))
	var a: Dictionary = s.get("arc", {}) if s.get("arc") is Dictionary else {}
	print("START%d " % starts + JSON.stringify({"n": starts, "map": s["map"], "slots": s["slots"].size(), "kinds": kinds,
		"slots_cls": s["slots"].map(func(x: Dictionary) -> String: return str(x.get("cls", ""))),
		"rules": s["rules"], "arc": a}))
	t = 0.0
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
	if t_total > 240.0:
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
	if starts != printed_start and t > 0.35 and not m.seats.is_empty():
		printed_start = starts
		var a: Dictionary = world.start_msg.get("arc", {}) if world.start_msg.get("arc") is Dictionary else {}
		var crew: Array = a.get("crew", [])
		var crew_ghosts := 0
		for slot: Variant in crew:
			var f: FighterState = nm.slot_fighter(int(slot))
			if f != null and f.is_ghost: crew_ghosts += 1
		var boss := int(a.get("boss", -1))
		var bf: FighterState = nm.slot_fighter(boss) if boss >= 0 else null
		var hf: FighterState = nm.slot_fighter(0)
		var own := int(m.own_seat())
		print("PEER_STAGE ", JSON.stringify({"n": starts, "st": m.stage, "count": m.count(), "map": world.map_id,
			"seed": SiteMap.current_seed, "my_slot": nm.my_slot, "arc_st": int(a.get("st", -1)), "arc_seed": int(a.get("seed", -1)),
			"seat_count": m.seats.size(), "own_seat": own,
			"own_is_me": own >= 0 and own < m.seats.size() and m.seats[own] == nm.sim.player,
			"seat0_is_me": m.seats.size() > 0 and m.seats[0] == nm.sim.player,
			"host_ghost": hf != null and hf.is_ghost, "crew_ghosts": crew_ghosts, "crew_n": crew.size(),
			"boss": boss, "boss_ghost": bf != null and bf.is_ghost, "big": bool(a.get("big", false)),
			"state": m.state, "lives": m.lives}))
	if not m.am.is_empty() and str(m.am) != last_am:
		last_am = str(m.am)
		am_n += 1
		print("AM ", JSON.stringify({"n": am_n, "st": int(m.am.get("st", -1)), "lv": int(m.am.get("lv", -1)),
			"s": str(m.am.get("s", "")), "dn": m.am.get("dn", []), "dnt": m.am.get("dnt", []), "hf": float(m.am.get("hf", 0.0)),
			"sh": float(m.am.get("sh", 0.0)), "cn": int(m.am.get("cn", 0)), "bt": m.am.get("bt", []),
			"rv": m.am.get("rv", {}), "state": m.state, "lives": m.lives}))
	_guest_checks(m, nm)
	return false

## Everything the guest half of M1/M3 has to show, checked from what the presentation manager did with `am`.
func _guest_checks(m, nm: NetMatch) -> void:
	var own_seat := int(m.own_seat())
	# -- the host put me down: the am pins MY fighter, no local respawn, the overlay counts the revive --
	if mode == "main" and not downed_seen and own_seat >= 0:
		var dn: Array = m.am.get("dn", []) if m.am.get("dn") is Array else []
		var mine_down := false
		for v: Variant in dn:
			if int(v) == int(nm.my_slot): mine_down = true
		if mine_down and m.seat_is_down(own_seat):
			downed_seen = true
			var f: FighterState = m.seat(own_seat)
			print("DOWNED ", JSON.stringify({"seat": own_seat, "slot": int(nm.my_slot), "dn": dn,
				"pinned": f != null and f.dead and f.elim, "overlay": m.down_overlay_text(),
				"revive_left": m.seat_revive_left(own_seat), "pinned_flag": m._guest_pinned}))
	# -- the host's revive: my fighter is back, at the host's spot and health fraction, briefly invulnerable --
	if mode == "main" and downed_seen and not revived_seen:
		var rv: Variant = m.am.get("rv")
		if rv is Dictionary and not (rv as Dictionary).is_empty() and int((rv as Dictionary).get("n", 0)) > 0 and m._guest_rv_n > 0:
			revived_seen = true
			var f: FighterState = m.seat(own_seat)
			var hf := float(f.hp / m.sim.combat.max_hp(f)) if f != null else 0.0
			var dxz := Vector2(f.phys.px, f.phys.pz).distance_to(Vector2(float((rv as Dictionary).get("x", 0.0)), float((rv as Dictionary).get("z", 0.0)))) if f != null else -1.0
			print("REVIVED ", JSON.stringify({"seat": own_seat, "alive": f != null and not f.dead and not f.elim,
				"hp_frac": snappedf(hf, 0.01), "rv_hf": float((rv as Dictionary).get("hf", -1.0)),
				"invuln": snappedf(f.invuln, 0.01) if f != null else 0.0, "dxz": snappedf(dxz, 0.01),
				"seat_down": m.seat_is_down(own_seat), "pinned_flag": m._guest_pinned, "rv_n": m._guest_rv_n}))
	# -- a clear `am` paid MY OWN save (once per am.cn); the card is up, buttons host-controlled --
	if m.state != "won" and m._guest_paid_cn > last_paid_cn and m._guest_paid_cn > 0:
		last_paid_cn = m._guest_paid_cn
		var d: Dictionary = m.stage_def()
		var id := str(d.get("id", ""))
		var sv: Node = root.get_node_or_null("Save")           # the autoload is looked up at runtime: --script has none yet
		var dlc: Dictionary = sv.get("dlc") if sv != null and sv.get("dlc") is Dictionary else {}
		print("GUEST_SAVE ", JSON.stringify({"st": m.stage, "id": id, "cn": m._guest_paid_cn, "coins": int(m.last.get("coins", 0)),
			"first": bool(m.last.get("first", false)), "reward": int(m.last.get("reward", 0)),
			"bonus": int(m.last.get("bonus", 0)), "time": snappedf(float(m.last.get("time", 0.0)), 0.1),
			"kos": int(m.last.get("kos", 0)), "save_coins": int(sv.get("coins")) if sv != null else -1,
			"best": DlcSave.best(dlc, m.diff), "cleared": DlcSave.has_cleared(dlc, id, m.diff)}))
	if world != null and world.results_open():
		var card := str(world._results.name)
		if card != card_seen:
			card_seen = card
			var wait: Node = world._results.find_child("Wait", true, false)
			print("GUEST_CARD ", JSON.stringify({"name": card, "wait": wait != null,
				"wait_text": str(wait.text) if wait != null else ""}))
	# -- the HUD strip names the stage/lives and the boss bar mirrors am.hf (and am.sh made the floor shrink) --
	if mode == "main" and m.stage == 1 and m.state == "fight" and not hud_printed and m.hud != null \
			and float(m.am.get("hf", 1.0)) < 0.9 and int(m.am.get("lv", 4)) == 3:
		m.hud.place(world, 0.0, 0.016)
		if m.hud.visible:
			hud_printed = true
			print("PEER_HUD ", JSON.stringify({"strip": str(m.hud.strip.text), "boss_visible": m.hud.boss_visible(),
				"hf": snappedf(m.boss_frac(), 0.01), "am_hf": snappedf(float(m.am.get("hf", -1.0)), 0.01),
				"lives": m.lives, "am_lv": int(m.am.get("lv", -1)), "stage": m.stage}))
	if not shrink_printed and m.sim != null and float(m.am.get("sh", 0.0)) > 0.0 and not m.sim.combat.rules.shrink.is_empty():
		shrink_printed = true
		print("SHRINK ", JSON.stringify({"size": snappedf(float(m.sim.combat.rules.shrink.get("size", 0.0)), 0.01),
			"sh": snappedf(float(m.am.get("sh", 0.0)), 0.01), "mesh": world._shrink_mesh != null}))
	# -- the final victory pays MY OWN save (bonus + the Site Foreman hat conditions) --
	if mode == "rejoin" and m.state == "won" and m._guest_paid_cn > last_paid_cn:
		last_paid_cn = m._guest_paid_cn
		var sv2: Node = root.get_node_or_null("Save")
		print("GUEST_VICTORY ", JSON.stringify({"coins": int(m.victory.get("coins", 0)), "first": bool(m.victory.get("first", false)),
			"hat_first": bool(m.victory.get("hat_first", false)), "hat_owned": bool(m.victory.get("hat_owned", false)),
			"save_coins": int(sv2.get("coins")) if sv2 != null else -1, "cn": m._guest_paid_cn}))
	# the first guest leaves after stage 2's fight is running (the host then drops the seat)
	if mode == "main" and m.stage == 1 and m.state == "fight":
		if stage2_at < 0.0: stage2_at = t
		elif t - stage2_at > 1.5: quit_t = 0.2

func _done() -> void:
	if done: return
	done = true
	var st := -1
	if world != null and is_instance_valid(world) and world.arcade != null: st = int(world.arcade.stage)
	print("DONE ", JSON.stringify({"fails": fails, "starts": starts, "am": am_n, "stage": st, "mode": mode}))
	session.leave("test done")
	if world != null and is_instance_valid(world): world.queue_free()
	world = null
	quit(1 if fails > 0 else 0)
