class_name KitchenProps
extends RefCounted
## Kitchen pack ("On Fire") arena props for KitchenMap: stainless prep islands, stoves with glowing burners, rolling prep carts,
## produce crates, fridges, floor burner strips and an exhaust-vent bounce pad with a pot rack. Plain boxes in flat stylised colours
## (see PackMapKit for the prop shape and the jump rules).

const STEEL := 0x8f9aa3
const STEEL_L := 0xd5dbe0
const STEEL_D := 0x59636b
const DARK := 0x2a2f36
const WHITE := 0xe8edef
const WHITE_D := 0xdde4e7
const GREY := 0x8a9199                    ## floor decal
const BASIN := 0x6fa4c4
const TILE := 0xc9d3d8
const TILE_D := 0xaab6be
const FIRE := 0xff5a1f
const FIRE_Y := 0xffc83a
const EMBER := 0x7a1d10
const GREASE := 0xb59a58
const WOOD := 0xa97b4a
const POTS := [0xc0392b, 0x2f6db5, 0x3a8f5a, 0xd9a21b, 0x7a8590]
const PRODUCE := [0x4fa043, 0xe0701f, 0xc0392b, 0xe6c34a, 0x8a5a9b]
const BX := preload("res://dlc/pack_map_kit.gd")


static func palette() -> Array:
	return [STEEL, STEEL_L, STEEL_D, DARK, WHITE, WHITE_D, TILE, TILE_D, FIRE, FIRE_Y, EMBER, GREASE, GREY, WOOD, BASIN] + POTS + PRODUCE


## Stainless prep island: steel base, a lighter top and a few pots (0.4 m) on it. Top 1.0 m: one jump.
static func island(rnd: Callable, w := 4.0, d := 2.0) -> Dictionary:
	var p := BX.new_prop("island")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, w, d, 0.9, 0.0, STEEL)
	BX.bx(o, 0, 0, w + 0.1, d + 0.1, 0.1, 0.9, STEEL_L)
	BX.bx(o, 0, d / 2.0 + 0.02, w - 0.4, 0.05, 0.3, 0.3, STEEL_D)           # drawer fronts: a darker panel on one long face
	var n := int(BX.f(rnd) * 3.0)
	for i in n:
		var x := (float(i) - float(n - 1) / 2.0) * 1.1 + (BX.f(rnd) - 0.5) * 0.3
		BX.bx(o, x, (BX.f(rnd) - 0.5) * 0.3, 0.5, 0.5, 0.4, 1.0, BX.pick(rnd, POTS))
	p["tops"].append([0.0, 0.0, 1.0])
	return BX.finish(p)


## Range island: a stove with four glowing burner plates on top (a burner zone: standing on it sets you alight) and a steel
## extraction hood far overhead (never a platform: it hangs above even a vent-pad jump).
static func range_island(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("range")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 6.0, 2.4, 0.95, 0.0, STEEL_D)
	BX.bx(o, 0, 0, 6.1, 2.5, 0.07, 0.95, DARK)
	BX.bx(o, 0, 1.22, 5.0, 0.05, 0.5, 0.2, DARK)                           # oven door
	for i in 4:
		var x := (float(i) - 1.5) * 1.35
		BX.bx(o, x, 0, 1.05, 1.05, 0.05, 1.02, FIRE, {"glow": FIRE})
		BX.bx(o, x, 0, 0.45, 0.45, 0.06, 1.02, FIRE_Y, {"glow": FIRE_Y})
	p["zones"].append({"kind": "burner", "rect": [-2.55, -0.62, 2.55, 0.62], "top": 1.02})
	BX.bx(o, 0, 0, 6.2, 2.8, 0.7, 8.6, STEEL_L, {"skip": true})               # the hood
	BX.bx(o, 0, 0, 1.2, 1.2, 3.0, 9.3, STEEL_D, {"skip": true})
	p["tops"].append([2.4, 0.9, 1.02])
	return BX.finish(p)


## Rolling prep cart: dark base and wheels, a steel tray at 0.85 m (the posts keep the gap closed), 0.93 m top: one jump.
static func cart(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("cart")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 2.4, 1.3, 0.5, 0.0, STEEL_D)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			BX.bx(o, sx * 1.1, sz * 0.55, 0.12, 0.12, 0.35, 0.5, STEEL)
	BX.bx(o, 0, 0, 2.5, 1.4, 0.08, 0.85, STEEL_L)
	BX.bx(o, -1.15, 0, 0.1, 1.4, 0.4, 0.93, STEEL)                          # the push rail
	if BX.f(rnd) < 0.7: BX.bx(o, 0.3, 0.1, 0.55, 0.55, 0.4, 0.93, BX.pick(rnd, POTS))
	p["tops"].append([0.2, 0.0, 0.93])
	return BX.finish(p)


## A stack of produce crates (1.3 m cubes): a row of three, with a single crate on the middle one if `tiers` is 2 (stepped back far
## enough that the navigability grid sees both levels).
static func crates(rnd: Callable, tiers := 2) -> Dictionary:
	var p := BX.new_prop("crates")
	var o: Array = p["boxes"]
	for k in tiers:
		var n := 3 - 2 * k
		for i in n:
			var x := (float(i) - float(n - 1) / 2.0) * 1.35
			BX.bx(o, x, 0, 1.3, 1.3, 1.1, 1.1 * float(k), BX.pick(rnd, PRODUCE))
			BX.bx(o, x, 0, 1.36, 1.36, 0.1, 1.1 * float(k) + 0.55, WOOD)     # the slat band round the middle
	p["tops"].append([0.0, 0.0, 1.1 * float(tiers)])
	return BX.finish(p)


## Tall fridge: 2.2 m square, 2.5 m high. Too tall to climb (a pillar), so the navigability test leaves its top out.
static func fridge() -> Dictionary:
	var p := BX.new_prop("fridge")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 2.2, 2.2, 2.5, 0.0, WHITE, {"skip": true})
	BX.bx(o, 1.12, 0.5, 0.06, 0.12, 0.8, 1.1, STEEL_D, {"skip": true})
	BX.bx(o, 1.1, 0, 0.04, 2.1, 0.06, 1.3, STEEL, {"skip": true})
	return BX.finish(p)


## A strip of floor burner: a glowing plate between two dark rails with flame tongues along it. It is a zone, not an obstacle (the
## whole thing is under 0.55 m: walk over it and you burn).
static func burner_strip(rnd: Callable, length := 6.0) -> Dictionary:
	var p := BX.new_prop("burner")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, length, 1.5, 0.1, 0.0, FIRE, {"glow": FIRE, "ei": 1.2})
	for s in [-1.0, 1.0]: BX.bx(o, 0, s * 0.85, length + 0.2, 0.2, 0.18, 0.0, DARK)
	for s in [-1.0, 1.0]: BX.bx(o, s * (length / 2.0 + 0.1), 0, 0.2, 1.9, 0.18, 0.0, DARK)
	var n := maxi(3, int(length / 1.2))
	for i in n:
		var x := (float(i) - float(n - 1) / 2.0) * (length / float(n)) + (BX.f(rnd) - 0.5) * 0.2
		BX.bx(o, x, (BX.f(rnd) - 0.5) * 0.5, 0.3, 0.3, 0.2 + BX.f(rnd) * 0.2, 0.1, FIRE_Y if i % 2 == 0 else FIRE, {"glow": FIRE_Y if i % 2 == 0 else FIRE, "ei": 1.8})
	p["zones"].append({"kind": "burner", "rect": [-length / 2.0, -0.75, length / 2.0, 0.75], "top": 0.1})
	return BX.finish(p)


## The overhead exhaust vent: a grated floor plate with the bounce pad on it, a vent hood hanging far above and a pot rack beside it (a shelf on two posts, 3.4 m up): only the pad (or a wall run) gets you onto it.
static func vent_pad(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("vent")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 3.4, 3.4, 0.05, 0.0, STEEL_L)
	BX.bx(o, 0, 0, 2.4, 2.4, 0.07, 0.0, STEEL_D)
	BX.bx(o, 0, 0, 3.6, 3.6, 0.6, 9.2, STEEL_L, {"skip": true})               # the hood
	BX.bx(o, 0, 0, 1.0, 1.0, 3.0, 9.8, STEEL_D, {"skip": true})
	p["pads"].append({"x": 0.0, "z": 0.0, "r": 1.2, "power": 17.0})
	# the pot rack: a shelf at 3.2 m on two posts, 3 m from the pad
	var rx := 3.6
	BX.bx(o, rx, 0, 1.6, 4.4, 0.2, 3.2, STEEL)
	for s in [-1.0, 1.0]: BX.bx(o, rx, s * 2.0, 0.3, 0.3, 3.2, 0.0, STEEL_D)
	for i in 3: BX.bx(o, rx, (float(i) - 1.0) * 1.3, 0.5, 0.5, 0.4, 3.4, BX.pick(rnd, POTS))
	p["tops"].append([rx, 0.0, 3.4])
	return BX.finish(p)


## A sink unit along a wall: steel with a blue basin inset.
static func sink(w := 3.0) -> Dictionary:
	var p := BX.new_prop("sink")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, w, 0.9, 0.9, 0.0, STEEL)
	BX.bx(o, 0, 0, w + 0.1, 1.0, 0.1, 0.9, STEEL_L)
	BX.bx(o, 0, 0, w - 1.0, 0.6, 0.04, 1.0, BASIN)
	BX.bx(o, -0.05, -0.38, 0.12, 0.12, 0.4, 1.0, STEEL_D)
	return BX.finish(p)


## A stove along a wall: dark body with two glowing plates that are NOT hazard strips (a wall stove is scenery), a steel back.
static func wall_stove() -> Dictionary:
	var p := BX.new_prop("wallstove")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 3.6, 0.95, 0.95, 0.0, STEEL_D)
	BX.bx(o, 0, 0, 3.7, 1.05, 0.06, 0.95, DARK)
	for s in [-1.0, 1.0]: BX.bx(o, s * 0.9, 0, 0.7, 0.7, 0.04, 1.01, EMBER, {"glow": EMBER, "ei": 0.8})
	return BX.finish(p)
