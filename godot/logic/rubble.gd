class_name Rubble
extends RefCounted
## Throwable rubble (Godot-only overlay, docs/DAMAGE.md "Ledge cling and throwable rubble").
##
## The destructible mode breaks cover into debris (world/prop_debris.gd, presentation only). This class keeps ONE logical
## chunk of each break on the floor: SHOVE next to it picks it up, FIRE throws it at the crosshair (SHOVE while holding
## puts it down), and a thrown chunk is a light projectile resolved by the thrower through the shared `Combat.hit` path.
## Bots throw rubble at range too (bot_brain.gd).
##
## Gate: MatchSim creates a Rubble only for an offline match with `Combat.tuning_active()` AND the destructible mode on
## (destructibles are offline-only, so rubble is offline by construction). The web game and the JS parity suites never
## see one; a match without rubble has `sim.rubble == null` and every caller costs one null check. Damage is decided by
## the thrower like every other attacker-side hit, so a thrown chunk needs NO protocol message (the note in docs/DAMAGE.md
## keeps this decision). Nothing here draws a combat random number: the chunk placement uses its own seeded RNG.
##
## Tuning is the overlay godot/data/extra/rubble.json (never shared/*.json).

const DATA_PATH := "res://data/extra/rubble.json"
const VERSION := 1
const DEFAULTS := {
	"enabled": true,
	"damage": 16.0, "force": 13.0, "speed": 17.0, "up": 3.2, "gravity": 22.0, "life": 16.0,
	"maxChunks": 8, "pickupRange": 1.9, "cooldown": 0.45, "radius": 0.28, "hitRadius": 0.55,
	"botGrab": 9.0, "botThrowMin": 2.5, "botThrowMax": 14.0, "botThink": 0.35,
}
const FLIGHT_TIME := 6.0          ## s a thrown chunk is tracked before it is dropped (out of bounds / stuck)
const VERTICAL_REACH := 1.9       ## m: how far above/below a resting chunk a fighter can pick it up

## One chunk: {id, state ("rest"|"fly"|"held"), x, y, z, vx, vy, vz, ground, life, fly_t, size, color, owner}
var chunks: Array = []
var held := {}                    ## FighterState -> chunk
var sim: MatchSim = null
var cfg: Dictionary = {}
var throws := 0                   ## test / HUD counters
var picks := 0
var hits := 0
var _next_id := 1
var _rng := RandomNumberGenerator.new()

static func load_data() -> Dictionary:
	var parsed: Variant = Combat.read_json(DATA_PATH)
	return parsed if parsed is Dictionary else {}

static func config(data: Dictionary = {}) -> Dictionary:
	var out := DEFAULTS.duplicate()
	if not data is Dictionary:
		return out
	if data.get("enabled") is bool: out["enabled"] = data["enabled"]
	for key: String in DEFAULTS:
		var v: Variant = data.get(key)
		if v is float or v is int: out[key] = float(v)
		if v is bool: out[key] = v
	var b: Variant = data.get("bot")
	if b is Dictionary:
		var m := {"grab": "botGrab", "throwMin": "botThrowMin", "throwMax": "botThrowMax", "think": "botThink"}
		for k: String in m:
			var v: Variant = (b as Dictionary).get(k)
			if v is float or v is int: out[m[k]] = float(v)
	return out

static func validate(data: Dictionary = {}) -> Array:
	var errs: Array = []
	if not data is Dictionary or (data as Dictionary).is_empty():
		return ["rubble.json missing or not an object"]
	if int(data.get("version", 0)) != VERSION: errs.append("version must be %d" % VERSION)
	for key: String in ["damage", "force", "speed", "up", "gravity", "life", "maxChunks", "pickupRange", "cooldown", "radius", "hitRadius"]:
		var v: Variant = data.get(key)
		if not (v is float or v is int): errs.append("%s not a number" % key)
		elif float(v) < 0.0: errs.append("%s negative" % key)
	var b: Variant = data.get("bot")
	if not b is Dictionary: errs.append("missing section bot")
	else:
		for key: String in ["grab", "throwMin", "throwMax", "think"]:
			var v: Variant = (b as Dictionary).get(key)
			if not (v is float or v is int) or float(v) < 0.0: errs.append("bot.%s bad" % key)
	if errs.is_empty():
		if float(data["speed"]) < 1.0: errs.append("speed too low")
		if int(data["maxChunks"]) < 1: errs.append("maxChunks must be at least 1")
		if float(data["hitRadius"]) < float(data["radius"]): errs.append("hitRadius below radius")
		if float(data["bot"]["throwMin"]) >= float(data["bot"]["throwMax"]): errs.append("bot.throwMin must be below throwMax")
	return errs

static func enabled() -> bool:
	return bool(config(load_data()).get("enabled", true))

func setup(p_sim: MatchSim) -> void:
	sim = p_sim
	cfg = config(load_data())
	_rng.seed = 0x9e3779b9 + int(p_sim.destruct_seed)

func dispose() -> void:
	chunks.clear(); held.clear(); sim = null

func count() -> int:
	return chunks.size()

func resting() -> Array:
	return chunks.filter(func(c: Dictionary) -> bool: return str(c["state"]) == "rest")

func held_by(f: FighterState) -> Dictionary:
	return held.get(f, {})

# ============================== spawning ==============================

## A breakable component broke (Destruct._break): leave one chunk of it on the floor. Presentation debris is separate
## (PropDebris); this is the logical pickup.
func spawn_from_break(prop: Dictionary) -> void:
	if sim == null or not bool(cfg.get("enabled", true)): return
	var cap := int(cfg["maxChunks"])
	if chunks.size() >= cap:
		var i := -1
		for k in chunks.size():
			if str(chunks[k]["state"]) == "rest": i = k; break
		if i < 0: return
		chunks.remove_at(i)
	var w := float(prop.get("w", 1.0)); var h := float(prop.get("h", 1.0)); var d := float(prop.get("d", 1.0))
	var size := clampf(minf(minf(w, h), d) * 0.6, 0.24, 0.55)
	var bottom := float(prop.get("bottom", prop.get("y", 0.0)))
	var cx := float(prop.get("x", 0.0)); var cz := float(prop.get("z", 0.0))
	var x := cx + _rng.randf_range(-w * 0.25, w * 0.25)
	var z := cz + _rng.randf_range(-d * 0.25, d * 0.25)
	chunks.append({"id": _next_id, "state": "rest", "x": x, "y": bottom + size * 0.5, "z": z,
		"vx": 0.0, "vy": 0.0, "vz": 0.0, "ground": bottom, "life": float(cfg["life"]), "fly_t": 0.0,
		"size": size, "color": int(prop.get("color", 0xffffff)), "owner": null})
	_next_id += 1

# ============================== per step (MatchSim.step) ==============================

func step(dt: float) -> void:
	_sync_held()
	var i := chunks.size() - 1
	while i >= 0:
		var c: Dictionary = chunks[i]
		var gone := false
		match str(c["state"]):
			"rest":
				c["life"] = float(c["life"]) - dt
				if float(c["life"]) <= 0.0: gone = true
			"fly":
				gone = _step_fly(c, dt)
		if gone: chunks.remove_at(i)
		i -= 1

## A fighter that respawned / was hit out of a hang etc. must not leave a chunk pinned in its hand.
func _sync_held() -> void:
	for f: Variant in held.keys():
		var fighter: FighterState = f
		if fighter.rubble != 1 or fighter.dead or fighter.down_t > 0.0 or fighter.carried_by != null:
			var c: Dictionary = held[fighter]
			held.erase(fighter)
			fighter.rubble = 0
			c["state"] = "fly"; c["vx"] = 0.0; c["vy"] = -1.0; c["vz"] = 0.0; c["fly_t"] = 0.0

## Physics of one thrown chunk: gravity, floor/wall stop, fighter hit. Returns true when the chunk is gone.
func _step_fly(c: Dictionary, dt: float) -> bool:
	c["fly_t"] = float(c["fly_t"]) + dt
	if float(c["fly_t"]) > FLIGHT_TIME: return true
	var g := float(cfg["gravity"])
	c["vy"] = float(c["vy"]) - g * dt
	var old_y := float(c["y"])
	c["y"] = old_y + float(c["vy"]) * dt
	c["x"] = float(c["x"]) + float(c["vx"]) * dt
	c["z"] = float(c["z"]) + float(c["vz"]) * dt
	var x := float(c["x"]); var y := float(c["y"]); var z := float(c["z"])
	var r := float(cfg["radius"])
	# fighters first: a light projectile that lands on someone hurts through the normal combat hit path
	for f: FighterState in sim.fighters:
		if f == c["owner"] or f.dead or f.left or f.is_ghost or f.elim: continue
		var dx := x - f.phys.px
		var dy := y - (f.phys.py + 1.1)
		var dz := z - f.phys.pz
		if dx * dx + dy * dy + dz * dz > pow(float(cfg["hitRadius"]) + 0.55, 2.0): continue
		_hit_fighter(f, c)
		return true
	# solids: land on a top, stop inside a wall
	for raw: Variant in sim.solids:
		if not (raw is Dictionary): continue
		var b: Dictionary = raw
		if x < float(b["minX"]) - r or x > float(b["maxX"]) + r or z < float(b["minZ"]) - r or z > float(b["maxZ"]) + r: continue
		var top := float(b["top"])
		if old_y - r >= top - 0.01 and y - r <= top and float(c["vy"]) < 0.0:   # landed on this box's top
			c["y"] = top + r
			_rest(c)
			return false
		if y > float(b["bottom"]) - r and y < top + r:                          # flew into a wall: stop and drop
			_rest(c)
			c["y"] = minf(y, top + r)
			return false
	if y < sim.ring_out_y - 10.0: return true
	return false

func _rest(c: Dictionary) -> void:
	c["state"] = "rest"
	c["vx"] = 0.0; c["vy"] = 0.0; c["vz"] = 0.0
	c["life"] = float(cfg["life"])
	c["owner"] = null
	sim.combat.ev({"type": "rubble", "kind": "land", "x": float(c["x"]), "y": float(c["y"]), "z": float(c["z"])})

func _hit_fighter(f: FighterState, c: Dictionary) -> void:
	var vx := float(c["vx"]); var vz := float(c["vz"])
	var l := sqrt(vx * vx + vz * vz)
	if l < 0.01: vx = 0.0; vz = 1.0; l = 1.0
	var owner: FighterState = c["owner"]
	sim.combat.hit(f, float(cfg["damage"]), vx / l, 0.25, vz / l, float(cfg["force"]), false, owner)
	hits += 1
	sim.combat.ev({"type": "rubble", "kind": "hit", "f": f, "x": float(c["x"]), "y": float(c["y"]), "z": float(c["z"]),
		"attacker": owner})

# ============================== pickup / drop / throw ==============================

## Can `f` pick a chunk up right now? Alive, on its feet, not trapped / carried / carrying / mid-swing and empty-handed
## (Rubble.held is empty for it). Offline only by construction (sim.rubble exists only there).
func can_pick(f: FighterState) -> bool:
	if sim == null or f == null or not bool(cfg.get("enabled", true)): return false
	if f.dead or f.down_t > 0.0 or f.trap_t > 0.0 or f.carried_by != null or f.carrying != null: return false
	if f.rubble != 0 or held.has(f) or f.stun > 0.0 or f.shove_cool > 0.0: return false
	return true

## Pick the nearest resting chunk within pickupRange. Returns the chunk (or {} when nothing is in reach).
func try_pickup(f: FighterState) -> Dictionary:
	if not can_pick(f): return {}
	var c := _nearest_rest(f, float(cfg["pickupRange"]))
	if c.is_empty(): return {}
	c["state"] = "held"; c["owner"] = f
	held[f] = c
	f.rubble = 1
	f.shove_cool = float(cfg["cooldown"])
	picks += 1
	sim.combat.ev({"type": "rubble", "kind": "pickup", "f": f})
	return c

## Put a held chunk down: it drops to the floor as a normal rest chunk (and can be picked up again).
func drop(f: FighterState) -> bool:
	var c: Dictionary = held.get(f, {})
	if c.is_empty(): return false
	held.erase(f)
	f.rubble = 0
	f.shove_cool = float(cfg["cooldown"])
	c["state"] = "fly"; c["vy"] = -0.5; c["vx"] = 0.0; c["vz"] = 0.0; c["fly_t"] = 0.0; c["owner"] = f
	sim.combat.ev({"type": "rubble", "kind": "drop", "f": f})
	return true

## Throw the held chunk at a world point (the crosshair point for the player, the target's chest for a bot). Ballistic:
## the horizontal speed is the overlay's `speed`, the vertical speed is solved so the chunk reaches the point.
func throw_at(f: FighterState, tx: float, ty: float, tz: float) -> bool:
	var c: Dictionary = held.get(f, {})
	if c.is_empty(): return false
	var sx := f.phys.px; var sy := f.phys.py + 1.3; var sz := f.phys.pz
	var dx := tx - sx; var dz := tz - sz
	var flat := sqrt(dx * dx + dz * dz)
	if flat < 0.2:
		return throw_dir(f)
	var t := maxf(flat / maxf(1.0, float(cfg["speed"])), 0.12)
	var vx := dx / t
	var vz := dz / t
	var vy := (ty - sy + 0.5 * float(cfg["gravity"]) * t * t) / t
	return _launch(f, c, vx, vy, vz)

## Throw along the fighter's facing when there is no aim point (a fixed arc from the overlay's `speed` and `up`).
func throw_dir(f: FighterState) -> bool:
	var c: Dictionary = held.get(f, {})
	if c.is_empty(): return false
	var sp := float(cfg["speed"])
	return _launch(f, c, sin(f.face_yaw) * sp, float(cfg["up"]), cos(f.face_yaw) * sp)

func _launch(f: FighterState, c: Dictionary, vx: float, vy: float, vz: float) -> bool:
	held.erase(f)
	f.rubble = 0
	f.shove_cool = float(cfg["cooldown"])
	c["state"] = "fly"
	c["x"] = f.phys.px + sin(f.face_yaw) * 0.5
	c["y"] = f.phys.py + 1.3
	c["z"] = f.phys.pz + cos(f.face_yaw) * 0.5
	c["vx"] = vx; c["vy"] = vy; c["vz"] = vz
	c["fly_t"] = 0.0; c["owner"] = f
	throws += 1
	sim.combat.ev({"type": "rubble", "kind": "throw", "f": f, "x": float(c["x"]), "y": float(c["y"]), "z": float(c["z"])})
	return true

# ============================== bots ==============================

## Nearest resting chunk a bot should walk to ({} = none). Same reach as the pickup plus a little for the walk.
func bot_chunk(f: FighterState, reach: float) -> Dictionary:
	if sim == null or not can_pick(f): return {}
	return _nearest_rest(f, reach)

## A bot with a chunk in hand throws it at `target` when it is in the overlay's window and has line of sight. Returns
## true when the chunk left the hand.
func bot_throw(f: FighterState, target: FighterState, los: bool, dist: float) -> bool:
	if f.rubble != 1 or target == null or target.dead: return false
	if dist < float(cfg["botThrowMin"]) or dist > float(cfg["botThrowMax"]): return false
	if not los and dist > 3.0: return false
	var ax := target.phys.px
	var ay := target.phys.py + 1.1
	var az := target.phys.pz
	if absf(target.chest_y - (target.phys.py + 1.22)) < 0.8:   # the animation wrote its pose this step: aim at the chest
		ax = target.chest_x; ay = target.chest_y; az = target.chest_z
	return throw_at(f, ax, ay, az)

## Distance from `f` to the nearest resting chunk (m), for the bot's decision (99 when none).
func nearest_rest_dist(f: FighterState) -> float:
	var c := _nearest_rest(f, 99.0)
	if c.is_empty(): return 99.0
	return sqrt(pow(float(c["x"]) - f.phys.px, 2.0) + pow(float(c["z"]) - f.phys.pz, 2.0))

func _nearest_rest(f: FighterState, reach: float) -> Dictionary:
	var best := {}
	var bd := reach + 0.0001
	for raw: Variant in chunks:
		var c: Dictionary = raw
		if str(c["state"]) != "rest": continue
		var dy := absf(float(c["y"]) - (f.phys.py + 0.4))
		if dy > VERTICAL_REACH: continue
		var d := sqrt(pow(float(c["x"]) - f.phys.px, 2.0) + pow(float(c["z"]) - f.phys.pz, 2.0))
		if d >= bd: continue
		bd = d; best = c
	return best
