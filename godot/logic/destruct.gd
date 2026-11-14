class_name Destruct
extends RefCounted
## Optional destructible-arena mode (docs/DESTRUCTIBLE.md), milestone M1 "all maps": breakable COVER ON EVERY ARENA MAP,
## picked procedurally from the map's own `maps.json` boxes, OFFLINE ONLY and off by default.
##
## Instead of authoring props (M0), the mode analyses a map's existing box geometry, groups boxes that are one object
## (a wall plus its thin cap, a stacked crate pile), throws away everything essential (ground slabs, roofs, boundary /
## ring-out walls, stairs, floor platforms that carry another structure, anything near a spawn / ladder / pad), then picks
## a seeded ~`fraction` of the remaining cover components. Those boxes are taken out of the map's merged mesh + collision
## and replaced by tagged individual boxes with a mesh, hit points, and a respawn timer. Breaking one removes its solid,
## hides its mesh and leaves rubble; ~2 minutes later (randomised, docs) the solid and the mesh come back with a fade-in and
## it can be broken again.
##
## Off is a real null path: `MatchSim.setup` only creates Destruct when `MatchSim.destructible` is true, the analysis never
## runs on a normal match, and no CombatRng draw is taken. Selection uses its own RandomNumberGenerator seeded from
## `MatchSim.destruct_seed`, so the same match seed always gives the same breakables and another seed gives another set.
##
## Authoring is the config overlay godot/data/extra/destructible.json (never shared/*.json): fraction, budget, hp band,
## respawn timing, colours and the exclusion rules. `validate()` checks the whole config against the shipped maps and
## `setup()` re-checks it before touching the match (bad config => no props, never a broken match).
##
## Runtime API (weapons / tests):
##   plan_for(map_id, map, seed)   deterministic component selection: {props, exclude, eligible, target, ...}
##   setup(sim, map_id, parent, plan)  remove the chosen boxes from map collision, add tagged solids + meshes
##   ray_hit(...) / break_hit(...) / break_blast(...)  the weapon hooks (same as M0)
##   step(dt)                      respawn timers (MatchSim.step calls it once per fixed step)
##   is_breakable / props / broken_count / remaining / total / mesh_count / rubble_count / respawn_delay  queries

const DATA_PATH := "res://data/extra/destructible.json"
const VERSION := 2
const KINDS := ["crate", "barricade"]
## Arenas the mode never runs on (the sandbox, the ranges, the shrinking floors, Lava Pillars' generated lake and the
## Construction DLC's generated site). Everything else in maps.json is a normal arena and gets breakables.
const NOT_SUPPORTED := ["custom", "test", "practice", "pillars", "pillars2", "shrink", "squeeze", "sitegen"]
## Hard caps the config may lower but never raise (docs/GRAPHICS.md: no shadow casting, 40-60 draws of headroom).
const HARD_MAX_PER_MAP := 60
const DEFAULT_PER_MAP := 40
const MIN_FRACTION := 0.05
const MAX_FRACTION := 1.0
const RUBBLE_LIFT := 0.018
## Things that must never be picked: ground slabs, roofs, and slivers / decorative boxes that are not cover.
const GROUND_BOTTOM := -0.25
const ROOF_MIN_Y := 6.0
const ROOF_MIN_AREA := 1500.0
const WALL_THIN := 1.6
const WALL_TALL := 3.0
const STACK_SLOP := 0.06
const STACK_OVERLAP := 0.6
const DROP_CLEARANCE := 0.0

## One entry per breakable component:
##   {id, kind, index, root, members, boxes, x, y, z, w, h, d, hp, max_hp, color, solid, mesh, mesh_nodes,
##    rubble, tween, broken, respawn_t, breaks}
var props: Array = []
var solids: Array = []          ## the live sim.solids array (same reference, so a break is seen by every query)
var events: Array = []          ## the combat event list (same reference); breaks / respawns append events
var parent: Node3D = null       ## where prop meshes live (the built MapNode); null = logic only (headless tests)
var sim: MatchSim = null        ## the match (fighter overlap check before a respawn)
var arena := ""
var merge_exclude: Dictionary = {}  ## box index -> true, the map boxes owned by this mode (merged mesh must skip them)
var merged_pruned := false      ## true when the built MapNode's merged meshes were rebuilt without those boxes
var _broken := 0
var _pending: Array = []        ## prop indices with a running respawn timer (no per-step allocation; break is rare)
var _mats := {}                 ## body colour -> tinted material
var _accent_mat: StandardMaterial3D = null
var _rubble_mats := {}          ## body colour -> rubble material
var _respawn_rng := RandomNumberGenerator.new()
var _cfg: Dictionary = {}
var _respawn_min := 100.0
var _respawn_max := 140.0

static var _data: Dictionary = {}
static var _data_loaded := false
static var _map_rows: Dictionary = {}
static var _map_rows_loaded := false
static var _style_rows: Dictionary = {}

# ============================== config ==============================

## The overlay (cached after the first read). {} when the file is missing or malformed.
static func load_data() -> Dictionary:
	if _data_loaded: return _data
	_data_loaded = true
	var parsed: Variant = Combat.read_json(DATA_PATH)
	_data = parsed if parsed is Dictionary else {}
	return _data

## Every supported arena id (in file order) from maps.json.
static func supported_ids() -> Array:
	var out: Array = []
	for raw_id: Variant in _maps().keys():
		var id := str(raw_id)
		var map: Variant = _maps()[raw_id]
		if map is Dictionary and supported(id, map):
			out.append(id)
	return out

static func _maps() -> Dictionary:
	if _map_rows_loaded: return _map_rows
	_map_rows_loaded = true
	var parsed: Variant = load("res://autoload/content.gd").load_json("maps")
	_map_rows = parsed if parsed is Dictionary else {}
	return _map_rows

## True when the mode can run on this map: a real arena, not a range / sandbox / generated / shrinking level, with
## box geometry to analyse. (Offline / Arcade / online gating stays in world.gd, exactly as in M0.)
static func supported(map_id: String, map: Dictionary) -> bool:
	if map_id == "" or NOT_SUPPORTED.has(map_id): return false
	if map.is_empty(): return false
	if bool(map.get("range", false)) or bool(map.get("shrinks", false)): return false
	var geo: Variant = map.get("geometry")
	if not (geo is Dictionary): return false
	return not ((geo as Dictionary).get("boxes", []) as Array).is_empty()

## True when the arena has a supported map in content (used by the Setup Wizard row / world gating).
static func has_arena(map_id: String) -> bool:
	if map_id == "" or NOT_SUPPORTED.has(map_id): return false
	var map: Variant = _maps().get(map_id)
	return map is Dictionary and supported(map_id, map)

## The normalised config with every knob used by the runtime. Missing fields fall back to the defaults; `validate_config`
## is the gate that rejects bad values before a match uses them.
static func config(data: Dictionary = {}) -> Dictionary:
	var d := data if not data.is_empty() else load_data()
	var budget: Dictionary = d.get("budget", {}) if d.get("budget") is Dictionary else {}
	var hp: Dictionary = d.get("hp", {}) if d.get("hp") is Dictionary else {}
	var rs: Dictionary = d.get("respawn", {}) if d.get("respawn") is Dictionary else {}
	var col: Dictionary = d.get("colors", {}) if d.get("colors") is Dictionary else {}
	var sel: Dictionary = d.get("selection", {}) if d.get("selection") is Dictionary else {}
	return {
		"version": int(d.get("version", 0)),
		"enabled": bool(d.get("enabled", false)),
		"fraction": float(d.get("fraction", 0.5)),
		"per_map": mini(int(budget.get("perMap", DEFAULT_PER_MAP)), HARD_MAX_PER_MAP),
		"hp_min": float(hp.get("min", 20)),
		"hp_max": float(hp.get("max", 56)),
		"hp_volume_min": float(hp.get("volumeMin", 0.6)),
		"hp_volume_max": float(hp.get("volumeMax", 30.0)),
		"respawn_min": float(rs.get("minSeconds", 100.0)),
		"respawn_max": float(rs.get("maxSeconds", 140.0)),
		"fade": float(rs.get("fadeSeconds", 0.35)),
		"retry": float(rs.get("retrySeconds", 2.5)),
		"accent": int(col.get("accent", 0xFFD166)),
		"tint": float(col.get("tint", 0.12)),
		"rubble": float(col.get("rubble", 0.45)),
		"spawn_clearance": float(sel.get("spawnClearance", 1.5)),
		"ladder_clearance": float(sel.get("ladderClearance", 1.5)),
		"pad_clearance": float(sel.get("padClearance", 0.8)),
		"edge_margin": float(sel.get("edgeMargin", 0.9)),
		"min_height": float(sel.get("minHeight", 0.8)),
		"max_height": float(sel.get("maxHeight", 5.5)),
		"max_span": float(sel.get("maxSpan", 8.0)),
		"min_thin": float(sel.get("minThin", 0.35)),
		"min_area": float(sel.get("minArea", 0.5)),
		"stack_ratio": float(sel.get("stackRatio", 2.0)),
	}

## Shape/range checks only (cheap; called on every setup). Empty = valid.
static func validate_config(data: Dictionary) -> Array:
	var errs: Array = []
	if int(data.get("version", 0)) != VERSION:
		errs.append("version must be %d (got %s)" % [VERSION, data.get("version")])
	if not (data.get("enabled") is bool):
		errs.append("enabled must be a bool")
	if not (data.get("fraction") is int or data.get("fraction") is float):
		errs.append("fraction must be a number")
	else:
		var f := float(data["fraction"])
		if not is_finite(f) or f < MIN_FRACTION or f > MAX_FRACTION:
			errs.append("fraction %.3f outside %.2f..%.2f" % [f, MIN_FRACTION, MAX_FRACTION])
	if not (data.get("budget") is Dictionary):
		errs.append("budget must be a dictionary")
	else:
		var budget: Dictionary = data["budget"]
		if not (budget.get("perMap") is int or budget.get("perMap") is float):
			errs.append("budget.perMap must be a number")
		else:
			var per := int(budget["perMap"])
			if per < 1 or per > HARD_MAX_PER_MAP:
				errs.append("budget.perMap %d outside 1..%d" % [per, HARD_MAX_PER_MAP])
	errs.append_array(_range_errors(data.get("hp"), "hp", ["min", "max", "volumeMin", "volumeMax"], [1.0, 1.0, 0.0, 0.0], [500.0, 500.0, 500.0, 500.0]))
	if data.get("hp") is Dictionary:
		var hp: Dictionary = data["hp"]
		if hp.get("min") is int or hp.get("min") is float:
			if hp.get("max") is int or hp.get("max") is float:
				if float(hp["min"]) > float(hp["max"]):
					errs.append("hp.min must be <= hp.max")
				if float(hp.get("volumeMin", 0.0)) >= float(hp.get("volumeMax", 1.0)):
					errs.append("hp.volumeMin must be < hp.volumeMax")
	errs.append_array(_range_errors(data.get("respawn"), "respawn", ["minSeconds", "maxSeconds", "fadeSeconds", "retrySeconds"], [30.0, 30.0, 0.0, 0.2], [600.0, 600.0, 1.0, 20.0]))
	if data.get("respawn") is Dictionary:
		var rs: Dictionary = data["respawn"]
		if (rs.get("minSeconds") is int or rs.get("minSeconds") is float) and (rs.get("maxSeconds") is int or rs.get("maxSeconds") is float):
			if float(rs["minSeconds"]) > float(rs["maxSeconds"]):
				errs.append("respawn.minSeconds must be <= respawn.maxSeconds")
	errs.append_array(_range_errors(data.get("colors"), "colors", ["accent", "tint", "rubble"], [0.0, 0.0, 0.0], [0xFFFFFF, 0.5, 0.9]))
	errs.append_array(_range_errors(data.get("selection"), "selection",
		["spawnClearance", "ladderClearance", "padClearance", "edgeMargin", "minHeight", "maxHeight", "maxSpan", "minThin", "minArea", "stackRatio"],
		[0.0, 0.0, 0.0, 0.0, 0.3, 2.0, 2.0, 0.1, 0.05, 1.0],
		[8.0, 8.0, 4.0, 3.0, 3.0, 12.0, 16.0, 2.0, 8.0, 4.0]))
	if data.has("arenas"):
		errs.append("arenas is the M0 authored-props schema; version 2 selects from map boxes instead")
	return errs

## Numeric field range check for one config sub-dictionary. Returns error strings.
static func _range_errors(value: Variant, tag: String, keys: Array, lows: Array, highs: Array) -> Array:
	var errs: Array = []
	if not (value is Dictionary):
		errs.append("%s must be a dictionary" % tag)
		return errs
	var d: Dictionary = value
	for i in keys.size():
		var k: String = keys[i]
		var v: Variant = d.get(k)
		if not (v is int or v is float):
			errs.append("%s.%s must be a number" % [tag, k])
			continue
		var f := float(v)
		if not is_finite(f) or f < float(lows[i]) or f > float(highs[i]):
			errs.append("%s.%s %.3f outside %.3f..%.3f" % [tag, k, f, float(lows[i]), float(highs[i])])
	return errs

# ============================== selection ==============================

## Number of components to make breakable for an eligible count (fraction, at least 1, capped by the budget).
static func target_count(eligible: int, cfg: Dictionary = {}) -> int:
	if eligible <= 0: return 0
	var c := cfg if not cfg.is_empty() else config()
	var raw := int(round(float(eligible) * float(c["fraction"])))
	return clampi(maxi(1, raw), 1, int(c["per_map"]))

## Build the deterministic plan for one map + seed: which map boxes become breakable, and the runtime prop rows.
## `box_styles` is map_look.json's `boxes` section (hidden / op / ...); empty loads it for `map_id`.
static func plan_for(map_id: String, map: Dictionary, seed: int, box_styles: Dictionary = {}) -> Dictionary:
	var cfg := config()
	var plan := {"arena": map_id, "seed": seed, "props": [], "exclude": {}, "eligible": 0, "target": 0,
		"components": 0, "essential": 0}
	if not bool(cfg["enabled"]) or not supported(map_id, map): return plan
	var analysis := analyze(map_id, map, box_styles)
	var eligible: Array = analysis["eligible"]
	plan["eligible"] = eligible.size()
	plan["components"] = (analysis["components"] as Array).size()
	plan["essential"] = (analysis["essential"] as Array).size()
	if eligible.is_empty(): return plan
	var target := target_count(eligible.size(), cfg)
	plan["target"] = target
	# seeded Fisher-Yates over the component list, then take the first `target` and sort by root index for a stable order
	var order: Array = []
	for i in eligible.size(): order.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_seed(map_id, seed)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	var chosen: Array = order.slice(0, target)
	chosen.sort()
	var boxes: Array = (map.get("geometry", {}) as Dictionary).get("boxes", [])
	for idx: int in chosen:
		var comp: Dictionary = eligible[idx]
		plan["props"].append(_prop_from_component(map_id, boxes, comp, cfg))
		for k: int in comp["members"]: plan["exclude"][k] = true
	return plan

## Analyse a map's boxes into components and split them into eligible cover vs essential geometry.
## Returns {components: [...], eligible: [...], essential: [...], counts: {...}}. Each component is
##   {root, members[], bottom, top, min_x, max_x, min_z, max_z, area, thin, span, height, volume, reason}
## where `reason` is "" for eligible or one of ground / roof / hidden / thin / tall / span / tiny / supports-above /
## stair / spawn / ladder / pad / edge-wall.
static func analyze(map_id: String, map: Dictionary, box_styles: Dictionary = {}) -> Dictionary:
	var boxes: Array = []
	var geo: Variant = map.get("geometry")
	if geo is Dictionary:
		var raw_boxes: Variant = (geo as Dictionary).get("boxes", [])
		if raw_boxes is Array: boxes = raw_boxes
	var empty := {"components": [], "eligible": [], "essential": [], "counts": {}}
	if boxes.is_empty(): return empty
	var styles := box_styles if not box_styles.is_empty() else _styles_for(map_id)
	var cfg := config()
	var solids := _solids_of(map)
	var n := boxes.size()
	# 1. cluster boxes that are one object: an upper box resting on a comparable lower one (a wall + its cap, a stack)
	var links: Array = []
	for i in n: links.append(i)
	for u in n:
		var us: Dictionary = solids[u]
		var ua := float(us["maxX"]) - float(us["minX"])
		var ub := float(us["maxZ"]) - float(us["minZ"])
		var u_area := ua * ub
		for l in n:
			if l == u: continue
			var ls: Dictionary = solids[l]
			if absf(float(us["bottom"]) - float(ls["top"])) > STACK_SLOP: continue
			var la := float(ls["maxX"]) - float(ls["minX"])
			var lb := float(ls["maxZ"]) - float(ls["minZ"])
			var l_area := la * lb
			if l_area > float(cfg["stack_ratio"]) * u_area or u_area > float(cfg["stack_ratio"]) * l_area: continue
			var ovx := maxf(0.0, minf(float(us["maxX"]), float(ls["maxX"])) - maxf(float(us["minX"]), float(ls["minX"])))
			var ovz := maxf(0.0, minf(float(us["maxZ"]), float(ls["maxZ"])) - maxf(float(us["minZ"]), float(ls["minZ"])))
			if ovx * ovz < STACK_OVERLAP * u_area: continue
			_union(links, l, u)
			break
	var groups := {}
	var order: Array = []
	for i in n:
		var r := _find(links, i)
		if not groups.has(r):
			groups[r] = []
			order.append(r)
		(groups[r] as Array).append(i)
	# 2. per-component geometry + classification
	var components: Array = []
	var eligible: Array = []
	var essential: Array = []
	var counts := {}
	for r: int in order:
		var members: Array = groups[r]
		var comp := _component_geometry(boxes, solids, r, members)
		comp["reason"] = _component_reason(map, boxes, solids, comp, styles, cfg)
		components.append(comp)
		if str(comp["reason"]) == "":
			eligible.append(comp)
		else:
			essential.append(comp)
			counts[str(comp["reason"])] = int(counts.get(str(comp["reason"]), 0)) + 1
	return {"components": components, "eligible": eligible, "essential": essential, "counts": counts}

static func _find(links: Array, x: int) -> int:
	var i := x
	while int(links[i]) != i:
		links[i] = links[int(links[i])]
		i = int(links[i])
	return i

static func _union(links: Array, lower: int, upper: int) -> void:
	var a := _find(links, lower)
	var b := _find(links, upper)
	if a != b: links[b] = a

## Union extents + size figures for one component. `root` is the lowest box of the cluster.
static func _component_geometry(boxes: Array, solids: Array, root: int, members: Array) -> Dictionary:
	var bottom := INF
	var top := -INF
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var volume := 0.0
	for k: int in members:
		var s: Dictionary = solids[k]
		var b: Dictionary = boxes[k]
		bottom = minf(bottom, float(s["bottom"]))
		top = maxf(top, float(s["top"]))
		min_x = minf(min_x, float(s["minX"]))
		max_x = maxf(max_x, float(s["maxX"]))
		min_z = minf(min_z, float(s["minZ"]))
		max_z = maxf(max_z, float(s["maxZ"]))
		volume += float(b["w"]) * float(b["h"]) * float(b["d"])
	var rb: Dictionary = boxes[root]
	var area := float(rb["w"]) * float(rb["d"])
	return {
		"root": root, "members": members,
		"bottom": bottom, "top": top, "min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z,
		"area": area, "thin": minf(float(rb["w"]), float(rb["d"])), "span": maxf(float(rb["w"]), float(rb["d"])),
		"height": top - bottom, "volume": volume, "reason": "",
	}

## Why a component may NOT be broken ("" = eligible cover). The order matters: the first rule that fires is reported.
static func _component_reason(map: Dictionary, boxes: Array, solids: Array, comp: Dictionary, styles: Dictionary, cfg: Dictionary) -> String:
	var root: int = comp["root"]
	var b: Dictionary = boxes[root]
	var st: Variant = styles.get(str(root), {})
	if st is Dictionary and bool((st as Dictionary).get("hidden", false)): return "hidden"
	if float(comp["bottom"]) <= GROUND_BOTTOM: return "ground"
	var area := float(comp["area"])
	if float(comp["bottom"]) >= ROOF_MIN_Y and area >= ROOF_MIN_AREA: return "roof"
	var h := float(comp["height"])
	if h < float(cfg["min_height"]): return "thin"
	if h > float(cfg["max_height"]): return "tall"
	if float(comp["span"]) > float(cfg["max_span"]): return "span"
	if float(comp["thin"]) < float(cfg["min_thin"]) or area < float(cfg["min_area"]): return "tiny"
	var members: Array = comp["members"]
	# a box resting on this component would be left floating: it is structural
	for o in solids.size():
		if members.has(o): continue
		var os: Dictionary = solids[o]
		if absf(float(os["bottom"]) - float(comp["top"])) > STACK_SLOP: continue
		if float(comp["min_x"]) < float(os["maxX"]) - 0.2 and float(comp["max_x"]) > float(os["minX"]) + 0.2 \
				and float(comp["min_z"]) < float(os["maxZ"]) - 0.2 and float(comp["max_z"]) > float(os["minZ"]) + 0.2:
			return "supports-above"
	# a stair / ramp step: same footprint as a neighbour, adjacent, and a small height step between them
	for j in boxes.size():
		if members.has(j): continue
		var o: Dictionary = boxes[j]
		if absf(float(o["w"]) - float(b["w"])) > 0.05 or absf(float(o["d"]) - float(b["d"])) > 0.05: continue
		var o_top := float(o["y"]) + float(o["h"])
		var dtop := absf(o_top - float(comp["top"]))
		if dtop < 0.2 or dtop > 0.9: continue
		var adj_x := absf(absf(float(o["x"]) - float(b["x"])) - float(b["w"])) < 0.06 and absf(float(o["z"]) - float(b["z"])) < 0.06
		var adj_z := absf(absf(float(o["z"]) - float(b["z"])) - float(b["d"])) < 0.06 and absf(float(o["x"]) - float(b["x"])) < 0.06
		if adj_x or adj_z: return "stair"
	var rect := {"minX": comp["min_x"], "maxX": comp["max_x"], "minZ": comp["min_z"], "maxZ": comp["max_z"]}
	if _near_points(map, "spawns", rect, float(cfg["spawn_clearance"])): return "spawn"
	if _near_points(map, "bots", rect, float(cfg["spawn_clearance"])): return "spawn"
	var player: Variant = map.get("player")
	if player is Array and (player as Array).size() >= 2:
		if (player[0] is int or player[0] is float) and (player[1] is int or player[1] is float):
			if _rect_dist(float(player[0]), float(player[1]), rect) < float(cfg["spawn_clearance"]): return "spawn"
	var geo: Dictionary = map.get("geometry", {}) if map.get("geometry") is Dictionary else {}
	for raw_l: Variant in (geo.get("ladders", []) as Array):
		if not (raw_l is Dictionary): continue
		var l: Dictionary = raw_l
		if _rect_dist(float(l.get("x", 0.0)), float(l.get("z", 0.0)), rect) < float(cfg["ladder_clearance"]): return "ladder"
	for raw_p: Variant in (geo.get("bouncePads", []) as Array):
		if not (raw_p is Dictionary): continue
		var pad: Dictionary = raw_p
		if _rect_dist(float(pad.get("x", 0.0)), float(pad.get("z", 0.0)), rect) < float(pad.get("r", 1.2)) + float(cfg["pad_clearance"]): return "pad"
	# a thin / tall box hanging over the ring-out edge is a boundary wall, never cover
	if not _margin_supported(solids, rect, float(comp["bottom"]), float(cfg["edge_margin"])):
		if float(comp["thin"]) <= WALL_THIN or float(comp["height"]) >= WALL_TALL: return "edge-wall"
	return ""

static func _near_points(map: Dictionary, key: String, rect: Dictionary, clearance: float) -> bool:
	for raw: Variant in (map.get(key, []) as Array):
		if not (raw is Array): continue
		var p: Array = raw
		if p.size() < 2: continue
		if not (p[0] is int or p[0] is float) or not (p[1] is int or p[1] is float): continue
		if _rect_dist(float(p[0]), float(p[1]), rect) < clearance: return true
	return false

static func _styles_for(map_id: String) -> Dictionary:
	if _style_rows.has(map_id): return _style_rows[map_id]
	var rows: Dictionary = {}
	var look: Variant = MapBuilder.look(map_id)
	if look is Dictionary:
		var b: Variant = (look as Dictionary).get("boxes", {})
		if b is Dictionary: rows = b
	_style_rows[map_id] = rows
	return rows

## Runtime prop row from one component: geometry, hp (by volume), kind (by aspect), debris colour, member boxes.
static func _prop_from_component(map_id: String, boxes: Array, comp: Dictionary, cfg: Dictionary) -> Dictionary:
	var members: Array = comp["members"]
	var member_boxes: Array = []
	var volume := float(comp["volume"])
	for k: int in members:
		var b: Dictionary = boxes[k]
		member_boxes.append({
			"x": float(b["x"]), "y": float(b["y"]), "z": float(b["z"]),
			"w": float(b["w"]), "h": float(b["h"]), "d": float(b["d"]), "color": int(b["color"]),
		})
	var rb: Dictionary = boxes[int(comp["root"])]
	var span := float(cfg["hp_volume_max"]) - float(cfg["hp_volume_min"])
	var t := clampf((volume - float(cfg["hp_volume_min"])) / maxf(span, 0.0001), 0.0, 1.0)
	var hp := int(round(lerpf(float(cfg["hp_min"]), float(cfg["hp_max"]), t)))
	var thin := float(comp["thin"])
	return {
		"id": "brk_%s_%d" % [map_id, int(comp["root"])],
		"kind": "barricade" if thin <= WALL_THIN else "crate",
		"root": int(comp["root"]),
		"members": members.duplicate(),
		"boxes": member_boxes,
		"x": float(rb["x"]), "y": float(comp["bottom"]), "z": float(rb["z"]),
		"w": float(rb["w"]), "h": float(comp["height"]), "d": float(rb["d"]),
		"min_x": float(comp["min_x"]), "max_x": float(comp["max_x"]),
		"min_z": float(comp["min_z"]), "max_z": float(comp["max_z"]),
		"top": float(comp["top"]), "bottom": float(comp["bottom"]),
		"hp": hp, "max_hp": hp, "volume": volume,
		"color": int(rb["color"]),
	}

## Validate the whole config against the shipped maps. Returns every problem as a string (empty = valid). Iterates every
## supported arena, proves it yields at least one breakable component, and checks the plan/target/budget invariants.
static func validate(data: Dictionary, maps: Dictionary) -> Array:
	var errs: Array = validate_config(data)
	if not errs.is_empty():
		return errs
	var cfg := config(data)
	if not bool(cfg["enabled"]):
		errs.append("enabled is false: the mode would be a no-op on every arena")
		return errs
	var tested := 0
	var ids := {}
	for raw_id: Variant in maps.keys():
		var id := str(raw_id)
		var map: Variant = maps[raw_id]
		if not (map is Dictionary): continue
		if not supported(id, map as Dictionary): continue
		tested += 1
		var mapd: Dictionary = map
		var analysis := analyze(id, mapd)
		var eligible: Array = analysis["eligible"]
		if eligible.is_empty():
			errs.append("%s: no eligible cover component (the mode would add nothing)" % id)
			continue
		var target := target_count(eligible.size(), cfg)
		if target < 1 or target > int(cfg["per_map"]):
			errs.append("%s: target %d outside 1..%d" % [id, target, int(cfg["per_map"])])
		var plan := plan_for(id, mapd, 12345)
		var plan_props: Array = plan["props"]
		if plan_props.size() != target:
			errs.append("%s: plan made %d breakables, expected %d" % [id, plan_props.size(), target])
		if (plan["exclude"] as Dictionary).size() < plan_props.size():
			errs.append("%s: exclude map does not cover every selected component" % id)
		var eligible_roots := {}
		for comp: Dictionary in eligible: eligible_roots[int(comp["root"])] = true
		for raw_prop: Variant in plan_props:
			var p: Dictionary = raw_prop
			if not eligible_roots.has(int(p["root"])):
				errs.append("%s: selected root %d is not eligible" % [id, int(p["root"])])
			if ids.has(str(p["id"])):
				errs.append("duplicate prop id " + str(p["id"]))
			ids[str(p["id"])] = true
			var hpv := float(p["hp"])
			if hpv < 1.0 or hpv > 500.0: errs.append("%s: %s hp %.1f outside 1..500" % [id, str(p["id"]), hpv])
		# determinism: the same seed must give exactly the same breakables
		var again := plan_for(id, mapd, 12345)
		if str(again["props"]) != str(plan["props"]):
			errs.append("%s: plan is not deterministic for a fixed seed" % id)
	if tested == 0:
		errs.append("no supported arena found in maps.json")
	return errs

# ============================== setup / meshes ==============================

## Called by MatchSim.setup only when the mode is on. `p_plan` is the world's precomputed plan (so it can prune the merged
## map meshes before the first frame); when empty the plan is rebuilt from sim.destruct_seed.
func setup(p_sim: MatchSim, p_map_id: String, p_parent: Node3D = null, p_plan: Dictionary = {}) -> void:
	arena = p_map_id
	sim = p_sim
	solids = p_sim.solids
	events = p_sim.combat.events
	parent = p_parent
	_cfg = config()
	var errs := validate_config(load_data())
	if not errs.is_empty():
		for e: String in errs: push_error("Destruct: " + e)
		return
	_apply_cfg()
	var plan: Dictionary = p_plan
	if plan.is_empty():
		plan = plan_for(arena, p_sim.map, p_sim.destruct_seed)
	var raw_props: Variant = plan.get("props", [])
	if not (raw_props is Array) or (raw_props as Array).is_empty(): return
	# The mode forces a steady floor (MatchSim), so sim.solids is exactly one dictionary per map box: the selected boxes
	# are removed by index (descending so earlier indices stay valid) and replaced by one tagged component box each.
	var boxes: Array = (p_sim.map.get("geometry", {}) as Dictionary).get("boxes", [])
	if solids.size() != boxes.size():
		push_error("Destruct: sim.solids (%d) is not one box per map box (%d); no props added" % [solids.size(), boxes.size()])
		return
	merge_exclude = (plan.get("exclude", {}) as Dictionary).duplicate()
	var cut: Array = merge_exclude.keys()
	cut.sort()
	cut.reverse()
	for i: int in cut: solids.remove_at(i)
	for raw: Variant in raw_props:
		var p := _make_prop(raw as Dictionary)
		props.append(p)
		solids.append(p["solid"])
	_rebuild_respawn_rng()
	if parent != null: _build_views()
	if not props.is_empty():
		events.append({"type": "props_ready", "arena": arena, "n": props.size(), "components": plan.get("components", 0),
			"eligible": plan.get("eligible", props.size()), "target": plan.get("target", props.size())})

func _apply_cfg() -> void:
	_respawn_min = float(_cfg["respawn_min"])
	_respawn_max = float(_cfg["respawn_max"])

func _rebuild_respawn_rng() -> void:
	var seed := sim.destruct_seed if sim != null else 0
	_respawn_rng = RandomNumberGenerator.new()
	_respawn_rng.seed = _mix_seed(arena + ":respawn", seed)

func _make_prop(raw: Dictionary) -> Dictionary:
	var p: Dictionary = raw.duplicate(true)
	p["index"] = props.size()
	p["broken"] = false
	p["mesh"] = null
	p["mesh_nodes"] = []
	p["rubble"] = null
	p["tween"] = null
	p["respawn_t"] = 0.0
	p["breaks"] = 0
	p["solid"] = {
		"minX": float(p["min_x"]), "maxX": float(p["max_x"]),
		"minZ": float(p["min_z"]), "maxZ": float(p["max_z"]),
		"top": float(p["top"]), "bottom": float(p["bottom"]),
		"breakable": true, "prop": str(p["id"]), "broken": false,
	}
	return p

## One prop root per component, one MeshInstance3D per member box plus a thin accent band on top (the "this is
## breakable" marker). Two-ish draw calls per component, shared materials, no shadow casting.
func _build_views() -> void:
	if parent == null: return
	if not merge_exclude.is_empty() and parent is MapBuilder.MapNode:
		var boxes: Array = (parent.map.get("geometry", {}) as Dictionary).get("boxes", [])
		MapBuilder.rebuild_boxes(parent, boxes, merge_exclude)
		merged_pruned = true
	for p: Dictionary in props: _build_prop_view(p)

func _build_prop_view(p: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Prop_" + str(p["id"])
	var base_x := float(p["x"])
	var base_y := float(p["y"])
	var base_z := float(p["z"])
	for raw: Variant in (p["boxes"] as Array):
		var b: Dictionary = raw
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(float(b["w"]), float(b["h"]), float(b["d"]))
		mi.mesh = bm
		mi.material_override = _body_mat(int(b["color"]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(float(b["x"]) - base_x, float(b["y"]) - base_y + float(b["h"]) * 0.5, float(b["z"]) - base_z)
		root.add_child(mi)
		(p["mesh_nodes"] as Array).append(mi)
	var trim := MeshInstance3D.new()
	var tm := BoxMesh.new()
	var band := minf(0.14, float(p["h"]) * 0.2)
	tm.size = Vector3(float(p["w"]) * 1.03, band, float(p["d"]) * 1.03)
	trim.mesh = tm
	trim.material_override = _accent()
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trim.name = "Trim"
	trim.position = Vector3(0.0, float(p["h"]) - band * 0.5 - 0.01, 0.0)
	root.add_child(trim)
	(p["mesh_nodes"] as Array).append(trim)
	root.position = Vector3(base_x, base_y, base_z)
	parent.add_child(root)
	p["mesh"] = root

func _body_mat(color: int) -> StandardMaterial3D:
	if _mats.has(color): return _mats[color]
	var m := MapBuilder.material(color).duplicate() as StandardMaterial3D
	var accent := MapBuilder.hex(int(_cfg["accent"]))
	m.albedo_color = (m.albedo_color as Color).lerp(accent, float(_cfg["tint"]))
	_mats[color] = m
	return m

func _accent() -> StandardMaterial3D:
	if _accent_mat != null: return _accent_mat
	var m := StandardMaterial3D.new()
	var accent := MapBuilder.hex(int(_cfg["accent"]))
	m.albedo_color = accent
	m.emission_enabled = true
	m.emission = accent
	m.emission_energy_multiplier = 0.4
	_accent_mat = m
	return m

func _rubble_mat(color: int) -> StandardMaterial3D:
	if _rubble_mats.has(color): return _rubble_mats[color]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c := MapBuilder.hex(color)
	var dark := float(_cfg["rubble"])
	m.albedo_color = Color(c.r * (1.0 - dark), c.g * (1.0 - dark * 0.9), c.b * (1.0 - dark * 0.8))
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
			best_t = t
			best_i = i
	return [best_t, best_i] if best_i >= 0 else []

## Reduce a prop's hit points. Returns true when this hit broke it.
func break_hit(index: int, dmg: float, dir: Array = []) -> bool:
	if index < 0 or index >= props.size(): return false
	var p: Dictionary = props[index]
	if bool(p["broken"]): return false
	p["hp"] = float(p["hp"]) - maxf(0.0, dmg)
	if float(p["hp"]) > 0.0:
		events.append({"type": "prop_hit", "id": p["id"], "index": index, "hp": float(p["hp"]), "max_hp": float(p["max_hp"]),
			"x": float(p["x"]), "y": float(p["y"]) + float(p["h"]) * 0.5, "z": float(p["z"]), "color": int(p["color"])})
		return false
	_break(index, dir)
	return true

## Explosion damage: every unbroken prop whose centre falls inside the blast radius takes `dmg * falloff`.
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

## Take a component out of the world: remove its solid, hide (never free) its mesh, show its rubble patch, start the
## randomised respawn timer and record the presentation events. The mesh is recycled when it respawns.
func _break(index: int, dir: Array) -> void:
	var p: Dictionary = props[index]
	p["broken"] = true
	p["breaks"] = int(p["breaks"]) + 1
	_broken += 1
	var solid: Dictionary = p["solid"]
	solid["breakable"] = false
	solid["broken"] = true
	var si := solids.find(solid)
	if si >= 0: solids.remove_at(si)
	_kill_tween(p)
	var mesh: Variant = p["mesh"]
	if mesh != null and is_instance_valid(mesh):
		(mesh as Node3D).visible = false
		for raw: Variant in (p["mesh_nodes"] as Array):
			if raw is MeshInstance3D: (raw as MeshInstance3D).transparency = 0.0
	p["respawn_t"] = _respawn_rng.randf_range(_respawn_min, _respawn_max)
	_pending.append(index)
	_show_rubble(p)
	var cx := float(p["x"])
	var cy := float(p["y"])
	var cz := float(p["z"])
	events.append({"type": "break", "id": p["id"], "kind": p["kind"], "index": index,
		"x": cx, "y": cy, "z": cz, "w": float(p["w"]), "h": float(p["h"]), "d": float(p["d"]),
		"color": int(p["color"]), "dir": dir, "total": props.size(), "broken": _broken,
		"respawn_in": float(p["respawn_t"])})
	events.append({"type": "sfx", "name": "whack" if str(p["kind"]) == "barricade" else "clink", "x": cx, "y": cy + 0.4, "z": cz})

## A cheap flat patch where the component stood; one unshaded shadowless box, created once per component and reused.
func _show_rubble(p: Dictionary) -> void:
	if parent == null or not is_instance_valid(parent): return
	var rub: Variant = p["rubble"]
	if rub == null or not is_instance_valid(rub):
		var mi := MeshInstance3D.new()
		mi.name = "Rubble_" + str(p["id"])
		var bm := BoxMesh.new()
		bm.size = Vector3(float(p["w"]) * 0.92, 0.03, float(p["d"]) * 0.92)
		mi.mesh = bm
		mi.material_override = _rubble_mat(int(p["color"]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(float(p["x"]), float(p["y"]) + RUBBLE_LIFT, float(p["z"]))
		mi.visible = false
		parent.add_child(mi)
		p["rubble"] = mi
		rub = mi
	(rub as Node3D).visible = true

func _kill_tween(p: Dictionary) -> void:
	var tw: Variant = p["tween"]
	if tw != null and tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	p["tween"] = null

# ============================== respawn ==============================

## Respawn timers, called once per fixed sim step by MatchSim.step. No allocation while nothing is pending; a respawn that
## would materialise inside a fighter is postponed by the config's retrySeconds instead of trapping them.
func step(dt: float) -> void:
	if _pending.is_empty(): return
	var i := _pending.size() - 1
	while i >= 0:
		var pi: int = _pending[i]
		var p: Dictionary = props[pi]
		var t := float(p["respawn_t"]) - dt
		p["respawn_t"] = t
		if t <= 0.0:
			if _blocked(p):
				p["respawn_t"] = float(_cfg["retry"])
			else:
				_respawn(pi)
				_pending.remove_at(i)
		i -= 1

## True when a living fighter overlaps the component's box (so it cannot materialise there yet).
func _blocked(p: Dictionary) -> bool:
	if sim == null: return false
	var r := FighterPhysics.R
	var min_x := float(p["min_x"])
	var max_x := float(p["max_x"])
	var min_z := float(p["min_z"])
	var max_z := float(p["max_z"])
	var bottom := float(p["bottom"])
	var top := float(p["top"])
	for f: FighterState in sim.fighters:
		if f.dead or f.is_ghost: continue
		var px := f.phys.px
		var py := f.phys.py
		var pz := f.phys.pz
		if px + r <= min_x or px - r >= max_x: continue
		if pz + r <= min_z or pz - r >= max_z: continue
		if py + 1.8 <= bottom or py >= top: continue
		return true
	return false

func _respawn(index: int) -> void:
	var p: Dictionary = props[index]
	p["broken"] = false
	p["hp"] = float(p["max_hp"])
	_broken = maxi(0, _broken - 1)
	var solid: Dictionary = p["solid"]
	solid["breakable"] = true
	solid["broken"] = false
	if solids.find(solid) < 0: solids.append(solid)
	var rub: Variant = p["rubble"]
	if rub != null and is_instance_valid(rub): (rub as Node3D).visible = false
	var mesh: Variant = p["mesh"]
	if mesh != null and is_instance_valid(mesh):
		(mesh as Node3D).visible = true
		for raw: Variant in (p["mesh_nodes"] as Array):
			if raw is MeshInstance3D: (raw as MeshInstance3D).transparency = 1.0
		var tw := (mesh as Node3D).create_tween()
		tw.set_parallel(true)
		for raw: Variant in (p["mesh_nodes"] as Array):
			if raw is MeshInstance3D: tw.tween_property(raw, "transparency", 0.0, float(_cfg["fade"]))
		p["tween"] = tw
	p["respawn_t"] = 0.0
	events.append({"type": "prop_respawn", "id": p["id"], "kind": p["kind"], "index": index,
		"x": float(p["x"]), "y": float(p["y"]), "z": float(p["z"]), "w": float(p["w"]), "h": float(p["h"]),
		"d": float(p["d"]), "color": int(p["color"]), "total": props.size(), "broken": _broken})
	events.append({"type": "sfx", "name": "pop", "x": float(p["x"]), "y": float(p["y"]) + float(p["h"]) * 0.5, "z": float(p["z"])})

# ============================== queries ==============================

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

## Seconds left until prop `index` respawns (-1 when it is not broken).
func respawn_delay(index: int) -> float:
	if index < 0 or index >= props.size(): return -1.0
	if not bool(props[index]["broken"]): return -1.0
	return float(props[index]["respawn_t"])

func pending_count() -> int:
	return _pending.size()

func rubble_count() -> int:
	var n := 0
	for p: Dictionary in props:
		var r: Variant = p["rubble"]
		if r != null and is_instance_valid(r): n += 1
	return n

## Rubble nodes currently visible (one reused node per component that has ever broken).
func rubble_visible_count() -> int:
	var n := 0
	for p: Dictionary in props:
		var r: Variant = p["rubble"]
		if r != null and is_instance_valid(r) and (r as Node3D).visible: n += 1
	return n

## A prop's live geometry: {id, kind, index, x, y, z, w, h, d, hp, max_hp, color, broken, respawn_t, breaks}.
func prop_info(index: int) -> Dictionary:
	if index < 0 or index >= props.size(): return {}
	var p: Dictionary = props[index]
	return {"id": p["id"], "kind": p["kind"], "index": index, "x": p["x"], "y": p["y"], "z": p["z"],
		"w": p["w"], "h": p["h"], "d": p["d"], "hp": p["hp"], "max_hp": p["max_hp"], "color": p["color"],
		"broken": p["broken"], "respawn_t": p["respawn_t"], "breaks": p["breaks"]}

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
	sim = null
	arena = ""
	merge_exclude = {}
	merged_pruned = false
	_broken = 0
	_pending.clear()
	_mats.clear()
	_accent_mat = null
	_rubble_mats.clear()

# ============================== helpers ==============================

static func _mix_seed(tag: String, seed: int) -> int:
	var h := 2166136261
	for b in tag.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	h = (h ^ (seed & 0xFFFFFFFF)) & 0xFFFFFFFF
	h = (h * 2654435761) & 0xFFFFFFFF
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	return h

static func _solids_of(map: Dictionary) -> Array:
	var out: Array = []
	var geo: Variant = map.get("geometry")
	if not (geo is Dictionary): return out
	for b: Variant in ((geo as Dictionary).get("boxes", []) as Array):
		if not (b is Dictionary): continue
		var box: Dictionary = b
		var w := float(box.get("w", 0.0))
		var d := float(box.get("d", 0.0))
		var y := float(box.get("y", 0.0))
		var h := float(box.get("h", 0.0))
		out.append({"minX": float(box.get("x", 0.0)) - w / 2.0, "maxX": float(box.get("x", 0.0)) + w / 2.0,
			"minZ": float(box.get("z", 0.0)) - d / 2.0, "maxZ": float(box.get("z", 0.0)) + d / 2.0,
			"top": y + h, "bottom": y})
	return out

static func _has_floor(solids: Array, x: float, z: float, y: float, tol := 0.25) -> bool:
	for b: Dictionary in solids:
		if x < float(b["minX"]) - 1e-6 or x > float(b["maxX"]) + 1e-6: continue
		if z < float(b["minZ"]) - 1e-6 or z > float(b["maxZ"]) + 1e-6: continue
		if absf(float(b["top"]) - y) <= tol: return true
	return false

## A ring of floor all round the footprint: a ring-out boundary wall fails it, interior cover passes.
static func _margin_supported(solids: Array, rect: Dictionary, y: float, margin: float) -> bool:
	var min_x := float(rect["minX"])
	var max_x := float(rect["maxX"])
	var min_z := float(rect["minZ"])
	var max_z := float(rect["maxZ"])
	var mx := (min_x + max_x) * 0.5
	var mz := (min_z + max_z) * 0.5
	var pts := [
		[min_x - margin, mz], [max_x + margin, mz], [mx, min_z - margin], [mx, max_z + margin],
		[min_x - 0.6, min_z - 0.6], [max_x + 0.6, min_z - 0.6], [min_x - 0.6, max_z + 0.6], [max_x + 0.6, max_z + 0.6],
	]
	for q: Array in pts:
		if _has_floor(solids, float(q[0]), float(q[1]), y): continue
		return false
	return true

## Distance from a point to a footprint rectangle (0 when inside it).
static func _rect_dist(px: float, pz: float, rect: Dictionary) -> float:
	var dx := maxf(maxf(float(rect["minX"]) - px, 0.0), px - float(rect["maxX"]))
	var dz := maxf(maxf(float(rect["minZ"]) - pz, 0.0), pz - float(rect["maxZ"]))
	return sqrt(dx * dx + dz * dz)
