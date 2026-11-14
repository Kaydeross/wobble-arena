extends SceneTree
## Destructible environment mode, M1 "all maps" (docs/DESTRUCTIBLE.md). Run by tools/test-godot-destruct.js:
##   godot --headless --path godot --script res://tests/destruct_test.gd -- --no-save
##
## 1. Config: godot/data/extra/destructible.json validates against shared/maps.json (version 2 config: fraction, budget,
##    hp band, respawn timing, colours, exclusion rules, usability weights). Negative cases prove the validator rejects
##    every bad knob.
## 2. Off (default): no Destruct object, no extra solids, no prop meshes, no CombatRng draws, and a normal match is
##    IDENTICAL - same state hash and RNG after 2 s as an explicit-off run. On a mode-excluded map the mode is a no-op too.
## 3. Selection, EVERY supported arena: the map's own boxes are split into components (a wall + its cap, a stacked pile
##    count once); ~half of the eligible cover components become breakable (fraction 0.5, at least 1, capped by the
##    budget); ground / roofs / boundary walls / stairs / spawn / ladder / pad / enclosed boxes are never selected
##    (checked independently in the test), the selected cover is visible from the surrounding floor (independent
##    sightline check), the pick prefers usable cover (on the arena the two mid-field crates are picked in most seeds
##    instead of the far-corner blocks), the plan is deterministic for one seed and changes with another seed, and the
##    live match swaps exactly those boxes out of collision.
## 4. Behaviour: hitscan and explosions break components, broken ones stay broken, then respawn after the config's
##    randomised delay with collision + mesh restored (and a fade-in) and can be broken again through several cycles; a
##    respawn is postponed while a fighter stands in the box; node counts stay flat (no leaks). A non-breaking hit emits
##    `prop_hit` + a tap sound and advances the visible damage tier; melee (the starting spatula) and flame damage cover.
## 5. World wiring AND the real offline match path: the Setup Wizard's Breakable props toggle writes Settings, the world
##    the wizard starts reads it, the merged map mesh is pruned and every selected component is a tagged solid with its
##    own mesh; the world's own player then fires the real gun at every selected component until it breaks, the break
##    reaches the presentation layer (chips/sound) and the HUD count drops; respawn restores it; load_map/rematch rebuilds
##    fresh; --destruct override; Settings off = no props; the Practice Range / Sandbox gates still hold.

const AK := "ak"
const SEED := 424242
var fails := 0
var checks := 0
var maps: Dictionary = {}
var data: Dictionary = {}
var cfg: Dictionary = {}

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		if fails <= 60: print("FAIL ", msg)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	maps = load("res://autoload/content.gd").load_json("maps")
	data = Combat.read_json(Destruct.DATA_PATH)
	check(data is Dictionary and not (data as Dictionary).is_empty(), "destructible.json loads")
	if not (data is Dictionary) or (data as Dictionary).is_empty():
		print("DESTRUCT FAILED checks=%d fails=%d" % [checks, fails]); quit(1); return
	cfg = Destruct.config(data)
	_config_checks()
	_off_checks()
	await _selection_checks()
	await _behaviour_checks()
	await _feedback_checks()
	await _world_checks()
	print("DESTRUCT %s checks=%d fails=%d" % ["ok" if fails == 0 else "FAILED", checks, fails])
	quit(0 if fails == 0 else 1)

# ============================== helpers ==============================

## A deterministic offline match: fixed RNG seed and destruct seed, steady floor, the given bot count, optional mesh parent.
func _match(map_id: String, destructible: bool, seed: int, parent: Node3D = null, bots := 0) -> MatchSim:
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(seed)
	sim.dyn_choice = "off"
	sim.destructible = destructible
	sim.destruct_seed = seed
	sim.view_parent = parent
	var m: Dictionary = maps[map_id]
	var geo: Dictionary = m.get("geometry", {})
	sim.setup(map_id, m, geo.get("ladders", []), geo.get("bouncePads", []), "wobbler",
		PlayerControl.new(InputState.new()), bots)
	return sim

## The match state hash: solids, RNG, every fighter (position / velocity / hp / cooldown), the combat clock.
func _state_hash(sim: MatchSim) -> String:
	var parts: Array = [sim.solids.size(), sim.combat.rng.state, sim.combat.time]
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

func _styles(id: String) -> Dictionary:
	var look: Variant = MapBuilder.look(id)
	if look is Dictionary:
		var b: Variant = (look as Dictionary).get("boxes", {})
		if b is Dictionary: return b
	return {}

func _box_solids(map: Dictionary) -> Array:
	var out: Array = []
	for raw: Variant in ((map.get("geometry", {}) as Dictionary).get("boxes", []) as Array):
		var b: Dictionary = raw
		var w := float(b["w"]); var d := float(b["d"]); var y := float(b["y"]); var h := float(b["h"])
		out.append({"minX": float(b["x"]) - w / 2.0, "maxX": float(b["x"]) + w / 2.0,
			"minZ": float(b["z"]) - d / 2.0, "maxZ": float(b["z"]) + d / 2.0, "top": y + h, "bottom": y})
	return out

## Place a fighter with a plausible hand/shoulder and arm direction (the animation normally writes these each frame).
func _pose(f: FighterState, sx: float, sz: float, aim: Array, base := 0.0) -> void:
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
	var y := float(p["y"])
	var aim: Array = [float(p["x"]), y + float(p["h"]) * 0.5, float(p["z"])]
	for dir: Array in [[0.0, -1.0], [1.0, 0.0], [0.0, 1.0], [-1.0, 0.0], [0.7, -0.7], [0.7, 0.7], [-0.7, 0.7], [-0.7, -0.7]]:
		for dist: float in [2.5, 3.5, 4.5, 6.0, 7.5]:
			var sx := float(p["x"]) + float(dir[0]) * dist
			var sz := float(p["z"]) + float(dir[1]) * dist
			if not _on_floor(sim, sx, sz, y): continue
			if not _clear_line(sim, d, sx, sz, y, aim, pi): continue
			return {"ok": true, "x": sx, "z": sz, "y": y, "aim": aim}
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
func _clear_line(sim: MatchSim, d: Destruct, sx: float, sz: float, base_y: float, aim: Array, pi: int) -> bool:
	var hand := Vector3(sx, base_y + 1.3, sz)
	var target := Vector3(float(aim[0]), float(aim[1]), float(aim[2]))
	var dir := (target - hand)
	var length := dir.length()
	if length < 0.5: return false
	dir = dir / length
	var ph: Array = d.ray_hit(hand.x, hand.y, hand.z, dir.x, dir.y, dir.z, length + 1.0)
	if ph.size() != 2 or int(ph[1]) != pi: return false
	var wall: float = sim.combat.weapons.ray_walls(hand.x, hand.y, hand.z, dir.x, dir.y, dir.z, length + 1.0)
	return wall < 0.0 or float(ph[0]) <= wall + 1e-6

## Fire the AK from a clear standing spot until the prop breaks. Returns {ok, shots, prop}.
func _fire_prop(sim: MatchSim, d: Destruct, pi: int) -> Dictionary:
	var spot := _stand_point(sim, d, pi)
	if not bool(spot.get("ok", false)): return {"ok": false, "why": "no standing spot"}
	var f: FighterState = sim.player
	_pose(f, float(spot["x"]), float(spot["z"]), spot["aim"], float(spot["y"]))
	for k in 24:
		sim.combat.weapons.fire_gun(f, AK, spot["aim"])
		if bool(d.props[pi]["broken"]): return {"ok": true, "shots": k + 1}
	return {"ok": false, "why": "did not break in 24 shots"}

## Fire the player's gun `n` times at prop `pi` through the real weapon function (the one PlayerControl's gun_tick
## calls). Returns {ok, shots, broke}. The pose is restored after every shot because firing kicks the arm.
func _fire_shots(sim: MatchSim, d: Destruct, pi: int, n: int) -> Dictionary:
	var spot := _stand_point(sim, d, pi)
	if not bool(spot.get("ok", false)): return {"ok": false, "why": "no standing spot"}
	var f: FighterState = sim.player
	for k in n:
		_pose(f, float(spot["x"]), float(spot["z"]), spot["aim"], float(spot["y"]))
		sim.combat.weapons.fire_gun(f, AK, spot["aim"])
		if bool(d.props[pi]["broken"]): return {"ok": true, "shots": k + 1, "broke": true}
	return {"ok": true, "shots": n, "broke": false}

## Put the player within spatula reach of prop `pi`, mid-swing (the state combat.melee_sweep / Destruct.melee_sweep see).
## Returns false when no clear floor spot in front of the component exists.
func _pose_melee(sim: MatchSim, d: Destruct, pi: int) -> bool:
	var p: Dictionary = d.props[pi]
	var f: FighterState = sim.player
	var w := float(p["w"])
	var dd := float(p["d"])
	for dir: Array in [[0.0, -1.0], [1.0, 0.0], [0.0, 1.0], [-1.0, 0.0]]:
		var sx := float(p["x"]) + float(dir[0]) * (w * 0.5 + 1.05)
		var sz := float(p["z"]) + float(dir[1]) * (dd * 0.5 + 1.05)
		if not _on_floor(sim, sx, sz, float(p["y"])): continue
		var yaw := atan2(float(p["x"]) - sx, float(p["z"]) - sz)
		f.phys.place(sx, float(p["y"]), sz)
		f.phys.grounded = true
		f.dead = false; f.down_t = 0.0; f.slot = -1; f.weapon = "spatula"; f.cool = 0.0
		f.hand_x = sx; f.hand_y = float(p["y"]) + 1.3; f.hand_z = sz
		f.shoulder_x = sx; f.shoulder_y = float(p["y"]) + 1.55; f.shoulder_z = sz
		f.chest_x = sx; f.chest_y = float(p["y"]) + 1.22; f.chest_z = sz
		sim.combat.melee_begin(f, "spatula", yaw)
		f.swing = 0.55
		sim.combat.melee_tick(f, "spatula", 0.0, yaw)
		f.arm_x = f.aim_x; f.arm_y = f.aim_y; f.arm_z = f.aim_z
		return true
	return false

func _last_event(sim: MatchSim, kind: String) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in sim.combat.events:
		if str(e.get("type", "")) == kind: out = e
	return out

# ============================== 1. config ==============================

func _config_checks() -> void:
	var errs: Array = Destruct.validate(data, maps)
	check(errs.is_empty(), "destructible.json validates: %s" % str(errs))
	check(int(cfg["version"]) == Destruct.VERSION, "config is version 2")
	check(bool(cfg["enabled"]), "config enabled")
	check(float(cfg["fraction"]) >= 0.4 and float(cfg["fraction"]) <= 0.6, "fraction is about half (%.2f)" % float(cfg["fraction"]))
	check(int(cfg["per_map"]) >= 1 and int(cfg["per_map"]) <= Destruct.HARD_MAX_PER_MAP, "per-map budget %d" % int(cfg["per_map"]))
	var rmin := float(cfg["respawn_min"])
	var rmax := float(cfg["respawn_max"])
	check(rmin >= 90.0 and rmax <= 180.0 and rmin < rmax, "respawn is about two minutes and randomised (%.0f..%.0f s)" % [rmin, rmax])
	check(float(cfg["fade"]) > 0.0, "respawn has a fade-in")
	check(int(cfg["accent"]) >= 0 and int(cfg["accent"]) <= 0xFFFFFF, "accent colour is a 24-bit colour")
	# usability weights: all four are exponents on 0..1 factors (0 = no preference, > 1 = stronger) and minVisible is a
	# 0..1 sightline fraction, so the validator's bounds are the contract the docs describe.
	check(float(cfg["weight_centre"]) >= 0.0 and float(cfg["weight_centre"]) <= 8.0, "weightCentre is an exponent (%.2f)" % float(cfg["weight_centre"]))
	check(float(cfg["weight_visible"]) >= 0.0 and float(cfg["weight_visible"]) <= 8.0, "weightVisible is an exponent (%.2f)" % float(cfg["weight_visible"]))
	check(float(cfg["weight_open"]) >= 0.0 and float(cfg["weight_open"]) <= 8.0, "weightOpen is an exponent (%.2f)" % float(cfg["weight_open"]))
	check(float(cfg["weight_height"]) >= 0.0 and float(cfg["weight_height"]) <= 8.0, "weightHeight is an exponent (%.2f)" % float(cfg["weight_height"]))
	check(float(cfg["min_visible"]) >= 0.0 and float(cfg["min_visible"]) <= 1.0, "minVisible is a sightline fraction (%.2f)" % float(cfg["min_visible"]))
	check(float(cfg["weight_visible"]) > 0.0 and float(cfg["weight_centre"]) > 0.0, "the pick actually prefers visible / central cover")
	# target maths: half, at least one, never above the budget
	check(Destruct.target_count(0) == 0, "target_count(0) == 0")
	check(Destruct.target_count(10) == 5, "target_count(10) == 5")
	check(Destruct.target_count(3) == 2, "target_count(3) rounds up to 2")
	check(Destruct.target_count(1) == 1, "one eligible component is still one breakable")
	check(Destruct.target_count(200) <= int(cfg["per_map"]), "target_count is capped by the budget")
	# every value the validator must reject
	_expect_error(_mutated(func(d: Dictionary) -> void: d["version"] = 1), "version", "a v1 manifest")
	_expect_error(_mutated(func(d: Dictionary) -> void: d.erase("enabled")), "enabled", "a missing enabled flag")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["fraction"] = 2.0), "fraction", "fraction > 1")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["budget"] = {"perMap": 0}), "budget.perMap", "perMap 0")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["budget"] = {"perMap": 999}), "budget.perMap", "perMap over the hard cap")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["hp"] = {"min": 60, "max": 20, "volumeMin": 0.6, "volumeMax": 30.0}), "hp.min", "hp min > max")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["hp"]["volumeMin"] = 40.0), "hp.volumeMin", "hp volumeMin >= volumeMax")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["respawn"]["maxSeconds"] = 10.0), "respawn.maxSeconds", "a 10 s respawn max")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["respawn"]["minSeconds"] = 200.0; d["respawn"]["maxSeconds"] = 100.0), "respawn.minSeconds", "respawn min > max")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["colors"]["accent"] = -1), "colors.accent", "a negative accent")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["selection"].erase("minHeight")), "selection.minHeight", "a missing selection rule")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["selection"]["maxSpan"] = 99.0), "selection.maxSpan", "maxSpan out of range")
	_expect_error(_mutated(func(d: Dictionary) -> void: d["arenas"] = {}), "arenas is the M0", "the old authored-props schema")
	# a bad config at match time fails safe: the match runs with no props (never a half-applied mode)
	var saved_data: Dictionary = Destruct._data
	var saved_loaded: bool = Destruct._data_loaded
	var broken_cfg: Dictionary = data.duplicate(true)
	broken_cfg["fraction"] = 2.0
	Destruct._data = broken_cfg
	Destruct._data_loaded = true
	var safe := _match("arena", true, SEED, null, 0)
	check(safe.destruct == null and safe.solids.size() == FighterPhysics.solids_from_map(maps["arena"]).size(),
		"bad config at setup: no props, no extra solids, a normal match")
	safe.dispose()
	Destruct._data = saved_data
	Destruct._data_loaded = saved_loaded

func _mutated(f: Callable) -> Dictionary:
	var d: Dictionary = data.duplicate(true)
	f.call(d)
	return d

func _expect_error(mutated: Dictionary, needle: String, what: String) -> void:
	var errs: Array = Destruct.validate(mutated, maps)
	var joined := "\n".join(errs)
	check(joined.contains(needle), "validator rejects %s (%s)" % [what, joined])

# ============================== 2. off / no-op ==============================

func _off_checks() -> void:
	var m: Dictionary = maps["arena"]
	var parent := Node3D.new()
	root.add_child(parent)
	var base := _match("arena", false, SEED, parent, 3)
	_run_steps(base, 240)
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
	var off := _match("arena", false, SEED, parent, 3)
	_run_steps(off, 240)
	check(_state_hash(off) == base_hash, "off: same state hash as the baseline after 2 s")
	check(off.combat.rng.state == base_rng, "off: same RNG draws as the baseline")
	check(off.solids.size() == base.solids.size(), "off: same solids as the baseline")
	# mode on for a map the mode excludes: a no-op (no props, no meshes, identical match)
	var skip_id := "squeeze"
	var skip_off := _match(skip_id, false, SEED, parent, 3)
	_run_steps(skip_off, 240)
	var skip_hash := _state_hash(skip_off)
	var skip_rng := skip_off.combat.rng.state
	skip_off.dispose()
	var skip_on := _match(skip_id, true, SEED, parent, 3)
	_run_steps(skip_on, 240)
	check(skip_on.destruct == null, "on, excluded map: no Destruct")
	check(skip_on.solids.size() == FighterPhysics.solids_from_map(maps[skip_id]).size(), "on, excluded map: no extra solids")
	check(skip_on.combat.rng.state == skip_rng, "on, excluded map: no RNG draws")
	check(_state_hash(skip_on) == skip_hash, "on, excluded map: the match is identical")
	check(parent.get_child_count() == 0, "on, excluded map: no prop meshes")
	# mode on uses its own RNG: turning it on takes no CombatRng draw (a real match's weapon stream is unchanged)
	var on := _match("arena", true, SEED, parent, 3)
	var probe := _match("arena", false, SEED, null, 3)
	check(on.destruct != null and on.destruct.total() > 0, "on: props are loaded for arena")
	check(on.combat.rng.state == probe.combat.rng.state, "on: the selection takes no CombatRng draws")
	probe.dispose()
	check(on.dyn.kind == "off", "on: the mode runs a steady floor (dyn=%s)" % on.dyn.kind)
	base.dispose(); off.dispose(); on.dispose(); skip_on.dispose()
	parent.free()

# ============================== 3. selection on every arena ==============================

func _selection_checks() -> void:
	var seen := {}
	var supported := 0
	for raw_id: Variant in maps.keys():
		var id := str(raw_id)
		var map: Dictionary = maps[raw_id]
		check(Destruct.supported(id, map) == (not Destruct.NOT_SUPPORTED.has(id) and not bool(map.get("range", false)) and not bool(map.get("shrinks", false)) and not ((map.get("geometry", {}) as Dictionary).get("boxes", []) as Array).is_empty()), "%s: supported() agrees with the exclusion list" % id)
		if not Destruct.supported(id, map): continue
		supported += 1
		var styles := _styles(id)
		var analysis := Destruct.analyze(id, map, styles)
		var comps: Array = analysis["components"]
		var eligible: Array = analysis["eligible"]
		var boxes: Array = (map.get("geometry", {}) as Dictionary).get("boxes", [])
		var covered := {}
		for comp: Dictionary in comps:
			for k: int in comp["members"]: covered[k] = true
		check(covered.size() == boxes.size(), "%s: components cover every map box (%d/%d)" % [id, covered.size(), boxes.size()])
		check(eligible.size() > 0, "%s: has eligible cover components (%d of %d)" % [id, eligible.size(), comps.size()])
		var target := Destruct.target_count(eligible.size())
		var plan := Destruct.plan_for(id, map, SEED, styles)
		var plan_props: Array = plan["props"]
		check(plan_props.size() == target, "%s: %d breakables == target %d" % [id, plan_props.size(), target])
		check(int(plan["target"]) == target, "%s: plan target agrees" % id)
		check(target >= 1 and target <= int(cfg["per_map"]), "%s: target within the budget" % id)
		var frac := float(target) / float(maxi(1, eligible.size()))
		if eligible.size() >= 4 and target < int(cfg["per_map"]):
			check(frac >= 0.4 and frac <= 0.6, "%s: about half of the eligible components (%.2f)" % [id, frac])
		# the plan's components are exactly the selected eligible roots, its exclude map exactly their boxes
		var eligible_roots := {}
		for comp: Dictionary in eligible: eligible_roots[int(comp["root"])] = true
		var essential_boxes := {}
		for comp: Dictionary in analysis["essential"]:
			for k: int in comp["members"]: essential_boxes[k] = true
		var wanted_boxes := 0
		for raw: Variant in plan_props:
			var p: Dictionary = raw
			check(eligible_roots.has(int(p["root"])), "%s %s: selected root is eligible" % [id, p["id"]])
			wanted_boxes += (p["members"] as Array).size()
			for k: int in p["members"]:
				check((plan["exclude"] as Dictionary).has(k), "%s %s: member %d is excluded from the merged map" % [id, p["id"], k])
				check(not essential_boxes.has(k), "%s %s: member %d is not essential geometry" % [id, p["id"], k])
		check((plan["exclude"] as Dictionary).size() == wanted_boxes, "%s: exclude map is exactly the selected boxes" % id)
		# independent safety checks on the selected components
		for raw: Variant in plan_props:
			_safe_checks(id, map, raw as Dictionary, styles)
		# deterministic for one seed, different for another
		var again := Destruct.plan_for(id, map, SEED, styles)
		check(str(again["props"]) == str(plan["props"]) and str(again["exclude"]) == str(plan["exclude"]),
			"%s: the same seed gives the same breakables" % id)
		if eligible.size() >= 4:
			var varied := false
			for extra: int in [1, 2, 3, 7, 11]:
				var other := Destruct.plan_for(id, map, SEED + extra, styles)
				if str(other["exclude"]) != str(plan["exclude"]): varied = true; break
			check(varied, "%s: another seed gives another set of breakables" % id)
		seen[id] = true
		# the live match really swaps those boxes out of collision and builds the meshes
		var parent := Node3D.new()
		root.add_child(parent)
		var sim := _match(id, true, SEED, parent, 0)
		var d: Destruct = sim.destruct
		check(d != null, "%s: Destruct created" % id)
		if d == null:
			parent.queue_free()
			continue
		check(d.total() == target, "%s: %d live breakables (want %d)" % [id, d.total(), target])
		var base_solids := FighterPhysics.solids_from_map(map).size()
		var excluded_boxes := (plan["exclude"] as Dictionary).size()
		check(sim.solids.size() == base_solids - excluded_boxes + target,
			"%s: collision = map - selected boxes + components (%d)" % [id, sim.solids.size()])
		var breakable_solids := 0
		for s: Dictionary in sim.solids:
			if bool(s.get("breakable", false)): breakable_solids += 1
		check(breakable_solids == target, "%s: every component is a tagged solid" % id)
		check(d.mesh_count() == target and parent.get_child_count() == target, "%s: one mesh root per component" % id)
		for i in d.total():
			check(d.is_breakable(i) and d.is_breakable(str(d.props[i]["id"])) and d.is_breakable(d.props[i]["solid"]),
				"%s: component %d is breakable" % [id, i])
		sim.dispose()
		parent.queue_free()
		await process_frame
	check(supported >= 25, "the mode runs on every arena map (%d supported)" % supported)
	check(supported == Destruct.supported_ids().size(), "supported_ids() matches the analysed maps")
	check(seen.size() == supported, "every supported map was checked")
	# Arena usability regression: the old uniform pick often made the far-corner blocks (boxes 6+7) breakable while the
	# two obvious mid-field crates stayed static - exactly the "nothing is breakable" feeling. The weighted pick has to
	# choose at least one of the mid-field crates in almost every seed, and both in most.
	var arena_map: Dictionary = maps["arena"]
	var mid_plans := 0
	var both_plans := 0
	for s in 50:
		var plan := Destruct.plan_for("arena", arena_map, s, {})
		var roots: Array = []
		for raw: Variant in plan["props"]: roots.append(int((raw as Dictionary)["root"]))
		var hits := (1 if roots.has(3) else 0) + (1 if roots.has(5) else 0)
		if hits >= 1: mid_plans += 1
		if hits == 2: both_plans += 1
	check(mid_plans >= 45, "arena: a mid-field crate breaks in %d/50 seeds" % mid_plans)
	check(both_plans >= 30, "arena: both mid-field crates break in %d/50 seeds" % both_plans)
	var fixed_plan := Destruct.plan_for("arena", arena_map, SEED, {})
	var fixed_roots: Array = []
	for raw: Variant in fixed_plan["props"]: fixed_roots.append(int((raw as Dictionary)["root"]))
	check(fixed_roots == [3, 5], "arena: seed %d picks the mid-field crates [3, 5] (got %s)" % [SEED, str(fixed_roots)])

## The selected component respects the config's exclusion rules (independent of the analyser's own bookkeeping).
func _safe_checks(id: String, map: Dictionary, p: Dictionary, styles: Dictionary) -> void:
	var ext := {"minX": float(p["min_x"]), "maxX": float(p["max_x"]), "minZ": float(p["min_z"]), "maxZ": float(p["max_z"])}
	var members: Array = p["members"]
	var boxes: Array = (map.get("geometry", {}) as Dictionary).get("boxes", [])
	var solids := _box_solids(map)
	for k: int in members:
		var b: Dictionary = boxes[k]
		check(float(b["y"]) > -0.25, "%s %s: not ground (box %d)" % [id, p["id"], k])
		var st: Variant = styles.get(str(k), {})
		check(not (st is Dictionary and bool((st as Dictionary).get("hidden", false))), "%s %s: not an invisible wall" % [id, p["id"]])
	var h := float(p["h"])
	var span := maxf(float(p["w"]), float(p["d"]))
	var thin := minf(float(p["w"]), float(p["d"]))
	check(h >= 0.8 and h <= 5.5, "%s %s: height %.2f is cover-sized" % [id, p["id"], h])
	check(span <= 8.0 and thin >= 0.35 and float(p["w"]) * float(p["d"]) >= 0.5, "%s %s: footprint is cover-sized" % [id, p["id"]])
	check(float(p["hp"]) >= 1.0 and float(p["hp"]) <= 500.0, "%s %s: sane hp" % [id, p["id"]])
	check(Destruct.KINDS.has(str(p["kind"])), "%s %s: known kind" % [id, p["id"]])
	# no spawn / player start / bot spot
	for key: String in ["spawns", "bots"]:
		for raw: Variant in (map.get(key, []) as Array):
			if not (raw is Array) or (raw as Array).size() < 2: continue
			var sp: Array = raw
			if not (sp[0] is int or sp[0] is float) or not (sp[1] is int or sp[1] is float): continue
			check(_rect_dist(float(sp[0]), float(sp[1]), ext) >= float(cfg["spawn_clearance"]) - 0.001,
				"%s %s: clear of spawn %s" % [id, p["id"], str(sp)])
	var player: Variant = map.get("player")
	if player is Array and (player as Array).size() >= 2 and (player[0] is int or player[0] is float):
		check(_rect_dist(float(player[0]), float(player[1]), ext) >= float(cfg["spawn_clearance"]) - 0.001, "%s %s: clear of the player start" % [id, p["id"]])
	var geo: Dictionary = map.get("geometry", {}) if map.get("geometry") is Dictionary else {}
	for raw: Variant in (geo.get("ladders", []) as Array):
		var l: Dictionary = raw
		check(_rect_dist(float(l["x"]), float(l["z"]), ext) >= float(cfg["ladder_clearance"]) - 0.001, "%s %s: clear of a ladder" % [id, p["id"]])
	for raw: Variant in (geo.get("bouncePads", []) as Array):
		var pad: Dictionary = raw
		check(_rect_dist(float(pad["x"]), float(pad["z"]), ext) >= float(pad.get("r", 1.2)) + float(cfg["pad_clearance"]) - 0.001,
			"%s %s: clear of a bounce pad" % [id, p["id"]])
	# not structural: nothing rests on top of the component, and it is not a stair step
	var top := float(p["top"])
	for j in boxes.size():
		if members.has(j): continue
		var ob: Dictionary = boxes[j]
		var os: Dictionary = solids[j]
		if absf(float(os["bottom"]) - top) < 0.06 and float(ext["minX"]) < float(os["maxX"]) - 0.2 and float(ext["maxX"]) > float(os["minX"]) + 0.2 \
				and float(ext["minZ"]) < float(os["maxZ"]) - 0.2 and float(ext["maxZ"]) > float(os["minZ"]) + 0.2:
			check(false, "%s %s: nothing rests on top (box %d does)" % [id, p["id"], j])
	var rb: Dictionary = boxes[int(p["root"])]
	for j in boxes.size():
		if members.has(j): continue
		var o: Dictionary = boxes[j]
		if absf(float(o["w"]) - float(rb["w"])) > 0.05 or absf(float(o["d"]) - float(rb["d"])) > 0.05: continue
		var dtop := absf(float(o["y"]) + float(o["h"]) - top)
		if dtop < 0.2 or dtop > 0.9: continue
		var adj_x := absf(absf(float(o["x"]) - float(rb["x"])) - float(rb["w"])) < 0.06 and absf(float(o["z"]) - float(rb["z"])) < 0.06
		var adj_z := absf(absf(float(o["z"]) - float(rb["z"])) - float(rb["d"])) < 0.06 and absf(float(o["x"]) - float(rb["x"])) < 0.06
		if adj_x or adj_z: check(false, "%s %s: not a stair step (box %d)" % [id, p["id"], j])
	# boundary / ring-out wall: a thin or tall box hanging over the void would fail the floor ring; cover must pass it
	if thin <= 1.6 or h >= 3.0:
		check(_margin_supported(solids, ext, float(p["bottom"]), float(cfg["edge_margin"])), "%s %s: not a boundary wall" % [id, p["id"]])
	# usability: the plan records why the component was picked, and an independent sightline from standable floor reaches
	# it (a fully enclosed box is unshootable cover and must never be selected).
	check(p.has("visible") and float(p["visible"]) > 0.0, "%s %s: visible from the playable floor (%.2f)" % [id, p["id"], float(p.get("visible", 0.0))])
	check(_can_see_from_floor(map, p), "%s %s: an independent sightline from the floor reaches it" % [id, p["id"]])
	check(int(p.get("open", -1)) >= 0 and int(p.get("open", -1)) <= 4, "%s %s: free-standing sides recorded (%s)" % [id, p["id"], str(p.get("open", -1))])
	check(float(p.get("score", 0.0)) > 0.0, "%s %s: usability score recorded" % [id, p["id"]])

func _rect_dist(px: float, pz: float, ext: Dictionary) -> float:
	var dx := maxf(maxf(float(ext["minX"]) - px, 0.0), px - float(ext["maxX"]))
	var dz := maxf(maxf(float(ext["minZ"]) - pz, 0.0), pz - float(ext["maxZ"]))
	return sqrt(dx * dx + dz * dz)

func _has_floor(solids: Array, x: float, z: float, y: float) -> bool:
	for b: Dictionary in solids:
		if x < float(b["minX"]) - 1e-6 or x > float(b["maxX"]) + 1e-6: continue
		if z < float(b["minZ"]) - 1e-6 or z > float(b["maxZ"]) + 1e-6: continue
		if absf(float(b["top"]) - y) <= 0.25: return true
	return false

func _margin_supported(solids: Array, ext: Dictionary, y: float, margin: float) -> bool:
	var min_x := float(ext["minX"]); var max_x := float(ext["maxX"])
	var min_z := float(ext["minZ"]); var max_z := float(ext["maxZ"])
	var mx := (min_x + max_x) * 0.5
	var mz := (min_z + max_z) * 0.5
	for q: Array in [[min_x - margin, mz], [max_x + margin, mz], [mx, min_z - margin], [mx, max_z + margin],
			[min_x - 0.6, min_z - 0.6], [max_x + 0.6, min_z - 0.6], [min_x - 0.6, max_z + 0.6], [max_x + 0.6, max_z + 0.6]]:
		if not _has_floor(solids, float(q[0]), float(q[1]), y): return false
	return true

## Independent usability check: from one of 8 compass directions on two rings around the component, at eye height above
## the floor at its base, the first solid hit along a ray to the component is the component itself. This is re-implemented
## here (never calling Destruct's own visibility sampler) so the analyser cannot mark an enclosed box as visible.
func _can_see_from_floor(map: Dictionary, p: Dictionary) -> bool:
	var solids := _box_solids(map)
	var members: Array = p["members"]
	var min_x := float(p["min_x"]); var max_x := float(p["max_x"])
	var min_z := float(p["min_z"]); var max_z := float(p["max_z"])
	var bottom := float(p["bottom"]); var top := float(p["top"])
	var cx := (min_x + max_x) * 0.5
	var cz := (min_z + max_z) * 0.5
	var span := maxf(max_x - min_x, max_z - min_z)
	var ty := clampf(bottom + 1.1, bottom + 0.15 * maxf(top - bottom, 0.2), top - 0.06)
	for k in 8:
		var ang := TAU * float(k) / 8.0
		for r: float in [span * 0.5 + 1.3, span * 0.5 + 3.2]:
			var px := cx + cos(ang) * r
			var pz := cz + sin(ang) * r
			if not _has_floor(solids, px, pz, bottom): continue
			var py := bottom + 1.35
			var inside := false
			for i in solids.size():
				if members.has(i): continue
				var b: Dictionary = solids[i]
				if px > float(b["minX"]) + 0.01 and px < float(b["maxX"]) - 0.01 and pz > float(b["minZ"]) + 0.01 \
						and pz < float(b["maxZ"]) - 0.01 and py > float(b["bottom"]) + 0.01 and py < float(b["top"]) - 0.01:
					inside = true
					break
			if inside: continue
			if members.has(_first_solid(solids, px, py, pz, cx, ty, cz)): return true
	return false

## Index of the first solid hit along the segment, -1 for a miss.
func _first_solid(solids: Array, ox: float, oy: float, oz: float, tx: float, ty: float, tz: float) -> int:
	var dx := tx - ox; var dy := ty - oy; var dz := tz - oz
	var length := sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1e-4: return -1
	dx /= length; dy /= length; dz /= length
	var best := INF
	var best_i := -1
	for i in solids.size():
		var s: Dictionary = solids[i]
		var t: float = Weapons.ray_box(ox, oy, oz, dx, dy, dz, float(s["minX"]), float(s["bottom"]), float(s["minZ"]),
			float(s["maxX"]), float(s["top"]), float(s["maxZ"]))
		if t >= 0.0 and t < best: best = t; best_i = i
	if best_i < 0 or best > length + 0.5: return -1
	return best_i

# ============================== 4b. hit feedback / melee / flame ==============================

## Every damage path has to tell the player something: a non-breaking hit shows chips + a tap sound (prop_hit) and a
## visible damage tier, melee (the starting spatula) chips cover, and flame damages it. This is what the owner was missing
## ("still not breakable" was partly "no reaction at all until the component finally broke").
func _feedback_checks() -> void:
	var sim := _match("arena", true, 9010, null, 0)
	var d: Destruct = sim.destruct
	var pi := -1
	for i in d.total():
		if float(d.props[i]["max_hp"]) >= 30.0: pi = i; break
	check(pi >= 0, "feedback: a big component exists on arena")
	if pi >= 0:
		var p: Dictionary = d.props[pi]
		var hp0 := float(p["hp"])
		sim.combat.events.clear()
		var shot := _fire_shots(sim, d, pi, 1)
		check(bool(shot.get("ok", false)) and not bool(shot.get("broke", true)) and float(p["hp"]) < hp0,
			"feedback: one shot chips but does not break (%.0f -> %.0f)" % [hp0, float(p["hp"])])
		check(_count_event(sim, "prop_hit") >= 1, "feedback: a non-breaking hit emits prop_hit")
		check(_has_event(sim, "sfx"), "feedback: a non-breaking hit emits a tap sound")
		var ev := _last_event(sim, "prop_hit")
		check(float(ev.get("frac", -1.0)) > 0.0 and float(ev.get("dmg", 0.0)) > 0.0 and ev.has("tier"),
			"feedback: prop_hit carries damage / remaining fraction / tier")
		check(int(p["damage"]) == 0, "feedback: one chip is still the healthy tier")
		d.break_hit(pi, float(p["max_hp"]) * 0.35)                 # ~2/3 hp left: chipped
		check(int(p["damage"]) == 1, "feedback: damage tier 1 at ~2/3 hp")
		d.break_hit(pi, float(p["max_hp"]) * 0.35)                 # ~1/3 hp left: cracked
		check(int(p["damage"]) == 2, "feedback: damage tier 2 at ~1/3 hp")
		check(not bool(p["broken"]), "feedback: the cracked component still stands")
		check(d.break_hit(pi, 9999.0), "feedback: the cracked component breaks")
		d.step(float(cfg["respawn_max"]) + 1.0)
		check(not bool(p["broken"]) and int(p["damage"]) == 0, "feedback: a respawned component is healthy again")
	sim.dispose()
	await process_frame
	# Melee: the classic match starts with the spatula, so melee has to chip cover (MatchSim.sweep -> Destruct.melee_sweep).
	var msim := _match("arena", true, 9011, null, 0)
	var md: Destruct = msim.destruct
	var mi := -1
	for i in md.total():
		if _pose_melee(msim, md, i): mi = i; break
	check(mi >= 0, "melee: a component is reachable on foot")
	if mi >= 0:
		var mp: Dictionary = md.props[mi]
		var mhp := float(mp["hp"])
		msim.combat.events.clear()
		msim.sweep()
		var after := float(mp["hp"])
		check(after < mhp, "melee: a spatula swing chips the component (%.0f -> %.0f)" % [mhp, after])
		msim.sweep()                                               # same swing: no second hit
		check(absf(float(mp["hp"]) - after) < 0.001, "melee: one swing hits the same component once")
		check(_count_event(msim, "prop_hit") + _count_event(msim, "break") >= 1, "melee: the melee hit emits feedback (prop_hit/break)")
	msim.dispose()
	await process_frame
	# Flame: the fire cone damages cover (weapons._flame -> Destruct.flame_hit).
	var lsim := _match("arena", true, 9012, null, 0)
	var ld: Destruct = lsim.destruct
	var li := -1
	for i in ld.total():
		if bool(_stand_point(lsim, ld, i).get("ok", false)): li = i; break
	check(li >= 0, "flame: a component is reachable by a flame ray")
	if li >= 0:
		var lp: Dictionary = ld.props[li]
		var lhp := float(lp["hp"])
		var spot := _stand_point(lsim, ld, li)
		var lf: FighterState = lsim.player
		_pose(lf, float(spot["x"]), float(spot["z"]), spot["aim"], float(spot["y"]))
		lf.weapon = "flame"; lf.slot = -1
		lsim.combat.events.clear()
		lsim.combat.weapons.fire_gun(lf, "flame", spot["aim"])
		check(float(lp["hp"]) < lhp, "flame: the fire burst chips a breakable (%.1f -> %.1f)" % [lhp, float(lp["hp"])])
	lsim.dispose()
	await process_frame

# ============================== 4. behaviour ==============================

func _behaviour_checks() -> void:
	var maps_to_test: Array = ["arena", "temple", "capsule", "haunted", "farm", "brawlpit"]
	for id: String in maps_to_test:
		await _behaviour_one(id)
	# the rocket path once (the shared explode() is what rockets call, but prove the launcher drives it too)
	var parent := Node3D.new()
	root.add_child(parent)
	var rsim := _match("arena", true, 777, parent, 0)
	var rd: Destruct = rsim.destruct
	var ri := -1
	var best_hp := INF
	for i in rd.total():
		var spot := _stand_point(rsim, rd, i)
		if bool(spot.get("ok", false)) and float(rd.props[i]["hp"]) < best_hp:
			best_hp = float(rd.props[i]["hp"]); ri = i
	check(ri >= 0, "rocket: a clear firing spot exists")
	if ri >= 0:
		var spot2 := _stand_point(rsim, rd, ri)
		var rf: FighterState = rsim.player
		_pose(rf, float(spot2["x"]), float(spot2["z"]), spot2["aim"], float(spot2["y"]))
		var broke := false
		for shot in 3:
			rsim.combat.events.clear()
			rsim.combat.weapons.launch_rocket(rf, "rocket", spot2["aim"])
			for k in 360:
				rsim.step(1.0 / 120.0)
				if _has_event(rsim, "explode") and k > 2: break
			if bool(rd.props[ri]["broken"]): broke = true; break
			_pose(rf, float(spot2["x"]), float(spot2["z"]), spot2["aim"], float(spot2["y"]))
		check(broke, "rocket: launched rockets break the component they hit")
		check(_has_event(rsim, "explode"), "rocket: the rocket exploded")
	rsim.dispose()
	parent.queue_free()
	await process_frame

func _behaviour_one(id: String) -> void:
	var map: Dictionary = maps[id]
	var parent := Node3D.new()
	root.add_child(parent)
	var sim := _match(id, true, 9001, parent, 0)
	var d: Destruct = sim.destruct
	check(d != null and d.total() > 0, "%s: mode on loads breakables" % id)
	if d == null:
		parent.queue_free()
		return
	var base_solids := FighterPhysics.solids_from_map(map).size()
	var excluded := d.merge_exclude.size()
	check(sim.solids.size() == base_solids - excluded + d.total(), "%s: map boxes replaced by component solids" % id)
	# collision: a fighter walking into a ground-level component is stopped by it
	var f: FighterState = sim.player
	for i in d.total():
		var gp: Dictionary = d.props[i]
		if float(gp["bottom"]) > 0.35: continue
		var gs: Dictionary = gp["solid"]
		var walk_x := (float(gs["minX"]) + float(gs["maxX"])) * 0.5
		var walk_z := float(gs["maxZ"]) + float(FighterPhysics.R) + 1.2
		f.phys.place(walk_x, 0.0, walk_z)
		f.phys.grounded = true
		for k in 90:
			f.phys.wish_x = 0.0
			f.phys.wish_z = -1.0
			f.phys.step(1.0 / 120.0, sim.solids, f)
		check(f.phys.pz >= float(gs["maxZ"]) + FighterPhysics.R - 0.06, "%s: a fighter cannot walk through a component" % id)
		break
	# hitscan: find a component with a clear standing shot and break it
	var hit_i := -1
	for i in d.total():
		if bool(_stand_point(sim, d, i).get("ok", false)): hit_i = i; break
	check(hit_i >= 0, "%s: a component is reachable by hitscan" % id)
	if hit_i < 0:
		sim.dispose(); parent.queue_free(); return
	var hp_i: Dictionary = d.props[hit_i]
	var start_hp := float(hp_i["hp"])
	var fire := _fire_prop(sim, d, hit_i)
	check(bool(fire.get("ok", false)), "%s: hitscan breaks a component (%s)" % [id, fire.get("why", "")])
	if bool(fire.get("ok", false)):
		check(int(fire["shots"]) >= 2 and int(fire["shots"]) <= 24, "%s: broke after %d hits" % [id, int(fire["shots"])])
		check(float(hp_i["hp"]) <= 0.0, "%s: hp reached 0" % id)
		check(not d.is_breakable(hit_i), "%s: a broken component is not breakable" % id)
		check(sim.solids.find(hp_i["solid"]) < 0, "%s: the broken component left sim.solids" % id)
		check(_has_event(sim, "break") and _has_event(sim, "sfx"), "%s: break + sound events fired" % id)
		check(d.mesh_count() == d.total(), "%s: the broken mesh is hidden/recycled, not freed" % id)
		var mesh: Variant = hp_i["mesh"]
		check(mesh != null and is_instance_valid(mesh) and not (mesh as Node3D).visible, "%s: the broken mesh is hidden" % id)
		var delay := d.respawn_delay(hit_i)
		check(delay >= float(cfg["respawn_min"]) - 0.01 and delay <= float(cfg["respawn_max"]) + 0.01,
			"%s: respawn scheduled in %.1f s (%.0f..%.0f)" % [id, delay, float(cfg["respawn_min"]), float(cfg["respawn_max"])])
		# broken components stay broken through the next second of real sim steps
		_run_steps(sim, 120)
		check(bool(hp_i["broken"]) and d.pending_count() >= 1, "%s: a broken component stays broken" % id)
		# simulate the timer: not before the delay, then restored with collision + mesh
		var left := d.respawn_delay(hit_i)
		check(left > 0.0, "%s: still counting down" % id)
		d.step(maxf(0.0, left - 0.5))
		check(bool(hp_i["broken"]), "%s: does not respawn early" % id)
		d.step(0.6)
		check(not bool(hp_i["broken"]), "%s: respawns at its randomised delay" % id)
		check(sim.solids.find(hp_i["solid"]) >= 0 and d.is_breakable(hit_i), "%s: collision + breakable restored" % id)
		check(float(hp_i["hp"]) == float(hp_i["max_hp"]) and start_hp > 0.0, "%s: hp restored" % id)
		check(_has_event(sim, "prop_respawn") and _has_event(sim, "sfx"), "%s: respawn event fired" % id)
		var mesh2: Variant = hp_i["mesh"]
		check(mesh2 != null and is_instance_valid(mesh2) and (mesh2 as Node3D).visible, "%s: mesh visible again" % id)
		var nodes: Array = hp_i["mesh_nodes"]
		check((nodes[0] as MeshInstance3D).transparency > 0.0, "%s: respawn starts with a materialise fade" % id)
		var tw: Variant = hp_i["tween"]
		if tw != null and tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).custom_step(1.0)
		check((nodes[0] as MeshInstance3D).transparency <= 0.01, "%s: the fade completes to fully opaque" % id)
		check(d.rubble_visible_count() == 0, "%s: rubble hidden after respawn" % id)
		# break it again straight away: a respawned component can be broken again
		check(d.break_hit(hit_i, 99999.0), "%s: a respawned component can be broken again" % id)
		d.step(float(cfg["respawn_max"]) + 1.0)
		check(not bool(hp_i["broken"]), "%s: its second respawn works too" % id)
	# explosion: the real explode() path breaks a nearby component
	var blast_i := -1
	for i in d.total():
		if bool(d.props[i]["broken"]): continue
		if blast_i < 0 or float(d.props[i]["hp"]) < float(d.props[blast_i]["hp"]): blast_i = i
	if blast_i >= 0:
		var bp2: Dictionary = d.props[blast_i]
		sim.combat.events.clear()
		sim.combat.weapons.explode(float(bp2["x"]), float(bp2["y"]) + 0.6, float(bp2["z"]), sim.player, sim.combat.wdata("rocket"))
		check(bool(bp2["broken"]), "%s: an explosion breaks a nearby component" % id)
		check(_count_event(sim, "break") >= 1, "%s: the explosion fired a break event" % id)
		d.step(float(cfg["respawn_max"]) + 1.0)
	# blocked respawn: a fighter standing in the box postpones it, then it comes back when they step out
	var block_i := -1
	for i in d.total():
		if not bool(d.props[i]["broken"]): block_i = i; break
	if block_i >= 0:
		var bp: Dictionary = d.props[block_i]
		check(d.break_hit(block_i, 99999.0), "%s: blocked-respawn component breaks" % id)
		f.phys.place(float(bp["x"]), float(bp["bottom"]) + 0.1, float(bp["z"]))
		f.phys.grounded = true
		d.step(float(cfg["respawn_max"]) + 1.0)
		check(bool(bp["broken"]), "%s: a respawn is postponed while a fighter stands in it" % id)
		check(absf(d.respawn_delay(block_i) - float(cfg["retry"])) < 0.05, "%s: postponed by retrySeconds" % id)
		f.phys.place(float(map.get("player", [0, 0])[0]), 0.0, float(map.get("player", [0, 0])[1]))
		d.step(float(cfg["retry"]) + 0.2)
		check(not bool(bp["broken"]), "%s: respawns once the fighter stepped out" % id)
	# randomisation: every break gets its own 100-140 s delay (not metronomic)
	var delays: Array = []
	var want_breaks := mini(4, d.total())
	var broke := 0
	for i in d.total():
		if broke >= want_breaks: break
		if bool(d.props[i]["broken"]):
			d.step(float(cfg["respawn_max"]) + 1.0)
		if d.break_hit(i, 99999.0, [0.0, 0.0, 1.0]):
			delays.append(snappedf(d.respawn_delay(i), 0.0001))
			broke += 1
	var distinct := {}
	for x: float in delays: distinct[x] = true
	check(broke == want_breaks, "%s: %d components broke for the delay check" % [id, broke])
	if broke >= 2:
		check(distinct.size() >= 2, "%s: respawn delays are randomised, not metronomic (%d distinct)" % [id, distinct.size()])
	# leaks: several break -> respawn cycles keep the node count flat
	var cycle_sim := _match(id, true, 9002, parent, 0)
	var cd: Destruct = cycle_sim.destruct
	var cyc := 0
	for i in cd.total():
		var spot := _stand_point(cycle_sim, cd, i)
		if bool(spot.get("ok", false)): cyc = i; break
	# one mesh root per component plus at most one reused rubble node for the component the cycles break
	var expected_nodes := parent.get_child_count() + (1 if cyc >= 0 else 0)
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for k in 3:
		check(cd.break_hit(cyc, 99999.0), "%s: cycle %d breaks" % [id, k + 1])
		cd.step(float(cfg["respawn_max"]) + 1.0)
		check(not bool(cd.props[cyc]["broken"]), "%s: cycle %d respawns" % [id, k + 1])
	check(cd.mesh_count() == cd.total(), "%s: every mesh recycled across the cycles" % id)
	check(cd.rubble_visible_count() == 0, "%s: no rubble visible after the cycles" % id)
	check(cd.rubble_count() <= cd.total(), "%s: rubble nodes are reused, not leaked" % id)
	check(parent.get_child_count() == expected_nodes, "%s: no node leak through break/respawn cycles (%d -> %d, expected %d)" % [id, expected_nodes, parent.get_child_count(), expected_nodes])
	await process_frame
	var orphans_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphans_after - orphans_before <= 2, "%s: no orphan-node leak through the cycles (%d -> %d)" % [id, orphans_before, orphans_after])
	cycle_sim.dispose()
	sim.dispose()
	parent.queue_free()
	await process_frame

# ============================== 5. world wiring ==============================

func _world_props(world: Node) -> int:
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
	check(_world_props(off) == 0, "world off: no prop meshes under the map")
	check(off._mode_l != null and not off._mode_l.text.contains("Breakables"), "world off: the mode line does not mention breakables")
	off.queue_free()
	await process_frame
	# Enablement through the REAL wizard path: the Arena page's Breakable props row writes Settings "destructible"; the
	# world launched from the wizard's Start (main.gd play_offline -> wizard.save()) reads that setting. The wizard is
	# loaded at runtime so this test script compiles before the UI autoloads are up.
	st.set_value("destructible", false)
	var wizard: Node = (load("res://ui/setup_wizard.gd") as Script).new()
	root.add_child(wizard)
	await process_frame
	wizard.load_settings()
	wizard.set_mode("classic")
	wizard.set_map("arena")
	wizard.set_destruct("on")
	wizard.save()
	check(bool(st.get_value("destructible")), "enablement: the wizard Breakable props toggle writes Settings destructible")
	check(str(st.get_value("offline_map")) == "arena", "enablement: the wizard saved arena")
	check(bool(wizard.destruct_arena_ok()), "enablement: the arena is offered the Breakable props row")
	wizard.queue_free()
	await process_frame
	var on: Node = load("res://world/world.tscn").instantiate()
	on.map_id = str(st.get_value("offline_map")); on.mode_id = str(st.get_value("mode"))
	on.auto_run = false; on.bot_count = 0; on.dyn_choice = "off"; on.rng_seed = 4242
	root.add_child(on)
	await process_frame
	check(on.sim.destruct != null, "enablement: the world reads the wizard's Settings and turns the mode on")
	var analysis := Destruct.analyze("arena", maps["arena"], _styles("arena"))
	var want := Destruct.target_count((analysis["eligible"] as Array).size())
	check(on.sim.destruct != null and on.sim.destruct.total() == want, "world on: %d breakables loaded" % want)
	check(_world_props(on) == want, "world on: one prop mesh root per component under the map")
	check(on._mode_l != null and on._mode_l.text.contains("Breakables") and on._mode_l.text.contains("%d/%d" % [want, want]),
		"world on: the HUD mode line shows the breakable count (%s)" % (on._mode_l.text if on._mode_l else ""))
	check(on.sim.destruct.merged_pruned, "world on: the merged map meshes were rebuilt without the breakable boxes")
	var base_solids := FighterPhysics.solids_from_map(maps["arena"]).size()
	check(on.sim.solids.size() == base_solids - on.sim.destruct.merge_exclude.size() + want, "world on: collision matches the swapped boxes")
	# THE REAL MATCH PATH: the world's own player fires the real gun at EVERY selected component until it breaks. This is
	# the end-to-end proof for "still not breakable": plan -> merged mesh prune -> tagged solids -> the gun's hit hook ->
	# solid removed + mesh hidden + presentation event + HUD count down.
	var sim: MatchSim = on.sim
	var d: Destruct = on.sim.destruct
	var fired := 0
	for i in d.total():
		var spot := _stand_point(sim, d, i)
		check(bool(spot.get("ok", false)), "world on: component %d has a clear firing spot" % i)
		if not bool(spot.get("ok", false)): continue
		var f: FighterState = sim.player
		var p: Dictionary = d.props[i]
		var shots := 0
		while not bool(p["broken"]) and shots < 40:
			_pose(f, float(spot["x"]), float(spot["z"]), spot["aim"], float(spot["y"]))
			sim.combat.weapons.fire_gun(f, AK, spot["aim"])
			shots += 1
		check(bool(p["broken"]), "world on: the player's gun breaks component %d (%d shots)" % [i, shots])
		check(not bool(p["broken"]) or sim.solids.find(p["solid"]) < 0, "world on: component %d leaves the live collision" % i)
		var mesh: Variant = p["mesh"]
		check(mesh != null and is_instance_valid(mesh) and not (mesh as Node3D).visible, "world on: component %d mesh hidden" % i)
		fired += 1
		on.present(0.0)
		check(int(on.counts.get("break", 0)) >= fired, "world on: break %d reaches the presentation layer" % fired)
		check(int(on.counts.get("sfx", 0)) >= fired, "world on: break sounds reach the audio hook")
	check(fired == want, "world on: the player broke all %d selected components" % want)
	await process_frame
	check(on._mode_l != null and on._mode_l.text.contains("Breakables 0/%d" % want),
		"world on: the HUD counts the breakables left (%s)" % (on._mode_l.text if on._mode_l else ""))
	# Respawn through the fixed-step path MatchSim.step calls.
	on.sim.destruct.step(float(cfg["respawn_max"]) + 1.0)
	on.present(0.0)
	await process_frame
	check(on.sim.destruct.pending_count() == 0 and on.sim.destruct.broken_count() == 0, "world on: every component respawned")
	check(int(on.counts.get("prop_respawn", 0)) >= want, "world on: every respawn reaches the presentation layer")
	check(on._mode_l.text.contains("Breakables %d/%d" % [want, want]), "world on: the HUD count is back to full (%s)" % on._mode_l.text)
	# A non-breaking gun hit on the real path must also reach the presentation layer (chips + tap sound).
	var chip := _fire_shots(sim, d, 0, 1)
	check(bool(chip.get("ok", false)) and not bool(chip.get("broke", true)), "world on: one gun shot chips a component")
	on.present(0.0)
	check(int(on.counts.get("prop_hit", 0)) >= 1, "world on: prop_hit reaches the presentation layer (chips + tap)")
	await process_frame
	on.load_map("arena")
	await process_frame
	check(on.sim.destruct != null and on.sim.destruct.total() == want and on.sim.destruct.broken_count() == 0, "world on: load_map rebuilds every component fresh")
	check(_world_props(on) == want, "world on: load_map shows every mesh again")
	check(on.sim.solids.size() == base_solids - on.sim.destruct.merge_exclude.size() + want, "world on: load_map restores component solids")
	check(on.sim.destruct.merged_pruned, "world on: load_map prunes the merged meshes again")
	on.queue_free()
	await process_frame
	# --destruct override (the CLI flag the setup wizard / test runners use)
	st.set_value("destructible", false)
	var forced: Node = load("res://world/world.tscn").instantiate()
	forced.map_id = "arena"; forced.auto_run = false; forced.bot_count = 0; forced.dyn_choice = "off"; forced.destruct_choice = "on"; forced.rng_seed = 4242
	root.add_child(forced)
	await process_frame
	check(forced.sim.destruct != null and forced.sim.destruct.total() == want, "--destruct=on forces the mode on")
	forced.queue_free()
	await process_frame
	# offline gating: the Practice Range never gets props, even with the setting on
	var practice: Node = load("res://world/world.tscn").instantiate()
	practice.map_id = "practice"; practice.mode_id = "practice"; practice.auto_run = false; practice.bot_count = 0; practice.dyn_choice = "off"
	root.add_child(practice)
	await process_frame
	check(practice.sim.destruct == null, "world gate: the Practice Range ignores the mode")
	check(_world_props(practice) == 0, "world gate: no prop meshes on the range")
	practice.queue_free()
	await process_frame
	# offline gating: build mode (Sandbox) never gets props
	var sandbox: Node = load("res://world/world.tscn").instantiate()
	sandbox.build_mode = true; sandbox.auto_run = false; sandbox.bot_count = 0; sandbox.dyn_choice = "off"
	root.add_child(sandbox)
	await process_frame
	check(sandbox.sim.destruct == null, "world gate: the Sandbox ignores the mode")
	sandbox.queue_free()
	await process_frame
	# Honest zero state: the setting is on but the level type has no breakables, so the HUD says "Breakables: 0" instead of
	# silently pretending the mode is active.
	st.set_value("destructible", true)
	var none: Node = load("res://world/world.tscn").instantiate()
	none.map_id = "squeeze"; none.mode_id = "classic"; none.auto_run = false; none.bot_count = 0; none.dyn_choice = "off"
	root.add_child(none)
	await process_frame
	check(none.sim.destruct == null, "world zero: a shrinking-floor level has no breakables")
	check(none._mode_l != null and none._mode_l.text.contains("Breakables") and none._mode_l.text.contains("0"),
		"world zero: the HUD says Breakables: 0 (%s)" % (none._mode_l.text if none._mode_l else ""))
	none.queue_free()
	st.reset("destructible")
	await process_frame
