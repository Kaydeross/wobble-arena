class_name FighterPhysics
extends RefCounted
## Movement and collision, ported 1:1 from the web game (Fighter.physics + collide in public/index.html).
## Uses plain 64-bit floats (not Vector3) so it stays numerically identical to the JS version.
## Solids are boxes {minX,maxX,minZ,maxZ,top,bottom}; build them with FighterPhysics.solids_from_map().

const R := 0.45
const STEP := 0.55
const FH := 2.3
const GRAV := 24.0

var px := 0.0
var py := 0.0
var pz := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var wish_x := 0.0
var wish_z := 0.0
var speed := 7.5
var want_jump := false
var grounded := false
var crouch_k := 0.0
var incapacitated := false   ## dead, knocked down or trapped: no steering, no jumping
var grav_scale := 1.0
var ice_grip := false         ## maps with `grip`: slidey steering

## One map's `geometry.boxes` (from shared/maps.json) -> solids.
static func solids_from_map(map: Dictionary) -> Array:
	var out := []
	for b in map["geometry"]["boxes"]:
		var w := float(b["w"]); var d := float(b["d"]); var y := float(b["y"]); var h := float(b["h"])
		out.append({
			"minX": float(b["x"]) - w / 2.0, "maxX": float(b["x"]) + w / 2.0,
			"minZ": float(b["z"]) - d / 2.0, "maxZ": float(b["z"]) + d / 2.0,
			"top": y + h, "bottom": y,
		})
	return out

func place(x: float, y: float, z: float) -> void:
	px = x; py = y; pz = z; vx = 0.0; vy = 0.0; vz = 0.0

func step(dt: float, solids: Array) -> void:
	var ctrl := 0.0 if incapacitated else 1.0
	var tx := wish_x * speed * ctrl
	var tz := wish_z * speed * ctrl
	var acc := 40.0 if grounded else 14.0
	if ice_grip and grounded and not incapacitated:
		acc = 32.0 if hypot(wish_x, wish_z) > 0.05 else 20.0 * pow(0.05, 0.5)
	var dx := tx - vx
	var dz := tz - vz
	var length := hypot(dx, dz)
	var md := acc * dt
	if length <= md:
		vx = tx; vz = tz
	else:
		vx += dx / length * md; vz += dz / length * md

	if want_jump and grounded and not incapacitated:
		vy = 7.4 if grav_scale < 0.3 else 9.2
		grounded = false
	want_jump = false

	vy = maxf(vy - GRAV * grav_scale * dt, -22.0)
	px += vx * dt; py += vy * dt; pz += vz * dt
	_collide(solids)

static func hypot(a: float, b: float) -> float:
	return sqrt(a * a + b * b)

func _collide(solids: Array) -> void:
	grounded = false
	var fh := FH - 0.75 * crouch_k
	for b in solids:
		if px <= b.minX - R or px >= b.maxX + R or pz <= b.minZ - R or pz >= b.maxZ + R:
			continue
		if b.bottom > 0.05:
			if py + fh <= b.bottom:
				continue
			var ceil_y: float = b.bottom - fh
			if vy > 0.0 and py - ceil_y <= 0.6 and py < b.bottom and px > b.minX - 0.15 and px < b.maxX + 0.15 and pz > b.minZ - 0.15 and pz < b.maxZ + 0.15:
				py = minf(py, ceil_y); vy = 0.0
				continue
		var pen: float = b.top - py
		if pen <= 0.0:
			continue
		if pen <= STEP:
			if vy <= 0.0:
				py = b.top; vy = 0.0; grounded = true
		else:
			var l: float = px - (b.minX - R)
			var r: float = (b.maxX + R) - px
			var n: float = pz - (b.minZ - R)
			var s: float = (b.maxZ + R) - pz
			var m := minf(minf(l, r), minf(n, s))
			if m == l:
				px = b.minX - R
				if vx > 0.0: vx = 0.0
			elif m == r:
				px = b.maxX + R
				if vx < 0.0: vx = 0.0
			elif m == n:
				pz = b.minZ - R
				if vz > 0.0: vz = 0.0
			else:
				pz = b.maxZ + R
				if vz < 0.0: vz = 0.0
