class_name AustraliaProps
extends RefCounted
## Australia pack ("Hey Mate") arena props for BackyardBbqMap: the Hills Hoist rotary clothesline (a pole plus a spinning hit band,
## PackZones), the BBQ with its glowing hotplate (a burner zone), esky cooler stacks, the kangaroo-spring trampoline pad, wheelie
## bins, a picnic table, garden beds, cricket stumps and the corrugated-iron fence. Plain boxes in flat colours (see PackMapKit).

const IRON := [0x9aa7ae, 0x8a9096, 0xa7b2b8, 0x7f98a8]
const IRON_RUST := [0xa0654a, 0xb07a58, 0x8f5a43]
const POST := 0x5a4a3a
const GRASS := 0x7bb661
const GRASS_L := 0x8cc470
const GRASS_D := 0x67a050
const DIRT := 0xb0845a
const PAVER := 0xc9b79a
const PAVER_D := 0xb6a384
const STEEL := 0x6a7078
const STEEL_D := 0x3a3f45
const WHITE := 0xeef2f4
const BBQ_BLACK := 0x2b2d31
const HOT := 0xff6a1f
const HOT_Y := 0xffc83a
const COOLERS := [0x2f6db5, 0xc0392b, 0x2f9a6a, 0xd9a21b]
const WOOD := 0x9b6b3d
const WOOD_D := 0x77502c
const BIN_G := 0x3a8f5a
const BIN_Y := 0xe8c33a
const TRAMP_FRAME := 0xf2c230
const TRAMP_MAT := 0x24272b
const LINE := 0xe9ecee
const BX := preload("res://dlc/pack_map_kit.gd")


static func palette() -> Array:
	return IRON + IRON_RUST + COOLERS + [POST, GRASS, GRASS_L, GRASS_D, DIRT, PAVER, PAVER_D, STEEL, STEEL_D, WHITE, BBQ_BLACK, HOT, HOT_Y, WOOD, WOOD_D,
		BIN_G, BIN_Y, TRAMP_FRAME, TRAMP_MAT, LINE, 0x9a9a96, 0xc4553a, 0x3a6db5, 0x5a4330, 0x4fa043, 0xe86fa5, 0xe6c34a, 0xe6d3a0, 0xc9b68a, 0x4f8a6a, 0x35604a, 0x3a9ad9, 0x8fd4f2, 0xd8cdb8, 0x5f9a5a, 0x73ad66]


## The corrugated-iron fence colours, in the order the panels use them (greys with the odd rusty sheet).
static func fence_cols(rng: SiteMap.Rng) -> Array:
	var cols: Array = []
	for i in 6:
		cols.append(IRON_RUST[rng.below(3)] if rng.next() < 0.25 else IRON[rng.below(4)])
	return cols


## The Hills Hoist: a concrete base and a 3.4 m pole (solid, a pillar) and the rotary arms (PackSpinner draws them; PackZones
## hits you with them). `omega` rad/s (sign = direction), the sweep reaches `r` m at 0.8 - 1.7 m above the floor: jump it,
## or run in behind an arm. The whole sweep disc is the prop's footprint (nothing stands in it).
static func hoist(omega: float, phase: float, r := 5.2) -> Dictionary:
	var p := BX.new_prop("hoist")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 1.3, 1.3, 0.3, 0.0, 0x9a9a96)
	BX.bx(o, 0, 0, 0.5, 0.5, 3.4, 0.3, WHITE, {"skip": true})
	BX.bx(o, 0, 0, 0.7, 0.7, 0.22, 3.7, STEEL_D, {"skip": true})                           # the hub
	p["zones"].append({"kind": "hoist", "x": 0.0, "z": 0.0, "r": r, "arms": 4, "omega": omega, "phase": phase, "y0": 0.8, "y1": 1.7})
	p["tops"].append([1.0, 0.0, 0.3])
	return BX.finish(p)


## An esky (cooler) stack: a big chest esky (0.9 m, white lid) with a smaller one up on one end (1.8 m: a jump from the chest, which is a
## jump from the floor), blue / red / green. The small one sits at the end so a 2 m run of the chest's top stays free to land on.
static func esky_stack(rnd: Callable, tiers := 2) -> Dictionary:
	var p := BX.new_prop("esky")
	var o: Array = p["boxes"]
	var col: int = BX.pick(rnd, COOLERS)
	var w := 4.2
	var d := 1.9
	BX.bx(o, 0, 0, w, d, 0.75, 0.0, col)
	BX.bx(o, 0, 0, w + 0.1, d + 0.1, 0.15, 0.75, WHITE)
	BX.bx(o, 0, d / 2.0 + 0.03, 0.5, 0.05, 0.18, 0.5, STEEL_D)                       # the latch
	p["tops"].append([-1.0, 0.0, 0.9])
	if tiers >= 2:
		var col2: int = BX.pick(rnd, COOLERS)
		BX.bx(o, 1.1, 0, 1.7, 1.7, 0.65, 0.9, col2)
		BX.bx(o, 1.1, 0, 1.8, 1.8, 0.15, 1.55, WHITE)
		p["tops"].insert(0, [1.1, 0.0, 1.7])
	return BX.finish(p)


## The BBQ: a black body with a lid hood on wheels (solid cover, 1.0 m, a hood at 1.5) beside a big glowing hotplate on the floor,
## 0.25 m high (walk across it and you burn: a burner zone). Smoke stack on the side.
static func bbq(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("bbq")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 4.2, 1.9, 1.0, 0.0, BBQ_BLACK)
	BX.bx(o, -0.1, 0, 3.8, 1.7, 0.6, 1.0, STEEL_D)                                       # the lid hood
	BX.bx(o, 1.9, 0.7, 0.24, 0.24, 0.9, 1.4, STEEL, {"skip": true})                       # smoke stack
	for s in [-1.0, 1.0]: BX.bx(o, s * 1.6, 1.05, 0.2, 0.2, 0.3, 0.0, STEEL)            # wheels
	BX.bx(o, 0.0, 0.96, 3.2, 0.05, 0.14, 0.7, HOT, {"glow": HOT, "ei": 1.2})            # the glow under the lid
	# the hotplate: in front of the BBQ (local +z), a steel frame round a glowing plate with sausages on it
	var cz := 3.9
	BX.bx(o, 0, cz, 5.0, 3.2, 0.25, 0.0, STEEL_D)
	BX.bx(o, 0, cz, 4.6, 2.8, 0.06, 0.25, HOT, {"glow": HOT, "ei": 1.3})
	for i in 5:
		BX.bx(o, (float(i) - 2.0) * 0.8, cz + (BX.f(rnd) - 0.5) * 1.0, 0.22, 1.0, 0.18, 0.31, 0xc4553a if i % 2 == 0 else HOT_Y, {"glow": HOT_Y, "ei": 0.8} if i % 2 == 1 else {})
	p["zones"].append({"kind": "burner", "rect": [-2.3, cz - 1.4, 2.3, cz + 1.4], "top": 0.31})
	p["tops"].append([1.0, 0.0, 1.6])
	return BX.finish(p)


## The kangaroo-spring trampoline: a yellow frame, a dark mat and the pad on it (a stronger one than a plain pad: 19).
static func trampoline() -> Dictionary:
	var p := BX.new_prop("trampoline")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 4.0, 4.0, 0.12, 0.0, TRAMP_MAT)
	for s in [-1.0, 1.0]:
		BX.bx(o, 0, s * 2.0, 4.4, 0.3, 0.4, 0.0, TRAMP_FRAME)
		BX.bx(o, s * 2.0, 0, 0.3, 4.0, 0.4, 0.0, TRAMP_FRAME)
	p["pads"].append({"x": 0.0, "z": 0.0, "r": 1.2, "power": 19.0})
	return BX.finish(p)


## A wheelie bin: 1.0 x 0.9 m, 1.1 m high with a coloured lid. A jump.
static func bin(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("bin")
	var o: Array = p["boxes"]
	var col: int = BIN_G if BX.f(rnd) < 0.5 else 0x3a6db5
	BX.bx(o, 0, 0, 1.0, 0.9, 1.0, 0.0, col)
	BX.bx(o, 0, 0, 1.1, 1.0, 0.12, 1.0, BIN_Y if BX.f(rnd) < 0.6 else col)
	p["tops"].append([0.0, 0.0, 1.12])
	return BX.finish(p)


## A picnic table: a plank top at 0.8 m with two benches at 0.45 m (walkable steps up).
static func picnic(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("picnic")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 3.0, 1.1, 0.8, 0.0, WOOD_D)
	BX.bx(o, 0, 0, 3.2, 1.3, 0.1, 0.8, WOOD)
	for s in [-1.0, 1.0]: BX.bx(o, 0, s * 1.15, 3.0, 0.5, 0.45, 0.0, WOOD)
	if BX.f(rnd) < 0.6: BX.bx(o, 0.6, 0, 0.5, 0.5, 0.25, 0.9, WHITE)
	p["tops"].append([0.0, 0.0, 0.9])
	return BX.finish(p)


## A raised garden bed: a timber frame filled with dark earth and green growth (0.5 m: walked over).
static func garden_bed(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("bed")
	var o: Array = p["boxes"]
	var w := 4.0 + BX.f(rnd) * 2.0
	BX.bx(o, 0, 0, w, 1.8, 0.5, 0.0, WOOD)
	BX.bx(o, 0, 0, w - 0.4, 1.4, 0.06, 0.5, 0x5a4330)
	for i in int(w / 1.0):
		if BX.f(rnd) < 0.8: BX.bx(o, (float(i) - float(int(w) - 1) / 2.0) * 0.9, (BX.f(rnd) - 0.5) * 0.8, 0.5, 0.5, 0.4, 0.56, BX.pick(rnd, [0x4fa043, 0x3a8f5a, 0xe86fa5, 0xe6c34a]))
	return BX.finish(p)


## Cricket stumps: three thin wooden stumps (0.7 m) with a bail: a low little cover.
static func stumps() -> Dictionary:
	var p := BX.new_prop("stumps")
	var o: Array = p["boxes"]
	for i in 3: BX.bx(o, 0, (float(i) - 1.0) * 0.4, 0.14, 0.14, 0.75, 0.0, 0xe6d3a0)
	BX.bx(o, 0, 0, 0.1, 1.0, 0.06, 0.75, 0xc9b68a)
	return BX.finish(p)


## A kettle BBQ: a round-ish black bowl on legs, 1.0 m (a jump), with a lid knob. Cover.
static func kettle() -> Dictionary:
	var p := BX.new_prop("kettle")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 1.2, 1.2, 0.6, 0.0, BBQ_BLACK)
	BX.bx(o, 0, 0, 1.0, 1.0, 0.35, 0.6, STEEL_D)
	BX.bx(o, 0, 0, 0.25, 0.25, 0.12, 0.95, STEEL)
	p["tops"].append([0.0, 0.0, 1.07])
	return BX.finish(p)


## A kids' paddling pool: a blue rim 0.4 m high round shallow water (a walk up and over): wading cover.
static func pool() -> Dictionary:
	var p := BX.new_prop("pool")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 4.2, 4.2, 0.4, 0.0, 0x3a9ad9)
	BX.bx(o, 0, 0, 3.4, 3.4, 0.04, 0.4, 0x8fd4f2)
	p["tops"].append([0.0, 0.0, 0.44])
	return BX.finish(p)


## A gum tree: a pale trunk (0.8 m, a pillar) and a green canopy hanging at 3.4 m (never a platform: above a jump, below a high leap).
static func gum_tree(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("gum")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 0.9, 0.9, 3.5, 0.0, 0xd8cdb8, {"skip": true})
	BX.bx(o, 0, 0, 4.6, 4.6, 1.3, 3.4, 0x5f9a5a, {"skip": true})
	BX.bx(o, 0.4, -0.3, 3.0, 3.0, 1.0, 4.7, 0x73ad66, {"skip": true})
	return BX.finish(p)


## A garden shed in a corner: 3 x 2.6 m, 2.4 m high (a pillar: too tall to jump on), green walls and a rusty roof.
static func shed() -> Dictionary:
	var p := BX.new_prop("shed")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 3.4, 2.8, 2.3, 0.0, 0x4f8a6a, {"skip": true})
	BX.bx(o, 0, 0, 3.7, 3.1, 0.2, 2.3, IRON_RUST[0], {"skip": true})
	BX.bx(o, 1.72, 0, 0.06, 1.2, 1.8, 0.0, 0x35604a, {"skip": true})
	return BX.finish(p)
