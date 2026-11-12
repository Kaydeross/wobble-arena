extends SceneTree
## Offline vertical slice, headless (run by tools/test-integration.js):
##   godot --headless --path godot --script res://tests/integration_test.gd -- --no-save
## A 30 s match on 'arena': the player (scripted through the same InputState the keyboard/touch write into, camera
## turned toward the nearest enemy) and 3 bots. The player brawls with the spatula, a forced SMG crate drops and the
## player walks to it, then shoots. Checks: K.O.s happen, the dead respawn, HP stays in [0, max] while alive,
## positions stay finite, the crate is picked up and the SMG fires and hits, no nodes leak when the world is freed.

const FRAME := 1.0 / 60.0
const SECONDS := 30.0

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _nearest(world: Node, me: FighterState) -> FighterState:
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in world.sim.fighters:
		if f == me or f.dead: continue
		var d := Vector2(f.phys.px - me.phys.px, f.phys.pz - me.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

func _run() -> void:
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = "arena"
	world.auto_run = false
	world.bot_count = 3
	world.player_class = "bruiser"
	world.rng_seed = 4242
	world.hp_setting = 100.0         # short lives: more K.O.s in 30 s
	root.add_child(world)
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	check(sim.fighters.size() == 4, "4 fighters (player + 3 bots)")
	check(p.class_id == "bruiser" and is_equal_approx(sim.combat.max_hp(p), 100.0 * float(sim.combat.classes["bruiser"]["hp"])), "player class bruiser, max hp from classes.json")
	var classes := {}
	for f: FighterState in sim.fighters: classes[f.class_id] = true
	check(classes.size() >= 3, "bots get class variety (%s)" % [classes.keys()])

	var frames := int(round(SECONDS / FRAME))
	var was_dead := {}
	var respawned := 0
	var max_hp_bad := 0
	var nonfinite := 0
	var smg_crate := {}
	var got_smg_at := -1.0
	var smg_hits_before := 0
	var max_fx := 0
	for i in frames:
		var t := i * FRAME
		var tg := _nearest(world, p)
		var go := Vector2.ZERO
		var fire := false
		if t >= 8.0 and smg_crate.is_empty() and got_smg_at < 0.0:
			smg_crate = sim.pickups.spawn_drop("smg")
			check(not smg_crate.is_empty(), "forced SMG crate spawned")
		if got_smg_at < 0.0 and not smg_crate.is_empty():     # walk to the crate
			var c := Vector2(smg_crate["x"] - p.phys.px, smg_crate["z"] - p.phys.pz)
			world.cam.yaw = atan2(c.x, c.y)
			go = Vector2(0, 1)
			if p.weapon == "smg": got_smg_at = t; smg_hits_before = int(p.st["hits"])
		elif tg != null:
			var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
			world.cam.yaw = atan2(d.x, d.y)
			world.cam.pitch = -0.12
			var reach := 1.6 if sim.combat.wdata(p.weapon if p.weapon != "" else "spatula").get("type", "") == "melee" else 6.0
			go = Vector2(0, 1) if d.length() > reach else Vector2.ZERO
			fire = d.length() < reach + 1.0
			if i % 97 == 0: st.press("kick")
			if i % 151 == 0: st.press("shove")
		st.set_move("script", go)
		st.hold("script", "fire", fire)
		st.hold("script", "jump", i % 173 < 3)
		world.tick(FRAME)
		max_fx = maxi(max_fx, world.fx.live_count() if world.fx else 0)
		for f: FighterState in sim.fighters:
			var ph := f.phys
			for v in [ph.px, ph.py, ph.pz, ph.vx, ph.vy, ph.vz, f.hp]:
				if not is_finite(v): nonfinite += 1
			if not f.dead and (f.hp < 0.0 or f.hp > sim.combat.max_hp(f) + 1e-6): max_hp_bad += 1
			if f.dead: was_dead[f] = true
			elif was_dead.has(f):
				was_dead.erase(f); respawned += 1
	var kos := 0
	var deaths := 0
	for f: FighterState in sim.fighters:
		kos += f.ko; deaths += int(f.st["deaths"])
	var cnt: Dictionary = world.counts
	print("MATCH t=%.1fs kos=%d deaths=%d respawned=%d player_ko=%d player_deaths=%d shots=%d crates=%d taken=%d hits=%d max_fx=%d" % [sim.elapsed(), kos, deaths, respawned,
		p.ko, int(p.st["deaths"]), int(cnt.get("shot", 0)), int(cnt.get("crate", 0)), int(cnt.get("crate_take", 0)), int(cnt.get("hit", 0)), max_fx])
	for f: FighterState in sim.fighters:
		print("FIGHTER %-12s %-8s ko=%d deaths=%d hits=%d dmg=%.0f taken=%.0f hp=%.0f weapon=%s" % [f.name, f.class_id, f.ko, int(f.st["deaths"]), int(f.st["hits"]), float(f.st["dmg"]), float(f.st["taken"]), f.hp, f.weapon])
	check(absf(sim.elapsed() - SECONDS) < 0.02, "simulated %.2f s" % sim.elapsed())
	check(kos >= 1 and deaths >= 1, "K.O.s happen (kos %d deaths %d)" % [kos, deaths])
	check(respawned >= 1, "a K.O.'d fighter respawned (%d)" % respawned)
	check(max_hp_bad == 0, "HP within [0, max] while alive (%d bad samples)" % max_hp_bad)
	check(nonfinite == 0, "positions finite (%d bad)" % nonfinite)
	check(got_smg_at > 0.0, "player picked up the SMG crate")
	check(int(cnt.get("shot", 0)) > 0, "SMG fired")
	check(int(p.st["hits"]) > smg_hits_before, "SMG hit something (%d -> %d)" % [smg_hits_before, int(p.st["hits"])])
	check(int(cnt.get("crate", 0)) >= 2, "crates drop by themselves too (%d)" % int(cnt.get("crate", 0)))
	check(int(cnt.get("hit", 0)) > 10, "hits land (%d)" % int(cnt.get("hit", 0)))
	check(max_fx < 400, "effects are cleaned up (max %d live)" % max_fx)
	for f: FighterState in sim.fighters:
		var v: Fighter = world.views[f]
		check(is_finite(v.wobbler.rig.position.y) and is_finite(v.wobbler.arm_dir.x), "%s pose finite" % f.name)

	world.queue_free()
	await process_frame
	await process_frame
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("NODES before=%d after=%d orphans=%d" % [nodes0, nodes1, orphans])
	check(nodes1 <= nodes0, "no node leak (%d -> %d)" % [nodes0, nodes1])
	check(orphans == 0, "no orphan nodes (%d)" % orphans)
	print("INTEGRATION %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)
