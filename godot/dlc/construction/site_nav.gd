class_name SiteNav
extends RefCounted
## Construction DLC: a simplified but real walk / jump / ladder / bounce-pad reachability graph over a map's boxes, used by the
## Building Site tests (and handy for any generated level). It rasterises the boxes into a 1 m grid the way FighterPhysics
## sees them (a box blocks a cell when the cell centre is within R of its footprint) and finds, per cell, every height a
## fighter could stand at: the top of a box covering the cell with nothing taller (more than STEP) and low enough to hit
## the head (FH) in the way. Edges: walk (up to STEP, or any drop), jump (up to JUMP_UP, over things up to 1.7 m high
## when the target is two cells away), ladders (grab cell <-> top cell) and bounce pads (power 17 = 6 m of lift).

const N := 64
const ORG := -32.0
const R := 0.5                ## FighterPhysics.R 0.45 plus a little, so a thin rail on a cell edge still blocks both cells
const STEP := 0.55
const FH := 2.3
const JUMP_UP := 2.0          ## 9.2 m/s at GRAV 24 lifts 1.76 m, and a landing may step 0.55 more: 2.0 keeps a margin
const FLY_OVER := 1.7         ## something this much higher than the jumper's feet can be crossed mid-jump
const PAD_LIFT := 5.4         ## highest top a pad (17 m/s, 6.0 m apex) reaches
const PAD_REACH := 6.5        ## ... and how far it carries sideways
const MAXL := 8               ## levels per cell the node ids allow


static func _away(v: int) -> int:
	return (v + signi(v)) / 2


static func _cell_x(i: int) -> float:
	return ORG + (float(i) + 0.5)


static func cell_of(v: float) -> int:
	return clampi(int(floor(v - ORG)), 0, N - 1)


## Analyses `map` (a maps.json-shaped Dictionary). `ignore`: {box index: true} for boxes that are never platforms (the fence),
## `starts`: [[x, z], ...] ground points that must all be connected to the first (default spawns + bots + player).
## Returns {ok, unreachable: [[x, z, top]], disconnected: [[x, z]], levels, reached, nodes}.
static func analyze(map: Dictionary, ignore := {}, starts := []) -> Dictionary:
	var geo: Dictionary = map["geometry"]
	var boxes: Array = geo["boxes"]
	var cb: Array = []
	cb.resize(N * N)
	for i in N * N: cb[i] = []
	for bi in boxes.size():
		var b: Dictionary = boxes[bi]
		var x0 := float(b["x"]) - float(b["w"]) / 2.0 - R
		var x1 := float(b["x"]) + float(b["w"]) / 2.0 + R
		var z0 := float(b["z"]) - float(b["d"]) / 2.0 - R
		var z1 := float(b["z"]) + float(b["d"]) / 2.0 + R
		for j in range(maxi(0, int(floor(z0 - ORG)) - 1), mini(N, int(ceil(z1 - ORG)) + 1)):
			var cz := _cell_x(j)
			if cz <= z0 or cz >= z1: continue
			for i in range(maxi(0, int(floor(x0 - ORG)) - 1), mini(N, int(ceil(x1 - ORG)) + 1)):
				var cx := _cell_x(i)
				if cx > x0 and cx < x1: (cb[j * N + i] as Array).append(bi)
	# standing heights and the highest thing in each cell
	var levels: Array = []
	levels.resize(N * N)
	var cmax := PackedFloat32Array()
	cmax.resize(N * N)
	var nlev := 0
	for c in N * N:
		var lst: Array = cb[c]
		var cand: Array = []
		var mx := -100.0
		for bi: int in lst:
			var b: Dictionary = boxes[bi]
			var top := float(b["y"]) + float(b["h"])
			mx = maxf(mx, top)
			if not ignore.has(bi) and not cand.has(snappedf(top, 0.001)): cand.append(snappedf(top, 0.001))
		cmax[c] = mx
		cand.sort()
		var valid: Array = []
		for h: float in cand:
			var blocked := false
			for bi: int in lst:
				var b: Dictionary = boxes[bi]
				var t2 := float(b["y"]) + float(b["h"])
				if t2 > h + STEP + 1e-4 and float(b["y"]) < h + FH - 1e-4: blocked = true; break
			if not blocked: valid.append(h)
		var keep: Array = []
		for k in valid.size():
			if k + 1 < valid.size() and float(valid[k + 1]) - float(valid[k]) <= STEP + 1e-4: continue
			keep.append(valid[k])
		if keep.size() > MAXL: keep = keep.slice(keep.size() - MAXL)
		levels[c] = keep
		nlev += keep.size()
	# graph
	var ladders: Array = geo.get("ladders", [])
	var pads: Array = geo.get("bouncePads", [])
	var visited := PackedByteArray()
	visited.resize(N * N * MAXL)
	var queue: Array = []
	var pad_cells: Array = []        # per pad: the cells a fighter on it stands in
	for pd: Dictionary in pads:
		var cells: Array = []
		var r := float(pd.get("r", 1.2)) + 0.4
		for j in N:
			for i in N:
				if Vector2(_cell_x(i) - float(pd["x"]), _cell_x(j) - float(pd["z"])).length() < r: cells.append(j * N + i)
		pad_cells.append(cells)
	var lad_up: Dictionary = {}      # node -> [nodes]: a ladder joins the ground by its foot with the deck at its top
	for l: Dictionary in ladders:
		var gx := float(l["x"]) + float(l["nx"]) * 0.55
		var gz := float(l["z"]) + float(l["nz"]) * 0.55
		var tx := float(l["x"]) - float(l["nx"]) * 0.4
		var tz := float(l["z"]) - float(l["nz"]) * 0.4
		var y0 := float(l["y0"])
		var y1 := float(l["y1"])
		var gn: Array = _nodes_near(levels, gx, gz, 1.5, y0 - STEP - 0.05, y0 + STEP + 0.05)       # the foot (a cell centre can sit inside a wall's margin)
		var tn: Array = _nodes_near(levels, tx, tz, 1.0, y1 - STEP - 0.05, y1 + STEP + 0.05)       # where the step-off lands
		if tn.is_empty() or gn.is_empty(): continue
		for g: int in gn:
			var h0 := float((levels[g / MAXL] as Array)[g % MAXL])
			if h0 > y0 - 0.4 and h0 < y1 - 0.1:
				if not lad_up.has(g): lad_up[g] = []
				lad_up[g].append_array(tn)
		for t: int in tn:
			if not lad_up.has(t): lad_up[t] = []
			lad_up[t].append_array(gn)
	# starting points
	var pts: Array = starts.duplicate()
	if pts.is_empty():
		for a: Array in map.get("spawns", []): pts.append([a[0], a[1]])
		for a: Array in map.get("bots", []): pts.append([a[0], a[1]])
		if map.has("player"): pts.append([map["player"][0], map["player"][1]])
	var first := -1
	var start_nodes: Array = []
	var disconnected_starts: Array = []
	for pt: Array in pts:
		var c := cell_of(float(pt[1])) * N + cell_of(float(pt[0]))
		var li := _ground_level(levels[c])
		if li < 0:
			disconnected_starts.append([pt[0], pt[1]])
			start_nodes.append(-1)
			continue
		start_nodes.append(c * MAXL + li)
	for sn: int in start_nodes:
		if sn >= 0: first = sn; break
	if first >= 0:
		visited[first] = 1
		queue.append(first)
	var head := 0
	while head < queue.size():
		var node: int = queue[head]
		head += 1
		var c := node / MAXL
		var h := float((levels[c] as Array)[node % MAXL])
		var ci := c % N
		var cj := c / N
		for dj in range(-2, 3):
			var nj := cj + dj
			if nj < 0 or nj >= N: continue
			for di in range(-2, 3):
				if di == 0 and dj == 0: continue
				var ni := ci + di
				if ni < 0 or ni >= N: continue
				var far := absi(di) == 2 or absi(dj) == 2
				if far:                                          # crossing something on the way: one of the two cells between must be low
					var m1 := (cj + dj / 2) * N + ci + di / 2
					var m2 := (cj + _away(dj)) * N + ci + _away(di)
					if cmax[m1] > h + FLY_OVER and cmax[m2] > h + FLY_OVER: continue
				var nc := nj * N + ni
				var tl2: Array = levels[nc]
				var best := -1
				for k in tl2.size():
					var h2 := float(tl2[k])
					if h2 <= h + STEP + 1e-4:
						best = k                               # walk / fall: the highest level not above a step
					elif h2 <= h + JUMP_UP + 1e-4:
						var nn := nc * MAXL + k
						if visited[nn] == 0: visited[nn] = 1; queue.append(nn)
				if best >= 0:
					var nn2 := nc * MAXL + best
					if visited[nn2] == 0: visited[nn2] = 1; queue.append(nn2)
		if lad_up.has(node):
			for tn: int in lad_up[node]:
				if visited[tn] == 0: visited[tn] = 1; queue.append(tn)
		if h < 0.7:
			for pi in pads.size():
				if (pad_cells[pi] as Array).has(c):
					var pd: Dictionary = pads[pi]
					for j in range(maxi(0, cell_of(float(pd["z"]) - PAD_REACH)), mini(N, cell_of(float(pd["z"]) + PAD_REACH) + 1)):
						for i in range(maxi(0, cell_of(float(pd["x"]) - PAD_REACH)), mini(N, cell_of(float(pd["x"]) + PAD_REACH) + 1)):
							if Vector2(_cell_x(i) - float(pd["x"]), _cell_x(j) - float(pd["z"])).length() > PAD_REACH: continue
							var lv: Array = levels[j * N + i]
							for k in lv.size():
								if float(lv[k]) <= PAD_LIFT:
									var nn3 := (j * N + i) * MAXL + k
									if visited[nn3] == 0: visited[nn3] = 1; queue.append(nn3)
	var unreachable: Array = []
	var reached := 0
	for c in N * N:
		var lv2: Array = levels[c]
		for k in lv2.size():
			if visited[c * MAXL + k] == 1:
				reached += 1
			elif float(lv2[k]) > 1.5:
				unreachable.append([_cell_x(c % N), _cell_x(c / N), float(lv2[k])])
	var disconnected: Array = disconnected_starts
	for k in start_nodes.size():
		if int(start_nodes[k]) >= 0 and visited[int(start_nodes[k])] == 0: disconnected.append([pts[k][0], pts[k][1]])
	return {"ok": unreachable.is_empty() and disconnected.is_empty() and first >= 0, "unreachable": unreachable, "disconnected": disconnected,
		"levels": nlev, "reached": reached, "nodes": queue.size()}


## Node ids of the levels within [lo, hi] in the cells whose centres are within `r` of (x, z).
static func _nodes_near(levels: Array, x: float, z: float, r: float, lo: float, hi: float) -> Array:
	var out: Array = []
	for j in range(maxi(0, cell_of(z - r)), mini(N, cell_of(z + r) + 1)):
		for i in range(maxi(0, cell_of(x - r)), mini(N, cell_of(x + r) + 1)):
			if absf(_cell_x(i) - x) > r or absf(_cell_x(j) - z) > r: continue
			var lv: Array = levels[j * N + i]
			for k in lv.size():
				if float(lv[k]) >= lo and float(lv[k]) <= hi: out.append((j * N + i) * MAXL + k)
	return out


## Index of the ground (lowest, near 0) level in a cell's list, or -1.
static func _ground_level(lv: Array) -> int:
	for k in lv.size():
		if absf(float(lv[k])) < 0.1: return k
	return -1
