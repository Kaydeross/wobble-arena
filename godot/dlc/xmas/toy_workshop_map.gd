class_name ToyWorkshopMap
extends RefCounted
## Xmas pack ("Ho Ho Ho"): the procedural arena `toy_workshop`, a 48 x 48 m Santa's workshop built from boxes and one bounce pad
## (plus the ice zones PackZones turns into slippery steering): a giant Christmas tree you can climb (stepped tiers), stacks of
## presents and toy blocks for cover, a toy train, workbenches and shelves along two walls, snow drifts, a big icy floor patch
## (low friction, only in this arena and only under the balance overlay), a candy-cane perimeter fence and a brick chimney whose
## bounce pad throws you up onto its top. Same seed, same workshop (a local mulberry32); see KitchenMap for the playability rules.

const ID := "toy_workshop"
const HALF := 24.0
const INSET := 3.5
const BX := preload("res://dlc/pack_map_kit.gd")
const X := preload("res://dlc/xmas/xmas_props.gd")


static func header() -> Dictionary:
	return {"name": "Toy Workshop", "cat": "obstacle", "tags": ["Xmas", "Ice", "Cover"], "only": "xmas",
		"blurb": "Santa's workshop on Christmas Eve: climb the giant tree, hide behind the present stacks, skid across the icy floor, and use the chimney bounce pad to reach the top. The candy-cane fence keeps the elves in.",
		"sky": 12436463, "skyTop": 8433363, "voidColor": 11393502, "hills": [14150140, 12112876, 15001340, 10590420],
		"shadow": 36, "orbit": 40, "orbitH": 26, "hemi": 1.0, "sunI": 1.0, "wander": 18,
		"spawns": [], "player": [0, 18], "bots": [], "drops": [],
		"geometry": {"boxes": [], "bouncePads": [], "floorPads": [], "ladders": []}}


static func try_layout(sd: int, attempt: int) -> Dictionary:
	var rng := SiteMap.Rng.new((sd * 2654435761 + attempt * 0x9E3779B1 + 47) & PackMapKit.U32)
	var rnd := Callable(rng, "next")
	var boxes: Array = []
	BX.bx(boxes, 0.0, 0.0, HALF * 2.0, HALF * 2.0, 2.0, -2.0, X.FLOOR_W if rng.next() < 0.5 else X.FLOOR_W2)
	BX.perimeter(boxes, HALF, {"seg": 3.0, "h": 2.8, "th": 0.35, "cols": [X.RED, X.WHITE], "post_w": 0.45, "post_col": X.GREEN, "rail": 0.2, "rail_col": X.WHITE})
	var placed: Array = []
	var props: Array = []
	# --- the chimney on the east or south wall, its pad facing in (the pad stays 2 m clear of the wall)
	var wall := HALF - 0.65
	var side := rng.below(2)
	var along := rng.between(-11.0, 11.0)
	var cdepth := wall - 1.55
	var ch: Dictionary
	if side == 0: ch = BX.put_at(placed, X.chimney(), cdepth, along, 2)         # east wall, faces -x
	else: ch = BX.put_at(placed, X.chimney(), along, cdepth, 3)                  # south wall, faces -z
	props.append(ch)
	# --- the giant tree in the middle, a little off centre
	props.append(BX.put_at(placed, X.tree(rnd), rng.between(-1.5, 1.5), rng.between(-1.5, 1.5), 0))
	# --- the icy floor: one big patch and a small one
	var ice := BX.put(placed, X.ice_patch(13.0 + rng.next() * 2.0, 9.0 + rng.next() * 2.0), rng, 2.0, HALF, 3.0)
	if not ice.is_empty(): props.append(ice)
	var ice2 := BX.put(placed, X.ice_patch(5.0, 4.0), rng, 2.0, HALF, 3.0)
	if not ice2.is_empty(): props.append(ice2)
	# --- the wall line on the north and west walls (benches and shelves)
	_wall_line(props, rng, rnd, 0, ch)
	_wall_line(props, rng, rnd, 3, ch)
	# --- cover
	for i in 6 + rng.below(2):
		var q := BX.put(placed, X.gifts(rnd, 1 + rng.below(2)), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	for i in 2 + rng.below(2):
		var q := BX.put(placed, X.blocks(rnd), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	var tq := BX.put(placed, X.train(rnd), rng, 2.5, HALF, INSET)
	if not tq.is_empty(): props.append(tq)
	for i in 2 + rng.below(2):
		var q := BX.put(placed, X.drift(rnd), rng, 2.5, HALF, INSET)
		if not q.is_empty(): props.append(q)
	return BX.assemble(boxes, [], [], [], props, rng, {"half": HALF, "header": header(), "attempt": attempt, "seed": sd,
		"required": ["tree", "ice", "chimney", "gifts", "blocks"], "raised": ["tree", "gifts", "chimney", "blocks"]})


## Benches and shelves along a wall (rot 0 = north, 3 = west), skipping anything too near the chimney.
static func _wall_line(props: Array, rng: SiteMap.Rng, rnd: Callable, rot: int, chimney: Dictionary) -> void:
	var cursor := -HALF + 3.0
	var end := HALF - 3.0
	while cursor < end - 1.0:
		var kind := rng.below(4)
		var p: Dictionary
		var w := 3.0
		match kind:
			0: p = X.bench(5.0); w = 5.0
			1: p = X.shelf(3.2); w = 3.2
			2: p = X.bench(3.0); w = 3.0
			_: p = {}; w = 3.0 + rng.next() * 2.0
		if not p.is_empty() and (rot == 0 or rng.next() < 0.5):
			var depth := 1.0 if kind != 1 else 0.9
			var off := HALF - 0.65 - depth / 2.0 - 0.05
			var c := cursor + w / 2.0
			var at := Vector2(c, -off) if rot == 0 else Vector2(-off, c)
			var q := BX.place(p, snappedf(at.x, 0.01), snappedf(at.y, 0.01), rot)
			var near := false
			for pr: Dictionary in props:
				if BX.rect_gap(q["rect"], pr["rect"]) < 1.0: near = true
			if not near: props.append(q)
		cursor += w + 0.2
