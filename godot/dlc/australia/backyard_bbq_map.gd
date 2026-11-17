class_name BackyardBbqMap
extends RefCounted
## Australia pack ("Hey Mate"): the procedural arena `backyard_bbq`, a 44 x 44 m suburban backyard built from boxes and one bounce
## pad (plus the zones PackZones turns into hazards): a corrugated-iron fence all round, a hot BBQ whose glowing hotplate burns
## anyone who walks on it, a Hills Hoist rotary clothesline in the middle whose arms sweep round and knock you flying (jump it or
## slip in behind an arm), esky cooler stacks, wheelie bins, a picnic table, garden beds, cricket stumps and a kangaroo-spring
## trampoline pad. The fence line is dressed (the shed and its rainwater tank, the veggie patch, a row of bins, the woodpile, pot
## plants, surfboards, the kennel, a bench) and the lawn carries the cover, dealt out a quadrant at a time so it stays spread:
## esky stacks, the outdoor setting under its umbrella, camp chairs, the paddling pool, the sandpit, the mower, gum trees.
## Same seed, same backyard (a local mulberry32); see KitchenMap for the playability rules.

const ID := "backyard_bbq"
const HALF := 22.0
const INSET := 3.5
const WALL := 21.42               ## the fence's inner face: fence-line props stand with their backs on it
const LIM := HALF - INSET
const QUADS := [[-LIM, -LIM, 1.0, 1.0], [-1.0, -LIM, LIM, 1.0], [-1.0, -1.0, LIM, LIM], [-LIM, -1.0, 1.0, LIM]]
const BX := preload("res://dlc/pack_map_kit.gd")
const A := preload("res://dlc/australia/australia_props.gd")


static func header() -> Dictionary:
	return {"name": "Backyard BBQ", "cat": "obstacle", "tags": ["Australia", "BBQ", "Hazard"], "only": "australia",
		"blurb": "A sunny afternoon in the backyard: eskys for cover, a hot BBQ plate you do not want to stand on, a Hills Hoist that sweeps the lawn, and a trampoline that launches you like a kangaroo.",
		"sky": 12113141, "skyTop": 6598884, "voidColor": 10080400, "hills": [9164152, 8112240, 10346104, 7254112],
		"shadow": 34, "orbit": 38, "orbitH": 26, "hemi": 1.0, "sunI": 1.2, "wander": 17,
		"spawns": [], "player": [0, 17], "bots": [], "drops": [],
		"geometry": {"boxes": [], "bouncePads": [], "floorPads": [], "ladders": []}}


## Stands `p` (back at local x = 0) against fence `side` (0 west, 1 north, 2 east, 3 south) at a random spot along it, `gap` clear of
## everything placed so far. Returns the placed prop or {} when the fence is full there.
static func _wall_put(placed: Array, p: Dictionary, rng: SiteMap.Rng, side: int, gap := 1.8, tries := 24) -> Dictionary:
	var rr: Array = SiteProps.rot_rect(p["lrect"], side)
	for t in tries:
		var s := rng.between(-WALL, WALL)
		var x := s
		var z := s
		match side:
			0: x = -WALL
			1: z = -WALL
			2: x = WALL
			_: z = WALL
		var rect := [x + float(rr[0]), z + float(rr[1]), x + float(rr[2]), z + float(rr[3])]
		if float(rect[0]) < -WALL - 0.01 or float(rect[2]) > WALL + 0.01 or float(rect[1]) < -WALL - 0.01 or float(rect[3]) > WALL + 0.01: continue
		var ok := true
		for q: Dictionary in placed:
			if BX.rect_gap(rect, q["rect"]) < gap: ok = false; break
		if ok: return BX.put_at(placed, p, snappedf(x, 0.01), snappedf(z, 0.01), side)
	return {}


## BX.put, but the whole prop stays inside `reg` [x0, z0, x1, z1]; falls back to anywhere on the lawn.
static func _put_in(placed: Array, p: Dictionary, rng: SiteMap.Rng, gap: float, reg: Array, tries := 30) -> Dictionary:
	var lr: Array = p["lrect"]
	for t in tries:
		var rot := rng.below(4)
		var rr: Array = SiteProps.rot_rect(lr, rot)
		var lo_x := float(reg[0]) - float(rr[0])
		var hi_x := float(reg[2]) - float(rr[2])
		var lo_z := float(reg[1]) - float(rr[1])
		var hi_z := float(reg[3]) - float(rr[3])
		if hi_x < lo_x or hi_z < lo_z: continue
		var x := rng.between(lo_x, hi_x)
		var z := rng.between(lo_z, hi_z)
		var rect := [x + float(rr[0]), z + float(rr[1]), x + float(rr[2]), z + float(rr[3])]
		var ok := true
		for q: Dictionary in placed:
			if BX.rect_gap(rect, q["rect"]) < gap: ok = false; break
		if ok: return BX.put_at(placed, p, snappedf(x, 0.01), snappedf(z, 0.01), rot)
	return BX.put(placed, p, rng, gap, HALF, INSET, 30)


static func _add(props: Array, q: Dictionary) -> void:
	if not q.is_empty(): props.append(q)


static func try_layout(sd: int, attempt: int) -> Dictionary:
	var rng := SiteMap.Rng.new((sd * 2654435761 + attempt * 0x9E3779B1 + 59) & PackMapKit.U32)
	var rnd := Callable(rng, "next")
	var boxes: Array = []
	var dark := rng.next() >= 0.6
	BX.bx(boxes, 0.0, 0.0, HALF * 2.0, HALF * 2.0, 2.0, -2.0, A.GRASS_D if dark else A.GRASS)
	BX.perimeter(boxes, HALF, {"seg": 2.6, "h": 2.8, "th": 0.25, "cols": A.fence_cols(rng), "post_w": 0.0, "rail": 0.1, "rail_col": A.STEEL})
	# fence posts on the yard side, every third sheet
	var ps := -WALL + 1.2
	while ps < WALL:
		for side in 4:
			var c := BX.rot_xz(-WALL + 0.07, ps, side)
			BX.bx(boxes, c.x, c.y, 0.18, 0.18, 2.95, 0.0, A.POST, {"skip": true})
		ps += 5.13
	var placed: Array = []
	var props: Array = []
	var wall := HALF - 0.6
	# --- the BBQ against the north wall, its hotplate in front (facing +z)
	var bx_at := rng.between(-10.0, 10.0)
	props.append(BX.put_at(placed, A.bbq(rnd), bx_at, -(wall - 1.1), 0))
	# --- the Hills Hoist in the middle, a little off centre, and the trampoline well clear of the fence (a launch must not clear it)
	var sgn := 1.0 if rng.next() < 0.5 else -1.0
	var hx := rng.between(-1.5, 1.5)
	var hz := rng.between(-1.0, 2.0)
	props.append(BX.put_at(placed, A.hoist(sgn * rng.between(1.0, 1.3), rng.between(0.0, TAU)), hx, hz, 0))
	var ang := rng.between(0.6, 2.4) + (PI if rng.next() < 0.5 else 0.0)
	props.append(BX.put_at(placed, A.trampoline(), snappedf(cos(ang) * 11.0, 0.01), snappedf(sin(ang) * 11.0, 0.01), 0))
	# --- the fence line: the shed first (it is the biggest), then the rest dealt round the four fences
	var s0 := rng.below(4)
	_add(props, _wall_put(placed, A.shed(), rng, s0 if s0 != 1 else 3))
	var line: Array = [A.veggie_patch(rnd), A.bin_row(), A.woodpile(), A.pots(rnd), A.surf_rack(rnd), A.kennel(), A.bench(), A.pots(rnd), A.garden_bed(rnd, true), A.bench()]
	for i in line.size():
		_add(props, _wall_put(placed, line[i], rng, (s0 + 1 + i) % 4))
	# --- the lawn: the big pieces first (trees, the setting, pool, sandpit, picnic table), then the esky stacks a quadrant at a time
	var q0 := rng.below(4)
	for i in 2:
		_add(props, _put_in(placed, A.gum_tree(rnd), rng, 2.5, QUADS[(q0 + 1 + i * 2) % 4]))
	_add(props, _put_in(placed, A.setting(rnd), rng, 2.5, QUADS[(q0 + 2) % 4]))
	_add(props, _put_in(placed, A.pool(), rng, 2.5, QUADS[(q0 + 3) % 4]))
	_add(props, _put_in(placed, A.sandpit(rnd), rng, 2.5, QUADS[(q0 + 1) % 4]))
	_add(props, _put_in(placed, A.picnic(rnd), rng, 2.5, QUADS[q0]))
	for i in 6:
		_add(props, _put_in(placed, A.esky_stack(rnd, 2 if i < 3 else 1), rng, 2.5, QUADS[(q0 + i) % 4]))
	_add(props, BX.put(placed, A.slide_mat(), rng, 0.6, HALF, INSET, 40))      # flat: it may lie close to things
	# --- the small stuff tucks in closer (1.7 m still leaves a lane on the 1 m grid): bins, kettles, chairs, little eskies, the mower
	for i in 4:
		_add(props, _put_in(placed, A.bin(rnd), rng, 1.7, QUADS[(q0 + 1 + i) % 4]))
	for i in 2:
		_add(props, _put_in(placed, A.kettle(), rng, 1.7, QUADS[(q0 + i * 2) % 4]))
	for i in 4:
		_add(props, _put_in(placed, A.camp_chairs(rnd), rng, 1.7, QUADS[(q0 + 3 + i) % 4]))
	for i in 3:
		_add(props, _put_in(placed, A.esky_small(rnd), rng, 1.7, QUADS[(q0 + 1 + i) % 4]))
	_add(props, _put_in(placed, A.mower(), rng, 1.7, QUADS[(q0 + 3) % 4]))
	for i in 1 + rng.below(2):
		_add(props, BX.put(placed, A.stumps(), rng, 1.7, HALF, INSET))
	# --- shrubs and flowers in the border along the fence, wherever nothing else stands
	for i in 18:
		_add(props, _wall_put(placed, A.shrub(rnd), rng, (s0 + i) % 4, 0.5, 6))
	# --- the lawn itself (decals, 2 - 6 cm): mowing stripes, the paving round the BBQ and stepping stones out to the hoist, worn patches
	var along_x := rng.next() < 0.5
	var stripe: int = A.GRASS if dark else A.GRASS_L
	for i in 5:
		var c := -17.2 + float(i) * 8.6
		if along_x: boxes.append({"x": 0.0, "z": c, "w": WALL * 2.0, "d": 4.3, "h": 0.02, "y": 0.0, "color": stripe})
		else: boxes.append({"x": c, "z": 0.0, "w": 4.3, "d": WALL * 2.0, "h": 0.02, "y": 0.0, "color": stripe})
	var pz := -(wall - 5.5)
	boxes.append({"x": snappedf(bx_at, 0.01), "z": pz, "w": 11.0, "d": 10.0, "h": 0.04, "y": 0.0, "color": A.PAVER})
	boxes.append({"x": snappedf(bx_at, 0.01), "z": pz, "w": 8.0, "d": 7.0, "h": 0.06, "y": 0.0, "color": A.PAVER_D})
	for i in 5:
		var k := (float(i) + 0.5) / 5.0
		boxes.append({"x": snappedf(lerpf(bx_at, hx, k) + (0.35 if i % 2 == 0 else -0.35), 0.01), "z": snappedf(lerpf(pz + 5.6, hz - 1.2, k), 0.01), "w": 1.0, "d": 0.8, "h": 0.05, "y": 0.0, "color": A.PAVER if i % 2 == 0 else A.PAVER_D})
	boxes.append({"x": snappedf(hx, 0.01), "z": snappedf(hz, 0.01), "w": 3.4, "d": 3.4, "h": 0.03, "y": 0.0, "color": A.DIRT})     # worn bare under the hoist
	for i in 3 + rng.below(3):
		boxes.append({"x": snappedf(rng.between(-17.0, 17.0), 0.01), "z": snappedf(rng.between(-17.0, 17.0), 0.01), "w": snappedf(rng.between(2.0, 4.5), 0.01),
			"d": snappedf(rng.between(2.0, 4.5), 0.01), "h": 0.03, "y": 0.0, "color": A.DIRT})
	return BX.assemble(boxes, [], [], [], props, rng, {"half": HALF, "header": header(), "attempt": attempt, "seed": sd,
		"required": ["hoist", "bbq", "trampoline", "esky", "bin", "shed"], "raised": ["esky", "bbq", "picnic", "bin"]})
