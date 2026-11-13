class_name FighterPhysics
extends RefCounted
## Movement and collision, ported 1:1 from the web game (Fighter.physics, Fighter.ladderStep, collide and the
## updatePads loop in public/index.html ~5562-5610, ~2495, ~6250).
## Uses plain 64-bit floats (not Vector3) so it stays numerically identical to the JS version.
## Solids are boxes {minX,maxX,minZ,maxZ,top,bottom}; build them with FighterPhysics.solids_from_map().
##
## Status effects live on the fighter (FighterState: dead, down_t, trap_t, stun, spd_t, dash_air_t, pad_cool), set by
## Combat; step() reads them and counts `stun` and `dash_air_t` down, exactly like Fighter.physics.

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
## Character class multipliers (shared/classes.json: spd, acc, air, jump). 1.0 = the default Wobbler.
var speed_mul := 1.0
var accel_mul := 1.0
var air_mul := 1.0
var jump_mul := 1.0
var want_jump := false
var grounded := false
var crouch_k := 0.0
var grav_scale := 1.0         ## cfg.grav
var ice_grip := false         ## maps with `grip`: slidey steering
var ice_setting := 0.6        ## settings.ice (how long you glide on ice when you let go)
var ceil_y := NAN             ## domed maps (`ceil`): the glass roof height, NAN = none

# --- ladders (Fighter.ladderStep) ---
var ladders: Array = []       ## the map's ladders {x, z, nx, nz, y0, y1} (MapNode.ladders)
var can_climb := false        ## isPlayer: only the local player grabs ladders by walking into them
var climb_in := 0.0           ## forward input while hanging on a ladder (+1 up, -1 down)
var ladder: Dictionary = {}   ## the ladder being climbed (onLadder), {} = none
var climb_t := 0.0            ## climbing animation phase (visual)

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

## Map flags that change movement (grip = ice, ceil = dome).
func set_map(map: Dictionary, map_ladders: Array) -> void:
	ice_grip = map.has("grip") and bool(map["grip"])
	ceil_y = float(map["ceil"]) if map.has("ceil") else NAN
	ladders = map_ladders

func place(x: float, y: float, z: float) -> void:
	px = x; py = y; pz = z; vx = 0.0; vy = 0.0; vz = 0.0
	ladder = {}

## Fighter.physics: one step of movement for the fighter `st` (its status effects steer the control).
func step(dt: float, solids: Array, st: FighterState) -> void:
	if ladder_step(dt, st):
		want_jump = false
		return
	var incap := st.dead or st.down_t > 0.0 or st.trap_t > 0.0
	var ctrl := 0.0 if incap else 1.0
	var spm := 1.4 if st.spd_t > 0.0 else 1.0
	var tx := wish_x * speed * speed_mul * ctrl * spm
	var tz := wish_z * speed * speed_mul * ctrl * spm
	var acc := 40.0 * accel_mul if grounded else 14.0 * air_mul
	if ice_grip and grounded and not incap:
		acc = 32.0 if hypot(wish_x, wish_z) > 0.05 else 20.0 * pow(0.05, ice_setting)
	if st.dash_air_t > 0.0:            # Pillars: a dash in the air carries you across the gap
		st.dash_air_t -= dt
		if not grounded: acc = 3.0
	if st.recover_air_t > 0.0:         # air recovery (Skills.do_recover): steer hard without losing the burst
		st.recover_air_t -= dt
		if not grounded and not incap:
			if hypot(wish_x, wish_z) < 0.05: acc = 0.0
			else:
				var cap := maxf(speed * speed_mul * spm, Skills.RECOVER_AIR_SPEED)
				tx = wish_x * cap; tz = wish_z * cap; acc = Skills.RECOVER_AIR_ACC * air_mul
	if st.down_t > 0.0: acc = 18.0     # slide along the floor a bit
	if st.stun > 0.0:
		acc *= 0.12; st.stun -= dt
	var dx := tx - vx
	var dz := tz - vz
	var length := hypot(dx, dz)
	var md := acc * dt
	if length <= md:
		vx = tx; vz = tz
	else:
		vx += dx / length * md; vz += dz / length * md

	if want_jump and grounded and not incap:
		vy = (7.4 if grav_scale < 0.3 else 9.2) * jump_mul
		grounded = false
	want_jump = false

	vy = maxf(vy - GRAV * grav_scale * dt, -22.0)
	px += vx * dt; py += vy * dt; pz += vz * dt
	if not is_nan(ceil_y):             # domed maps: the glass roof stops you drifting away
		if vy > 30.0: vy = 30.0
		if py + FH > ceil_y - 0.01:
			py = ceil_y - FH - 0.01
			if vy > 0.0: vy = 0.0
	_collide(solids)

## Fighter.ladderStep: returns true while hanging on a ladder (climb with climb_in).
func ladder_step(dt: float, st: FighterState) -> bool:
	var l: Dictionary = ladder
	if not l.is_empty() and (st.dead or st.down_t > 0.0 or st.stun > 0.05):
		ladder = {}
		return false
	if l.is_empty() and can_climb and not st.dead and st.down_t <= 0.0:
		for c: Dictionary in ladders:
			var cx: float = c["x"] + c["nx"] * 0.55
			var cz: float = c["z"] + c["nz"] * 0.55
			if absf(px - cx) < 0.8 and absf(pz - cz) < 0.8 and py > c["y0"] - 0.4 and py < c["y1"] - 0.1 \
					and -(wish_x * c["nx"] + wish_z * c["nz"]) > 0.45:
				l = c; ladder = c
				break
	if l.is_empty():
		return false
	var nx: float = l["nx"]
	var nz: float = l["nz"]
	if want_jump:
		ladder = {}; vx = nx * 4.5; vy = 6.5; vz = nz * 4.5; want_jump = false; grounded = false
		return false
	var sx: float = l["x"] + nx * 0.55
	var sz: float = l["z"] + nz * 0.55
	var k := minf(1.0, 14.0 * dt)
	px += (sx - px) * k; pz += (sz - pz) * k
	vx = 0.0; vy = 0.0; vz = 0.0; grounded = false
	py += climb_in * 4.4 * dt
	climb_t += absf(climb_in) * dt * 7.0
	if py <= l["y0"] and climb_in < 0.0:
		py = l["y0"] + 0.01; ladder = {}; grounded = true
		return false
	if py >= l["y1"]:                  # top: step off onto the platform
		py = l["y1"] + 0.03; px -= nx * 0.95; pz -= nz * 0.95; ladder = {}
		vx = -nx * 1.5; vy = 0.0; vz = -nz * 1.5
	return true

## The updatePads loop for one fighter (run after every fighter's step): returns the index of the pad that launched
## it, or -1. `pads` = MapNode.pads ({x, z, r, power}).
func bounce_pads(pads: Array, st: FighterState) -> int:
	for i in pads.size():
		if st.dead or st.pad_cool > 0.0 or vy > 1.0:
			return -1
		var pd: Dictionary = pads[i]
		var dx: float = px - pd["x"]
		var dz: float = pz - pd["z"]
		var r: float = pd["r"]
		if dx * dx + dz * dz < r * r and py < 0.7:
			vy = pd["power"]; grounded = false; st.pad_cool = 0.4
			return i
	return -1

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
			var ceil_b: float = b.bottom - fh
			if vy > 0.0 and py - ceil_b <= 0.6 and py < b.bottom and px > b.minX - 0.15 and px < b.maxX + 0.15 and pz > b.minZ - 0.15 and pz < b.maxZ + 0.15:
				py = minf(py, ceil_b); vy = 0.0
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
