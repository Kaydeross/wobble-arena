class_name FollowCamera
extends Camera3D
## Third-person follow camera, ported from updateCamera (public/index.html ~9674): yaw/pitch orbit around a pivot above
## the player, over-the-shoulder offset, aim zoom (distance, shoulder, height and FOV blend with `aim`), pulled in when a
## solid is between the pivot and the camera. Orbit mode (menus / fell out) circles the map like the web game.
## Kill cam: world/kill_cam.gd drives this camera while it replays. Not ported yet: scoped weapon FOV per weapon, giant scale, screen shake.
##
## Auto-centre (Godot only, Settings `cam_auto_center` / `cam_center_dist`): after the player has walked `cam_center_dist`
## metres (default 5) since the last manual look input (mouse, look drag, right stick), aim or fire, the yaw eases to the
## direction of travel (= the character's facing while not aiming) and the pitch back to DEFAULT_PITCH with a critically
## damped spring (SmoothDamp, ~0.4 s; faster while sprinting), and then keeps following the travel direction while the
## stick stays held. It never runs while aiming, firing or a look touch is down, nor while standing still.
## The stick maps against `move_basis()`, not `yaw`: the basis is latched while the stick is held in one direction, so the
## camera turning under a held stick cannot turn the walk (no feedback loop); it re-latches to the camera yaw when the stick
## is released or turned by more than LATCH_TURN, and on any manual look.

const PITCH_MIN := -1.1
const PITCH_MAX := 0.8
const AIM_FOV := 52.0
const DEFAULT_YAW := PI
const DEFAULT_PITCH := -0.2
const CENTER_SMOOTH := 0.7         ## SmoothDamp time (s) walking: a slow, gentle swing (~90 % in 1.6 s, settled by ~2.2 s)
const CENTER_SMOOTH_SPRINT := 0.45 ## sprinting (a little quicker)
const CENTER_DEADZONE := 0.35     ## rad (~20 deg): a smaller offset than this is left alone, so small turns never drag the camera
const CENTER_RAMP := 1.2           ## s: the swing starts at a third of its speed and builds up to full over this time
const CENTER_MIN_SPEED := 0.8      ## m/s: slower than this is standing (knockback alone never recentres)
const STICK_MIN := 0.2             ## stick length below this = released
const LATCH_TURN := 0.35           ## rad the stick may turn before the basis re-latches to the camera

var yaw := PI
var pitch := -0.2
var aim := 0.0            ## 0 = hip, 1 = aiming (eased)
var orbit_t := 0.0
var aim_point := Vector3.ZERO   ## where the crosshair points (first solid hit or 150 m)
var travel := 0.0               ## metres walked since the last manual look / aim / fire
var centering := false          ## auto-centre active (travel reached cam_center_dist)
var _ramp_t := 0.0              ## seconds since the swing started (eases the start so it never jerks)
var _yaw_v := 0.0
var _pitch_v := 0.0
var _latched := false           ## stick basis held apart from `yaw` (see move_basis)
var _basis := PI
var _stick := Vector2.ZERO      ## stick direction when the basis was latched
var _own_yaw := PI              ## yaw as this script last left it: a different value = set from outside (tests, kill cam)

func add_look(d: Vector2) -> void:
	yaw += d.x
	pitch = clampf(pitch + d.y, PITCH_MIN, PITCH_MAX)
	_own_yaw += d.x   # keeps any outside write visible to auto_center
	if d != Vector2.ZERO:
		_latched = false

## Back to the default view (match start).
func reset_view() -> void:
	yaw = DEFAULT_YAW; pitch = DEFAULT_PITCH
	travel = 0.0; centering = false; _ramp_t = 0.0; _yaw_v = 0.0; _pitch_v = 0.0; _latched = false; _own_yaw = yaw

## Yaw the movement stick maps against (PlayerControl.cam_yaw): the camera yaw, except while auto-centre turns the camera
## under a held stick, when it stays where it was when the stick was pushed.
func move_basis() -> float:
	return _basis if _latched and yaw == _own_yaw else yaw

## Per frame, after add_look: `look` = this frame's manual look delta, `stick` = InputState.move(), `vel` = the player's
## horizontal velocity (x, z), `hold` = aiming / firing / a look touch is down, `sprint` = sprint held.
func auto_center(dt: float, look: Vector2, stick: Vector2, vel: Vector2, hold: bool, sprint: bool) -> void:
	if look != Vector2.ZERO or hold or yaw != _own_yaw:   # a manual look (or yaw set from outside) starts the count again
		travel = 0.0; centering = false; _ramp_t = 0.0; _yaw_v = 0.0; _pitch_v = 0.0; _latched = false; _own_yaw = yaw
		return
	# stick basis: release or a new direction re-latches to the camera as it is now
	if stick.length() < STICK_MIN:
		_latched = false
		_stick = Vector2.ZERO
	elif not _latched or absf(stick.angle_to(_stick)) > LATCH_TURN:
		_latched = true
		_basis = yaw
		_stick = stick.normalized()
	var speed := vel.length()
	if not bool(Settings.get_value("cam_auto_center", true)) or stick.length() < STICK_MIN or speed < CENTER_MIN_SPEED:
		_yaw_v = 0.0; _pitch_v = 0.0
		return
	travel += speed * dt
	if travel < float(Settings.get_value("cam_center_dist", 5.0)):
		return
	var target := atan2(vel.x, vel.y)
	var err := wrapf(target - yaw, -PI, PI)
	if not centering and absf(err) < CENTER_DEADZONE:
		return                          # already roughly behind the direction of travel: leave the camera alone
	centering = true
	_ramp_t += dt
	var st := (CENTER_SMOOTH_SPRINT if sprint else CENTER_SMOOTH) * lerpf(3.0, 1.0, clampf(_ramp_t / CENTER_RAMP, 0.0, 1.0))
	var r := smooth_damp(0.0, err, _yaw_v, st, dt)
	yaw += r.x; _yaw_v = r.y; _own_yaw = yaw
	r = smooth_damp(pitch, DEFAULT_PITCH, _pitch_v, st, dt)
	pitch = r.x; _pitch_v = r.y

## Critically damped spring toward `target` (Game Programming Gems 4 / Unity SmoothDamp): no overshoot on a still
## target. Returns (new value, new velocity).
static func smooth_damp(cur: float, target: float, vel: float, smooth: float, dt: float) -> Vector2:
	var omega := 2.0 / smooth
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - target
	var temp := (vel + omega * change) * dt
	vel = (vel - omega * temp) * e
	var out := target + (change + temp) * e
	if (target - cur > 0.0) == (out > target):   # never step past the target
		out = target; vel = 0.0
	return Vector2(out, vel)

## Horizontal forward of the camera (the web game's movement basis).
func forward_flat() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))

func follow(dt: float, target: Vector3, aiming: bool, solids: Array, zoom_fov := AIM_FOV) -> void:
	aim += ((1.0 if aiming else 0.0) - aim) * minf(1.0, 12.0 * dt)
	var cam_dist := float(Settings.get_value("cam_dist", 1.0))
	var dist := lerpf(6.2, 2.4, aim) * cam_dist
	var shoulder := lerpf(0.8, 1.15, aim)
	var height := lerpf(2.0, 1.85, aim)
	var want_fov := lerpf(float(Settings.get_value("fov", 72.0)), zoom_fov, aim)
	var sy := sin(yaw); var cy := cos(yaw); var sp := sin(pitch); var cp := cos(pitch)
	var fwd := Vector3(sy * cp, sp, cy * cp)
	var pivot := target + Vector3(0, height, 0)
	var desired := pivot - fwd * dist
	desired.x += -cy * shoulder
	desired.z += sy * shoulder
	var dir := desired - pivot
	var l := dir.length()
	dir /= l
	var hit := ray_solids(pivot, dir, l, solids)
	if hit < l:
		l = maxf(0.5, hit - 0.3)
	var cam_pos := pivot + dir * l
	look_at_from_position(cam_pos, cam_pos + fwd, Vector3.UP)
	if absf(fov - want_fov) > 0.01:
		fov = want_fov
	aim_point = cam_pos + fwd * ray_solids(cam_pos, fwd, 150.0, solids)

## Menus / spectating: slowly circle the map (`orbit`, `orbitH` from maps.json).
func orbit(dt: float, map: Dictionary) -> void:
	orbit_t += dt * 0.15
	var r := float(map.get("orbit", 40)); var h := float(map.get("orbitH", 22))
	look_at_from_position(Vector3(cos(orbit_t) * r, h, sin(orbit_t) * r), Vector3(0, 2, 0), Vector3.UP)
	fov = 55.0

## Distance along a ray to the first solid box (slab test), or `far` when nothing is hit.
static func ray_solids(o: Vector3, d: Vector3, far: float, solids: Array) -> float:
	var best := far
	for b in solids:
		var t0 := 0.0
		var t1 := best
		var ok := true
		for ax in 3:
			var o_a: float = o[ax]
			var d_a: float = d[ax]
			var lo: float = b.minX if ax == 0 else (b.bottom if ax == 1 else b.minZ)
			var hi: float = b.maxX if ax == 0 else (b.top if ax == 1 else b.maxZ)
			if absf(d_a) < 1e-9:
				if o_a < lo or o_a > hi:
					ok = false; break
			else:
				var ta := (lo - o_a) / d_a
				var tb := (hi - o_a) / d_a
				if ta > tb:
					var tmp := ta; ta = tb; tb = tmp
				t0 = maxf(t0, ta); t1 = minf(t1, tb)
				if t0 > t1:
					ok = false; break
		if ok and t0 < best and t0 > 0.0:
			best = t0
	return best
