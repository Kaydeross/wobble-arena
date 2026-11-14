extends SceneTree
## Construction DLC Arcade boss rush, headless (run by tools/test-arcade.js, npm run test:godot-arcade):
##   godot --headless --path godot --script res://tests/arcade_test.gd -- --no-save
## 1. Gate: the hub's Arcade card turns on once arcade_manager.gd exists (owned players only), the title wires it, a locked
##    profile cannot launch a run.
## 2. A scripted player clears ALL six stages in order through the real manager and the real stage table (easy bots, a boosted
##    hammer): intro card first (the match frozen behind it), the bots of the table (names, tools, health, speed, Giant Client),
##    the run strip and the boss bar (only on boss stages), the stage-clear card, coins paid, Next stage, the victory card.
## 3. Lives and retry: dying on stage 2 costs a life and retries stage 2 on a fresh site; no lives left = run over.
## 4. Events fire at their intervals (load test crates, revision pads, backup call, deadline shrink, scope creep) and the crates hurt.
## 5. Boss phases at 66 / 33 percent (bumps, toast, the Client's change request swaps tools).
## 6. Coins once per first clear (not on a replay), arcade_best / arcade_clears saved and reloaded, the Site Foreman hat granted once.
## 7. A Classic match afterwards is unaffected (arcade flag cleared, no leaked or orphan nodes).

const FRAME := 1.0 / 60.0
var AM: GDScript          ## arcade_manager.gd, loaded in _run (it uses the autoloads, which a --script registers after this script compiled)
var CH: GDScript
var SM: GDScript          ## site_map.gd
var LD: GDScript          ## ui/locker_data.gd
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _running() -> Variant:
	return AM.get("running")

func _seed() -> int:
	return int(SM.get("current_seed"))

func _hats() -> Array:
	return LD.call("hats")

func _sv() -> Node:
	return root.get_node("Save")

func _unlock() -> void:
	_sv().reset()
	_sv().dlc["owned"] = true

func _run() -> void:
	AM = load("res://dlc/construction/arcade_manager.gd")
	CH = load("res://dlc/construction/construction_hub.gd")
	SM = load("res://dlc/construction/site_map.gd")
	LD = load("res://ui/locker_data.gd")
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	await _gate()
	await _full_run()
	await _lives()
	await _events()
	await _boss_weapon_crates()
	await _phases()
	await _replay_and_reload()
	await _difficulties()
	await _class_pick()
	await _classic_after(nodes0)
	print("ARCADE %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------------- helpers ----------------

## A world on a new Arcade run (auto_run off: the test ticks it).
func _launch(stage := 0, easy := true, dmg := 15.0, diff := "nightmare", cls := "") -> Node:
	var w: Node = AM.call("launch", 4242, diff, cls)
	var arc = w.arcade
	if easy: arc.difficulty_override = "easy"
	arc.player_dmg = dmg
	arc.fixed_seed = 900
	arc.stage = stage
	w.auto_run = false
	root.add_child(w)
	return w

func _ui(w: Node, n: String) -> Node:
	return w.get_node("UI").get_node_or_null(n)

func _press(panel: Node, button: String) -> void:
	var b := panel.find_child(button, true, false) as Button
	check(b != null, "button %s exists" % button)
	if b != null: b.pressed.emit()

func _wait_frames(n := 3) -> void:
	for i in n: await process_frame

func _nearest_enemy(w: Node) -> FighterState:
	var sim: MatchSim = w.sim
	var arc = w.arcade
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in arc.enemies:
		if f.dead or arc.downed.has(f): continue
		var d := Vector2(f.phys.px - sim.player.phys.px, f.phys.pz - sim.player.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

## One scripted frame: face the nearest enemy, close in (a teleport when a prop is in the way), swing the hammer.
func _script_frame(w: Node, i: int, alive := true) -> void:
	var sim: MatchSim = w.sim
	var p := sim.player
	var st: InputState = w.input.state
	if alive: p.hp = sim.combat.max_hp(p)
	var tg := _nearest_enemy(w)
	var go := Vector2.ZERO
	var fire := false
	if tg != null:
		var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		w.cam.yaw = atan2(d.x, d.y)
		w.cam.pitch = -0.1
		if d.length() > 7.0 and i % 40 == 0:
			var away := (-d).normalized() * 1.7
			p.phys.place(tg.phys.px + away.x, tg.phys.py + 0.05, tg.phys.pz + away.y)
		go = Vector2(0, 1) if d.length() > 1.6 else Vector2.ZERO
		fire = d.length() < 2.6
		if i % 131 == 0: st.press("kick")
	st.set_move("script", go)
	st.hold("script", "fire", fire)
	st.hold("script", "jump", i % 197 < 3)

## Plays until the manager leaves "fight" (cleared / failed); returns the seconds it took, -1 on timeout.
func _play(w: Node, limit_s := 90.0) -> float:
	var arc = w.arcade
	var frames := int(limit_s / FRAME)
	for i in frames:
		_script_frame(w, i)
		w.tick(FRAME)
		if arc.state != "fight": return i * FRAME
	return -1.0

func _idle(w: Node, secs: float, keep_alive := true) -> void:
	var p: FighterState = w.sim.player
	for i in int(secs / FRAME):
		if keep_alive: p.invuln = 5.0
		w.input.state.set_move("script", Vector2.ZERO)
		w.tick(FRAME)

func _start_fight(w: Node) -> void:
	var intro := _ui(w, "ArcadeIntro")
	check(intro != null and w.arcade.state == "intro", "stage %d opens with its intro card" % (w.arcade.stage + 1))
	if intro != null: _press(intro, "Start")
	check(w.arcade.state == "fight", "Start begins the fight")
	check(not w.results_open(), "the intro card is gone")

func _free_world(w: Node) -> void:
	w.queue_free()
	await _wait_frames(3)

# ---------------- 1. the gate ----------------

func _gate() -> void:
	check(AM.call("count") == 6, "the stage table has 6 stages (%s)" % AM.call("count"))
	check(CH.call("arcade_ready"), "the hub sees arcade_manager.gd")
	_sv().reset()
	check(AM.call("launch") == null, "a locked profile cannot start the Arcade")
	check(_running() == null, "no run after a refused launch")
	_unlock()
	var hub = CH.new()
	root.add_child(hub)
	await _wait_frames(2)
	hub.open()
	check(not hub.arcade_b.disabled, "the Arcade card is enabled for an owner")
	check(hub.arcade_card.modulate.a > 0.9, "... and not dimmed")
	var got := [0]
	hub.arcade_requested.connect(func() -> void: got[0] += 1)
	hub.arcade_b.pressed.emit()
	check(got[0] == 0 and hub.arc_step == 1 and hub.arc_class_box.visible, "the card opens the class step first")
	hub.arcade_next()
	check(got[0] == 0 and hub.arc_step == 2 and hub.arc_diff_box.visible, "Next opens the difficulty step")
	hub.pick_diff("easy")
	check(str(root.get_node("Settings").get_value("arcade_diff")) == "easy", "the pick is remembered (Settings arcade_diff)")
	hub.arcade_next()
	check(got[0] == 1, "Start emits arcade_requested")
	hub.back()
	check(hub.arc_step == 1, "Back goes to the class step")
	hub.back()
	check(hub.arc_step == 0 and hub.main_view.visible, "Back again returns to the cards")
	_sv().dlc["owned"] = false
	hub.refresh()
	check(hub.arcade_b.disabled, "locked: the Arcade card is disabled")
	hub.free()
	_unlock()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(2)
	check(main.hub.arcade_requested.get_connections().size() > 0, "the title starts the Arcade on arcade_requested")
	main.free()
	await _wait_frames(2)

# ---------------- 2. all six stages ----------------

func _full_run() -> void:
	_unlock()
	var sv := _sv()
	var w := _launch(0)
	var arc = w.arcade
	check(_running() == arc, "the run is active")
	check(w.map_id == "sitegen", "stages play on the generated site (%s)" % w.map_id)
	var table: Array = AM.call("stages")
	var seeds := {}
	for si in 6:
		var d: Dictionary = table[si]
		check(arc.stage == si, "on stage %d (%d)" % [si + 1, arc.stage])
		seeds[_seed()] = true
		check(_seed() == ((4242 + int(d["map_seed_offset"])) & 0xFFFFFFFF), "stage %d site seed = base + offset (%d)" % [si + 1, _seed()])
		var sim: MatchSim = w.sim
		# the intro card freezes the match
		var t0 := sim.elapsed()
		for k in 20: w.tick(FRAME)
		check(is_equal_approx(sim.elapsed(), t0), "stage %d: the match waits behind the intro card" % (si + 1))
		check(not arc.hud.visible, "stage %d: no run strip over the intro card" % (si + 1))
		var intro := _ui(w, "ArcadeIntro")
		check(intro != null and intro.find_child("StageName", true, false).text == str(d["name"]), "stage %d intro names the stage" % (si + 1))
		# the table's fighters
		check(arc.enemies.size() == (d["bots"] as Array).size(), "stage %d has %d enemies" % [si + 1, arc.enemies.size()])
		for bi in arc.enemies.size():
			var spec: Dictionary = d["bots"][bi]
			var f: FighterState = arc.enemies[bi]
			check(f.name == str(spec["name"]), "stage %d bot %d is %s (%s)" % [si + 1, bi, spec["name"], f.name])
			check(f.weapon == str(spec["weapon"]), "%s holds %s (%s)" % [f.name, spec["weapon"], f.weapon])
			var want_hp: float = sim.combat.hp_setting * float(spec["hp"])
			check(absf(sim.combat.max_hp(f) - want_hp) < 0.5, "%s health %.0f = hp setting x %s" % [f.name, sim.combat.max_hp(f), spec["hp"]])
			check(str(sim.looks[f]["skin"]) == str(spec["skin"]) and str(sim.looks[f]["hat"]) == str(spec["hat"]), "%s look" % f.name)
			check((f.big_t > 0.0) == (str(spec["name"]) == "The Client"), "%s Giant flag only for the Client" % f.name)
		check(sim.player.weapon == "hammer", "the player starts with the hammer")
		check(not sim.combat.ffa, "the crew fights you, not each other")
		_start_fight(w)
		for k in 10: _script_frame(w, k); w.tick(FRAME)
		check(arc.hud.visible, "stage %d: run strip shown" % (si + 1))
		check(arc.hud.boss_visible() == bool(d["boss"]), "stage %d: boss bar %s (boss=%s)" % [si + 1, arc.hud.boss_visible(), d["boss"]])
		if bool(d["boss"]): _hud_layout(w, "stage %d" % (si + 1))
		if si == 5:
			check(w.views[arc.boss].scale.x > 1.4, "the Client is drawn 1.5 x (%s)" % w.views[arc.boss].scale)
		var c0: int = sv.coins
		var took := _play(w)
		check(took >= 0.0, "stage %d cleared (%.1fs)" % [si + 1, took])
		check(arc.state == "clearing", "stage %d: clearing (%s)" % [si + 1, arc.state])
		check(not arc.hud.boss_visible(), "stage %d: boss bar gone once the boss is down" % (si + 1))
		for k in int((arc.CLEAR_DELAY + 0.2) / FRAME): w.tick(FRAME)
		var want_coins: int = arc.stage_coins(d)
		check(int(arc.last["coins"]) == want_coins, "stage %d pays %d coins (%s)" % [si + 1, want_coins, arc.last["coins"]])
		check(sv.coins - c0 >= want_coins, "stage %d coins in the wallet (+%d)" % [si + 1, sv.coins - c0])
		check(DlcSave.best(sv.dlc, "nightmare") == si + 1, "arcade_best = %d (%s)" % [si + 1, sv.dlc["arcade_best"]])
		check(DlcSave.has_cleared(sv.dlc, str(d["id"]), "nightmare") and not DlcSave.has_cleared(sv.dlc, str(d["id"]), "easy"), "%s is in the Nightmare arcade_clears only" % d["id"])
		if si < 5:
			var card := _ui(w, "ArcadeClear")
			check(card != null and arc.state == "cleared", "stage %d: the clear card" % (si + 1))
			if card != null:
				check(card.find_child("Earned", true, false) != null, "the clear card shows the coins")
				_press(card, "Next")
			await _wait_frames(3)
		else:
			check(_ui(w, "ArcadeVictory") != null and arc.state == "won", "the victory card after The Client (%s)" % arc.state)
	check(seeds.size() == 6, "six different sites (%d)" % seeds.size())
	check(DlcSave.won_diff(sv.dlc, "nightmare"), "victory remembered")
	check(_hats().has("foreman"), "the Site Foreman hat is unlocked")
	check(arc.victory.get("hat", "") == "foreman" and bool(arc.victory["first"]), "victory grants the hat once (%s)" % [arc.victory])
	print("FULL RUN stages=%d coins=%d time=%.0fs" % [arc.history.size(), arc.run_coins, arc.run_time])
	await _free_world(w)
	check(_running() == null, "the arcade flag is cleared when the world goes")

## The run strip / boss bar against the toast, mode line, score, radar, pause and emote buttons.
func _hud_layout(w: Node, tag: String) -> void:
	var hud: Control = w.hud
	var ah: Control = w.arcade.hud
	w.hud.toast("Crate incoming: Mammoth Sniper Rifle!")
	for i in 3: w.tick(FRAME)
	var vs: Vector2 = hud.get_viewport_rect().size
	var r := Rect2(ah.position, ah.size)
	check(Rect2(Vector2.ZERO, vs).encloses(r), "%s arcade HUD %s inside the screen" % [tag, r])
	for n: String in ["Score", "Radar", "Toast"]:
		var c: Control = hud.get_node(n)
		if c.visible: check(not r.intersects(Rect2(c.position, c.size * c.scale)), "%s arcade HUD overlaps %s" % [tag, n])
	var ml: Control = w.get_node("UI/ModeLine")
	if ml.visible: check(ml.position.y >= r.end.y, "%s mode line under the arcade HUD" % tag)

# ---------------- 3. lives ----------------

func _kill_player(w: Node) -> void:
	var p: FighterState = w.sim.player
	p.invuln = 0.0; p.shield_t = 0.0
	w.sim.combat.hit(p, 1e6, 0.0, 1.0, 0.0, 5.0, false, null)

func _lives() -> void:
	_unlock()
	var sv := _sv()
	var w := _launch(1, true, 1.0)
	var arc = w.arcade
	check(arc.lives == 3 and arc.stage == 1, "stage 2 with 3 lives")
	var seed_a: int = _seed()
	var coins0: int = sv.coins
	_start_fight(w)
	for k in 20: w.tick(FRAME)
	_kill_player(w)
	var n := 0
	while arc.state == "fight" or arc.state == "failing":
		w.tick(FRAME); n += 1
		if n > 600: break
	check(arc.state == "failed", "dying fails the attempt (%s)" % arc.state)
	check(arc.lives == 2, "a life is lost (%d)" % arc.lives)
	check(_ui(w, "ArcadeFailed") != null, "the failed card shows")
	check(arc.stage == 1, "still on stage 2")
	check(sv.coins == coins0 or sv.coins - coins0 < 50, "no stage coins for a failure (+%d)" % (sv.coins - coins0))
	check(DlcSave.best(sv.dlc, "nightmare") == 0, "arcade_best unchanged by a failure")
	_press(_ui(w, "ArcadeFailed"), "Retry")
	await _wait_frames(3)
	check(arc.stage == 1 and arc.attempt == 1 and arc.lives == 2, "retry: stage 2 again, attempt %d, lives %d" % [arc.attempt, arc.lives])
	check(_seed() != seed_a, "retry builds a fresh site (%d vs %d)" % [_seed(), seed_a])
	check(_ui(w, "ArcadeIntro") != null, "retry opens the intro card again")
	for round_i in 2:
		_start_fight(w)
		for k in 20: w.tick(FRAME)
		_kill_player(w)
		n = 0
		while (arc.state == "fight" or arc.state == "failing") and n < 600:
			w.tick(FRAME); n += 1
		if round_i == 0:
			check(arc.state == "failed" and arc.lives == 1, "second death: one life left (%s, %d)" % [arc.state, arc.lives])
			_press(_ui(w, "ArcadeFailed"), "Retry")
			await _wait_frames(3)
		else:
			check(arc.state == "over" and arc.lives == 0, "third death: run over (%s, %d)" % [arc.state, arc.lives])
			check(_ui(w, "ArcadeOver") != null, "the run over card shows")
	arc.retry_stage()
	check(arc.state == "over", "no retry after the run is over")
	await _free_world(w)

# ---------------- 4. events ----------------

func _events() -> void:
	# Engineer: load test crates every 12 s (3 crates, 2.5 s warning)
	_unlock()
	var w := _launch(1, true, 1.0)
	var arc = w.arcade
	_start_fight(w)
	var sim: MatchSim = w.sim
	_idle(w, 11.5)
	check(int(arc.events.counts.get("load_test", 0)) == 0, "load test: nothing before 12 s")
	_idle(w, 1.0)
	check(int(arc.events.counts.get("load_test", 0)) == 1, "load test fires at 12 s")
	check(arc.events._crates.size() == 3, "three crates are falling (%d)" % arc.events._crates.size())
	check(w.get_node_or_null("StageEvents") != null and w.get_node("StageEvents").get_child_count() >= 6, "crates and warning rings are shown")
	var boss: FighterState = arc.boss
	var hp0 := boss.hp
	boss.invuln = 0.0
	arc.events._land({"x": boss.phys.px, "z": boss.phys.pz, "gy": boss.phys.py, "left": 0.0, "dur": 1.0, "node": null, "ring": null})
	check(boss.hp < hp0 - 20.0, "a landing crate hurts the boss (%.0f -> %.0f)" % [hp0, boss.hp])
	_idle(w, 2.6)
	check(arc.events._crates.size() == 0, "the crates have landed")
	_idle(w, 24.0 - 15.1 + 0.2)
	_idle(w, 12.0)
	var times: Array = arc.events.fired.filter(func(e: Array) -> bool: return e[1] == "load_test").map(func(e: Array) -> float: return e[0])
	check(times.size() == 3 and absf(times[0] - 12.0) < 0.1 and absf(times[1] - 24.0) < 0.1 and absf(times[2] - 36.0) < 0.1, "load test every 12 s: %s" % [times])
	await _free_world(w)
	# Designer: revision pads every 15 s for 8 s
	w = _launch(2, true, 1.0)
	arc = w.arcade
	_start_fight(w)
	sim = w.sim
	var pads0: int = sim.pads.size()
	_idle(w, 14.5)
	check(sim.pads.size() == pads0, "revision pads: none before 15 s")
	_idle(w, 1.0)
	check(int(arc.events.counts.get("revision_pads", 0)) == 1 and sim.pads.size() == pads0 + 3, "revision pads appear at 15 s (+%d)" % (sim.pads.size() - pads0))
	var boost: float = sim.pads[sim.pads.size() - 1]["power"]
	check(boost > 20.0, "boost pads bounce harder (%.1f)" % boost)
	_idle(w, 7.7)
	check(sim.pads.size() == pads0, "the pads are gone after 8 s (%d)" % (sim.pads.size() - pads0))
	await _free_world(w)
	# Supervisor: backup call at 50 % health, once
	w = _launch(3, true, 1.0)
	arc = w.arcade
	_start_fight(w)
	sim = w.sim
	boss = arc.boss
	var n0: int = sim.fighters.size()
	boss.hp = sim.combat.max_hp(boss) * 0.6
	_idle(w, 1.0)
	check(arc.enemies.size() == 1, "no backup above 50 %")
	boss.hp = sim.combat.max_hp(boss) * 0.49
	_idle(w, 1.0)
	check(arc.enemies.size() == 2 and sim.fighters.size() == n0 + 1, "backup call: 1 tradie joins (%d enemies)" % arc.enemies.size())
	check(w.views.size() == sim.fighters.size(), "the new tradies have views")
	check(int(arc.events.counts.get("backup_call", 0)) == 1, "backup called once")
	boss.hp = sim.combat.max_hp(boss) * 0.2
	_idle(w, 1.0)
	check(arc.enemies.size() == 2, "never a second backup call")
	check(arc.enemies[1].name == "Bluey", "the named tradie comes (%s)" % arc.enemies[1].name)
	await _free_world(w)
	# Project Manager: the floor closes in after 20 s; scope creep every 25 s (at most 3 extra)
	w = _launch(4, true, 1.0)
	arc = w.arcade
	_start_fight(w)
	sim = w.sim
	var sh: Dictionary = sim.combat.rules.shrink
	check(not sh.is_empty() and float(sh["size"]) >= 63.9, "deadline: the floor starts full (%s)" % sh.get("size"))
	_idle(w, 19.0)
	check(float(sim.combat.rules.shrink["size"]) >= 63.9, "deadline: holds for 20 s")
	_idle(w, 12.0)
	var sz: float = sim.combat.rules.shrink["size"]
	check(sz < 50.0 and sz > 18.0, "deadline: the floor is closing in (%.1f m at 31 s)" % sz)
	check(int(arc.events.counts.get("deadline_shrink", 0)) == 1, "deadline announced once")
	check(sim.combat.rules.hud_text(sim.player).contains("Arena"), "the mode line shows the arena size")
	check(arc.enemies.size() == 2, "scope creep at 25 s: one more worker (%d)" % arc.enemies.size())
	for k in 5: arc.events._creep({"spawn_extra": 1, "max_extra": 3})
	check(arc.enemies.size() == 4, "scope creep never goes past max_extra 3 (%d)" % arc.enemies.size())
	# the ground you see closes in with the collision floor, and reinforcements arrive on what is left of it
	_idle(w, 10.0)
	var half: float = float(sim.combat.rules.shrink["size"]) / 2.0
	check(w._shrink_pad != null and w._shrink_pad.scale.x < 0.9, "the visible floor pad shrinks with the floor (scale %.2f at %.0f m)" % [w._shrink_pad.scale.x if w._shrink_pad else -1.0, half * 2.0])
	check(w._shrink_pad == null or absf(w._shrink_pad.scale.x * 29.0 - half) < 1.0 or w._shrink_pad.scale.x >= 1.0, "the pad's edge sits on the floor's edge")
	var edge_bad := 0
	for k in 12:
		var m: FighterState = arc.spawn_minion()
		if absf(m.phys.px) > half + 0.1 or absf(m.phys.pz) > half + 0.1: edge_bad += 1
	check(edge_bad == 0, "scope creep / backup workers spawn on the shrunk floor (%d off the edge)" % edge_bad)
	var ct: Array = arc.events.fired.filter(func(e: Array) -> bool: return e[1] == "scope_creep").map(func(e: Array) -> float: return e[0])
	check(absf(ct[0] - 25.0) < 0.1, "scope creep at 25 s (%s)" % [ct])
	await _free_world(w)

## Bosses may swap melee for a ranged crate, but kit refills never turn the picked-up gun into endless ammo.
func _boss_weapon_crates() -> void:
	_unlock()
	var w := _launch(1, true, 1.0)
	var arc = w.arcade
	_start_fight(w)
	var sim: MatchSim = w.sim
	var b: FighterState = arc.boss
	check(arc.kit[b] == "drill" and b.weapon == "drill", "the Engineer starts on melee")
	check(sim.pickups.armed_weapon_crates and sim.pickups.bot_wants(b, {"key": "nailgun"}), "an armed Arcade boss wants a ranged crate")
	var before := sim.pickups.list.size()
	arc.events._weapon_drop({"weapon_count": 1})
	check(sim.pickups.list.size() == before + 1 and arc.events.BOSS_RANGED.has(str(sim.pickups.list[-1]["key"])), "a boss-stage weapon crate spawns a ranged tool")
	sim.pickups._take(b, "nailgun")
	check(b.weapon == "nailgun", "the boss equips the ranged weapon it picked up (%s)" % b.weapon)
	var drill_ammo := 0.0
	var gun_ammo := 0.0
	for i in 3:
		var sl: Variant = b.slots[i]
		if sl == null: continue
		if sl["key"] == "drill": drill_ammo = float(sl["ammo"]); sl["ammo"] = 0.0
		if sl["key"] == "nailgun": gun_ammo = float(sl["ammo"]); sl["ammo"] = 5.0
	arc.keep_kit(b)
	for i in 3:
		var sl: Variant = b.slots[i]
		if sl == null: continue
		if sl["key"] == "drill": drill_ammo = float(sl["ammo"])
		if sl["key"] == "nailgun": gun_ammo = float(sl["ammo"])
	check(drill_ammo >= float(sim.combat.wdata("drill")["ammo"]), "the melee kit is topped up")
	check(is_equal_approx(gun_ammo, 5.0), "the picked-up gun is not topped up (%.0f ammo)" % gun_ammo)
	sim.combat.drop_slot(b)
	check(b.weapon == "drill", "the boss returns to its melee kit when the gun runs out (%s)" % b.weapon)
	await _free_world(w)

# ---------------- 5. boss phases ----------------

func _phases() -> void:
	_unlock()
	# The Client: Giant, change request swaps the tools at 66 and 33 %
	var w := _launch(5, true, 1.0)
	var arc = w.arcade
	_start_fight(w)
	var sim: MatchSim = w.sim
	var b: FighterState = arc.boss
	var spd0 := b.phys.speed
	var dmg0 := b.dmg_scale
	var key0: String = arc.kit[b]
	check(key0 == "mallet", "the Client starts with the Giant Mallet")
	check(b.big_t > 0.0, "the Client is a Giant (big_t)")
	check(arc.phase_n == 0, "no phase at full health")
	# the Giant is drawn where he fights: the rig scales about his feet, so his hand and shoulder (read back from it, and the
	# points his swings use) stay next to his body wherever he stands (a scale about the world origin pushed them metres away)
	b.phys.place(24.0, 0.05, -20.0)
	for k in 3: w.tick(FRAME)
	var gv: Node3D = w.views[b]
	check(is_equal_approx(gv.scale.x, 1.5), "the Giant's view is 1.5 x")
	var feet := Vector3(b.phys.px, b.phys.py, b.phys.pz)
	var shoulder_off := Vector2(b.shoulder_x - feet.x, b.shoulder_z - feet.z).length()
	var hand_off := Vector2(b.hand_x - feet.x, b.hand_z - feet.z).length()
	check(shoulder_off < 2.5 and hand_off < 4.0, "the Giant's shoulder (%.1f m) and hand (%.1f m) are by his body, far from the arena centre" % [shoulder_off, hand_off])
	check((gv.position - feet * (1.0 - gv.scale.x)).length() < 0.001, "the Giant's view is scaled about his feet")
	var toasts := []
	var mx := sim.combat.max_hp(b)
	b.hp = mx * 0.65
	sim.combat.events.clear()
	for k in 3: w.tick(FRAME)
	check(arc.phase_n == 1, "phase 1 at 66 %% (%d)" % arc.phase_n)
	check(absf(b.phys.speed - spd0 * 1.1) < 0.001 and absf(b.dmg_scale - dmg0 * 1.2) < 0.001, "phase 1: faster and harder")
	check(int(arc.events.counts.get("change_request", 0)) == 1, "the change request fired")
	var key1: String = arc.kit[b]
	check(key1 != key0, "the Client swapped tools (%s -> %s)" % [key0, key1])
	check(str(sim.combat.wdata(key1).get("type", "")) == "melee", "the Client's change request stays melee (%s)" % key1)
	check(b.weapon == key1 or b.slots.any(func(s: Variant) -> bool: return s != null and s["key"] == key1), "... and holds %s" % key1)
	b.hp = mx * 0.5
	for k in 3: w.tick(FRAME)
	check(arc.phase_n == 1, "no phase between 66 and 33 %")
	b.hp = mx * 0.32
	for k in 3: w.tick(FRAME)
	check(arc.phase_n == 2, "phase 2 at 33 percent")
	check(absf(b.phys.speed - spd0 * 1.21) < 0.001, "phase 2: faster again")
	check(int(arc.events.counts.get("change_request", 0)) == 2, "second change request")
	b.hp = mx * 0.05
	for k in 3: w.tick(FRAME)
	check(arc.phase_n == 2, "only two phases")
	check(arc.phase_log.size() == 2, "phase log")
	await _free_world(w)
	# Another boss (the Engineer): phases bump the boss and toast, but no tool swap
	w = _launch(1, true, 1.0)
	arc = w.arcade
	_start_fight(w)
	sim = w.sim
	b = arc.boss
	mx = sim.combat.max_hp(b)
	var seen_toast := [false]
	b.hp = mx * 0.6
	sim.combat.events.clear()
	sim.step(1.0 / 120.0)
	arc.step(1.0 / 120.0)
	for e: Dictionary in sim.combat.events:
		if e.get("type") == "toast" and str(e.get("text")).contains("fired up"): seen_toast[0] = true
	check(arc.phase_n == 1 and seen_toast[0], "Engineer phase 1 announces itself")
	check(arc.kit[b] == "drill", "the Engineer keeps its cordless drill")
	await _free_world(w)

# ---------------- 6. replay pays nothing, saved and reloaded ----------------

func _replay_and_reload() -> void:
	var sv := _sv()
	# state after _full_run lives in this profile? _lives / _events reset it: replay the whole story on a fresh unlocked profile
	_unlock()
	var w := _launch(5, true, 40.0)            # straight to the last stage (the earlier ones are covered by the full run)
	var arc = w.arcade
	_start_fight(w)
	var c0: int = sv.coins
	check(_play(w) >= 0.0, "the Client falls")
	for k in int(2.0 / FRAME): w.tick(FRAME)
	check(arc.state == "won" and bool(arc.victory["first"]), "first victory")
	var want: int = arc.scaled(500) + arc.scaled(1500) + arc.scaled(2000)
	check(sv.coins - c0 >= want and sv.coins - c0 < want + 60, "stage + first clear + victory coins paid once (+%d)" % (sv.coins - c0))
	check(_hats().has("foreman"), "hat granted")
	# save + reload through the blob
	var blob: Dictionary = sv.get_blob()
	var dlc: Dictionary = blob["dlc"]
	check(DlcSave.best(dlc, "nightmare") == 6 and DlcSave.has_cleared(dlc, "the_client", "nightmare") and DlcSave.won_diff(dlc, "nightmare"), "blob carries arcade_best / arcade_clears %s" % [dlc])
	sv.reset()
	check(not _hats().has("foreman"), "a fresh profile does not list the Site Foreman hat")
	check(sv.apply_blob(JSON.parse_string(JSON.stringify(blob))), "blob reloads")
	check(DlcSave.best(sv.dlc, "nightmare") == 6 and DlcSave.has_cleared(sv.dlc, "the_client", "nightmare"), "arcade_best / arcade_clears survive a reload")
	check(_hats().has("foreman") and sv.set_hat("foreman"), "the hat is listed and wearable after the reload")
	await _free_world(w)
	# the same stage again: no coins, no second hat
	w = _launch(5, true, 40.0)
	arc = w.arcade
	_start_fight(w)
	c0 = sv.coins
	check(_play(w) >= 0.0, "the Client falls again")
	for k in int(2.0 / FRAME): w.tick(FRAME)
	check(arc.state == "won" and not bool(arc.victory["first"]) and int(arc.victory["coins"]) == 0, "second victory grants nothing new (%s)" % [arc.victory])
	check(int(arc.last["coins"]) == 0 and not bool(arc.last["first"]), "replaying a cleared stage pays no stage coins")
	check(sv.coins - c0 < 60, "the wallet only gets K.O. coins (+%d)" % (sv.coins - c0))
	check(((sv.dlc["arcade_clears"] as Dictionary)["nightmare"] as Array).count("the_client") == 1 and ((sv.dlc["arcade_clears"] as Dictionary)["nightmare"] as Array).count("_victory") == 1, "no duplicate clears")
	check(_ui(w, "ArcadeVictory").find_child("Quit", true, false) != null, "the victory card has a way back to the title")
	await _free_world(w)

# ---------------- 6b. difficulties ----------------

func _difficulties() -> void:
	var sv := _sv()
	var tab: Dictionary = AM.call("difficulties")
	check(tab.keys() == ["easy", "normal", "nightmare"], "three difficulties (%s)" % [tab.keys()])
	# tuned numbers (data/extra/construction/stages.json difficulties): changing them is a balance decision, so it fails here first
	var want := {"easy": [5, 0.35, 0.85, 1.5], "normal": [4, 0.65, 1.0, 1.15], "nightmare": [3, 1.0, 1.0, 1.0]}
	for k: String in want:
		var d: Dictionary = tab[k]
		var w: Array = want[k]
		check(int(d["lives"]) == w[0] and is_equal_approx(float(d["dmg_mul"]), w[1]) and is_equal_approx(float(d["speed_mul"]), w[2]) and is_equal_approx(float(d["event_mul"]), w[3]), "%s: lives / damage / speed / event timing %s" % [k, d])
	var n: Dictionary = tab["nightmare"]
	check(is_equal_approx(float(n["hp_mul"]), 1.0) and float(n["hp_floor"]) == 0.0 and float(n["boss_hp_floor"]) == 0.0, "Nightmare keeps the table's health as written")
	check(float(tab["easy"]["coin_mul"]) < float(tab["normal"]["coin_mul"]) and float(tab["normal"]["coin_mul"]) < float(n["coin_mul"]), "coin rewards grow with the difficulty")
	var arcs := {}
	for k: String in want:
		var a = AM.new()
		a.start_run(1, k)
		check(a.lives == want[k][0], "%s starts with %d lives (%d)" % [k, want[k][0], a.lives])
		arcs[k] = a
		a.end_run()
	# every enemy of every stage: Easy < Normal < Nightmare health (the bosses too)
	var stages: Array = AM.call("stages")
	var bad := 0
	for st: Dictionary in stages:
		var boss: bool = bool(st["boss"])
		for i in (st["bots"] as Array).size():
			var h: float = float(st["bots"][i]["hp"])
			var isb := boss and i == 0
			var e: float = arcs["easy"].enemy_hp(h, isb)
			var nm: float = arcs["normal"].enemy_hp(h, isb)
			var nt: float = arcs["nightmare"].enemy_hp(h, isb)
			if not (e < nm and nm < nt and is_equal_approx(nt, h)): bad += 1; print("FAIL hp order %s %s: %.2f %.2f %.2f" % [st["id"], st["bots"][i]["name"], e, nm, nt])
	check(bad == 0, "Easy < Normal < Nightmare health for every enemy and boss")
	# the boss ladder climbs: Engineer < Designer < Supervisor at every difficulty
	for k: String in ["normal", "nightmare"]:
		var hs: Array = []
		for i in [1, 2, 3]: hs.append(arcs[k].enemy_hp(float(stages[i]["bots"][0]["hp"]), true))
		check(hs[0] < hs[1] and hs[1] < hs[2], "%s boss health climbs Engineer %.2f < Designer %.2f < Supervisor %.2f" % [k, hs[0], hs[1], hs[2]])
	# the fighters really get them
	for k: String in ["easy", "nightmare"]:
		var w := _launch(1, false, 1.0, k)
		_start_fight(w)
		var b: FighterState = w.arcade.boss
		var h0: float = float(stages[1]["bots"][0]["hp"])
		check(is_equal_approx(b.cls_hp, w.arcade.enemy_hp(h0, true)), "%s Engineer health multiplier %.2f" % [k, b.cls_hp])
		var want_heal := 0.05 if k == "easy" else 0.10
		check(is_equal_approx(b.heal_frac, want_heal), "%s: a Health Pack heals the boss %.0f %%" % [k, b.heal_frac * 100.0])
		var mx: float = w.sim.combat.max_hp(b)
		b.hp = mx * 0.2
		w.sim.pickups._take(b, "heal")
		check(absf(b.hp - mx * (0.2 + want_heal)) < 0.01, "%s: the pack really gave the boss %.0f %% (hp %.1f of %.1f)" % [k, want_heal * 100.0, b.hp, mx])
		check(w.sim.player.heal_frac == 0.6, "the player's Health Pack stays 60 %")
		check(is_equal_approx(w.arcade.lives, want[k][0]), "%s lives in the run" % k)
		var ev = w.arcade.events
		var le: Dictionary = ev.evs[0]
		check(is_equal_approx(float(le["every"]), 12.0 * want[k][3]), "%s: load test every %.1f s" % [k, le["every"]])
		await _free_world(w)
	# first-clear coins are paid once PER difficulty; an Easy victory pays coins but no hat
	_unlock()
	var coins_seen := {}
	for k: String in ["easy", "normal"]:
		var w := _launch(5, true, 40.0, k)
		var arc = w.arcade
		_start_fight(w)
		var c0: int = sv.coins
		check(_play(w) >= 0.0, "%s: the Client falls" % k)
		for i in int(2.0 / FRAME): w.tick(FRAME)
		check(arc.state == "won" and bool(arc.victory["first"]), "%s: first victory pays its own bonus (%s)" % [k, arc.victory])
		check(int(arc.last["coins"]) == arc.stage_coins(stages[5]), "%s: the Client's first clear pays %d" % [k, arc.last["coins"]])
		check(int(arc.victory["coins"]) == arc.scaled(2000), "%s: victory bonus x coin multiplier (%d)" % [k, arc.victory["coins"]])
		coins_seen[k] = int(arc.last["coins"])
		check(DlcSave.best(sv.dlc, k) == 6 and DlcSave.won_diff(sv.dlc, k), "%s progress saved under %s" % [k, k])
		var card := _ui(w, "ArcadeVictory")
		var hat_l := card.find_child("Hat", true, false) as Label
		if k == "easy":
			check(not _hats().has("foreman") and not bool(arc.victory["hat_first"]), "an Easy victory grants no hat")
			check(hat_l != null and hat_l.text.contains("Normal or Nightmare"), "... and the card says how to get it (%s)" % [hat_l.text if hat_l else ""])
			check(DlcSave.best(sv.dlc, "normal") == 0 and DlcSave.best(sv.dlc, "nightmare") == 0, "Easy progress stays on Easy")
		else:
			check(_hats().has("foreman") and bool(arc.victory["hat_first"]), "the first Normal victory grants the Site Foreman hat")
		await _free_world(w)
	check(coins_seen["easy"] < coins_seen["normal"], "Normal pays more than Easy (%s)" % [coins_seen])
	# the menu text
	var hub = CH.new()
	root.add_child(hub)
	await _wait_frames(2)
	hub.open()
	hub.show_arcade(2)
	check(hub.best_text("easy") == "Cleared" and hub.best_text("nightmare") == "Not played yet", "picker: best per difficulty (%s / %s)" % [hub.best_text("easy"), hub.best_text("nightmare")])
	sv.dlc["arcade_best"]["nightmare"] = 4
	check(hub.best_text("nightmare") == "Best: stage 4/6", "picker: Best: stage 4/6 (%s)" % hub.best_text("nightmare"))
	hub.free()
	await _wait_frames(2)

# ---------------- 6c. the class pick ----------------

func _class_pick() -> void:
	var st := root.get_node("Settings")
	var sv := _sv()
	_unlock()
	st.set_value("class", "kid")
	var hub = CH.new()
	root.add_child(hub)
	await _wait_frames(2)
	hub.open()
	hub.show_arcade(1)
	await _wait_frames(3)
	var wz = hub.arc_wizard
	check(wz != null and wz.class_only and wz.cls == "kid", "the class step preselects the last class (%s)" % [wz.cls if wz else ""])
	check(wz.get_node("Head").visible == false and wz.get_node("Foot").visible == false, "only the Character page shows")
	var owned := 0
	for id: String in wz._class_bs:
		var c: Control = wz._class_bs[id]
		check(c.visible == sv.owns_class(id), "class card %s visible = owned (%s)" % [id, c.visible])
		if c.visible: owned += 1
	check(owned >= 5, "the five starter classes are offered (%d)" % owned)
	wz.set_class("bruiser")
	hub.show_arcade(2)
	check(hub.arcade_class() == "bruiser", "the pick reaches the run")
	var got := [""]
	hub.arcade_requested.connect(func() -> void: got[0] = str(st.get_value("class")))
	hub.arcade_next()
	check(got[0] == "bruiser", "Start writes the Settings class like the wizard does (%s)" % got[0])
	hub.free()
	await _wait_frames(2)
	# the run uses it on every stage and retry
	var w := _launch(0, true, 1.0, "nightmare", "bruiser")
	var p0: FighterState = w.sim.player
	var cd: Dictionary = root.get_node("Content").classes["bruiser"]
	check(p0.class_id == "bruiser" and is_equal_approx(p0.cls_hp, float(cd["hp"])), "stage 1 starts as a Bruiser (hp x%.2f)" % p0.cls_hp)
	_start_fight(w)
	w.arcade.stage = 1
	w.arcade.attempt = 1
	w.load_map(w.map_id)
	await _wait_frames(2)
	check(w.sim.player.class_id == "bruiser", "... still a Bruiser on the next stage / retry")
	await _free_world(w)
	var w2 := _launch(0, true, 1.0, "nightmare", "wobbler")
	check(w2.sim.player.class_id == "wobbler" and is_equal_approx(w2.sim.player.cls_hp, 1.0), "a Wobbler run is unchanged")
	await _free_world(w2)
	# a class that is not owned is not offered, and cannot be launched with
	var secret := ""
	for id: String in root.get_node("Content").classes:
		if not sv.owns_class(id): secret = id
	if secret != "":
		var h2 = CH.new()
		root.add_child(h2)
		await _wait_frames(2)
		h2.open()
		st.set_value("class", secret)
		h2.show_arcade(1)
		await _wait_frames(3)
		check(not (h2.arc_wizard._class_bs[secret] as Control).visible and h2.arc_wizard.cls != secret, "an unowned class (%s) is not offered or preselected" % secret)
		h2.free()
	st.set_value("class", "wobbler")
	await _wait_frames(2)

# ---------------- 7. nothing leaks into a normal match ----------------

func _classic_after(nodes0: int) -> void:
	_sv().reset()
	var seed_before: int = _seed()
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = "arena"
	w.mode_id = "classic"
	w.auto_run = false
	w.bot_count = 3
	w.rng_seed = 31
	root.add_child(w)
	check(w.arcade == null and _running() == null, "a Classic match has no arcade run")
	for i in 240: w.tick(FRAME)
	check(w.sim.combat.ffa and w.sim.combat.rules.shrink.is_empty(), "Classic rules untouched (ffa, no shrink)")
	check(w.get_node_or_null("UI/ArcadeHud") == null and w.get_node_or_null("StageEvents") == null, "no arcade nodes in a Classic match")
	check(_seed() == seed_before, "the site seed is the game's own again (%d)" % _seed())
	await _free_world(w)
	await _wait_frames(2)
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("NODES before=%d after=%d orphans=%d" % [nodes0, nodes1, orphans])
	check(nodes1 <= nodes0 + 2, "no node leak (%d -> %d)" % [nodes0, nodes1])
	check(orphans == 0, "no orphan nodes (%d)" % orphans)
