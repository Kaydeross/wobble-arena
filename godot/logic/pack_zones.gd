class_name PackZones
extends RefCounted
## DLC pack arena hazards (Kitchen "On Fire", Xmas "Ho Ho Ho", Australia "Hey Mate"): a Godot-only overlay in the pattern of
## logic/ledge.gd (docs/DAMAGE.md "Ledge cling"). MatchSim creates one ONLY when `Combat.tuning_active()` is on (offline, or
## online with net_zones) AND the arena carries a `zones` list (or a stage event asks for one through MatchSim.ensure_zones());
## in every other match `MatchSim.zones` is null, so the web game, the JS parity suites and online-without-net_zones matches
## execute exactly one `!= null` test per step and nothing else. Nothing here draws a random number or touches
## FighterPhysics: ice reuses the existing `ice_grip` steering flag (set for a fighter standing in an ice zone, restored to the
## arena's own `grip` flag everywhere else), burners reuse the existing on-fire status (`burn`, ticked by Combat.timers),
## the Hills Hoist is a rotating hit band through Combat.hit.
##
## A zone is a Dictionary (maps carry them as `map.zones`, stage events add temporary ones with add()):
##   {kind: "burner", rect: [x0, z0, x1, z1] | c: [x, z], r, top}   damage over time while you stand on it (floor or stove top `top`)
##   {kind: "ice",    rect | c + r}                                  slippery floor: the ice-grip steering while grounded in it
##   {kind: "hoist",  x, z, r, arms, omega, phase, y0, y1}           spinning bar(s): anyone inside the band is knocked sideways
## `temp` zones (events) may carry `left` seconds; update() removes them when they run out.

const BURN_TIME := 1.3          ## s of the existing on-fire status refreshed every step on a burner
const BURN_TOP_BELOW := 0.5     ## feet may be this far under a burner's `top` and still stand on it
const BURN_TOP_ABOVE := 0.45    ## ... or this far above (a step up onto a low plate)
const HOIST_DMG := 6.0
const HOIST_FORCE := 9.0
const HOIST_COOLDOWN := 0.8
const HOIST_WIDTH := 0.55       ## m: half the width of an arm's hit band
const ICE_TOP_ABOVE := 0.6      ## a fighter this far above the ice (on a counter, in the air) is not on it

## Presentation only: the sim clock PackSpinner reads to turn the hoist in step with the hit band (0 without a sim).
static var clock := 0.0

var sim: MatchSim = null
var zones: Array = []
var base_grip := false
var burn_hits := 0               ## fighter-steps spent on a burner (tests)
var hoist_hits := 0              ## hoist knocks (tests)
var _cool := {}                  ## FighterState -> seconds until the hoist can hit it again

## True when the arena carries zones (MatchSim creates the overlay only then, plus under tuning).
static func wanted(map: Dictionary) -> bool:
	var z: Variant = map.get("zones")
	return z is Array and not (z as Array).is_empty()

func setup(p_sim: MatchSim) -> void:
	sim = p_sim
	base_grip = bool(sim.map.get("grip", false))
	zones = []
	var src: Variant = sim.map.get("zones")
	if src is Array:
		for z: Variant in src:
			if z is Dictionary: zones.append((z as Dictionary).duplicate(true))
	clock = 0.0

func dispose() -> void:
	sim = null
	zones = []
	_cool.clear()

func add(z: Dictionary) -> Dictionary:
	zones.append(z)
	return z

func remove(z: Dictionary) -> void:
	zones.erase(z)

func has_kind(kind: String) -> bool:
	for z: Dictionary in zones:
		if str(z.get("kind", "")) == kind: return true
	return false

## Is (x, z) inside the zone's footprint (rect or circle), grown by `pad` metres?
static func inside(z: Dictionary, x: float, zz: float, pad := 0.0) -> bool:
	if z.has("rect"):
		var r: Array = z["rect"]
		return x >= float(r[0]) - pad and x <= float(r[2]) + pad and zz >= float(r[1]) - pad and zz <= float(r[3]) + pad
	if z.has("c"):
		var c: Array = z["c"]
		var rr := float(z.get("r", 1.0)) + pad
		var dx := x - float(c[0])
		var dz := zz - float(c[1])
		return dx * dx + dz * dz <= rr * rr
	return false

## Distance from (x, z) to the zone (0 inside it); a hoist counts as its sweep disc. Map builders use it to keep spawns and crates off hazards.
static func distance(z: Dictionary, x: float, zz: float) -> float:
	match str(z.get("kind", "")):
		"hoist":
			return maxf(0.0, Vector2(x - float(z["x"]), zz - float(z["z"])).length() - float(z["r"]))
		_:
			if z.has("rect"):
				var r: Array = z["rect"]
				var dx := maxf(0.0, maxf(float(r[0]) - x, x - float(r[2])))
				var dz := maxf(0.0, maxf(float(r[1]) - zz, zz - float(r[3])))
				return sqrt(dx * dx + dz * dz)
			if z.has("c"):
				var c: Array = z["c"]
				return maxf(0.0, Vector2(x - float(c[0]), zz - float(c[1])).length() - float(z.get("r", 1.0)))
	return 1e9

## Is a fighter standing at (x, y, z) on ice? Pure geometry (no fighter state): the test and the steering share it.
func on_ice(x: float, y: float, z: float) -> bool:
	for zn: Dictionary in zones:
		if str(zn.get("kind", "")) != "ice": continue
		if inside(zn, x, z) and y <= float(zn.get("top", 0.0)) + ICE_TOP_ABOVE: return true
	return false

func on_burner(x: float, y: float, z: float) -> bool:
	for zn: Dictionary in zones:
		if str(zn.get("kind", "")) != "burner": continue
		var top := float(zn.get("top", 0.0))
		if inside(zn, x, z) and y <= top + BURN_TOP_ABOVE and y >= top - BURN_TOP_BELOW: return true
	return false

## The angle of arm `k` of hoist `z` at sim time `t` (radians in the x / z plane).
static func hoist_angle(z: Dictionary, t: float, k := 0) -> float:
	return float(z.get("phase", 0.0)) + float(z.get("omega", 1.0)) * t + TAU * float(k) / maxf(1.0, float(z.get("arms", 4)))

# ---------------------------------------------------------------- per step (MatchSim.step)

## Before the fighters move: the ice steering flag for each of them (a fighter in an ice zone steers like the Ice Rink).
func pre_step() -> void:
	if sim == null: return
	var any_ice := has_kind("ice")
	for f: FighterState in sim.fighters:
		if f.is_ghost: continue
		var ph := f.phys
		ph.ice_grip = base_grip or (any_ice and ph.grounded and on_ice(ph.px, ph.py, ph.pz))

## After the fighters moved: burners set fighters alight, the hoist knocks them, temporary zones expire.
func post_step(dt: float) -> void:
	if sim == null: return
	var t := sim.combat.time
	clock = t - sim.match_start
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if z.has("left"):
			z["left"] = float(z["left"]) - dt
			if float(z["left"]) <= 0.0: zones.remove_at(i)
	for k: Variant in _cool.keys():
		_cool[k] = float(_cool[k]) - dt
		if float(_cool[k]) <= 0.0: _cool.erase(k)
	if zones.is_empty(): return
	for f: FighterState in sim.fighters:
		if f.dead or f.is_ghost: continue
		var ph := f.phys
		for z: Dictionary in zones:
			match str(z.get("kind", "")):
				"burner":
					if on_burner(ph.px, ph.py, ph.pz):
						f.burn = maxf(f.burn, BURN_TIME); burn_hits += 1
				"hoist":
					if not _cool.has(f): _hoist_hit(z, f)

func _hoist_hit(z: Dictionary, f: FighterState) -> void:
	var ph := f.phys
	if ph.py > float(z.get("y1", 1.7)) or ph.py + FighterPhysics.FH < float(z.get("y0", 0.8)): return   # jumped clear / under it
	var dx := ph.px - float(z["x"])
	var dz := ph.pz - float(z["z"])
	var r := sqrt(dx * dx + dz * dz)
	if r < 0.5 or r > float(z["r"]) + 0.4: return
	var fa := atan2(dz, dx)
	var arms := maxi(1, int(z.get("arms", 4)))
	var span := TAU / float(arms)
	var rel := fposmod(fa - hoist_angle(z, clock, 0), span)
	if rel > span / 2.0: rel -= span
	var half := atan(HOIST_WIDTH / maxf(r, 0.6)) + absf(float(z.get("omega", 1.0))) * 0.04
	if absf(rel) > half: return
	var dir := signf(float(z.get("omega", 1.0)))
	var nx := -sin(fa) * dir          # along the sweep
	var nz := cos(fa) * dir
	var ox := dx / r
	var oz := dz / r
	sim.combat.hit(f, HOIST_DMG, nx * 0.8 + ox * 0.35, 0.55, nz * 0.8 + oz * 0.35, HOIST_FORCE, false, null)
	sim.combat.ev({"type": "sfx", "name": "drop"})
	_cool[f] = HOIST_COOLDOWN
	hoist_hits += 1
