extends SceneTree
## Every ported game mode played headless to the end (run by tools/test-modes.js after the parity test):
##   godot --headless --path godot --script res://tests/modes_test.gd -- --no-save [--only=<mode>]
## A scripted player (chases the nearest enemy, swings/shoots, kicks, dashes) and the mode's bots on one of the mode's
## maps. Checks that the match ends by the mode's rule (K.O. limit, team K.O. limit, last one standing, top of the
## Weapon Ladder), that the results panel shows after ModeRules.END_TIME, team colours, dashes in Ninja, the shrinking
## floor, finite state, and no node leaks.
## Godot-only modes (res://data/extra/modes.json): Team Deathmatch (a team reaches 30), Death Match (first to 20),
## Sudden Death (one life: K.O.s and falls eliminate, the player is pushed off and spectates until one stands) and Chaos
## (10 fighters, 5 v 5 to 50, random events that end cleanly; prints the step time).

const FRAME := 1.0 / 30.0           ## coarse frames: the sim still steps at 1/120
## [mode, map, K.O. limit (-1 = preset), hp, max simulated minutes]
const CASES := [
	["classic", "arena", 5, 100.0, 6.0],
	["melee", "park", 5, 100.0, 6.0],
	["guns", "gunrange", 5, 100.0, 6.0],
	["ninja", "temple", 5, 100.0, 6.0],
	["giant", "arena", 5, 100.0, 6.0],
	["duel", "arena", -1, 100.0, 8.0],
	["t2", "park", -1, 100.0, 8.0],
	["t3", "arena", -1, 100.0, 8.0],
	["t4", "temple", -1, 100.0, 10.0],
	["mega", "shrink", -1, 100.0, 8.0],
	["mega", "squeeze", -1, 100.0, 8.0],
	["gungame", "arena", -1, 60.0, 14.0],
	["tdm", "arena", -1, 50.0, 16.0],
	["deathmatch", "park", -1, 50.0, 16.0],
	["sudden", "arena", -1, 100.0, 8.0],
	["sudden", "shrink", -1, 100.0, 8.0],
	["chaos", "arenaxl", -1, 50.0, 20.0],
]

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _nearest(sim: MatchSim, me: FighterState) -> FighterState:
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in sim.fighters:
		if f == me or f.dead or sim.combat.is_friend(me, f): continue
		var d := Vector2(f.phys.px - me.phys.px, f.phys.pz - me.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.substr(7)
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for cs: Array in CASES:
		if only != "" and cs[0] != only: continue
		await _play(cs[0], cs[1], cs[2], cs[3], cs[4])
	await process_frame
	await process_frame
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("NODES before=%d after=%d orphans=%d" % [nodes0, nodes1, orphans])
	check(nodes1 <= nodes0, "no node leak (%d -> %d)" % [nodes0, nodes1])
	check(orphans == 0, "no orphan nodes (%d)" % orphans)
	print("MODES %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _play(mode: String, map: String, limit: int, hp: float, minutes: float) -> void:
	var t0 := Time.get_ticks_msec()
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = map
	world.mode_id = mode
	world.ko_limit = limit
	world.auto_run = false
	world.bot_count = 3
	world.player_class = "bruiser"
	world.rng_seed = 777
	world.hp_setting = hp
	world.dyn_choice = "wobble" if mode == "chaos" else "off"     # Chaos: a tile floor so the floor event can run
	root.add_child(world)
	var sim: MatchSim = world.sim
	var c := sim.combat
	var r := c.rules
	var p := sim.player
	var st: InputState = world.input.state
	var tag := "%s/%s" % [mode, map]
	check(c.mode_id == mode, "%s: mode set" % tag)
	if c.teams:
		check(sim.fighters.size() == c.teams * 2, "%s: %d fighters for teams of %d" % [tag, sim.fighters.size(), c.teams])
		var per := [0, 0]
		for f: FighterState in sim.fighters:
			per[f.team] += 1
			check(int(world.views[f].look["color"]) == ModeRules.TEAM_COL[f.team], "%s: %s wears the team colour" % [tag, f.name])
		check(per[0] == per[1], "%s: even teams %s" % [tag, per])
	if c.lives_mode:
		for f: FighterState in sim.fighters: check(f.lives == c.lives_mode, "%s: %s starts with %d lives" % [tag, f.name, c.lives_mode])
	if mode == "gungame":
		for f: FighterState in sim.fighters: check(f.weapon == ModeRules.GG[0], "%s: %s starts on the first rung (%s)" % [tag, f.name, f.weapon])
	if mode == "tdm": check(c.teams == 2 and sim.fighters.size() == 4, "%s: 2 v 2 from 3 bots (%d per side)" % [tag, c.teams])
	if mode == "chaos":
		check(sim.fighters.size() == 10 and c.teams == 5, "%s: 10 fighters, 5 v 5 (%d)" % [tag, sim.fighters.size()])
		check(not r.chaos.is_empty(), "%s: chaos events armed" % tag)
	var chaos_seq: Array = []
	var chaos_bad := 0
	var step_us := 0
	var steps := 0
	var spect_ok := false
	var spect_cycled := false
	var pushed := false
	var shrinks := not r.shrink.is_empty()
	check(shrinks == (map == "shrink" or map == "squeeze"), "%s: shrinking floor %s" % [tag, shrinks])
	var frames := int(minutes * 60.0 / FRAME)
	var nonfinite := 0
	var over_at := -1.0
	var min_size := 1e9
	var dashes := 0
	var i := 0
	while i < frames:
		var tg := _nearest(sim, p)
		var go := Vector2.ZERO
		var fire := false
		if tg != null and not p.dead:
			var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
			if shrinks and Vector2(p.phys.px, p.phys.pz).length() > sim.wander():     # stay on the floor that is left
				d = -Vector2(p.phys.px, p.phys.pz)
			world.cam.yaw = atan2(d.x, d.y)
			world.cam.pitch = -0.12
			var reach := 1.6 if c.wdata(p.weapon if p.weapon != "" else "spatula").get("type", "") == "melee" else 7.0
			go = Vector2(0, 1) if d.length() > reach else Vector2.ZERO
			fire = d.length() < reach + 1.5
			if i % 41 == 0: st.press("kick")
			if i % 67 == 0: st.press("spatula")
			if i % 90 == 0 and d.length() > 8.0: st.press("dash")
		st.set_move("script", go)
		st.hold("script", "fire", fire)
		st.hold("script", "jump", i % 87 < 2)
		var dn := 0
		for f: FighterState in sim.fighters: dn += f.dash_n
		if mode == "sudden" and not pushed and sim.elapsed() > 3.0 and not p.dead:   # off the edge: a fall eliminates too
			p.phys.place(60.0, -30.0, 0.0); p.last_attacker = null; pushed = true
		var us0 := Time.get_ticks_usec()
		world.tick(FRAME)
		step_us += Time.get_ticks_usec() - us0; steps += 1
		if mode == "chaos":
			var ch := r.chaos
			if int(world.counts.get("chaos_end", 0)) > chaos_seq.size(): chaos_seq.append(ch["last"])
			if ch["id"] == "" and not r.match_over:          # between events: the normal rules are back
				for f: FighterState in sim.fighters:
					if f.phys.grav_scale != c.grav_setting or f.big_t > 0.0: chaos_bad += 1
				if c.kb_setting != float(ch["kb0"]): chaos_bad += 1
		if mode == "sudden" and p.elim and not r.match_over:
			var sp: FighterState = world.spectating
			if sp != null and not sp.elim and sp != p: spect_ok = true
			if sp != null and not spect_cycled and r.survivors().size() >= 2:
				world.spectate_next()
				spect_cycled = world.spectating != sp and world.spectating != null and not world.spectating.elim
		var dn2 := 0
		for f: FighterState in sim.fighters: dn2 += f.dash_n
		if dn2 < dn: dashes += 1
		if shrinks: min_size = minf(min_size, float(r.shrink["size"]))
		for f: FighterState in sim.fighters:
			for v in [f.phys.px, f.phys.py, f.phys.pz, f.hp]:
				if not is_finite(v): nonfinite += 1
		if r.match_over and over_at < 0.0:
			over_at = sim.elapsed()
			frames = mini(frames, i + int((ModeRules.END_TIME + 0.5) / FRAME))
		i += 1
	var w := r.winner
	var kos := 0
	for f: FighterState in sim.fighters: kos += f.ko
	print("MATCH %-16s over=%s at=%.0fs winner=%s won=%s kos=%d player ko=%d deaths=%d dashes=%d %s(%.1fs real)" % [tag, r.match_over, over_at,
		w.name if w else "-", r.player_won(w), kos, p.ko, int(p.st["deaths"]), dashes, ("min_size=%.1f " % min_size) if shrinks else "",
		(Time.get_ticks_msec() - t0) / 1000.0])
	check(r.match_over and w != null, "%s: the match ended within %.0f simulated minutes" % [tag, minutes])
	check(world._results != null, "%s: results panel shown after the end" % tag)
	check(nonfinite == 0, "%s: state finite (%d bad)" % [tag, nonfinite])
	if w != null:
		if c.lives_mode:
			var alive := 0
			for f: FighterState in sim.fighters: if not f.elim: alive += 1
			check(not w.elim, "%s: the winner is still in" % tag)
			check(alive <= 1 or p.elim, "%s: last one standing or the player is out (%d left)" % [tag, alive])
		elif c.mode.get("ladder", false):
			check(w.gg_rung == ModeRules.GG.size() - 1 and w.ko >= ModeRules.GG.size(), "%s: the winner topped the ladder (rung %d, %d K.O.s)" % [tag, w.gg_rung, w.ko])
		elif c.teams:
			check(r.team_ko(w.team) >= r.limit, "%s: winning team reached %d (%d)" % [tag, r.limit, r.team_ko(w.team)])
			check(r.team_ko(1 - w.team) < r.limit, "%s: losing team below the limit" % tag)
		else:
			check(w.ko >= r.limit and r.limit > 0, "%s: winner reached %d K.O.s (%d)" % [tag, r.limit, w.ko])
	if mode == "ninja": check(dashes > 0, "%s: someone dashed" % tag)
	if mode == "sudden":
		check(pushed and p.elim and int(p.st["falls"]) >= 1, "%s: the player's fall eliminated them" % tag)
		check(spect_ok, "%s: the camera followed a survivor after the player was out" % tag)
		check(spect_cycled, "%s: tap switched the spectated fighter" % tag)
		check(world.touch.spectate_mode, "%s: touch layer in spectator mode" % tag)
		for f: FighterState in sim.fighters:
			if int(f.st["deaths"]) > 0: check(f.elim, "%s: %s was out after one death" % [tag, f.name])
			check(int(f.st["deaths"]) <= 1, "%s: %s died once at most (%d)" % [tag, f.name, int(f.st["deaths"])])
		var fell := 0
		for f: FighterState in sim.fighters: fell += int(f.st["falls"])
		print("SUDDEN %-14s eliminated=%d falls=%d spectating=%s" % [tag, sim.fighters.size() - r.survivors().size(), fell,
			world.spectating.name if world.spectating else "-"])
	if mode == "chaos":
		var ok_seq := true
		for k in range(1, chaos_seq.size()):
			if chaos_seq[k] == chaos_seq[k - 1]: ok_seq = false
		print("CHAOS %-15s events=%s warns=%d ms/step=%.3f (10 fighters, %d frames)" % [tag, chaos_seq, int(world.counts.get("chaos_warn", 0)),
			step_us / 1000.0 / maxf(1.0, steps * 4.0), steps])
		check(chaos_seq.size() >= 3, "%s: several chaos events ran (%d)" % [tag, chaos_seq.size()])
		check(ok_seq, "%s: no event twice in a row %s" % [tag, chaos_seq])
		check(chaos_bad == 0, "%s: rules restored between events (%d bad)" % [tag, chaos_bad])
		check(int(world.counts.get("chaos_warn", 0)) >= chaos_seq.size(), "%s: every event was announced" % tag)
	if shrinks: check(min_size < float(ModeRules.SHRINK[map]["S0"]) - 10.0, "%s: the floor shrank (min %.1f)" % [tag, min_size])
	world.queue_free()
	await process_frame
