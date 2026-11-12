class_name FollowCamera
extends Camera3D
## Third-person follow camera, ported from updateCamera (public/index.html ~9674): yaw/pitch orbit around a pivot above
## the player, over-the-shoulder offset, aim zoom (distance, shoulder, height and FOV blend with `aim`), pulled in when a
## solid is between the pivot and the camera. Orbit mode (menus / fell out) circles the map like the web game.
## Not ported yet: kill cam, scoped weapon FOV per weapon, giant scale, screen shake.

const PITCH_MIN := -1.1
const PITCH_MAX := 0.8
const AIM_FOV := 52.0

var yaw := PI
var pitch := -0.2
var aim := 0.0            ## 0 = hip, 1 = aiming (eased)
var orbit_t := 0.0
var aim_point := Vector3.ZERO   ## where the crosshair points (first solid hit or 150 m)

func add_look(d: Vector2) -> void:
	yaw += d.x
	pitch = clampf(pitch + d.y, PITCH_MIN, PITCH_MAX)

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
