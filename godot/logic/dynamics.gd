class_name Dynamics
extends RefCounted
## Dynamic arenas: the pure deterministic functions, a line-by-line port of the DYN-PURE block in public/index.html
## (dynHash, dynRand, dynRamp, dynMapAllowed, dynResolve, dynOffset, dynDelta, dynPlan). No scene, no randomness, no globals.
## Integers are uint32 with wrap-around like Math.imul (GDScript ints are 64-bit: everything is masked with U32).
## Parity with the JS is checked by tools/test-godot-dynamics.js (hashes exact, floats within 1e-9). See docs/DYNAMICS.md.

const KINDS := ["off", "random", "wobble", "tilt", "quake", "drift"]
const NAMES := {"off": "Steady", "random": "Random", "wobble": "Wobble", "tilt": "Tilt", "quake": "Quake", "drift": "Drift"}
const RAMP := 4.0                                       ## seconds: everything eases in from 0
const WOB_A := 0.3
const WOB_P := 6.0
const TILT_A := 0.5
const TILT_P := 12.0
const TILT_ROT := 40.0
const Q_FIRST := 12.0
const Q_SLOT := 15.0
const Q_JIT := 3.0
const Q_SHAKE := 1.5
const Q_DROP := 0.6
const Q_DOWN := 3.0
const Q_RISE := 1.2
const Q_DEPTH := 30.0
const Q_JA := 0.05
const Q_HZ := 9.0
const Q_HOLE := 0.4
const DRIFT_A := 2.0
const DRIFT_P := 10.0
const DRIFT_PV := 4.0
const U32 := 0xFFFFFFFF

## Math.imul, as uint32: the low 32 bits of a * b (split so the 64-bit product never overflows).
static func imul(a: int, b: int) -> int:
	a &= U32; b &= U32
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) * b) & 0xFFFF
	return (lo + (hi << 16)) & U32

static func hash32(seed: int, a: int, b: int, c: int) -> int:   ## dynHash -> uint32
	var h := (seed & U32) ^ imul(a, 0x27d4eb2d) ^ imul(b, 0x165667b1) ^ imul(c, 0x9e3779b1)
	h = imul(h ^ (h >> 16), 0x85ebca6b)
	h = imul(h ^ (h >> 13), 0xc2b2ae35)
	return (h ^ (h >> 16)) & U32

static func rand(seed: int, a: int, b: int, c: int) -> float:   ## dynRand: [0, 1)
	return float(hash32(seed, a, b, c)) / 4294967296.0

static func ramp(t: float) -> float:
	if t <= 0.0: return 0.0
	if t >= RAMP: return 1.0
	var x := t / RAMP
	return x * x * (3.0 - 2.0 * x)

static func map_allowed(id: String, m: Dictionary) -> bool:
	return not m.is_empty() and not m.get("noDynamics", false) and not m.get("shrinks", false) and not m.get("range", false) \
		and not m.get("randSpawn", false) and not ["custom", "test", "practice", "pillars"].has(id)

## The kind that actually runs on this map ('random' picks one from the seed).
static func resolve(kind: String, seed: int, can_tile: bool, can_drift: bool) -> String:
	if not KINDS.has(kind) or kind == "off": return "off"
	if kind == "random":
		var list: Array = ["wobble", "tilt", "quake"] if can_tile else []
		if can_drift: list.append("drift")
		return list[hash32(seed, 7, 0, 0) % list.size()] if list.size() > 0 else "off"
	if kind == "drift": return "drift" if can_drift else "off"
	return kind if can_tile else "off"

## Vertical offset (m) of floor tile (ix, iz) in an nx * nz grid at match time t (s).
## mask: bit 1 = anchored (never moves), bit 2 = never becomes a hole.
static func offset(kind: String, seed: int, t: float, ix: int, iz: int, nx: int, nz: int, mask: int) -> float:
	if (mask & 1) or not (t > 0.0): return 0.0
	var r := ramp(t)
	var u := (ix + 0.5) / nx - 0.5
	var v := (iz + 0.5) / nz - 0.5
	if kind == "wobble":
		var th := rand(seed, 1, 0, 0) * TAU
		return WOB_A * r * sin(TAU * (t / WOB_P - (u * cos(th) + v * sin(th))))
	if kind == "tilt":
		var dir := 1.0 if hash32(seed, 1, 1, 0) & 1 else -1.0
		var ph := rand(seed, 1, 0, 0) * TAU + dir * TAU * t / TILT_ROT
		var h := 2.0 * (u * cos(ph) + v * sin(ph))
		return TILT_A * r * sin(TAU * t / TILT_P) * maxf(-1.0, minf(1.0, h))
	if kind == "quake":
		if t < Q_FIRST: return 0.0
		var k := int(floor((t - Q_FIRST) / Q_SLOT))
		var lt := t - (Q_FIRST + k * Q_SLOT + Q_JIT * rand(seed, 2, k, 0))
		if lt < 0.0 or lt >= Q_SHAKE + Q_DROP + Q_DOWN + Q_RISE: return 0.0
		var rx := int(floor(rand(seed, 3, k, 0) * nx))
		var rz := int(floor(rand(seed, 3, k, 1) * nz))
		var dx := ix - rx
		var dz := iz - rz
		if dx * dx + dz * dz > 2: return 0.0
		if lt < Q_SHAKE: return Q_JA * sin(TAU * (Q_HZ * lt + rand(seed, 5, ix, iz))) * sin(PI * lt / Q_SHAKE)
		if (mask & 2) or rand(seed, 4, k, ix * 4096 + iz) >= Q_HOLE: return 0.0
		var q := lt - Q_SHAKE
		if q < Q_DROP:
			var x := q / Q_DROP
			return -Q_DEPTH * x * x
		q -= Q_DROP
		if q < Q_DOWN: return -Q_DEPTH
		var x2 := (q - Q_DOWN) / Q_RISE
		return -Q_DEPTH * (1.0 - x2) * (1.0 - x2)
	return 0.0

## Drift: signed slide (m) of drifting block number bi (its index in plan.drift) along its axis.
static func delta(seed: int, t: float, bi: int) -> float:
	if not (t > 0.0): return 0.0
	var p := DRIFT_P + DRIFT_PV * rand(seed, 6, bi, 0)
	var dir := 1.0 if hash32(seed, 6, bi, 1) & 1 else -1.0
	return dir * DRIFT_A * ramp(t) * sin(2.0 * PI * t / p)

static func _ov(a0: float, a1: float, b0: float, b1: float, m: float) -> bool:
	return a0 < b1 - m and b0 < a1 - m

static func _near(solids: Array, fi: int, j: int, x0: float, x1: float, z0: float, z1: float) -> bool:
	for k in solids.size():
		var o: Dictionary = solids[k]
		if k != fi and k != j and _ov(x0, x1, o.minX, o.maxX, 0.0) and _ov(z0, z1, o.minZ, o.maxZ, 0.0): return true
	return false

static func _jsround(x: float) -> int:   ## Math.round
	return int(floor(x + 0.5))

## The static plan for a map, from collision data only: solids [{minX,maxX,minZ,maxZ,top,bottom}] in load order,
## ladders [{x,z}], pads [{x,z,r}], spawns [[x,z,y?]]. -> {floor, nx, nz, mask[], free, canTile, drift[{i, axis}]}
static func plan(solids: Array, ladders: Array, pads: Array, spawns: Array) -> Dictionary:
	var p := {"floor": -1, "nx": 0, "nz": 0, "mask": [], "free": 0, "canTile": false, "drift": []}
	var big: Array = []
	var slabs: Array = []
	for i in solids.size():
		var s: Dictionary = solids[i]
		var w: float = s.maxX - s.minX
		var d: float = s.maxZ - s.minZ
		if s.bottom < -0.5 and s.top <= 0.05 and s.top >= -0.6 and w * d >= 30.0: slabs.append(i)
		if s.bottom < -0.5 and absf(s.top) < 0.05 and w >= 12.0 and d >= 12.0: big.append(i)
	if big.size() != 1 or slabs.size() != 1: return p
	var fi: int = big[0]
	var F: Dictionary = solids[fi]
	var nx := maxi(4, mini(12, _jsround((F.maxX - F.minX) / 4.0)))
	var nz := maxi(4, mini(12, _jsround((F.maxZ - F.minZ) / 4.0)))
	var tw: float = (F.maxX - F.minX) / nx
	var td: float = (F.maxZ - F.minZ) / nz
	p["floor"] = fi; p["nx"] = nx; p["nz"] = nz
	var masks: Array = p["mask"]
	for iz in nz:
		for ix in nx:
			var x0: float = F.minX + ix * tw
			var x1 := x0 + tw
			var z0: float = F.minZ + iz * td
			var z1 := z0 + td
			var mask := 0
			for i in solids.size():
				var s: Dictionary = solids[i]
				if i != fi and s.bottom <= 0.05 and s.top > -0.05 and _ov(x0, x1, s.minX, s.maxX, 0.01) and _ov(z0, z1, s.minZ, s.maxZ, 0.01): mask |= 1
			for l: Dictionary in ladders:
				if l.x > x0 - 0.8 and l.x < x1 + 0.8 and l.z > z0 - 0.8 and l.z < z1 + 0.8: mask |= 1
			for q: Dictionary in pads:
				if q.x > x0 - q.r - 0.3 and q.x < x1 + q.r + 0.3 and q.z > z0 - q.r - 0.3 and q.z < z1 + q.r + 0.3: mask |= 1
			for sp: Array in spawns:
				if float(sp[0]) > x0 - 1.2 and float(sp[0]) < x1 + 1.2 and float(sp[1]) > z0 - 1.2 and float(sp[1]) < z1 + 1.2: mask |= 2
			if mask & 1: mask |= 2
			masks.append(mask)
			if not (mask & 1): p["free"] += 1
	p["canTile"] = p["free"] >= 0.3 * nx * nz
	var drift: Array = p["drift"]
	for j in solids.size():
		if j == fi or drift.size() >= 12: continue
		var s: Dictionary = solids[j]
		var w: float = s.maxX - s.minX
		var d: float = s.maxZ - s.minZ
		if w > 10.0 or d > 10.0 or s.top < 0.6 or s.top > 8.0 or s.bottom < -0.05: continue
		if _near(solids, fi, j, s.minX - 0.3, s.maxX + 0.3, s.minZ - 0.3, s.maxZ + 0.3): continue
		var bad := false
		for l: Dictionary in ladders:
			if l.x > s.minX - 1.0 and l.x < s.maxX + 1.0 and l.z > s.minZ - 1.0 and l.z < s.maxZ + 1.0: bad = true; break
		if bad: continue
		for q: Dictionary in pads:
			if q.x > s.minX - q.r - 0.5 and q.x < s.maxX + q.r + 0.5 and q.z > s.minZ - q.r - 0.5 and q.z < s.maxZ + q.r + 0.5: bad = true; break
		if bad: continue
		for sp: Array in spawns:
			if float(sp[0]) > s.minX - 1.0 and float(sp[0]) < s.maxX + 1.0 and float(sp[1]) > s.minZ - 1.0 and float(sp[1]) < s.maxZ + 1.0: bad = true; break
		if bad: continue
		var M := DRIFT_A + 1.2
		for axis: String in (["z", "x"] if (j & 1) else ["x", "z"]):
			var x0: float = s.minX - (M if axis == "x" else 0.0)
			var x1: float = s.maxX + (M if axis == "x" else 0.0)
			var z0: float = s.minZ - (M if axis == "z" else 0.0)
			var z1: float = s.maxZ + (M if axis == "z" else 0.0)
			if x0 < F.minX + 0.5 or x1 > F.maxX - 0.5 or z0 < F.minZ + 0.5 or z1 > F.maxZ - 0.5: continue
			if _near(solids, fi, j, x0, x1, z0, z1): continue
			var sp_in := false
			for sp: Array in spawns:
				if float(sp[0]) > x0 - 0.5 and float(sp[0]) < x1 + 0.5 and float(sp[1]) > z0 - 0.5 and float(sp[1]) < z1 + 0.5: sp_in = true; break
			if sp_in: continue
			drift.append({"i": j, "axis": axis})
			break
	return p
