class_name AustraliaProps
extends RefCounted
## Australia pack ("Hey Mate") arena props for BackyardBbqMap: the Hills Hoist rotary clothesline (a pole plus a spinning hit band,
## PackZones), the BBQ with its glowing hotplate (a burner zone), esky cooler stacks, the kangaroo-spring trampoline pad, wheelie
## bins, a picnic table, garden beds, cricket stumps and the corrugated-iron fence; the fence-line dressing (shed and rainwater tank,
## veggie patch, bin row, woodpile, pot plants, surfboards, kennel, bench, shrubs) and the lawn furniture and toys (outdoor setting,
## camp chairs, sandpit, paddling pool, mower, slip-and-slide, gum trees). Plain boxes in flat colours (see PackMapKit).

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
const SAND := 0xe8d49a
const TERRA := 0xc46a3f
const PUMPKIN := 0xe8862a
const LEAF_D := 0x2f7a3a
const SOIL := 0x5a4330
const WATER := 0x8fd4f2
const SHED_G := 0x4f8a6a
const SHED_D := 0x35604a
const BX := preload("res://dlc/pack_map_kit.gd")


static func palette() -> Array:
	return IRON + IRON_RUST + COOLERS + [POST, GRASS, GRASS_L, GRASS_D, DIRT, PAVER, PAVER_D, STEEL, STEEL_D, WHITE, BBQ_BLACK, HOT, HOT_Y, WOOD, WOOD_D,
		BIN_G, BIN_Y, TRAMP_FRAME, TRAMP_MAT, LINE, SAND, TERRA, PUMPKIN, LEAF_D, 0x9a9a96, 0xc4553a, 0x3a6db5, 0x5a4330, 0x4fa043, 0xe86fa5, 0xe6c34a, 0xe6d3a0, 0xc9b68a, 0x4f8a6a, 0x35604a, 0x3a9ad9, 0x8fd4f2, 0xd8cdb8, 0x5f9a5a, 0x73ad66]


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
	for s: float in [-1.0, 1.0]: BX.bx(o, s * (w / 2.0 + 0.04), 0, 0.08, 0.9, 0.12, 0.5, WHITE, {"skip": true})   # carry handles
	p["tops"].append([-1.0, 0.0, 0.9])
	if tiers >= 2:
		var col2: int = BX.pick(rnd, COOLERS)
		BX.bx(o, 1.1, 0, 1.7, 1.7, 0.65, 0.9, col2)
		BX.bx(o, 1.1, 0, 1.8, 1.8, 0.15, 1.55, WHITE)
		p["tops"].insert(0, [1.1, 0.0, 1.7])
	elif BX.f(rnd) < 0.7:
		BX.bx(o, 1.3, 0.2, 0.7, 0.5, 0.3, 0.9, BX.pick(rnd, [TRAMP_FRAME, 0xc4553a, WOOD]))        # a carton of drinks left on the lid
	return BX.finish(p)


## A small loose esky with a camp stool beside it: low cover you hop over (0.6 m).
static func esky_small(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("esky_s")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 1.5, 1.0, 0.5, 0.0, BX.pick(rnd, COOLERS))
	BX.bx(o, 0, 0, 1.58, 1.08, 0.12, 0.5, WHITE)
	BX.bx(o, 1.35, 0.1, 0.5, 0.5, 0.4, 0.0, BX.pick(rnd, [WOOD, STEEL, BIN_Y]))
	p["tops"].append([0.0, 0.0, 0.62])
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
	BX.bx(o, -3.0, 0, 1.4, 1.5, 0.9, 0.0, WOOD)                                          # the side bench: sauce and a tray of snags
	BX.bx(o, -3.0, 0, 1.6, 1.7, 0.08, 0.9, WOOD_D)
	BX.bx(o, -3.3, -0.3, 0.2, 0.2, 0.34, 0.98, 0xc0392b, {"skip": true})
	BX.bx(o, -3.0, -0.3, 0.2, 0.2, 0.34, 0.98, HOT_Y, {"skip": true})
	BX.bx(o, -2.9, 0.35, 0.8, 0.5, 0.08, 0.98, WHITE, {"skip": true})
	BX.bx(o, 2.75, -0.3, 0.6, 0.6, 0.8, 0.0, 0x3a6db5)                                    # the gas bottle
	BX.bx(o, 2.75, -0.3, 0.3, 0.3, 0.16, 0.8, STEEL, {"skip": true})
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


## A raised garden bed: a timber frame filled with dark earth and green growth (0.5 m: walked over). `fence`: built with its back
## at local x = 0, to stand on the fence line.
static func garden_bed(rnd: Callable, fence := false) -> Dictionary:
	var p := BX.new_prop("bed")
	var o: Array = p["boxes"]
	var w := 4.0 + snappedf(BX.f(rnd) * 2.0, 0.1)
	var cx := 0.9 if fence else 0.0
	BX.bx(o, cx, 0, 1.8, w, 0.5, 0.0, WOOD)
	BX.bx(o, cx, 0, 1.4, w - 0.4, 0.06, 0.5, SOIL)
	for i in int(w / 1.0):
		if BX.f(rnd) < 0.8: BX.bx(o, cx + (BX.f(rnd) - 0.5) * 0.8, (float(i) - float(int(w) - 1) / 2.0) * 0.9, 0.5, 0.5, 0.4, 0.56, BX.pick(rnd, [0x4fa043, 0x3a8f5a, 0xe86fa5, 0xe6c34a]))
	return BX.finish(p)


## Cricket stumps: three thin wooden stumps (0.7 m) with a bail: a low little cover.
static func stumps() -> Dictionary:
	var p := BX.new_prop("stumps")
	var o: Array = p["boxes"]
	for i in 3: BX.bx(o, 0, (float(i) - 1.0) * 0.4, 0.14, 0.14, 0.75, 0.0, 0xe6d3a0)
	BX.bx(o, 0, 0, 0.1, 1.0, 0.06, 0.75, 0xc9b68a)
	BX.bx(o, 3.2, 0, 7.6, 1.5, 0.035, 0.0, 0xc9b68a, {"decal": true})                  # the worn pitch in front of them
	BX.bx(o, 0.9, 0, 0.08, 1.5, 0.045, 0.0, WHITE, {"decal": true})                    # the crease
	BX.bx(o, 1.6, 0.5, 0.85, 0.16, 0.07, 0.0, 0xe6d3a0, {"decal": true})               # the bat, dropped
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
	BX.bx(o, 0, 0, 3.4, 3.4, 0.04, 0.4, WATER)
	BX.bx(o, 0.8, -0.7, 0.42, 0.34, 0.26, 0.44, HOT_Y, {"skip": true})                  # the rubber duck
	BX.bx(o, 0.95, -0.7, 0.24, 0.24, 0.2, 0.7, HOT_Y, {"skip": true})
	BX.bx(o, 1.12, -0.7, 0.12, 0.14, 0.07, 0.74, HOT, {"skip": true})
	BX.bx(o, -0.8, 0.7, 1.1, 1.1, 0.16, 0.44, 0xe86fa5, {"skip": true})                 # the swim ring
	BX.bx(o, -0.8, 0.7, 0.5, 0.5, 0.17, 0.44, WATER, {"skip": true})
	p["tops"].append([0.0, 0.0, 0.44])
	return BX.finish(p)


## A gum tree: a pale trunk (0.9 m, a pillar) and a green canopy hanging at 3.4 m (never a platform: above a jump, below a high leap),
## a low branch stub, bark litter on the lawn and, sometimes, a sitting log beside it (a 0.5 m step).
static func gum_tree(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("gum")
	var o: Array = p["boxes"]
	var S := {"skip": true}
	BX.bx(o, 0, 0, 0.9, 0.9, 3.5, 0.0, 0xd8cdb8, S)
	BX.bx(o, 0, 0, 1.2, 1.2, 0.3, 0.0, 0xc9b68a, S)                                      # the root flare
	BX.bx(o, 0, 0, 4.6, 4.6, 1.3, 3.4, 0x5f9a5a, S)
	BX.bx(o, 0.4, -0.3, 3.0, 3.0, 1.0, 4.7, 0x73ad66, S)
	var sx := 1.0 if BX.f(rnd) < 0.5 else -1.0
	BX.bx(o, sx * 2.1, 1.2, 2.2, 2.4, 0.9, 3.7, 0x73ad66, S)                             # side clumps
	BX.bx(o, -sx * 1.9, -1.6, 2.4, 2.0, 0.8, 3.55, 0x4f8a6a, S)
	BX.bx(o, -0.3, 0.2, 1.6, 1.6, 0.6, 5.7, 0x5f9a5a, S)
	BX.bx(o, 0, 0, 3.6, 3.2, 0.03, 0.0, DIRT, {"decal": true})                           # bark and leaf litter
	if BX.f(rnd) < 0.6:
		BX.bx(o, sx * 1.7, 0.3, 0.6, 2.0, 0.5, 0.0, WOOD_D)                              # a sitting log
		BX.bx(o, sx * 1.7, 1.31, 0.5, 0.03, 0.4, 0.05, 0xe6d3a0, S)
	return BX.finish(p)


# ---------------------------------------------------------------- fence-line props (back at local x = 0, the front faces +x)

## The garden shed against the fence: 3.2 m deep, 4.2 m wide, 2.4 m high (a pillar: too tall to jump on), green walls, a rusty iron
## roof, a door and a window, with a corrugated rainwater tank beside it.
static func shed() -> Dictionary:
	var p := BX.new_prop("shed")
	var o: Array = p["boxes"]
	var S := {"skip": true}
	BX.bx(o, 1.6, 0, 3.2, 4.2, 2.4, 0.0, SHED_G, S)
	BX.bx(o, 1.8, 0, 3.6, 4.6, 0.18, 2.4, IRON_RUST[0], S)
	BX.bx(o, 1.1, 0, 2.2, 4.6, 0.16, 2.58, IRON_RUST[2], S)
	BX.bx(o, 3.22, -0.8, 0.06, 1.1, 1.9, 0.0, SHED_D, S)                                # the door
	BX.bx(o, 3.25, -0.4, 0.06, 0.1, 0.1, 0.95, HOT_Y, S)
	BX.bx(o, 3.22, 1.0, 0.06, 1.0, 0.7, 1.1, WATER, S)                                  # the window
	BX.bx(o, 3.24, 1.0, 0.06, 1.2, 0.1, 1.0, WHITE, S)
	BX.bx(o, 1.0, 3.3, 1.8, 1.8, 2.0, 0.0, IRON[3], S)                                  # the rainwater tank
	BX.bx(o, 1.0, 3.3, 1.5, 1.5, 0.14, 2.0, IRON[1], S)
	BX.bx(o, 2.0, 3.3, 0.2, 0.2, 0.2, 0.35, STEEL_D, S)
	return BX.finish(p)


## The fence-line veggie patch: a long timber bed (0.4 m: walked over) with staked tomatoes at the back, a row of greens and
## pumpkins at the front.
static func veggie_patch(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("veggie")
	var o: Array = p["boxes"]
	var S := {"skip": true}
	var w := 7.0 + snappedf(BX.f(rnd) * 2.0, 0.1)
	BX.bx(o, 1.1, 0, 2.2, w, 0.4, 0.0, WOOD)
	BX.bx(o, 1.1, 0, 1.9, w - 0.3, 0.06, 0.4, SOIL)
	var n := 4
	for i in n:
		var z := (float(i) - float(n - 1) / 2.0) * (w - 1.4) / float(n - 1)
		BX.bx(o, 0.45, z, 0.1, 0.1, 1.4, 0.46, WOOD_D, S)                                # the stake
		BX.bx(o, 0.45, z, 0.6, 0.6, 0.8, 0.46, LEAF_D if i % 2 == 0 else 0x4fa043, S)
		BX.bx(o, 0.74, z + 0.15, 0.18, 0.18, 0.18, 0.8 + BX.f(rnd) * 0.3, 0xc0392b, S)
	BX.bx(o, 1.15, 0, 0.4, w - 1.0, 0.22, 0.46, 0x73ad66, S)                             # the lettuce row
	for i in 3:
		BX.bx(o, 1.75, (float(i) - 1.0) * (w / 3.2) + (BX.f(rnd) - 0.5) * 0.6, 0.45, 0.5, 0.34, 0.46, PUMPKIN, S)
	BX.bx(o, 1.75, w / 2.0 - 0.6, 0.1, 0.5, 0.5, 0.46, WHITE, S)                         # the seed-packet sign
	return BX.finish(p)


## Three wheelie bins lined up on the fence: dark green bodies, red / yellow / green lids (1.1 m: a jump).
static func bin_row() -> Dictionary:
	var p := BX.new_prop("bins")
	var o: Array = p["boxes"]
	var lids := [0xc0392b, BIN_Y, 0x4fa043]
	for i in 3:
		var z := (float(i) - 1.0) * 1.2
		BX.bx(o, 0.5, z, 0.9, 1.0, 1.0, 0.0, SHED_D)
		BX.bx(o, 0.52, z, 1.0, 1.08, 0.12, 1.0, lids[i])
	p["tops"].append([0.5, 0.0, 1.12])
	return BX.finish(p)


## A woodpile for the fire pit: stacked logs (1.15 m), pale cut ends, and a chopping block.
static func woodpile() -> Dictionary:
	var p := BX.new_prop("woodpile")
	var o: Array = p["boxes"]
	BX.bx(o, 0.45, 0, 0.9, 2.8, 0.9, 0.0, WOOD_D)
	BX.bx(o, 0.45, 0, 0.8, 2.2, 0.25, 0.9, WOOD)
	for i in 4: BX.bx(o, 0.92, (float(i) - 1.5) * 0.66, 0.04, 0.4, 0.4, 0.1 + 0.35 * float(i % 2), 0xe6d3a0, {"skip": true})
	BX.bx(o, 1.7, 0.7, 0.6, 0.6, 0.45, 0.0, 0xc9b68a)                                    # the chopping block
	return BX.finish(p)


## Pot plants along the fence: terracotta pots, a lemon tree in the middle one.
static func pots(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("pots")
	var o: Array = p["boxes"]
	var S := {"skip": true}
	for i in 3:
		var z := (float(i) - 1.0) * 1.3
		BX.bx(o, 0.5, z, 0.7, 0.7, 0.5, 0.0, TERRA)
		if i == 1:
			BX.bx(o, 0.5, z, 0.14, 0.14, 0.9, 0.5, WOOD_D, S)
			BX.bx(o, 0.6, z, 1.2, 1.3, 0.9, 1.3, LEAF_D, S)
			BX.bx(o, 1.22, z - 0.3, 0.16, 0.16, 0.16, 1.45, HOT_Y, S)
			BX.bx(o, 1.22, z + 0.35, 0.16, 0.16, 0.16, 1.7, HOT_Y, S)
		else:
			BX.bx(o, 0.5, z, 0.55, 0.55, 0.45, 0.5, BX.pick(rnd, [0x4fa043, 0xe86fa5, 0x73ad66]), S)
	return BX.finish(p)


## Surfboards and a boogie board leaning on the fence, with the hose reel.
static func surf_rack(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("surf")
	var o: Array = p["boxes"]
	var S := {"skip": true}
	var cols := [0xe86fa5, TRAMP_FRAME, 0x3a9ad9, WHITE, 0x2f9a6a]
	var k := int(BX.f(rnd) * 5.0)
	BX.bx(o, 0.1, -0.7, 0.16, 0.56, 2.3, 0.0, cols[k % 5], S)
	BX.bx(o, 0.19, -0.7, 0.04, 0.14, 2.1, 0.1, cols[(k + 3) % 5], S)                      # the stringer stripe
	BX.bx(o, 0.1, 0.0, 0.16, 0.56, 2.0, 0.0, cols[(k + 1) % 5], S)
	BX.bx(o, 0.1, 0.75, 0.16, 0.66, 1.1, 0.0, cols[(k + 2) % 5], S)
	BX.bx(o, 0.22, 1.7, 0.4, 0.7, 0.7, 0.0, LEAF_D)                                       # the hose reel
	BX.bx(o, 0.45, 1.7, 0.08, 0.45, 0.45, 0.12, HOT_Y, S)
	return BX.finish(p)


## The dog kennel: a red box with a dark roof and a water bowl (1.2 m: a jump).
static func kennel() -> Dictionary:
	var p := BX.new_prop("kennel")
	var o: Array = p["boxes"]
	BX.bx(o, 0.7, 0, 1.4, 1.3, 0.95, 0.0, 0xc0392b)
	BX.bx(o, 0.8, 0, 1.6, 1.5, 0.25, 0.95, STEEL_D)
	BX.bx(o, 1.41, 0, 0.04, 0.6, 0.65, 0.0, BBQ_BLACK, {"skip": true})
	BX.bx(o, 2.0, 0.6, 0.36, 0.36, 0.14, 0.0, STEEL, {"skip": true})
	p["tops"].append([0.8, 0.0, 1.2])
	return BX.finish(p)


## A garden bench against the fence (a 0.45 m seat: a step).
static func bench() -> Dictionary:
	var p := BX.new_prop("bench")
	var o: Array = p["boxes"]
	BX.bx(o, 0.45, 0, 0.6, 2.2, 0.45, 0.0, WOOD)
	BX.bx(o, 0.1, 0, 0.14, 2.2, 0.55, 0.45, WOOD_D, {"skip": true})
	for s: float in [-1.0, 1.0]: BX.bx(o, 0.42, s * 1.14, 0.7, 0.1, 0.22, 0.45, WOOD_D, {"skip": true})
	return BX.finish(p)


# ---------------------------------------------------------------- lawn furniture and toys

## The outdoor setting: a table (0.8 m) under a striped sun umbrella (its canopy at 3.15 m, clear of a fighter standing on the table)
## with four white plastic chairs round it.
static func setting(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("setting")
	var o: Array = p["boxes"]
	var S := {"skip": true}
	BX.bx(o, 0, 0, 0.5, 0.5, 0.72, 0.0, STEEL)
	BX.bx(o, 0, 0, 1.7, 1.7, 0.1, 0.72, WHITE)
	BX.bx(o, 0, 0, 0.12, 0.12, 2.35, 0.82, STEEL_D, S)                                   # the umbrella pole
	var uc: int = BX.pick(rnd, [0xc0392b, 0x2f6db5, 0x2f9a6a, TRAMP_FRAME])
	BX.bx(o, 0, 0, 3.4, 3.4, 0.16, 3.15, uc, S)
	BX.bx(o, 0, 0, 3.42, 1.1, 0.17, 3.15, WHITE, S)                                      # the stripe
	BX.bx(o, 0, 0, 1.6, 1.6, 0.22, 3.31, uc, S)
	for i in 4:
		var c := BX.rot_xz(1.45, 0.0, i)
		var b := BX.rot_xz(1.72, 0.0, i)
		BX.bx(o, c.x, c.y, 0.6, 0.6, 0.45, 0.0, WHITE)
		BX.bx(o, b.x, b.y, 0.12 if i % 2 == 0 else 0.6, 0.6 if i % 2 == 0 else 0.12, 0.5, 0.45, WHITE, S)
	if BX.f(rnd) < 0.7: BX.bx(o, 0.4, -0.35, 0.3, 0.3, 0.22, 0.82, BX.pick(rnd, [HOT_Y, 0xc4553a, 0x3a9ad9]), S)
	p["tops"].append([-0.45, 0.45, 0.82])
	return BX.finish(p)


## Two folding camp chairs facing each other over a little esky: low cover for one.
static func camp_chairs(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("chairs")
	var o: Array = p["boxes"]
	for s: float in [-1.0, 1.0]:
		var col: int = BX.pick(rnd, [0x2f9a6a, 0x2f6db5, 0xc0392b, TRAMP_FRAME])
		BX.bx(o, s * 1.0, 0, 0.6, 0.65, 0.42, 0.0, col)
		BX.bx(o, s * 1.32, 0, 0.1, 0.65, 0.5, 0.42, col, {"skip": true})
	BX.bx(o, 0, 0.1, 0.6, 0.45, 0.36, 0.0, BX.pick(rnd, COOLERS))
	BX.bx(o, 0, 0.1, 0.66, 0.5, 0.08, 0.36, WHITE)
	return BX.finish(p)


## The sandpit: a timber frame (0.3 m: walked over) full of sand, a sandcastle, a bucket and a spade.
static func sandpit(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("sandpit")
	var o: Array = p["boxes"]
	var S := {"skip": true}
	BX.bx(o, 0, 0, 3.8, 3.8, 0.3, 0.0, WOOD)
	BX.bx(o, 0, 0, 3.3, 3.3, 0.05, 0.3, SAND)
	var sx := 1.0 if BX.f(rnd) < 0.5 else -1.0
	BX.bx(o, sx * 0.7, -0.6, 0.9, 0.9, 0.3, 0.35, 0xe6d3a0, S)                           # the sandcastle
	BX.bx(o, sx * 0.7, -0.6, 0.45, 0.45, 0.28, 0.65, 0xe6d3a0, S)
	BX.bx(o, sx * 0.7, -0.6, 0.06, 0.06, 0.3, 0.93, WOOD_D, S)
	BX.bx(o, sx * 0.82, -0.6, 0.2, 0.04, 0.14, 1.09, 0xc0392b, S)                        # its flag
	BX.bx(o, -sx * 0.8, 0.7, 0.4, 0.4, 0.36, 0.35, 0xc0392b, S)                          # the bucket
	BX.bx(o, -sx * 0.2, 1.0, 0.7, 0.14, 0.06, 0.35, 0x3a9ad9, S)                         # the spade
	p["tops"].append([0.0, 0.3, 0.35])
	return BX.finish(p)


## The lawn mower, left out: a red deck, the engine, a grass catcher and the handle (0.95 m: low cover).
static func mower() -> Dictionary:
	var p := BX.new_prop("mower")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 1.1, 0.75, 0.36, 0.0, 0xc0392b)
	BX.bx(o, 0.15, 0, 0.45, 0.45, 0.3, 0.36, BBQ_BLACK, {"skip": true})
	BX.bx(o, -0.85, 0, 0.6, 0.7, 0.5, 0.05, LEAF_D)
	BX.bx(o, -1.2, 0, 0.1, 0.7, 0.95, 0.0, STEEL, {"skip": true})
	return BX.finish(p)


## The slip-and-slide: a long yellow sheet on the lawn (flat: nothing to hide behind) with a blue splash end.
static func slide_mat() -> Dictionary:
	var p := BX.new_prop("slide")
	var o: Array = p["boxes"]
	BX.bx(o, 0, 0, 8.0, 1.8, 0.04, 0.0, HOT_Y)
	BX.bx(o, 0, 0, 8.0, 0.5, 0.05, 0.0, TRAMP_FRAME)
	BX.bx(o, 4.6, 0, 1.4, 2.2, 0.06, 0.0, 0x3a9ad9)
	BX.bx(o, 4.6, 0, 0.9, 1.6, 0.07, 0.0, WATER)
	return BX.finish(p)


## A shrub or a clump of flowers in the border along the fence (0.5 - 0.8 m, a soft little bump of colour).
static func shrub(rnd: Callable) -> Dictionary:
	var p := BX.new_prop("shrub")
	var o: Array = p["boxes"]
	var h := 0.5 + snappedf(BX.f(rnd) * 0.3, 0.05)
	BX.bx(o, 0.45, 0, 0.8, 0.9, h, 0.0, BX.pick(rnd, [LEAF_D, 0x4fa043, 0x5f9a5a, BIN_G]), {"skip": true})
	if BX.f(rnd) < 0.6: BX.bx(o, 0.5, (BX.f(rnd) - 0.5) * 0.4, 0.4, 0.4, 0.16, h, BX.pick(rnd, [0xe86fa5, HOT_Y, WHITE, 0xc0392b]), {"skip": true})
	return BX.finish(p)
