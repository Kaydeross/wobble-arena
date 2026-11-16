class_name Ledge
extends RefCounted
## Ledge cling (Godot-only overlay, docs/DAMAGE.md "Ledge cling and throwable rubble").
##
## A fighter who walks off a platform, or is knocked past its edge but is still touching it, catches the ledge: the body
## is pinned just outside the platform face, hands at its top, and it hangs. JUMP climbs up (a short snap over the lip),
## CROUCH lets go. Bots use it too (BotBrain's ledge probe steers a falling bot toward a catchable lip and climbs after a
## moment, bot_brain.gd).
##
## Gate: only a match where `Combat.tuning_active()` is on (offline, or online with net_zones) runs this; MatchSim only
## creates a Ledge in that case, and a FighterState's `hang` stays empty in every other match, so the web game, the JS
## parity suites and online matches without net_zones are bit-identical. Nothing here draws a random number.
##
## Tuning is the overlay godot/data/extra/ledge.json (never shared/*.json); the geometry helpers are static so the bot
## probe can ask the same question without an instance.

const DATA_PATH := "res://data/extra/ledge.json"
const VERSION := 1
## Fallbacks for an overlay field that is missing: the shipped values (see the JSON's comment).
const DEFAULTS := {
	"enabled": true,
	"topMin": 1.1, "topMax": 2.2, "reach": 0.35, "maxRise": 0.0, "hangDrop": 1.35, "cooldown": 0.45,
	"inset": 0.35, "rise": 0.03, "push": 1.6, "botClimbDelay": 0.25, "probeRange": 2.8,
}
const LATERAL_SLOP := 0.25        ## m: a ledge face counts while the body is within this of its span
const HIT_CATCH_DELAY := 0.3      ## s after being hit in which a fighter cannot grab: a hit knocks a hanging one off

var cfg: Dictionary = {}
var sim: MatchSim = null

## Parsed overlay, cached like every other res://data JSON (Combat.read_json's cache).
static func load_data() -> Dictionary:
	var parsed: Variant = Combat.read_json(DATA_PATH)
	return parsed if parsed is Dictionary else {}

## Flatten one overlay dictionary to the numeric fields the code reads, with the DEFAULTS for anything missing or bad.
static func config(data: Dictionary = {}) -> Dictionary:
	var out := DEFAULTS.duplicate()
	if not data is Dictionary:
		return out
	var sections := {"catch": ["topMin", "topMax", "reach", "maxRise", "hangDrop", "cooldown"],
		"climb": ["inset", "rise"], "drop": ["push"], "bot": ["climbDelay", "probeRange"]}
	for key: String in ["enabled"]:
		if data.has(key) and data[key] is bool: out[key] = data[key]
	for sec: String in sections:
		var d: Variant = data.get(sec)
		if not d is Dictionary: continue
		for key: String in sections[sec]:
			var v: Variant = (d as Dictionary).get(key)
			if v is float or v is int: out[key] = float(v)
	return out

## Every overlay problem (the test asserts the shipped file is clean and a bad one cannot break a match). [] = fine.
static func validate(data: Dictionary = {}) -> Array:
	var errs: Array = []
	if not data is Dictionary or (data as Dictionary).is_empty():
		return ["ledge.json missing or not an object"]
	if int(data.get("version", 0)) != VERSION: errs.append("version must be %d" % VERSION)
	var secs := {"catch": ["topMin", "topMax", "reach", "maxRise", "hangDrop", "cooldown"],
		"climb": ["inset", "rise"], "drop": ["push"], "bot": ["climbDelay", "probeRange"]}
	for sec: String in secs:
		var d: Variant = data.get(sec)
		if not d is Dictionary: errs.append("missing section " + sec); continue
		for key: String in secs[sec]:
			var v: Variant = (d as Dictionary).get(key)
			if not (v is float or v is int): errs.append("%s.%s not a number" % [sec, key])
			elif float(v) < 0.0: errs.append("%s.%s negative" % [sec, key])
	if errs.is_empty():
		if float(data["catch"]["topMin"]) >= float(data["catch"]["topMax"]): errs.append("catch.topMin must be below topMax")
		if float(data["catch"]["hangDrop"]) < float(data["catch"]["topMin"]): errs.append("catch.hangDrop must be at least topMin")
		if float(data["catch"]["topMax"]) > 4.0: errs.append("catch.topMax beyond the body height")
	return errs

## True when the overlay is enabled (MatchSim creates a Ledge only then).
static func enabled() -> bool:
	return bool(config(load_data()).get("enabled", true))

func setup(p_sim: MatchSim) -> void:
	sim = p_sim
	cfg = config(load_data())

# ============================== per step (MatchSim.step, after the fighters' physics) ==============================

## One fixed step for `f` (a fighter whose physics just ran): hold a hang, or catch a new ledge.
func after_step(f: FighterState, dt: float) -> void:
	if f.hang_cool > 0.0:
		f.hang_cool = maxf(0.0, f.hang_cool - dt)
	if not f.hang.is_empty():
		_hold(f, dt)
		return
	if not _can_catch(f):
		return
	var c := candidate(sim.solids, f.phys.px, f.phys.py, f.phys.pz, cfg)
	if c.is_empty():
		return
	_grab(f, c)

func _can_catch(f: FighterState) -> bool:
	var p := f.phys
	if sim == null or sim.combat.time - f.last_hit_time < HIT_CATCH_DELAY: return false
	return not p.grounded and p.vy <= float(cfg["maxRise"]) and f.hang_cool <= 0.0 and not f.dead \
		and f.down_t <= 0.0 and f.trap_t <= 0.0 and f.carried_by == null and f.ball_t < 0.0 and f.swing < 0.0

func _grab(f: FighterState, c: Dictionary) -> void:
	var top := float(c["top"])
	f.hang = {"solid": c["solid"], "x": float(c["x"]), "z": float(c["z"]), "nx": float(c["nx"]), "nz": float(c["nz"]), "top": top}
	f.hang_t = 0.0
	f.hang_drop = false
	var p := f.phys
	p.px = float(f.hang["x"]); p.pz = float(f.hang["z"])
	p.py = top - float(cfg["hangDrop"])
	p.vx = 0.0; p.vy = 0.0; p.vz = 0.0; p.grounded = false
	p.want_jump = false
	sim.combat.ev({"type": "ledge", "f": f, "kind": "catch"})

## Pinned while hanging; the ledge (a live solid dictionary) may move with the floor or disappear when broken, so the
## top is re-read every step and a vanished ledge lets go.
func _hold(f: FighterState, dt: float) -> void:
	var h: Dictionary = f.hang
	var solid: Variant = h.get("solid")
	if not (solid is Dictionary) or not sim.solids.has(solid) or bool((solid as Dictionary).get("broken", false)):
		_release(f, false)
		return
	var top := float((solid as Dictionary)["top"])
	h["top"] = top
	var p := f.phys
	p.px = float(h["x"]); p.pz = float(h["z"])
	p.py = top - float(cfg["hangDrop"])
	p.vx = 0.0; p.vy = 0.0; p.vz = 0.0; p.grounded = false
	f.hang_t += dt
	if f.hang_drop:
		_release(f, true)
		return
	if p.want_jump:
		p.want_jump = false
		_climb(f, h, top)

func _climb(f: FighterState, h: Dictionary, top: float) -> void:
	var nx := float(h["nx"])
	var nz := float(h["nz"])
	var p := f.phys
	var inset := FighterPhysics.R * 0.9 + float(cfg["inset"])   # from the pinned hang point to just inside the lip
	p.px = float(h["x"]) - nx * inset
	p.pz = float(h["z"]) - nz * inset
	p.py = top + float(cfg["rise"])
	p.vx = -nx * 1.2; p.vy = 0.0; p.vz = -nz * 1.2; p.grounded = true
	f.hang = {}; f.hang_t = 0.0; f.hang_drop = false; f.hang_cool = float(cfg["cooldown"])
	sim.combat.ev({"type": "ledge", "f": f, "kind": "climb"})

func _release(f: FighterState, push: bool) -> void:
	var h: Dictionary = f.hang
	f.hang = {}; f.hang_t = 0.0; f.hang_drop = false; f.hang_cool = float(cfg["cooldown"])
	var p := f.phys
	if push:
		p.vx = float(h["nx"]) * float(cfg["push"])
		p.vz = float(h["nz"]) * float(cfg["push"])
		p.vy = -0.5
	p.grounded = false
	sim.combat.ev({"type": "ledge", "f": f, "kind": "drop"})

# ============================== geometry ==============================

## The nearest catchable ledge beside (px, py, pz): {} or {solid, x, z, nx, nz, top}. `x`/`z` are the pinned hang point
## (body radius outside the face), (nx, nz) the face's outward normal. Shared by the catch and the bots' edge probe.
static func candidate(solids: Array, px: float, py: float, pz: float, cfg: Dictionary) -> Dictionary:
	var best := {}
	var bd := 1e9
	var reach := float(cfg["reach"])
	var top_min := float(cfg["topMin"])
	var top_max := float(cfg["topMax"])
	for raw: Variant in solids:
		if not (raw is Dictionary): continue
		var b: Dictionary = raw
		var top := float(b["top"])
		var above := top - py
		if above < top_min or above > top_max: continue
		var min_x := float(b["minX"]); var max_x := float(b["maxX"])
		var min_z := float(b["minZ"]); var max_z := float(b["maxZ"])
		# Four vertical faces. d = how far outside the face the body centre is (negative = not beside it); a catch needs
		# the body touching the face: from 0 to R + reach out.
		var faces := [
			[px, min_x - px, -1.0, 0.0, pz, min_z, max_z],
			[px, px - max_x, 1.0, 0.0, pz, min_z, max_z],
			[pz, min_z - pz, 0.0, -1.0, px, min_x, max_x],
			[pz, pz - max_z, 0.0, 1.0, px, min_x, max_x],
		]
		for face: Array in faces:
			var d := float(face[1])
			if d < 0.0 or d > FighterPhysics.R + reach: continue
			var lat := float(face[4])
			if lat < float(face[5]) - LATERAL_SLOP or lat > float(face[6]) + LATERAL_SLOP: continue
			if d >= bd: continue
			bd = d
			var nx := float(face[2])
			var nz := float(face[3])
			best = {"solid": b, "x": px - nx * (d - FighterPhysics.R * 0.9), "z": pz - nz * (d - FighterPhysics.R * 0.9),
				"nx": nx, "nz": nz, "top": top}
	return best

## Bot edge probe: where a falling bot should steer to reach a catchable ledge, {} if none is close. `px, py, pz` and the
## probe range come from the bot; the geometry is the same as the catch.
func probe(p: FighterPhysics) -> Dictionary:
	if sim == null: return {}
	var c := candidate(sim.solids, p.px, p.py, p.pz, cfg)
	if c.is_empty(): return {}
	var dx := float(c["x"]) - p.px
	var dz := float(c["z"]) - p.pz
	if sqrt(dx * dx + dz * dz) > float(cfg["probeRange"]): return {}
	return {"x": float(c["x"]), "z": float(c["z"]), "top": float(c["top"])}

## True while `f` hangs on a ledge (for tests / the presentation).
static func hanging(f: FighterState) -> bool:
	return not f.hang.is_empty()
