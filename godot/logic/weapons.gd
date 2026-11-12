class_name Weapons
extends RefCounted
## Ranged weapons, ported 1:1 from the web game. One helper per `type` in shared/weapons.json; see docs/COMBAT_PORTING.md
## for the pattern and the list of what is still to port. Ported so far:
##   gun (hitscan, plain style: smg/ak/uzi*/sniper/revolver/mammoth/shotgun*)  -> fire_gun   (*: see TODOs)
##   knife (thrown, straight flight)                                         -> throw_knife / release_knife
##   projectile flight + hit test for knife-like projectiles (knives[] in JS)  -> step_projectiles
## Effects go to combat.events; randomness comes from combat.rng in the web game's Math.random order.

## Thrown weapons: wind-up starters (PROJ in the web game) and the release that runs when the wind-up ends.
const LAUNCH := {"knife": "throw_knife"}
const RELEASE := {"knife": "release_knife"}

## One flying projectile (an entry of `knives` in the web game; boomerang `ty` fields are kept for later).
class Proj:
	extends RefCounted
	var key := ""
	var w := {}
	var owner: FighterState = null
	var px := 0.0
	var py := 0.0
	var pz := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var age := 0.0
	var stuck := 0.0
	var grav := 3.0                ## undefined grav in JS = 3
	var homing := false            ## k.home set
	var hx := 0.0
	var hy := 0.0
	var hz := 0.0
	var turn := 0.0
	var pierce := false
	var hit_set := {}
	var gone := false

var _combat: WeakRef              ## weak: Combat owns this object (no reference cycle)
var combat: Combat:
	get: return _combat.get_ref()
var projectiles: Array = []

func _init(c: Combat) -> void:
	_combat = weakref(c)

# ============================== generic input ==============================

## The fire button with a non-melee weapon (playerControl / botThink). Returns true if something was fired.
## Bots add random extra cooldown in the web game (botThink); that belongs to the bot port.
func try_fire(f: FighterState, aim_point: Array = []) -> bool:
	var w := combat.wdata(f.weapon)
	var t: String = w.get("type", "")
	if f.dead or f.down_t > 0.0:
		return false
	if t == "gun":
		var gs: Variant = f.current_slot()
		if gs != null and w.get("mag", 0) and int(gs["mag"]) >= 0 and not combat.inf:
			if int(gs["mag"]) <= 0 and int(gs["ammo"]) > 0 and not f.reloading: combat.start_reload(f)   # trigger on an empty gun
		if f.cool > 0.0 or f.swing >= 0.0 or f.reloading: return false
		f.cool = float(w["cooldown"]); fire_gun(f, f.weapon, aim_point); combat.use_ammo(f)
		return true
	if LAUNCH.has(t):
		if f.cool > 0.0 or f.swing >= 0.0: return false
		f.cool = float(w["cooldown"]); call(LAUNCH[t], f, f.weapon); combat.use_ammo(f)
		return true
	push_warning("Weapons.try_fire: type '%s' not ported yet" % t)
	return false

## Called by Combat.timers when a thrown weapon's wind-up ends.
func release(f: FighterState, key: String) -> void:
	var t: String = combat.wdata(key).get("type", "")
	if RELEASE.has(t): call(RELEASE[t], f, key)

# ============================== geometry ==============================

## Ray vs every solid box (the web game raycasts the box meshes; front faces only, so a ray starting inside a box
## does not hit it). Returns the distance to the first wall, or -1.
func ray_walls(ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, far: float) -> float:
	var best := -1.0
	for b in combat.solids:
		var t := ray_box(ox, oy, oz, dx, dy, dz, b.minX, b.bottom, b.minZ, b.maxX, b.top, b.maxZ)
		if t >= 0.0 and t <= far and (best < 0.0 or t < best): best = t
	return best

## Slab test; -1 = miss or origin inside the box.
static func ray_box(ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> float:
	var tmin := -INF
	var tmax := INF
	var o := [ox, oy, oz]
	var d := [dx, dy, dz]
	var lo := [x0, y0, z0]
	var hi := [x1, y1, z1]
	for a in 3:
		if d[a] == 0.0:
			if o[a] < lo[a] or o[a] > hi[a]: return -1.0
			continue
		var inv: float = 1.0 / d[a]
		var t1: float = (lo[a] - o[a]) * inv
		var t2: float = (hi[a] - o[a]) * inv
		if t1 > t2: var tt := t1; t1 = t2; t2 = tt
		if t1 > tmin: tmin = t1
		if t2 < tmax: tmax = t2
		if tmin > tmax: return -1.0
	if tmax < 0.0 or tmin < 0.0: return -1.0
	return tmin

## raySphere: distance along a unit ray to a sphere, 0 if starting inside, -1 = miss.
static func ray_sphere(ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, cx: float, cy: float, cz: float, r: float) -> float:
	var px := ox - cx
	var py := oy - cy
	var pz := oz - cz
	var b := px * dx + py * dy + pz * dz
	var cc := px * px + py * py + pz * pz - r * r
	var disc := b * b - cc
	if disc < 0.0: return -1.0
	var sq := sqrt(disc)
	var t := -b - sq
	if t >= 0.0: return t
	return 0.0 if (-b + sq) >= 0.0 else -1.0

## clampToWalls: a muzzle poking through a wall must not start the shot on the other side of it.
func clamp_to_walls(f: FighterState, o: Array) -> Array:
	var cx: float = o[0] - f.shoulder_x
	var cy: float = o[1] - f.shoulder_y
	var cz: float = o[2] - f.shoulder_z
	var dl := sqrt(cx * cx + cy * cy + cz * cz)
	if dl < 0.05: return o
	var inv := 1.0 / dl
	cx *= inv; cy *= inv; cz *= inv
	var t := ray_walls(f.shoulder_x, f.shoulder_y, f.shoulder_z, cx, cy, cz, dl)
	if t >= 0.0:
		var s := maxf(0.0, t - 0.03)
		return [f.shoulder_x + cx * s, f.shoulder_y + cy * s, f.shoulder_z + cz * s]
	return o

## aimFromHand: the player's shots go to the crosshair point (aim_point); bots use the arm target.
func aim_from_hand(f: FighterState, from: Array, aim_point: Array) -> Array:
	if f.is_player and aim_point.size() == 3:
		var ox: float = aim_point[0] - from[0]
		var oy: float = aim_point[1] - from[1]
		var oz: float = aim_point[2] - from[2]
		if ox * ox + oy * oy + oz * oz > 0.09: return Combat.norm3(ox, oy, oz)
	return Combat.norm3(f.aim_x, f.aim_y, f.aim_z)

# ============================== guns ==============================

const UZI_SIDE := 0.66          ## how far apart the two Uzis are held

## shotSpread: the shotgun is wide from the hip and tight when aimed (the on-screen circle is only the HUD).
static func shot_spread(w: Dictionary, aim: float) -> float:
	var sp := float(w["spread"]) if w.has("spread") else 0.012
	if w.get("adsMul", 0): sp *= Combat.lerp_js(1.0, float(w["adsMul"]), Combat.clampf_js(aim, 0.0, 1.0))
	return sp

## arm.quaternion applied to (1,0,0): "the shooter's left". The web game builds the quaternion in Fighter.animate
## (setFromUnitVectors(DOWN, armDir), then rolls guns upright about the aim line); the visual layer may overwrite
## `arm_right` later, until then it is derived from the arm direction exactly like the JS.
static func arm_right(f: FighterState) -> Array:
	var dx := f.arm_x
	var dy := f.arm_y
	var dz := f.arm_z
	# Quaternion.setFromUnitVectors(from = (0,-1,0), to = d)
	var r := -dy + 1.0
	var qx := 0.0
	var qy := 0.0
	var qz := 0.0
	var qw := 0.0
	if r < 1e-8:               # pointing straight up (opposite of DOWN): three.js picks the axis (0, -from.z, from.y)
		qx = 0.0; qy = 0.0; qz = -1.0; qw = 0.0
	else:
		qx = -1.0 * dz - 0.0 * dy
		qy = 0.0 * dx - 0.0 * dz
		qz = 0.0 * dy - -1.0 * dx
		qw = r
	var ql := sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if ql != 0.0:
		var il := 1.0 / ql
		qx *= il; qy *= il; qz *= il; qw *= il
	if f.slot >= 0 and ROLL_KEYS.has(f.weapon) and not f.dead:
		var zx := 2.0 * (qx * qz + qw * qy)
		var zy := 2.0 * (qy * qz - qw * qx)
		var zz := 1.0 - 2.0 * (qx * qx + qy * qy)
		var ux := -dy * dx
		var uy := 1.0 - dy * dy
		var uz := -dy * dz
		var ul := sqrt(ux * ux + uy * uy + uz * uz)
		if ul > 0.15:
			ux /= ul; uy /= ul; uz /= ul
			var ang := atan2((zy * uz - zz * uy) * dx + (zz * ux - zx * uz) * dy + (zx * uy - zy * ux) * dz, zx * ux + zy * uy + zz * uz)
			var sn := sin(ang / 2.0)
			var rx := dx * sn
			var ry := dy * sn
			var rz := dz * sn
			var rw := cos(ang / 2.0)
			var nx := rw * qx + rx * qw + ry * qz - rz * qy
			var ny := rw * qy - rx * qz + ry * qw + rz * qx
			var nz := rw * qz + rx * qy - ry * qx + rz * qw
			var nw := rw * qw - rx * qx - ry * qy - rz * qz
			qx = nx; qy = ny; qz = nz; qw = nw
	# Vector3(1,0,0).applyQuaternion(q), three.js operation order (q is not unit after the roll when the arm is not)
	var ix := qw * 1.0 + qy * 0.0 - qz * 0.0
	var iy := qw * 0.0 + qz * 1.0 - qx * 0.0
	var iz := qw * 0.0 + qx * 0.0 - qy * 1.0
	var iw := -qx * 1.0 - qy * 0.0 - qz * 0.0
	return [ix * qw + iw * -qx + iy * -qz - iz * -qy, iy * qw + iw * -qy + iz * -qx - ix * -qz, iz * qw + iw * -qz + ix * -qy - iy * -qx]

## GUN_KEYS in the web game: guns are rolled upright about the aim line.
const ROLL_KEYS := ["net", "shotgun", "sniper", "ak", "smg", "uzi", "minigun", "revolver", "mammoth", "flame", "rocket", "glauncher", "cluster"]

## playerControl's gun lines: reload on an empty trigger, minigun spin-up, fire. `held` = fire button.
func gun_tick(f: FighterState, held: bool, dt: float, aim_point: Array = []) -> void:
	var w := combat.wdata(f.weapon)
	var gs: Variant = f.current_slot()
	if gs != null and w.get("mag", 0) and int(gs["mag"]) >= 0 and not combat.inf:
		if int(gs["mag"]) <= 0 and int(gs["ammo"]) > 0 and not f.reloading: combat.start_reload(f)
	var spinup := float(w.get("spinup", 0.0))
	if spinup != 0.0: f.spin = minf(spinup, f.spin + dt) if held else maxf(0.0, f.spin - dt * 2.0)
	if held and f.cool <= 0.0 and f.swing < 0.0 and not f.reloading and (spinup == 0.0 or f.spin >= spinup):
		f.cool = float(w["cooldown"]); fire_gun(f, f.weapon, aim_point); combat.use_ammo(f)

## Fighter.fireGun for the plain hitscan style. `aim_point` = the crosshair point for the player ([] for bots).
## Not ported yet: style 'flame'. Spring glove ('punch'), shotgun pellet circle and dual Uzis are ported.
func fire_gun(f: FighterState, key: String, aim_point: Array = []) -> void:
	var w := combat.wdata(key)
	var giant := combat.giant
	if w.get("style", "") == "flame":
		push_warning("Weapons.fire_gun: style 'flame' not ported yet"); return   # TODO(next batch): flame cone + burn
	# barrelDir
	var bx := f.arm_x
	var by := f.arm_y
	var bz := f.arm_z
	if f.hip_d != 0.0:
		var hl := sqrt(bx * bx + bz * bz)
		if hl == 0.0: hl = 1.0
		var np := asin(Combat.clampf_js(by, -1.0, 1.0)) + f.hip_d
		var nx := bx / hl * cos(np)
		var ny := sin(np)
		bz = bz / hl * cos(np); bx = nx; by = ny
	var muz := float(w.get("muzzle", 0.0)) * (2.4 if giant else 1.0)
	var o := clamp_to_walls(f, [f.hand_x + bx * muz, f.hand_y + by * muz, f.hand_z + bz * muz])
	if w.get("lift", 0):
		var lift := float(w["lift"])
		var ul := sqrt((bx * by) * (bx * by) + (1.0 - by * by) * (1.0 - by * by) + (bz * by) * (bz * by))
		if ul == 0.0: ul = 1.0
		o[0] += -by * bx / ul * lift; o[1] += (1.0 - by * by) / ul * lift; o[2] += -by * bz / ul * lift
	if f.is_player and aim_point.size() == 3:   # a target right in front: shoot from the hand
		var ex: float = aim_point[0] - f.hand_x
		var ey: float = aim_point[1] - f.hand_y
		var ez: float = aim_point[2] - f.hand_z
		var dd := sqrt(ex * ex + ey * ey + ez * ez)
		if dd < float(w.get("muzzle", 0.0)) + 1.2 and dd > 0.05: o = [f.hand_x, f.hand_y, f.hand_z]
	if w.get("dual", false):               # dual Uzis: shots come out of each gun in turn
		f.uzi_side ^= 1; f.uzi_k[f.uzi_side] = 1.0
		if f.uzi_side != 0:
			var ax := arm_right(f)
			o[0] += ax[0] * UZI_SIDE; o[1] += ax[1] * UZI_SIDE; o[2] += ax[2] * UZI_SIDE
	var n := int(w.get("pellets", 1)) if w.get("pellets", 0) else 1
	var sp := float(w["spread"]) if w.has("spread") else 0.012
	if w.get("adsMul", 0):
		sp = shot_spread(w, f.ads if f.is_player else 0.0)
	elif f.is_player and f.ads > 0.5:
		sp *= 0.45
	var victims := {}                  # FighterState -> {dmg, force, dx, dy, dz, head}; insertion order = hit order
	var lx := bx
	var ly := by
	var lz := bz
	var base := [bx, by, bz]
	var asst := 1.0 if f.is_player else float(w.get("assist", 0.0))
	if asst != 0.0:
		var a := aim_from_hand(f, o, aim_point)
		if f.climb > 0.0: a[1] += f.climb
		a = Combat.norm3(a[0], a[1], a[2])
		base = Combat.norm3(bx + (a[0] - bx) * asst, by + (a[1] - by) * asst, bz + (a[2] - bz) * asst)
	if w.get("style", "") == "punch":
		_punch(f, w, o)
		return
	var rng: CombatRng = combat.rng
	var rng_range := float(w.get("range", 0.0))
	for i in n:
		var dx: float = base[0]
		var dy: float = base[1]
		var dz: float = base[2]
		if sp != 0.0 and w.get("adsMul", 0):   # pellets land anywhere inside the circle drawn round the crosshair
			var pa := rng.range_f(0, 6.2832)
			var pr := sqrt(rng.next()) * sp
			var rx: Array = Combat.norm3(-base[2], 0.0, base[0]) if (base[2] * base[2] + base[0] * base[0]) >= 1e-6 else [1.0, 0.0, 0.0]
			var ry := [rx[1] * base[2] - rx[2] * base[1], rx[2] * base[0] - rx[0] * base[2], rx[0] * base[1] - rx[1] * base[0]]
			var cs := cos(pa) * pr
			var sn := sin(pa) * pr
			dx += rx[0] * cs; dy += rx[1] * cs; dz += rx[2] * cs
			dx += ry[0] * sn; dy += ry[1] * sn; dz += ry[2] * sn
		elif sp != 0.0:
			dx += rng.range_f(-sp, sp); dy += rng.range_f(-sp, sp); dz += rng.range_f(-sp, sp)
		var d := Combat.norm3(dx, dy, dz)
		dx = d[0]; dy = d[1]; dz = d[2]
		lx = dx; ly = dy; lz = dz
		var best_t := rng_range
		var victim: FighterState = null
		var head := false
		var wt := ray_walls(o[0], o[1], o[2], dx, dy, dz, rng_range)
		if wt >= 0.0: best_t = wt
		for e: FighterState in combat.fighters:
			if e == f or e.dead: continue
			for s: Array in e.spheres(giant):
				var t := ray_sphere(o[0], o[1], o[2], dx, dy, dz, s[0], s[1], s[2], s[3])
				if t >= 0.0 and t < best_t: best_t = t; victim = e; head = s[4]
		if victim != null:
			var rec: Dictionary = victims.get(victim, {"dmg": 0.0, "force": 0.0, "dx": 0.0, "dy": 0.0, "dz": 0.0, "head": false})
			var fo := 1.0
			if w.has("falloff"):
				var fl: Array = w["falloff"]
				fo = Combat.lerp_js(1.0, fl[2], Combat.clampf_js((best_t - fl[0]) / (fl[1] - fl[0]), 0.0, 1.0))
			var hm := (float(w.get("headMul", 2.0)) if w.get("headMul", 0) else 2.0) if head else 1.0
			rec["dmg"] += float(w["dmg"]) * f.dmg_scale * hm * fo
			rec["force"] += float(w["force"]) * (0.45 + 0.55 * fo)
			rec["dx"] += dx; rec["dy"] += dy; rec["dz"] += dz
			rec["head"] = rec["head"] or head
			victims[victim] = rec
		combat.ev({"type": "tracer", "f": f, "key": key, "ox": o[0], "oy": o[1], "oz": o[2],
			"ex": o[0] + dx * best_t, "ey": o[1] + dy * best_t, "ez": o[2] + dz * best_t, "hit": victim != null})
	var max_force := float(w.get("maxForce", 20.0)) if w.get("maxForce", 0) else 20.0
	for v: FighterState in victims:
		var rec: Dictionary = victims[v]
		var rd := Combat.norm3(rec["dx"], rec["dy"], rec["dz"])
		combat.hit(v, rec["dmg"], rd[0], rd[1], rd[2], minf(rec["force"], max_force), rec["head"], f)
		if rec["head"] and key == "mammoth" and not v.dead:   # a Mammoth headshot snaps their head back
			var s_ := sin(v.yaw)
			var c_ := cos(v.yaw)
			var d_f: float = rd[0] * s_ + rd[2] * c_
			var d_r: float = -rd[0] * c_ + rd[2] * s_
			combat.kick_head(v, -d_f * 11.0, -d_r * 11.0); combat.kick_lean(v, -d_f * 6.0, -d_r * 6.0)
			v.phys.vx += rd[0] * 7.0; v.phys.vz += rd[2] * 7.0; v.phys.vy += 3.5; v.stun = maxf(v.stun, 0.8)
		var tp := float(w.get("topple", 0.0))
		if tp and rng.next() < tp: combat.topple(v, 1.0)
	# recoil kicks the arm up and back and rocks the body
	var rc := float(w.get("recoil", 1.0)) if w.get("recoil", 0) else 1.0
	if w.get("climb", 0):
		f.climb = minf(float(w["climbMax"]), f.climb + float(w["climb"])); f.climb_back = float(w["climbBack"]); f.last_shot_t = combat.time
	var ay := (1.5 + rng.range_f(0, 0.8)) * rc
	var ax := rng.range_f(-0.9, 0.9) * rc
	var az := rng.range_f(-0.9, 0.9) * rc
	combat.push_arm(f, 0.0, ay, 0.0); combat.push_arm(f, ax, 0.0, 0.0); combat.push_arm(f, 0.0, 0.0, az)
	var s8 := -0.8 * rc
	combat.push_arm(f, lx * s8, ly * s8, lz * s8)
	var la := -0.9 * rc
	combat.kick_lean(f, la, rng.range_f(-0.4, 0.4) * rc)
	if w.get("hop", 0):
		var hl2 := sqrt(lx * lx + lz * lz)
		if hl2 == 0.0: hl2 = 1.0
		var kb := float(w["kickback"])
		f.phys.vx -= lx / hl2 * kb; f.phys.vz -= lz / hl2 * kb
		f.phys.vy = maxf(f.phys.vy, float(w["hop"])); f.phys.grounded = false
	elif w.get("kickback", 0):
		var kb2 := float(w["kickback"])
		f.phys.vx -= lx * kb2; f.phys.vz -= lz * kb2
	combat.ev({"type": "shot", "f": f, "key": key})

## fireGun style 'punch' (Spring Glove): a big springy fist that hits whoever is roughly in front of it.
func _punch(f: FighterState, w: Dictionary, o: Array) -> void:
	var best: FighterState = null
	var best_score := -1.0
	var rng_range := float(w["range"])
	var adx := f.arm_x
	var ady := f.arm_y
	var adz := f.arm_z
	for e: FighterState in combat.fighters:
		if e == f or e.dead: continue
		var cx := e.chest_x - f.hand_x
		var cy := e.chest_y - f.hand_y
		var cz := e.chest_z - f.hand_z
		var d := sqrt(cx * cx + cy * cy + cz * cz)
		if d > rng_range or d < 0.05: continue
		var inv := 1.0 / d
		var cs := (cx * inv) * adx + (cy * inv) * ady + (cz * inv) * adz
		if cs < 0.82 and d > 1.8: continue          # within ~35 degrees (anyone really close counts too)
		if not has_los(f, e): continue
		var score := cs + (1.0 - d / rng_range) * 0.6
		if score > best_score: best_score = score; best = e
	var ex: float = o[0] + adx * (rng_range * 0.5)
	var ey: float = o[1] + ady * (rng_range * 0.5)
	var ez: float = o[2] + adz * (rng_range * 0.5)
	if best != null: ex = best.chest_x; ey = best.chest_y; ez = best.chest_z
	combat.ev({"type": "tracer", "f": f, "key": f.weapon, "ox": o[0], "oy": o[1], "oz": o[2], "ex": ex, "ey": ey, "ez": ez, "hit": best != null, "punch": true})
	if best != null:
		var dd := Combat.norm3(best.chest_x - f.hand_x, best.chest_y - f.hand_y, best.chest_z - f.hand_z)
		var dn := Combat.norm3(dd[0], dd[1] + 0.25, dd[2])
		var fm := 2.1 if (combat.giant and f.weapon == "glove") else 1.0
		combat.hit(best, float(w["dmg"]) * f.dmg_scale, dn[0], dn[1], dn[2], float(w["force"]) * fm, false, f)
		if combat.rng.next() < float(w.get("topple", 0.0)): combat.topple(best, 1.0)
	combat.push_arm(f, adx * 4.0, ady * 4.0, adz * 4.0); combat.kick_lean(f, -1.6, 0.0)
	combat.ev({"type": "sfx", "name": "whack", "f": f})

## hasLOS: nothing solid between the shooter's shoulder and the target's chest.
func has_los(b: FighterState, tg: FighterState) -> bool:
	var cx := tg.chest_x - b.shoulder_x
	var cy := tg.chest_y - b.shoulder_y
	var cz := tg.chest_z - b.shoulder_z
	var d := sqrt(cx * cx + cy * cy + cz * cz)
	if d < 0.1: return true
	var inv := 1.0 / d
	return ray_walls(b.shoulder_x, b.shoulder_y, b.shoulder_z, cx * inv, cy * inv, cz * inv, d) < 0.0

## Recoil climb settles once you stop shooting (from Fighter.animate in the web game).
func climb_tick(f: FighterState, dt: float) -> void:
	if combat.time - f.last_shot_t > 0.1: f.climb = maxf(0.0, f.climb - f.climb_back * dt)

# ============================== thrown: knife ==============================

## throwKnife: wind the arm back; Combat.timers calls release_knife 0.11 s later.
func throw_knife(f: FighterState, key: String) -> void:
	if f.throw_key != "": return
	f.throw_t = 0.0; f.thrown = false; f.throw_key = key
	combat.kick_lean(f, 0.9, 0.0); combat.push_arm(f, 0.0, 2.5, 0.0)
	combat.ev({"type": "sfx", "name": "swing", "f": f})

func release_knife(f: FighterState, key: String) -> void:
	var w := combat.wdata(key)
	var d := Combat.norm3(f.aim_x, f.aim_y, f.aim_z)
	var o := [f.shoulder_x + d[0] * 0.9, f.shoulder_y + d[1] * 0.9, f.shoulder_z + d[2] * 0.9]
	o[1] += 0.25
	o = clamp_to_walls(f, o)
	var k := Proj.new()
	k.key = key; k.w = w; k.owner = f
	k.px = o[0]; k.py = o[1]; k.pz = o[2]
	var spd := float(w["speed"])
	k.vx = d[0] * spd; k.vy = d[1] * spd; k.vz = d[2] * spd
	projectiles.append(k)
	combat.push_arm(f, d[0] * 5.0, d[1] * 5.0, d[2] * 5.0); combat.kick_lean(f, -2.4, combat.rng.range_f(-0.3, 0.3))
	f.knife_t = 0.0; f.twirl_len = 1.4
	combat.ev({"type": "projectile", "p": k})

## updateKnives: 4 sub-steps per call so a fast knife can't skip through a head. Boomerang-style return (`ty`) is
## not ported yet. Removed projectiles get gone = true and a "projectile_end" event.
func step_projectiles(dt: float) -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var k: Proj = projectiles[i]
		i -= 1
		k.age += dt
		if k.stuck > 0.0:
			k.stuck -= dt
			if k.stuck <= 0.0: _remove(k)
			continue
		var gone := false
		var N := 4
		var h := dt / N
		for sub in N:
			if gone or k.stuck > 0.0: break
			if k.homing:               # curving throw: steer toward the target point
				var ex := k.hx - k.px
				var ey := k.hy - k.py
				var ez := k.hz - k.pz
				var dd := sqrt(ex * ex + ey * ey + ez * ez)
				if dd < 1.2 or k.age > 1.4: k.homing = false
				else:
					var spd := sqrt(k.vx * k.vx + k.vy * k.vy + k.vz * k.vz)
					var inv := 1.0 / dd
					ex *= inv; ey *= inv; ez *= inv
					var is_ := 1.0 / spd
					var ux := k.vx * is_
					var uy := k.vy * is_
					var uz := k.vz * is_
					var al := minf(1.0, k.turn * (3.0 if dd < 16.0 else 1.6) * h)
					var nv := Combat.norm3(ux + (ex - ux) * al, uy + (ey - uy) * al, uz + (ez - uz) * al)
					k.vx = nv[0] * spd; k.vy = nv[1] * spd; k.vz = nv[2] * spd
			k.vy -= k.grav * h
			k.px += k.vx * h; k.py += k.vy * h; k.pz += k.vz * h
			if _in_solid(k.px, k.py, k.pz, 0.05):
				k.stuck = 1.6
				combat.ev({"type": "sfx", "name": "clink", "x": k.px, "y": k.py, "z": k.pz})
				break
			for f: FighterState in combat.fighters:
				if f.dead or (f == k.owner and k.age < 0.25) or k.hit_set.has(f): continue
				for s: Array in f.spheres(combat.giant):
					var dx: float = k.px - s[0]
					var dy: float = k.py - s[1]
					var dz: float = k.pz - s[2]
					var rr: float = s[3] + (0.4 if k.homing else 0.1)
					if dx * dx + dy * dy + dz * dz < rr * rr:
						var hd: bool = s[4]
						var vd := Combat.norm3(k.vx, k.vy, k.vz)
						var ds := k.owner.dmg_scale if k.owner != null else 1.0
						combat.hit(f, float(k.w["dmg"]) * ds * (1.8 if hd else 1.0), vd[0], vd[1], vd[2], float(k.w["force"]), hd, k.owner)
						combat.ev({"type": "sfx", "name": "clink", "x": k.px, "y": k.py, "z": k.pz})
						if k.pierce: k.hit_set[f] = true; break
						gone = true; break
				if gone: break
		if gone or k.py < -30.0 or k.age > 4.0:
			_remove(k)

func _remove(k: Proj) -> void:
	k.gone = true
	projectiles.erase(k)
	combat.ev({"type": "projectile_end", "p": k})

func _in_solid(x: float, y: float, z: float, rad: float) -> bool:
	for b in combat.solids:
		if x > b.minX - rad and x < b.maxX + rad and z > b.minZ - rad and z < b.maxZ + rad and y - rad < b.top and y + rad > b.bottom:
			return true
	return false
