extends SceneTree
## Construction mode offline, headless (run by tools/test-construction.js, npm run test:godot-construction):
##   godot --headless --path godot --script res://tests/construction_test.gd -- --no-save
## 1. Title: the Mode picker lists Classic and Construction; Construction offers only Site Yard, Classic arena/practice.
## 2. Site Yard builds (solids = boxes, 2 bounce pads, no ladders); dynamic floors resolve like the web (drift only).
## 3. Crates in Construction only ever hold what the mode allows (heal, hammer, Live Wire, Air Blower, power-ups).
## 4. A 30 s match on Site Yard in Construction: everyone starts with the Claw Hammer, bots swing it, the scripted
##    player hammers, then picks up an Air Blower and blows a bot away (push, stun, blame, ammo drain), K.O.s happen,
##    HP stays in range, positions finite, no node leaks.

const FRAME := 1.0 / 60.0
const SECONDS := 30.0
const ALLOW := ["heal", "hammer", "wirewhip", "blower", "speed", "rage", "shield"]

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
		if f == me or f.dead: continue
		var d := Vector2(f.phys.px - me.phys.px, f.phys.pz - me.phys.pz).length()
		if d < bd: bd = d; best = f
	return best

func _run() -> void:
	await _title()
	_map()
	_crates()
	await _match()
	print("CONSTRUCTION %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _title() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await process_frame
	var w = main.wizard   # the setup wizard (ui/setup_wizard.gd): game type page lists the modes
	var names: Array = []
	for m: String in w.modes(): names.append(w.mode_name(m))
	check(names.has("Classic") and names.has("Construction"), "wizard modes %s" % [names])
	check(w.maps_for("classic").has("arena") and w.maps_for("classic").has("practice") and not w.maps_for("classic").has("siteyard"), "classic maps %s" % [w.maps_for("classic")])
	check(w.maps_for("construction") == ["siteyard"], "construction maps %s" % [w.maps_for("construction")])
	w.set_map("arena")
	w.set_mode("construction")
	check(w._map_bs.size() == 1 and w._map_bs.has("siteyard") and w.map_id == "siteyard", "Construction lists only Site Yard")
	check(str(root.get_node("Settings").get_value("mode")) == "construction", "mode saved in Settings")
	w.set_mode("classic")
	check(w._map_bs.has("arena") and w._map_bs.has("practice") and w.map_id == "arena", "Classic lists arena + practice again")
	print("TITLE modes=%s" % [names])
	vp.queue_free()
	await process_frame

func _map() -> void:
	var m := MapBuilder.build("siteyard")
	var geo: Dictionary = m.map["geometry"]
	check(m.solids.size() == geo["boxes"].size(), "siteyard solids %d == boxes %d" % [m.solids.size(), geo["boxes"].size()])
	check(m.pads.size() == 2 and m.ladders.is_empty(), "siteyard 2 bounce pads, no ladders")
	check(str(m.map.get("only", "")) == "construction", "siteyard is Construction only")
	var kinds := {}
	for k: String in Dynamics.KINDS:
		var d := ArenaDyn.new()
		var solids := FighterPhysics.solids_from_map(m.map)
		d.setup("siteyard", m.map, solids, m.ladders, m.pads, k, 1234)
		kinds[k] = d.kind
		# same as the web (node tools/test-dynamics.js --table): the hazard stripes anchor the floor, so no tile kinds; drift moves 2 blocks
		var want: String = {"off": "off", "random": "drift", "wobble": "off", "tilt": "off", "quake": "off", "drift": "drift"}[k]
		check(d.kind == want, "siteyard dyn %s -> %s (got %s)" % [k, want, d.kind])
	print("MAP siteyard solids=%d pads=%d dyn=%s" % [m.solids.size(), m.pads.size(), kinds])
	m.free()

func _crates() -> void:
	var sim := MatchSim.new()
	sim.combat.set_mode("construction")
	sim.combat.rng = CombatRng.new(99)
	var seen := {}
	for i in 3000:
		var k := sim.pickups.pick_crate_key()
		seen[k] = int(seen.get(k, 0)) + 1
		check(ALLOW.has(k), "crate key %s allowed in Construction" % k)
		if not ALLOW.has(k): break
	for k in ["hammer", "wirewhip", "blower", "heal"]:
		check(seen.has(k), "Construction crates include %s" % k)
	print("CRATES %s" % [seen])
	sim.dispose()

func _match() -> void:
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = "siteyard"
	world.mode_id = "construction"
	world.auto_run = false
	world.bot_count = 3
	world.rng_seed = 777
	world.hp_setting = 100.0
	root.add_child(world)
	var sim: MatchSim = world.sim
	var p := sim.player
	var st: InputState = world.input.state
	check(sim.combat.mode_id == "construction", "world runs Construction")
	for f: FighterState in sim.fighters:
		check(f.weapon == "hammer", "%s starts with the Claw Hammer (%s)" % [f.name, f.weapon])
	sim.pickups.crate_rate = "often"
	var frames := int(round(SECONDS / FRAME))
	var nonfinite := 0
	var hp_bad := 0
	var crate_keys := {}
	var bot_swings := 0
	var blow_start := -1.0
	var blow_target: FighterState = null
	var blow_push := 0.0
	var blow_stunned := false
	var ammo0 := 0.0
	var ammo1 := 0.0
	for i in frames:
		var t := i * FRAME
		if t >= 18.0 and blow_start < 0.0 and not p.dead:      # an Air Blower from a crate, straight into the hand
			sim.combat.pickup(p, "blower")
			for s in 3:
				if p.slots[s] != null and p.slots[s]["key"] == "blower": sim.combat.equip_slot(p, s)
			blow_start = t
			ammo0 = float(p.current_slot()["ammo"]) if p.current_slot() != null else 0.0
		var tg := _nearest(sim, p)
		var go := Vector2.ZERO
		var fire := false
		if tg != null:
			var d := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
			world.cam.yaw = atan2(d.x, d.y)
			world.cam.pitch = -0.1
			if p.weapon == "blower":
				go = Vector2(0, 1) if d.length() > 4.0 else Vector2.ZERO
				fire = d.length() < 7.0
				if fire and blow_target == null: blow_target = tg
			else:
				go = Vector2(0, 1) if d.length() > 1.6 else Vector2.ZERO
				fire = d.length() < 2.6
			if i % 131 == 0: st.press("kick")
		st.set_move("script", go)
		st.hold("script", "fire", fire)
		st.hold("script", "jump", i % 197 < 3)
		var tv := Vector2.ZERO
		if blow_target != null: tv = Vector2(blow_target.phys.vx, blow_target.phys.vz)
		world.tick(FRAME)
		if p.weapon == "blower" and fire and blow_target != null and not blow_target.dead:
			var pd := Vector2(blow_target.phys.px - p.phys.px, blow_target.phys.pz - p.phys.pz).normalized()
			blow_push = maxf(blow_push, (Vector2(blow_target.phys.vx, blow_target.phys.vz) - tv).dot(pd))
			if blow_target.stun > 0.0 and blow_target.last_attacker == p: blow_stunned = true
			if p.current_slot() != null: ammo1 = float(p.current_slot()["ammo"])
		for f: FighterState in sim.fighters:
			if not f.is_player and f.swing >= 0.0 and f.weapon == "hammer": bot_swings += 1
			for v in [f.phys.px, f.phys.py, f.phys.pz, f.phys.vx, f.phys.vy, f.phys.vz, f.hp]:
				if not is_finite(v): nonfinite += 1
			if not f.dead and (f.hp < 0.0 or f.hp > sim.combat.max_hp(f) + 1e-6): hp_bad += 1
		for c: Dictionary in sim.pickups.list: crate_keys[c["key"]] = true
	var kos := 0
	for f: FighterState in sim.fighters: kos += f.ko + int(f.st["falls"])
	var cnt: Dictionary = world.counts
	print("MATCH t=%.1fs kos+falls=%d hits=%d crates=%d keys=%s bot_hammer_frames=%d blow_push=%.3f stunned=%s ammo %.1f->%.1f dyn=%s" % [sim.elapsed(), kos,
		int(cnt.get("hit", 0)), int(cnt.get("crate", 0)), crate_keys.keys(), bot_swings, blow_push, blow_stunned, ammo0, ammo1, sim.dyn.kind])
	for f: FighterState in sim.fighters:
		print("FIGHTER %-12s %-8s ko=%d deaths=%d hits=%d dmg=%.0f hp=%.0f weapon=%s" % [f.name, f.class_id, f.ko, int(f.st["deaths"]), int(f.st["hits"]), float(f.st["dmg"]), f.hp, f.weapon])
	for k: String in crate_keys: check(ALLOW.has(k), "match crate %s allowed" % k)
	check(int(cnt.get("crate", 0)) >= 2, "crates drop (%d)" % int(cnt.get("crate", 0)))
	check(bot_swings > 0, "bots swing the hammer")
	check(int(cnt.get("hit", 0)) > 5, "hits land (%d)" % int(cnt.get("hit", 0)))
	check(kos >= 1, "K.O.s or ring-outs happen (%d)" % kos)
	check(blow_start > 0.0, "player got the Air Blower")
	check(blow_push > 0.01, "the blower pushes its target away (%.3f)" % blow_push)
	check(blow_stunned, "the blower stuns and is blamed")
	check(ammo1 < ammo0, "the blower drains ammo (%.1f -> %.1f)" % [ammo0, ammo1])
	check(nonfinite == 0, "positions finite (%d bad)" % nonfinite)
	check(hp_bad == 0, "HP within [0, max] (%d bad)" % hp_bad)
	world.queue_free()
	await process_frame
	await process_frame
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("NODES before=%d after=%d orphans=%d" % [nodes0, nodes1, orphans])
	check(nodes1 <= nodes0, "no node leak (%d -> %d)" % [nodes0, nodes1])
	check(orphans == 0, "no orphan nodes (%d)" % orphans)
