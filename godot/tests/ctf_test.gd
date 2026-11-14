extends SceneTree
## Capture the Flag (logic/ctf.gd, world/ctf_view.gd), headless, run by tools/test-ctf.js (npm run test:godot-ctf):
##   godot --headless --path godot --script res://tests/ctf_test.gd -- --no-save
## 1 every CTF map: the stand is on the floor near the middle and not inside a box; 2 pickup; 3 a 30 s hold wins for the
## holder's team (either team); 4 a K.O. drops the flag where the carrier fell and resets the hold; the drop lock;
## 5 a ring-out returns the flag to the stand; 6 the 5:00 clock: most total hold time, then K.O.s, then the player's team
## loses; 7 bots go for the free flag and a bots-only match ends by the rules; 8 the mode is in the wizard, has a card, and
## is offline only (not hosted, not in the Host sheet); 9 the HUD line and the flag view.

const DT := 1.0 / 120.0
var fails := 0
var content: Node

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	content = root.get_node("Content")
	_maps()
	_pickup_and_win()
	_drop_and_ring_out()
	_clock()
	_bots()
	_wiring()
	await _view()
	print("CTF %s" % ("ok" if fails == 0 else "FAILED %d" % fails))
	quit(0 if fails == 0 else 1)

## A CTF match on `map_id` (bots idle unless `think` is true; the player stands still).
func _sim(map_id: String, bots := 3, think := false, seed_ := 4242) -> MatchSim:
	var map: Dictionary = (content.get_map(map_id) as Dictionary).duplicate(true)
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(seed_)
	sim.configure("ctf", -1)
	sim.setup(map_id, map, map.get("geometry", {}).get("ladders", []), map.get("geometry", {}).get("bouncePads", []),
		"wobbler", PlayerControl.new(InputState.new()), ModeRules.bot_count("ctf", sim.combat.modes, bots), "normal", false)
	if not think:
		for b: FighterState in sim.fighters:
			if b != sim.player: sim.controllers.erase(b)
	return sim

func _ctf(sim: MatchSim) -> CtfRules:
	return sim.combat.rules.ctf

func _run_steps(sim: MatchSim, secs: float) -> void:
	var n := int(secs / DT)
	for i in n:
		sim.step(DT)
		if sim.combat.rules.match_over: break
	sim.combat.events.clear()

func _at(sim: MatchSim, f: FighterState, p: Vector3) -> void:
	sim.combat.place_at(f, p.x, p.z, p.y)

## Everyone far from the flag (so only the fighter we move can take it).
func _park(sim: MatchSim) -> void:
	var st := _ctf(sim).stand
	var k := 0
	for f: FighterState in sim.fighters:
		var q := _far(sim, st, k)
		sim.combat.place_at(f, q.x, q.z, q.y); k += 1

## A start point of the map at least 12 m from `st`.
func _far(sim: MatchSim, st: Vector3, k: int) -> Vector3:
	var pts: Array = []
	for sp: Array in MatchSim.start_points(sim.map):
		if Vector2(float(sp[0]) - st.x, float(sp[1]) - st.z).length() > 12.0: pts.append(Vector3(float(sp[0]), float(sp[2]), float(sp[1])))
	if pts.is_empty(): return st + Vector3(40.0 + k, 0.0, 0.0)
	return pts[k % pts.size()]

func _teams(sim: MatchSim) -> Array:
	var n := [0, 0]
	for f: FighterState in sim.fighters: n[f.team] += 1
	return n

func _maps() -> void:
	check(ModeRules.CTF_MAPS.size() >= 6, "CTF has 6+ maps (%d)" % ModeRules.CTF_MAPS.size())
	for id: String in ModeRules.CTF_MAPS:
		check(content.maps.has(id), "%s exists" % id)
		var sim := _sim(id)
		var c := _ctf(sim)
		check(c != null, "%s: CTF rules exist" % id)
		var st := c.stand
		var fy := CtfRules.floor_at(sim.solids, st.x, st.z, st.y, sim.ring_out_y)
		check(fy != -INF and absf(fy - st.y) < 0.5, "%s: the stand (%.1f, %.1f, %.1f) is on the floor (floor %.2f)" % [id, st.x, st.y, st.z, fy])
		var inside := false
		for b: Dictionary in sim.solids:
			if st.x > float(b["minX"]) + 0.01 and st.x < float(b["maxX"]) - 0.01 and st.z > float(b["minZ"]) + 0.01 and st.z < float(b["maxZ"]) - 0.01 \
					and float(b["bottom"]) < st.y + 1.2 and float(b["top"]) > st.y + 0.15: inside = true
		check(not inside, "%s: the stand is not inside a box" % id)
		check(MatchSim.start_point_safe(sim.solids, st.x, st.z, st.y, sim.ring_out_y), "%s: the stand is 2 m from the void" % id)
		check(Vector2(st.x, st.z).length() < 14.0, "%s: the stand is near the middle (%.1f m)" % [id, Vector2(st.x, st.z).length()])
		var n := _teams(sim)
		check(n[0] == n[1] and sim.combat.teams == 2, "%s: two even teams %s" % [id, n])
		print("CTF-MAP %-10s stand %5.1f %4.1f %5.1f  (%.1f m from the middle)" % [id, st.x, st.y, st.z, Vector2(st.x, st.z).length()])
		sim.dispose()

func _pickup_and_win() -> void:
	var sim := _sim("crossroads")
	var c := _ctf(sim)
	var p := sim.player
	_park(sim)
	check(c.carrier == null and c.at_stand and c.holder == -1, "the flag starts free on its stand")
	_run_steps(sim, 0.5)
	check(c.carrier == null, "nobody near: nobody takes it")
	_at(sim, p, c.stand + Vector3(1.0, 0.0, 0.0))                      # 1.0 m away: inside GRAB_R
	_run_steps(sim, 0.1)
	check(c.carrier == p and c.holder == 0, "the player takes the flag (team 0 holds)")
	var toast := false
	_at(sim, p, c.stand)
	_run_steps(sim, 1.0)
	check(is_equal_approx(c.hold, 1.0) or absf(c.hold - 1.1) < 0.05, "hold counts up in whole-match time (%.2f)" % c.hold)
	_run_steps(sim, 20.0)
	check(not sim.combat.rules.match_over and c.hold > 20.0 and c.hold < 23.0, "no win before 30 s (%.1f)" % c.hold)
	var won := false
	var title := ""
	var sub := ""
	for i in int(12.0 / DT):
		sim.step(DT)
		for e: Dictionary in sim.combat.events:
			if e["type"] == "match_over": won = bool(e["won"]); title = str(e["title"]); sub = str(e["sub"])
		if sim.combat.rules.match_over: break
	check(sim.combat.rules.match_over and sim.combat.rules.winner != null and sim.combat.rules.winner.team == 0, "30 s of holding ends the match for the carrier's team")
	check(won and title == "YOUR TEAM WINS!" and sub == "Held the flag for 30 seconds", "banner: %s / %s" % [title, sub])
	check(c.hold >= 29.99 and c.total[0] >= 29.99 and c.total[1] == 0.0, "totals: %s hold %.2f" % [c.total, c.hold])
	sim.dispose()
	# the enemy team can win too
	var sim2 := _sim("donut")
	var c2 := _ctf(sim2)
	_park(sim2)
	var e: FighterState = null
	for f: FighterState in sim2.fighters:
		if f.team == 1: e = f; break
	_at(sim2, e, c2.stand)
	_run_steps(sim2, 0.1)
	check(c2.carrier == e and c2.holder == 1, "an enemy bot takes it (team 1)")
	var title2 := ""
	for i in int(31.0 / DT):
		sim2.step(DT)
		for ev: Dictionary in sim2.combat.events:
			if ev["type"] == "match_over": title2 = str(ev["title"])
		sim2.combat.events.clear()
		if sim2.combat.rules.match_over: break
	check(sim2.combat.rules.match_over and sim2.combat.rules.winner.team == 1 and title2 == "ENEMY TEAM WINS!", "the other team wins by holding (%s)" % title2)
	sim2.dispose()

func _drop_and_ring_out() -> void:
	var sim := _sim("crossroads")
	var c := _ctf(sim)
	var p := sim.player
	var en: FighterState = null
	for f: FighterState in sim.fighters:
		if f.team == 1: en = f; break
	_park(sim)
	_at(sim, p, c.stand)
	_run_steps(sim, 8.0)
	check(c.carrier == p and c.hold > 7.5, "carrying for 8 s (%.1f)" % c.hold)
	# a real K.O.: the enemy kills the carrier a few metres from the stand
	_at(sim, p, c.stand + Vector3(4.0, 0.0, 3.0))
	var r := sim.combat.hit(p, 9999.0, 0.0, 0.0, 0.0, 1.0, false, en)
	check(bool(r["ko"]) and p.dead, "the carrier is K.O.'d")
	check(c.carrier == null and c.hold == 0.0 and c.holder == -1, "a K.O. drops the flag and resets the hold")
	check(absf(c.pos.x - (c.stand.x + 4.0)) < 0.3 and absf(c.pos.z - (c.stand.z + 3.0)) < 0.3 and not c.at_stand, "the flag lies where the carrier fell (%.1f, %.1f)" % [c.pos.x, c.pos.z])
	check(c.total[0] > 7.5, "the total hold time is kept (%.1f)" % c.total[0])
	var texts: Array = []
	for e: Dictionary in sim.combat.events:
		if e["type"] == "toast": texts.append(e["text"])
	check(texts.has("Flag dropped!"), "toast: Flag dropped! (%s)" % [texts])
	# the 1 s lock: an enemy standing on the flag cannot take it at once, but can after the lock
	_at(sim, en, c.pos)
	_run_steps(sim, 0.5)
	check(c.carrier == null, "locked for %.1f s after a drop" % CtfRules.DROP_LOCK)
	_run_steps(sim, 0.7)
	check(c.carrier == en and c.holder == 1, "after the lock the enemy takes it")
	var took := false
	check(c.hold < 0.5, "the new hold starts from 0 (%.2f)" % c.hold)
	# ring-out: the enemy carrier falls off the map, the flag goes back to the stand
	sim.combat.events.clear()
	en.phys.py = sim.ring_out_y - 1.0
	_run_steps(sim, 0.05)
	check(c.carrier == null and c.at_stand and c.pos.is_equal_approx(c.stand), "a ring-out returns the flag to the stand")
	check(c.hold == 0.0 and c.holder == -1, "and resets the hold")
	sim.dispose()
	# a dead carrier the hooks missed is dropped by the safety net
	var sim2 := _sim("farm")
	var c2 := _ctf(sim2)
	_park(sim2)
	_at(sim2, sim2.player, c2.stand)
	_run_steps(sim2, 0.2)
	check(c2.carrier == sim2.player, "farm: taken")
	sim2.player.dead = true
	_run_steps(sim2, 0.05)
	check(c2.carrier == null, "safety net: a dead carrier is dropped")
	# nobody can take it while they are eliminated
	sim2.player.dead = false; sim2.player.elim = true
	_at(sim2, sim2.player, c2.pos)
	_run_steps(sim2, 1.5)
	check(c2.carrier == null, "an eliminated fighter cannot take the flag")
	sim2.dispose()

func _clock() -> void:
	# most TOTAL hold time wins
	var sim := _sim("crossroads")
	var c := _ctf(sim)
	_park(sim)
	c.total = [12.0, 20.0]; c.clock = 0.01
	var sub := ""
	var title := ""
	_run_steps_events(sim, 0.1)
	for e: Dictionary in _last_over: sub = str(e["sub"]); title = str(e["title"])
	check(sim.combat.rules.match_over and sim.combat.rules.winner.team == 1, "clock: the team with the most total hold time wins (team %s)" % [sim.combat.rules.winner.team if sim.combat.rules.winner else "none"])
	check(title == "ENEMY TEAM WINS!" and sub == "Held the flag the longest", "clock banner: %s / %s" % [title, sub])
	sim.dispose()
	# exact tie: more K.O.s
	var sim2 := _sim("crossroads")
	var c2 := _ctf(sim2)
	_park(sim2)
	c2.total = [5.0, 5.0]; c2.clock = 0.01
	sim2.player.ko = 3
	_run_steps_events(sim2, 0.1)
	for e: Dictionary in _last_over: sub = str(e["sub"]); title = str(e["title"])
	check(sim2.combat.rules.match_over and sim2.combat.rules.winner.team == 0 and title == "YOUR TEAM WINS!" and sub == "Most K.O.s when the clock ran out", "clock tie: more K.O.s wins (%s / %s)" % [title, sub])
	sim2.dispose()
	# still tied: the player's team loses
	var sim3 := _sim("crossroads")
	var c3 := _ctf(sim3)
	_park(sim3)
	c3.total = [5.0, 5.0]; c3.clock = 0.01
	_run_steps_events(sim3, 0.1)
	for e: Dictionary in _last_over: sub = str(e["sub"]); title = str(e["title"])
	check(sim3.combat.rules.match_over and sim3.combat.rules.winner.team == 1 and title == "ENEMY TEAM WINS!" and sub == "Dead even when the clock ran out", "clock dead heat: the player's team loses (%s / %s)" % [title, sub])
	sim3.dispose()
	# the clock runs: 5:00
	var sim4 := _sim("crossroads")
	check(is_equal_approx(_ctf(sim4).clock, 300.0), "the clock starts at 5:00")
	_park(sim4)
	_run_steps(sim4, 10.0)
	check(absf(_ctf(sim4).clock - 290.0) < 0.1, "and counts down (%.1f)" % _ctf(sim4).clock)
	sim4.dispose()

var _last_over: Array = []
func _run_steps_events(sim: MatchSim, secs: float) -> void:
	_last_over = []
	for i in int(secs / DT):
		sim.step(DT)
		for e: Dictionary in sim.combat.events:
			if e["type"] == "match_over": _last_over.append(e)
		sim.combat.events.clear()
		if sim.combat.rules.match_over: break

func _bots() -> void:
	# the free flag draws one bot per team toward it
	var sim := _sim("crossroads", 5, true)
	var c := _ctf(sim)
	var b := BotBrain.new(content.difficulties["normal"], "normal")
	sim.controllers[sim.player] = b            # a bots-only match: the player's wobbler is played by a bot too
	for f: FighterState in sim.fighters: sim.combat.place_at(f, f.phys.px, f.phys.pz, f.phys.py)
	var first_goal := false
	var near0 := INF
	for i in int(6.0 / DT):
		sim.step(DT)
		sim.combat.events.clear()
		if not first_goal and i > 40:
			var g0: Array = c.bot_goal(c.chaser[0]) if c.chaser[0] != null else []
			var g1: Array = c.bot_goal(c.chaser[1]) if c.chaser[1] != null else []
			if c.carrier == null and g0.size() > 0 and g1.size() > 0 and g0[2] == "go" and g1[2] == "go": first_goal = true
		if c.carrier != null: break
	check(first_goal or c.carrier != null, "bots of both teams head for the free flag")
	# the full match, bots only, to its end by the rules (two seeds, two maps)
	for cs: Array in [["crossroads", 5, 11], ["fortress", 3, 12], ["arenaxl", 7, 13], ["farm", 3, 14], ["donut", 5, 15], ["colosseum", 3, 16]]:
		var s := _sim(cs[0], cs[1], true, cs[2])
		s.controllers[s.player] = BotBrain.new(content.difficulties["normal"], "normal")
		var cc := _ctf(s)
		var takes := 0
		var drops := 0
		var over := false
		var sub := ""
		var by_clock := false
		var steps := 0
		while steps < int(330.0 / DT):
			s.step(DT); steps += 1
			for e: Dictionary in s.combat.events:
				if e["type"] == "ctf" and e["kind"] == "take": takes += 1
				if e["type"] == "ctf" and e["kind"] != "take": drops += 1
				if e["type"] == "match_over": over = true; sub = str(e["sub"])
			s.combat.events.clear()
			if s.combat.rules.match_over: break
		by_clock = cc.timeout
		check(over and s.combat.rules.match_over, "%s: the bots-only match ends (%.0f s, %d takes, %d drops, '%s')" % [cs[0], steps * DT, takes, drops, sub])
		check(takes > 0, "%s: the bots picked the flag up (%d)" % [cs[0], takes])
		check(by_clock or cc.hold >= CtfRules.HOLD_WIN - 0.01, "%s: it ended on the hold or the clock" % cs[0])
		print("CTF-BOTS %-10s %3.0f s  takes %d  drops %d  totals %.1f/%.1f  %s" % [cs[0], steps * DT, takes, drops, cc.total[0], cc.total[1], "clock" if by_clock else "hold"])
		s.dispose()
	# an enemy bot goes for the carrier; a teammate stays near the carrier; the carrier runs away
	var s2 := _sim("crossroads", 5, true)
	var c2 := _ctf(s2)
	_park(s2)
	var mate: FighterState = null
	var foe: FighterState = null
	for f: FighterState in s2.fighters:
		if f == s2.player: continue
		if f.team == 0 and mate == null: mate = f
		if f.team == 1 and foe == null: foe = f
	_at(s2, s2.player, c2.stand)
	c2.take(s2.player)
	var tgt := c2.bot_target(foe)
	check(tgt == s2.player, "an enemy bot targets the carrier first")
	var far := c2.stand + Vector3(0.0, 0.0, 20.0)
	_at(s2, mate, Vector3(far.x, c2.stand.y, far.z))
	var g := c2.bot_goal(mate)
	check(g.size() == 3 and g[2] == "escort", "a teammate 20 m away is told to escort the carrier")
	_at(s2, mate, c2.stand + Vector3(2.0, 0.0, 0.0))
	check(c2.bot_goal(mate).is_empty(), "a teammate within 6 m fights instead")
	c2.drop(s2.player, false)
	c2.take(foe)
	_at(s2, foe, c2.stand)
	_at(s2, s2.player, c2.stand + Vector3(5.0, 0.0, 0.0))
	var fg := c2.bot_goal(foe)
	check(fg.size() == 3 and fg[2] == "flee" and float(fg[0]) < foe.phys.px, "a carrier bot runs away from the nearest enemy")
	s2.dispose()

func _wiring() -> void:
	check(ModeRules.PLAYABLE.has("ctf") and ModeRules.OFFLINE_ONLY.has("ctf"), "ctf is playable and offline only")
	check(content.modes.has("ctf") and str(content.modes["ctf"]["name"]) == "Capture the Flag", "the mode is in modes.json: Capture the Flag")
	check(str(content.modes["ctf"]["desc"]) == "Grab the flag and hold it for 30 seconds to win for your team", "its description")
	var wiz := FileAccess.get_file_as_string("res://data/extra/wizard.json")
	var d: Dictionary = JSON.parse_string(wiz)
	var in_sec := false
	for sec: Dictionary in d["sections"]:
		if (sec["modes"] as Array).has("ctf"): in_sec = true
	check(in_sec and d["modes"].has("ctf") and str(d["modes"]["ctf"]["short"]) != "" and str(d["modes"]["ctf"]["icon"]) == "flag", "a wizard card in a section with a short line and the flag icon")
	check(ModeRules.maps_for("ctf").size() >= 6 and ModeRules.maps_for("ctf").size() == ModeRules.CTF_MAPS.size(), "the wizard lists its maps (%s)" % [ModeRules.maps_for("ctf")])
	check(not HostSession.online_modes().has("ctf"), "not in the Host sheet")
	var hs := HostSession.new()
	check(hs.net_mode("ctf") == "classic", "a hosted room never plays ctf (net_mode)")
	check(NetMatch.play_mode(content.modes, {"mode": "ctf"}) == "classic" and NetMatch.play_mode(content.modes, {"gmode": "ctf"}) != "ctf", "a guest never plays ctf (play_mode)")
	check(not NetMatch.GODOT_MODES.has("ctf"), "not an app-only online mode")
	check(ModeRules.bot_count("ctf", content.modes, 3) == 3 and ModeRules.bot_count("ctf", content.modes, 4) == 5, "team sizes follow the Players page (odd bot counts)")
	check(ModeRules.preset_limit("ctf", content.modes) == 0, "no K.O. limit")

func _view() -> void:
	var sim := _sim("crossroads")
	var c := _ctf(sim)
	var rules := sim.combat.rules
	check(rules.hud_text(sim.player).begins_with("Flag free"), "HUD, free: %s" % rules.hud_text(sim.player))
	check(rules.hud_text(sim.player).ends_with("5:00"), "HUD shows the 5:00 clock")
	_park(sim)
	c.take(sim.player)
	c.hold = 12.4
	check(rules.hud_text(sim.player).begins_with("FLAG  Blue 12/30"), "HUD, held: %s" % rules.hud_text(sim.player))
	var view := CtfView.new()
	root.add_child(view)
	view.bind(c)
	await process_frame
	check(view.get_child_count() >= 2 and view.get_node("Flag") != null and view.get_node("FlagStand") != null, "the view has a stand and a flag")
	var fl: Node3D = view.get_node("Flag")
	check(fl.scale.x < 0.9, "carried: a small flag on the carrier's back")
	check(absf(fl.position.x - sim.player.phys.px) < 0.6 and absf(fl.position.z - sim.player.phys.pz) < 0.6, "...at the carrier")
	c.drop(sim.player, false)
	view.update(0.0)
	check(fl.scale.x >= 1.0 and absf(fl.position.x - c.pos.x) < 0.01, "dropped: full size where it lies")
	view.queue_free()
	await process_frame
	sim.dispose()
