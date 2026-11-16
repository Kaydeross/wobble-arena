extends SceneTree
## DLC packs phase C, headless (run by tools/test-pack-maps.js, npm run test:godot-pack-maps):
##   godot --headless --path godot --script res://tests/pack_maps_test.gd -- --no-save [--seeds N]
## 1. The three procedural arenas (kitchen_chaos, toy_workshop, backyard_bbq) for seeds 1..N (default 8): the maps.json schema,
##    box count <= 450 (never above 690), palette, every spawn / bot / player point on walkable floor 2 m from any box and off every
##    hazard, SiteNav's 1 m grid flood fill reaches every spawn from every other and every ground crate spot, every platform above
##    1.5 m reachable (walk / jump / ladder / bounce pad), pads present, each arena's own hazard (burner / ice / hoist), the same seed
##    twice identical and different seeds different.
## 2. Registration: Content has the maps (`only` = the pack id) and no ordinary mode lists them; MapBuilder.build for 3 seeds.
## 3. PackZones: burner sets a fighter alight, the hoist knocks one (and a jump clears it), ice steering ONLY inside the zone and ONLY
##    under the balance overlay (a classic-rule match has no overlay at all), an ordinary arena has none.
## 4. A 20 s bot match per arena (a World): finite positions, nobody falls through the floor, with the pack's stage events running.
## 5. Each stage event id (dinner_rush, ingredient_drop, ice_zone, gift_barrage, hoist_sweep, sausage_sizzle) runs a few simulated
##    seconds and cleans up; an unknown event id is ignored.
## Prints PACKMAPS ... lines and PACKMAPS ok / FAILED.

const SEEDS := 8
const IDS := ["kitchen_chaos", "toy_workshop", "backyard_bbq"]
const PACKS := {"kitchen_chaos": "kitchen", "toy_workshop": "xmas", "backyard_bbq": "australia"}
const NAMES := {"kitchen_chaos": "Kitchen Chaos", "toy_workshop": "Toy Workshop", "backyard_bbq": "Backyard BBQ"}
const EVENTS := {"kitchen_chaos": ["dinner_rush", "ingredient_drop"], "toy_workshop": ["ice_zone", "gift_barrage"], "backyard_bbq": ["hoist_sweep", "sausage_sizzle"]}

var fails := 0
var AM: GDScript                       # loaded in _run: these scripts name the Content autoload
var SE: GDScript
var QP: GDScript
var counts := {}                       # id -> [box counts per seed]
var nav_ms := 0.0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		if fails < 60: print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	AM = load("res://dlc/construction/arcade_manager.gd")
	SE = load("res://dlc/construction/stage_events.gd")
	QP = load("res://logic/quick_play.gd")
	var n := SEEDS
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--seeds" and i + 1 < a.size(): n = int(a[i + 1])
	for id: String in IDS: _seeds(id, n)
	_registration()
	_zones()
	await _matches()
	_events_logic()
	for id: String in IDS:
		var c: Array = counts[id]
		print("PACKMAPS boxes %s seeds 1..%d: min %d max %d, seeds 1..8 %s" % [id, n, c.min(), c.max(), c.slice(0, 8)])
	print("PACKMAPS nav %.0f ms for %d maps" % [nav_ms, n * IDS.size()])
	print("PACKMAPS %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------- helpers

func _dist_to_box(x: float, z: float, b: Dictionary) -> float:
	var dx := maxf(0.0, maxf(float(b["x"]) - float(b["w"]) / 2.0 - x, x - float(b["x"]) - float(b["w"]) / 2.0))
	var dz := maxf(0.0, maxf(float(b["z"]) - float(b["d"]) / 2.0 - z, z - float(b["z"]) - float(b["d"]) / 2.0))
	return sqrt(dx * dx + dz * dz)

func _clearance(boxes: Array, x: float, z: float) -> float:
	var best := 99.0
	for i in range(1, boxes.size()):
		var b: Dictionary = boxes[i]
		if float(b["y"]) + float(b["h"]) <= 0.1: continue          # floor decals
		best = minf(best, _dist_to_box(x, z, b))
	return best

func _inside(boxes: Array, x: float, z: float, y: float) -> bool:
	for b: Dictionary in boxes:
		if absf(x - float(b["x"])) < float(b["w"]) / 2.0 and absf(z - float(b["z"])) < float(b["d"]) / 2.0 \
				and y > float(b["y"]) + 0.02 and y < float(b["y"]) + float(b["h"]) - 0.02:
			return true
	return false

func _sig(m: Dictionary) -> String:
	return JSON.stringify([m["geometry"]["boxes"], m["zones"], m["spawns"]]).md5_text()

func _palette(id: String) -> Array:
	var out: Array = []
	match id:
		"kitchen_chaos": out = KitchenProps.palette()
		"toy_workshop": out = XmasProps.palette()
		_: out = AustraliaProps.palette()
	return out

## Is (x, z) off every hazard (burner / hoist sweep) and every bounce pad?
func _hazard_free(m: Dictionary, x: float, z: float) -> bool:
	for zn: Dictionary in m["zones"]:
		if str(zn["kind"]) == "ice": continue
		if PackZones.distance(zn, x, z) < 1.0: return false
	for p: Dictionary in m["geometry"]["bouncePads"]:
		if Vector2(x - float(p["x"]), z - float(p["z"])).length() < float(p["r"]) + 0.3: return false
	return true

# ---------------------------------------------------------------- 1. seeds

func _seeds(id: String, n: int) -> void:
	counts[id] = []
	var sigs := {}
	var palette := _palette(id)
	var kinds := {}
	for sd in range(1, n + 1):
		var L := PackMaps.layout(id, sd)
		var tag := "%s seed %d" % [id, sd]
		check(not L.is_empty() and bool(L["ok"]), tag + " layout ok (attempt %d)" % int(L.get("attempt", -1)))
		if L.is_empty(): continue
		var m: Dictionary = L["map"]
		for k in ["name", "cat", "tags", "only", "blurb", "sky", "skyTop", "voidColor", "hills", "shadow", "orbit", "hemi", "sunI", "spawns", "player", "bots", "wander", "drops", "geometry", "zones", "boxStyles"]:
			check(m.has(k), tag + " has " + k)
		check(str(m.get("only")) == PACKS[id] and str(m.get("name")) == NAMES[id], tag + " belongs to pack %s" % PACKS[id])
		var geo: Dictionary = m["geometry"]
		for k in ["boxes", "bouncePads", "floorPads", "ladders"]: check(geo.get(k) is Array, tag + " geometry." + k)
		var boxes: Array = geo["boxes"]
		counts[id].append(boxes.size())
		check(boxes.size() >= 60 and boxes.size() <= 450, tag + " box budget %d (<= 450)" % boxes.size())
		check(boxes.size() <= 690, tag + " never above the 690 cap")
		var bad_box := 0
		for b: Dictionary in boxes:
			check(b.keys().size() == 7, tag + " box has only the 7 maps.json keys %s" % [b.keys()])
			for k in ["x", "z", "w", "d", "h", "y", "color"]:
				if not b.has(k) or not (b[k] is float or b[k] is int): bad_box += 1
			if float(b["w"]) <= 0.0 or float(b["d"]) <= 0.0 or float(b["h"]) <= 0.0: bad_box += 1
			if not palette.has(int(b["color"])): bad_box += 1; check(false, tag + " colour %06x outside the palette" % int(b["color"]))
		check(bad_box == 0, tag + " %d malformed boxes" % bad_box)
		var half: float = float(L["half"])
		var slab: Dictionary = boxes[0]
		check(float(slab["w"]) == half * 2.0 and float(slab["d"]) == half * 2.0 and float(slab["y"]) == -2.0 and float(slab["h"]) == 2.0, tag + " the floor slab first")
		for i in (m["boxStyles"] as Dictionary).keys():
			check(int(i) < boxes.size() and (m["boxStyles"][i] as Dictionary).has("emissive"), tag + " box style %s" % i)
		# spots
		var spawns: Array = m["spawns"]
		var bots: Array = m["bots"]
		var drops: Array = m["drops"]
		check(spawns.size() >= 8 and bots.size() >= 12 and drops.size() >= 12, tag + " counts spawns %d bots %d drops %d" % [spawns.size(), bots.size(), drops.size()])
		check(m["player"] is Array and (m["player"] as Array).size() == 2, tag + " player start")
		var pts: Array = spawns + bots + [m["player"]]
		var solids := FighterPhysics.solids_from_map(m)
		for pt: Array in pts:
			var c := _clearance(boxes, float(pt[0]), float(pt[1]))
			check(c >= 2.0, tag + " spot %s only %.2f m from a box" % [pt, c])
			check(not _inside(boxes, float(pt[0]), float(pt[1]), 0.01), tag + " spot %s inside a box" % [pt])
			check(MatchSim.start_point_safe(solids, float(pt[0]), float(pt[1]), 0.01, MatchSim.RING_OUT_Y), tag + " spot %s is not on walkable floor 2 m from the edge" % [pt])
			check(_hazard_free(m, float(pt[0]), float(pt[1])), tag + " spot %s is in or at a hazard / bounce pad" % [pt])
		for d: Array in drops:
			if d.size() > 2:
				check(not _inside(boxes, float(d[0]), float(d[1]), float(d[2])), tag + " raised drop %s inside a box" % [d])
				var stands := false
				for b: Dictionary in boxes:
					if absf(float(d[0]) - float(b["x"])) < float(b["w"]) / 2.0 and absf(float(d[1]) - float(b["z"])) < float(b["d"]) / 2.0 and absf(float(b["y"]) + float(b["h"]) - float(d[2])) < 0.01: stands = true
				check(stands, tag + " raised drop %s floats" % [d])
			else:
				check(_clearance(boxes, float(d[0]), float(d[1])) >= 1.2, tag + " drop %s too close to a box" % [d])
				check(_hazard_free(m, float(d[0]), float(d[1])), tag + " crate spot %s is in a hazard" % [d])
		# the 1 m grid flood fill (SiteNav): every spawn from every other, every ground crate spot, every platform
		var starts: Array = []
		for pt: Array in pts: starts.append([pt[0], pt[1]])
		for d: Array in drops:
			if d.size() <= 2: starts.append([d[0], d[1]])
		var t0 := Time.get_ticks_usec()
		var nav := SiteNav.analyze(m, L["ignore"], starts)
		nav_ms += (Time.get_ticks_usec() - t0) / 1000.0
		check(bool(nav["ok"]), tag + " navigable: unreachable %s disconnected %s" % [(nav["unreachable"] as Array).slice(0, 4), (nav["disconnected"] as Array).slice(0, 4)])
		# features
		check((geo["bouncePads"] as Array).size() >= 1, tag + " has a bounce pad")
		for p: Dictionary in geo["bouncePads"]:
			check(p.has("x") and p.has("z") and p.has("r") and p.has("power"), tag + " pad keys")
			check(maxf(absf(float(p["x"])), absf(float(p["z"]))) < half - 5.5, tag + " pad %s too near the wall (a launch must not clear it)" % [p])
		for l: Dictionary in geo["ladders"]:
			check(absf(float(l["nx"])) + absf(float(l["nz"])) == 1.0 and float(l["y1"]) > float(l["y0"]), tag + " ladder normal / span")
		for z: Dictionary in m["zones"]: kinds[str(z["kind"])] = true
		var zk := {}
		for z: Dictionary in m["zones"]:
			zk[str(z["kind"])] = int(zk.get(str(z["kind"]), 0)) + 1
			check(["burner", "ice", "hoist"].has(str(z["kind"])), tag + " zone kind")
		match id:
			"kitchen_chaos": check(int(zk.get("burner", 0)) >= 4 and (geo["bouncePads"] as Array).size() >= 2, tag + " burners %s + 2 vent pads" % zk)
			"toy_workshop": check(int(zk.get("ice", 0)) >= 1 and (geo["bouncePads"] as Array).size() == 1, tag + " icy floor + the chimney pad %s" % zk)
			_: check(int(zk.get("hoist", 0)) == 1 and int(zk.get("burner", 0)) >= 1 and (geo["bouncePads"] as Array).size() == 1 and float(geo["bouncePads"][0]["power"]) > 17.0, tag + " hoist + hotplate + trampoline %s" % zk)
		sigs[_sig(m)] = true
		# same seed twice identical (the cache is bypassed by a different map object: regenerate from scratch)
		if sd <= 3:
			PackMaps._cache.clear()
			var again := PackMaps.generate(id, sd)
			check(_sig(again) == _sig(m), tag + " deterministic")
	check(sigs.size() == n, "%s: %d different seeds gave %d different levels" % [id, n, sigs.size()])

# ---------------------------------------------------------------- 2. registration and the builder

func _registration() -> void:
	var content := root.get_node("Content")
	var W := load("res://ui/setup_wizard.gd")
	for id: String in IDS:
		check(content.maps.has(id) and str(content.get_map(id).get("only")) == PACKS[id], "Content registers %s for pack %s" % [id, PACKS[id]])
		for mode: String in W.modes():
			check(not W.maps_for(mode).has(id), "the %s mode does not offer %s" % [mode, id])
		check(not ModeRules.maps_for("construction").has(id), "Construction does not offer " + id)
		check(not QP.maps_for("classic").has(id), "Quick Play does not roll " + id)
		check(Destruct.NOT_SUPPORTED.has(id), id + " is not a destructible arena")
	for id: String in IDS:
		for sd in [3, 5, 9]:
			PackMaps.set_seed(sd)
			var node := MapBuilder.build(id)
			var geo: Dictionary = PackMaps.generate(id, sd)["geometry"]
			check(node.map_id == id and node.solids.size() == (geo["boxes"] as Array).size(), "%s build seed %d: solids == boxes" % [id, sd])
			check(node.pads.size() == (geo["bouncePads"] as Array).size() and node.get_child_count() > 3, "%s build seed %d: pads and visuals" % [id, sd])
			var spinners := 0
			for c in node.get_children():
				if c is PackSpinner: spinners += 1
			check(spinners == (1 if id == "backyard_bbq" else 0), "%s build seed %d: Hills Hoist spinner nodes %d" % [id, sd, spinners])
			node.free()
	PackMaps.set_seed(1)
	print("PACKMAPS registration: 3 maps hidden from every ordinary mode, Quick Play and Construction; MapBuilder builds them")

# ---------------------------------------------------------------- 3. zones

func _sim(id: String, sd: int, classic := false) -> MatchSim:
	var map := PackMaps.generate(id, sd)
	var s := MatchSim.new()
	if classic: s.combat.damage_rule = "classic"
	s.configure("classic", -1)
	s.setup(id, map, map["geometry"]["ladders"], map["geometry"]["bouncePads"], "wobbler", PlayerControl.new(InputState.new()), 1, "normal", false)
	return s

func _first(m: Dictionary, kind: String) -> Dictionary:
	for z: Dictionary in m["zones"]:
		if str(z["kind"]) == kind: return z
	return {}

func _park(f: FighterState, x: float, y: float, z: float) -> void:
	f.phys.px = x; f.phys.py = y; f.phys.pz = z; f.phys.vx = 0.0; f.phys.vy = 0.0; f.phys.vz = 0.0

func _zones() -> void:
	# burner: kitchen. A fighter parked on a strip is alight within a step and loses health; one beside it is not.
	var s := _sim("kitchen_chaos", 2)
	check(s.zones != null and s.zones.zones.size() >= 4, "kitchen: the overlay exists with its burners")
	var bz: Dictionary = s.zones.zones[0]
	for z: Dictionary in s.zones.zones:
		if float(z.get("top", 0.0)) < 0.2: bz = z; break
	var r: Array = bz["rect"]
	var cx := (float(r[0]) + float(r[2])) / 2.0
	var cz := (float(r[1]) + float(r[3])) / 2.0
	var f := s.player
	var hp0 := f.hp
	_park(f, cx, 0.02, cz)
	for i in 90:
		s.step(1.0 / 60.0); s.sweep(); _park_hold(f, cx, cz)
	check(f.burn > 0.0 and f.hp < hp0, "a burner sets you alight and hurts (burn %.2f hp %.1f -> %.1f)" % [f.burn, hp0, f.hp])
	check(s.zones.burn_hits > 0, "burn steps counted")
	var s2 := _sim("kitchen_chaos", 2)
	var f2 := s2.player
	_park(f2, float(r[2]) + 5.5, 0.02, cz)
	if not PackZones.inside(bz, f2.phys.px, f2.phys.pz, 2.0):
		for i in 30: s2.step(1.0 / 60.0)
		check(f2.burn <= 0.0, "away from the burners nobody burns")
	s2.dispose(); s.dispose()
	# hoist: backyard. Stand in an arm's path: knocked (hp down) once; a fighter high above the band is not touched.
	var sh := _sim("backyard_bbq", 2)
	var hz := _first(sh.map, "hoist")
	check(sh.zones != null and not hz.is_empty(), "backyard: the overlay exists with its Hills Hoist")
	var hf := sh.player
	var ang := PackZones.hoist_angle(hz, 0.0) + 0.02
	_park(hf, float(hz["x"]) + cos(ang) * 3.0, 0.01, float(hz["z"]) + sin(ang) * 3.0)
	var hhp := hf.hp
	sh.step(1.0 / 60.0)
	check(sh.zones.hoist_hits >= 1 and hf.hp < hhp, "the hoist arm knocks you (hits %d, hp %.1f -> %.1f)" % [sh.zones.hoist_hits, hhp, hf.hp])
	var hits := sh.zones.hoist_hits
	for i in 10: sh.step(1.0 / 60.0)
	check(sh.zones.hoist_hits == hits, "one knock, then a cool-down")
	sh.dispose()
	var sj := _sim("backyard_bbq", 2)
	var jz := _first(sj.map, "hoist")
	var ja := PackZones.hoist_angle(jz, 0.0) + 0.02
	_park(sj.player, float(jz["x"]) + cos(ja) * 3.0, 2.4, float(jz["z"]) + sin(ja) * 3.0)
	sj.step(1.0 / 60.0)
	check(sj.zones.hoist_hits == 0, "a jump over the arm is clear")
	sj.dispose()
	# ice: toy workshop. Standing in the zone flips the steering flag; outside it never does; the classic rule has no overlay.
	var si := _sim("toy_workshop", 2)
	var iz := _first(si.map, "ice")
	check(si.zones != null and not iz.is_empty(), "workshop: the overlay exists with its ice")
	var ir: Array = iz["rect"]
	var icx := (float(ir[0]) + float(ir[2])) / 2.0
	var icz := (float(ir[1]) + float(ir[3])) / 2.0
	var p := si.player
	_park(p, icx, 0.01, icz)
	si.step(1.0 / 60.0)                                  # lands (grounded) first
	_park(p, icx, 0.01, icz)
	si.step(1.0 / 60.0)
	check(p.phys.ice_grip, "ice: the steering flag is on inside the zone")
	_park(p, float(ir[2]) + 3.0, 0.01, icz)
	var outside_ok := true
	for z: Dictionary in si.zones.zones:
		if str(z["kind"]) == "ice" and PackZones.inside(z, p.phys.px, p.phys.pz, 0.5): outside_ok = false
	if outside_ok:
		si.step(1.0 / 60.0); si.step(1.0 / 60.0)
		check(not p.phys.ice_grip, "ice: the flag is off outside the zone")
	# the slide itself: moving at 6 m/s and no input. On ice (ice_setting 0.6: 20 * 0.05^0.6 = 3.3 m/s^2) the speed barely drops in
	# 0.3 s; on bare floor (40 m/s^2) it is gone in 0.15 s.
	_park(p, icx, 0.01, icz); si.step(1.0 / 60.0); si.step(1.0 / 60.0)
	p.phys.vx = 6.0
	for i in 18: si.step(1.0 / 60.0)
	check(p.phys.vx > 4.0, "ice: you keep gliding with no input (6.0 -> %.2f m/s in 0.3 s)" % p.phys.vx)
	si.dispose()
	var sn := _sim("toy_workshop", 2)
	var np := sn.player
	var nz := _outside_ice(sn)
	_park(np, nz.x, 0.01, nz.y); sn.step(1.0 / 60.0); sn.step(1.0 / 60.0)
	np.phys.vx = 6.0
	for i in 18: sn.step(1.0 / 60.0)
	check(np.phys.vx < 1.0, "no ice: you stop quickly (6.0 -> %.2f m/s in 0.3 s)" % np.phys.vx)
	sn.dispose()
	# gated: the classic rule (web / parity / online-without-net_zones) has no overlay and never sets the flag, even parked on ice
	var sc := _sim("toy_workshop", 2, true)
	check(sc.zones == null and not sc.combat.tuning_active(), "classic rule: no pack overlay (tuning off)")
	var cp := sc.player
	_park(cp, icx, 0.01, icz)
	for i in 5: sc.step(1.0 / 60.0)
	check(not cp.phys.ice_grip and sc.ensure_zones() == null, "classic rule: ice never applies, ensure_zones refuses")
	sc.dispose()
	var sa := MatchSim.new()
	var am: Dictionary = (load("res://autoload/content.gd") as Script).call("load_json", "maps")["arena"]
	sa.configure("classic", -1)
	sa.setup("arena", am, am["geometry"]["ladders"], am["geometry"]["bouncePads"], "wobbler", PlayerControl.new(InputState.new()), 1, "normal", false)
	check(sa.zones == null and not sa.player.phys.ice_grip, "an ordinary arena has no pack overlay")
	sa.dispose()
	print("PACKMAPS zones: burner burns, hoist knocks (jump clears), ice only in its zone and only under tuning")

func _park_hold(f: FighterState, x: float, z: float) -> void:
	f.phys.px = x; f.phys.pz = z; f.phys.vx = 0.0; f.phys.vz = 0.0

## A floor point of the workshop well away from every ice zone, props and walls (a free ground spot).
func _outside_ice(s: MatchSim) -> Vector2:
	for sp: Array in s.map["spawns"]:
		var ok := true
		for z: Dictionary in s.zones.zones:
			if str(z["kind"]) == "ice" and PackZones.inside(z, float(sp[0]), float(sp[1]), 3.0): ok = false
		if ok: return Vector2(float(sp[0]), float(sp[1]))
	return Vector2(float(s.map["spawns"][0][0]), float(s.map["spawns"][0][1]))

# ---------------------------------------------------------------- 4. 20 s bot matches

func _stage(id: String) -> Dictionary:
	var evs: Array = []
	for t: String in EVENTS[id]:
		evs.append({"type": t, "every": 3.0, "params": {}})
	evs.append({"type": "no_such_event", "every": 3.0, "params": {}})        # must be ignored
	return {"id": "test", "events": evs}

func _matches() -> void:
	for id: String in IDS:
		PackMaps.set_seed(7)
		var world: Node = load("res://world/world.tscn").instantiate()
		world.map_id = id
		world.auto_run = false
		world.bot_count = 5
		world.rng_seed = 4242
		world.dyn_choice = "off"
		root.add_child(world)
		var sim: MatchSim = world.sim
		check(world.map_node.map_id == id and str(sim.map.get("name")) == NAMES[id], id + " the match runs on the generated arena")
		check(sim.zones != null, id + " offline: the pack overlay is on")
		var am: RefCounted = AM.new()
		am.start_run(1)
		var ev: RefCounted = SE.new()
		ev.world = world
		var half := float(PackMaps.layout(id, 7)["half"])
		ev.setup(am, sim, _stage(id), _rng(7))
		var bad := 0
		var thru := 0                    # fighters below the floor while still over it: falling through the world
		var out := 0                     # fighters knocked over the perimeter (a legitimate ring-out, as on any walled arena)
		for i in 1200:
			world.tick(1.0 / 60.0)
			am.t_stage += 1.0 / 60.0
			ev.update(1.0 / 60.0)
			for f: FighterState in sim.fighters:
				if not (is_finite(f.phys.px) and is_finite(f.phys.py) and is_finite(f.phys.pz) and is_finite(f.hp)): bad += 1
				if f.phys.py < -1.0 and not f.dead:
					if absf(f.phys.px) < half - 0.3 and absf(f.phys.pz) < half - 0.3: thru += 1
					else: out += 1
		check(bad == 0, id + " positions and health stay finite over 20 s")
		check(thru == 0, id + " nobody fell through the floor (%d fighter-steps below it, over it)" % thru)
		for t: String in EVENTS[id]:
			check(int(ev.counts.get(t, 0)) >= 1, "%s: event %s fired in the match (%d times)" % [id, t, int(ev.counts.get(t, 0))])
		check(not ev.counts.has("no_such_event"), id + ": an unknown event id is ignored")
		var toasts: Array = []
		for e: Dictionary in sim.combat.events:
			if e.get("type") == "toast": toasts.append(e["text"])
		ev.finish()
		check(ev._pulses.is_empty() and ev._crates.is_empty(), id + ": finish() clears the events")
		print("PACKMAPS match %s: 20 s, %d fighters, events %s, burn steps %d, hoist hits %d, fighter-steps knocked out of the arena %d" % [id, sim.fighters.size(), ev.counts, sim.zones.burn_hits, sim.zones.hoist_hits, out])
		world.free()
	PackMaps.set_seed(1)

func _rng(sd: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = sd
	return r

# ---------------------------------------------------------------- 5. each event on its own (logic only)

func _events_logic() -> void:
	var expect := {"dinner_rush": "Dinner Rush!", "ingredient_drop": "Ingredient Drop!", "ice_zone": "Ice Zone!", "gift_barrage": "Gift Barrage!",
		"hoist_sweep": "Hoist Sweep!", "sausage_sizzle": "Sausage Sizzle!"}
	for id: String in IDS:
		for t: String in EVENTS[id]:
			var s := _sim(id, 4)
			var am: RefCounted = AM.new()
			am.start_run(1)
			var ev: RefCounted = SE.new()
			ev.setup(am, s, {"id": "t", "events": [{"type": t, "every": 1.0, "params": {"warning_time": 0.5, "duration": 1.5}}]}, _rng(11))
			var max_zones := 0
			var max_crates := 0
			for i in 360:
				s.step(1.0 / 60.0)
				ev.update(1.0 / 60.0)
				max_zones = maxi(max_zones, s.zones.zones.size())
				max_crates = maxi(max_crates, ev._crates.size())
			var toasts: Array = s.combat.events.filter(func(e: Dictionary) -> bool: return e.get("type") == "toast").map(func(e: Dictionary) -> String: return str(e["text"]))
			check(int(ev.counts.get(t, 0)) >= 4, "%s fires every second (%d in 6 s)" % [t, int(ev.counts.get(t, 0))])
			check(toasts.has(expect[t]), "%s toasts '%s' %s" % [t, expect[t], toasts.slice(0, 2)])
			if t == "ingredient_drop" or t == "gift_barrage": check(max_crates >= 3, "%s drops crates (%d at once)" % [t, max_crates])
			else: check(max_zones > s.map["zones"].size(), "%s adds temporary zones (%d vs %d)" % [t, max_zones, s.map["zones"].size()])
			ev.finish()
			check(ev._pulses.is_empty() and s.zones.zones.size() == (s.map["zones"] as Array).size(), "%s cleans its zones up" % t)
			s.dispose()
	# an event with an unknown id, and a stage with no events at all, are harmless
	var s2 := _sim("kitchen_chaos", 4)
	var am2: RefCounted = AM.new()
	am2.start_run(1)
	var ev2: RefCounted = SE.new()
	ev2.setup(am2, s2, {"id": "t", "events": [{"type": "meteor_shower", "every": 0.5, "params": {}}]}, _rng(11))
	for i in 120: s2.step(1.0 / 60.0); ev2.update(1.0 / 60.0)
	check(ev2.counts.is_empty() and ev2._pulses.is_empty(), "an unknown event id does nothing")
	s2.dispose()
	# without the balance overlay (classic rule) the pulses keep their toast and warning but never create zones
	var s3 := _sim("toy_workshop", 4, true)
	var am3: RefCounted = AM.new()
	am3.start_run(1)
	var ev3: RefCounted = SE.new()
	ev3.setup(am3, s3, {"id": "t", "events": [{"type": "ice_zone", "every": 1.0, "params": {"warning_time": 0.2, "duration": 1.0}}]}, _rng(11))
	for i in 180: s3.step(1.0 / 60.0); ev3.update(1.0 / 60.0)
	check(int(ev3.counts.get("ice_zone", 0)) >= 1 and s3.zones == null, "ice_zone without tuning: toast only, no overlay is created")
	ev3.finish()
	s3.dispose()
	print("PACKMAPS events: dinner_rush ingredient_drop ice_zone gift_barrage hoist_sweep sausage_sizzle run, clean up, unknown ids are ignored")
