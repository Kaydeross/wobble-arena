class_name RagdollRig
extends RefCounted
## Leg-driven ragdoll overlay for a Wobbler (docs/RAGDOLL.md). PRESENTATION ONLY: it reads the wobbler's sim-fed
## fields (pos, vel, yaw, grounded, wish, down_t, dead, trap, kick_t, fall_side, the classic grip transform) and
## re-poses the visible nodes after Fighter.present has read the gameplay points from the classic pose.
##
## Standing: feet are planted in world space and step toward a home point that leads the body (stick input moves the
## capsule, the capsule drags the feet); the hips follow the feet with a damped pendulum offset and are capped by leg
## reach (stride bob, landing dip); torso tilt and head nod are soft springs with lag; the off arm is a verlet
## pendulum. Down (topple, K.O., net trap): a 6-point position-based body (pelvis, chest, head, feet, aim hand) with
## gravity, sticks and a floor at the sim height, carried with the sim position; get-up blends back to standing.
## No allocations per frame (fixed packed arrays, value types only).

const UP := Vector3(0, 1, 0)
const DOWN := Vector3(0, -1, 0)
const GRAV := 22.0
const GETUP_TIME := 0.55
const LEG := 0.8                      # hip to sole, rig units (Thigh 0.8, foot sole at -0.8)
const ARM_L := 0.78                   # off shoulder to hand centre
const ARM := 0.85                     # aim shoulder to grip
const PLANTED := -1.0
const FREE := -2.0                    # in the air / kicking: not planted, not on a step arc
## particles of the collapsed body
const P_PELVIS := 0
const P_CHEST := 1
const P_HEAD := 2
const P_FOOT0 := 3
const P_FOOT1 := 4
const P_HAND := 5
const RADIUS := [0.24, 0.28, 0.3, 0.09, 0.09, 0.12]

var inited := false
var last_pos := Vector3.ZERO
var prev_vel := Vector3.ZERO
var was_ground := true
var was_down := false
var down_yaw := 0.0
var time := 0.0

# --- standing controller
var off := Vector3.ZERO               ## hips' pendulum offset from the sim position (horizontal, world)
var off_v := Vector3.ZERO
var hy := 0.8                         ## hip height above pos.y (world units)
var hy_v := 0.0
var tilt := Spring2.new()             ## torso pitch (x, + = forward) / roll (y, + = toward the character's right)
var nod := Spring2.new()              ## head on top of the torso
var _tvx := 0.0
var _tvy := 0.0
var feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]          ## world sole points
var foot_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var step_t: Array[float] = [PLANTED, PLANTED]
var step_dur: Array[float] = [0.2, 0.2]
var steps := 0                        ## steps taken (tests)
var idle_t := 0.0
var hand_off := Vector3.ZERO          ## off-hand verlet point (world)
var hand_off_v := Vector3.ZERO

# --- knock-down body
var px := PackedVector3Array()
var pv := PackedVector3Array()
var _pp := PackedVector3Array()
var down_k := 0.0                     ## 1 = the collapsed body drives the pose, 0 = standing controller
var getup := -1.0                     ## seconds into the get-up blend, -1 = not getting up

# --- hits
var hit_dir := Vector3.ZERO
var hit_age := 9.0
var hp_prev := -1.0
var dmg_recent := 0.0
var dmg_age := 9.0

# --- last rendered points (world), for tests and for starting a collapse from the visible pose
var pelvis_w := Vector3.ZERO
var chest_w := Vector3.ZERO
var head_w := Vector3.ZERO
var aim_hand_w := Vector3.ZERO
var shoulder_w := Vector3.ZERO        ## visible aim shoulder
var shoulder_off_w := Vector3.ZERO    ## visible off shoulder
var leg_k: Array[float] = [1.0, 1.0]  ## leg stretch (visible length / rest length) before clamping
var arm_k := 1.0                      ## aim arm stretch before clamping
var aim_free := 0.0                   ## 0 = the grip sits exactly on the sim hand; > 0 while down / spinning up


func _init() -> void:
	px.resize(6)
	pv.resize(6)
	_pp.resize(6)


## Damage seen in the state (hp drop): scales the next hit reaction.
func note_hp(hp: float) -> void:
	if hp_prev >= 0.0 and hp < hp_prev - 0.01:
		dmg_recent = hp_prev - hp
		dmg_age = 0.0
	hp_prev = hp


## A Combat `lean` kick (a, b) = -(hit dir . forward / right) * force * 0.22: shove the hips, whip torso, head, arm.
func hit(a: float, b: float, yaw: float, size: float) -> void:
	var yb := Basis(UP, yaw)
	var d := -(yb.z * a - yb.x * b)               # right = -left (yb.x)
	var f := d.length() / 0.22
	if f < 1e-4:
		return
	var dir := d.normalized()
	var m := clampf(0.7 + (dmg_recent / 25.0 if dmg_age < 0.25 else 0.0), 0.7, 2.2)
	off_v += dir * f * 0.12 * m * size
	tilt.kick(-a * 0.8 * m, -b * 0.8 * m)                 # the struck chest snaps away from the blow, the head whips
	nod.kick(-a * 1.4 * m, -b * 1.4 * m)
	hand_off_v += dir * f * 0.35 * m + UP * f * 0.1 * m
	hy_v -= f * 0.03 * m * size
	hit_dir = dir * minf(1.0, f / 12.0) * m
	hit_age = 0.0


func _reset(w: Wobbler, s: float, yb: Basis) -> void:
	var pos := w.pos
	inited = true
	last_pos = pos
	prev_vel = w.vel
	off = Vector3.ZERO
	off_v = Vector3.ZERO
	hy = LEG * s
	hy_v = 0.0
	tilt.reset()
	nod.reset()
	for i in 2:
		feet[i] = pos + yb.x * (_sgn(i) * 0.2 * s)
		step_t[i] = PLANTED
	hand_off = pos + yb * (Vector3(0.6, 0.8, 0.0) * s)
	hand_off_v = Vector3.ZERO
	pelvis_w = pos + UP * (LEG * s)
	chest_w = pos + UP * (1.55 * s)
	head_w = pos + UP * (1.97 * s)
	aim_hand_w = pos + yb * (Vector3(-0.6, 0.8, 0.0) * s)
	down_k = 0.0
	getup = -1.0
	was_down = false
	was_ground = w.grounded


static func _sgn(i: int) -> float:
	return -1.0 if i == 0 else 1.0       # legs[0] sits at x = -0.2 (the character's right), legs[1] at +0.2


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	return Quaternion(Wobbler._arc(from, to))


## The classic floppy kick angle of leg 1 (Wobbler.animate).
static func _kick_angle(t: float) -> float:
	if t < 0.3:
		return lerpf(0.0, 0.7, t / 0.3)
	if t < 0.5:
		return lerpf(0.7, -2.0, (t - 0.3) / 0.2)
	if t < 0.65:
		return -2.0
	return lerpf(-2.0, 0.0, minf(1.0, (t - 0.65) / 0.35))


func _start_step(i: int, dur: float) -> void:
	foot_from[i] = feet[i]
	step_t[i] = 0.0
	step_dur[i] = dur
	steps += 1


## Collapse: seed the particles from the visible pose, push them toward fall_side and the last hit.
func _start_down(w: Wobbler, s: float, yb: Basis) -> void:
	down_yaw = w.yaw
	px[P_PELVIS] = pelvis_w
	px[P_CHEST] = chest_w
	px[P_HEAD] = head_w
	px[P_FOOT0] = feet[0]
	px[P_FOOT1] = feet[1]
	px[P_HAND] = aim_hand_w
	var fd := -yb.x * w.fall_side                    # fall_side +1 = toward the character's right (classic fall_a)
	var hd := hit_dir if hit_age < 0.5 else Vector3.ZERO
	var extra := UP * 1.5 if w.dead else Vector3.ZERO
	pv[P_PELVIS] = UP * 0.8 + hd * 1.0 + extra
	pv[P_CHEST] = fd * 3.0 * s + hd * 2.5 + UP * 0.4 + extra
	pv[P_HEAD] = fd * 4.2 * s + hd * 3.5 + extra
	pv[P_FOOT0] = -fd * 1.4 * s + UP * 2.6 * s + extra
	pv[P_FOOT1] = -fd * 1.0 * s + UP * 3.2 * s + extra
	pv[P_HAND] = fd * 2.0 * s + UP * 3.0 + extra
	down_k = 1.0
	getup = -1.0


# ================================================================ simulate
func update(w: Wobbler, dt: float) -> void:
	var s := float(w.cls.get("size", 1.0))
	var yb := Basis(UP, w.yaw)
	if not inited or w.pos.distance_to(last_pos) > 4.0:      # spawn / respawn / teleport: start standing
		_reset(w, s, yb)
	if dt <= 0.0:
		return
	time += dt
	var wob := float(w.cls.get("wob", 1.0))
	var pos := w.pos
	var vel := w.vel
	var fwd := yb.z
	var left := yb.x
	var hv := Vector3(vel.x, 0.0, vel.z)
	var speed := hv.length()
	var acc := (vel - prev_vel) / dt
	acc.y = 0.0
	acc = acc.limit_length(80.0)
	var land_vy := prev_vel.y
	prev_vel = vel
	var carry := pos - last_pos
	last_pos = pos
	dmg_age += dt
	hit_age += dt
	var down_now := w.dead or w.down_t > 0.0 or w.trap
	var grounded := w.grounded
	var rs: Vector3 = w.rig_scale

	# ---- state changes
	if down_now and not was_down:
		_start_down(w, s, yb)
	elif not down_now and was_down:                           # get up: feet re-planted under the body, then blend
		getup = 0.0
		off = Vector3.ZERO
		off_v = Vector3.ZERO
		hy = maxf(px[P_PELVIS].y - pos.y, 0.3 * s)
		hy_v = 0.0
		tilt.reset()
		tilt.x = 0.5
		nod.reset()
		for i in 2:
			feet[i] = pos + left * (_sgn(i) * 0.2 * rs.x)
			step_t[i] = PLANTED
	was_down = down_now
	if getup >= 0.0:
		getup += dt
		var e := clampf(getup / GETUP_TIME, 0.0, 1.0)
		down_k = 1.0 - e * e * (3.0 - 2.0 * e)
		if getup >= GETUP_TIME:
			getup = -1.0
			down_k = 0.0

	# ---- collapsed body
	if down_k > 0.0:
		for i in 6:
			px[i] += carry
		if down_now:
			_simulate_down(w, dt, s, pos)

	if down_now:
		was_ground = grounded
		return

	# ---- feet: stick input moves the capsule, the feet chase it
	var lead_len := minf(0.45 * s, speed * 0.07)
	var lead := hv * (lead_len / speed) if speed > 0.05 else Vector3.ZERO
	var home0 := pos + left * (-0.2 * rs.x) + lead
	var home1 := pos + left * (0.2 * rs.x) + lead
	var kicking := w.kick_t >= 0.0
	if grounded:
		if not was_ground:                                    # landing: the hips dip, the feet catch the floor
			hy_v -= maxf(0.0, -land_vy) * 0.12 * s
		if kicking:
			var kxf := Transform3D(yb.scaled_local(rs), pos)
			feet[1] = kxf * (Vector3(0.2, LEG, 0.0) + Basis(Vector3.RIGHT, _kick_angle(w.kick_t)) * Vector3(0.0, -LEG, 0.0))
			step_t[1] = FREE
		for i in 2:
			if step_t[i] == FREE and not (kicking and i == 1):
				_start_step(i, 0.1)
			elif step_t[i] == PLANTED:
				feet[i].y = pos.y
		var e0 := Vector2(feet[0].x - home0.x, feet[0].z - home0.z).length()
		var e1 := Vector2(feet[1].x - home1.x, feet[1].z - home1.z).length()
		var trig := lead_len + s * clampf(0.18 + 0.04 * speed, 0.18, 0.42)   # how far behind the hip a foot may trail
		var dur := clampf(0.42 / (speed + 1.4), 0.1, 0.24)
		var free0 := step_t[0] == PLANTED and (step_t[1] == PLANTED or step_t[1] > 0.45)
		var free1 := step_t[1] == PLANTED and (step_t[0] == PLANTED or step_t[0] > 0.45)
		var best := -1
		if free0 and e0 > trig and (not free1 or e0 >= e1 or e1 <= trig):
			best = 0
		elif free1 and e1 > trig:
			best = 1
		if best < 0 and speed < 0.3 and (free0 or free1):     # standing still: square the feet up after a moment
			if maxf(e0 if free0 else 0.0, e1 if free1 else 0.0) > 0.06 * s:
				idle_t += dt
				if idle_t > 0.3:
					best = 0 if (free0 and (e0 >= e1 or not free1)) else 1
					idle_t = 0.0
			else:
				idle_t = 0.0
		if best >= 0:
			_start_step(best, dur if speed >= 0.3 else 0.18)
		if step_t[0] == PLANTED and e0 > trig + 0.35 * s:     # over-reach (shoved, sprint): step now, whatever
			_start_step(0, 0.12)
		if step_t[1] == PLANTED and e1 > trig + 0.35 * s:
			_start_step(1, 0.12)
		var lift := s * minf(0.1 + 0.025 * speed, 0.3)
		for i in 2:
			if step_t[i] < 0.0:
				continue
			step_t[i] += dt / step_dur[i]
			var t := minf(step_t[i], 1.0)
			var home := home0 if i == 0 else home1
			var tgt := home + hv * ((1.0 - t) * step_dur[i])
			tgt.y = pos.y
			var e := t * t * (3.0 - 2.0 * t)
			var p := foot_from[i].lerp(tgt, e)
			p.y = lerpf(foot_from[i].y, pos.y, e) + sin(PI * t) * lift
			feet[i] = p
			if step_t[i] >= 1.0:
				feet[i] = tgt
				step_t[i] = PLANTED
	else:                                                     # airborne: legs dangle and paddle
		for i in 2:
			step_t[i] = FREE
			var tgt := pos + left * (_sgn(i) * 0.24 * rs.x) + fwd * (_sgn(i) * 0.14 * s * sin(time * 9.0)) + hv * 0.03
			tgt.y = pos.y + (0.12 * s if vel.y > 0.0 else 0.0)
			feet[i] = feet[i].lerp(tgt, minf(1.0, 12.0 * dt))
	was_ground = grounded

	# ---- hips: damped pendulum offset (lag on starts, overshoot on stops), pulled toward the feet, capped by reach
	var k_off := 60.0 / wob
	off_v += (-k_off * off - 2.0 * sqrt(k_off) * 0.35 * off_v - acc * 0.22) * dt
	off += off_v * dt
	off.y = 0.0
	off_v.y = 0.0
	off = off.limit_length(0.35 * s)
	var mid := (feet[0] + feet[1]) * 0.5
	var pel := pos + off
	if grounded:
		pel += Vector3(mid.x - pos.x, 0.0, mid.z - pos.z) * 0.25
	var rest := LEG * rs.y
	var cap := rest
	if grounded:
		var reach := LEG * rs.y * 1.02
		for i in 2:
			if step_t[i] != PLANTED:
				continue
			var hj := pel + left * (_sgn(i) * 0.2 * rs.x)
			var dxz := Vector2(hj.x - feet[i].x, hj.z - feet[i].z).length()
			var h := sqrt(maxf(reach * reach - dxz * dxz, 0.56 * reach * reach))
			cap = minf(cap, feet[i].y - pos.y + h)
	hy_v += (-160.0 * (hy - cap) - 2.0 * sqrt(160.0) * 0.5 * hy_v) * dt
	hy += hy_v * dt
	hy = clampf(hy, 0.35 * rest, 1.15 * rest)

	# ---- torso and head springs (inertia: lean into runs, flop on stops, sway over the stance foot)
	var right := -left
	var sway := 0.0
	for i in 2:
		if step_t[i] >= 0.0:
			sway += _sgn(i) * 0.09 * sin(PI * minf(step_t[i], 1.0))
	var v_f := hv.dot(fwd)
	var v_r := hv.dot(right)
	tilt.step(dt, 70.0 / wob, 0.2, -acc.dot(fwd) * 0.5, -acc.dot(right) * 0.5, clampf(v_f * 0.045, -0.45, 0.45), clampf(v_r * 0.05, -0.45, 0.45) + sway)
	_clamp_spring(tilt, 1.1)
	var tax := (tilt.vx - _tvx) / dt
	var tay := (tilt.vy - _tvy) / dt
	_tvx = tilt.vx
	_tvy = tilt.vy
	nod.step(dt, 45.0 / wob, 0.16, clampf(-tax * 0.3 - acc.dot(fwd) * 0.4, -200.0, 200.0), clampf(-tay * 0.3 - acc.dot(right) * 0.4, -200.0, 200.0))
	_clamp_spring(nod, 0.9)
	pelvis_w = Vector3(pel.x, pos.y + hy, pel.z)


static func _clamp_spring(sp: Spring2, lim: float) -> void:
	if absf(sp.x) > lim:
		sp.x = signf(sp.x) * lim
		sp.vx = 0.0
	if absf(sp.y) > lim:
		sp.y = signf(sp.y) * lim
		sp.vy = 0.0


func _stick(i: int, j: int, lo: float, hi: float) -> void:
	var d := _pp[j] - _pp[i]
	var l := d.length()
	if l < 1e-6:
		return
	var tl := clampf(l, lo, hi)
	if tl == l:
		return
	var c := d * ((l - tl) / l * 0.5)
	_pp[i] += c
	_pp[j] -= c


func _simulate_down(w: Wobbler, dt: float, s: float, pos: Vector3) -> void:
	var damp := maxf(0.0, 1.0 - 1.2 * dt)
	var floor_y := pos.y
	var struggle := w.down_t > 0.0 and not w.dead and not w.trap
	for i in 6:
		var v := pv[i]
		v.y -= GRAV * dt
		v *= damp
		if struggle and (i == P_FOOT0 or i == P_FOOT1 or i == P_HAND):   # stunned: limbs paddle a bit
			v.y += sin(time * 11.0 + i * 1.7) * 9.0 * dt
		_pp[i] = px[i] + v * dt
	var hs := float(w.cls.get("head", 1.0))
	for it in 4:
		_stick(P_PELVIS, P_CHEST, 0.75 * s, 0.75 * s)
		_stick(P_CHEST, P_HEAD, 0.42 * s * hs, 0.45 * s * hs)
		_stick(P_PELVIS, P_HEAD, 0.95 * s, 1.3 * s)
		_stick(P_PELVIS, P_FOOT0, 0.45 * s, 0.84 * s)
		_stick(P_PELVIS, P_FOOT1, 0.45 * s, 0.84 * s)
		_stick(P_FOOT0, P_FOOT1, 0.25 * s, 1.4 * s)
		_stick(P_CHEST, P_HAND, 0.55 * s, 0.92 * s)
		for i in 6:
			var r: float = RADIUS[i] * s
			var q := _pp[i]
			if q.y < floor_y + r:
				q.y = floor_y + r
				_pp[i] = q
	# the body stays with the capsule
	var pp := _pp[P_PELVIS]
	var dx := Vector2(pp.x - pos.x, pp.z - pos.z)
	var lim := 0.7 * s
	if dx.length() > lim:
		var c := dx * (1.0 - lim / dx.length())
		for i in 6:
			_pp[i] -= Vector3(c.x, 0.0, c.y)
	for i in 6:
		var v := (_pp[i] - px[i]) / dt
		if _pp[i].y <= floor_y + RADIUS[i] * s + 1e-3:          # floor friction
			var fr := maxf(0.0, 1.0 - 9.0 * dt)
			v.x *= fr
			v.z *= fr
		pv[i] = v
		px[i] = _pp[i]


# ================================================================ pose the nodes
## Writes the visible transforms of the wobbler's nodes. `grip` = the classic world (wobbler-local) grip transform.
func render(w: Wobbler, dt: float, grip: Transform3D) -> void:
	var s := float(w.cls.get("size", 1.0))
	var dk := down_k
	var yaw_used := lerp_angle(w.yaw, down_yaw, dk)
	var yb := Basis(UP, yaw_used)
	var rs: Vector3 = w.rig_scale.lerp(Vector3.ONE * s, dk)
	var rig_xf := Transform3D(yb.scaled_local(rs), w.pos)
	var rig_inv := rig_xf.affine_inverse()
	w.rig.transform = rig_xf

	# standing pose (rig local)
	var pel_l := rig_inv * pelvis_w
	var twist := clampf((feet[1] - feet[0]).dot(yb.z) / maxf(s, 0.1) * 0.3, -0.35, 0.35)
	var body_q := Quaternion(Wobbler._euler_xyz(Vector3(tilt.x, twist, tilt.y)))
	var neck_q := Quaternion(Wobbler._euler_xyz(Vector3(nod.x, -twist * 0.6, nod.y)))
	var f0 := rig_inv * feet[0]
	var f1 := rig_inv * feet[1]
	var hip_q := Quaternion(Basis(UP, twist * 0.5))
	if dk > 0.0:                                            # collapsed body (rig local), blended in
		var dp := rig_inv * px[P_PELVIS]
		var dc := rig_inv * px[P_CHEST]
		var dh := rig_inv * px[P_HEAD]
		var bq := _arc(UP, (dc - dp).normalized())
		var bb := Basis(bq)
		var hb := bb.inverse() * (dh - (dp + bb * Vector3(0.0, 0.85, 0.0)))
		var nq := _arc(UP, hb.normalized()) if hb.length_squared() > 1e-6 else Quaternion.IDENTITY
		pel_l = pel_l.lerp(dp, dk)
		body_q = body_q.slerp(bq, dk)
		neck_q = neck_q.slerp(nq, dk)
		hip_q = hip_q.slerp(bq, dk)
		f0 = f0.lerp(rig_inv * px[P_FOOT0], dk)
		f1 = f1.lerp(rig_inv * px[P_FOOT1], dk)
	var body_b := Basis(body_q)
	w.body.transform = Transform3D(body_b, pel_l)
	var hsc := float(w.cls.get("head", 1.0))
	w.neck.basis = Basis(neck_q).scaled_local(Vector3.ONE * hsc)

	# legs: from the hip joints to the feet, stretched a little; the foot block stays flat while standing
	var hip_b := Basis(hip_q)
	for i in 2:
		var hip := pel_l + hip_b * Vector3(_sgn(i) * 0.2, 0.0, 0.0)
		var d := (f0 if i == 0 else f1) - hip
		var l := d.length()
		var ky := 1.0
		var r := Quaternion.IDENTITY
		if l > 1e-4:
			r = _arc(DOWN, d / l)
			leg_k[i] = l / LEG
			ky = clampf(leg_k[i], 0.6, 1.1)
		var lg: Node3D = w.legs[i]
		lg.position = hip
		lg.basis = Basis(r) * Basis.from_scale(Vector3(1.0, ky, 1.0))
		var unscale := Basis.from_scale(Vector3(1.0, 1.0 / ky, 1.0))
		w.foot_meshes[i].basis = unscale * Basis(r.inverse().slerp(Quaternion.IDENTITY, dk))

	# points for the next collapse / tests
	var body_xf := rig_xf * w.body.transform
	pelvis_w = body_xf.origin if dk > 0.0 else pelvis_w
	chest_w = body_xf * Vector3(0.0, 0.75, 0.0)
	head_w = body_xf * (w.neck.transform * Vector3(0.0, 0.32, 0.0))

	# off arm: verlet pendulum from the visible shoulder, a weak muscle toward the classic swing
	shoulder_off_w = body_xf * w.arm_l.position
	var gb := (rig_xf.basis * body_b).orthonormalized()
	var classic_dir := gb * (w.arm_l.basis * DOWN).normalized()
	var len_off := ARM_L * s
	if dt > 0.0:
		var old := hand_off
		hand_off_v.y -= GRAV * dt
		hand_off_v += (shoulder_off_w + classic_dir * len_off - hand_off) * (22.0 * dt * (1.0 - dk))
		hand_off_v *= maxf(0.0, 1.0 - 2.5 * dt)
		hand_off += hand_off_v * dt
		var dd := hand_off - shoulder_off_w
		var local := gb.inverse() * dd
		if local.x < 0.15 * len_off and dk < 0.5:          # never swing through the torso
			local.x = 0.15 * len_off
			dd = gb * local
		if dd.length_squared() < 1e-8:
			dd = classic_dir
		dd = dd.normalized() * len_off
		var fl := w.pos.y + 0.1 * s - shoulder_off_w.y           # keep the hand above the floor, arm length exact
		if dd.y < fl and fl < len_off:
			var hz := Vector2(dd.x, dd.z)
			var hl := sqrt(len_off * len_off - fl * fl)
			hz = hz.normalized() * hl if hz.length_squared() > 1e-8 else Vector2(hl, 0.0)
			dd = Vector3(hz.x, fl, hz.y)
		hand_off = shoulder_off_w + dd
		hand_off_v = (hand_off - old) / dt
	else:
		hand_off = shoulder_off_w + classic_dir * len_off
	var dl := gb.inverse() * (hand_off - shoulder_off_w)
	if dl.length_squared() > 1e-8:
		w.arm_l.basis = Basis(_arc(DOWN, dl.normalized()))

	# aim arm: from the visible shoulder to the sim hand; the grip keeps the classic world transform (true aim)
	shoulder_w = body_xf * w.shoulder.position
	var target := grip.origin
	var up_k := clampf(1.0 - absf(w.fall_a) / 0.3, 0.0, 1.0) * (1.0 - w.lie_k)
	if up_k < 1.0:                                      # classic pose not upright (its own get-up spin): hang the arm
		var hang := shoulder_w + (rig_xf.basis.orthonormalized() * Vector3(0.0, -1.0, 0.25)).normalized() * (ARM * s)
		target = hang.lerp(target, up_k)
	if dk > 0.0:
		target = target.lerp(px[P_HAND], dk)
	var da := target - shoulder_w
	var la := da.length()
	var dir := da / la if la > 1e-4 else DOWN
	arm_k = la / (ARM * s)
	var lr := clampf(la / s, 0.45, 1.3)
	var arm_xf := Transform3D(Basis(_arc(DOWN, dir)).scaled(Vector3.ONE * s), shoulder_w)
	w.arm.transform = arm_xf
	w.arm_sleeve.transform = Transform3D(Basis.from_scale(Vector3(1.0, lr / ARM, 1.0)), Vector3(0.0, -lr * 0.5, 0.0))
	w.arm_hand_mesh.position = Vector3(0.0, -lr, 0.0)
	var g_local := arm_xf.affine_inverse() * grip
	var free_k := maxf(dk, 1.0 - up_k)
	aim_free = free_k
	if free_k > 0.0:
		g_local = g_local.interpolate_with(Transform3D(Basis.IDENTITY, Vector3(0.0, -lr, 0.0)), free_k)
	w.hand.transform = g_local
	aim_hand_w = arm_xf * w.hand.position
