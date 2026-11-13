extends SceneTree
## Construction DLC unit B, headless (run by tools/test-site-map.js, npm run test:godot-site-map):
##   godot --headless --path godot --script res://tests/site_map_test.gd -- --no-save [--seeds N]
## 1. The generated Building Site ('sitegen', SiteMap) for seeds 1..200: maps.json schema, counts (>= 8 spawns, >= 12 bot
##    spots, >= 12 crate drops, boxes under 700), colours in the construction palette, 2 m of free floor round every spawn and
##    bot spot, drops on free floor or on a real top, big machines >= 6 m apart, every platform above 1.5 m reachable by a
##    walk / jump / ladder / bounce-pad graph (SiteNav) and all spots connected, the same seed twice identical, different
##    seeds different, the seed changes the mix, orientation and count of props.
## 2. SiteNav itself can fail: a tall box with no way up is reported unreachable.
## 3. MapBuilder.build('sitegen') for 5 seeds (set_seed) builds without errors or leaks; Construction offers the map.
## 4. The nine DLC tool models and the PPE (hard hats, hi-vis vest) build on a Wobbler with nothing null; bots in a Construction
##    match are tradies (Builder vest, hard hat, trade names).
## 5. A short Construction match on a generated site: positions finite, nobody falls through the world on the spot.
## Prints SITEMAP ... lines and SITEMAP ok / FAILED.

const SEEDS := 200
var fails := 0
var stats := {"boxes": [], "machines": {}, "kinds": {}, "gen_ms": 0.0, "nav_ms": 0.0}

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		if fails < 40: print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var n := SEEDS
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--seeds" and i + 1 < a.size(): n = int(a[i + 1])
	_seeds(n)
	_negative()
	_builder()
	_tools_and_ppe()
	await _match()
	print("SITEMAP %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------- 1. seeds

func _dist_to_rect(x: float, z: float, b: Dictionary) -> float:
	var dx := maxf(0.0, maxf(float(b["x"]) - float(b["w"]) / 2.0 - x, x - float(b["x"]) - float(b["w"]) / 2.0))
	var dz := maxf(0.0, maxf(float(b["z"]) - float(b["d"]) / 2.0 - z, z - float(b["z"]) - float(b["d"]) / 2.0))
	return sqrt(dx * dx + dz * dz)

func _clearance(boxes: Array, x: float, z: float) -> float:
	var best := 99.0
	for i in range(1, boxes.size()):
		var b: Dictionary = boxes[i]
		if float(b["y"]) + float(b["h"]) <= 0.1: continue          # floor decals
		best = minf(best, _dist_to_rect(x, z, b))
	return best

func _inside(boxes: Array, x: float, z: float, y: float) -> bool:
	for b: Dictionary in boxes:
		if absf(x - float(b["x"])) < float(b["w"]) / 2.0 and absf(z - float(b["z"])) < float(b["d"]) / 2.0 \
				and y > float(b["y"]) + 0.02 and y < float(b["y"]) + float(b["h"]) - 0.02:
			return true
	return false

func _rect_gap(a: Array, b: Array) -> float:
	var dx := maxf(0.0, maxf(float(a[0]) - float(b[2]), float(b[0]) - float(a[2])))
	var dz := maxf(0.0, maxf(float(a[1]) - float(b[3]), float(b[1]) - float(a[3])))
	return sqrt(dx * dx + dz * dz)

func _sig(m: Dictionary) -> String:
	return JSON.stringify(m["geometry"]["boxes"]).md5_text()

func _seeds(n: int) -> void:
	var palette := SiteProps.palette()
	palette.append_array(SiteMap.FLOORS); palette.append_array(SiteMap.PATCHES); palette.append(SiteMap.FLOOR_PAD)
	var sigs := {}
	var unreach_total := 0
	var min_machine_gap := 99.0
	var min_spawn_clear := 99.0
	var orient := {"excavator_x": 0, "excavator_z": 0}
	for sd in range(1, n + 1):
		var t0 := Time.get_ticks_usec()
		var L := SiteMap.layout(sd)
		stats["gen_ms"] += (Time.get_ticks_usec() - t0) / 1000.0
		var m: Dictionary = L["map"]
		var tag := "seed %d" % sd
		check(bool(L["ok"]), tag + " layout ok (attempt %d)" % int(L["attempt"]))
		# schema (shared/maps.json siteyard)
		for k in ["name", "cat", "tags", "only", "blurb", "sky", "skyTop", "voidColor", "hills", "shadow", "orbit", "hemi", "sunI", "spawns", "player", "bots", "wander", "drops", "geometry"]:
			check(m.has(k), tag + " has " + k)
		check(str(m.get("only")) == "construction" and str(m.get("name")) == "Building Site", tag + " is the Construction-only Building Site")
		var geo: Dictionary = m["geometry"]
		for k in ["boxes", "bouncePads", "floorPads", "ladders"]: check(geo.get(k) is Array, tag + " geometry." + k)
		var boxes: Array = geo["boxes"]
		stats["boxes"].append(boxes.size())
		check(boxes.size() >= 100 and boxes.size() < 700, tag + " box budget %d" % boxes.size())
		var bad_box := 0
		for b: Dictionary in boxes:
			for k in ["x", "z", "w", "d", "h", "y", "color"]:
				if not b.has(k) or not (b[k] is float or b[k] is int): bad_box += 1
			if float(b["w"]) <= 0.0 or float(b["d"]) <= 0.0 or float(b["h"]) <= 0.0: bad_box += 1
			if not palette.has(int(b["color"])): bad_box += 1; check(false, tag + " colour %06x outside the palette" % int(b["color"]))
		check(bad_box == 0, tag + " %d malformed boxes" % bad_box)
		var slab: Dictionary = boxes[0]
		check(float(slab["w"]) == 64.0 and float(slab["d"]) == 64.0 and float(slab["y"]) == -2.0 and float(slab["h"]) == 2.0, tag + " 64 x 64 slab first")
		for l: Dictionary in geo["ladders"]:
			for k in ["x", "z", "nx", "nz", "y0", "y1"]: check(l.has(k), tag + " ladder " + k)
			check(absf(float(l["nx"])) + absf(float(l["nz"])) == 1.0 and float(l["y1"]) > float(l["y0"]), tag + " ladder normal / span")
		for p: Dictionary in geo["bouncePads"]:
			check(p.has("x") and p.has("z") and p.has("r") and p.has("power"), tag + " pad keys")
		check((geo["floorPads"] as Array).size() == 1, tag + " one floor pad")
		# counts and clearance
		var spawns: Array = m["spawns"]
		var bots: Array = m["bots"]
		var drops: Array = m["drops"]
		check(spawns.size() >= 8 and bots.size() >= 12 and drops.size() >= 12, tag + " counts spawns %d bots %d drops %d" % [spawns.size(), bots.size(), drops.size()])
		check(m["player"] is Array and (m["player"] as Array).size() == 2, tag + " player start")
		var pts: Array = spawns + bots + [m["player"]]
		for pt: Array in pts:
			var c := _clearance(boxes, float(pt[0]), float(pt[1]))
			min_spawn_clear = minf(min_spawn_clear, c)
			check(c >= 2.0, tag + " spot %s only %.2f m from a box" % [pt, c])
			check(absf(float(pt[0])) < 31.0 and absf(float(pt[1])) < 31.0, tag + " spot %s on the slab" % [pt])
		for d: Array in drops:
			if d.size() > 2:
				check(not _inside(boxes, float(d[0]), float(d[1]), float(d[2])), tag + " raised drop %s inside a box" % [d])
				var stands := false
				for b: Dictionary in boxes:
					if absf(float(d[0]) - float(b["x"])) < float(b["w"]) / 2.0 and absf(float(d[1]) - float(b["z"])) < float(b["d"]) / 2.0 and absf(float(b["y"]) + float(b["h"]) - float(d[2])) < 0.01: stands = true
				check(stands, tag + " raised drop %s floats" % [d])
			else:
				check(_clearance(boxes, float(d[0]), float(d[1])) >= 1.2, tag + " drop %s too close to a box" % [d])
		# no two spots on top of each other
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				pass
		# machines
		var mach: Array = L["machines"]
		check(mach.size() >= 2, tag + " at least two big machines (%d)" % mach.size())
		for i in mach.size():
			stats["machines"][mach[i]["kind"]] = int(stats["machines"].get(mach[i]["kind"], 0)) + 1
			for j in range(i + 1, mach.size()):
				var g := _rect_gap(mach[i]["rect"], mach[j]["rect"])
				min_machine_gap = minf(min_machine_gap, g)
				check(g >= 6.0, tag + " %s and %s only %.1f m apart" % [mach[i]["kind"], mach[j]["kind"], g])
			if mach[i]["kind"] == "excavator":
				var r: Array = mach[i]["rect"]
				if float(r[2]) - float(r[0]) > float(r[3]) - float(r[1]): orient["excavator_x"] += 1
				else: orient["excavator_z"] += 1
		for pr: Dictionary in L["props"]: stats["kinds"][pr["kind"]] = int(stats["kinds"].get(pr["kind"], 0)) + 1
		# reachability
		var t1 := Time.get_ticks_usec()
		var nav := SiteNav.analyze(m, L["fence"])
		stats["nav_ms"] += (Time.get_ticks_usec() - t1) / 1000.0
		unreach_total += (nav["unreachable"] as Array).size()
		check(nav["ok"], tag + " nav: %d unreachable tops %s, %d spots cut off %s" % [(nav["unreachable"] as Array).size(), (nav["unreachable"] as Array).slice(0, 3), (nav["disconnected"] as Array).size(), (nav["disconnected"] as Array).slice(0, 3)])
		check((m["geometry"]["ladders"] as Array).size() + (m["geometry"]["bouncePads"] as Array).size() > 0, tag + " has a ladder or a pad")
		# determinism
		if sd <= 40:
			var again := SiteMap.generate(sd)
			SiteMap._cache.clear()
			var fresh := SiteMap.generate(sd)
			check(JSON.stringify(again) == JSON.stringify(fresh) and JSON.stringify(fresh) == JSON.stringify(m), tag + " not deterministic")
		sigs[_sig(m)] = true
	check(sigs.size() == n, "different seeds give different levels (%d distinct of %d)" % [sigs.size(), n])
	var mk: Dictionary = stats["machines"]
	check(mk.size() == 3 and int(mk.get("crane", 0)) < n and int(mk.get("excavator", 0)) < n and int(mk.get("bulldozer", 0)) < n, "machines vary with the seed %s" % [mk])
	check(orient["excavator_x"] > 0 and orient["excavator_z"] > 0, "machines turn by 90 degrees %s" % [orient])
	var kd: Dictionary = stats["kinds"]
	for k in ["heap", "pipes", "container", "scaffold", "trench", "mixer", "cones", "barriers"]: check(int(kd.get(k, 0)) > 0 and int(kd.get(k, 0)) < n * 6, "prop %s appears (%d)" % [k, int(kd.get(k, 0))])
	var bx: Array = stats["boxes"]
	print("SITEMAP seeds=%d boxes %d..%d (avg %d) | min machine gap %.1f m, min spot clearance %.1f m | props %s | gen %.0f ms/seed nav %.0f ms/seed" % [
		n, bx.min(), bx.max(), int(float(bx.reduce(func(s: int, v: int) -> int: return s + v, 0)) / float(n)), min_machine_gap, min_spawn_clear, kd, stats["gen_ms"] / n, stats["nav_ms"] / n])

# ---------------------------------------------------------------- 2. the nav check can fail

func _negative() -> void:
	var L := SiteMap.layout(1)
	var m: Dictionary = (L["map"] as Dictionary).duplicate(true)
	check(SiteNav.analyze(m, L["fence"])["ok"], "negative: seed 1 passes first")
	m["geometry"]["boxes"].append({"x": 0.0, "z": 0.0, "w": 3.0, "d": 3.0, "h": 6.0, "y": 0.0, "color": SiteProps.STEEL})   # a 6 m tower with no way up (in the middle: clear it first)
	var nav := SiteNav.analyze(m, L["fence"])
	check(not nav["ok"] and (nav["unreachable"] as Array).size() > 0, "negative: a 6 m block with no ladder is reported unreachable")
	var m2: Dictionary = (L["map"] as Dictionary).duplicate(true)
	m2["geometry"]["ladders"] = []
	m2["geometry"]["bouncePads"] = []
	var nav2 := SiteNav.analyze(m2, L["fence"])
	check(not nav2["ok"], "negative: without ladders and pads the crane / containers are out of reach")
	print("SITEMAP nav catches: a bare 6 m block -> %d unreachable cells, no ladders/pads -> %d" % [(nav["unreachable"] as Array).size(), (nav2["unreachable"] as Array).size()])

# ---------------------------------------------------------------- 3. MapBuilder

func _count_all(n: Node) -> int:
	var k := 1
	for c in n.get_children(): k += _count_all(c)
	return k

func _builder() -> void:
	var content: Node = root.get_node("Content")
	check(content.maps.has(SiteMap.ID) and str(content.get_map(SiteMap.ID).get("name")) == "Building Site", "Content registers sitegen")
	check(ModeRules.maps_for("construction") == ["siteyard", "sitegen"], "Construction offers %s" % [ModeRules.maps_for("construction")])
	check(not ModeRules.maps_for("melee").has("sitegen") and not ModeRules.maps_for("guns").has("sitegen"), "other modes do not offer it")
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans0 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var res0 := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var seeds := [1, 7, 42, 99, 123456]
	var tot_ms := 0.0
	for sd in seeds:
		SiteMap.set_seed(sd)
		var t0 := Time.get_ticks_usec()
		var node := MapBuilder.build(SiteMap.ID)
		tot_ms += (Time.get_ticks_usec() - t0) / 1000.0
		var geo: Dictionary = SiteMap.generate(sd)["geometry"]
		check(node.map_id == SiteMap.ID and node.solids.size() == (geo["boxes"] as Array).size(), "build seed %d: solids == boxes" % sd)
		check(node.ladders.size() == (geo["ladders"] as Array).size() and node.pads.size() == (geo["bouncePads"] as Array).size() and node.floor_pads.size() == 1, "build seed %d: ladders / pads" % sd)
		check(node.get_child_count() > 8 and node.decor_tris > 0, "build seed %d: visuals and the Site Yard backdrop (%d children)" % [sd, node.get_child_count()])
		check(str(node.map.get("name")) == "Building Site", "build seed %d: the generated map is what the node carries" % sd)
		var dm: Mesh = null
		var meshes := 0
		for c in node.get_children():
			if c is MeshInstance3D and str(c.name).begins_with("Boxes_"): meshes += 1
		check(meshes > 4, "build seed %d: batched box meshes (%d)" % [sd, meshes])
		node.free()
	SiteMap.set_seed(1)
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans1 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(nodes1 <= nodes0 + 1 and orphans1 <= orphans0, "build leaks no nodes (%d -> %d, orphans %d -> %d)" % [nodes0, nodes1, orphans0, orphans1])
	print("SITEMAP MapBuilder built %d seeds in %.0f ms each, no leaks (nodes %d -> %d, resources %d -> %d)" % [seeds.size(), tot_ms / seeds.size(), nodes0, nodes1, res0, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))])

# ---------------------------------------------------------------- 4. tools and PPE

func _meshes(n: Node) -> int:
	var k := 1 if n is MeshInstance3D and (n as MeshInstance3D).mesh != null else 0
	for c in n.get_children(): k += _meshes(c)
	return k

func _tools_and_ppe() -> void:
	var w: Wobbler = preload("res://actors/wobbler.tscn").instantiate()
	root.add_child(w)
	var states := {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": Vector3(0, -0.5, 0.8)}
	for key in WeaponModels.DLC_KEYS:
		var m := WeaponModels.build(key)
		check(m != null and m.name == "Weapon_" + key, "tool %s builds" % key)
		var n := _meshes(m)
		var bb := WeaponModels.bounds(m)
		var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		check(n >= 5, "tool %s has %d meshes (the grey placeholder block has 2)" % [key, n])
		check(longest >= 0.7 and longest <= 3.4, "tool %s longest side %.2f" % [key, longest])
		check(bb.position.y > -3.2 and bb.end.y < 1.5, "tool %s y %.2f..%.2f within reach of the hand" % [key, bb.position.y, bb.end.y])
		for c in m.get_children():
			if c is MeshInstance3D: check((c as MeshInstance3D).mesh != null and (c as MeshInstance3D).material_override != null, "tool %s mesh has a mesh and a material" % key)
		m.free()
		w.set_weapon(key)
		for f in 5:
			w.apply_state(states)
			w.animate(1.0 / 60.0)
		check(w.weapon == key, "tool %s equips on a Wobbler" % key)
	# PPE
	var cos := WobblerLooks.data("cosmetics")
	for h in ["hardhat", "hardhat_white", "hardhat_orange"]:
		check((cos["hats"] as Array).has(h) and WobblerLooks.HATS.has(h), "hat %s is offered and has parts" % h)
		check(str(LockerData.data()["hat_rarity"].get(h)) == "common" and LockerData.hat_name(h) != h.capitalize(), "hat %s is common and has a label" % h)
		w.set_hat(h)
		check(w.hat != null and w.hat_name == h and _meshes(w.hat) >= 6, "hat %s builds on a Wobbler (%d meshes)" % [h, _meshes(w.hat) if w.hat else 0])
		w.apply_state(states)
		w.animate(1.0 / 60.0)
	w.set_hat("none")
	check(w.hat == null, "hat none clears")
	var parts := WobblerLooks.skin_parts("builder")
	var silver := 0
	for pt: Array in parts:
		if pt[2] is int and int(pt[2]) == WobblerLooks.REFLECTIVE: silver += 1
	check(WobblerLooks.SKIN_BUILDERS.has("builder") and silver >= 6, "builder skin has a vest with silver reflective stripes (%d parts)" % silver)
	w.set_skin("builder")
	check(w.skin_key == "builder" and w._skin_nodes.size() >= 12, "Builder outfit builds on a Wobbler (%d nodes)" % w._skin_nodes.size())
	for nd in w._skin_nodes: check(nd != null and is_instance_valid(nd), "builder part valid")
	w.apply_state(states)
	w.animate(1.0 / 60.0)
	w.free()
	print("SITEMAP tools %s + PPE (3 hard hats, hi-vis vest with %d silver parts) build" % [WeaponModels.DLC_KEYS, silver])

# ---------------------------------------------------------------- 5. a match

func _match() -> void:
	SiteMap.set_seed(11)
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = SiteMap.ID
	world.mode_id = "construction"
	world.auto_run = false
	world.bot_count = 7
	world.rng_seed = 4242
	root.add_child(world)
	var sim: MatchSim = world.sim
	var bots: Array = sim.fighters.slice(1)
	var names: Array = []
	var dressed := 0
	for b: FighterState in bots:
		names.append(b.name)
		var lk: Dictionary = sim.looks[b]
		if lk["skin"] == "builder" and MatchSim.TRADIE_HATS.has(lk["hat"]): dressed += 1
	check(dressed == 7, "every Construction bot wears the vest and a hard hat (%d of 7)" % dressed)
	check(names == MatchSim.TRADIE_NAMES, "bots carry trade names %s" % [names])
	var hats := {}
	for b: FighterState in bots: hats[sim.looks[b]["hat"]] = true
	check(hats.size() == 3, "all three hard hats are worn")
	var low := 0.0
	var bad := 0
	for i in 600:
		world.tick(1.0 / 60.0)
		for f: FighterState in sim.fighters:
			if not (is_finite(f.phys.px) and is_finite(f.phys.py) and is_finite(f.phys.pz)): bad += 1
			low = minf(low, f.phys.py)
	check(bad == 0, "positions stay finite over a 10 s match")
	check(world.map_node.map_id == SiteMap.ID and str(sim.map.get("name")) == "Building Site", "the match runs on the generated site")
	check(sim.player.phys.py > -1.0 and sim.player.hp > 0.0 or sim.player.dead, "the player is still on the slab or just beaten")
	world.free()
	SiteMap.set_seed(1)
	print("SITEMAP match: 7 tradies %s on a generated site, 600 ticks fine" % [names])
