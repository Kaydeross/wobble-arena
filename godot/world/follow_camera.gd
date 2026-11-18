class_name FollowCamera
extends Camera3D
## Third-person follow camera, ported from updateCamera (public/index.html ~9674): yaw/pitch orbit around a pivot above
## the player, over-the-shoulder offset, aim zoom (distance, shoulder, height and FOV blend with `aim`), pulled in when a
## solid is between the pivot and the camera. Orbit mode (menus / fell out) circles the map like the web game.
## Kill cam: world/kill_cam.gd drives this camera while it replays. Not ported yet: scoped weapon FOV per weapon, giant scale.
## Screen shake (web cam.shake): add_shake() / apply_shake(), presentation only (after aim_point is computed; the
## next follow() starts from a clean transform). Settings `screen_shake` (default on) gates it, `shake_scale` scales it.
##
## Auto-centre (Godot only, Settings `cam_auto_center` / `cam_center_dist`): after the player has walked `cam_center_dist`
## metres (default 5) since the last manual look input (mouse, look drag, right stick), aim or fire, the yaw eases to the
## direction of travel (= the character's facing while not aiming) and the pitch back to DEFAULT_PITCH with a critically
## damped spring (SmoothDamp, ~0.4 s; faster while sprinting), and then keeps following the travel direction while the
## stick stays held. It never runs while aiming, firing or a look touch is down, nor while standing still.
## The stick maps against `move_basis()`, not `yaw`: the basis is latched while the stick is held in one direction, so the
## camera turning under a held stick cannot turn the walk (no feedback loop); it re-latches to the camera yaw when the stick
## is released or turned by more than LATCH_TURN, and on any manual look.
##
## Impact freeze / zoom (Post-v0.4.0 Sprint 2.1, docs/GRAPHICS.md): the FINAL K.O. moment (fx.gd decides when: a
## match-winning K.O., a Sudden Death elimination or an Arcade boss K.O.) sets `Engine.time_scale` to 0.15 for 0.9 s of
## REAL time while the camera zooms (narrower FOV, shorter arm, pivot leaning toward the decisive hit). The state lives
## here because this camera is the one object every rendered frame goes through: HUD.update() and KillCam.step() call
## tick_impact(), and reset_view() (World.load_map), end_impact() and _exit_tree() restore the global time scale, so a
## match restart, a scene teardown or a skipped kill cam can never leave the game in slow motion. Presentation only: the
## explicit deltas headless suites pass to World.tick() are never scaled.

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
const IMPACT_TIME_SCALE := 0.15    ## the final K.O.'s engine time scale (Sprint 2.1)
const IMPACT_MS := 900.0           ## how long the freeze lasts, in REAL milliseconds
const IMPACT_BADGE_MS := 1500.0    ## how long the comic HUD badge stays up, in REAL milliseconds
const IMPACT_ATTACK := 0.14        ## s the zoom takes to reach full
const IMPACT_RELEASE := 0.30       ## s the zoom eases back out at the end of the freeze
const IMPACT_ZOOM := 0.22          ## FOV narrowing at full impact (fraction of the base FOV)
const IMPACT_PULL := 0.30          ## arm shortened at full impact (fraction of the follow distance)
const IMPACT_FOCUS := 0.45         ## how far the orbit pivot leans toward the decisive hit

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
var shake := 0.0                ## current shake amplitude (m), decays exp(-9 t) like the web game
var shake_scale := 1.0
var _shake_off := Vector3.ZERO  ## the offset applied this frame (removed before the next one)
var _shake_rng := RandomNumberGenerator.new()
## Final K.O. impact freeze / zoom (Sprint 2.1): `impact_kmh` is the victim's launch speed for the comic badge, or -1
## for a ring-out without launch speed ("TERMINAL RING-OUT!"). Everything is real-time (Time.get_ticks_msec), never the
## scaled frame delta, so the freeze ends after 0.9 s of wall clock even while the match itself runs at 0.15x.
var impact_in_tests := false      ## hand-stepped suites opt in (world/fx.gd only freezes when auto_run or this is set)
var impact_active := false
var impact_kmh := -1
var impact_started_ms := 0
var impact_until_ms := 0
var impact_badge_until_ms := 0
var impact_focus := Vector3.ZERO
var _impact_k := 0.0              ## eased 0..1 amount currently applied
var _impact_fov_k := 0.0          ## amount the last follow() zoomed by (undone by end_impact)

## A shake pulse (the web game's `cam.shake = max(cam.shake, a)`).
func add_shake(a: float) -> void:
	shake = maxf(shake, a)

## Presentation only: nudge the camera after follow(); never feeds aim_point or the move basis.
func apply_shake(dt: float) -> void:
	position -= _shake_off
	_shake_off = Vector3.ZERO
	if shake <= 0.002:
		shake = 0.0
		return
	var k := shake * shake_scale * (1.0 if bool(Settings.get_value("screen_shake", true)) else 0.0)
	_shake_off = Vector3(_shake_rng.randf_range(-1, 1), _shake_rng.randf_range(-1, 1), _shake_rng.randf_range(-1, 1)) * k
	position += _shake_off
	shake *= exp(-9.0 * dt)

# ---------------- final K.O. impact freeze / zoom (Sprint 2.1) ----------------

## A decisive K.O. just happened (world/fx.gd): freeze the match at 0.15x for 0.9 s REAL time and zoom in on `focus`
## (the victim's position). `kmh` is the launch speed shown by the comic HUD badge; -1 = a ring-out with no launch speed.
## One moment at a time: a second decisive K.O. inside the freeze is ignored.
func trigger_impact(kmh: int, focus: Vector3) -> void:
	if impact_active: return
	var now := Time.get_ticks_msec()
	impact_active = true
	impact_kmh = kmh
	impact_focus = focus
	impact_started_ms = now
	impact_until_ms = now + int(IMPACT_MS)
	impact_badge_until_ms = now + int(IMPACT_BADGE_MS)
	_impact_k = 0.0
	_impact_fov_k = 0.0
	Engine.time_scale = IMPACT_TIME_SCALE

## REAL-time update of the moment: called every rendered frame from HUD.update() (normal play) and KillCam.step()
## (the replay), the two places that see every frame. Ends the freeze itself when the 0.9 s are up.
func tick_impact() -> void:
	if not impact_active: return
	var now := Time.get_ticks_msec()
	var t := float(now - impact_started_ms) / 1000.0
	if now >= impact_until_ms:
		end_impact()
		return
	var rise := clampf(t / IMPACT_ATTACK, 0.0, 1.0)
	rise = rise * rise * (3.0 - 2.0 * rise)
	var left := clampf(float(impact_until_ms - now) / 1000.0 / IMPACT_RELEASE, 0.0, 1.0)
	left = left * left * (3.0 - 2.0 * left)
	_impact_k = rise * left

## End the freeze now: back to normal time, undo the zoom, keep the badge up for the rest of its own 1.5 s. Safe to call
## any number of times and on a teardown path (it is what guarantees Engine.time_scale can never be left at 0.15).
func end_impact() -> void:
	if impact_active:
		impact_active = false
		_impact_k = 0.0
		if _impact_fov_k > 0.0:
			fov /= (1.0 - IMPACT_ZOOM * _impact_fov_k)      # take back the zoom follow() applied last frame
			_impact_fov_k = 0.0
	Engine.time_scale = 1.0

## 0..1 amount of the zoom currently applied (tests / the kill cam).
func impact_amount() -> float:
	return _impact_k

## Is the comic badge still inside its ~1.5 s REAL window?
func impact_badge_visible() -> bool:
	return impact_badge_until_ms > 0 and Time.get_ticks_msec() < impact_badge_until_ms

## A base FOV with the impact zoom applied (the kill cam also asks for it, so a replay keeps the effect if it is active).
func impact_fov(base: float) -> float:
	return base * (1.0 - IMPACT_ZOOM * _impact_k)

func _exit_tree() -> void:
	end_impact()                    # a freed World camera must never leave the engine in slow motion

func add_look(d: Vector2) -> void:
	yaw += d.x
	pitch = clampf(pitch + d.y, PITCH_MIN, PITCH_MAX)
	_own_yaw += d.x   # keeps any outside write visible to auto_center
	if d != Vector2.ZERO:
		_latched = false

## Back to the default view (match start). Also ends any final-K.O. freeze: World.load_map calls this for a fresh match,
## so a restart can never inherit the previous match's 0.15x time scale or zoom.
func reset_view() -> void:
	end_impact()
	end_podium_shot()
	yaw = DEFAULT_YAW; pitch = DEFAULT_PITCH
	travel = 0.0; centering = false; _ramp_t = 0.0; _yaw_v = 0.0; _pitch_v = 0.0; _latched = false; _own_yaw = yaw

# ---------------- results podium shot (world/winner_podium.gd) ----------------

## The 3D winner podium's results shot: the camera leaves the follow view, eases over PODIUM_BLEND to the podium
## framing (the podium's camera_shot()) and stays there until the result closes. Presentation only: the match is frozen
## offline (and over online) behind the results panel, and a tap / key still comes through the pause menu.
const PODIUM_BLEND := 1.15        ## s: the smooth move from the match view to the podium shot
const PODIUM_FOV := 54.0          ## narrower than play: the podium and the arena behind it fill the frame

var podium_shot := false          ## true while the results camera owns the transform
var _podium_t := 0.0
var _podium_from_pos := Vector3.ZERO
var _podium_from_look := Vector3.ZERO
var _podium_from_fov := 72.0

## Start the results shot from wherever the camera is now (called when the podium is built).
func begin_podium_shot() -> void:
	if podium_shot: return
	podium_shot = true
	_podium_t = 0.0
	_podium_from_pos = global_position
	_podium_from_look = global_position - global_transform.basis.z * 8.0
	_podium_from_fov = fov

func end_podium_shot() -> void:
	podium_shot = false
	_podium_t = 0.0

## One rendered frame of the results shot: ease position / look / FOV in and pull the camera in front of any solid
## between the podium and the shot (the same ray test follow() uses), so the result never looks through a wall.
func frame_podium(dt: float, pos: Vector3, look: Vector3, solids: Array) -> void:
	if not podium_shot: begin_podium_shot()
	var to_cam := pos - look
	var d := to_cam.length()
	if d > 0.01:
		to_cam /= d
		var hit := ray_solids(look, to_cam, d, solids)
		if hit < d: pos = look + to_cam * maxf(1.4, hit - 0.4)
	_podium_t = minf(_podium_t + maxf(dt, 0.0), PODIUM_BLEND)
	var k := smoothstep(0.0, 1.0, _podium_t / PODIUM_BLEND)
	look_at_from_position(_podium_from_pos.lerp(pos, k), _podium_from_look.lerp(look, k), Vector3.UP)
	var want := lerpf(_podium_from_fov, PODIUM_FOV, k)
	if absf(fov - want) > 0.01: fov = want
	aim_point = look
	_shake_off = Vector3.ZERO

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

## The inner rectangle (x, z) of a walled yard's fence, or an empty Rect2 for an open arena. Fence = the tall thin boxes
## of the perimeter (Backyard BBQ's 2.8 m corrugated fence): per side the inner face shared by the most fence length wins,
## so a stray tall post or prop cannot move it. Needs all four sides.
static func arena_bounds(solids: Array) -> Rect2:
	var sides := [{}, {}, {}, {}]    ## x-min wall, x-max wall, z-min wall, z-max wall: inner face (rounded cm) -> total length
	for b: Dictionary in solids:
		if float(b["top"]) - float(b["bottom"]) < 2.0 or float(b["top"]) < 2.0: continue
		var w := float(b["maxX"]) - float(b["minX"])
		var d := float(b["maxZ"]) - float(b["minZ"])
		var cx := (float(b["minX"]) + float(b["maxX"])) * 0.5
		var cz := (float(b["minZ"]) + float(b["maxZ"])) * 0.5
		if w <= 0.6 and d >= 1.0 and absf(cx) > 8.0:
			var si := 0 if cx < 0.0 else 1
			var face := roundf((float(b["maxX"]) if cx < 0.0 else float(b["minX"])) * 100.0)
			sides[si][face] = float(sides[si].get(face, 0.0)) + d
		elif d <= 0.6 and w >= 1.0 and absf(cz) > 8.0:
			var si := 2 if cz < 0.0 else 3
			var face := roundf((float(b["maxZ"]) if cz < 0.0 else float(b["minZ"])) * 100.0)
			sides[si][face] = float(sides[si].get(face, 0.0)) + w
	var v: Array = []
	for si in 4:
		var best_len := 0.0
		var best_face := 0.0
		for f: float in sides[si]:
			if float(sides[si][f]) > best_len: best_len = float(sides[si][f]); best_face = f
		if best_len < 20.0: return Rect2()      # not a closed fence: an open arena keeps its framing
		v.append(best_face / 100.0)
	return Rect2(Vector2(v[0], v[2]), Vector2(v[1] - v[0], v[3] - v[2]))

## Distance along the ray (o, d) at which it leaves `bounds` (o inside), or `far`.
static func exit_bounds(o: Vector3, d: Vector3, far: float, bounds: Rect2) -> float:
	var t := far
	if d.x > 1e-9: t = minf(t, (bounds.end.x - o.x) / d.x)
	elif d.x < -1e-9: t = minf(t, (bounds.position.x - o.x) / d.x)
	if d.z > 1e-9: t = minf(t, (bounds.end.y - o.z) / d.z)
	elif d.z < -1e-9: t = minf(t, (bounds.position.y - o.z) / d.z)
	return t

## `bounds`: the yard's fence rectangle (arena_bounds) or an empty Rect2. The camera arm sits above the head and behind,
## so near a fence its ray passes OVER the fence top and the camera ends up outside the yard looking in: the arm is
## also cut where it leaves the bounds.
func follow(dt: float, target: Vector3, aiming: bool, solids: Array, zoom_fov := AIM_FOV, bounds := Rect2()) -> void:
	aim += ((1.0 if aiming else 0.0) - aim) * minf(1.0, 12.0 * dt)
	var cam_dist := float(Settings.get_value("cam_dist", 1.0))
	var dist := lerpf(6.2, 2.4, aim) * cam_dist
	var shoulder := lerpf(0.8, 1.15, aim)
	var height := lerpf(2.0, 1.85, aim)
	var want_fov := lerpf(float(Settings.get_value("fov", 72.0)), zoom_fov, aim)
	var k := _impact_k
	if k > 0.0:                                  # final K.O.: pull the arm in and narrow the FOV
		dist *= 1.0 - IMPACT_PULL * k
		want_fov = impact_fov(want_fov)
		_impact_fov_k = k
	var sy := sin(yaw); var cy := cos(yaw); var sp := sin(pitch); var cp := cos(pitch)
	var fwd := Vector3(sy * cp, sp, cy * cp)
	var pivot := target + Vector3(0, height, 0)
	if k > 0.0:                                  # ... and lean the orbit pivot toward the decisive hit
		pivot = pivot.lerp(impact_focus, IMPACT_FOCUS * k)
	var desired := pivot - fwd * dist
	desired.x += -cy * shoulder
	desired.z += sy * shoulder
	var dir := desired - pivot
	var l := dir.length()
	dir /= l
	var hit := ray_solids(pivot, dir, l, solids)
	if hit < l:
		l = maxf(0.5, hit - 0.3)
	if bounds.has_area() and bounds.grow(-0.2).has_point(Vector2(pivot.x, pivot.z)):
		var out := exit_bounds(pivot, dir, l, bounds.grow(-0.3))
		if out < l: l = maxf(0.5, out)
	var cam_pos := pivot + dir * l
	look_at_from_position(cam_pos, cam_pos + fwd, Vector3.UP)
	if absf(fov - want_fov) > 0.01:
		fov = want_fov
	aim_point = cam_pos + fwd * ray_solids(cam_pos, fwd, 150.0, solids)
	_shake_off = Vector3.ZERO          # a fresh transform: nothing to take back

## Menus / spectating: slowly circle the map (`orbit`, `orbitH` from maps.json).
func orbit(dt: float, map: Dictionary) -> void:
	orbit_t += dt * 0.15
	var r := float(map.get("orbit", 40)); var h := float(map.get("orbitH", 22))
	look_at_from_position(Vector3(cos(orbit_t) * r, h, sin(orbit_t) * r), Vector3(0, 2, 0), Vector3.UP)
	_shake_off = Vector3.ZERO
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
