class_name SiteMap
extends RefCounted
## Construction DLC: the generated "Building Site" (map id `sitegen`, Construction mode only). generate(seed) returns a complete
## maps.json-shaped level made of boxes, ladders and bounce pads only (physics needs nothing new): a ~64 x 64 m slab inside a
## site fence with gates, and a seeded mix of an excavator, a bulldozer, a tower crane, spoil heaps, pipe stacks, shipping
## containers, scaffold towers, a trench with a bounce pad, a concrete mixer, cones, barriers and hazard stripes (SiteProps).
##
## The seed (SiteMap.current_seed, set_seed) changes which props appear, where they stand, how they are turned (90 degree
## steps), their colours and how many there are. The layout has its own mulberry32 generator seeded locally: nothing here
## touches the combat RNG, and the same seed always gives the same level (the result is cached per seed).
## Playability is built in, not searched for: props are rectangles kept 3 m apart (machines 6 m), 3.5 m inside the fence, so
## the floor between them is one connected space; every raised top is a walkable step, a jump (2.0 m or less), a ladder, a set
## of steps or a bounce pad away (SiteProps); spawns, bot spots and crates are picked on floor 2 m from any prop. The Building
## Site tests (tests/site_map_test.gd, SiteNav) verify all of that for seeds 1..200.
##
## MapBuilder.build("sitegen") calls generate(current_seed) the way it completes the Pillars level; Content only holds header().

const ID := "sitegen"
const HALF := 32.0              ## the slab is 64 x 64
const INSET := 3.5              ## props stay this far inside the fence
const FENCE_AT := 31.55
const MAX_BOXES := 690          ## batching budget: well under 700
const MACHINE_GAP := 6.0        ## big machines (excavator, bulldozer, crane) keep this far from each other
const PROP_GAP := 3.0
const U32 := 0xFFFFFFFF
const CACHE_MAX := 6
const FLOORS := [0x8a7e6a, 0x7d7060, 0x948a76]       ## slab colours (dirt and gravel)
const PATCHES := [0x7a6a52, 0x6f6150, 0x857860]      ## dirt patch decals
const FLOOR_PAD := 0xa3a7ab                          ## the concrete pad over the middle of the slab

static var current_seed := 1
static var _cache: Dictionary = {}


## mulberry32 (the generator Sandbox's custom level uses too), local to the layout.
class Rng extends RefCounted:
	var s: int
	func _init(seed: int) -> void:
		s = seed & 0xFFFFFFFF
	func next() -> float:
		s = (s + 0x6D2B79F5) & 0xFFFFFFFF
		var t: int = s
		t = Dynamics.imul(t ^ (t >> 15), t | 1)
		t = (t ^ ((t + Dynamics.imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
	func between(a: float, b: float) -> float:
		return a + (b - a) * next()
	func below(n: int) -> int:
		return mini(n - 1, int(next() * float(n)))


## Sets the seed the next MapBuilder.build("sitegen") uses.
static func set_seed(s: int) -> void:
	current_seed = absi(s) & U32


## The maps.json entry without a layout (Content registers this; MapBuilder.build completes it with generate()).
static func header() -> Dictionary:
	return {"name": "Building Site", "cat": "obstacle", "tags": ["Construction", "Scaffold", "Cover"], "only": "construction",
		"blurb": "A new building site every time: a fenced yard with a crane, an excavator, a bulldozer, spoil heaps, containers, scaffold towers and a trench with a bounce pad. Climb ladders, jump from machine to machine, and mind the open gates.",
		"sky": 14083311, "skyTop": 8035000, "voidColor": 9083560, "hills": [11055248, 10002560, 12107936, 8949872],
		"shadow": 52, "orbit": 56, "orbitH": 32, "hemi": 0.9, "sunI": 1.05, "wander": 24,
		"spawns": [], "player": [0, 24], "bots": [], "drops": [],
		"geometry": {"boxes": [], "bouncePads": [], "floorPads": [], "ladders": []}}


## The complete level for `seed` (a deep copy: callers may change it).
static func generate(seed: int) -> Dictionary:
	return (layout(seed)["map"] as Dictionary).duplicate(true)


## generate() plus what the tests want to know: {map, ok, attempt, machines [{kind, rect}], props [{kind, rect}], fence (box
## index -> true), seed}.
static func layout(seed: int) -> Dictionary:
	var sd := absi(seed) & U32
	if _cache.has(sd): return _cache[sd]
	var res: Dictionary = {}
	for attempt in 12:
		res = _try(sd, attempt)
		if res["ok"]: break
	if _cache.size() >= CACHE_MAX: _cache.clear()
	_cache[sd] = res
	return res


static func _rect_gap(a: Array, b: Array) -> float:
	var dx := maxf(0.0, maxf(float(a[0]) - float(b[2]), float(b[0]) - float(a[2])))
	var dz := maxf(0.0, maxf(float(a[1]) - float(b[3]), float(b[1]) - float(a[3])))
	return sqrt(dx * dx + dz * dz)


## Puts `p` somewhere inside the yard at least `gap` (`machine_gap` between two machines) from everything placed so far.
## Returns the placed prop, or {} when nothing fits in `tries` goes.
static func _put(placed: Array, p: Dictionary, rng: Rng, gap: float, tries := 60, machine_gap := MACHINE_GAP) -> Dictionary:
	var lr: Array = p["lrect"]
	for t in tries:
		var rot := rng.below(4)
		var rr := SiteProps.rot_rect(lr, rot)
		var lo_x := -HALF + INSET - float(rr[0])
		var hi_x := HALF - INSET - float(rr[2])
		var lo_z := -HALF + INSET - float(rr[1])
		var hi_z := HALF - INSET - float(rr[3])
		var x := rng.between(lo_x, hi_x)
		var z := rng.between(lo_z, hi_z)
		if hi_x < lo_x or hi_z < lo_z: continue
		var rect := [x + float(rr[0]), z + float(rr[1]), x + float(rr[2]), z + float(rr[3])]
		var ok := true
		for q: Dictionary in placed:
			var need := machine_gap if (bool(p["machine"]) and bool(q["machine"])) else gap
			if _rect_gap(rect, q["rect"]) < need: ok = false; break
		if ok:
			var out := SiteProps.place(p, snappedf(x, 0.01), snappedf(z, 0.01), rot)
			placed.append(out)
			return out
	return {}


static func _add(boxes: Array, ladders: Array, pads: Array, p: Dictionary) -> void:
	boxes.append_array(p["boxes"])
	ladders.append_array(p["ladders"])
	pads.append_array(p["pads"])


## One go at a layout: attempt > 0 only when the first came up short on spawns / spots / budget (a different draw of the same seed).
static func _try(sd: int, attempt: int) -> Dictionary:
	var rng := Rng.new((sd * 2654435761 + attempt * 0x9E3779B1 + 17) & U32)
	var rnd := Callable(rng, "next")
	var boxes: Array = []
	var ladders: Array = []
	var pads: Array = []
	var placed: Array = []
	var fence: Dictionary = {}
	var floor_col: int = FLOORS[rng.below(3)]
	boxes.append({"x": 0.0, "z": 0.0, "w": HALF * 2.0, "d": HALF * 2.0, "h": 2.0, "y": -2.0, "color": floor_col})   # the slab (first box: the floor)
	# --- the fence: four runs with 1-2 gates, 6 m wide, at least two in all
	var gate_total := 0
	var gates_at: Array = []                                           # [side, centre]
	for side in 4:
		var gl: Array = []
		var n := 1 if rng.next() < 0.6 else 2
		if side == 3 and gate_total < 1: n = maxi(n, 1)
		var c0 := rng.between(-20.0, 20.0)
		gl.append([c0, 6.0])
		if n == 2:
			var c1 := c0 + (rng.between(14.0, 22.0) if c0 < 0.0 else -rng.between(14.0, 22.0))
			gl.append([clampf(c1, -24.0, 24.0), 6.0])
		gate_total += n
		gates_at.append(gl)
	var style := rng.below(3)
	for side in 4:
		var o: Array = []
		var a: Array
		var b: Array
		match side:
			0: a = [-FENCE_AT - 0.15, -FENCE_AT]; b = [FENCE_AT + 0.15, -FENCE_AT]
			1: a = [-FENCE_AT - 0.15, FENCE_AT]; b = [FENCE_AT + 0.15, FENCE_AT]
			2: a = [-FENCE_AT, -FENCE_AT - 0.15]; b = [-FENCE_AT, FENCE_AT + 0.15]
			_: a = [FENCE_AT, -FENCE_AT - 0.15]; b = [FENCE_AT, FENCE_AT + 0.15]
		SiteProps.fence_run(o, a, b, gates_at[side], (style + side) % 3 if rng.next() < 0.5 else style)
		for bx: Dictionary in o:
			fence[boxes.size()] = true
			boxes.append(bx)
		for g: Array in gates_at[side]:                                  # hazard stripes just inside every gate
			var hs := SiteProps.hazard_strip(6.0, 1.2)
			var edge := FENCE_AT - 1.3
			var at := [float(g[0]), -edge if side == 0 else edge] if side < 2 else [-edge if side == 2 else edge, float(g[0])]
			boxes.append_array(SiteProps.place(hs, float(at[0]), float(at[1]), 0 if side < 2 else 1)["boxes"])
	# --- the big machines
	var kinds: Array = []
	for k: String in ["crane", "excavator", "bulldozer"]:
		if rng.next() < 0.8: kinds.append(k)
	for k: String in ["excavator", "crane", "bulldozer"]:
		if kinds.size() < 2 and not kinds.has(k): kinds.append(k)
	var order := ["crane", "excavator", "bulldozer"]
	var props: Array = []                                              # every placed prop, in order
	for k: String in order:
		if not kinds.has(k): continue
		var col: int = SiteProps.YELLOW if rng.next() < 0.8 else SiteProps.ORANGE_D
		var p := SiteProps.crane(rnd, col) if k == "crane" else (SiteProps.excavator(col) if k == "excavator" else SiteProps.bulldozer(col))
		var q := _put(placed, p, rng, PROP_GAP)
		if not q.is_empty(): props.append(q)
	# --- the rest
	var plan: Array = []
	for i in 2 + rng.below(3): plan.append(["heap", 0])
	for i in 1 + rng.below(3): plan.append(["pipes", 0])
	for i in 2 + rng.below(3): plan.append(["container", 1 if rng.next() < 0.3 else 0])
	for i in 2 + rng.below(2): plan.append(["scaffold", 0])
	if rng.next() < 0.7: plan.append(["trench", 0])
	if rng.next() < 0.6: plan.append(["mixer", 0])
	for i in 2 + rng.below(3): plan.append(["cones", 3 + rng.below(4)])
	for i in 2 + rng.below(3): plan.append(["barriers", 2 + rng.below(3)])
	for pl: Array in plan:
		var p: Dictionary
		var gap := PROP_GAP
		match str(pl[0]):
			"heap": p = SiteProps.spoil_heap(rnd)
			"pipes": p = SiteProps.pipe_stack(rnd)
			"container": p = SiteProps.container(rnd, int(pl[1]) == 1)
			"scaffold": p = SiteProps.scaffold(rnd)
			"trench": p = SiteProps.trench(rnd)
			"mixer": p = SiteProps.mixer(SiteProps.ORANGE_D if rng.next() < 0.6 else SiteProps.YELLOW_D)
			"cones": p = SiteProps.cones(rnd, int(pl[1])); gap = 2.0
			_: p = SiteProps.barriers(rnd, int(pl[1])); gap = 2.0
		var q := _put(placed, p, rng, gap)
		if not q.is_empty(): props.append(q)
	for q: Dictionary in props: _add(boxes, ladders, pads, q)
	# --- floor decals: hazard stripes and dirt patches (4 cm high, never in the way)
	for i in rng.below(3) + 2:
		var hs := SiteProps.hazard_strip(rng.between(3.0, 6.0), 1.2)
		var q := _put(placed, hs, rng, 1.0, 30)
		if not q.is_empty(): _add(boxes, ladders, pads, q)
	for i in 4 + rng.below(4):
		var w := rng.between(3.0, 6.0)
		var d := rng.between(3.0, 6.0)
		boxes.append({"x": snappedf(rng.between(-26.0, 26.0), 0.01), "z": snappedf(rng.between(-26.0, 26.0), 0.01), "w": snappedf(w, 0.01), "d": snappedf(d, 0.01),
			"h": 0.03, "y": 0.0, "color": PATCHES[rng.below(3)]})
	# --- spots on free floor: 2 m from every box taller than a decal
	var obst: Array = []
	for i in range(1, boxes.size()):
		var b: Dictionary = boxes[i]
		if float(b["y"]) + float(b["h"]) <= 0.1: continue
		obst.append([float(b["x"]) - float(b["w"]) / 2.0, float(b["z"]) - float(b["d"]) / 2.0, float(b["x"]) + float(b["w"]) / 2.0, float(b["z"]) + float(b["d"]) / 2.0])
	var cands: Array = []                                              # [x, z, clearance]
	var gx := -28.0
	while gx <= 28.0:
		var gz := -28.0
		while gz <= 28.0:
			var cl := 99.0
			for r: Array in obst:
				var dx := maxf(0.0, maxf(float(r[0]) - gx, gx - float(r[2])))
				var dz := maxf(0.0, maxf(float(r[1]) - gz, gz - float(r[3])))
				cl = minf(cl, sqrt(dx * dx + dz * dz))
				if cl < 1.4: break
			if cl >= 1.4: cands.append([gx, gz, cl])
			gz += 2.0
		gx += 2.0
	var free2: Array = cands.filter(func(c: Array) -> bool: return float(c[2]) >= 2.05)
	var spawns := _spread(free2, [], 8, [9.0, 7.0, 5.0], Vector2(-22.0, -22.0))
	var bots := _spread(free2, spawns, 14, [4.0, 3.0, 2.0], Vector2(22.0, 22.0))
	var drops := _spread(cands, [], 12, [7.0, 5.0, 3.5], Vector2(0.0, 0.0))
	var drop_pts: Array = []
	for d: Array in drops: drop_pts.append([d[0], d[1]])
	# a few crates up on tops a player (and a bot) can reach: heap summits, scaffold decks, machine roofs
	var raised: Array = []
	for q: Dictionary in props:
		if ["heap", "scaffold", "bulldozer", "excavator", "trench"].has(str(q["kind"])) and (q["tops"] as Array).size() > 0: raised.append((q["tops"] as Array)[0])
	for i in mini(raised.size(), 3):
		var t: Array = raised[(i * 2 + rng.below(2)) % raised.size()]
		if not drop_pts.any(func(e: Array) -> bool: return e.size() > 2 and absf(float(e[0]) - float(t[0])) < 0.01 and absf(float(e[1]) - float(t[1])) < 0.01):
			drop_pts.append([t[0], t[1], t[2]])
	var ok := spawns.size() >= 8 and bots.size() >= 12 and drops.size() >= 12 and boxes.size() <= MAX_BOXES and kinds.size() >= 2
	for k: String in kinds:
		var found := false
		for q: Dictionary in props:
			if str(q["kind"]) == k: found = true
		if not found: ok = false                                       # a chosen machine had no room: draw again
	var player: Array = spawns[0] if spawns.size() > 0 else [0.0, 24.0]
	for s: Array in spawns:
		if float(s[1]) > float(player[1]) or (is_equal_approx(float(s[1]), float(player[1])) and absf(float(s[0])) < absf(float(player[0]))): player = s
	var m := header()
	m["spawns"] = spawns
	m["player"] = [player[0], player[1]]
	m["bots"] = bots
	m["drops"] = drop_pts
	m["geometry"] = {"boxes": boxes, "bouncePads": pads, "floorPads": [{"size": 58.0, "color": FLOOR_PAD}], "ladders": ladders}
	var machines: Array = []
	var plist: Array = []
	for q: Dictionary in props:
		plist.append({"kind": q["kind"], "rect": q["rect"]})
		if bool(q["machine"]): machines.append({"kind": q["kind"], "rect": q["rect"]})
	return {"map": m, "ok": ok, "attempt": attempt, "seed": sd, "machines": machines, "props": plist, "fence": fence}


## Up to `n` of `cands` ([x, z, ...]) as [x, z], farthest first: each next pick is the candidate farthest from all earlier ones
## (and from `others`), as long as it keeps at least seps[0] away; seps[1], seps[2] are fallbacks when the yard is crowded.
static func _spread(cands: Array, others: Array, n: int, seps: Array, start: Vector2) -> Array:
	var out: Array = []
	if cands.is_empty(): return out
	var taken: Array = others.duplicate()
	for sep in seps:
		while out.size() < n:
			var best := -1
			var bd := -1.0
			for i in cands.size():
				var c: Array = cands[i]
				var d := 1e9
				if taken.is_empty(): d = 1e6 - Vector2(float(c[0]), float(c[1])).distance_to(start)
				for t: Array in taken:
					d = minf(d, Vector2(float(c[0]) - float(t[0]), float(c[1]) - float(t[1])).length())
				if d > bd: bd = d; best = i
			if best < 0 or bd < float(sep): break
			var c2: Array = cands[best]
			out.append([c2[0], c2[1]])
			taken.append([c2[0], c2[1]])
		if out.size() >= n: break
	return out
