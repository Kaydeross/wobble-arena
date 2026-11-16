class_name PackKit
extends RefCounted
## Small helpers shared by the pack weapon models (kitchen_models.gd, xmas_models.gd, australia_models.gd). They only wrap
## WeaponModels' builder `b` (hand at the origin, the business end along -Y), so a pack model reads as a list of parts.
## Budget for a pack model: under 40 parts and under 2000 vertices (tests/pack_models_test.gd enforces 60 / 3000).

static func V(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


## Cylinder along Y (rt on top, rb at the bottom) unless `rot` turns it.
static func cyl(b, rt: float, rb: float, h: float, c: int, p: Vector3, seg := 8, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	return b.mi(null, LowPoly.cyl(rt, rb, h, seg), c, p, rot, sc)


## Cylinder lying along Z (a disc or a plate seen from the side): pans, soles, caps.
static func disc(b, r: float, thick: float, c: int, p: Vector3, seg := 10, sc := Vector3.ONE) -> MeshInstance3D:
	return b.mi(null, LowPoly.cyl(r, r, thick, seg), c, p, Vector3(PI / 2, 0, 0), sc)


## Cylinder lying along X (a rolled head: mallets).
static func drum(b, r: float, len: float, c: int, p: Vector3, seg := 10) -> MeshInstance3D:
	return b.mi(null, LowPoly.cyl(r, r, len, seg), c, p, Vector3(0, 0, PI / 2))


static func box(b, sx: float, sy: float, sz: float, c: int, p: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return b.mi(null, LowPoly.box(sx, sy, sz), c, p, rot)


static func ball(b, r: float, c: int, p: Vector3, sc := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	return b.mi(null, LowPoly.ico(r, 0), c, p, rot, sc)


## A cone with its point along -Y (flames, nozzles) or +Y when `up`.
static func cone(b, r: float, h: float, c: int, p: Vector3, seg := 8, up := false, rot := Vector3.ZERO) -> MeshInstance3D:
	return b.mi(null, LowPoly.cone(r, h, seg), c, p, rot + (Vector3.ZERO if up else Vector3(PI, 0, 0)))


## A piece of a torus ring in the XY plane: angles a0..a1 (radians, counter-clockwise from +X), centre `p`.
static func arc(b, big_r: float, tube: float, a0: float, a1: float, c: int, p: Vector3, tubular := 4, radial := 5) -> MeshInstance3D:
	return b.mi(null, LowPoly.torus(big_r, tube, radial, tubular, a1 - a0), c, p, Vector3(0, 0, a0))


## A thin round rod from `a` to `b2` (whip links, strings).
static func rod(b, r: float, a: Vector3, b2: Vector3, c: int, seg := 5) -> MeshInstance3D:
	var d := b2 - a
	var l := d.length()
	var m: MeshInstance3D = b.mi(null, LowPoly.cyl(r, r, l, seg), c, (a + b2) * 0.5)
	var up := d.normalized()
	var ax := Vector3.UP.cross(up)
	if ax.length() < 1e-5:
		ax = Vector3.RIGHT
	m.transform = Transform3D(Basis(ax.normalized(), Vector3.UP.angle_to(up)), (a + b2) * 0.5)
	return m


static func tip(b, x: float, y: float, z: float) -> void:
	b.grp(x, y, z, "Tip")


# ---------------------------------------------------------------- outfit helpers (the Wobbler's hexagonal torso, see WobblerLooks._faces)
## Torso radius at body height y (the front is a ridge, like WobblerLooks._r_at).
static func r_at(y: float) -> float:
	return 0.34 + 0.06 * (y / 0.85)


## Two flat panels that follow the two front faces of the torso at height y (a chevron over the ridge).
static func faces(out: Array, y: float, w: float, h: float, d: float, spec: Variant, off: float = 0.03) -> void:
	var r := r_at(y)
	for sg in [-1.0, 1.0]:
		out.append(["body", ["box", w, h, d], spec, [sg * 0.433 * r + sg * 0.5 * off, y, 0.75 * r + 0.866 * off], [0, sg * PI / 6, 0]])


## A patch lying on the front face `sg` (-1 / +1) at height y, `u` along the face, standing `off` proud of it.
static func patch(out: Array, sg: float, y: float, u: float, w: float, h: float, col: Variant, off: float = 0.056) -> void:
	var r := r_at(y)
	var phi := sg * PI / 6
	var n := Vector3(sin(phi), 0, cos(phi))
	var t := Vector3(cos(phi), 0, -sin(phi))
	var c := Vector3(sg * 0.433 * r, y, 0.75 * r) + n * off + t * u
	out.append(["body", ["box", w, h, 0.014], col, [c.x, c.y, c.z], [0, phi, 0]])
