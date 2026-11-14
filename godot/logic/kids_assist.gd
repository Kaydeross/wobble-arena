class_name KidsAssist
extends RefCounted
## The "kids mode" assist (Settings `kids_mode`), offline v1: auto-aim + auto-fire at the nearest enemy in front and an
## edge guard that stops the player walking or hopping off the map. PlayerControl.think() calls assist() once per step;
## with the setting off it returns {} before doing anything else, so the normal control path (and the web-parity tests)
## never sees it. docs/KIDS_MODE.md has the rules and the numbers.
##
##   - target: the nearest living enemy (not Combat.is_friend, not a ghost, not dead / eliminated / left) inside the
##     held weapon's range and a +-75 deg cone around the camera, with line of sight (MatchSim.has_los). The current
##     target stays picked while another enemy is less than SWITCH_BIAS times closer, so the aim does not flicker
##     between two enemies at the same distance.
##   - aim: the chest; lobbed weapons aim at the feet plus their drop, like BotBrain.BOT_FIRE. A slow +-AIM_ERR m
##     sideways sway keeps this assistance rather than an aimbot, and the assist does not lead a moving target.
##   - fire: held while the target is in range. Melee swings only inside the weapon's tip; the bow lets go at 85 %
##     draw; the trident taps a jab up close and charges TRIDENT_CHARGE s before throwing further out; everything else
##     holds the trigger.
##   - edge guard: while grounded, probe the floor EDGE_STEPS m ahead; if the floor runs out, steer the wish (up to
##     +-1.6 rad) to a direction with floor, else stop it; a jump is cancelled when its landing spot is in the void.
##     Nothing teleports: the player stops or slides along the edge and can always walk back inward.
##   - rewards / ranking: half coins (Save.add_coins -> reward_coins) and no leaderboard submission
##     (leaderboard_allowed() is the guard any ranking code can check; the RankingSheet uses AccountApi.rank_allowed).
## Kids mode is offline-only in v1: it only changes the local player's input. Online the other players are ghosts, so
## the target rule has nobody to pick (the edge guard still helps locally); the online lobby and rooms are untouched.

## Metres of slow sideways aim sway (about 1.4 deg at 14 m). Enough that a running target slips a little; small enough
## that a standing target is still hit. The sway is a fixed sine of the match clock, not random, so a run is repeatable.
const AIM_ERR := 0.35
const AIM_SWAY_HZ := 0.85
const AIM_UP := 0.05            ## aim a touch above the chest centre (towards the head)

## Only enemies in front of the camera: cos(75 deg). A target behind the camera is the player's to find.
const FRONT_COS := 0.2588
const RANGE_DEFAULT := 22.0     ## thrown / bow weapons without a `range` in shared/weapons.json
const MELEE_PAD := 0.9          ## arm + tip reach past the weapon's `tip`
const MELEE_ALERT := 2.5        ## melee target awareness: face an enemy this close even outside the swing reach
const BOW_RELEASE := 0.85       ## let go of the bow at this draw
const TRIDENT_CHARGE := 0.35    ## hold the trident this long, then release the throw
const SWITCH_BIAS := 1.25       ## keep the current target while it is within this factor of the nearest one

## Edge guard probes (metres ahead of the feet) and the steering tries (radians off the wish direction).
const EDGE_STEPS := [0.9, 1.8, 2.7]
const EDGE_TURNS := [0.55, -0.55, 1.1, -1.1, 1.6, -1.6]
const EDGE_DOWN := 7.0          ## a floor up to 7 m below counts (a short drop is fine), same as BotBrain.ground_at
const EDGE_UP := 0.7            ## ... and up to 0.7 m above (a step)
const JUMP_AIR_PAD := 2.0       ## extra metres for the jump-landing probe under the estimated flight distance

static var _settings_ref: WeakRef = null

## Is kids mode on right now? Read live from the Settings autoload (every think step), so toggling the row applies at
## once without a signal connection in the pure-logic layer.
static func is_enabled() -> bool:
	var st := _settings()
	return st != null and bool(st.get_value("kids_mode", false))

## The guard the ranking client uses: never submit a score / rank from a kids mode session.
static func leaderboard_allowed() -> bool:
	return not is_enabled()

## Half coins in kids mode (an odd reward rounds down; a 1-coin award pays nothing), unchanged otherwise.
static func reward_coins(n: int) -> int:
	if n <= 0 or not is_enabled(): return n
	return int(floor(float(n) * 0.5))

static func _settings() -> Node:
	var n: Node = _settings_ref.get_ref() if _settings_ref != null else null
	if n != null and is_instance_valid(n): return n
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return null
	n = tree.root.get_node_or_null("Settings")
	if n != null: _settings_ref = weakref(n)
	return n

# ============================== one step ==============================

## One step of assistance for PlayerControl. Returns {} when the setting is off or the player cannot act; otherwise
## {target: FighterState|null, yaw, aim: [x,y,z] or [], fire: bool, wish_x, wish_z, jump}. With no target the aim stays
## [] and fire false, and the caller keeps the manual aim and trigger untouched.
static func assist(p: FighterState, sim: MatchSim, w: Dictionary, cam_yaw: float, prev_target: FighterState,
		wish_x: float, wish_z: float, want_jump: bool) -> Dictionary:
	if not is_enabled(): return {}
	if p.dead or p.down_t > 0.0 or p.trap_t > 0.0 or p.elim: return {}
	var wx := wish_x
	var wz := wish_z
	var jump := want_jump
	if p.phys.grounded:
		var g := guard(p, sim, wish_x, wish_z, want_jump)
		wx = g[0]; wz = g[1]; jump = g[2]
	var tg := pick_target(p, sim, w, cam_yaw, prev_target)
	var out := {"target": tg, "yaw": cam_yaw, "aim": [], "fire": false, "wish_x": wx, "wish_z": wz, "jump": jump}
	if tg != null:
		out["yaw"] = atan2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
		out["aim"] = aim_point(p, sim, w, tg)
		out["fire"] = fire_wanted(p, sim, w, dist(p, tg))
	return out

## The nearest valid enemy in front and in range, keeping the previous target while it stays close enough.
static func pick_target(p: FighterState, sim: MatchSim, w: Dictionary, cam_yaw: float, prev_target: FighterState) -> FighterState:
	var fx := sin(cam_yaw)
	var fz := cos(cam_yaw)
	var reach := weapon_range(w)
	var best: FighterState = null
	var best_score := INF
	for e: FighterState in sim.fighters:
		if e == p or e.dead or e.elim or e.is_ghost or e.left: continue
		if sim.combat.is_friend(p, e): continue
		var dx := e.phys.px - p.phys.px
		var dz := e.phys.pz - p.phys.pz
		var d := sqrt(dx * dx + dz * dz)
		if d > reach: continue
		if d > 0.05 and (dx * fx + dz * fz) / d < FRONT_COS: continue
		var score := d * (1.0 / SWITCH_BIAS if e == prev_target else 1.0)
		if score >= best_score: continue
		if not line_of_sight(p, e, sim): continue
		best = e
		best_score = score
	return best

## How far the held weapon can reach: the gun's `range`, the melee tip plus the arm, else a sane thrown range.
static func weapon_range(w: Dictionary) -> float:
	var t := str(w.get("type", ""))
	if t == "melee":
		if w.get("throwable", false): return RANGE_DEFAULT      # trident: jab up close, throw further out
		return maxf(MELEE_ALERT, melee_reach(w))
	if w.has("range"): return maxf(float(w["range"]), 2.0)
	return RANGE_DEFAULT

static func melee_reach(w: Dictionary) -> float:
	return float(w.get("tip", 2.0)) + MELEE_PAD

## Should the assist hold the trigger this step?
static func fire_wanted(p: FighterState, sim: MatchSim, w: Dictionary, d: float) -> bool:
	var t := str(w.get("type", ""))
	if t == "melee":
		if w.get("throwable", false):                          # trident: tap = jab, hold = throw
			if d <= melee_reach(w): return int(floor(sim.combat.time * 120.0)) % 2 == 0   # alternate hold/release = a tap
			return p.t_charge < TRIDENT_CHARGE                  # far: charge a moment, then let the throw go
		return d <= melee_reach(w)
	if t == "bow": return p.draw < BOW_RELEASE                  # hold the draw, release at 85 %
	return true

## Where to aim: the chest (or the feet plus the drop for lobbed weapons) plus the slow sway.
static func aim_point(p: FighterState, sim: MatchSim, w: Dictionary, tg: FighterState) -> Array:
	var sh: Array = shoulder(p)
	var ch: Array = chest(tg)
	var dx := float(ch[0]) - float(sh[0])
	var dz := float(ch[2]) - float(sh[2])
	var l := sqrt(dx * dx + dz * dz)
	if l < 0.001:
		dx = sin(p.yaw); dz = cos(p.yaw); l = 1.0
	var px := dz / l
	var pz := -dx / l
	var sway := AIM_ERR * sin(sim.combat.time * TAU * AIM_SWAY_HZ + float(p.id) * 1.7)
	var out := [ch[0] + px * sway, ch[1] + AIM_UP, ch[2] + pz * sway]
	var t := str(w.get("type", ""))
	var sp := float(w.get("speed", 0.0))
	var d := dist(p, tg)
	if t == "glauncher" and sp > 0.0:                          # grenade: aim at the feet, allowing for the drop
		var tt := d / sp
		out[1] = tg.phys.py + 0.15 + maxf(0.0, 4.5 * tt * tt - 1.8 * tt)
	elif t == "net" and sp > 0.0:
		var tn := d / sp
		out[1] = tg.phys.py + 0.45 + maxf(0.0, 3.5 * tn * tn - 1.5 * tn)
	elif t == "ball":                                          # snowball: a high lob
		out[1] = tg.phys.py + 0.45 + d * 0.2 + 0.7
	return out

# ============================== bodies and sight ==============================

## The shoulder point: the animation writes it every frame; fall back to the body when it has not been written yet (a
## test that steps the sim by hand, the first frame of a match).
static func shoulder(p: FighterState) -> Array:
	if _posed(p, p.shoulder_x, p.shoulder_y, p.shoulder_z, 1.55): return [p.shoulder_x, p.shoulder_y, p.shoulder_z]
	return [p.phys.px, p.phys.py + 1.55, p.phys.pz]

static func chest(f: FighterState) -> Array:
	if _posed(f, f.chest_x, f.chest_y, f.chest_z, 1.22): return [f.chest_x, f.chest_y, f.chest_z]
	return [f.phys.px, f.phys.py + 1.22, f.phys.pz]

## A written animation point is trusted when it sits near where that body part belongs; all-zero (never written) points
## do not.
static func _posed(f: FighterState, x: float, y: float, z: float, height: float) -> bool:
	return absf(x - f.phys.px) < 1.2 and absf(z - f.phys.pz) < 1.2 and absf(y - (f.phys.py + height)) < 0.8

## MatchSim.has_los from the shoulder to the chest; a hand-stepped sim that never wrote the points gets the same ray
## computed from the body points instead.
static func line_of_sight(p: FighterState, tg: FighterState, sim: MatchSim) -> bool:
	if _posed(p, p.shoulder_x, p.shoulder_y, p.shoulder_z, 1.55) and _posed(tg, tg.chest_x, tg.chest_y, tg.chest_z, 1.22):
		return sim.has_los(p, tg)
	var sh: Array = shoulder(p)
	var ch: Array = chest(tg)
	var dx := float(ch[0]) - float(sh[0])
	var dy := float(ch[1]) - float(sh[1])
	var dz := float(ch[2]) - float(sh[2])
	var d := sqrt(dx * dx + dy * dy + dz * dz)
	if d < 0.1: return true
	return sim.combat.weapons.ray_walls(sh[0], sh[1], sh[2], dx / d, dy / d, dz / d, d) < 0.0

static func dist(p: FighterState, tg: FighterState) -> float:
	var dx := tg.phys.px - p.phys.px
	var dz := tg.phys.pz - p.phys.pz
	return sqrt(dx * dx + dz * dz)

# ============================== edge guard ==============================

## The edge guard: returns [wish_x, wish_z, jump]. Grounded only; the caller keeps the result for the physics step.
static func guard(p: FighterState, sim: MatchSim, wx: float, wz: float, want_jump: bool) -> Array:
	var solids: Array = sim.solids
	var l := sqrt(wx * wx + wz * wz)
	if l <= 0.02: return [wx, wz, want_jump]                   # standing still: nothing to guard (a straight hop is safe)
	var ux := wx / l
	var uz := wz / l
	if not _clear_ahead(solids, p.phys.py, p.phys.px, p.phys.pz, ux, uz):
		var found := false
		for a: float in EDGE_TURNS:                            # slide along the edge rather than stopping dead
			var tx := ux * cos(a) - uz * sin(a)
			var tz := ux * sin(a) + uz * cos(a)
			if _clear_ahead(solids, p.phys.py, p.phys.px, p.phys.pz, tx, tz):
				ux = tx; uz = tz; found = true
				break
		if not found: return [0.0, 0.0, false]                 # cornered: stop; walking back inward always works
		wx = ux * l
		wz = uz * l
		want_jump = false                                      # the walk is at the edge: do not hop outward too
	if want_jump:
		var run := p.phys.speed * p.phys.speed_mul * (1.4 if p.spd_t > 0.0 else 1.0)
		var grav := maxf(p.phys.grav_scale, 0.05)
		var up := 7.4 if p.phys.grav_scale < 0.3 else 9.2
		var t_air := 2.0 * up * p.phys.jump_mul / (FighterPhysics.GRAV * grav)
		var ahead := JUMP_AIR_PAD + maxf(run, sqrt(p.phys.vx * p.phys.vx + p.phys.vz * p.phys.vz)) * t_air
		if not floor_at(solids, p.phys.py, p.phys.px + ux * ahead, p.phys.pz + uz * ahead, 3.2):
			want_jump = false                                  # nowhere to land out there: no jump
	return [wx, wz, want_jump]

## Floor along the wish direction at every probe distance?
static func _clear_ahead(solids: Array, py: float, px: float, pz: float, ux: float, uz: float) -> bool:
	for d: float in EDGE_STEPS:
		if not floor_at(solids, py, px + ux * d, pz + uz * d): return false
	return true

## Is there floor to stand on (or drop to) at (x, z)? Same probe as BotBrain.ground_at / botGround.
static func floor_at(solids: Array, py: float, x: float, z: float, up: float = EDGE_UP) -> bool:
	var hi := py + up
	var lo := py - EDGE_DOWN
	for sb: Dictionary in solids:
		if x > sb["minX"] and x < sb["maxX"] and z > sb["minZ"] and z < sb["maxZ"]:
			var top: float = sb["top"]
			if top <= hi and top >= lo: return true
	return false
