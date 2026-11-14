extends SceneTree
## Destructible environment mode, milestone M0 (docs/DESTRUCTIBLE.md). Run by tools/test-godot-destruct.js:
##   godot --headless --path godot --script res://tests/destruct_test.gd -- --no-save
##
## 1. Authoring data: godot/data/extra/destructible.json is valid against shared/maps.json - arena ids exist, every prop
##    stands on the floor INSIDE the map and clear of spawns / player start / bot spots / ladders / pads / ring-out
##    edges, props do not overlap map geometry or each other, hp / colour / sizes / the prop budget are sane. Negative
##    cases prove the validator actually rejects each rule.
## 2. Off (default): no Destruct object, no extra solids, no prop meshes, and a normal match is IDENTICAL - same state
##    hash and same CombatRng state after 2 s as a run where the mode is explicitly off. Turning the mode on for an
##    arena without authored props is a no-op too (no solids, no RNG draws, identical hash).
## 3. On, for each authored arena: props load with collision; an AK hitscan breaks a crate after its hp (solid removed,
##    mesh hidden, "break" + sound events); a rocket/explosion breaks a prop; a broken prop stays broken; a fresh
##    load_map rebuilds every prop unbroken.
## 4. Break EVERY prop: no errors, every solid removed, debris events fire, 120 more sim frames run clean and the prop
##    nodes are gone (rubble patches stay).
## 5. World wiring: Settings "destructible" off = no props, on = props + the "Breakables" mode line, load_map clears
##    and rebuilds, --destruct override, and the offline-off mode gates (Practice Range / Sandbox never get props).

const AK := "ak"
var fails := 0
var checks := 0
var maps: Dictionary = {}
var data: Dictionary = {}

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		if fails <= 40: print("FAIL ", msg)

func close(a: float, b: float, tol: float, msg: String) -> void:
	check(absf(a - b) <= tol, "%s (%.4f vs %.4f)" % [msg, a, b])

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	maps = load("res://autoload/content.gd").load_json("maps")
	data = Combat.read_json(Destruct.DATA_PATH)
	check(data is Dictionary and not (data as Dictionary).is_empty(), "destructible.json loads")
	if not (data is Dictionary) or (data as Dictionary).is_empty():
		print("DESTRUCT FAILED checks=%d fails=%d" % [checks, fails]); quit(1); return
	_data_checks()
	_off_checks()
	await _arena_checks()
	await _break_everything()
	await _world_checks()
	print("DESTRUCT %s checks=%d fails=%d" % ["ok" if fails == 0 else "FAILED", checks, fails])
	quit(0 if fails == 0 else 1)

# ============================== helpers ==============================

## A deterministic offline match: fixed RNG seed, steady floor, the given bot count, optional prop-mesh parent.
func _match(map_id: String, destructible: bool, seed: int, parent: Node3D = null, bots := 0) -> MatchSim:
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(seed)
	sim.dyn_choice = "off"
	sim.destructible = destructible
	sim.view_parent = parent
	var m: Dictionary = maps[map_id]
	var geo: Dictionary = m.get("geometry", {})
	sim.setup(map_id, m, geo.get("ladders", []), geo.get("bouncePads", []), "wobbler",
		PlayerControl.new(InputState.new()), bots)
	return sim

## The match state hash: solids, RNG, every fighter (position / velocity / hp / cooldown), the combat clock.
func _state_hash(sim: MatchSim) -> String:
	var parts: Array = [sim.solids.size(), sim.combat.rng.state, sim.solids.size(), sim.combat.time]
	for f: FighterState in sim.fighters:
		parts.append([f.phys.px, f.phys.py, f.phys.pz, f.phys.vx, f.phys.vy, f.phys.vz, f.hp, f.cool])
	return str(parts).sha256_text()

func _run_steps(sim: MatchSim, n: int) -> void:
	for i in n: sim.step(1.0 / 120.0)

func _has_event(sim: MatchSim, kind: String) -> bool:
	for e: Dictionary in sim.combat.events:
		if str(e.get("type", "")) == kind: return true
	return false

func _count_event(sim: MatchSim, kind: String) -> int:
	var n := 0
	for e: Dictionary in sim.combat.events:
		if str(e.get("type", "")) == kind: n += 1
	return n

## Place a fighter with a plausible hand/shoulder and arm direction (the animation normally writes these each frame).
func _pose(f: FighterState, sx: float, sz: float, aim: Array) -> void:
	var base := 0.0
	f.phys.place(sx, base, sz)
	f.phys.grounded = true
	f.hand_x = sx; f.hand_y = base + 1.3; f.hand_z = sz
	f.shoulder_x = sx; f.shoulder_y = base + 1.55; f.shoulder_z = sz
	f.chest_x = sx; f.chest_y = base + 1.22; f.chest_z = sz
	f.head_x = sx; f.head_y = base + 1.95; f.head_z = sz
	var d: Array = Combat.norm3(float(aim[0]) - f.hand_x, float(aim[1]) - f.hand_y, float(aim[2]) - f.hand_z)
	f.arm_x = d[0]; f.arm_y = d[1]; f.arm_z = d[2]
	f.is_player = true
	f.weapon = AK
	f.slot = 0
	f.cool = 0.0
	f.swing = -1.0

## A standing spot with a clear shot at prop `pi`: on the floor, outside every solid, first solid on the line is the prop.
func _stand_point(sim: MatchSim, d: Destruct, pi: int) -> Dictionary:
	var p: Dictionary = d.props[pi]
	var aim: Array = [float(p["x"]), float(p["y"]) + float(p["h"]) * 0.5, float(p["z"])]
	for dir: Array in [[0.0, -1.0], [1.0, 0.0], [0.0, 1.0], [-1.0, 0.0], [0.7, -0.7], [0.7, 0.7], [-0.7, 0.7], [-0.7, -0.7]]:
		for dist: float in [4.5, 6.0, 7.5]:
			var sx := float(p["x"]) + float(dir[0]) * dist
			var sz := float(p["z"]) + float(dir[1]) * dist
			if not _on_floor(sim, sx, sz, float(p["y"])): continue
			if not _clear_line(sim, d, sx, sz, aim, pi): continue
			return {"ok": true, "x": sx, "z": sz, "aim": aim}
	return {"ok": false}

## Is (x, z) on a floor whose top is `y`, and outside every solid at foot height?
func _on_floor(sim: MatchSim, x: float, z: float, y: float) -> bool:
	var floor_top := NAN
	for b: Dictionary in sim.solids:
		var inside_x: bool = x > float(b["minX"]) + 0.01 and x < float(b["maxX"]) - 0.01
		var inside_z: bool = z > float(b["minZ"]) + 0.01 and z < float(b["maxZ"]) - 0.01
		if inside_x and inside_z and float(b["bottom"]) + 0.01 < y and y < float(b["top"]) - 0.01: return false
		if inside_x and inside_z and absf(float(b["top"]) - y) < 0.06: floor_top = y
	return not is_nan(floor_top)

## Nothing solid (apart from the target prop) is closer along the fire line than the target prop.
func _clear_line(sim: MatchSim, d: Destruct, sx: float, sz: float, aim: Array, pi: int) -> bool:
	var hand := Vector3(sx, float(aim[1]) - 0.0 + 1.3, sz)
	var target := Vector3(float(aim[0]), float(aim[1]), float(aim[2]))
	var dir := (target - hand)
	var length := dir.length()
	if length < 0.5: return false
	dir = dir / length
	var ph: Array = d.ray_hit(hand.x, hand.y, hand.z, dir.x, dir.y, dir.z, length + 1.0)
	if ph.size() != 2 or int(ph[1]) != pi: return false
	var wall: float = sim.combat.weapons.ray_walls(hand.x, hand.y, hand.z, dir.x, dir.y, dir.z, length + 1.0)
	return wall < 0.0 or float(ph[0]) <= wall + 1e-6

## Fire the AK from a clear standing spot until the prop breaks. Returns {ok, shots, dmg}.
func _fire_prop(sim: MatchSim, d: Destruct, pi: int) -> Dictionary:
	var spot := _stand_point(sim, d, pi)
	if not bool(spot.get("ok", false)): return {"ok": false, "why": "no standing spot"}
	var f: FighterState = sim.player
	_pose(f, float(spot["x"]), float(spot["z"]), spot["aim"])
	var p: Dictionary = d.props[pi]
	var start_hp := float(p["hp"])
	var shots := 0
	var first_dmg := -1.0
	for k in 12:
		sim.combat.weapons.fire_gun(f, AK, spot["aim"])
		shots += 1
		if first_dmg < 0.0 and float(p["hp"]) < start_hp: first_dmg = start_hp - float(p["hp"])
		if bool(p["broken"]): return {"ok": true, "shots": shots, "dmg": first_dmg, "start_hp": start_hp}
	return {"ok": false, "why": "did not break in 12 shots", "shots": shots}

# ============================== 1. authoring data ==============================

func _data_checks() -> void:
	var errs: Array = Destruct.validate(data, maps)
	check(errs.is_empty(), "destructible.json validates: %s" % str(errs))
	var arenas: Dictionary = data.get("arenas", {}) if data.get("arenas") is Dictionary else {}
	check(arenas.size() == 3, "three arenas authored (found %d)" % arenas.size())
	var budget: Dictionary = Destruct.budget_of(data)
	var total := 0
	for raw_id: Variant in arenas:
		var id := str(raw_id)
		check(maps.has(id), "arena %s exists in maps.json" % id)
		var entry: Dictionary = arenas[raw_id] if arenas[raw_id] is Dictionary else {}
		var props: Array = entry.get("props", []) if entry.get("props") is Array else []
		total += props.size()
		check(props.size() > 0 and props.size() <= int(budget["perArena"]), "%s: %d props within the per-arena budget %d" % [id, props.size(), int(budget["perArena"])])
		for raw: Variant in props:
			var p: Dictionary = raw
			var b: Dictionary = p["box"]
			var m: Dictionary = maps[id]
			var g: Dictionary = m.get("geometry", {})
			# sits on the floor, inside the arena, nowhere near the void
			check(_data_on_floor(g, float(b["x"]), float(b["z"]), float(b["y"])), "%s %s stands on a floor" % [id, p["id"]])
			check(_data_clear_of_spawns(m, p), "%s %s is clear of spawns / player start / bot spots" % [id, p["id"]])
			check(_data_clear_of_ladders_pads(g, p), "%s %s is clear of ladders and bounce pads" % [id, p["id"]])
			check(_data_clear_of_drops(m, p), "%s %s is clear of crate drop spots" % [id, p["id"]])
			check(float(p["hp"]) > 0.0 and float(p["hp"]) <= 500.0, "%s %s has sane hp" % [id, p["id"]])
			var col := int(p["color"])
			check(col >= 0 and col <= 0xFFFFFF, "%s %s has a sane colour" % [id, p["id"]])
			check(Destruct.KINDS.has(str(p["kind"])), "%s %s has a known kind" % [id, p["id"]])
	check(total <= int(budget["total"]), "total prop budget respected (%d <= %d)" % [total, int(budget["total"])])
	check(total > 0, "the mode authors some props (%d)" % total)
	# the props are the right way round: only crates and barricades, no duplicated ids
	var ids := {}
	for raw_id: Variant in arenas:
		for raw: Variant in (arenas[raw_id] as Dictionary).get("props", []):
			var p: Dictionary = raw
			check(not ids.has(str(p["id"])), "prop id %s is unique" % p["id"])
			ids[str(p["id"])] = true

func _data_on_floor(g: Dictionary, x: float, z: float, y: float) -> bool:
	for raw: Variant in (g.get("boxes", []) as Array):
		var b: Dictionary = raw
		var w := float(b["w"]); var d := float(b["d"]); var by := float(b["y"]); var h := float(b["h"])
		var top := by + h
		if absf(top - y) > 0.06: continue
		if x > float(b["x"]) - w / 2.0 and x < float(b["x"]) + w / 2.0 and z > float(b["z"]) - d / 2.0 and z < float(b["z"]) + d / 2.0:
			return true
	return false

func _aabb_clear(px: float, pz: float, min_x: float, max_x: float, min_z: float, max_z: float, margin: float) -> bool:
	var dx := maxf(maxf(min_x - px, 0.0), px - max_x)
	var dz := maxf(maxf(min_z - pz, 0.0), pz - max_z)
	return sqrt(dx * dx + dz * dz) >= margin

func _data_clear_of_spawns(m: Dictionary, p: Dictionary) -> bool:
	var b: Dictionary = p["box"]
	var min_x := float(b["x"]) - float(b["w"]) / 2.0; var max_x := float(b["x"]) + float(b["w"]) / 2.0
	var min_z := float(b["z"]) - float(b["d"]) / 2.0; var max_z := float(b["z"]) + float(b["d"]) / 2.0
	var pts: Array = []
	for sp: Variant in (m.get("spawns", []) as Array): pts.append(sp)
	for sp: Variant in (m.get("bots", []) as Array): pts.append(sp)
	if m.get("player") is Array: pts.append(m["player"])
	for sp: Variant in pts:
		if not (sp is Array): continue
		var a: Array = sp
		if a.size() < 2: continue
		if not _aabb_clear(float(a[0]), float(a[1]), min_x, max_x, min_z, max_z, Destruct.SPAWN_CLEARANCE): return false
	return true

func _data_clear_of_ladders_pads(g: Dictionary, p: Dictionary) -> bool:
	var b: Dictionary = p["box"]
	var min_x := float(b["x"]) - float(b["w"]) / 2.0; var max_x := float(b["x"]) + float(b["w"]) / 2.0
	var min_z := float(b["z"]) - float(b["d"]) / 2.0; var max_z := float(b["z"]) + float(b["d"]) / 2.0
	for raw: Variant in (g.get("ladders", []) as Array):
		var l: Dictionary = raw
		if not _aabb_clear(float(l["x"]), float(l["z"]), min_x, max_x, min_z, max_z, Destruct.LADDER_CLEARANCE): return false
	for raw: Variant in (g.get("bouncePads", []) as Array):
		var q: Dictionary = raw
		if not _aabb_clear(float(q["x"]), float(q["z"]), min_x, max_x, min_z, max_z, float(q.get("r", 1.2)) + Destruct.PAD_CLEARANCE): return false
	return true

func _data_clear_of_drops(m: Dictionary, p: Dictionary) -> bool:
	var b: Dictionary = p["box"]
	var min_x := float(b["x"]) - float(b["w"]) / 2.0; var max_x := float(b["x"]) + float(b["w"]) / 2.0
	var min_z := float(b["z"]) - float(b["d"]) / 2.0; var max_z := float(b["z"]) + float(b["d"]) / 2.0
	for raw: Variant in (m.get("drops", []) as Array):
		if not (raw is Array) or (raw as Array).size() < 2: continue
		var dr: Array = raw
		if not _aabb_clear(float(dr[0]), float(dr[1]), min_x, max_x, min_z, max_z, Destruct.CRATE_CLEARANCE): return false
	return true

func _expect_error(mutated: Dictionary, needle: String, what: String) -> void:
	var errs: Array = Destruct.validate(mutated, maps)
	var joined := "\n".join(errs)
	check(joined.contains(needle), "validator rejects %s (%s)" % [what, joined])

func _negative_checks() -> void:
	# a prop moved off the floor (outside the arena)
	var bad: Dictionary = data.duplicate(true)
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["box"]["x"] = 500
	_expect_error(bad, "no floor", "a prop outside the map")
	# a prop on the ring-out edge (its footprint is supported but it hangs over the void)
	bad = data.duplicate(true)
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["box"]["x"] = 19.0
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["box"]["z"] = 0.0
	_expect_error(bad, "ring-out edge", "a prop on the ring-out edge")
	# a prop on the player's start
	bad = data.duplicate(true)
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["box"]["x"] = 0.0
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["box"]["z"] = 8.0
	_expect_error(bad, "blocks a spawn", "a prop on the player start")
	# a prop inside existing map geometry
	bad = data.duplicate(true)
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["box"]["x"] = 9.0
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["box"]["z"] = 6.0
	_expect_error(bad, "overlaps existing map geometry", "a prop inside a wall")
	# bad hp / colour / kind / unknown arena / budget
	bad = data.duplicate(true)
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["hp"] = 0
	_expect_error(bad, "hp", "hp 0")
	bad = data.duplicate(true)
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["color"] = 0xFFFFFF + 1
	_expect_error(bad, "color", "an out-of-range colour")
	bad = data.duplicate(true)
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0]["kind"] = "boulder"
	_expect_error(bad, "kind", "an unknown prop kind")
	bad = data.duplicate(true)
	bad["arenas"]["not_a_real_map"] = {"props": [((data["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0].duplicate(true)]}
	_expect_error(bad, "unknown arena id", "an arena that does not exist")
	bad = data.duplicate(true)
	bad["budget"] = {"total": 1, "perArena": 12}
	_expect_error(bad, "budget", "an over-budget manifest")
	bad = data.duplicate(true)
	# duplicate prop id in one arena
	((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"].append((((bad["arenas"] as Dictionary)["arena"] as Dictionary)["props"][0] as Dictionary).duplicate(true))
	_expect_error(bad, "duplicate id", "a duplicated prop id")

# ============================== 2. off / no-op ==============================

func _off_checks() -> void:
	_negative_checks()
	var m: Dictionary = maps["arena"]
	var parent := Node3D.new()
	root.add_child(parent)
	# baseline: the mode untouched (the default of a normal match), three bots
	var base := _match("arena", false, 424242, parent, 3)
	_run_steps(base, 240)                      # 2 s of a real match before anything else
	var base_hash := _state_hash(base)
	var base_rng := base.combat.rng.state
	check(base.destruct == null, "off: no Destruct object")
	check(base.combat.destruct == null, "off: Combat has no destruct hook")
	check(base.solids.size() == FighterPhysics.solids_from_map(m).size(), "off: no extra solids (%d)" % base.solids.size())
	var tagged := 0
	for s: Dictionary in base.solids:
		if s.has("breakable"): tagged += 1
	check(tagged == 0, "off: no solid is tagged breakable")
	check(parent.get_child_count() == 0, "off: no prop meshes")
	# explicit off: a second match with the same seed and the flag passed as false must be byte-identical
	var off := _match("arena", false, 424242, parent, 3)
	_run_steps(off, 240)
	check(_state_hash(off) == base_hash, "off: same state hash as the baseline after 2 s")
	check(off.combat.rng.state == base_rng, "off: same RNG draws as the baseline")
	check(off.solids.size() == base.solids.size(), "off: same solids as the baseline")
	# mode on for an arena with no authored props: no solids, no meshes, no RNG draws, identical match to that map's off
	var farm_off := _match("farm", false, 424242, parent, 3)
	_run_steps(farm_off, 240)
	var farm_hash := _state_hash(farm_off)
	var farm_rng := farm_off.combat.rng.state
	farm_off.dispose()
	var no_data := _match("farm", true, 424242, parent, 3)
	_run_steps(no_data, 240)
	check(no_data.destruct != null and no_data.destruct.props.is_empty(), "on, unauthored arena: Destruct exists with 0 props")
	check(no_data.solids.size() == FighterPhysics.solids_from_map(maps["farm"]).size(), "on, unauthored arena: no extra solids")
	check(no_data.combat.rng.state == farm_rng, "on, unauthored arena: no RNG draws")
	check(_state_hash(no_data) == farm_hash, "on, unauthored arena: the match is identical")
	check(parent.get_child_count() == 0, "on, unauthored arena: no prop meshes")
	# the steady-floor rule: the mode forces off the moving floor (props must not float, docs/DESTRUCTIBLE.md)
	var on := _match("arena", true, 424242, parent, 3)
	check(on.dyn.kind == "off", "on: the destructible mode runs a steady floor (dyn=%s)" % on.dyn.kind)
	check(on.destruct != null and on.destruct.props.size() > 0, "on: props authored for arena")
	check(on.solids.size() == FighterPhysics.solids_from_map(m).size() + on.destruct.props.size(), "on: every prop is a solid")
	check(parent.get_child_count() == on.destruct.props.size(), "on: one prop mesh root per prop")
	var mesh_ok := true
	for c in parent.get_children():
		if not str(c.name).begins_with("Prop_"): mesh_ok = false
	check(mesh_ok, "on: prop mesh nodes are named Prop_<id>")
	check(on.destruct.mesh_count() == on.destruct.props.size(), "on: every prop has a mesh")
	base.dispose(); off.dispose(); no_data.dispose(); on.dispose()
	parent.free()

# ============================== 3. per-arena behaviour ==============================

func _arena_checks() -> void:
	var arenas: Dictionary = data.get("arenas", {}) if data.get("arenas") is Dictionary else {}
	for raw_id: Variant in arenas:
		var id := str(raw_id)
		var entry: Dictionary = arenas[raw_id]
		var want: int = (entry.get("props", []) as Array).size()
		var m: Dictionary = maps[id]
		var base_solids := FighterPhysics.solids_from_map(m).size()
		var parent := Node3D.new()
		root.add_child(parent)
		var sim := _match(id, true, 9001 + want, parent, 0)
		var d: Destruct = sim.destruct
		check(d != null, "%s: Destruct created" % id)
		if d == null: parent.queue_free(); continue
		check(d.props.size() == want, "%s: %d props loaded" % [id, d.props.size()])
		check(sim.solids.size() == base_solids + want, "%s: props are collision solids" % id)
		for i in d.props.size():
			var p: Dictionary = d.props[i]
			check(sim.solids.find(p["solid"]) >= 0, "%s %s is in sim.solids" % [id, p["id"]])
			check(d.is_breakable(p["solid"]) and d.is_breakable(str(p["id"])) and d.is_breakable(i), "%s %s is_breakable()" % [id, p["id"]])
			check(float(p["solid"]["top"]) > float(p["solid"]["bottom"]), "%s %s has a real box" % [id, p["id"]])
		# collision: a fighter walking into a prop is stopped by it (it is a normal box in the list)
		var target_i := 0
		var tp: Dictionary = d.props[target_i]
		var ts: Dictionary = tp["solid"]
		var f: FighterState = sim.player
		var walk_x := (float(ts["minX"]) + float(ts["maxX"])) * 0.5
		var walk_z := float(ts["maxZ"]) + float(FighterPhysics.R) + 1.2
		f.phys.place(walk_x, 0.0, walk_z)
		f.phys.grounded = true
		var sx := f.phys.px
		for k in 90:
			f.phys.wish_x = 0.0
			f.phys.wish_z = -1.0
			f.phys.step(1.0 / 120.0, sim.solids, f)
		check(f.phys.pz >= float(ts["maxZ"]) + FighterPhysics.R - 0.06, "%s: a fighter cannot walk through a prop (%.2f vs %.2f)" % [id, f.phys.pz, float(ts["maxZ"]) + FighterPhysics.R])
		check(absf(f.phys.px - walk_x) < 0.6, "%s: the prop collision keeps the walk roughly on line" % id)
		# hitscan: the AK breaks a crate after its hp (2-5 hits for the authored hp)
		var fire := _fire_prop(sim, d, target_i)
		check(bool(fire.get("ok", false)), "%s: hitscan breaks %s (%s)" % [id, tp["id"], fire.get("why", "")])
		if bool(fire.get("ok", false)):
			check(int(fire["shots"]) >= 2 and int(fire["shots"]) <= 8, "%s: %s broke after %d hits" % [id, tp["id"], int(fire["shots"])])
			check(float(tp["hp"]) <= 0.0, "%s: %s hp reduced to <= 0" % [id, tp["id"]])
			check(d.broken_count() >= 1, "%s: broken_count() counts the break" % id)
			check(not d.is_breakable(target_i), "%s: a broken prop is not breakable" % id)
			check(sim.solids.find(tp["solid"]) < 0, "%s: the broken prop left sim.solids" % id)
			check(_has_event(sim, "break"), "%s: a break event fired" % id)
			check(_has_event(sim, "sfx"), "%s: a break sound event fired" % id)
			check(tp["mesh"] == null, "%s: the broken prop mesh was released" % id)
		var broken_before := d.broken_count()
		_run_steps(sim, 120)                    # broken props stay broken
		check(d.broken_count() == broken_before, "%s: broken props stay broken" % id)
		check(not d.is_breakable(target_i) and sim.solids.find(tp["solid"]) < 0, "%s: a broken prop is still gone after 1 s" % id)
		# explosion: a rocket blast breaks a nearby prop through the real explosion path
		var blast_i := -1
		for i in d.props.size():
			if not bool(d.props[i]["broken"]): blast_i = i; break
		if blast_i >= 0:
			var bp: Dictionary = d.props[blast_i]
			sim.combat.events.clear()
			var bx := float(bp["x"]); var by := float(bp["y"]); var bz := float(bp["z"])
			sim.combat.weapons.explode(bx, by + 0.6, bz, sim.player, sim.combat.wdata("rocket"))
			check(bool(bp["broken"]), "%s: an explosion breaks a nearby prop" % id)
			check(_count_event(sim, "break") >= 1, "%s: the explosion fired a break event" % id)
		# a fresh load (a new MatchSim) rebuilds every prop unbroken
		var parent2 := Node3D.new()
		root.add_child(parent2)
		var fresh := _match(id, true, 9001 + want, parent2, 0)
		check(fresh.destruct != null and fresh.destruct.props.size() == want and fresh.destruct.broken_count() == 0, "%s: a fresh match rebuilds every prop" % id)
		check(fresh.destruct != null and fresh.solids.size() == base_solids + want, "%s: a fresh match has every prop solid back" % id)
		if fresh.destruct != null: fresh.dispose()
		parent2.queue_free()
		sim.dispose()
		parent.queue_free()
		await process_frame
	# the rocket path, once (the shared explode() above is what rockets call, but prove the launcher drives it too)
	var arena_parent := Node3D.new()
	root.add_child(arena_parent)
	var rsim := _match("arena", true, 777, arena_parent, 0)
	var rd: Destruct = rsim.destruct
	var ri := -1
	for i in rd.props.size():
		if str(rd.props[i]["kind"]) == "crate": ri = i; break
	var spot := _stand_point(rsim, rd, ri)
	check(bool(spot.get("ok", false)), "rocket: a clear firing spot exists")
	if bool(spot.get("ok", false)):
		var rf: FighterState = rsim.player
		_pose(rf, float(spot["x"]), float(spot["z"]), spot["aim"])
		rsim.combat.events.clear()
		rsim.combat.weapons.launch_rocket(rf, "rocket", spot["aim"])
		var broke := false
		for k in 240:
			rsim.step(1.0 / 120.0)
			if bool(rd.props[ri]["broken"]): broke = true; break
		check(broke, "rocket: a launched rocket breaks the crate it hits")
		check(_has_event(rsim, "explode"), "rocket: the rocket exploded")
	rsim.dispose()
	arena_parent.queue_free()
	await process_frame

# ============================== 4. every prop breaks ==============================

func _break_everything() -> void:
	var arenas: Dictionary = data.get("arenas", {}) if data.get("arenas") is Dictionary else {}
	for raw_id: Variant in arenas:
		var id := str(raw_id)
		var m: Dictionary = maps[id]
		var want: int = ((arenas[raw_id] as Dictionary).get("props", []) as Array).size()
		var base_solids := FighterPhysics.solids_from_map(m).size()
		var parent := Node3D.new()
		root.add_child(parent)
		var sim := _match(id, true, 31, parent, 0)
		var d: Destruct = sim.destruct
		sim.combat.events.clear()
		for i in d.props.size():
			check(d.break_hit(i, 9999.0, [0.0, 0.0, 1.0]), "%s: prop %d breaks" % [id, i])
		check(d.broken_count() == want, "%s: every prop broken (%d/%d)" % [id, d.broken_count(), want])
		check(sim.solids.size() == base_solids, "%s: no prop solids left" % id)
		check(d.remaining() == 0, "%s: remaining() == 0" % id)
		check(_count_event(sim, "break") == want, "%s: one break event per prop" % id)
		_run_steps(sim, 120)                   # at least 100 frames after the last break: no errors, no crash
		check(sim.solids.size() == base_solids, "%s: still no prop solids after 1 s" % id)
		await process_frame                     # let the freed prop meshes go
		var roots := 0
		var rubble := 0
		for c in parent.get_children():
			if str(c.name).begins_with("Prop_"): roots += 1
			elif str(c.name).begins_with("Rubble_"): rubble += 1
		check(roots == 0, "%s: every prop mesh node was freed" % id)
		check(rubble == want, "%s: one rubble patch per broken prop (%d)" % [id, rubble])
		sim.dispose()
		parent.queue_free()
		await process_frame

# ============================== 5. world wiring ==============================

func _world_off_props(world: Node) -> int:
	if world.map_node == null: return -1
	var n := 0
	for c in world.map_node.get_children():
		if str(c.name).begins_with("Prop_"): n += 1
	return n

func _world_checks() -> void:
	var st: Node = root.get_node("Settings")
	st.set_value("destructible", false)
	var off: Node = load("res://world/world.tscn").instantiate()
	off.map_id = "arena"; off.auto_run = false; off.bot_count = 0; off.dyn_choice = "off"
	root.add_child(off)
	await process_frame
	check(off.sim.destruct == null, "world off: no destructible mode")
	check(_world_off_props(off) == 0, "world off: no prop meshes under the map")
	check(off._mode_l != null and not off._mode_l.text.contains("Breakables"), "world off: the mode line does not mention breakables")
	off.queue_free()
	await process_frame
	st.set_value("destructible", true)
	var on: Node = load("res://world/world.tscn").instantiate()
	on.map_id = "arena"; on.auto_run = false; on.bot_count = 0; on.dyn_choice = "off"
	root.add_child(on)
	await process_frame
	check(on.sim.destruct != null, "world on: Destruct is wired")
	var want: int = ((data["arenas"] as Dictionary)["arena"] as Dictionary)["props"].size()
	check(on.sim.destruct != null and on.sim.destruct.props.size() == want, "world on: %d props loaded" % want)
	check(_world_off_props(on) == want, "world on: one prop mesh per prop under the map")
	check(on._mode_l != null and on._mode_l.text.contains("Breakables"), "world on: the HUD mode line says Breakables (%s)" % (on._mode_l.text if on._mode_l else ""))
	var base_solids := FighterPhysics.solids_from_map(maps["arena"]).size()
	on.sim.destruct.break_hit(0, 9999.0)
	check(on.sim.solids.size() == base_solids + want - 1, "world on: a break leaves sim.solids")
	await process_frame
	on.load_map("arena")
	await process_frame
	check(on.sim.destruct != null and on.sim.destruct.props.size() == want and on.sim.destruct.broken_count() == 0, "world on: load_map rebuilds every prop fresh")
	check(_world_off_props(on) == want, "world on: load_map shows every prop mesh again")
	check(on.sim.solids.size() == base_solids + want, "world on: load_map restores every prop solid")
	on.queue_free()
	await process_frame
	# --destruct override (the CLI flag the setup wizard / test runners use)
	st.set_value("destructible", false)
	var forced: Node = load("res://world/world.tscn").instantiate()
	forced.map_id = "arena"; forced.auto_run = false; forced.bot_count = 0; forced.dyn_choice = "off"; forced.destruct_choice = "on"
	root.add_child(forced)
	await process_frame
	check(forced.sim.destruct != null and forced.sim.destruct.props.size() == want, "--destruct=on forces the mode on")
	forced.queue_free()
	await process_frame
	# offline gating: the Practice Range never gets props, even with the setting on
	var practice: Node = load("res://world/world.tscn").instantiate()
	practice.map_id = "practice"; practice.mode_id = "practice"; practice.auto_run = false; practice.bot_count = 0; practice.dyn_choice = "off"
	root.add_child(practice)
	await process_frame
	check(practice.sim.destruct == null, "world gate: the Practice Range ignores the mode")
	check(_world_off_props(practice) == 0, "world gate: no prop meshes on the range")
	practice.queue_free()
	await process_frame
	# offline gating: build mode (Sandbox) never gets props
	var sandbox: Node = load("res://world/world.tscn").instantiate()
	sandbox.build_mode = true; sandbox.auto_run = false; sandbox.bot_count = 0; sandbox.dyn_choice = "off"
	root.add_child(sandbox)
	await process_frame
	check(sandbox.sim.destruct == null, "world gate: the Sandbox ignores the mode")
	sandbox.queue_free()
	st.reset("destructible")
	await process_frame
