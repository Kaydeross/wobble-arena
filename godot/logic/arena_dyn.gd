class_name ArenaDyn
extends RefCounted
## Dynamic arenas runtime (pure logic, no nodes): the gameplay half of dynSetup / dynBuildTiles / dynBuildDrift /
## dynSupport / updateDyn / dynFloorDy in public/index.html. MatchSim owns one; the world reads it to move the meshes.
## The clock is deterministic: t = match time + t0 (t0 = `dt0` from start.rules online), seed = `dseed`.

var kind := "off"                 ## what runs: off | wobble | tilt | quake | drift
var choice := "off"               ## what was asked for (off | random | a kind)
var seed := 0
var plan: Dictionary = {}
var tiles: Array = []             ## {s, ix, iz, mask, off, dy, low}  (s = the tile's solid, in sim.solids)
var drift: Array = []             ## {s, i, axis, bi, d, dd}          (i = the block's index in the map's boxes)
var support := {"tile": false, "drift": false}
## Chaos floor event (Godot-only): another tile kind blended over this one for a while (ModeRules.update_chaos).
var force_k := ""                 ## the forced kind ("" = none)
var force_w := 0.0                ## its blend weight, eases 0 -> 1 -> 0 over FORCE_RAMP so tiles never jump
var force_left := 0.0
var _force_t := -1.0
const FORCE_RAMP := 1.0
var fx: Array = []                ## quake moments for the world: {type: "drop" | "rise", x, y, z}; the world drains it

## dynSetup (from MatchSim.setup, after the solids are loaded). Splits the floor into tiles in `solids` in place.
func setup(map_id: String, map: Dictionary, solids: Array, ladders: Array, pads: Array, p_choice: String, p_seed: int) -> void:
	kind = "off"; plan = {}; tiles = []; drift = []; fx = []
	force_k = ""; force_w = 0.0; force_left = 0.0; _force_t = -1.0
	support = {"tile": false, "drift": false}
	choice = p_choice if Dynamics.KINDS.has(p_choice) else "off"
	seed = p_seed & Dynamics.U32
	if not Dynamics.map_allowed(map_id, map): return
	var spawns: Array = map.get("spawns", []) + map.get("bots", []) + ([map["player"]] if map.has("player") else [])
	var lad: Array = []
	for l: Dictionary in ladders: lad.append({"x": float(l["x"]), "z": float(l["z"])})
	var pd: Array = []
	for q: Dictionary in pads: pd.append({"x": float(q["x"]), "z": float(q["z"]), "r": float(q.get("r", 1.2))})
	var p := Dynamics.plan(solids, lad, pd, spawns)
	support = {"tile": p["canTile"], "drift": p["drift"].size() > 0}
	if choice == "off": return
	var k := Dynamics.resolve(choice, seed, p["canTile"], p["drift"].size() > 0)
	if k == "off": return
	kind = k; plan = p
	if kind == "drift": _build_drift(solids)
	else: _build_tiles(solids)

## dynBuildTiles (collision half): the tiles take the floor's place in the collision list, same order as the web game.
func _build_tiles(solids: Array) -> void:
	var fi: int = plan["floor"]
	var F: Dictionary = solids[fi]
	var nx: int = plan["nx"]
	var nz: int = plan["nz"]
	var tw: float = (F.maxX - F.minX) / nx
	var td: float = (F.maxZ - F.minZ) / nz
	plan["x0"] = F.minX; plan["z0"] = F.minZ; plan["tw"] = tw; plan["td"] = td
	plan["top"] = F.top; plan["bottom"] = F.bottom
	var tiles_s: Array = []
	for iz in nz:
		for ix in nx:
			var s := {"minX": F.minX + ix * tw, "maxX": F.maxX if ix == nx - 1 else F.minX + (ix + 1) * tw,
				"minZ": F.minZ + iz * td, "maxZ": F.maxZ if iz == nz - 1 else F.minZ + (iz + 1) * td, "top": F.top, "bottom": F.bottom}
			tiles_s.append(s)
			tiles.append({"s": s, "ix": ix, "iz": iz, "mask": plan["mask"][iz * nx + ix], "off": 0.0, "dy": 0.0, "low": false})
	solids.remove_at(fi)
	for k in range(tiles_s.size() - 1, -1, -1):
		solids.insert(fi, tiles_s[k])

func _build_drift(solids: Array) -> void:
	var bi := 0
	for d: Dictionary in plan["drift"]:
		drift.append({"s": solids[d["i"]], "i": d["i"], "axis": d["axis"], "bi": bi, "d": 0.0, "dd": 0.0})
		bi += 1

## Can the Chaos floor event run here? (tiles that move up and down: wobble / tilt / quake)
func can_force() -> bool:
	return (kind == "wobble" or kind == "tilt" or kind == "quake") and not tiles.is_empty()

## The kind the floor event forces: a quake, or a wobble where the floor already quakes.
func force_kind() -> String:
	return "wobble" if kind == "quake" else "quake"

## Blend `k` over the floor for `dur` seconds ("" = ease back now).
func force(k: String, dur: float) -> void:
	if k == "" or not can_force(): force_left = 0.0; return
	force_k = k; force_left = dur

## dynSupport: the moving thing a fighter stands on (highest top), or {}.
static func support_of(f: FighterState, list: Array) -> Dictionary:
	if f.is_ghost or not f.phys.grounded or f.dead: return {}
	var p := f.phys
	var R := FighterPhysics.R
	var best: Dictionary = {}
	for e: Dictionary in list:
		var s: Dictionary = e["s"]
		if absf(p.py - s.top) < 0.002 and p.px > s.minX - R and p.px < s.maxX + R and p.pz > s.minZ - R and p.pz < s.maxZ + R \
				and (best.is_empty() or s.top > best["s"].top):
			best = e
	return best

## updateDyn: move tiles / blocks to match time t and carry whoever stands on them. Runs first in every sim step.
func update(t: float, fighters: Array) -> void:
	if kind == "off": return
	if kind == "drift":
		var on_d: Array = []
		for f: FighterState in fighters: on_d.append(support_of(f, drift))
		for e: Dictionary in drift:
			var d := Dynamics.delta(seed, t, e["bi"])
			var dd: float = d - e["d"]
			e["dd"] = dd
			if dd == 0.0: continue
			e["d"] = d
			var s: Dictionary = e["s"]
			if e["axis"] == "x": s["minX"] += dd; s["maxX"] += dd
			else: s["minZ"] += dd; s["maxZ"] += dd
		for i in fighters.size():
			var e: Dictionary = on_d[i]
			if e.is_empty() or e["dd"] == 0.0: continue
			var ph: FighterPhysics = fighters[i].phys
			if e["axis"] == "x": ph.px += e["dd"]
			else: ph.pz += e["dd"]
		return
	var nx: int = plan["nx"]
	var nz: int = plan["nz"]
	if force_k != "":                                    # Chaos floor event: ease in, hold, ease out
		var fdt := clampf(t - _force_t, 0.0, 0.1) if _force_t >= 0.0 else 0.0
		force_left -= fdt
		force_w = clampf(force_w + (fdt if force_left > 0.0 else -fdt) / FORCE_RAMP, 0.0, 1.0)
		if force_left <= 0.0 and force_w <= 0.0: force_k = ""
	_force_t = t
	var quake := kind == "quake" or (force_k == "quake" and force_w > 0.5)
	var on: Array = []
	for f: FighterState in fighters: on.append(support_of(f, tiles))
	for e: Dictionary in tiles:
		var off := Dynamics.offset(kind, seed, t, e["ix"], e["iz"], nx, nz, e["mask"])
		if force_k != "" and force_w > 0.0:
			off = lerpf(off, Dynamics.offset(force_k, seed, t, e["ix"], e["iz"], nx, nz, e["mask"]), force_w)
		var dy: float = off - e["off"]
		e["dy"] = dy
		if dy == 0.0: continue
		var s: Dictionary = e["s"]
		if quake:
			var cx: float = (s.minX + s.maxX) * 0.5
			var cz: float = (s.minZ + s.maxZ) * 0.5
			if not e["low"] and off <= -0.3:
				e["low"] = true; fx.append({"type": "drop", "x": cx, "y": s.top, "z": cz})
			elif e["low"] and off >= -0.02:
				e["low"] = false; fx.append({"type": "rise", "x": cx, "y": off, "z": cz})
		e["off"] = off
		s["top"] += dy; s["bottom"] += dy
	if fx.size() > 64: fx = fx.slice(fx.size() - 64)      # nobody drained them (headless)
	for i in fighters.size():
		var e: Dictionary = on[i]
		if e.is_empty(): continue
		var dy: float = e["dy"]
		if dy != 0.0 and absf(dy) <= 0.03: fighters[i].phys.py += dy

## dynFloorDy: how far the floor at (x, z) is off its normal height (crates sit on it).
func floor_dy(x: float, z: float) -> float:
	if kind == "off" or kind == "drift" or plan.is_empty(): return 0.0
	var ix := int(floor((x - plan["x0"]) / plan["tw"]))
	var iz := int(floor((z - plan["z0"]) / plan["td"]))
	var nx: int = plan["nx"]
	return tiles[iz * nx + ix]["off"] if ix >= 0 and ix < nx and iz >= 0 and iz < plan["nz"] else 0.0
