extends SceneTree
## Headless winner podium test (world/winner_podium.gd + world.gd, run by tools/test-podium.js):
##   godot --headless --path godot --script res://tests/podium_test.gd -- --no-save
## The results moment builds a real 3D podium: every fighter gets a place, ordered by the results' own ranking (the
## match winner first, then K.O.s then damage dealt), with the winning team first in team modes; the winners stand on
## the raised platform / steps and play the victory emote (Wobbler.play_emote), the rest stand beside the podium; the
## results camera eases onto a framing shot of it with the arena behind; the results panel still shows. The podium is
## skipped in tutorial / trial / sandbox and in headless runs (the suites opt in with `podium_in_tests`). No node leaks.

const FRAME := 1.0 / 60.0

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PODIUM ok   " if ok else "FAIL ") + what)
	if not ok: fails += 1

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

## A hand-stepped world (auto_run = false) that draws no podium unless the test opts in, like the other suites.
func _world(mode := "classic", map := "arena") -> Node:
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = map
	w.auto_run = false
	w.bot_count = 3
	w.dyn_choice = "off"
	w.mode_id = mode
	w.rng_seed = 11
	w.podium_in_tests = true
	root.add_child(w)
	return w

func _labels(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label: out.append(c)
		_labels(c, out)

func _run() -> void:
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var worlds: Array = []
	# ---- 1. Free for all: the ranking, a place for every fighter, emotes for the winner only, the camera, the panel
	var w := _world()
	worlds.append(w)
	var sim = w.sim
	var p = sim.player
	var bots: Array = []
	for f in sim.fighters:
		if f != p: bots.append(f)
	p.ko = 2; p.st["dmg"] = 500.0
	bots[0].ko = 5; bots[0].st["dmg"] = 100.0
	bots[1].ko = 2; bots[1].st["dmg"] = 300.0
	bots[2].ko = 0; bots[2].st["dmg"] = 50.0
	sim.combat.rules.winner = bots[0]
	check(w.podium_enabled(), "the podium is enabled for a normal offline result (the test opts in)")
	w._show_offline_results(true, "")
	var pod = w.podium
	check(pod != null, "the podium is built with the results panel")
	check(w._results != null, "the results panel still shows")
	var labels: Array = []
	_labels(w._results, labels)
	var has_title := false
	for l: Label in labels:
		if l.text == "You win!": has_title = true
	check(has_title, "the results panel's title is unchanged")
	if pod == null:
		print("PODIUM FAILED (no podium)")
		quit(1)
		return
	check(pod.standings.size() == sim.fighters.size(), "every fighter has a place (%d/%d)" % [pod.standings.size(), sim.fighters.size()])
	check(pod.slots.size() == sim.fighters.size(), "one podium Wobbler per fighter")
	check(pod.standings[0] == bots[0] and pod.standings[1] == p and pod.standings[2] == bots[1] and pod.standings[3] == bots[2],
		"winner order = winner, then K.O.s, then damage dealt")
	check(pod.winner_count == 1 and pod.emote_requests.size() == 1 and pod.emote_requests[0] == bots[0],
		"only the winner is asked to play the victory emote")
	var by_f := {}
	for s: Dictionary in pod.slots: by_f[s["f"]] = s
	check(by_f[bots[0]]["place"] == 1 and is_equal_approx(by_f[bots[0]]["pos"].y, pod.base.y + pod.WINNER_TOP),
		"the winner stands on the raised platform")
	check(by_f[p]["place"] == 2 and is_equal_approx(by_f[p]["pos"].y, pod.base.y + pod.SECOND_TOP),
		"2nd stands on the second step")
	check(by_f[bots[1]]["place"] == 3 and is_equal_approx(by_f[bots[1]]["pos"].y, pod.base.y + pod.THIRD_TOP),
		"3rd stands on the third step")
	check(by_f[bots[2]]["place"] == 4 and is_equal_approx(by_f[bots[2]]["pos"].y, pod.base.y),
		"the rest stand beside the podium on the floor")
	check(by_f[bots[0]]["wob"].is_emoting() and not by_f[bots[2]]["wob"].is_emoting(),
		"the winner emotes and the loser does not")
	for i in 90: w.tick(FRAME)
	var shot: Dictionary = pod.camera_shot()
	var off: float = w.cam.global_position.distance_to(shot["pos"])
	check(off < 0.35, "the camera eases onto the podium framing (%.2f m off)" % off)
	var fwd: Vector3 = -w.cam.global_transform.basis.z
	var want: Vector3 = (shot["look"] - w.cam.global_position).normalized()
	check(fwd.dot(want) > 0.995, "the camera looks at the podium")

	# ---- 2. The match winner is 1st even when a bot has more K.O.s (the rules' winner, not a new ranking)
	var w2 := _world()
	worlds.append(w2)
	w2.sim.player.ko = 1; w2.sim.player.st["dmg"] = 1.0
	for f in w2.sim.fighters:
		if f != w2.sim.player: f.ko = 9
	w2.sim.combat.rules.winner = w2.sim.player
	w2._show_offline_results(true, "")
	check(w2.podium != null and w2.podium.standings[0] == w2.sim.player, "the match winner is 1st even behind on K.O.s")

	# ---- 2b. The Godot-hosted online result path (`_show_results`) builds it the same way
	var n := _world()
	worlds.append(n)
	n.sim.combat.rules.winner = n.sim.player
	n._show_results("You")
	check(n.podium != null and n.podium.standings[0] == n.sim.player and n.podium.slots.size() == n.sim.fighters.size(),
		"the online (host) results path builds the podium too")

	# ---- 3. Team result: the whole winning team on the top platform, the other team beside it (even behind on K.O.s)
	var t := _world("tdm")
	worlds.append(t)
	var ts = t.sim
	var team0: Array = []
	var team1: Array = []
	for f in ts.fighters:
		if f.team == 0: team0.append(f)
		else: team1.append(f)
	check(ts.combat.teams == 2 and team0.size() == 2 and team1.size() == 2, "a 2 v 2 team match")
	for f in team0: f.ko = 1; f.st["dmg"] = 10.0
	for f in team1: f.ko = 9; f.st["dmg"] = 900.0
	ts.combat.rules.winner = team0[0]
	t._show_offline_results(true, "")
	var tp = t.podium
	check(tp != null and tp.team_mode, "a team result builds a team podium")
	if tp != null:
		check(tp.winner_count == team0.size() and tp.emote_requests.size() == team0.size(),
			"the whole winning team is asked to emote (%d)" % tp.emote_requests.size())
		check(tp.standings[0].team == 0 and tp.standings[1].team == 0 and tp.standings[2].team == 1 and tp.standings[3].team == 1,
			"the winning team comes first in the podium order")
		var team_wobs := {}
		for s: Dictionary in tp.slots: team_wobs[s["f"]] = s
		var top_ok := true
		var beside_ok := true
		var losers_quiet := true
		for f in team0:
			if not is_equal_approx(team_wobs[f]["pos"].y, tp.base.y + tp.WINNER_TOP): top_ok = false
			if not tp.emote_requests.has(f): top_ok = false
		for f in team1:
			if not is_equal_approx(team_wobs[f]["pos"].y, tp.base.y): beside_ok = false
			if team_wobs[f]["wob"].is_emoting() or tp.emote_requests.has(f): losers_quiet = false
		check(top_ok, "every winner stands on the top platform and emotes")
		check(beside_ok, "the losing team stands beside the podium")
		check(losers_quiet, "the losing team is not asked to emote")

	# ---- 4. Skipped where there is no result celebration, and in headless runs without the test seam
	var h := _world()
	worlds.append(h)
	h.podium_in_tests = false
	h._show_offline_results(true, "")
	check(h.podium == null and not h.podium_enabled(), "a headless run without the test seam skips the podium")
	for flag in ["tutorial", "trial", "build_mode"]:
		var s := _world()
		worlds.append(s)
		s.set(flag, true)
		s._show_offline_results(true, "")
		check(s.podium == null and not s.podium_enabled(), "%s skips the podium" % flag)
	var sb := _world("sandbox", "custom")
	worlds.append(sb)
	sb._show_offline_results(true, "")
	check(sb.podium == null and not sb.podium_enabled(), "the Sandbox arena skips the podium")

	# ---- 5. No node leaks: every world and its podium/Wobblers go away with the match
	for x: Node in worlds: x.queue_free()
	await process_frame
	await process_frame
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("NODES before=%d after=%d orphans=%d" % [nodes0, nodes1, orphans])
	check(nodes1 <= nodes0, "no node leak (%d -> %d)" % [nodes0, nodes1])
	check(orphans == 0, "no orphan nodes (%d)" % orphans)
	print("PODIUM %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)
