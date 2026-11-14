extends SceneTree
## Pre-match countdown test (headless, node tools/test-countdown.js):
##   godot --headless --path godot --script res://tests/countdown_test.gd -- --no-save
## The countdown locks the match until "GO!":
##   - with countdown_force = true (headless would otherwise skip it) the numbers run 3, 2, 1, GO!;
##     while it presses forward the player does not move, no bot moves / thinks, the sim clock stays 0;
##   - the fight starts on the GO! frame (that very tick steps the sim), then the player walks and the bots act;
##   - with the default flags in a headless run there is no countdown and the match starts on the first tick.
## Presentation only: it never touches MatchSim, so nothing here changes the simulation.

const FRAME := 1.0 / 60.0
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func frames(n: int) -> void:
	for i in n: await process_frame

## A World that only advances when the test calls tick() (like flow_test / perf_test).
func _world(force: bool) -> Node:
	var w: Node = load("res://world/world.tscn").instantiate()
	w.auto_run = false
	w.countdown_force = force
	w.bot_count = 3
	w.map_id = "arena"
	w.dyn_choice = "off"
	w.rng_seed = 7
	root.add_child(w)
	await frames(3)
	return w

func _run() -> void:
	await _forced_countdown()
	await _default_headless()
	print("COUNTDOWN %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _pos(f: FighterState) -> Vector3:
	var p: FighterPhysics = f.phys
	return Vector3(p.px, p.py, p.pz)

func _forced_countdown() -> void:
	var w: Node = await _world(true)
	# the bots we hold to their spawn positions while the countdown runs
	var bots: Array = []
	for f: FighterState in w.sim.fighters:
		if f != w.sim.player: bots.append([f, _pos(f)])
	check(w.countdown_number() == 3 and w.countdown_locked(), "forced countdown starts on 3 (n=%d)" % w.countdown_number())
	check(w._count_big.text == "3" and w._count_small.visible and w._count_small.text == "Get ready", "3 shows with the Get ready line")
	check(w._count_root.visible, "countdown overlay visible")
	var start: Vector3 = w.player_pos()
	w.input.state.set_move("script", Vector2(0.0, 1.0))       # hold forward through the whole countdown
	# step the locked countdown; every locked tick must leave the player, the bots and the sim clock alone
	var seq: Array = [w.countdown_number()]
	var player_still := true
	var bots_still := true
	var clock_still := true
	var think_still := true
	var guard := 0
	while w.countdown_number() > 0 and guard < 600:
		w.tick(FRAME)
		guard += 1
		var n: int = w.countdown_number()
		if n != seq[seq.size() - 1]: seq.append(n)
		if w.countdown_locked():
			if w.player_pos() != start: player_still = false
			for b: Array in bots:
				if _pos(b[0]) != b[1]: bots_still = false
			if w.sim.combat.time != 0.0: clock_still = false
			if w.sim.think_us != 0: think_still = false
	check(player_still, "player does not move while forward is held before GO")
	check(bots_still, "bots do not move before GO")
	check(clock_still and think_still, "sim clock / bot brains are frozen before GO (%s / %s)" % [w.sim.combat.time, w.sim.think_us])
	check(seq == [3, 2, 1, 0], "numbers are 3, 2, 1, GO! (%s)" % [seq])
	check(w._count_big.text == "GO!" and not w._count_small.visible, "GO! replaces the Get ready line")
	check(not w.countdown_locked(), "the lock is released on the GO! frame")
	# the GO! frame itself already stepped the sim: the fight starts exactly then
	check(w.sim.combat.time > 0.0, "sim starts on the GO! frame (t=%.4f)" % w.sim.combat.time)
	check(w.player_pos() != start, "player moves on the GO! frame")
	# presentation: GO! flashes gold and holds, then fades and the overlay goes away
	for i in 15: w.tick(FRAME)
	var fc: Color = w._count_big.get_theme_color("font_color")
	check(w.countdown_number() == 0 and absf(fc.g - UiTheme.ACCENT.g) < 0.02 and absf(fc.r - UiTheme.ACCENT.r) < 0.05, "GO! settles on the gold accent (%s)" % fc)
	var go_pos: Vector3 = w.player_pos()
	var bot_before: Array = []
	for b: Array in bots: bot_before.append(_pos(b[0]))
	for i in 90: w.tick(FRAME)
	check(w.countdown_number() == -1 and not w._count_root.visible, "countdown ends and the overlay hides")
	check(w.sim.combat.time > 1.0, "sim advances normally after GO (t=%.2f)" % w.sim.combat.time)
	check(Vector2(w.player_pos().x - go_pos.x, w.player_pos().z - go_pos.z).length() > 0.5, "player walks after GO")
	var moved := 0
	for i in bots.size():
		if _pos(bots[i][0]).distance_to(bot_before[i]) > 0.1: moved += 1
	check(moved > 0, "bots act after GO (%d of %d moved)" % [moved, bots.size()])
	check(w.sim.think_us > 0, "bot brains think after GO")
	w.input.state.set_move("script", Vector2.ZERO)
	w.queue_free()
	await frames(2)

func _default_headless() -> void:
	var w: Node = await _world(false)                       # headless, no countdown_force
	check(w.countdown_number() == -1 and not w.countdown_locked(), "headless default: no countdown (n=%d)" % w.countdown_number())
	check(not w._count_root.visible, "headless default: overlay hidden")
	var start: Vector3 = w.player_pos()
	w.input.state.set_move("script", Vector2(0.0, 1.0))
	w.tick(FRAME)
	check(w.sim.combat.time > 0.0, "headless default: match starts on the first tick (t=%.4f)" % w.sim.combat.time)
	for i in 15: w.tick(FRAME)
	check(Vector2(w.player_pos().x - start.x, w.player_pos().z - start.z).length() > 0.1, "headless default: player moves at once")
	check(w.sim.think_us > 0, "headless default: bots think at once")
	print("COUNTDOWN seq=[3, 2, 1, GO!] forced=yes headless-default=no")
	w.queue_free()
	await frames(2)
