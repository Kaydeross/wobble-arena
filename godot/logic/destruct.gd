class_name Destruct
extends RefCounted
## Milestone M0 of the optional destructible environment mode (docs/DESTRUCTIBLE.md): breakable crates and barricades
## added to three arenas, OFFLINE ONLY and off by default.
##
## A prop is just a normal `sim.solids` box tagged `{breakable, prop}` with a little bookkeeping around it: hit points, a
## mesh, and a pooled-debris "break" event. Nothing about the rest of the simulation changes when the mode is off (no
## solids, no meshes, no RNG draws): `MatchSim.setup` only creates a Destruct when `MatchSim.destructible` is true.
##
## Authoring: godot/data/extra/destructible.json (Godot-side overlay, never shared/*.json). Only arenas listed there get
## props, so the mode is opt-in per arena and every other arena is untouched. `validate()` checks the whole overlay and
## `validate_arena()` re-checks one arena at match setup (bad data is reported and the arena gets no props, never a bad
## match). See tools/test-godot-destruct.js for the end-to-end checks.
##
## Runtime API (weapons / explosions / tests):
##   setup(sim, map_id, parent)  append the arena's solids + build one mesh per prop (never rebuilds the map)
##   ray_hit(...)                nearest breakable along a ray: [distance, prop index] (empty = miss)
##   break_hit(i, dmg, dir)      apply damage; true when the prop broke on this hit
##   break_blast(x, y, z, rad, dmg)  explosion: damage every prop in the radius with the usual falloff
##   is_breakable(x) / props / broken_count() / remaining() / find_prop(...)  queries for tests and impact code

const DATA_PATH := "res://data/extra/destructible.json"
const KINDS := ["crate", "barricade"]
const VERSION := 1
## The mode's own budget (docs/GRAPHICS.md: props cost one draw each and cast no shadows; 24-40 per arena is safe).
const MAX_TOTAL := 40
const MAX_PER_ARENA := 12
## Authoring rules (validate_arena): clear of the points the match uses, and never hanging over the void.
const SPAWN_CLEARANCE := 2.0
const LADDER_CLEARANCE := 1.5
const PAD_CLEARANCE := 0.8
const CRATE_CLEARANCE := 1.5
const EDGE_MARGIN := 0.9
const OVERLAP_SLOP := 0.15
const PROP_SLOP := 0.25
## Arenas the mode never runs on (shrinking floors, the range, the sandbox and the generated Arcade sites).
const NOT_SUPPORTED := ["custom", "test", "practice", "pillars", "shrink", "squeeze"]
## Meshes per prop: body + trim/lid. Two draw calls, no shadow casting, one shared material per colour.
const RUBBLE_LIFT := 0.018

## One entry per authored prop:
##   {id, kind, x, y, z, w, h, d, hp, max_hp, color, solid, mesh, rubble, broken}
var props: Array = []
var solids: Array = []          ## the live sim.solids array (same reference, so a break is seen by every query)
var events: Array = []          ## the combat event list (same reference); breaks append "break" + "sfx" events
var parent: Node3D = null       ## where prop meshes live (the built MapNode); null = logic only (headless tests)
var arena := ""
var _broken := 0
var _mats := {}                 ## colour -> body material (shared by every prop that uses it)
var _trim_mats := {}            ## colour -> trim material
var _rubble_mats := {}          ## colour -> flat rubble material

static var _data: Dictionary = {}
static var _data_loaded := false

# ============================== static authoring data ==============================

## The overlay (cached after the first read). {} when the file is missing or malformed.
static func load_data() -> Dictionary:
	if _data_loaded: return _data
	_data_loaded = true
	var parsed: Variant = Combat.read_json(DATA_PATH)
	_data = parsed if parsed is Dictionary else {}
	return _data

## True when the overlay authors breakable props for this arena.
static func has_arena(map_id: String) -> bool:
	return (load_data().get("arenas", {}) as Dictionary).has(map_id)

## The arena ids the overlay authors props for, in file order.
static func arena_ids() -> Array:
	return (load_data().get("arenas", {}) as Dictionary).keys()

## The mode's budget (the file may lower it, never raise it above the hard caps).
static func budget_of(data: Dictionary = {}) -> Dictionary:
	var d := data if not data.is_empty() else load_data()
	var b: Dictionary = d.get("budget", {}) if d.get("budget") is Dictionary else {}
	return {
		"total": mini(int(b.get("total", MAX_TOTAL)), MAX_TOTAL),
		"perArena": mini(int(b.get("perArena", MAX_PER_ARENA)), MAX_PER_ARENA),
	}

## Validate the whole overlay against the shipped maps dictionary (id -> map). Returns every problem as a string
## (empty = valid). Used by the test runner; `setup` re-checks only the arena it is loading.
static func validate(data: Dictionary, maps: Dictionary) -> Array:
	var errs: Array = []
	if int(data.get("version", 0)) != VERSION:
		errs.append("version must be %d (got %s)" % [VERSION, data.get("version")])
	if not (data.get("arenas") is Dictionary) or (data.get("arenas") as Dictionary).is_empty():
		errs.append("arenas must be a non-empty dictionary")
		return errs
	var budget := budget_of(data)
	var arenas: Dictionary = data["arenas"]
	var total := 0
	for raw_id: Variant in arenas:
		var id := str(raw_id)
		var entry: Variant = arenas[raw_id]
		if not (entry is Dictionary):
			errs.append("%s: arena entry must be a dictionary" % id)
			continue
		var map: Variant = maps.get(id)
		if not (map is Dictionary) or (map as Dictionary).is_empty():
			errs.append("%s: unknown arena id (not in maps.json)" % id)
			continue
		var props: Variant = (entry as Dictionary).get("props", [])
		if not (props is Array):
			errs.append("%s: props must be an array" % id)
			continue
		total += (props as Array).size()
		errs.append_array(validate_arena(id, entry as Dictionary, map as Dictionary, int(budget["perArena"])))
	if total > int(budget["total"]):
		errs.append("budget: %d props total, max %d" % [total, int(budget["total"])])
	return errs

## Validate every prop of one arena against that map's own data. `per_cap` is the per-arena budget.
static func validate_arena(map_id: String, entry: Dictionary, map: Dictionary, per_cap := MAX_PER_ARENA) -> Array:
	var errs: Array = []
	if NOT_SUPPORTED.has(map_id) or bool(map.get("range", false)) or bool(map.get("shrinks", false)):
		errs.append("%s: the destructible mode is not supported on this arena" % map_id)
	var props: Variant = entry.get("props", [])
	if not (props is Array):
		errs.append("%s: props must be an array" % map_id)
		return errs
	var list: Array = props
	if list.is_empty():
		errs.append("%s: no props authored" % map_id)
		return errs
	if list.size() > per_cap:
		errs.append("%s: %d props, max %d per arena" % [map_id, list.size(), per_cap])
	var map_solids := _solids_of(map)
	var spawns: Array = []
	for sp: Variant in (map.get("spawns", []) as Array):
		if sp is Array and (sp as Array).size() >= 2: spawns.append([float(sp[0]), float(sp[1])])
	for sp: Variant in (map.get("bots", []) as Array):
		if sp is Array and (sp as Array).size() >= 2: spawns.append([float(sp[0]), float(sp[1])])
	var player: Variant = map.get("player")
	if player is Array and (player as Array).size() >= 2: spawns.append([float(player[0]), float(player[1])])
	var ladders: Array = ((map.get("geometry", {}) as Dictionary).get("ladders", []) as Array)
	var pads: Array = ((map.get("geometry", {}) as Dictionary).get("bouncePads", []) as Array)
	var drops: Array = map.get("drops", []) if map.get("drops") is Array else []
	var seen := {}
	var placed: Array = []      ## earlier valid boxes of this arena, for prop-vs-prop overlap
	for i in list.size():
		var raw: Variant = list[i]
		var tag := "%s props[%d]" % [map_id, i]
		if not (raw is Dictionary):
			errs.append(tag + ": must be a dictionary"); continue
		var p: Dictionary = raw
		var id := str(p.get("id", "")).strip_edges()
		if id == "":
			errs.append(tag + ": id is required"); continue
		tag = "%s %s" % [map_id, id]
		if seen.has(id):
			errs.append(tag + ": duplicate id"); continue
		seen[id] = true
		var kind := str(p.get("kind", ""))
		if not KINDS.has(kind):
			errs.append(tag + ": kind must be one of " + str(KINDS)); continue
		var hp := float(p.get("hp", 0.0))
		if not is_finite(hp) or hp < 1.0 or hp > 500.0:
			errs.append(tag + ": hp %.2f outside 1..500" % hp)
		var color: Variant = p.get("color", null)
		if not (color is int or color is float) or int(color) < 0 or int(color) > 0xFFFFFF:
			errs.append(tag + ": color must be 0x000000..0xFFFFFF")
		if p.has("drop") and not (p["drop"] is String):
			errs.append(tag + ": drop must be a string when present")
		var box: Variant = p.get("box")
		if not (box is Dictionary):
			errs.append(tag + ": box is required"); continue
		var b: Dictionary = box
		for k: String in ["x", "y", "z", "w", "h", "d"]:
			if not (b.get(k) is int or b.get(k) is float):
				errs.append(tag + ": box.%s must be a number" % k)
		if not (b.get("x") is int or b.get("x") is float):
			continue
		var x := float(b.get("x", 0.0)); var y := float(b.get("y", 0.0)); var z := float(b.get("z", 0.0))
		var w := float(b.get("w", 0.0)); var h := float(b.get("h", 0.0)); var d := float(b.get("d", 0.0))
		if not (is_finite(x) and is_finite(y) and is_finite(z) and is_finite(w) and is_finite(h) and is_finite(d)):
			errs.append(tag + ": box must be finite"); continue
		if w <= 0.2 or d <= 0.2 or h <= 0.2 or w > 8.0 or d > 8.0 or h > 8.0:
			errs.append(tag + ": box size %.2f x %.2f x %.2f outside 0.2..8" % [w, h, d])
			continue
		var min_x := x - w / 2.0; var max_x := x + w / 2.0
		var min_z := z - d / 2.0; var max_z := z + d / 2.0
		var base := _support_top(map_solids, x, z, y)
		if is_nan(base):
			errs.append(tag + ": no floor under the box (base y %.2f)" % y); continue
		if absf(base - y) > 0.06:
			errs.append(tag + ": base y %.2f does not sit on the floor top %.2f" % [y, base]); continue
		# the whole footprint, and a margin all round it, must have floor under it: no ring-out edge, no void
		if not _footprint_supported(map_solids, min_x, max_x, min_z, max_z, y):
			errs.append(tag + ": footprint is not fully on the floor")
		if not _margin_supported(map_solids, min_x, max_x, min_z, max_z, y):
			errs.append(tag + ": too close to a ring-out edge (needs %.1f m of floor around it)" % EDGE_MARGIN)
		for o: Dictionary in map_solids:
			if float(o["top"]) <= y + 0.05 or float(o["bottom"]) >= y + h - 0.05: continue
			if min_x - OVERLAP_SLOP < float(o["maxX"]) and float(o["minX"]) < max_x + OVERLAP_SLOP \
					and min_z - OVERLAP_SLOP < float(o["maxZ"]) and float(o["minZ"]) < max_z + OVERLAP_SLOP:
				errs.append(tag + ": overlaps existing map geometry")
				break
		for sp: Array in spawns:
			if _rect_dist(float(sp[0]), float(sp[1]), min_x, max_x, min_z, max_z) < SPAWN_CLEARANCE:
				errs.append(tag + ": blocks a spawn / player start / bot spot")
				break
		for l: Dictionary in ladders:
			if _rect_dist(float(l.get("x", 0.0)), float(l.get("z", 0.0)), min_x, max_x, min_z, max_z) < LADDER_CLEARANCE:
				errs.append(tag + ": blocks a ladder")
				break
		for q: Dictionary in pads:
			var pr := float(q.get("r", 1.2))
			if _rect_dist(float(q.get("x", 0.0)), float(q.get("z", 0.0)), min_x, max_x, min_z, max_z) < pr + PAD_CLEARANCE:
				errs.append(tag + ": blocks a bounce pad")
				break
		for raw_drop: Variant in drops:
			if not (raw_drop is Array) or (raw_drop as Array).size() < 2: continue
			var dr: Array = raw_drop
			if _rect_dist(float(dr[0]), float(dr[1]), min_x, max_x, min_z, max_z) < CRATE_CLEARANCE:
				errs.append(tag + ": blocks a crate drop spot")
				break
		var prev: Dictionary = {"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z, "y": y, "h": h, "id": id}
		for q: Dictionary in placed:
			if float(q["y"]) >= y + h - 0.01 or y >= float(q["y"]) + float(q["h"]) - 0.01: continue
			if float(q["min_x"]) - PROP_SLOP < max_x and min_x < float(q["max_x"]) + PROP_SLOP \
					and float(q["min_z"]) - PROP_SLOP < max_z and min_z < float(q["max_z"]) + PROP_SLOP:
				errs.append(tag + ": overlaps prop " + str(q["id"]))
				break
		placed.append(prev)
	return errs

# ============================== setup / meshes ==============================

## Called by MatchSim.setup only when the mode is on. Appends the arena's breakable boxes to `sim.solids` (each tagged
## so impact code can tell them apart) and, when `p_parent` is a real node, builds one two-tone mesh per prop. It never
## touches the map's own merged meshes: props are new children only.
func setup(p_sim: MatchSim, p_map_id: String, p_parent: Node3D = null) -> void:
	arena = p_map_id
	solids = p_sim.solids
	events = p_sim.combat.events
	parent = p_parent
	var data := load_data()
	var arenas: Dictionary = data.get("arenas", {}) if data.get("arenas") is Dictionary else {}
	var entry: Dictionary = arenas.get(arena, {}) if arenas.get(arena) is Dictionary else {}
	if entry.is_empty(): return
	var errs := validate_arena(arena, entry, p_sim.map, int(budget_of(data)["perArena"]))
	if not errs.is_empty():
		for e: String in errs: push_error("Destruct: " + e)
		return
	var raw_props: Array = entry.get("props", [])
	for i in raw_props.size():
		var p := _make_prop(raw_props[i], i)
		if p.is_empty(): continue
		props.append(p)
		solids.append(p["solid"])
	# One "props ready" event so a match log / test can see the mode actually loaded (no RNG, no gameplay effect).
	if not props.is_empty():
		events.append({"type": "props_ready", "arena": arena, "n": props.size()})
	if parent != null: _build_views()

func _make_prop(raw: Dictionary, index: int) -> Dictionary:
	var b: Dictionary = raw["box"]
	var x := float(b["x"]); var y := float(b["y"]); var z := float(b["z"])
	var w := float(b["w"]); var h := float(b["h"]); var d := float(b["d"])
	var solid := {
		"minX": x - w / 2.0, "maxX": x + w / 2.0,
		"minZ": z - d / 2.0, "maxZ": z + d / 2.0,
		"top": y + h, "bottom": y,
		"breakable": true, "prop": str(raw["id"]), "broken": false,
	}
	return {
		"id": str(raw["id"]), "kind": str(raw["kind"]), "index": index,
		"x": x, "y": y, "z": z, "w": w, "h": h, "d": d,
		"hp": float(raw["hp"]), "max_hp": float(raw["hp"]), "color": int(raw["color"]),
		"solid": solid, "mesh": null, "rubble": null, "broken": false,
	}

## One MeshInstance3D per prop body plus one trim/lid slab: a two-tone, pre-fractured look for two draw calls, with
## shadow casting off (docs/GRAPHICS.md: 40 shadowed props would eat the MID headroom). Materials are shared by colour.
func _build_views() -> void:
	if parent == null: return
	for p: Dictionary in props:
		var root := Node3D.new()
		root.name = "Prop_" + str(p["id"])
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(float(p["w"]), float(p["h"]), float(p["d"]))
		body.mesh = bm
		body.material_override = _mat(int(p["color"]))
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.name = "Body"
		body.position.y = float(p["h"]) * 0.5
		root.add_child(body)
		var trim := MeshInstance3D.new()
		var tm := BoxMesh.new()
		var over := 1.05 if str(p["kind"]) == "crate" else 1.02
		tm.size = Vector3(float(p["w"]) * over, float(p["h"]) * 0.13, float(p["d"]) * over)
		trim.mesh = tm
		trim.material_override = _trim_mat(int(p["color"]))
		trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		trim.name = "Trim"
		trim.position.y = float(p["h"]) * 0.93
		root.add_child(trim)
		root.position = Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
		parent.add_child(root)
		p["mesh"] = root

func _mat(color: int) -> StandardMaterial3D:
	if _mats.has(color): return _mats[color]
	var m := MapBuilder.material(color)
	_mats[color] = m
	return m

func _trim_mat(color: int) -> StandardMaterial3D:
	if _trim_mats.has(color): return _trim_mats[color]
	var m := MapBuilder.material(color).duplicate() as StandardMaterial3D
	var c := MapBuilder.hex(color)
	m.albedo_color = Color(clampf(c.r + 0.22, 0.0, 1.0), clampf(c.g + 0.22, 0.0, 1.0), clampf(c.b + 0.22, 0.0, 1.0))
	_trim_mats[color] = m
	return m

func _rubble_mat(color: int) -> StandardMaterial3D:
	if _rubble_mats.has(color): return _rubble_mats[color]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c := MapBuilder.hex(color)
	m.albedo_color = Color(c.r * 0.42, c.g * 0.38, c.b * 0.34)
	_rubble_mats[color] = m
	return m

# ============================== damage / breaks ==============================

## Nearest breakable along a unit ray: [distance, prop index], [] on a miss. The impact code compares this distance with
## the wall/fighter distance it already computed, so a shot never damages a prop behind a wall or a fighter.
func ray_hit(ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, far: float) -> Array:
	var best_t := -1.0
	var best_i := -1
	for i in props.size():
		var p: Dictionary = props[i]
		if bool(p["broken"]): continue
		var s: Dictionary = p["solid"]
		var t := Weapons.ray_box(ox, oy, oz, dx, dy, dz, float(s["minX"]), float(s["bottom"]), float(s["minZ"]),
			float(s["maxX"]), float(s["top"]), float(s["maxZ"]))
		if t >= 0.0 and t <= far and (best_i < 0 or t < best_t):
			best_t = t; best_i = i
	return [best_t, best_i] if best_i >= 0 else []

## Reduce a prop's hit points. Returns true when this hit broke it. `dir` is the impact direction (bullets) or the
## blast direction (explosions); it only feeds the event / debris, never the simulation.
func break_hit(index: int, dmg: float, dir: Array = []) -> bool:
	if index < 0 or index >= props.size(): return false
	var p: Dictionary = props[index]
	if bool(p["broken"]): return false
	p["hp"] = float(p["hp"]) - maxf(0.0, dmg)
	if float(p["hp"]) > 0.0:
		events.append({"type": "prop_hit", "id": p["id"], "hp": float(p["hp"]), "max_hp": float(p["max_hp"]),
			"x": float(p["x"]), "y": float(p["y"]) + float(p["h"]) * 0.5, "z": float(p["z"]), "color": int(p["color"])})
		return false
	_break(index, dir)
	return true

## Explosion damage: every unbroken prop whose centre falls inside the blast radius takes `dmg * falloff` (the same
## linear falloff explosions already use on fighters). Returns how many props broke.
func break_blast(x: float, y: float, z: float, rad: float, dmg: float) -> int:
	var broke := 0
	if rad <= 0.0: return broke
	for i in props.size():
		var p: Dictionary = props[i]
		if bool(p["broken"]): continue
		var dx := float(p["x"]) - x
		var dy := float(p["y"]) + float(p["h"]) * 0.5 - y
		var dz := float(p["z"]) - z
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		if d >= rad: continue
		var k := 1.0 - d / rad
		var dir: Array = Combat.norm3(dx, dy, dz) if d > 0.001 else [0.0, 1.0, 0.0]
		if break_hit(i, dmg * k, dir): broke += 1
	return broke

## Take a prop out of the world: remove its solid (so the next sim step has no collision there), free/hide its mesh,
## leave a flat rubble patch, and record the "break" event the presentation layer turns into debris, dust and sound.
func _break(index: int, dir: Array) -> void:
	var p: Dictionary = props[index]
	p["broken"] = true
	_broken += 1
	var solid: Dictionary = p["solid"]
	solid["breakable"] = false
	solid["broken"] = true
	var si := solids.find(solid)
	if si >= 0: solids.remove_at(si)
	var mesh: Variant = p["mesh"]
	if mesh != null and is_instance_valid(mesh):
		(mesh as Node3D).visible = false
		(mesh as Node3D).queue_free()
	p["mesh"] = null
	_make_rubble(p)
	var cx := float(p["x"])
	var cy := float(p["y"])
	var cz := float(p["z"])
	events.append({"type": "break", "id": p["id"], "kind": p["kind"], "index": index,
		"x": cx, "y": cy, "z": cz, "w": float(p["w"]), "h": float(p["h"]), "d": float(p["d"]),
		"color": int(p["color"]), "dir": dir, "total": props.size(), "broken": _broken})
	events.append({"type": "sfx", "name": "whack" if str(p["kind"]) == "barricade" else "clink", "x": cx, "y": cy + 0.4, "z": cz})

## A cheap flat patch where the prop stood (one unshaded, shadowless quad-ish box: one draw call, no texture).
func _make_rubble(p: Dictionary) -> void:
	if parent == null or not is_instance_valid(parent): return
	var mi := MeshInstance3D.new()
	mi.name = "Rubble_" + str(p["id"])
	var bm := BoxMesh.new()
	bm.size = Vector3(float(p["w"]) * 0.92, 0.03, float(p["d"]) * 0.92)
	mi.mesh = bm
	mi.material_override = _rubble_mat(int(p["color"]))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(float(p["x"]), float(p["y"]) + RUBBLE_LIFT, float(p["z"]))
	parent.add_child(mi)
	p["rubble"] = mi

# ============================== queries ==============================

## Is `what` an unbroken breakable? Accepts a prop index, a prop id, or a freed solid dictionary (tagged at creation).
func is_breakable(what: Variant) -> bool:
	if what is int:
		var i: int = what
		return i >= 0 and i < props.size() and not bool(props[i]["broken"])
	if what is String or what is StringName:
		var id := str(what)
		for p: Dictionary in props:
			if str(p["id"]) == id: return not bool(p["broken"])
		return false
	if what is Dictionary:
		var d: Dictionary = what
		return bool(d.get("breakable", false)) and not bool(d.get("broken", false))
	return false

## The prop index whose `solid` is this dictionary, or -1.
func find_prop(solid: Variant) -> int:
	if not (solid is Dictionary): return -1
	for i in props.size():
		if props[i]["solid"] == solid: return i
	return -1

func broken_count() -> int:
	return _broken

func remaining() -> int:
	return props.size() - _broken

func total() -> int:
	return props.size()

## A prop's authored box in world space: {x, y, z, w, h, d, id, kind, hp, color}. {} for a bad index.
func prop_info(index: int) -> Dictionary:
	if index < 0 or index >= props.size(): return {}
	var p: Dictionary = props[index]
	return {"id": p["id"], "kind": p["kind"], "x": p["x"], "y": p["y"], "z": p["z"], "w": p["w"], "h": p["h"], "d": p["d"],
		"hp": p["hp"], "max_hp": p["max_hp"], "color": p["color"], "broken": p["broken"]}

## Live prop mesh nodes under `parent` (tests / leak checks).
func mesh_count() -> int:
	var n := 0
	for p: Dictionary in props:
		var m: Variant = p["mesh"]
		if m != null and is_instance_valid(m): n += 1
	return n

## Drop every reference. The prop / rubble nodes are children of the map node and are freed with it by World.load_map;
## a headless test that passed its own parent frees that parent itself.
func clear() -> void:
	props.clear()
	solids = []
	events = []
	parent = null
	arena = ""
	_broken = 0

# ============================== authoring helpers ==============================

static func _solids_of(map: Dictionary) -> Array:
	var out: Array = []
	var geo: Dictionary = map.get("geometry", {}) if map.get("geometry") is Dictionary else {}
	for b: Variant in (geo.get("boxes", []) as Array):
		if not (b is Dictionary): continue
		var box: Dictionary = b
		var w := float(box.get("w", 0.0)); var d := float(box.get("d", 0.0))
		var y := float(box.get("y", 0.0)); var h := float(box.get("h", 0.0))
		out.append({"minX": float(box.get("x", 0.0)) - w / 2.0, "maxX": float(box.get("x", 0.0)) + w / 2.0,
			"minZ": float(box.get("z", 0.0)) - d / 2.0, "maxZ": float(box.get("z", 0.0)) + d / 2.0,
			"top": y + h, "bottom": y})
	return out

## The highest floor top under (x, z) within `tol` of `y`; NAN when there is none.
static func _support_top(bs: Array, x: float, z: float, y: float, tol := 0.6) -> float:
	var best := NAN
	for b: Dictionary in bs:
		if x < float(b["minX"]) - 1e-6 or x > float(b["maxX"]) + 1e-6: continue
		if z < float(b["minZ"]) - 1e-6 or z > float(b["maxZ"]) + 1e-6: continue
		if absf(float(b["top"]) - y) > tol: continue
		if is_nan(best) or float(b["top"]) > best: best = float(b["top"])
	return best

static func _has_floor(bs: Array, x: float, z: float, y: float) -> bool:
	return not is_nan(_support_top(bs, x, z, y, 0.25))

## Every corner and edge midpoint is over the floor at the prop's base height.
static func _footprint_supported(bs: Array, min_x: float, max_x: float, min_z: float, max_z: float, y: float) -> bool:
	for fx in [0.0, 0.5, 1.0]:
		for fz in [0.0, 0.5, 1.0]:
			if not _has_floor(bs, min_x + (max_x - min_x) * fx, min_z + (max_z - min_z) * fz, y): return false
	return true

## A ring of floor all round the footprint: a prop may not hang over a ring-out edge.
static func _margin_supported(bs: Array, min_x: float, max_x: float, min_z: float, max_z: float, y: float) -> bool:
	var mx := (min_x + max_x) * 0.5
	var mz := (min_z + max_z) * 0.5
	var pts := [
		[min_x - EDGE_MARGIN, mz], [max_x + EDGE_MARGIN, mz], [mx, min_z - EDGE_MARGIN], [mx, max_z + EDGE_MARGIN],
		[min_x - 0.6, min_z - 0.6], [max_x + 0.6, min_z - 0.6], [min_x - 0.6, max_z + 0.6], [max_x + 0.6, max_z + 0.6],
	]
	for q: Array in pts:
		if _has_floor(bs, float(q[0]), float(q[1]), y): continue
		return false
	return true

## Distance from a point to a footprint rectangle (0 when inside it).
static func _rect_dist(px: float, pz: float, min_x: float, max_x: float, min_z: float, max_z: float) -> float:
	var dx := maxf(maxf(min_x - px, 0.0), px - max_x)
	var dz := maxf(maxf(min_z - pz, 0.0), pz - max_z)
	return sqrt(dx * dx + dz * dz)
