class_name SandboxLayout
extends RefCounted
## The Sandbox arena you build (the web game's Wobble Workshop: MAPS.custom + the B / N block builder, public/index.html
## ~1888-1925 and ~8442-8460). Pure logic: the generated arena's settings (cfg.custom: size, theme, obs, plat, pads,
## walls, ice, seed) plus your blocks, 2 x 2 x 2 m on a 2 m grid, at most MAX_BLOCKS.
## Save shape = the web save's cfg, so the cloud save carries it between both games:
##   cfg.custom   {size, theme, obs, plat, pads, walls, ice, seed}           (web: copied key by key on load)
##   cfg.blocks   [[x, yBase, z], ...]                                     (web: arrays of 3 finite numbers, first 150)
##   cfg.blockCols [colour, ...] one per block (Godot only: the web keeps the blocks and paints them its yellow)
## The brush (size 1..3 cells square, height 1..4 blocks) places / removes several blocks at once; each block is still
## one [x, yBase, z] entry, so a web client builds the same arena.
## Aiming like the web game: place = the cell just in front of the crosshair hit (aimPoint - camFwd * 0.35), remove =
## the block the crosshair hits (aimPoint + camFwd * 0.25); out of reach (sky, far away) falls back to the cell in front
## of the player.

const MAX_BLOCKS := 150            ## the web cap ("That's a lot of blocks!")
const CELL := 2.0                  ## block size and grid
const MAX_YB := 18.0               ## highest block base (10 blocks tall)
const REACH := 14.0                ## m from the player the crosshair may place / remove
const WEB_YELLOW := 0xffe08a       ## addPlayerBlock's colour
const COLORS := [WEB_YELLOW, 0xff7a59, 0x4aa8ff, 0x6fd16a, 0xb784ff, 0xf4f1ea]
const COLOR_NAMES := ["Yellow", "Red", "Blue", "Green", "Purple", "White"]
const SIZES := [1, 2, 3]
const HEIGHTS := [1, 2, 3, 4]
const CUSTOM_KEYS := ["size", "obs", "plat", "walls", "pads", "seed"]

var custom := {}                   ## cfg.custom (MapBuilder.CUSTOM_DEFAULTS merged)
var blocks: Array = []             ## [[x, yb, z], ...] (ints)
var cols: Array = []               ## colour per block
## brush
var color: int = WEB_YELLOW
var size := 1
var height := 1

func _init(cfg: Dictionary = {}) -> void:
	load_cfg(cfg)

# ============================== save shape ==============================

## The web load(): cfg.custom key by key (finite numbers, a known theme, ice as a bool), cfg.blocks filtered to arrays
## of three finite numbers and cut to MAX_BLOCKS; Godot's cfg.blockCols when it lines up with the blocks.
func load_cfg(cfg: Dictionary) -> void:
	custom = MapBuilder.CUSTOM_DEFAULTS.duplicate()
	var c: Variant = cfg.get("custom")
	if c is Dictionary:
		for k: String in CUSTOM_KEYS:
			if _num(c.get(k)): custom[k] = int(c[k]) if float(c[k]) == floorf(float(c[k])) else float(c[k])
		if MapBuilder.CUSTOM_THEMES.has(str(c.get("theme", ""))): custom["theme"] = str(c["theme"])
		custom["ice"] = bool(c.get("ice", false))
	blocks = clean_blocks(cfg.get("blocks"))
	cols = []
	var bc: Variant = cfg.get("blockCols")
	for i in blocks.size():
		var v: Variant = bc[i] if bc is Array and i < (bc as Array).size() else null
		cols.append(int(v) if _num(v) else WEB_YELLOW)

## cfg.blocks as the web game reads it.
static func clean_blocks(v: Variant) -> Array:
	var out: Array = []
	if not (v is Array): return out
	for b: Variant in v:
		if out.size() >= MAX_BLOCKS: break
		if b is Array and (b as Array).size() == 3 and _num(b[0]) and _num(b[1]) and _num(b[2]):
			out.append([_n(b[0]), _n(b[1]), _n(b[2])])
	return out

## {custom, blocks, blockCols} for the save's cfg (merged into the rest of cfg by Save.set_sandbox).
func to_cfg() -> Dictionary:
	return {"custom": custom.duplicate(), "blocks": blocks.duplicate(true), "blockCols": cols.duplicate()}

## The arena as MapBuilder.custom_map's settings, with or without the blocks.
func map_cfg(with_blocks := true) -> Dictionary:
	var c := custom.duplicate()
	c["blocks"] = blocks.duplicate(true) if with_blocks else []
	c["blockCols"] = cols.duplicate() if with_blocks else []
	return c

static func _num(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func _n(v: Variant) -> Variant:
	var f := float(v)
	return int(f) if f == floorf(f) and absf(f) < 1e9 else f

# ============================== blocks ==============================

func count() -> int:
	return blocks.size()

func full() -> bool:
	return blocks.size() >= MAX_BLOCKS

func index_of(x: float, yb: float, z: float) -> int:
	for i in blocks.size():
		var b: Array = blocks[i]
		if float(b[0]) == x and float(b[1]) == yb and float(b[2]) == z: return i
	return -1

## Half the floor: blocks keep their centre at least one cell inside the edge.
func half() -> float:
	return float(custom.get("size", 44)) / 2.0

func in_bounds(x: float, z: float) -> bool:
	var h := half() - CELL / 2.0
	return absf(x) <= h and absf(z) <= h

## Cells (x, z) the brush covers around `anchor` (a grid point): size x size, the anchor in the middle (size 2: the
## anchor and the cells on the +x / +z side).
func brush_cells(anchor: Vector2) -> Array:
	var out: Array = []
	var lo := -floori((size - 1) / 2.0)
	for i in size:
		for j in size:
			out.append(Vector2(anchor.x + (lo + i) * CELL, anchor.y + (lo + j) * CELL))
	return out

static func snap(v: float) -> float:
	return roundf(v / CELL) * CELL

## Where Place puts the brush: [anchor (Vector2 grid point), yBase] from the crosshair hit `aim` (Vector3.ZERO = none)
## along the camera forward `fwd`, else the cell in front of the player `pos` facing `yaw`.
func place_target(aim: Vector3, fwd: Vector3, pos: Vector3, yaw: float) -> Array:
	if aim != Vector3.ZERO and aim.distance_to(pos) <= REACH:
		var t := aim - fwd * 0.35
		var x := snap(t.x)
		var z := snap(t.z)
		if in_bounds(x, z):
			return [Vector2(x, z), maxf(0.0, floorf((t.y + 0.05) / CELL) * CELL)]
	var ax := snap(pos.x + sin(yaw) * (CELL + size))
	var az := snap(pos.z + cos(yaw) * (CELL + size))
	var top := 0.0
	for c: Vector2 in brush_cells(Vector2(ax, az)): top = maxf(top, column_top(c.x, c.y))
	return [Vector2(ax, az), top]

## The block Remove takes out first: the one the crosshair hits, else the top one in front of the player. -1 = none.
func remove_target(aim: Vector3, fwd: Vector3, pos: Vector3, yaw: float) -> int:
	if aim != Vector3.ZERO and aim.distance_to(pos) <= REACH:
		var t := aim + fwd * 0.25
		for i in blocks.size():
			var b: Array = blocks[i]
			if t.x >= float(b[0]) - 1.05 and t.x <= float(b[0]) + 1.05 and t.z >= float(b[2]) - 1.05 and t.z <= float(b[2]) + 1.05 \
					and t.y >= float(b[1]) - 0.05 and t.y <= float(b[1]) + 2.05:
				return i
	var ax := snap(pos.x + sin(yaw) * (CELL + size))
	var az := snap(pos.z + cos(yaw) * (CELL + size))
	var best := -1
	for i in blocks.size():
		var b: Array = blocks[i]
		if float(b[0]) == ax and float(b[2]) == az and (best < 0 or float(b[1]) > float(blocks[best][1])): best = i
	return best

## The top of the block column at (x, z) (0 = the floor).
func column_top(x: float, z: float) -> float:
	var top := 0.0
	for b: Array in blocks:
		if float(b[0]) == x and float(b[2]) == z: top = maxf(top, float(b[1]) + CELL)
	return top

## Is a fighter standing where a block at (x, yb, z) would go? (`bodies` = [Vector3 feet], the web check).
static func blocked(x: float, yb: float, z: float, bodies: Array) -> bool:
	for p: Vector3 in bodies:
		if absf(p.x - x) < 1.5 and absf(p.z - z) < 1.5 and p.y < yb + CELL and p.y + 2.3 > yb: return true
	return false

## Places the brush at `anchor` from `yb` up (height blocks), skipping cells that are taken, out of the arena, too high
## or blocked by a fighter, until MAX_BLOCKS. Returns {added: [[x, yb, z], ...], why: "" | "full" | "blocked" | "taken"}.
func place(anchor: Vector2, yb: float, bodies: Array = []) -> Dictionary:
	var added: Array = []
	var why := ""
	for c: Vector2 in brush_cells(anchor):
		if not in_bounds(c.x, c.y): continue
		for h in height:
			var y := yb + h * CELL
			if y > MAX_YB: break
			if full():
				why = "full"; break
			if index_of(c.x, y, c.y) >= 0:
				if why == "": why = "taken"
				continue
			if blocked(c.x, y, c.y, bodies):
				why = "blocked"; continue
			var b := [int(c.x), int(y), int(c.y)]
			blocks.append(b); cols.append(color)
			added.append(b)
	return {"added": added, "why": "" if added.size() > 0 and why == "taken" else why}

## Removes block `i` and, with a bigger brush, the blocks around it on the same layers (size x size x height).
## Returns the removed [[x, yb, z], ...].
func remove(i: int) -> Array:
	if i < 0 or i >= blocks.size(): return []
	var b0: Array = blocks[i]
	var out: Array = []
	for c: Vector2 in brush_cells(Vector2(float(b0[0]), float(b0[2]))):
		for h in height:
			var k := index_of(c.x, float(b0[1]) + h * CELL, c.y)
			if k >= 0:
				out.append(blocks[k])
				blocks.remove_at(k); cols.remove_at(k)
	return out

func clear() -> void:
	blocks = []; cols = []

## One block as a maps.json box / a FighterPhysics solid.
static func box_of(b: Array, col: int) -> Dictionary:
	return {"x": float(b[0]), "z": float(b[2]), "w": CELL, "d": CELL, "h": CELL, "y": float(b[1]), "color": col}

static func solid_of(b: Array) -> Dictionary:
	var x := float(b[0]); var z := float(b[2]); var y := float(b[1])
	return {"minX": x - 1.0, "maxX": x + 1.0, "minZ": z - 1.0, "maxZ": z + 1.0, "top": y + CELL, "bottom": y}

func color_of(i: int) -> int:
	return int(cols[i]) if i >= 0 and i < cols.size() else WEB_YELLOW
