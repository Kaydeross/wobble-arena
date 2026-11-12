class_name PlayerControl
extends RefCounted
## The local player's controls, ported from playerControl and the key handlers (public/index.html ~9391, ~9321):
## InputState + camera yaw -> wish/jump/speed/facing/aim, then fire, melee swing (and its tick), kick, shove, quick
## melee, slot keys, reload. The world sets `cam_yaw` and `aim_point` (the crosshair point, from the camera ray)
## before every step; tests drive the same InputState from the "script" source.

var input: InputState
var cam_yaw := PI
var aim_point: Array = []        ## [x, y, z] the crosshair is on ([] = straight ahead of the arm)
var squat := false
var _dash_held := false

func _init(state: InputState) -> void:
	input = state

func think(p: FighterState, sim: MatchSim, dt: float) -> void:
	var combat := sim.combat
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

	# aim target: from the shoulder toward whatever the crosshair is on
	if aim_point.size() == 3:
		var a := Combat.norm3(aim_point[0] - p.shoulder_x, aim_point[1] - p.shoulder_y, aim_point[2] - p.shoulder_z)
		p.aim_x = a[0]; p.aim_y = a[1]; p.aim_z = a[2]
	if not w.get("spinup", 0): p.spin = 0.0
	if w.get("type", "") != "bow" or incap: p.draw = 0.0
	if incap:
		_drain_taps()
		return

	# taps (key handlers)
	if input.consume("kick"): combat.do_kick(p, cam_yaw)
	if input.consume("shove"): combat.shove(p, cam_yaw)
	if input.consume("spatula"): sim.quick_melee(p, cam_yaw)
	if input.consume("reload"): combat.start_reload(p)
	for i in 3:
		if input.consume("slot%d" % (i + 1)) and p.slots[i] != null: combat.equip_slot(p, i)
	if input.consume("swap"): _cycle(p, combat)
	input.consume("dash")              # ninja dash: not ported yet

	key = p.weapon if p.weapon != "" else "spatula"
	w = combat.wdata(key)
	var t: String = w.get("type", "")
	if t == "melee":
		if fire and p.cool <= 0.0 and p.swing < 0.0:
			combat.try_melee(p, cam_yaw)
		if p.swing >= 0.0 and combat.melee_tick(p, key, dt, cam_yaw): combat.after_swing(p)
	elif t == "gun":
		combat.weapons.gun_tick(p, fire, dt, aim_point)
	elif t == "bow":                   # hold to draw, let go to shoot
		combat.weapons.bow_tick(p, fire, dt, aim_point)
		if fire and p.cool <= 0.0 and p.swing < 0.0 and p.get_ammo() > 0: ph.speed *= 0.75
	elif fire:
		combat.weapons.try_fire(p, aim_point)

func _drain_taps() -> void:
	for a in ["kick", "shove", "spatula", "reload", "slot1", "slot2", "slot3", "swap", "dash"]:
		while input.consume(a): pass

## cycleWeapon: the next filled slot after the current one, the spatula (-1) included.
func _cycle(p: FighterState, combat: Combat) -> void:
	for k in range(1, 5):
		var i := (p.slot + 1 + k) % 4 - 1
		if i < 0 or p.slots[i] != null:
			combat.equip_slot(p, i)
			return
