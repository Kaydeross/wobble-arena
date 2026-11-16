class_name PackMapKit
extends RefCounted
## DLC pack arenas (kitchen_chaos, toy_workshop, backyard_bbq): the shared building kit, in the style of SiteMap / SiteProps.
## A prop is a Dictionary {kind, boxes, ladders, pads, zones, tops, lrect} built in its own local frame (front = +x) and put on the
## yard with place() (a multiple of 90 degrees). Boxes are plain `{x, z, w, d, h, y, color}`; while a prop is being built a box may
## also carry flags that assemble() strips again: `glow` (an emissive colour: burners, hotplates), `ei` (its energy), `skip`
## (never a platform for the navigability test: ceilings, tall pillars, the perimeter).
## Zones (PackZones) are in the same local frame: {kind: burner | ice, rect | c + r, top} and {kind: hoist, x, z, r, ...}.
## Jump rules are SiteProps': 0.55 m or less is walked, up to 2.0 m is a jump, taller needs a ladder, steps or a bounce pad.

const U32 := 0xFFFFFFFF
const FENCE_H := 2.8
const MAX_BOXES := 450          ## the owner's brief: <= 450 boxes per pack arena (the engine batching cap is 690)
const HARD_MAX := 690
const GLOW_EI := 1.5


static func r3(v: float) -> float:
	return snappedf(v, 0.001)


static func f(rnd: Callable) -> float:
	return float(rnd.call())


static func pick(rnd: Callable, list: Array) -> Variant:
	return list[mini(list.size() - 1, int(f(rnd) * float(list.size())))]


## One box (centre x, z; size w x d x h; bottom y). flags: glow (colour), ei, skip.
static func bx(o: Array, x: float, z: float, w: float, d: float, h: float, y: float, color: int, flags := {}) -> void:
	var b := {"x": r3(x), "z": r3(z), "w": r3(w), "d": r3(d), "h": r3(h), "y": r3(y), "color": color}
	for k: String in flags: b[k] = flags[k]
	o.append(b)


static func new_prop(kind: String) -> Dictionary:
	return {"kind": kind, "boxes": [], "ladders": [], "pads": [], "zones": [], "tops": []}


static func rot_xz(x: float, z: float, rot: int) -> Vector2:
	return SiteProps.rot_xz(x, z, rot)


## lrect: the boxes' footprint plus the ground in front of every ladder / pad and the whole footprint of every zone.
static func finish(p: Dictionary) -> Dictionary:
	var x0 := 1e9
	var z0 := 1e9
	var x1 := -1e9
	var z1 := -1e9
	for b: Dictionary in p["boxes"]:
		if bool(b.get("decal", false)): continue
		x0 = minf(x0, float(b["x"]) - float(b["w"]) / 2.0); x1 = maxf(x1, float(b["x"]) + float(b["w"]) / 2.0)
		z0 = minf(z0, float(b["z"]) - float(b["d"]) / 2.0); z1 = maxf(z1, float(b["z"]) + float(b["d"]) / 2.0)
	for l: Dictionary in p["ladders"]:
		var sx := float(l["x"]) + float(l["nx"]) * 0.55
		var sz := float(l["z"]) + float(l["nz"]) * 0.55
		x0 = minf(x0, sx - 1.0); x1 = maxf(x1, sx + 1.0); z0 = minf(z0, sz - 1.0); z1 = maxf(z1, sz + 1.0)
	for pd: Dictionary in p["pads"]:
		x0 = minf(x0, float(pd["x"]) - 1.6); x1 = maxf(x1, float(pd["x"]) + 1.6); z0 = minf(z0, float(pd["z"]) - 1.6); z1 = maxf(z1, float(pd["z"]) + 1.6)
	for z: Dictionary in p["zones"]:
		if str(z.get("kind", "")) == "hoist":
			var hr := float(z["r"]) + 0.3
			x0 = minf(x0, float(z["x"]) - hr); x1 = maxf(x1, float(z["x"]) + hr); z0 = minf(z0, float(z["z"]) - hr); z1 = maxf(z1, float(z["z"]) + hr)
		elif z.has("rect"):
			var r: Array = z["rect"]
			x0 = minf(x0, float(r[0])); x1 = maxf(x1, float(r[2])); z0 = minf(z0, float(r[1])); z1 = maxf(z1, float(r[3]))
	p["lrect"] = [x0, z0, x1, z1]
	return p


static func _rot_zone(z: Dictionary, x: float, zz: float, rot: int) -> Dictionary:
	var q := z.duplicate(true)
	if z.has("rect"):
		var r: Array = SiteProps.rot_rect(z["rect"], rot)
		q["rect"] = [r3(x + float(r[0])), r3(zz + float(r[1])), r3(x + float(r[2])), r3(zz + float(r[3]))]
	if z.has("c"):
		var c := rot_xz(float((z["c"] as Array)[0]), float((z["c"] as Array)[1]), rot)
		q["c"] = [r3(x + c.x), r3(zz + c.y)]
	if str(z.get("kind", "")) == "hoist":
		var c2 := rot_xz(float(z["x"]), float(z["z"]), rot)
		q["x"] = r3(x + c2.x); q["z"] = r3(zz + c2.y)
	return q


## The prop turned by `rot` quarter turns and moved to (x, z); `rect` is its yard footprint.
static func place(p: Dictionary, x: float, z: float, rot: int) -> Dictionary:
	var q := new_prop(str(p["kind"]))
	var odd := (rot & 1) == 1
	for b: Dictionary in p["boxes"]:
		var c := rot_xz(float(b["x"]), float(b["z"]), rot)
		var nb := b.duplicate()
		nb["x"] = r3(x + c.x); nb["z"] = r3(z + c.y)
		if odd: nb["w"] = b["d"]; nb["d"] = b["w"]
		(q["boxes"] as Array).append(nb)
	for l: Dictionary in p["ladders"]:
		var c := rot_xz(float(l["x"]), float(l["z"]), rot)
		var n := rot_xz(float(l["nx"]), float(l["nz"]), rot)
		(q["ladders"] as Array).append({"x": r3(x + c.x), "z": r3(z + c.y), "nx": n.x, "nz": n.y, "y0": float(l["y0"]), "y1": float(l["y1"])})
	for pd: Dictionary in p["pads"]:
		var c := rot_xz(float(pd["x"]), float(pd["z"]), rot)
		(q["pads"] as Array).append({"x": r3(x + c.x), "z": r3(z + c.y), "r": float(pd["r"]), "power": float(pd["power"])})
	for zn: Dictionary in p["zones"]: (q["zones"] as Array).append(_rot_zone(zn, x, z, rot))
	for t: Array in p["tops"]:
		var c := rot_xz(float(t[0]), float(t[1]), rot)
		(q["tops"] as Array).append([r3(x + c.x), r3(z + c.y), float(t[2])])
	var lr: Array = SiteProps.rot_rect(p["lrect"], rot)
	q["lrect"] = p["lrect"]
	q["rect"] = [x + float(lr[0]), z + float(lr[1]), x + float(lr[2]), z + float(lr[3])]
	return q


static func rect_gap(a: Array, b: Array) -> float:
	return SiteMap._rect_gap(a, b)


## Puts `p` at a random spot (and quarter turn) inside the yard, at least `gap` from everything placed so far and `inset` from the
## wall. Returns the placed prop or {} when it does not fit.
static func put(placed: Array, p: Dictionary, rng: SiteMap.Rng, gap: float, half: float, inset: float, tries := 60) -> Dictionary:
	var lr: Array = p["lrect"]
	for t in tries:
		var rot := rng.below(4)
		var rr: Array = SiteProps.rot_rect(lr, rot)
		var lo_x := -half + inset - float(rr[0])
		var hi_x := half - inset - float(rr[2])
		var lo_z := -half + inset - float(rr[1])
		var hi_z := half - inset - float(rr[3])
		if hi_x < lo_x or hi_z < lo_z: continue
		var x := rng.between(lo_x, hi_x)
		var z := rng.between(lo_z, hi_z)
		var rect := [x + float(rr[0]), z + float(rr[1]), x + float(rr[2]), z + float(rr[3])]
		var ok := true
		for q: Dictionary in placed:
			if rect_gap(rect, q["rect"]) < gap: ok = false; break
		if ok:
			var out := place(p, snappedf(x, 0.01), snappedf(z, 0.01), rot)
			placed.append(out)
			return out
	return {}


## Places `p` exactly (no overlap test: the caller has reserved the spot).
static func put_at(placed: Array, p: Dictionary, x: float, z: float, rot: int) -> Dictionary:
	var out := place(p, x, z, rot)
	placed.append(out)
	return out


## One run of perimeter wall along an axis: panels `seg` long in rotating `cols`, posts between them and an optional top rail.
## `a` / `b` are the ends [x, z]. Every box is flagged `skip` (the perimeter is never a platform: it is taller than a jump).
static func wall_run(o: Array, a: Array, b: Array, st: Dictionary) -> void:
	var along_x := absf(float(b[0]) - float(a[0])) > absf(float(b[1]) - float(a[1]))
	var s0 := float(a[0]) if along_x else float(a[1])
	var s1 := float(b[0]) if along_x else float(b[1])
	var fixed := float(a[1]) if along_x else float(a[0])
	var seg := float(st.get("seg", 4.0))
	var h := float(st.get("h", FENCE_H))
	var th := float(st.get("th", 0.3))
	var cols: Array = st.get("cols", [0x999999])
	var n := maxi(1, int(ceil((s1 - s0) / seg)))
	var pl := (s1 - s0) / float(n)
	for i in n:
		var c := s0 + (float(i) + 0.5) * pl
		var col: int = cols[i % cols.size()]
		if along_x: bx(o, c, fixed, pl, th, h, 0.0, col, {"skip": true})
		else: bx(o, fixed, c, th, pl, h, 0.0, col, {"skip": true})
	var pw := float(st.get("post_w", 0.0))
	if pw > 0.0:
		for i in n + 1:
			var c2 := s0 + float(i) * pl
			var ph := h + float(st.get("post_up", 0.2))
			if along_x: bx(o, c2, fixed, pw, pw + th - 0.1, ph, 0.0, int(st.get("post_col", 0x555555)), {"skip": true})
			else: bx(o, fixed, c2, pw + th - 0.1, pw, ph, 0.0, int(st.get("post_col", 0x555555)), {"skip": true})
	var rail := float(st.get("rail", 0.0))
	if rail > 0.0:
		if along_x: bx(o, (s0 + s1) / 2.0, fixed, s1 - s0, th + 0.12, rail, h, int(st.get("rail_col", 0x333333)), {"skip": true})
		else: bx(o, fixed, (s0 + s1) / 2.0, th + 0.12, s1 - s0, rail, h, int(st.get("rail_col", 0x333333)), {"skip": true})


## The four perimeter runs of a yard `half` metres from the middle to the wall face; every box is added to `o`.
static func perimeter(o: Array, half: float, st: Dictionary) -> void:
	var at := half - 0.45
	var e := half - 0.3
	wall_run(o, [-e - 0.15, -at], [e + 0.15, -at], st)
	wall_run(o, [-e - 0.15, at], [e + 0.15, at], st)
	wall_run(o, [-at, -e], [-at, e], st)
	wall_run(o, [at, -e], [at, e], st)


# ---------------------------------------------------------------- assembling a level

## Everything a pack map generator ends with: `boxes[0]` must be the floor slab; `props` the placed props (their boxes are NOT yet
## in `boxes`: assemble appends them). `opts`: half, header (the maps.json entry without a layout), required (prop kinds that must
## have been placed), raised (kinds whose first top may hold a crate), floor_pad ({size, color}), attempt, seed.
## Returns {map, ok, attempt, seed, props [{kind, rect}], ignore {box index: true}, zones, counts}.
static func assemble(boxes: Array, ladders: Array, pads: Array, zones: Array, props: Array, rng: SiteMap.Rng, opts: Dictionary) -> Dictionary:
	var half := float(opts["half"])
	for q: Dictionary in props:
		boxes.append_array(q["boxes"])
		ladders.append_array(q["ladders"])
		pads.append_array(q["pads"])
		zones.append_array(q["zones"])
	# styles / platform ignore list from the flags, then strip them: the geometry stays plain maps.json boxes
	var styles := {}
	var ignore := {}
	var clean: Array = []
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		if b.has("glow"): styles[str(i)] = {"emissive": int(b["glow"]), "ei": float(b.get("ei", GLOW_EI))}
		if bool(b.get("skip", false)): ignore[i] = true
		clean.append({"x": b["x"], "z": b["z"], "w": b["w"], "d": b["d"], "h": b["h"], "y": b["y"], "color": b["color"]})
	boxes = clean
	# free-floor candidates: 1.4 m from every box taller than a decal, off the hazards
	var obst: Array = []
	for i in range(1, boxes.size()):
		var b: Dictionary = boxes[i]
		if float(b["y"]) + float(b["h"]) <= 0.1: continue
		obst.append([float(b["x"]) - float(b["w"]) / 2.0, float(b["z"]) - float(b["d"]) / 2.0, float(b["x"]) + float(b["w"]) / 2.0, float(b["z"]) + float(b["d"]) / 2.0])
	var hazards: Array = zones.filter(func(z: Dictionary) -> bool: return str(z.get("kind", "")) != "ice")
	for pd: Dictionary in pads: hazards.append({"kind": "pad", "c": [pd["x"], pd["z"]], "r": float(pd["r"]) + 0.3})   # nobody starts on a bounce pad
	var cands: Array = []                                              # [x, z, clearance, hazard distance]
	var span := half - 4.0
	var gx := -span
	while gx <= span + 0.01:
		var gz := -span
		while gz <= span + 0.01:
			var cl := 99.0
			for r: Array in obst:
				var dx := maxf(0.0, maxf(float(r[0]) - gx, gx - float(r[2])))
				var dz := maxf(0.0, maxf(float(r[1]) - gz, gz - float(r[3])))
				cl = minf(cl, sqrt(dx * dx + dz * dz))
				if cl < 1.4: break
			if cl >= 1.4:
				var hz := 99.0
				for z: Dictionary in hazards: hz = minf(hz, PackZones.distance(z, gx, gz))
				cands.append([gx, gz, cl, hz])
			gz += 2.0
		gx += 2.0
	var free2: Array = cands.filter(func(c: Array) -> bool: return float(c[2]) >= 2.05 and float(c[3]) >= 2.5)
	var spawns := SiteMap._spread(free2, [], 8, [8.0, 6.0, 4.0], Vector2(-half * 0.7, -half * 0.7))
	var bots := SiteMap._spread(free2, spawns, 14, [4.0, 3.0, 2.0], Vector2(half * 0.7, half * 0.7))
	var drops := SiteMap._spread(cands.filter(func(c: Array) -> bool: return float(c[3]) >= 1.2), [], 12, [6.0, 4.5, 3.0], Vector2(0.0, 0.0))
	var drop_pts: Array = []
	for d: Array in drops: drop_pts.append([d[0], d[1]])
	var raised: Array = []
	var rk: Array = opts.get("raised", [])
	for q: Dictionary in props:
		if rk.has(str(q["kind"])) and (q["tops"] as Array).size() > 0: raised.append((q["tops"] as Array)[0])
	for i in mini(raised.size(), 3):
		var t: Array = raised[(i * 2 + rng.below(2)) % raised.size()]
		if not drop_pts.any(func(e: Array) -> bool: return e.size() > 2 and absf(float(e[0]) - float(t[0])) < 0.01 and absf(float(e[1]) - float(t[1])) < 0.01):
			drop_pts.append([t[0], t[1], t[2]])
	var ok := spawns.size() >= 8 and bots.size() >= 12 and drops.size() >= 12 and boxes.size() <= MAX_BOXES
	var have := {}
	for q: Dictionary in props: have[str(q["kind"])] = true
	for k: String in opts.get("required", []):
		if not have.has(k): ok = false
	var player: Array = spawns[0] if spawns.size() > 0 else [0.0, half - 6.0]
	for s: Array in spawns:
		if float(s[1]) > float(player[1]) or (is_equal_approx(float(s[1]), float(player[1])) and absf(float(s[0])) < absf(float(player[0]))): player = s
	var m: Dictionary = (opts["header"] as Dictionary).duplicate(true)
	m["spawns"] = spawns
	m["player"] = [player[0], player[1]]
	m["bots"] = bots
	m["drops"] = drop_pts
	m["zones"] = zones
	m["boxStyles"] = styles
	var geo := {"boxes": boxes, "bouncePads": pads, "floorPads": [], "ladders": ladders}
	if opts.has("floor_pad"): geo["floorPads"] = [opts["floor_pad"]]
	m["geometry"] = geo
	var plist: Array = []
	for q: Dictionary in props: plist.append({"kind": q["kind"], "rect": q["rect"]})
	return {"map": m, "ok": ok, "attempt": int(opts.get("attempt", 0)), "seed": int(opts.get("seed", 0)), "props": plist, "ignore": ignore, "half": half}
