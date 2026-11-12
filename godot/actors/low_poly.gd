class_name LowPoly
extends RefCounted
## Flat-shaded mesh builders that reproduce three.js geometry exactly (same vertex layout, same facets), so the
## blocky parts look like the web game's: BoxGeometry, CylinderGeometry/ConeGeometry, IcosahedronGeometry,
## SphereGeometry (with phi/theta ranges) and TorusGeometry (in the XY plane, with an arc).
## Every face gets its own normal (flat shading). Meshes are cached by their parameters and shared.

static var _cache: Dictionary = {}


## Box centred on the origin.
static func box(w: float, h: float, d: float) -> ArrayMesh:
	var key := "box:%s:%s:%s" % [w, h, d]
	if _cache.has(key):
		return _cache[key]
	var x := w * 0.5
	var y := h * 0.5
	var z := d * 0.5
	var c := [Vector3(-x, -y, -z), Vector3(x, -y, -z), Vector3(x, y, -z), Vector3(-x, y, -z),
		Vector3(-x, -y, z), Vector3(x, -y, z), Vector3(x, y, z), Vector3(-x, y, z)]
	var quads := [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]
	var tris := PackedVector3Array()
	for q in quads:
		tris.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return _store(key, _emit(tris, func(_p: Vector3) -> Vector3: return Vector3.ZERO))


## three.js CylinderGeometry(rt, rb, h, n): radial vertex k at angle k/n*TAU sits at (r sin, y, r cos), so a 6-sided
## torso has a ridge facing +Z (forward). rt = 0 makes a cone (ConeGeometry(r, h, n) == cyl(0, r, h, n)).
static func cyl(rt: float, rb: float, h: float, n: int = 6, arc: float = TAU, open_ended: bool = false) -> ArrayMesh:
	var key := "cyl:%s:%s:%s:%d:%s:%s" % [rt, rb, h, n, arc, open_ended]
	if _cache.has(key):
		return _cache[key]
	var hh := h * 0.5
	var tris := PackedVector3Array()
	for i in n:
		var t0 := float(i) / n * arc
		var t1 := float(i + 1) / n * arc
		var a := Vector3(rt * sin(t0), hh, rt * cos(t0))
		var b := Vector3(rb * sin(t0), -hh, rb * cos(t0))
		var c := Vector3(rb * sin(t1), -hh, rb * cos(t1))
		var d := Vector3(rt * sin(t1), hh, rt * cos(t1))
		tris.append_array([a, b, d, b, c, d])
		if not open_ended:
			if rt > 0.0:
				tris.append_array([Vector3(0, hh, 0), a, d])
			if rb > 0.0:
				tris.append_array([Vector3(0, -hh, 0), b, c])
	return _store(key, _emit(tris, func(p: Vector3) -> Vector3: return Vector3(0, clampf(p.y, -hh * 0.999, hh * 0.999), 0)))


static func cone(r: float, h: float, n: int = 8) -> ArrayMesh:
	return cyl(0.0, r, h, n)


## three.js IcosahedronGeometry(r, detail).
static func ico(r: float, detail: int = 0) -> ArrayMesh:
	var key := "ico:%s:%d" % [r, detail]
	if _cache.has(key):
		return _cache[key]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [-1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, 0, 0, -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, t, 0, -1, t, 0, 1, -t, 0, -1, -t, 0, 1]
	var idx := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	var tris := PackedVector3Array()
	var cols := detail + 1
	for f in range(0, idx.size(), 3):
		var a := Vector3(v[idx[f] * 3], v[idx[f] * 3 + 1], v[idx[f] * 3 + 2])
		var b := Vector3(v[idx[f + 1] * 3], v[idx[f + 1] * 3 + 1], v[idx[f + 1] * 3 + 2])
		var c := Vector3(v[idx[f + 2] * 3], v[idx[f + 2] * 3 + 1], v[idx[f + 2] * 3 + 2])
		var grid := []
		for i in cols + 1:
			var aj := a.lerp(c, float(i) / cols)
			var bj := b.lerp(c, float(i) / cols)
			var rows := cols - i
			var row := []
			for j in rows + 1:
				row.append(aj if rows == 0 and j == 0 else aj.lerp(bj, float(j) / rows))
			grid.append(row)
		for i in cols:
			for j in 2 * (cols - i) - 1:
				var k := j / 2
				if j % 2 == 0:
					tris.append_array([grid[i][k + 1], grid[i + 1][k], grid[i][k]])
				else:
					tris.append_array([grid[i][k + 1], grid[i + 1][k + 1], grid[i + 1][k]])
	for i in tris.size():
		tris[i] = tris[i].normalized() * r
	return _store(key, _emit(tris, func(_p: Vector3) -> Vector3: return Vector3.ZERO))


## three.js SphereGeometry(r, ws, hs, phi_start, phi_len, theta_start, theta_len).
static func sphere(r: float, ws: int = 8, hs: int = 6, p0: float = 0.0, pl: float = TAU, t0: float = 0.0, tl: float = PI) -> ArrayMesh:
	var key := "sph:%s:%d:%d:%s:%s:%s:%s" % [r, ws, hs, p0, pl, t0, tl]
	if _cache.has(key):
		return _cache[key]
	var grid := []
	for iy in hs + 1:
		var vv := float(iy) / hs
		var row := []
		for ix in ws + 1:
			var u := float(ix) / ws
			row.append(Vector3(-r * cos(p0 + u * pl) * sin(t0 + vv * tl), r * cos(t0 + vv * tl), r * sin(p0 + u * pl) * sin(t0 + vv * tl)))
		grid.append(row)
	var tris := PackedVector3Array()
	for iy in hs:
		for ix in ws:
			var a: Vector3 = grid[iy][ix + 1]
			var b: Vector3 = grid[iy][ix]
			var c: Vector3 = grid[iy + 1][ix]
			var d: Vector3 = grid[iy + 1][ix + 1]
			if iy != 0 or t0 > 0.0:
				tris.append_array([a, b, d])
			if iy != hs - 1 or t0 + tl < PI:
				tris.append_array([b, c, d])
	return _store(key, _emit(tris, func(_p: Vector3) -> Vector3: return Vector3.ZERO))


## three.js TorusGeometry(R, tube, radial, tubular, arc): ring in the XY plane round the Z axis.
static func torus(rr: float, tube: float, radial: int = 6, tubular: int = 12, arc: float = TAU) -> ArrayMesh:
	var key := "tor:%s:%s:%d:%d:%s" % [rr, tube, radial, tubular, arc]
	if _cache.has(key):
		return _cache[key]
	var grid := []
	for j in radial + 1:
		var row := []
		for i in tubular + 1:
			var u := float(i) / tubular * arc
			var vv := float(j) / radial * TAU
			row.append(Vector3((rr + tube * cos(vv)) * cos(u), (rr + tube * cos(vv)) * sin(u), tube * sin(vv)))
		grid.append(row)
	var tris := PackedVector3Array()
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a: Vector3 = grid[j][i - 1]
			var b: Vector3 = grid[j - 1][i - 1]
			var c: Vector3 = grid[j - 1][i]
			var d: Vector3 = grid[j][i]
			tris.append_array([a, b, d, b, c, d])
	return _store(key, _emit(tris, func(p: Vector3) -> Vector3:
		var ang := atan2(p.y, p.x)
		return Vector3(rr * cos(ang), rr * sin(ang), 0.0)))


## Mesh from a data spec: ["box", w, h, d] | ["cyl", rt, rb, h, n] | ["cone", r, h, n] | ["ico", r, detail]
## | ["sph", r, ws, hs, phi0, phi_len, theta0, theta_len] | ["tor", R, tube, radial, tubular, arc].
static func from_spec(g: Array) -> ArrayMesh:
	match String(g[0]):
		"box":
			return box(g[1], g[2], g[3])
		"cyl":
			return cyl(g[1], g[2], g[3], g[4] if g.size() > 4 else 6)
		"cone":
			return cone(g[1], g[2], g[3] if g.size() > 3 else 8)
		"ico":
			return ico(g[1], g[2] if g.size() > 2 else 0)
		"sph":
			return sphere(g[1], g[2], g[3], g[4] if g.size() > 4 else 0.0, g[5] if g.size() > 5 else TAU, g[6] if g.size() > 6 else 0.0, g[7] if g.size() > 7 else PI)
		"tor":
			return torus(g[1], g[2], g[3], g[4], g[5] if g.size() > 5 else TAU)
	push_error("LowPoly: unknown shape %s" % [g])
	return box(0.1, 0.1, 0.1)


static func _store(key: String, m: ArrayMesh) -> ArrayMesh:
	_cache[key] = m
	return m


## Triangle soup -> flat-shaded ArrayMesh. `inside(p)` gives a point inside the solid near p, so every facet's normal
## points outward whatever the source winding was; triangles are then emitted in Godot's front-face (clockwise) order.
static func _emit(tris: PackedVector3Array, inside: Callable) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			continue
		n = n.normalized()
		var mid := (a + b + c) / 3.0
		if n.dot(mid - inside.call(mid)) < 0.0:
			n = -n
		# n is now outward; make the winding clockwise seen from outside (Godot front face)
		if (b - a).cross(c - a).dot(n) > 0.0:
			verts.append_array([a, c, b])
		else:
			verts.append_array([a, b, c])
		norms.append_array([n, n, n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
