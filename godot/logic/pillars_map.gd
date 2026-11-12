class_name PillarsMap
extends RefCounted
## The Pillars level's layout, ported from MAPS.pillars (public/index.html ~3462-3490: PIL_PTS and build()). The web
## export (tools/export-maps.js) cannot run that build() (PIL_PTS lives outside the MAPS literal), so shared/maps.json
## has the level's look and flags but no boxes, spawns, player or bot spots: complete() fills them in, the same numbers
## as the web game. MapBuilder.build("pillars") and the maps audit use it.
## Eight pillars on a ring 28 m from the middle (shaft 8.4 x 8.4 from y -80 to 9.7, a cap 8.9 x 8.9 to 10.3) and a
## different low piece of cover on each pillar's inner side (crate, barrels, wall, sandbags, fountain, hay, container, ice).

const RING := 28.0
const SPAWN_Y := 10.35                 ## m.player[2] / the bots' y
const COLS := [0xe8d9b0, 0xd9c8a0, 0xf0e2bc, 0xcfbf94, 0xf4e8c8, 0xd4c49a, 0xe6d6ac, 0xcdbd92]
const IDS := ["pillars"]               ## levels built this way (Lava Pillars, pillars2, is not exported from the web game)

## PIL_PTS: [x, z] of the eight pillars (rounded to 0.01 like the web game).
static func points() -> Array:
	var o: Array = []
	for i in 8:
		var a := i * PI / 4.0
		o.append([Combat.js_round(cos(a) * RING * 100.0) / 100.0, Combat.js_round(sin(a) * RING * 100.0) / 100.0])
	return o

## `base` (the maps.json entry) plus spawns, player, bots and geometry from MAPS.pillars.
static func complete(base: Dictionary) -> Dictionary:
	var m := base.duplicate(true)
	var pts := points()
	var bots: Array = []
	for i in pts.size():
		if i != 5: bots.append([pts[i][0], pts[i][1], SPAWN_Y])
	m["spawns"] = pts.duplicate(true)
	m["player"] = [pts[5][0], pts[5][1], SPAWN_Y]
	m["bots"] = bots
	m["geometry"] = {"boxes": boxes(), "ladders": [], "bouncePads": [], "floorPads": []}
	return m

## build(): every addBox of the level, in the web order ({x, z, w, d, h, y, color} like maps.json).
static func boxes() -> Array:
	var out: Array = []
	var pts := points()
	for n in pts.size():
		var gx: float = pts[n][0]
		var gz: float = pts[n][1]
		out.append(_box(gx, gz, 8.4, 8.4, 89.7, COLS[n], -80.0))
		out.append(_box(gx, gz, 8.9, 8.9, 0.6, 0xb08a5a, 9.7))     # shaft top 9.7, cap 9.7 to 10.3
		var l := sqrt(gx * gx + gz * gz)
		var ix := -gx / l
		var iz := -gz / l
		var cx := gx + ix * 2.6
		var cz := gz + iz * 2.6
		var tw := absf(gz) >= absf(gx)                             # the long side runs along X
		var c0 := [cx, cz, tw]
		match n:
			0: _bx(out, c0, 1.7, 1.7, 1.3, 0xb98650); _bx(out, c0, 1.8, 1.8, 0.14, 0xd6a96a, 0.0, 0.0, 1.3)              # wooden crate
			1: _bx(out, c0, 1.2, 1.2, 1.3, 0xc0392b, -0.7); _bx(out, c0, 1.2, 1.2, 1.3, 0xd04a3a, 0.7); _bx(out, c0, 1.2, 1.2, 0.9, 0xc0392b, 0.0, 0.0, 1.3)   # barrels
			2: _wide(out, c0, 3.6, 0.9, 1.2, 0x8f98a3); _wide(out, c0, 3.8, 1.0, 0.18, 0xaab2bc, 1.2)                     # stone wall
			3: _wide(out, c0, 3.2, 1.0, 0.6, 0xd9c28a); _wide(out, c0, 2.4, 0.9, 0.5, 0xcdb67c, 0.6); _wide(out, c0, 1.8, 0.8, 0.4, 0xd9c28a, 1.1)   # sandbags
			4: _bx(out, c0, 2.4, 2.4, 0.9, 0x3b82c4); _bx(out, c0, 1.7, 1.7, 0.9, 0x6fb7ee, 0.0, 0.0, 0.9); _bx(out, c0, 0.5, 0.5, 0.9, 0xdff3ff, 0.0, 0.0, 1.8)   # fountain
			5: _wide(out, c0, 3.0, 1.5, 0.8, 0xe3c35a); _wide(out, c0, 2.2, 1.4, 0.5, 0xeed272, 0.8)                       # hay bales
			6: _wide(out, c0, 3.6, 1.5, 1.4, 0xd2542f); _wide(out, c0, 3.7, 1.6, 0.1, 0x8a2f19, 1.4)                       # container
			_: _bx(out, c0, 1.9, 1.9, 1.4, 0xbfe9fa); _bx(out, c0, 1.3, 1.3, 0.5, 0xe8f8ff, 0.0, 0.0, 1.4)                # ice block
	return out

## bx(): a cover piece at the pillar's cover spot c0 = [cx, cz, along X], resting on the cap top (10.3) + y.
static func _bx(out: Array, c0: Array, w: float, d: float, h: float, color: int, dx := 0.0, dz := 0.0, y := 0.0) -> void:
	out.append(_box(float(c0[0]) + dx, float(c0[1]) + dz, w, d, h, color, 10.3 + y))

## wide(): a long piece lying along the pillar's tangent.
static func _wide(out: Array, c0: Array, ln: float, th: float, h: float, color: int, y := 0.0) -> void:
	if c0[2]: _bx(out, c0, ln, th, h, color, 0.0, 0.0, y)
	else: _bx(out, c0, th, ln, h, color, 0.0, 0.0, y)

static func _box(x: float, z: float, w: float, d: float, h: float, color: int, y: float) -> Dictionary:
	return {"x": x, "z": z, "w": w, "d": d, "h": h, "y": y, "color": color}
