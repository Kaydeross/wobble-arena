extends SceneTree
## Arcade co-op HOST test, headless (run by tools/test-net-host.js scenario "arcade", tests/net_arcade_peer.gd as the
## guest):  godot --headless --path godot --script res://tests/net_arcade_host.gd -- ws://127.0.0.1:PORT/ws --no-save
##
## Opens the Construction hub's "Play co-op" room directly through HostSession (opts `arcade: true`, 2 seats, 1 teammate bot,
## Construction on the generated site, normal difficulty) and starts ALONE: seat 1 is the teammate bot, then the four
## Tradies crew. It walks the run through the M1/M3 guest-side path and prints what the host did, for the Node side to
## line up with the guest's own prints:
##   - starts the stage-1 fight, so the Godot guest joins mid-fight (its `start.arc` state is the stage's intro);
##   - puts guest seat 1 down (`_seat_down`): `am.dn`/`am.dnt` go out, then the 6 s auto-revive sends `am.rv`;
##   - clears stage 1 for real (`_cleared` -> `_pay`), then retries the same stage and clears it again (no double pay);
##   - advances to stage 2 (new `start` + fresh site seed), sets 0.42 boss health / 3 lives / a 50 m shrinking floor for
##     the guest's HUD and shrink checks;
##   - the guest leaves: the seat becomes a teammate bot that keeps fighting and keeps the player's class/kit (M3);
##   - the guest REJOINS: `_hello` sends the current stage's `start` and `bot_to_human` hands seat 1 back;
##   - the host wins (`_win`: victory bonus on its own save) and leaves: the run ends for the guest.
## Prints JSON lines the Node side asserts: HOSTED, START<n>, HOST_STAGE, HOST_FIGHT, PEER_IN, DOWN_SENT, REVIVED_HOST,
## CLEAR1_H, RETRY, HOST_FIGHT2, CLEAR2_H, ADVANCING, HOST_HF, PEER_OUT, SEAT_BOT, REJOIN, HOST_WON, AM_SENT, LEAVE, DONE.

var session := HostSession.new()
var world: Node = null
var starts := 0
var t := 0.0
var t_total := 0.0
var fails := 0
var started := false
var began := false
var stage_printed := -1
var peer_in_at := -1.0
var down_sent := false
var down_at := -1.0
var revived := false
var clear1 := false
var clear1_at := -1.0
var clear1_done_at := -1.0
var retry_started := false
var retry_intro_at := -1.0
var retry_fight := false
var retry_fight_at := -1.0
var clear2 := false
var stage2_go := false
var stage2_fight := false
var stage2_fight_at := -1.0
var stage2_set := false
var peer_out := false
var peer_out_at := -1.0
var seat_bot_printed := false
var rejoined := false
var rejoin_at := -1.0
var won_sent := false
var left := false
var finished := false
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
	# the stage fights are scripted: keep both seats from dying on their own while the driver sets states (the manual
	# seat-down below is not affected: it forces the pin itself).
	if m.state == "fight":
		for k in m.seats.size():
			var f: FighterState = m.seat(k)
			if f != null: f.invuln = maxf(f.invuln, 5.0)
	if peer_in_at < 0.0 and not session.conns.is_empty():
		peer_in_at = t
		print("PEER_IN ", JSON.stringify({"slot": 1, "seat1_kind": str(session.slots[1].get("kind", "")) if session.slots.size() > 1 else "",
			"seat1_ghost": m.seat(1) != null and m.seat(1).is_ghost, "seat1_player": m.seat(1) != null and m.seat(1).is_player,
			"seats": m.seats.size(), "state": m.state, "arc_state": str(nm.arc.get("state", ""))}))
	if int(m.stage) != stage_printed and not m.seats.is_empty():
		stage_printed = int(m.stage)
		print("HOST_STAGE ", JSON.stringify({"st": m.stage, "map": world.map_id, "seed": SiteMap.current_seed,
			"count": m.count(), "seats": m.seats.size(), "enemies": m.enemies.size(),
			"boss": m.boss.net_slot if m.boss != null else -1, "state": m.state, "slots": session.slots.size(),
			"seat1_ghost": m.seat(1) != null and m.seat(1).is_ghost,
			"arc_seed": int((world.start_msg.get("arc", {}) as Dictionary).get("seed", -1))}))
	# stage 1: fight right away, so the guest joins a RUNNING fight
	if not began and m.stage == 0 and m.state == "intro":
		began = true
		m.begin_fight()
		print("HOST_FIGHT ", JSON.stringify({"st": m.stage, "state": m.state, "lives": m.lives}))
	# the guest is in: put ITS seat down (the guest must pin itself from am.dn, not respawn)
	if peer_in_at >= 0.0 and not down_sent and m.state == "fight" and t - peer_in_at > 0.8:
		down_sent = true
		down_at = t
		m._seat_down(1)
		print("DOWN_SENT ", JSON.stringify({"seat": 1, "slot": int(m._seat_slot(1)), "dn": m.downed_seats(),
			"dnt": snappedf(m.seat_revive_left(1), 0.1), "lives": m.lives, "state": m.state}))
	if down_sent and not revived and not m.seat_is_down(1):
		revived = true
		print("REVIVED_HOST ", JSON.stringify({"seat": 1, "state": m.state, "lives": m.lives,
			"next_revive": m._last_revive, "ghost": m.seat(1).is_ghost}))
	# stage 1 clear for real: _cleared -> _pay on the host's own save, am with last.cn
	if revived and not clear1 and m.state == "fight":
		clear1 = true
		clear1_at = t
		m._cleared()
		print("CLEAR1_H ", JSON.stringify({"st": m.stage, "state": m.state, "cn": m._am_seq,
			"coins": int(m.last.get("coins", 0)), "first": bool(m.last.get("first", false)),
			"reward": int(m.last.get("reward", 0)), "bonus": int(m.last.get("bonus", 0)),
			"first_bonus": int(m.last.get("first_bonus", -1))}))
	# let the guest receive the "cleared" am and show its card before the world is rebuilt
	if clear1 and m.state == "cleared" and clear1_done_at < 0.0: clear1_done_at = t
	# retry the same stage: a fresh start, then a second clear that must pay 0 on both saves
	if clear1 and not retry_started and clear1_done_at >= 0.0 and t - clear1_done_at > 0.6:
		retry_started = true
		m.state = "failed"
		m.retry_stage()
		print("RETRY ", JSON.stringify({"st": m.stage, "attempt": m.attempt, "seed": m.stage_seed()}))
	if retry_started and not retry_fight and m.state == "intro" and m.stage == 0:
		if retry_intro_at < 0.0: retry_intro_at = t
		elif t - retry_intro_at > 0.4:
			retry_fight = true
			retry_fight_at = t
			m.begin_fight()
			print("HOST_FIGHT2 ", JSON.stringify({"st": m.stage, "state": m.state, "attempt": m.attempt}))
	if retry_fight and not clear2 and m.state == "fight" and t - retry_fight_at > 0.4:
		clear2 = true
		m._cleared()
		print("CLEAR2_H ", JSON.stringify({"st": m.stage, "cn": m._am_seq, "coins": int(m.last.get("coins", 0)),
			"first": bool(m.last.get("first", false)), "reward": int(m.last.get("reward", 0)),
			"bonus": int(m.last.get("bonus", 0))}))
	if clear2 and not stage2_go and m.state == "cleared":
		stage2_go = true
		m.next_stage()
		print("ADVANCING ", JSON.stringify({"from": 0, "to": m.stage, "seed": m.stage_seed()}))
	# stage 2: start the fight, then set the display numbers the guest mirrors (0.42 boss / 3 lives / 50 m floor)
	if m.stage == 1 and not stage2_fight and m.state == "intro":
		stage2_fight = true
		stage2_fight_at = t
		m.begin_fight()
		print("HOST_FIGHT ", JSON.stringify({"st": m.stage, "state": m.state, "lives": m.lives}))
	if stage2_fight and not stage2_set and m.state == "fight" and m.boss != null:
		stage2_set = true
		m.lives = 3
		m.boss.hp = m.sim.combat.max_hp(m.boss) * 0.42
		var box: Dictionary = m.sim.solids[0]
		var sz := float(box.maxX) - float(box.minX)
		m.sim.combat.rules.shrink = {"S0": sz, "size": 50.0, "start": 50.0, "min": 16.0, "max": sz, "dir": -1, "cycle": 0,
			"hold": 1.0e9, "both": true, "D": sz, "rate": 55.0, "rest": -1.0, "box": box, "id": str(m.sim.map_id)}
		print("HOST_HF ", JSON.stringify({"st": m.stage, "hf": snappedf(m.boss_frac(), 0.01), "lives": m.lives,
			"sh": snappedf(float(m.sim.combat.rules.shrink["size"]), 0.01)}))
	# the guest left: the seat is a teammate bot that keeps fighting and keeps the player's fighter
	if stage2_fight and not peer_out and peer_in_at >= 0.0 and session.conns.is_empty():
		peer_out = true
		peer_out_at = t
		var f: FighterState = nm.slot_fighter(1)
		var brain: Variant = nm.sim.controllers.get(f)
		print("PEER_OUT ", JSON.stringify({"seat1_kind": str(session.slots[1].get("kind", "")) if session.slots.size() > 1 else "",
			"seat1_ghost": m.seat(1) != null and m.seat(1).is_ghost, "seat1_player": m.seat(1) != null and m.seat(1).is_player,
			"seat1_name": str(session.slots[1].get("name", "")) if session.slots.size() > 1 else "",
			"seat1_cls": str(session.slots[1].get("cls", "")) if session.slots.size() > 1 else "",
			"started": session.started, "state": m.state, "bt": m._am_payload().get("bt", [])}))
	if peer_out and not seat_bot_printed and t - peer_out_at > 0.8:
		seat_bot_printed = true
		var f: FighterState = nm.slot_fighter(1)
		var brain: Variant = nm.sim.controllers.get(f)
		var tg := ""
		if brain is BotBrain and (brain as BotBrain).target != null:
			tg = (brain as BotBrain).target.name
		print("SEAT_BOT ", JSON.stringify({"seat": 1, "alive": f != null and not f.dead, "is_ghost": f != null and f.is_ghost,
			"is_player": f != null and f.is_player, "cls": f.class_id if f != null else "", "name": f.name if f != null else "",
			"brain": brain != null and brain is BotBrain, "target": tg, "weapon": f.weapon if f != null else "",
			"state": m.state, "enemies_alive": m.alive_enemies()}))
	# the guest rejoined: the current stage's start and seat 1 back as a human
	if peer_out and not rejoined and not session.conns.is_empty():
		rejoined = true
		rejoin_at = t
		var f: FighterState = nm.slot_fighter(1)
		print("REJOIN ", JSON.stringify({"arc_st": int(nm.arc.get("st", -1)), "arc_seed": int(nm.arc.get("seed", -1)),
			"arc_lv": int(nm.arc.get("lv", -1)), "seat1_kind": str(session.slots[1].get("kind", "")) if session.slots.size() > 1 else "",
			"seat1_ghost": f != null and f.is_ghost, "seat1_human": f != null and f.net_human,
			"seat1_name": str(session.slots[1].get("name", "")) if session.slots.size() > 1 else "",
			"stage": m.stage, "state": m.state}))
	# ... then win (victory bonus on the host's own save) and leave: the run is over for the guest
	if rejoined and not won_sent and t - rejoin_at > 1.2:
		won_sent = true
		m._win()
		print("HOST_WON ", JSON.stringify({"coins": int(m.victory.get("coins", 0)), "first": bool(m.victory.get("first", false)),
			"hat_first": bool(m.victory.get("hat_first", false)), "cn": m._am_seq, "state": m.state}))
	if won_sent and not left and t - rejoin_at > 2.4:
		left = true
		print("LEAVE ", JSON.stringify({"state": m.state, "reason": m.end_reason("You left the room.")}))
		_finish(0)
	return false

func _finish(code: int) -> void:
	if finished: return
	finished = true
	var n := 0
	for x: Variant in session.sent:
		if x is Dictionary and x.get("t") == "am": n += 1
	print("AM_SENT ", JSON.stringify({"n": n, "guarded": session.guarded, "relayed": session.relayed, "started": session.started}))
	print("DONE ", JSON.stringify({"fails": fails, "starts": starts}))
	session.leave("test done")
	if world != null and is_instance_valid(world): world.queue_free()
	world = null
	quit(1 if fails > 0 or code != 0 else 0)
