class_name PlayerControl
extends RefCounted
## The local player's controls, ported from playerControl and the key handlers (public/index.html ~9391, ~9321):
## InputState + camera yaw -> wish/jump/speed/facing/aim, then fire, melee swing (and its tick), kick, shove, quick
## melee, slot keys, reload. The world sets `cam_yaw` and `aim_point` (the crosshair point, from the camera ray)
## before every step; tests drive the same InputState from the "script" source.
## Kids mode (Settings `kids_mode`, docs/KIDS_MODE.md): logic/kids_assist.gd adds auto-aim/auto-fire and the edge guard,
## consulted once per think after the taps so it uses the weapon actually in hand. With the setting off the normal path
## below runs unchanged (the bot-parity / flow tests never see it).

var input: InputState
var cam_yaw := PI
var aim_point: Array = []        ## [x, y, z] the crosshair is on ([] = straight ahead of the arm)
var squat := false
var _dash_held := false
var _kids_target: FighterState = null   ## kids mode: the enemy being assisted (null = none)

func _init(state: InputState) -> void:
	input = state

func think(p: FighterState, sim: MatchSim, dt: float) -> void:
	var combat := sim.combat
	if p.is_player:
		combat.aim_mode = Combat.settings_aim_mode()   # docs/AIM.md: the Settings row applies live, one copy per step
	var ph := p.phys
	var key := p.weapon if p.weapon != "" else "spatula"
	var w := combat.wdata(key)
	var incap := p.dead or p.down_t > 0.0
	var s := sin(cam_yaw)
	var c := cos(cam_yaw)
	var mv := input.move()
	var f := mv.y
	var r := mv.x
	var wx := s * f - c * r
	var wz := c * f + s * r
	var l := sqrt(wx * wx + wz * wz)
	if l > 1.0: wx /= l; wz /= l
	if incap: wx = 0.0; wz = 0.0
	ph.wish_x = wx; ph.wish_z = wz; ph.climb_in = f
	if input.consume("dash") and not combat.rules.do_dash(p, wx, wz) and not ph.grounded:   # ninja dash (needs a ninja weapon in hand)
		Skills.do_recover(p, sim, wx, wz)                      # no dash gear: the dash key recovers in the air
	if input.consume("recover"): Skills.do_recover(p, sim, wx, wz)   # air recovery, the "boing burst" (logic/skills.gd)
	var aiming := input.aiming()
	var fire := input.is_held("fire")
	squat = input.is_held("crouch") and not incap and ph.ladder.is_empty()
	var sprint := input.is_held("sprint") and not aiming and f > 0.0 and not squat
	p.ads = 1.0 if aiming else 0.0
	var spm := float(w.get("speedMul", 1.0)) if w.get("speedMul", 0) else 1.0
	ph.speed = (3.8 if aiming else (10.5 if sprint else 7.5)) * spm * (0.5 if squat else 1.0)
	if input.is_held("jump") and not incap and not squat: ph.want_jump = true

	# facing: the camera direction while aiming/attacking, else the direction of travel
	var face := p.yaw
	if not incap and (aiming or fire or p.swing >= 0.0 or p.kick_t >= 0.0): face = cam_yaw
	elif sqrt(ph.vx * ph.vx + ph.vz * ph.vz) > 0.8 and l > 0.05: face = atan2(ph.vx, ph.vz)
	p.face_yaw = face

	# aim target: from the shoulder toward whatever the crosshair is on. Normal aim mode pulls the point toward a
	# nearby enemy first (docs/AIM.md); Advanced mode keeps the raw crosshair: no snapping, manual aim only.
	var ap := aim_point
	if (aiming or fire) and not incap:
		ap = _assisted_aim(p, sim, aim_point)
	p.aim_pt = ap
	if ap.size() == 3:
		var a := Combat.norm3(ap[0] - p.shoulder_x, ap[1] - p.shoulder_y, ap[2] - p.shoulder_z)
		p.aim_x = a[0]; p.aim_y = a[1]; p.aim_z = a[2]
	if not w.get("spinup", 0): p.spin = 0.0
	if w.get("type", "") != "bow" or incap: p.draw = 0.0
	if not w.get("throwable", false) or incap:         # trident charge state resets when it is not in hand
		p.t_charge = -1.0; p.t_pend = -1.0
		if p.throw_hold: p.throw_hold = false; p.throw_key = ""
	if incap:
		_drain_taps()
		return

	# taps (key handlers)
	if input.consume("kick"): combat.do_kick(p, cam_yaw)
	if input.consume("shove"): combat.shove(p, cam_yaw)
	if input.consume("spatula"): sim.quick_melee(p, cam_yaw)
	if input.consume("spatula_equip"): combat.equip_slot(p, -1)   # touch: the Spatula tile is a real slot, not a swing
	if input.consume("reload"): combat.start_reload(p)
	for i in 3:
		if not input.consume("slot%d" % (i + 1)) or p.slots[i] == null: continue
		combat.equip_slot(p, -1 if p.slot == i else i)   # press the slot key again = back to the spatula (web parity)
	if input.consume("swap"): _cycle(p, combat)

	key = p.weapon if p.weapon != "" else "spatula"
	w = combat.wdata(key)

	# --- kids mode: auto-aim / auto-fire and the edge guard (logic/kids_assist.gd) ---
	# cy = the yaw the attacks use (the target's when the assist picked one), ap = the point the shots go to.
	var cy := cam_yaw
	var kids := KidsAssist.assist(p, sim, w, cam_yaw, _kids_target, ph.wish_x, ph.wish_z, ph.want_jump)
	if not kids.is_empty():
		ph.wish_x = float(kids["wish_x"])
		ph.wish_z = float(kids["wish_z"])
		ph.want_jump = bool(kids["jump"])                     # the guard may cancel a hop into the void
		var tg: FighterState = kids["target"]
		_kids_target = tg
		if tg != null:
			cy = float(kids["yaw"])
			ap = kids["aim"]
			fire = bool(kids["fire"])
			p.aim_pt = ap
			var sh := KidsAssist.shoulder(p)
			var av := Combat.norm3(ap[0] - sh[0], ap[1] - sh[1], ap[2] - sh[2])
			p.aim_x = av[0]; p.aim_y = av[1]; p.aim_z = av[2]
			p.face_yaw = cy
	else:
		_kids_target = null

	var t: String = w.get("type", "")
	if t == "melee":
		if w.get("throwable", false):   # trident: a tap jabs someone close, holding charges a throw
			combat.weapons.trident_tick(p, fire, dt, cy)
		elif fire and p.cool <= 0.0 and p.swing < 0.0:
			combat.try_melee(p, cy)
		if p.swing >= 0.0 and combat.melee_tick(p, key, dt, cy): combat.after_swing(p)
	elif t == "gun":
		combat.weapons.gun_tick(p, fire, dt, ap)
	elif t == "bow":                   # hold to draw, let go to shoot
		combat.weapons.bow_tick(p, fire, dt, ap)
		if fire and p.cool <= 0.0 and p.swing < 0.0 and p.get_ammo() > 0: ph.speed *= 0.75
	elif t == "blower":
		combat.weapons.blower_tick(p, fire, dt)
	elif fire:
		combat.weapons.try_fire(p, ap)

func _drain_taps() -> void:
	for a in ["kick", "shove", "spatula", "spatula_equip", "reload", "slot1", "slot2", "slot3", "swap", "dash", "recover"]:
		while input.consume(a): pass

## cycleWeapon: the next filled slot after the current one, the spatula (-1) included (the web game's cycleWeapon).
## The spatula is always in the order, so repeated swaps always come back to it, and empty slots are skipped.
func _cycle(p: FighterState, combat: Combat) -> void:
	var order: Array = [-1]
	for i in 3:
		if p.slots[i] != null: order.append(i)
	var idx := order.find(p.slot)
	combat.equip_slot(p, int(order[(idx + 1) % order.size()] if idx >= 0 else order[0]))

# ============================== aim assist (Normal aim mode) ==============================
# docs/AIM.md: Normal aim mode gives the LOCAL player a small target magnetism while aiming / firing. The crosshair
# point is pulled toward the chest of the enemy nearest to it: inside a narrow cone, with line of sight, offline only
# (online the web game decides hits and a client-side buff would skew cross-play). Advanced mode never calls this.

const ASSIST_CONE_COS := 0.9925    ## ~7 deg around the crosshair: a target further off is not pulled at all
const ASSIST_RANGE := 32.0         ## m from the shoulder
const ASSIST_MIN_DIST := 1.0       ## closer than this is the player's own body
const ASSIST_PULL := 0.85          ## how far the aim direction moves toward that enemy's chest

## The aim point the shots use: `ap`, or a point in the same distance pulled toward a near enemy.
func _assisted_aim(p: FighterState, sim: MatchSim, ap: Array) -> Array:
	if ap.size() != 3 or not p.is_player or sim == null: return ap
	var combat := sim.combat
	if combat.aim_advanced() or combat.net_started: return ap     # Advanced: manual aim; online: no client-side help
	var sd := Combat.norm3(ap[0] - p.shoulder_x, ap[1] - p.shoulder_y, ap[2] - p.shoulder_z)
	var best: FighterState = null
	var best_dot := ASSIST_CONE_COS
	for e: FighterState in sim.fighters:
		if e == p or e.dead or e.elim or e.left or e.is_ghost: continue
		if combat.is_friend(p, e): continue
		var dx := e.chest_x - p.shoulder_x
		var dy := e.chest_y - p.shoulder_y
		var dz := e.chest_z - p.shoulder_z
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		if d < ASSIST_MIN_DIST or d > ASSIST_RANGE: continue
		var dot: float = (dx * sd[0] + dy * sd[1] + dz * sd[2]) / d
		if dot < best_dot or not sim.has_los(p, e): continue
		best = e; best_dot = dot
	if best == null: return ap
	var td := Combat.norm3(best.chest_x - p.shoulder_x, best.chest_y - p.shoulder_y, best.chest_z - p.shoulder_z)
	var dir := Combat.norm3(sd[0] + (td[0] - sd[0]) * ASSIST_PULL, sd[1] + (td[1] - sd[1]) * ASSIST_PULL,
		sd[2] + (td[2] - sd[2]) * ASSIST_PULL)
	var ox: float = ap[0] - p.shoulder_x
	var oy: float = ap[1] - p.shoulder_y
	var oz: float = ap[2] - p.shoulder_z
	var dl := sqrt(ox * ox + oy * oy + oz * oz)
	return [p.shoulder_x + dir[0] * dl, p.shoulder_y + dir[1] * dl, p.shoulder_z + dir[2] * dl]
