class_name BackyardBbqMap
extends RefCounted
## Australia pack ("Hey Mate"): the procedural arena `backyard_bbq`, a 44 x 44 m suburban backyard built from boxes and one bounce
## pad (plus the zones PackZones turns into hazards): a corrugated-iron fence all round, a hot BBQ whose glowing hotplate burns
## anyone who walks on it, a Hills Hoist rotary clothesline in the middle whose arms sweep round and knock you flying (jump it or
## slip in behind an arm), esky cooler stacks, wheelie bins, a picnic table, garden beds, cricket stumps and a kangaroo-spring
## trampoline pad. Same seed, same backyard (a local mulberry32); see KitchenMap for the playability rules.

const ID := "backyard_bbq"
const HALF := 22.0
const INSET := 3.5
const BX := preload("res://dlc/pack_map_kit.gd")
const A := preload("res://dlc/australia/australia_props.gd")


static func header() -> Dictionary:
	return {"name": "Backyard BBQ", "cat": "obstacle", "tags": ["Australia", "BBQ", "Hazard"], "only": "australia",
		"blurb": "A sunny afternoon in the backyard: eskys for cover, a hot BBQ plate you do not want to stand on, a Hills Hoist that sweeps the lawn, and a trampoline that launches you like a kangaroo.",
		"sky": 12113141, "skyTop": 6598884, "voidColor": 10080400, "hills": [9164152, 8112240, 10346104, 7254112],
		"shadow": 34, "orbit": 38, "orbitH": 26, "hemi": 1.0, "sunI": 1.2, "wander": 17,
		"spawns": [], "player": [0, 17], "bots": [], "drops": [],
		"geometry": {"boxes": [], "bouncePads": [], "floorPads": [], "ladders": []}}


static func try_layout(sd: int, attempt: int) -> Dictionary:
	var rng := SiteMap.Rng.new((sd * 2654435761 + attempt * 0x9E3779B1 + 59) & PackMapKit.U32)
	var rnd := Callable(rng, "next")
	var boxes: Array = []
	BX.bx(boxes, 0.0, 0.0, HALF * 2.0, HALF * 2.0, 2.0, -2.0, A.GRASS if rng.next() < 0.6 else A.GRASS_D)
	BX.perimeter(boxes, HALF, {"seg": 2.6, "h": 2.8, "th": 0.25, "cols": A.fence_cols(rng), "post_w": 0.0})
	var placed: Array = []
	var props: Array = []
	var wall := HALF - 0.6
	# --- the BBQ against the north wall, its hotplate in front (facing +z)
	var bx_at := rng.between(-10.0, 10.0)
	props.append(BX.put_at(placed, A.bbq(rnd), bx_at, -(wall - 1.1), 0))
	# --- the Hills Hoist in the middle, a little off centre, and the trampoline well clear of the fence (a launch must not clear it)
	var sgn := 1.0 if rng.next() < 0.5 else -1.0
	props.append(BX.put_at(placed, A.hoist(sgn * rng.between(1.0, 1.3), rng.between(0.0, TAU)), rng.between(-1.5, 1.5), rng.between(-1.0, 2.0), 0))
	var ang := rng.between(0.6, 2.4) + (PI if rng.next() < 0.5 else 0.0)
	props.append(BX.put_at(placed, A.trampoline(), snappedf(cos(ang) * 11.0, 0.01), snappedf(sin(ang) * 11.0, 0.01), 0))
	for i in 2:
		var gq := BX.put(placed, A.gum_tree(rnd), rng, 2.5, HALF, INSET)
		if not gq.is_empty(): props.append(gq)
	# --- cover and furniture
	for i in 4:
		var q := BX.put(placed, A.esky_stack(rnd, 1 + rng.below(2)), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 4:
		var q := BX.put(placed, A.bin(rnd), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 1 + rng.below(2):
		var q := BX.put(placed, A.picnic(rnd), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 2:
		var q := BX.put(placed, A.garden_bed(rnd), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 2:
		var q := BX.put(placed, A.kettle(), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	var pq := BX.put(placed, A.pool(), rng, 2.5, HALF, INSET)
	if not pq.is_empty(): props.append(pq)
	for i in 1 + rng.below(2):
		var q := BX.put(placed, A.stumps(), rng, 2.0, HALF, INSET)
		if not q.is_empty(): props.append(q)
	var sq := BX.put(placed, A.shed(), rng, 2.5, HALF, INSET)
	if not sq.is_empty(): props.append(sq)
	# --- lawn patches and the paving round the BBQ (3 cm decals)
	boxes.append({"x": snappedf(bx_at, 0.01), "z": -(wall - 5.5), "w": 11.0, "d": 10.0, "h": 0.03, "y": 0.0, "color": A.PAVER})
	boxes.append({"x": snappedf(bx_at, 0.01), "z": -(wall - 5.5), "w": 8.0, "d": 7.0, "h": 0.05, "y": 0.0, "color": A.PAVER_D})
	for i in 7 + rng.below(4):
		boxes.append({"x": snappedf(rng.between(-17.0, 17.0), 0.01), "z": snappedf(rng.between(-17.0, 17.0), 0.01), "w": snappedf(rng.between(3.0, 7.0), 0.01),
			"d": snappedf(rng.between(3.0, 7.0), 0.01), "h": 0.03, "y": 0.0, "color": A.GRASS_L if rng.next() < 0.6 else A.DIRT})
	return BX.assemble(boxes, [], [], [], props, rng, {"half": HALF, "header": header(), "attempt": attempt, "seed": sd,
		"required": ["hoist", "bbq", "trampoline", "esky", "bin"], "raised": ["esky", "bbq", "picnic", "bin"]})
