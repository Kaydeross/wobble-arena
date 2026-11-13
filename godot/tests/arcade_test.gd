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
	await _phases()
	await _replay_and_reload()
	await _classic_after(nodes0)
	print("ARCADE %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------------- helpers ----------------

## A world on a new Arcade run (auto_run off: the test ticks it).
func _launch(stage := 0, easy := true, dmg := 15.0) -> Node:
	var w: Node = AM.call("launch", 4242)
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
	check(got[0] == 1, "the card emits arcade_requested")
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
		var want_coins: int = int(d["coin_reward"]) + int(d["first_clear_bonus"])
		check(int(arc.last["coins"]) == want_coins, "stage %d pays %d coins (%s)" % [si + 1, want_coins, arc.last["coins"]])
		check(sv.coins - c0 >= want_coins, "stage %d coins in the wallet (+%d)" % [si + 1, sv.coins - c0])
		check(int(sv.dlc["arcade_best"]) == si + 1, "arcade_best = %d (%s)" % [si + 1, sv.dlc["arcade_best"]])
		check((sv.dlc["arcade_clears"] as Array).has(str(d["id"])), "%s is in arcade_clears" % d["id"])
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
	check(not (sv.dlc["arcade_clears"] as Array).is_empty() and (sv.dlc["arcade_clears"] as Array).has("_victory"), "victory remembered")
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
	check(int(sv.dlc.get("arcade_best", 0)) == 0, "arcade_best unchanged by a failure")
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
	check(arc.enemies.size() == 3 and sim.fighters.size() == n0 + 2, "backup call: 2 tradies join (%d enemies)" % arc.enemies.size())
	check(w.views.size() == sim.fighters.size(), "the new tradies have views")
	check(int(arc.events.counts.get("backup_call", 0)) == 1, "backup called once")
	boss.hp = sim.combat.max_hp(boss) * 0.2
	_idle(w, 1.0)
	check(arc.enemies.size() == 3, "never a second backup call")
	check(arc.enemies[1].name == "Bluey" and arc.enemies[2].name == "Sparky", "the named tradies come (%s, %s)" % [arc.enemies[1].name, arc.enemies[2].name])
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
	var ct: Array = arc.events.fired.filter(func(e: Array) -> bool: return e[1] == "scope_creep").map(func(e: Array) -> float: return e[0])
	check(absf(ct[0] - 25.0) < 0.1, "scope creep at 25 s (%s)" % [ct])
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
	check(key0 == "jackhammer", "the Client starts with the jackhammer")
	check(b.big_t > 0.0, "the Client is a Giant (big_t)")
	check(arc.phase_n == 0, "no phase at full health")
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
	check(arc.kit[b] == "nailgun", "the Engineer keeps its nail gun")
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
	var want: int = 500 + 1500 + 2000
	check(sv.coins - c0 >= want and sv.coins - c0 < want + 60, "stage + first clear + victory coins paid once (+%d)" % (sv.coins - c0))
	check(_hats().has("foreman"), "hat granted")
	# save + reload through the blob
	var blob: Dictionary = sv.get_blob()
	var dlc: Dictionary = blob["dlc"]
	check(int(dlc["arcade_best"]) == 6 and (dlc["arcade_clears"] as Array).has("the_client") and (dlc["arcade_clears"] as Array).has("_victory"), "blob carries arcade_best / arcade_clears %s" % [dlc])
	sv.reset()
	check(not _hats().has("foreman"), "a fresh profile does not list the Site Foreman hat")
	check(sv.apply_blob(JSON.parse_string(JSON.stringify(blob))), "blob reloads")
	check(int(sv.dlc["arcade_best"]) == 6 and (sv.dlc["arcade_clears"] as Array).has("the_client"), "arcade_best / arcade_clears survive a reload")
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
	check((sv.dlc["arcade_clears"] as Array).count("the_client") == 1 and (sv.dlc["arcade_clears"] as Array).count("_victory") == 1, "no duplicate clears")
	check(_ui(w, "ArcadeVictory").find_child("Quit", true, false) != null, "the victory card has a way back to the title")
	await _free_world(w)

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
