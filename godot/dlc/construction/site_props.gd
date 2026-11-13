class_name SiteProps
extends RefCounted
## Construction DLC: the props of the generated Building Site (SiteMap), each a cluster of plain collision boxes
## ({x, z, w, d, h, y, color} like shared/maps.json), ladders and bounce pads, so physics needs nothing new.
##
## Every prop is built in its own local frame (front = +x, origin near the middle) and put on the yard with place(),
## which rotates it by a multiple of 90 degrees and moves it. A prop is a Dictionary:
##   kind, machine (a big machine: kept 6 m from the others), boxes, ladders, pads,
##   tops [[x, z, y]] (spots on its roof/deck a crate can sit on), lrect [x0, z0, x1, z1] (everything it needs to be left
##   free, including the foot of each ladder), and after place(): rect (the same, in yard coordinates).
## Jump rules the props are built to (FighterPhysics: jump 9.2 m/s at GRAV 24 = 1.76 m of lift, STEP 0.55 more on landing):
## a step up of 2.0 m or less can be jumped, 0.55 m or less is walked, taller needs a ladder, a stepped ramp or a pad.

const YELLOW := 0xf2c230
const YELLOW_D := 0xd9a21b
const ORANGE := 0xff7a1a
const ORANGE_D := 0xe0701f
const RED := 0xc0392b
const BLUE := 0x2f6db5
const GREEN := 0x3a8f5a
const WHITE := 0xe9ecee
const STEEL := 0x7a8590
const STEEL_D := 0x4a4f55
const DARK := 0x2a2f36
const GLASS := 0x5f93aa
const CONCRETE := 0x9aa0a6
const CONCRETE_D := 0x7d848b
const SAND := 0xd8c090
const PANEL := 0x6a7480
const BRICK := 0xb5523b
const DIRT := [0x8a6a45, 0x7c5d3b, 0x9b7a52, 0x6f5236, 0x8b8f93, 0xa08560]   ## spoil: browns and gravel grey
const PIPES := [0x9aa0a6, 0x7a8590, 0xe07a1f, 0x3b73b9, 0x2f343a, 0xc9ccd0]
const CONTAINERS := [0xc0392b, 0x2f6db5, 0x3a8f5a, 0xd9a21b, 0xe0701f, 0x7a8590]
const FENCE_H := 2.8          ## taller than anyone can jump (1.76 + 0.55): the perimeter is never a platform
const WALK := 0.55            ## FighterPhysics.STEP
const MAX_RISE := 2.0         ## the highest step the props ask for a jump to climb


## Every colour a prop uses (the construction palette: safety yellow and orange, steel and concrete greys, dirt browns, a
## little red / blue / green on containers and pipes, glass).
static func palette() -> Array:
	var out: Array = [YELLOW, YELLOW_D, ORANGE, ORANGE_D, RED, BLUE, GREEN, WHITE, STEEL, STEEL_D, DARK, GLASS, CONCRETE, CONCRETE_D,
		SAND, PANEL, BRICK, 0x8da3b5, 0xc9a46a, 0xb89a5a, 0xa8884a]
	for list: Array in [DIRT, PIPES, CONTAINERS]: out.append_array(list)
	return out


static func _new(kind: String, machine := false) -> Dictionary:
	return {"kind": kind, "machine": machine, "boxes": [], "ladders": [], "pads": [], "tops": []}


static func _bx(o: Array, x: float, z: float, w: float, d: float, h: float, y: float, color: int) -> void:
	o.append({"x": x, "z": z, "w": w, "d": d, "h": h, "y": y, "color": color})


## Steps rising toward (dx, dz) (one of the four axis directions) from (x0, z0): n steps, each `run` long and `width` wide,
## the last one `top` high. They are plain boxes standing on the floor.
static func _stairs(o: Array, x0: float, z0: float, dx: float, dz: float, n: int, top: float, run: float, width: float, c1: int, c2: int) -> void:
	for k in range(1, n + 1):
		var along := (k - 0.5) * run
		var cx := x0 + dx * along
		var cz := z0 + dz * along
		var h := top * float(k) / float(n)
		if dx != 0.0: _bx(o, cx, cz, run, width, h, 0.0, c1 if k % 2 == 0 else c2)
		else: _bx(o, cx, cz, width, run, h, 0.0, c1 if k % 2 == 0 else c2)


# ---------------------------------------------------------------- placing

static func rot_xz(x: float, z: float, rot: int) -> Vector2:
	match rot & 3:
		1: return Vector2(-z, x)
		2: return Vector2(-x, -z)
		3: return Vector2(z, -x)
	return Vector2(x, z)


## [x0, z0, x1, z1] of a local rect turned by `rot`.
static func rot_rect(r: Array, rot: int) -> Array:
	var a := rot_xz(float(r[0]), float(r[1]), rot)
	var b := rot_xz(float(r[2]), float(r[3]), rot)
	return [minf(a.x, b.x), minf(a.y, b.y), maxf(a.x, b.x), maxf(a.y, b.y)]


static func _f(rnd: Callable) -> float:
	return float(rnd.call())


static func _r3(v: float) -> float:
	return snappedf(v, 0.001)


## The prop turned by `rot` quarter turns and moved to (x, z). Returns a new Dictionary with `rect` set.
static func place(p: Dictionary, x: float, z: float, rot: int) -> Dictionary:
	var q := _new(str(p["kind"]), bool(p["machine"]))
	var bs: Array = q["boxes"]
	for b: Dictionary in p["boxes"]:
		var c := rot_xz(float(b["x"]), float(b["z"]), rot)
		var odd := (rot & 1) == 1
		bs.append({"x": _r3(x + c.x), "z": _r3(z + c.y), "w": float(b["d"]) if odd else float(b["w"]), "d": float(b["w"]) if odd else float(b["d"]),
			"h": float(b["h"]), "y": float(b["y"]), "color": int(b["color"])})
	for l: Dictionary in p["ladders"]:
		var c := rot_xz(float(l["x"]), float(l["z"]), rot)
		var n := rot_xz(float(l["nx"]), float(l["nz"]), rot)
		q["ladders"].append({"x": _r3(x + c.x), "z": _r3(z + c.y), "nx": n.x, "nz": n.y, "y0": float(l["y0"]), "y1": float(l["y1"])})
	for pd: Dictionary in p["pads"]:
		var c := rot_xz(float(pd["x"]), float(pd["z"]), rot)
		q["pads"].append({"x": _r3(x + c.x), "z": _r3(z + c.y), "r": float(pd["r"]), "power": float(pd["power"])})
	for t: Array in p["tops"]:
		var c := rot_xz(float(t[0]), float(t[1]), rot)
		q["tops"].append([_r3(x + c.x), _r3(z + c.y), float(t[2])])
	var lr := rot_rect(p["lrect"], rot)
	q["lrect"] = p["lrect"]
	q["rect"] = [x + lr[0], z + lr[1], x + lr[2], z + lr[3]]
	return q


## lrect: the boxes' footprint plus the ground in front of every ladder and bounce pad.
static func _finish(p: Dictionary) -> Dictionary:
	var x0 := 1e9
	var z0 := 1e9
	var x1 := -1e9
	var z1 := -1e9
	for b: Dictionary in p["boxes"]:
		x0 = minf(x0, float(b["x"]) - float(b["w"]) / 2.0); x1 = maxf(x1, float(b["x"]) + float(b["w"]) / 2.0)
		z0 = minf(z0, float(b["z"]) - float(b["d"]) / 2.0); z1 = maxf(z1, float(b["z"]) + float(b["d"]) / 2.0)
	for l: Dictionary in p["ladders"]:
		var sx := float(l["x"]) + float(l["nx"]) * 0.55
		var sz := float(l["z"]) + float(l["nz"]) * 0.55
		x0 = minf(x0, sx - 1.0); x1 = maxf(x1, sx + 1.0); z0 = minf(z0, sz - 1.0); z1 = maxf(z1, sz + 1.0)
	for pd: Dictionary in p["pads"]:
		x0 = minf(x0, float(pd["x"]) - 1.6); x1 = maxf(x1, float(pd["x"]) + 1.6); z0 = minf(z0, float(pd["z"]) - 1.6); z1 = maxf(z1, float(pd["z"]) + 1.6)
	p["lrect"] = [x0, z0, x1, z1]
	return p


# ---------------------------------------------------------------- the machines

## Tracked excavator: tracks, house, counterweight, cab with glass, a three-piece boom and a bucket on the ground.
## Climb: rear steps to the track, then jumps (track 1.2 -> house 2.6 -> cab roof 4.25).
static func excavator(col := YELLOW) -> Dictionary:
	var p := _new("excavator", true)
	var o: Array = p["boxes"]
	for s in [-1.0, 1.0]:
		_bx(o, 0, s * 2.0, 6.6, 1.4, 1.2, 0.0, DARK)                      # tracks
		_bx(o, 3.2, s * 2.0, 0.5, 1.2, 0.8, 0.0, STEEL_D)                 # sprockets
	_bx(o, 0, 0, 5.6, 2.6, 1.2, 0.0, STEEL_D)                             # undercarriage
	_bx(o, -0.4, 0, 5.0, 4.2, 1.4, 1.2, col)                              # house, top 2.6
	_bx(o, -3.3, 0, 1.6, 3.0, 1.4, 1.2, STEEL_D)                          # counterweight
	_bx(o, 0.5, -1.0, 2.0, 2.0, 1.5, 2.6, col)                            # cab
	_bx(o, 1.52, -1.0, 0.06, 1.5, 0.8, 3.1, GLASS)
	_bx(o, 0.5, -2.02, 1.4, 0.06, 0.8, 3.1, GLASS)
	_bx(o, 0.5, -1.0, 2.4, 2.4, 0.15, 4.1, STEEL_D)                       # cab roof, top 4.25
	_bx(o, 2.4, 1.0, 2.6, 0.9, 0.7, 2.8, col)                             # boom
	_bx(o, 4.7, 1.0, 2.4, 0.8, 0.7, 3.3, col)
	_bx(o, 5.9, 1.0, 0.8, 0.8, 3.1, 0.9, YELLOW_D)                        # stick
	_bx(o, 6.5, 1.0, 1.8, 1.8, 0.9, 0.0, YELLOW_D)                        # bucket
	_bx(o, 7.45, 1.0, 0.2, 1.8, 0.35, 0.0, STEEL_D)                       # teeth
	_stairs(o, -5.1, 2.1, 1.0, 0.0, 3, 1.2, 0.6, 1.0, STEEL, CONCRETE_D)  # rear steps up to the +z track
	p["tops"].append([-0.4, 1.6, 2.6])
	return _finish(p)


## Bulldozer: tracks, body, hood with a grille and an exhaust stack, cab with glass, push blade on arms, ripper.
static func bulldozer(col := YELLOW) -> Dictionary:
	var p := _new("bulldozer", true)
	var o: Array = p["boxes"]
	for s in [-1.0, 1.0]:
		_bx(o, 0, s * 1.75, 5.2, 1.1, 1.15, 0.0, DARK)
		_bx(o, 2.95, s * 1.75, 0.7, 0.35, 0.5, 0.35, STEEL_D)             # push arms
	_bx(o, 0, 0, 4.6, 2.4, 1.15, 0.0, STEEL_D)
	_bx(o, -0.5, 0, 3.6, 2.8, 0.9, 1.15, col)                             # body, top 2.05
	_bx(o, 1.7, 0, 1.9, 2.0, 0.55, 1.15, col)                             # hood
	_bx(o, 2.66, 0, 0.06, 1.6, 0.4, 1.2, DARK)
	_bx(o, 1.5, 0.6, 0.25, 0.25, 1.1, 1.7, DARK)                          # exhaust stack
	_bx(o, -1.0, 0, 2.0, 2.4, 1.5, 2.05, col)                             # cab
	_bx(o, 0.03, 0, 0.06, 1.8, 0.8, 2.5, GLASS)
	for s in [-1.0, 1.0]: _bx(o, -1.0, s * 1.23, 1.4, 0.06, 0.8, 2.5, GLASS)
	_bx(o, -1.0, 0, 2.6, 2.8, 0.15, 3.55, STEEL_D)                        # roof, top 3.7
	_bx(o, 3.5, 0, 0.5, 4.6, 1.35, 0.0, YELLOW_D)                         # blade
	_bx(o, 3.45, 0, 0.7, 4.6, 0.2, 1.35, STEEL_D)
	_bx(o, -3.0, 0, 0.6, 2.0, 0.9, 0.0, STEEL_D)                          # ripper
	_stairs(o, -4.4, 1.75, 1.0, 0.0, 3, 1.15, 0.6, 1.0, STEEL, CONCRETE_D)
	p["tops"].append([0.4, 0.0, 2.05])
	return _finish(p)


## Tower crane: a ladder up the tower to the turntable, a jib with rails, a counter-jib with a counterweight, an operator
## cab, and a load hanging on a cable above a bounce pad's reach (the pad lifts you onto the load).
static func crane(rnd: Callable, col := YELLOW) -> Dictionary:
	var p := _new("crane", true)
	var o: Array = p["boxes"]
	var H := 12.0 + float(int(_f(rnd) * 4.0))                           # tower top 12..15
	var top := H + 0.25                                                   # turntable top = where the ladder ends
	_bx(o, 0, 0, 2.4, 2.4, 0.3, 0.0, CONCRETE)                            # foot
	_bx(o, 0, 0, 2.0, 2.0, H * 0.5, 0.0, col)                             # tower
	_bx(o, 0, 0, 2.0, 2.0, H * 0.5, H * 0.5, YELLOW_D if col == YELLOW else col)
	_bx(o, 0, 0, 2.0, 2.0, 0.25, H, DARK)                                 # turntable
	_bx(o, 6.5, 0, 13.0, 1.2, 0.3, top, col)                              # jib walkway, top H + 0.55
	_bx(o, -2.5, 0, 5.0, 1.2, 0.3, top, col)                              # counter-jib
	for s in [-1.0, 1.0]:
		_bx(o, 7.0, s * 0.56, 12.0, 0.1, 0.95, top + 0.3, STEEL_D)        # jib rails
	_bx(o, -4.2, 0, 1.6, 1.8, 1.4, top + 0.3, CONCRETE_D)                 # counterweight
	_bx(o, 0.95, -1.3, 1.7, 1.4, 1.5, top, col)                           # operator cab
	_bx(o, 0.95, -2.02, 1.2, 0.06, 0.7, top + 0.5, GLASS)
	var lx := 10.5
	var load_col: int = [BRICK, STEEL, ORANGE_D, BLUE][int(_f(rnd) * 4.0)]
	_bx(o, lx, 0, 2.6, 2.2, 1.2, 3.2, load_col)                           # the hanging load, top 4.4
	_bx(o, lx, 0, 0.14, 0.14, top - 4.4, 4.4, DARK)                       # cable
	p["ladders"].append({"x": 0.0, "z": 1.0, "nx": 0.0, "nz": 1.0, "y0": 0.0, "y1": top})
	p["pads"].append({"x": 7.0, "z": 0.0, "r": 1.2, "power": 17.0})
	p["tops"].append([lx - 0.9, 0.7, 4.4])
	return _finish(p)


# ---------------------------------------------------------------- piles, stacks, boxes

## Stepped mound of spoil: tiers 0.5 m high (walkable all the way up), browns and a little gravel grey.
static func spoil_heap(rnd: Callable) -> Dictionary:
	var p := _new("heap")
	var o: Array = p["boxes"]
	var w := 6.5 + _f(rnd) * 2.5
	var d := 5.0 + _f(rnd) * 2.5
	var n := 4 if w > 7.6 else 3
	var cx := 0.0
	var cz := 0.0
	var pal: Array = DIRT.duplicate()
	var pick := int(_f(rnd) * 3.0)
	for i in n:
		var col: int = pal[(pick + i * 2) % pal.size()] if _f(rnd) < 0.8 else DIRT[4]
		_bx(o, _r3(cx), _r3(cz), _r3(w), _r3(d), 0.5, 0.5 * i, col)
		cx += (_f(rnd) - 0.5) * 0.6
		cz += (_f(rnd) - 0.5) * 0.6
		w = maxf(1.6, w - 1.6 - _f(rnd) * 0.4)
		d = maxf(1.4, d - 1.4 - _f(rnd) * 0.4)
	p["tops"].append([_r3(cx), _r3(cz), 0.5 * n])
	return _finish(p)


## Stack of pipes lying along z: 3 layers of 0.9 m pipes in a pyramid (each layer a jump up), mixed colours.
static func pipe_stack(rnd: Callable) -> Dictionary:
	var p := _new("pipes")
	var o: Array = p["boxes"]
	var n0 := 3 + int(_f(rnd) * 3.0)                                   # 3..5 on the bottom
	var layers := 2 + int(_f(rnd) * 2.0)                               # 2..3
	var ln := 4.0 + float(int(_f(rnd) * 3.0))
	var pal0 := int(_f(rnd) * PIPES.size())
	for L in layers:
		var cnt := n0 - L
		if cnt < 1: break
		for i in cnt:
			var x := (float(i) - float(cnt - 1) / 2.0) * 0.95
			_bx(o, _r3(x), 0.0, 0.9, ln, 0.9, 0.9 * L, PIPES[(pal0 + i + L * 2) % PIPES.size()])
	_bx(o, 0, -ln / 2.0 + 0.5, float(n0) * 0.95, 0.25, 0.12, 0.0, 0x8a6a45)   # timber bearers
	return _finish(p)


## Shipping container 6 x 2.4 x 2.6, one or two high. A ladder on one short end climbs it (to 5.2 m when stacked).
static func container(rnd: Callable, stacked := false) -> Dictionary:
	var p := _new("container")
	var o: Array = p["boxes"]
	var col: int = CONTAINERS[int(_f(rnd) * CONTAINERS.size())]
	var n := 2 if stacked else 1
	for k in n:
		var c: int = col if k == 0 else CONTAINERS[int(_f(rnd) * CONTAINERS.size())]
		_bx(o, 0, 0, 6.0, 2.4, 2.6, 2.6 * k, c)
		_bx(o, 3.03, 0, 0.12, 2.1, 2.2, 2.6 * k + 0.2, DARK)               # doors at the +x end
	p["ladders"].append({"x": -3.0, "z": 0.0, "nx": -1.0, "nz": 0.0, "y0": 0.0, "y1": 2.6 * n})
	p["tops"].append([0.5, 0.0, 2.6 * n])
	return _finish(p)


## The siteyard scaffold tower (5 x 5 hoarding, 5.4 m deck, grey panels) with handrails on three sides. Low ones (deck 3.05 m
## or less) have steps up the open side, the tall ones a ladder.
static func scaffold(rnd: Callable) -> Dictionary:
	var p := _new("scaffold")
	var o: Array = p["boxes"]
	var hh: float = [2.8, 3.6, 4.2][int(_f(rnd) * 3.0)]
	var deck := hh + 0.25
	_bx(o, 0, 0, 5.0, 5.0, hh, 0.0, SAND)
	_bx(o, 0, 0, 5.4, 5.4, 0.25, hh, YELLOW)
	_bx(o, -2.6, 0, 0.25, 5.2, hh, 0.0, PANEL)
	_bx(o, 2.6, 0, 0.25, 5.2, hh, 0.0, PANEL)
	_bx(o, 0, -2.6, 5.2, 0.25, hh, 0.0, PANEL)
	_bx(o, 0, 2.6, 5.2, 0.25, hh, 0.0, PANEL)
	_bx(o, 2.65, 0, 0.12, 5.4, 0.95, deck, STEEL_D)                       # rails: +x, +-z, and two stubs on the open -x side
	for s in [-1.0, 1.0]:
		_bx(o, 0, s * 2.65, 5.4, 0.12, 0.95, deck, STEEL_D)
		_bx(o, -2.65, s * 2.0, 0.12, 1.4, 0.95, deck, STEEL_D)
	if deck <= 3.1:
		var n := int(ceil(deck / 0.5 - 1e-6))
		_stairs(o, -2.725 - float(n) * 0.8, 0.0, 1.0, 0.0, n, deck, 0.8, 2.4, 0xb89a5a, 0xa8884a)
	else:
		p["ladders"].append({"x": -2.725, "z": 0.0, "nx": -1.0, "nz": 0.0, "y0": 0.0, "y1": deck})
	p["tops"].append([0.5, 0.0, deck])
	return _finish(p)


## Sunken-looking trench: two spoil banks (0.5 then 1.0 m) with a 3.6 m channel between, handrails along the channel with a
## gap, and a bounce pad in the channel that throws you up onto the banks and the cover around.
static func trench(rnd: Callable) -> Dictionary:
	var p := _new("trench")
	var o: Array = p["boxes"]
	var L := 10.0 + float(int(_f(rnd) * 3.0)) * 2.0
	var ci := int(_f(rnd) * 3.0)
	for s in [-1.0, 1.0]:
		_bx(o, 0, s * 3.9, L, 1.8, 0.5, 0.0, DIRT[(ci + (1 if s > 0 else 0)) % 4])
		_bx(o, 0, s * 2.4, L, 1.2, 1.0, 0.0, DIRT[(ci + 2) % 4])
	var g := (_f(rnd) - 0.5) * (L - 6.0)                                # the rail gap
	for s in [-1.0, 1.0]:
		var a0 := -L / 2.0 + 0.3
		var a1 := g - 1.5
		var b0 := g + 1.5
		var b1 := L / 2.0 - 0.3
		if a1 - a0 > 0.5: _bx(o, _r3((a0 + a1) / 2.0), s * 1.95, _r3(a1 - a0), 0.1, 0.95, 1.0, YELLOW)
		if b1 - b0 > 0.5: _bx(o, _r3((b0 + b1) / 2.0), s * 1.95, _r3(b1 - b0), 0.1, 0.95, 1.0, YELLOW)
	var px := (_f(rnd) - 0.5) * (L - 5.0)
	p["pads"].append({"x": _r3(px), "z": 0.0, "r": 1.2, "power": 17.0})
	p["tops"].append([_r3(-px * 0.5), -2.4, 1.0])
	return _finish(p)


## Concrete mixer on a frame: a drum, a chute and wheels. Its top is 1.7 m, one jump from the ground.
static func mixer(col := ORANGE_D) -> Dictionary:
	var p := _new("mixer")
	var o: Array = p["boxes"]
	for s in [-1.0, 1.0]: _bx(o, -0.5, s * 0.95, 0.9, 0.3, 0.9, 0.0, DARK)
	_bx(o, 0, 0, 3.6, 1.6, 0.3, 0.3, YELLOW)                              # frame
	_bx(o, -0.1, 0, 1.9, 1.7, 1.1, 0.6, col)                              # drum, top 1.7
	_bx(o, -0.1, 0, 2.0, 1.8, 0.2, 1.0, STEEL_D)                          # drum band
	_bx(o, 1.45, 0, 0.9, 0.7, 0.25, 1.1, STEEL)                           # chute
	_bx(o, 1.95, 0, 0.5, 0.7, 0.25, 0.85, STEEL)
	return _finish(p)


## A few traffic cones standing in a loose cluster (0.64 m: jump over them).
static func cones(rnd: Callable, count := 4) -> Dictionary:
	var p := _new("cones")
	var o: Array = p["boxes"]
	var pts: Array = []
	var tries := 0
	while pts.size() < count and tries < 40:
		tries += 1
		var x := (_f(rnd) - 0.5) * 3.0
		var z := (_f(rnd) - 0.5) * 3.0
		var ok := true
		for q: Vector2 in pts:
			if q.distance_to(Vector2(x, z)) < 0.95: ok = false
		if ok: pts.append(Vector2(_r3(x), _r3(z)))
	for q: Vector2 in pts:
		_bx(o, q.x, q.y, 0.5, 0.5, 0.1, 0.0, DARK)
		_bx(o, q.x, q.y, 0.36, 0.36, 0.3, 0.1, ORANGE)
		_bx(o, q.x, q.y, 0.24, 0.24, 0.14, 0.4, WHITE)
		_bx(o, q.x, q.y, 0.14, 0.14, 0.1, 0.54, ORANGE)
	return _finish(p)


## A line of jersey barriers (1.0 m high), concrete or the orange-and-white water-filled kind.
static func barriers(rnd: Callable, count := 3) -> Dictionary:
	var p := _new("barriers")
	var o: Array = p["boxes"]
	var hazard := _f(rnd) < 0.5
	for i in count:
		var x := (float(i) - float(count - 1) / 2.0) * 3.1
		_bx(o, _r3(x), 0.0, 3.0, 0.7, 0.4, 0.0, ORANGE_D if hazard else CONCRETE)
		_bx(o, _r3(x), 0.0, 3.0, 0.4, 0.6, 0.4, WHITE if hazard else CONCRETE_D)
	return _finish(p)


## Hazard-stripe floor marking (0.04 m high decal boxes, yellow and black), w along x.
static func hazard_strip(w: float, d: float) -> Dictionary:
	var p := _new("hazard")
	var o: Array = p["boxes"]
	var n := maxi(2, int(round(w / 0.9)))
	for i in n:
		var x := -w / 2.0 + (float(i) + 0.5) * w / float(n)
		_bx(o, _r3(x), 0.0, _r3(w / float(n)), d, 0.04, 0.0, YELLOW if i % 2 == 0 else DARK)
	return _finish(p)


# ---------------------------------------------------------------- runs along an edge

## Site fence along one axis-aligned run: panels (<= 7 m) between posts, with gaps (gates) = [[centre, width]] measured along
## the run. `a` and `b` are the run's ends as [x, z]; the run's own axis is whichever coordinate changes.
static func fence_run(o: Array, a: Array, b: Array, gates: Array, style: int) -> void:
	var along_x := absf(float(b[0]) - float(a[0])) > absf(float(b[1]) - float(a[1]))
	var s0 := float(a[0]) if along_x else float(a[1])
	var s1 := float(b[0]) if along_x else float(b[1])
	var fixed := float(a[1]) if along_x else float(a[0])
	var segs: Array = [[s0, s1]]
	for g: Array in gates:
		var lo := float(g[0]) - float(g[1]) / 2.0
		var hi := float(g[0]) + float(g[1]) / 2.0
		var next: Array = []
		for sg: Array in segs:
			if hi <= sg[0] or lo >= sg[1]:
				next.append(sg)
				continue
			if lo > sg[0] + 0.2: next.append([sg[0], lo])
			if hi < sg[1] - 0.2: next.append([hi, sg[1]])
		segs = next
	var panel: int = [0x8da3b5, 0xc9a46a, 0x9aa0a6][style % 3]
	for sg: Array in segs:
		var len_s := float(sg[1]) - float(sg[0])
		var n := maxi(1, int(ceil(len_s / 7.0)))
		var pl := len_s / float(n)
		for i in n:
			var c := float(sg[0]) + (float(i) + 0.5) * pl
			if along_x: _bx(o, _r3(c), fixed, _r3(pl - 0.3), 0.18, FENCE_H, 0.0, panel)
			else: _bx(o, fixed, _r3(c), 0.18, _r3(pl - 0.3), FENCE_H, 0.0, panel)
		for i in n + 1:
			var c := float(sg[0]) + float(i) * pl
			var gate_post := i == 0 or i == n
			var pc: int = YELLOW if gate_post and gates.size() > 0 else STEEL_D
			if along_x: _bx(o, _r3(c), fixed, 0.3, 0.3, FENCE_H + 0.2, 0.0, pc)
			else: _bx(o, fixed, _r3(c), 0.3, 0.3, FENCE_H + 0.2, 0.0, pc)
