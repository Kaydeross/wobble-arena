class_name KitchenMap
extends RefCounted
## Kitchen pack ("On Fire"): the procedural arena `kitchen_chaos`, a 48 x 48 m commercial kitchen built from boxes, ladders and a
## bounce pad only (plus the burner zones PackZones turns into damage): tiled walls with a counter / sink / stove / fridge line along
## them, stainless prep islands as cover, glowing burner strips and stove tops (standing on one sets you alight), rolling prep carts,
## produce crates and two overhead-vent bounce pads that throw you onto a pot rack. Same seed, same kitchen (a local mulberry32);
## `current_seed` / PackMaps.set_seed pick it, MapBuilder.build calls generate(). Props keep 3 m apart and 3.5 m off the walls, so the
## floor between them is one connected space; every raised top is a walk, a jump (2.0 m or less) or a pad away, which
## tests/pack_maps_test.gd proves with SiteNav for 8+ seeds. Budget: <= 450 boxes (PackMapKit.MAX_BOXES), cap 690.

const ID := "kitchen_chaos"
const HALF := 24.0
const INSET := 3.5
const BX := preload("res://dlc/pack_map_kit.gd")
const K := preload("res://dlc/kitchen/kitchen_props.gd")


static func header() -> Dictionary:
	return {"name": "Kitchen Chaos", "cat": "obstacle", "tags": ["Kitchen", "Fire", "Cover"], "only": "kitchen",
		"blurb": "A restaurant kitchen at the dinner rush: stainless prep islands for cover, glowing burners on the floor and the stoves (do not stand on them), rolling carts, and exhaust-vent bounce pads that fling you up to the pot rack.",
		"sky": 16382415, "skyTop": 11392728, "voidColor": 10459544, "hills": [13548472, 12755112, 14464984, 11965592],
		"shadow": 38, "orbit": 42, "orbitH": 27, "hemi": 1.0, "sunI": 1.1, "wander": 19,
		"spawns": [], "player": [0, 18], "bots": [], "drops": [],
		"geometry": {"boxes": [], "bouncePads": [], "floorPads": [], "ladders": []}}


## One go at a layout (attempt > 0 only when the first came up short): the complete result PackMapKit.assemble returns.
static func try_layout(sd: int, attempt: int) -> Dictionary:
	var rng := SiteMap.Rng.new((sd * 2654435761 + attempt * 0x9E3779B1 + 31) & PackMapKit.U32)
	var rnd := Callable(rng, "next")
	var boxes: Array = []
	BX.bx(boxes, 0.0, 0.0, HALF * 2.0, HALF * 2.0, 2.0, -2.0, K.TILE)                       # the floor (first box)
	var cells := 8                                                                           # a checkerboard of darker 6 m tiles (3 cm decals)
	var cs := HALF * 2.0 / float(cells)
	var odd := rng.below(2)
	for i in cells:
		for j in cells:
			if (i + j) % 2 == odd: BX.bx(boxes, -HALF + (float(i) + 0.5) * cs, -HALF + (float(j) + 0.5) * cs, cs, cs, 0.03, 0.0, K.TILE_D)
	BX.perimeter(boxes, HALF, {"seg": 6.5, "h": 2.8, "th": 0.4, "cols": [K.WHITE, K.WHITE_D], "post_w": 0.5, "post_col": K.STEEL, "rail": 0.2, "rail_col": K.STEEL_D})
	var placed: Array = []
	var props: Array = []
	# --- the wall line: counters, sinks, stoves, fridges along the north wall (all of it) and parts of the west / east walls
	_wall_line(props, rng, rnd, 0, -HALF + 0.45 + 0.1)
	_wall_line(props, rng, rnd, 3, -HALF + 0.45 + 0.1)
	_wall_line(props, rng, rnd, 1, -HALF + 0.45 + 0.1)
	# --- the big things first: stoves, vent pads, burner strips
	for i in 2:
		var q := BX.put(placed, K.range_island(rnd), rng, 3.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 2:
		var q := BX.put(placed, K.vent_pad(rnd), rng, 3.0, HALF, 7.0)      # well clear of the wall: a launch must not clear the fence
		if not q.is_empty(): props.append(q)
	for i in 4 + rng.below(3):
		var q := BX.put(placed, K.burner_strip(rnd, 4.0 + float(rng.below(3)) * 1.5), rng, 3.0, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 6 + rng.below(3):
		var q := BX.put(placed, K.island(rnd, 3.0 + float(rng.below(4)), 1.8 + rng.next() * 0.4), rng, 3.0, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 5 + rng.below(3):
		var q := BX.put(placed, K.cart(rnd), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 3 + rng.below(3):
		var q := BX.put(placed, K.crates(rnd, 1 + rng.below(2)), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	# --- floor decals (3 cm): grease spills and tile mats, never in the way
	for i in 6 + rng.below(4):
		boxes.append({"x": snappedf(rng.between(-18.0, 18.0), 0.01), "z": snappedf(rng.between(-18.0, 18.0), 0.01), "w": snappedf(rng.between(2.0, 4.5), 0.01),
			"d": snappedf(rng.between(2.0, 4.5), 0.01), "h": 0.03, "y": 0.0, "color": K.GREASE if rng.next() < 0.6 else K.GREY})
	return BX.assemble(boxes, [], [], [], props, rng, {"half": HALF, "header": header(), "attempt": attempt, "seed": sd,
		"required": ["range", "vent", "burner", "island", "cart"], "raised": ["island", "range", "cart", "crates", "vent"]})


## A run of wall furniture along one wall: `rot` 0 = the north wall (faces +z), 3 = the west wall (faces +x), 1 = the east wall.
static func _wall_line(props: Array, rng: SiteMap.Rng, rnd: Callable, rot: int, _unused: float) -> void:
	var cursor := -HALF + 3.0
	var end := HALF - 3.0
	var full := rot == 0
	while cursor < end - 1.0:
		var kind := rng.below(6)
		var p: Dictionary
		var w := 3.0
		var depth := 0.9
		match kind:
			0: p = K.island(rnd, 4.0, 0.9); w = 4.0
			1: p = K.sink(3.0); w = 3.0; depth = 0.9
			2: p = K.wall_stove(); w = 3.6
			3: p = K.fridge(); w = 2.2; depth = 2.2
			4: p = K.island(rnd, 5.0, 0.9); w = 5.0
			_: p = {}; w = 2.5 + rng.next() * 2.0                                # a gap
		if not p.is_empty() and (full or rng.next() < 0.5):
			var c := cursor + w / 2.0
			var wall := HALF - 0.65                                              # the wall face
			var off := wall - depth / 2.0 - 0.05
			var at := Vector2(c, -off) if rot == 0 else (Vector2(-off, c) if rot == 3 else Vector2(off, c))
			props.append(BX.place(p, snappedf(at.x, 0.01), snappedf(at.y, 0.01), rot))
		cursor += w + 0.2
