class_name CtfRules
extends RefCounted
## Capture the Flag (Godot-only mode "ctf"). Two teams (like Team
## Deathmatch: sizes from the Players page, no friendly fire) and ONE neutral flag on a stand near the middle of the arena.
## Touch an uncarried flag (CtfRules.GRAB_R, alive, not eliminated) and it is yours: your team's HOLD timer counts up while
## you carry it. HOLD_WIN seconds of continuous holding ends the match and that team wins. If the carrier is K.O.'d the
## flag drops where they fell (off the map: back on the stand), the hold timer resets to 0 and nobody can grab it for
## DROP_LOCK seconds. Carrying changes nothing else (speed, weapons).
## Fallback clock CLOCK_TIME: if nobody got there, the team with the most TOTAL (cumulative) hold time wins; a dead heat
## goes to the team with more K.O.s; still level: the player's team loses (the other team is named the winner).
## Events (combat.ev): {"type": "toast", "text"} on pick up / drop / return, {"type": "ctf", "kind": "take"|"drop"|"return", "f"}.
## Offline only (ModeRules.OFFLINE_ONLY). Owned by ModeRules (`ctf`, like `chaos`); bots: BotBrain reads `bot_goal`.

const HOLD_WIN := 30.0               ## seconds of continuous holding that win
const CLOCK_TIME := 300.0            ## the fallback clock (5:00)
const GRAB_R := 1.4                  ## how close (m, on the floor plane) a fighter must be to take the flag
const GRAB_DY := 1.6                 ## ... and how far up / down (m)
const DROP_LOCK := 1.0               ## nobody can grab a dropped / returned flag for this long
const ESCORT_R := 6.0                ## bots of the carrier's team stay within this of the carrier
const FLEE_STEP := 8.0               ## a carrier bot runs for a point this far from the nearest enemy

var _combat: WeakRef
var combat: Combat:
	get: return _combat.get_ref()
var stand := Vector3.ZERO            ## the flag stand (x, floor y, z)
var pos := Vector3.ZERO              ## where the flag lies when nobody carries it
var carrier: FighterState = null
var lock := 0.0                      ## s until a free flag can be grabbed
var hold := 0.0                      ## continuous hold of the current carrier's team (resets when the flag drops)
var holder := -1                     ## the team that holds it (-1 = nobody)
var total := [0.0, 0.0]              ## cumulative hold time per team (the fallback clock's tie-break)
var clock := CLOCK_TIME              ## fallback clock left
var timeout := false                 ## the clock ended the match
var at_stand := true                 ## the flag lies on its stand
var chaser: Array = [null, null]     ## per team: the bot that goes for a free flag
var solids: Array = []
var ring_out_y := -30.0
var _acc := 0.0

func _init(c: Combat) -> void:
	_combat = weakref(c)

## The stand: a walkable spot as near the middle of the map as there is one. A map can set `flag`: [x, z, y]. Otherwise the
## open floor on a 2 m grid around the origin is tried nearest first (on the floor, not inside a box, 2 m from the void:
## MatchSim.start_point_safe), then the map's own start / spawn / bot points nearest the origin.
static func pick_stand(map: Dictionary, p_solids: Array, p_ring_out_y: float) -> Vector3:
	var fl: Variant = map.get("flag", null)
	if fl is Array and (fl as Array).size() >= 3:
		return Vector3(float(fl[0]), float(fl[2]), float(fl[1]))
	var cand: Array = []
	for ix in range(-7, 8):
		for iz in range(-7, 8): cand.append(Vector2(ix * 2.0, iz * 2.0))
	cand.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() < b.length_squared())
	for v: Vector2 in cand:
		var tops: Array = []
		for sb: Dictionary in p_solids:
			if v.x > float(sb["minX"]) and v.x < float(sb["maxX"]) and v.y > float(sb["minZ"]) and v.y < float(sb["maxZ"]):
				var t := float(sb["top"])
				if t <= 1.5 and t > p_ring_out_y and not tops.has(t): tops.append(t)
		tops.sort()
		for t: float in tops:
			if MatchSim.start_point_safe(p_solids, v.x, v.y, t + 0.01, p_ring_out_y) and _open_around(p_solids, v.x, v.y, t): return Vector3(v.x, t + 0.01, v.y)
	var best := Vector3.ZERO
	var bd := INF
	var found := false
	for sp: Array in MatchSim.start_points(map):
		var x := float(sp[0]); var z := float(sp[1]); var y := float(sp[2])
		if not MatchSim.start_point_safe(p_solids, x, z, y, p_ring_out_y): continue
		var d := x * x + z * z
		if d < bd: bd = d; best = Vector3(x, y, z); found = true
	if not found:
		var pts: Array = MatchSim.start_points(map)
		if pts.size() > 0: best = Vector3(float(pts[0][0]), float(pts[0][2]), float(pts[0][1]))
		else: best = Vector3(0.0, maxf(0.0, floor_at(p_solids, 0.0, 0.0, 99.0, p_ring_out_y)), 0.0)
	return best

## Is the body space (floor `t` up to 1.2 m) free of boxes at (x, z) and 1.2 m around it (a tall box standing on the ground
## passes start_point_safe, which only looks at the feet)?
static func _open_around(p_solids: Array, x: float, z: float, t: float) -> bool:
	for k in 9:
		var px := x if k == 0 else x + cos(float(k) * PI / 4.0) * 1.2
		var pz := z if k == 0 else z + sin(float(k) * PI / 4.0) * 1.2
		for sb: Dictionary in p_solids:
			if px > float(sb["minX"]) and px < float(sb["maxX"]) and pz > float(sb["minZ"]) and pz < float(sb["maxZ"]) \
					and float(sb["bottom"]) < t + 1.2 and float(sb["top"]) > t + 0.15: return false
	return true

## The top of the highest solid under (x, z) that is at most `up` above `py`, or -INF over the void.
static func floor_at(p_solids: Array, x: float, z: float, py: float, p_ring_out_y: float, up: float = 0.6) -> float:
	var f := -INF
	for b: Dictionary in p_solids:
		if x > float(b["minX"]) and x < float(b["maxX"]) and z > float(b["minZ"]) and z < float(b["maxZ"]):
			var top := float(b["top"])
			if top <= py + up and top > p_ring_out_y: f = maxf(f, top)
	return f

## Put the flag on its stand (match start). Called once the map and its solids exist.
func setup(map: Dictionary, p_solids: Array, p_ring_out_y: float) -> void:
	solids = p_solids; ring_out_y = p_ring_out_y
	stand = pick_stand(map, p_solids, p_ring_out_y)
	pos = stand; at_stand = true
	carrier = null; lock = 0.0; hold = 0.0; holder = -1; total = [0.0, 0.0]; clock = CLOCK_TIME; timeout = false
	chaser = [null, null]

func _can_take(f: FighterState) -> bool:
	return not f.dead and not f.elim and not f.left and not f.is_ghost

## One simulation step (ModeRules.update).
func update(dt: float) -> void:
	var c := combat
	var r := c.rules
	if r.match_over or c.net_started: return
	if carrier != null and not _can_take(carrier):         # safety net (the hooks below normally act first)
		drop(carrier, carrier.phys.py < ring_out_y)
	lock = maxf(0.0, lock - dt)
	clock = maxf(0.0, clock - dt)
	if carrier == null:
		if lock <= 0.0: _try_take()
	else:
		hold += dt
		total[carrier.team] += dt
		if hold >= HOLD_WIN:
			hold = HOLD_WIN
			r.end_match(carrier)
			return
	if clock <= 0.0:
		_time_up()
		return
	_acc += dt                                              # who goes for a free flag (bots), a few times a second
	if _acc >= 0.25:
		_acc = 0.0
		_pick_chasers()

func _try_take() -> void:
	var best: FighterState = null
	var bd := GRAB_R * GRAB_R
	for f: FighterState in combat.fighters:
		if not _can_take(f): continue
		var dx := f.phys.px - pos.x; var dz := f.phys.pz - pos.z
		if absf(f.phys.py - pos.y) > GRAB_DY: continue
		var d := dx * dx + dz * dz
		if d <= bd: bd = d; best = f
	if best != null: take(best)

## A fighter picks the flag up.
func take(f: FighterState) -> void:
	carrier = f; hold = 0.0; holder = f.team; at_stand = false
	combat.ev({"type": "ctf", "kind": "take", "f": f})
	combat.ev({"type": "toast", "text": tr("%s took the flag!") % f.name})

## The carrier is down: `fell` = off the map (the flag goes back to the stand), else it lies where they dropped.
func drop(f: FighterState, fell: bool) -> void:
	if carrier == null or carrier != f: return
	carrier = null; hold = 0.0; holder = -1; lock = DROP_LOCK
	var fy := floor_at(solids, f.phys.px, f.phys.pz, f.phys.py + 0.5, ring_out_y, 1.2)
	if fell or fy == -INF or f.phys.py < ring_out_y:
		pos = stand; at_stand = true
		combat.ev({"type": "ctf", "kind": "return", "f": f})
		combat.ev({"type": "toast", "text": tr("Flag back on its stand!")})
	else:
		pos = Vector3(f.phys.px, fy, f.phys.pz); at_stand = false
		combat.ev({"type": "ctf", "kind": "drop", "f": f})
		combat.ev({"type": "toast", "text": tr("Flag dropped!")})

## ModeRules.on_down: `f` was K.O.'d (fell = ring-out).
func on_down(f: FighterState, fell: bool) -> void:
	if f == carrier: drop(f, fell)

## The fighter of team `t` that stands first in line (the team's winner when a team wins on the clock).
func team_fighter(t: int) -> FighterState:
	for f: FighterState in combat.fighters:
		if f.team == t and not f.left and not f.is_ghost: return f
	return null

## The clock ran out: most total hold time, then more K.O.s; a dead heat is a loss for the player's team.
func _time_up() -> void:
	var r := combat.rules
	timeout = true
	var t := -1
	if absf(total[0] - total[1]) > 0.001: t = 0 if total[0] > total[1] else 1
	else:
		var k0 := r.team_ko(0); var k1 := r.team_ko(1)
		if k0 != k1: t = 0 if k0 > k1 else 1
	var tie := t < 0
	if tie: t = 1 - clampi(_player_team(), 0, 1)       # the other side takes it: the player's team loses
	var w := team_fighter(t)
	if w == null: w = carrier if carrier != null else combat.fighters[0]
	r.timeout_tie = tie
	r.end_match(w)

func _player_team() -> int:
	for f: FighterState in combat.fighters:
		if f.is_player: return f.team
	return 0

## How the match ended, for the banner: "" = the 30 s hold.
func sub_text() -> String:
	if not timeout: return tr("Held the flag for 30 seconds")
	if combat.rules.timeout_tie: return tr("Dead even when the clock ran out")
	if absf(total[0] - total[1]) > 0.001: return tr("Held the flag the longest")
	return tr("Most K.O.s when the clock ran out")

## "FLAG  Blue 12/30   4:31" while held, "Flag free   4:31" otherwise.
func hud_text() -> String:
	var secs := maxi(0, ceili(clock))
	var clk := "%d:%02d" % [secs / 60, secs % 60]
	if carrier != null:
		var nm := tr("Blue") if holder == 0 else tr("Red")
		return tr("FLAG  %s %d/%d") % [nm, mini(int(hold), int(HOLD_WIN)), int(HOLD_WIN)] + "   " + clk
	return tr("Flag free") + "   " + clk

# ============================== bots ==============================

## Per team, the living non-carrier bot nearest the free flag (the others fight as usual).
func _pick_chasers() -> void:
	chaser = [null, null]
	if carrier != null: return
	var bd := [INF, INF]
	for f: FighterState in combat.fighters:
		if f.is_player or not _can_take(f) or f.team < 0 or f.team > 1: continue
		var dx := f.phys.px - pos.x; var dz := f.phys.pz - pos.z
		var d := dx * dx + dz * dz
		if d < bd[f.team]: bd[f.team] = d; chaser[f.team] = f

## What a bot should walk to instead of its usual chase: [] = nothing special, else [x, z, kind] with kind "go" (take the
## free flag), "flee" (the carrier runs from the nearest enemy) or "escort" (a teammate is too far from the carrier).
func bot_goal(b: FighterState) -> Array:
	if carrier == null:
		if chaser[b.team] == b and lock < 2.5: return [pos.x, pos.z, "go"]
		return []
	var p := b.phys
	if carrier == b:
		var en: FighterState = null
		var bd := INF
		for f: FighterState in combat.fighters:
			if f == b or f.dead or f.elim or f.left or combat.is_friend(b, f): continue
			var d := (f.phys.px - p.px) * (f.phys.px - p.px) + (f.phys.pz - p.pz) * (f.phys.pz - p.pz)
			if d < bd: bd = d; en = f
		if en == null: return []
		var ax := p.px - en.phys.px; var az := p.pz - en.phys.pz
		var l := maxf(0.001, sqrt(ax * ax + az * az))
		ax = ax / l - p.px * 0.02; az = az / l - p.pz * 0.02        # away from them, a little toward the middle
		l = maxf(0.001, sqrt(ax * ax + az * az))
		return [p.px + ax / l * FLEE_STEP, p.pz + az / l * FLEE_STEP, "flee"]
	if carrier.team == b.team:
		var dx := carrier.phys.px - p.px; var dz := carrier.phys.pz - p.pz
		if dx * dx + dz * dz > ESCORT_R * ESCORT_R: return [carrier.phys.px, carrier.phys.pz, "escort"]
	return []

## BotBrain.pick_target in this mode: enemies go for the carrier first; the carrier's teammates fight whoever is nearest the
## carrier. null = use the usual pick.
func bot_target(b: FighterState) -> FighterState:
	if carrier == null or carrier == b or carrier.dead: return null
	if not combat.is_friend(b, carrier): return carrier
	var best: FighterState = null
	var bd := ESCORT_R * 2.0
	for f: FighterState in combat.fighters:
		if f == b or f.dead or f.elim or f.left or combat.is_friend(b, f): continue
		var d := sqrt((f.phys.px - carrier.phys.px) * (f.phys.px - carrier.phys.px) + (f.phys.pz - carrier.phys.pz) * (f.phys.pz - carrier.phys.pz))
		if d < bd: bd = d; best = f
	return best
