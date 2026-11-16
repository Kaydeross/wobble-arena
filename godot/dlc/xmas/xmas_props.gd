class_name XmasProps
extends RefCounted
## Xmas pack ("Ho Ho Ho") arena props for ToyWorkshopMap: the giant tree (a stepped pyramid you can climb), gift-box stacks, toy
## blocks, a toy train, workbenches, snow drifts, the brick chimney with its bounce pad, icy floor patches and the candy-cane
## perimeter. Plain boxes in flat colours (see PackMapKit).

const RED := 0xc8283a
const GREEN := 0x2f8f4e
const GREEN_D := 0x1f6b3a
const GREEN_L := 0x4aa860
const GOLD := 0xf2c230
const BLUE := 0x3a76c8
const WHITE := 0xf1f4f6
const SNOW := 0xe3edf3
const ICE := 0xbfe4f5
const ICE_D := 0xa5d4ea
const BRICK := 0xa8452f
const BRICK_D := 0x8a3624
const SOOT := 0x2b2724
const WOOD := 0x9b6b3d
const WOOD_D := 0x77502c
const FLOOR_W := 0xe6dccb
const FLOOR_W2 := 0xdcd1bd
const GIFTS := [0xc8283a, 0x2f8f4e, 0x3a76c8, 0xf2c230, 0x8e4fb8, 0xe8754a]
const RIBBONS := [0xf2c230, 0xf1f4f6, 0xc8283a, 0x2f8f4e]
const BX := preload("res://dlc/pack_map_kit.gd")


static func palette() -> Array:
	return [RED, GREEN, GREEN_D, GREEN_L, GOLD, BLUE, WHITE, SNOW, ICE, ICE_D, BRICK, BRICK_D, SOOT, WOOD, WOOD_D, FLOOR_W, FLOOR_W2, 0xe8754a, 0xff7a2a, 0xd9f0fa] + GIFTS


## The giant Christmas tree: a stepped pyramid of green tiers (1.2 m each: every tier is a jump from the one below, the top is
## 6 m up), a gold star, red / gold / blue baubles (0.3 m: walkable) and a trunk stub. The king-of-the-hill centrepiece.
static func tree(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("tree")
	var o: Array = p["boxes"]
	var sizes := [11.0, 8.6, 6.4, 4.4, 2.6]
	var cols := [GREEN_D, GREEN, GREEN_D, GREEN, GREEN_L]
	for i in sizes.size():
		BX.bx(o, 0, 0, float(sizes[i]), float(sizes[i]), 1.2, 1.2 * float(i), int(cols[i]))
		# tinsel band round the rim of every tier (a flat 4 cm strip on top, along the front and back)
		BX.bx(o, 0, float(sizes[i]) / 2.0 - 0.25, float(sizes[i]) - 0.4, 0.3, 0.05, 1.2 * float(i + 1), GOLD if i % 2 == 0 else WHITE)
		BX.bx(o, 0, -float(sizes[i]) / 2.0 + 0.25, float(sizes[i]) - 0.4, 0.3, 0.05, 1.2 * float(i + 1), GOLD if i % 2 == 0 else WHITE)
	BX.bx(o, 0, 0, 0.5, 0.5, 1.4, 6.0, GOLD, {"skip": true})                             # the star's post (never a platform)
	BX.bx(o, 0, 0, 1.1, 1.1, 0.5, 7.2, GOLD, {"glow": GOLD, "ei": 1.4, "skip": true})  # the star (never a platform)
	for i in 10:                                                                       # baubles on the tiers
		var tier := int(BX.f(rnd) * 4.0)
		var half := float(sizes[tier]) / 2.0 - 0.9
		var a := BX.f(rnd) * TAU
		var r := half * (0.4 + BX.f(rnd) * 0.6)
		BX.bx(o, cos(a) * r, sin(a) * r, 0.5, 0.5, 0.3, 1.2 * float(tier + 1), BX.pick(rnd, [RED, GOLD, BLUE, WHITE]))
	p["tops"].append([0.9, 0.0, 6.0])
	p["tops"].append([3.3, 3.3, 1.2])
	return BX.finish(p)


## A stack of presents: a big one (1.3 m) with a smaller one on top (1.1 m), stepped well back so each is a jump from the one below,
## with ribbons and a bow.
static func gifts(rnd: Callable, tiers := 3) -> Dictionary:
	var p := BX.new_prop("gifts")
	var o: Array = p["boxes"]
	var y := 0.0
	var w := 4.4 + BX.f(rnd) * 0.8
	for k in tiers:
		var h := 1.3 - 0.2 * float(k)
		var col: int = BX.pick(rnd, GIFTS)
		var rib: int = BX.pick(rnd, RIBBONS)
		var ox := (BX.f(rnd) - 0.5) * 0.5
		BX.bx(o, ox, 0, w, w, h, y, col)
		BX.bx(o, ox, 0, 0.34, w + 0.06, h + 0.04, y, rib)
		BX.bx(o, ox, 0, w + 0.06, 0.34, h + 0.04, y, rib)
		y += h
		w = maxf(1.4, w - 3.0)
	BX.bx(o, 0, 0, 0.7, 0.7, 0.35, y, BX.pick(rnd, RIBBONS))                                 # the bow
	p["tops"].append([0.0, 0.0, y + 0.35])
	return BX.finish(p)


## Alphabet / toy blocks: 1.4 m cubes in a loose group of 3 to 5 (single or stacked two high on the same spot), 1.4 m top.
static func blocks(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("blocks")
	var o: Array = p["boxes"]
	var n := 3 + int(BX.f(rnd) * 3.0)
	for i in n:
		var x := (float(i) - float(n - 1) / 2.0) * 1.5
		BX.bx(o, x, (BX.f(rnd) - 0.5) * 0.4, 1.4, 1.4, 1.4, 0.0, BX.pick(rnd, [RED, BLUE, GOLD, GREEN, 0xe8754a]))
		BX.bx(o, x, 0.0, 0.9, 1.44, 0.04, 0.8, WHITE)
	if n >= 4: BX.bx(o, 0.0, 0.0, 1.2, 1.2, 1.1, 1.4, BX.pick(rnd, [RED, BLUE, GOLD]))
	p["tops"].append([0.0, 0.0, 1.4])
	return BX.finish(p)


## A toy train: an engine and two wagons in a row (1.0 m high bodies on thin wheels), a low run of cover.
static func train(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("train")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 2.4, 1.5, 1.1, 0.0, RED)
	BX.bx(o, 0.5, 0, 1.0, 1.5, 0.7, 1.1, BLUE)
	BX.bx(o, -0.9, 0, 0.7, 0.7, 0.5, 1.1, SOOT)                                            # the funnel
	for i in 2:
		var x := -3.0 - float(i) * 2.6
		BX.bx(o, x, 0, 2.3, 1.4, 0.9, 0.0, BX.pick(rnd, [GREEN, GOLD, BLUE]))
		BX.bx(o, x, 0, 2.0, 1.1, 0.25, 0.9, WOOD)
	p["tops"].append([0.2, 0.0, 1.8])
	return BX.finish(p)


## A workbench along a wall: wood top on a base, tools (low blocks) on it. 1.0 m top.
static func bench(w := 5.0) -> Dictionary:
	var p := BX.new_prop("bench")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, w, 1.0, 0.9, 0.0, WOOD_D)
	BX.bx(o, 0, 0, w + 0.1, 1.1, 0.1, 0.9, WOOD)
	for i in int(w / 1.5):
		BX.bx(o, (float(i) - float(int(w / 1.5) - 1) / 2.0) * 1.5, -0.1, 0.5, 0.4, 0.3, 1.0, [RED, BLUE, GOLD, GREEN][i % 4])
	return BX.finish(p)


## A shelf unit along a wall: a tall dark frame (2.6 m: a pillar) with toy boxes on the lower shelf.
static func shelf(w := 3.2) -> Dictionary:
	var p := BX.new_prop("shelf")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, w, 0.9, 2.6, 0.0, WOOD_D, {"skip": true})
	for i in 3: BX.bx(o, (float(i) - 1.0) * (w / 3.2), 0.5, 0.8, 0.2, 0.5, 0.5 + 0.7 * float(i % 2), [RED, BLUE, GOLD][i], {"skip": true})
	return BX.finish(p)


## A snow drift: three low tiers (0.5 m: walked up), white.
static func drift(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("drift")
	var o: Array = p["boxes"]
	var w := 4.5 + BX.f(rnd) * 1.5
	for i in 3:
		BX.bx(o, (BX.f(rnd) - 0.5) * 0.4, (BX.f(rnd) - 0.5) * 0.4, w - 1.3 * float(i), w * 0.7 - 1.0 * float(i), 0.5, 0.5 * float(i), SNOW if i % 2 == 0 else WHITE)
	p["tops"].append([0.0, 0.0, 1.5])
	return BX.finish(p)


## The chimney: a brick column (4.4 m, soot cap) against the wall with a hearth glow at its foot, and the bounce pad two metres in
## front of it: the pad throws you up onto the top. A brick ledge halfway keeps the top reachable from a pad jump that falls short.
static func chimney() -> Dictionary:
	var p := BX.new_prop("chimney")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 3.0, 3.0, 4.4, 0.0, BRICK)
	for i in 4: BX.bx(o, 0, 0, 3.06, 3.06, 0.12, 0.7 + 1.0 * float(i), BRICK_D)         # mortar courses
	BX.bx(o, 0, 0, 3.4, 3.4, 0.2, 4.4, SOOT)
	BX.bx(o, 0, 0, 1.6, 1.6, 0.5, 4.6, BRICK_D)                                            # the pot on the top
	BX.bx(o, 1.52, 0, 0.06, 1.4, 1.0, 0.0, SOOT)                                           # the hearth mouth
	BX.bx(o, 1.55, 0, 0.05, 1.0, 0.6, 0.0, 0xff7a2a, {"glow": 0xff7a2a, "ei": 1.2})
	p["pads"].append({"x": 4.6, "z": 0.0, "r": 1.2, "power": 17.0})
	p["tops"].append([0.0, 1.1, 4.6])
	return BX.finish(p)


## An icy floor patch: pale blue 3 cm slabs (a decal: it hides nothing and blocks nothing) plus the ice zone (PackZones: the
## ice-grip steering while you stand on it). `w` x `d` metres, centred on the origin.
static func ice_patch(w: float, d: float) -> Dictionary:
	var p := BX.new_prop("ice")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, w, d, 0.03, 0.0, ICE, {"decal": true})
	BX.bx(o, -w * 0.18, d * 0.12, w * 0.5, d * 0.45, 0.04, 0.0, ICE_D, {"decal": true})
	BX.bx(o, w * 0.3, -d * 0.2, w * 0.28, d * 0.3, 0.05, 0.0, 0xd9f0fa, {"decal": true})
	p["zones"].append({"kind": "ice", "rect": [-w / 2.0, -d / 2.0, w / 2.0, d / 2.0], "top": 0.05})
	return BX.finish(p)
