class_name WeaponModels
extends RefCounted
## Held weapon models: a port of the web game's makeWeaponMesh (public/index.html ~3522). Same dimensions, colours
## and local origin: the hand is at the origin, barrels/blades point along local -Y, the top of a gun is -Z and its
## grip hangs toward +Z. Named child nodes mirror what the JS records in userData for effects/animation:
## "Tip" (flame, net, revolver, mammoth), "Bolt", "Mag", "Slide", "Spinner", "Drum", "Belt", "Tanks", "Shell".
## Not ported: the spatula outfit skins (skinSpatula) and the bow's string/arrow animation (built at rest, draw 0).
## Every colour goes through one material function (`mat_fn`, default `make_mat`) so a later pass can swap the shader.

const KEYS: Array[String] = ["katana", "spatula", "bat", "shotgun", "sniper", "typhoon", "mammoth", "glove", "meteor",
	"rocket", "trident", "mallet", "snow", "glauncher", "cluster", "knife", "net", "snake", "ak", "smg", "uzi",
	"minigun", "revolver", "bow", "shuriken", "flame", "boomerang", "blower"]


static func make_mat(c: int) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.hex(c << 8 | 0xff)
	m.roughness = 0.95
	m.metallic = 0.0
	return m


## Euler XYZ like three.js (matrix Rx * Ry * Rz).
static func euler(r: Vector3) -> Basis:
	return Basis(Vector3.RIGHT, r.x) * Basis(Vector3.UP, r.y) * Basis(Vector3.BACK, r.z)


## Union of all visible mesh bounds under `n`, in n's local space (the model's own space).
static func bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Node3D = it[0]
		if not node.visible:
			continue
		var t: Transform3D = it[1] * (node.transform if node != n else Transform3D.IDENTITY)
		if node is MeshInstance3D and node.mesh != null:
			var bb: AABB = t * node.mesh.get_aabb()
			out = bb if first else out.merge(bb)
			first = false
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, t])
	return out


## Unknown key -> the old grey placeholder block.
static func build(key: String, mat_fn: Callable = Callable()) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon_" + key
	var b := _B.new()
	b.root = root
	b.mf = mat_fn if mat_fn.is_valid() else Callable(WeaponModels, "make_mat")
	match key:
		"spatula": _spatula(b)
		"katana": _katana(b)
		"bat": _bat(b)
		"ak": _ak(b)
		"smg": _smg(b)
		"uzi": _uzi(b)
		"minigun": _minigun(b)
		"revolver": _revolver(b)
		"mammoth": _mammoth(b)
		"shotgun": _shotgun(b)
		"sniper": _sniper(b)
		"flame": _flame(b)
		"net": _net(b)
		"rocket": _rocket(b)
		"meteor": _meteor(b)
		"glauncher": _glauncher(b)
		"cluster": _cluster(b)
		"snake": _snake(b)
		"snow": _snow(b)
		"bow": _bow(b)
		"knife": _knife(b)
		"typhoon": _typhoon(b)
		"shuriken": _shuriken(b)
		"boomerang": _boomerang(b)
		"glove": _glove(b)
		"trident": _trident(b)
		"mallet": _mallet(b)
		"blower": _blower(b)
		_:
			b.bx(0.14, 0.7, 0.18, 0x5a6270, 0, -0.3, -0.05)
			b.bx(0.1, 0.12, 0.22, 0x3a3f4a, 0, -0.02, 0.12)
	return root


# ---------------------------------------------------------------- builder helper (the `add`/`bx`/`cy` of makeWeaponMesh)
class _B extends RefCounted:
	var root: Node3D
	var mf: Callable

	func mi(parent: Node3D, mesh: Mesh, c: int, p: Vector3, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = mf.call(c)
		m.transform = Transform3D(WeaponModels.euler(rot).scaled_local(sc), p)
		(parent if parent != null else root).add_child(m)
		return m

	func bx(sx: float, sy: float, sz: float, c: int, x: float, y: float, z: float, rx := 0.0, ry := 0.0, rz := 0.0, parent: Node3D = null) -> MeshInstance3D:
		return mi(parent, LowPoly.box(sx, sy, sz), c, Vector3(x, y, z), Vector3(rx, ry, rz))

	func cy(rt: float, rb: float, h: float, c: int, x: float, y: float, z: float, seg := 7, parent: Node3D = null) -> MeshInstance3D:
		return mi(parent, LowPoly.cyl(rt, rb, h, seg), c, Vector3(x, y, z))

	func ico(r: float, detail: int, c: int, x: float, y: float, z: float, parent: Node3D = null) -> MeshInstance3D:
		return mi(parent, LowPoly.ico(r, detail), c, Vector3(x, y, z))

	func grp(x: float, y: float, z: float, nm: String, parent: Node3D = null) -> Node3D:
		var g := Node3D.new()
		g.name = nm
		g.position = Vector3(x, y, z)
		(parent if parent != null else root).add_child(g)
		return g


static func _tip(b: _B, x: float, y: float, z: float) -> void:
	b.grp(x, y, z, "Tip")


static func _mag(b: _B, nm: String) -> Node3D:
	return b.grp(0, 0, 0, nm)


# ---------------------------------------------------------------- melee
static func _spatula(b: _B) -> void:
	b.cy(0.065, 0.065, 0.45, 0xe3566b, 0, 0, 0, 6)
	b.cy(0.035, 0.04, 1.0, 0xb8c2c9, 0, -0.65, 0, 6)
	b.bx(0.58, 0.78, 0.05, 0xcfd8de, 0, -1.5, 0)
	for x in [-0.17, 0.0, 0.17]:
		b.bx(0.07, 0.38, 0.07, 0x6b7a86, x, -1.58, 0)


static func _katana(b: _B) -> void:
	b.cy(0.055, 0.055, 0.55, 0x23262d, 0, -0.1, 0, 6)
	for y in [-0.28, -0.1, 0.08]:
		b.cy(0.065, 0.065, 0.05, 0xe3566b, 0, y, 0, 6)
	b.bx(0.42, 0.06, 0.16, 0xffd24a, 0, -0.42, 0)
	b.bx(0.05, 1.95, 0.13, 0xdfeaf5, 0, -1.45, 0)
	b.bx(0.02, 1.95, 0.05, 0xffffff, 0.03, -1.45, 0)


static func _bat(b: _B) -> void:
	b.cy(0.1, 0.27, 2.0, 0xd9a066, 0, -0.75, 0, 7)
	b.cy(0.215, 0.215, 0.12, 0xe3566b, 0, -1.3, 0, 7)


static func _glove(b: _B) -> void:
	b.cy(0.07, 0.07, 0.4, 0x3a3f48, 0, 0.05, 0, 6)
	b.cy(0.05, 0.05, 0.7, 0xb8c2c9, 0, -0.5, 0, 5)
	b.mi(null, LowPoly.ico(0.3, 0), 0xe3566b, Vector3(0, -1.0, 0), Vector3.ZERO, Vector3(1, 0.9, 1.1))
	b.bx(0.4, 0.12, 0.14, 0xffffff, 0, -0.75, 0)


static func _trident(b: _B) -> void:
	b.cy(0.05, 0.05, 2.0, 0xb9894f, 0, -0.9, 0, 6)
	b.cy(0.075, 0.075, 0.2, 0x2fb8c8, 0, 0.05, 0, 6)
	b.cy(0.09, 0.09, 0.14, 0xffd24a, 0, -1.78, 0, 6)
	b.bx(0.62, 0.09, 0.1, 0x2fb8c8, 0, -1.9, 0)
	for sx in [-0.28, 0.0, 0.28]:
		var mid: bool = sx == 0.0
		b.cy(0.035, 0.035, 0.62 if mid else 0.5, 0x7be3ee, sx, -2.0 - (0.28 if mid else 0.2), 0, 5)
		b.mi(null, LowPoly.cone(0.075, 0.2, 4), 0xe9fbff, Vector3(sx, -2.0 - (0.68 if mid else 0.55), 0), Vector3(PI, 0, 0))
	for sx in [-0.28, 0.28]:
		b.bx(0.06, 0.12, 0.08, 0x2fb8c8, sx * 0.9, -1.96, 0)
	for c in b.root.get_children():                          # the hand holds the middle of the long pole
		(c as Node3D).position.y += 0.9


static func _mallet(b: _B) -> void:
	b.cy(0.07, 0.07, 1.5, 0xd9a066, 0, -0.55, 0, 6)
	b.mi(null, LowPoly.cyl(0.34, 0.34, 0.95, 8), 0xe3566b, Vector3(0, -1.4, 0), Vector3(0, 0, PI / 2))
	for sx in [-0.5, 0.5]:
		b.mi(null, LowPoly.cyl(0.37, 0.37, 0.08, 8), 0xffd24a, Vector3(sx, -1.4, 0), Vector3(0, 0, PI / 2))


static func _blower(b: _B) -> void:
	b.cy(0.2, 0.2, 0.7, 0x4aa3d8, 0, -0.35, 0, 8)
	b.mi(null, LowPoly.cone(0.42, 0.6, 8), 0xdff3fb, Vector3(0, -0.95, 0))
	b.bx(0.14, 0.3, 0.16, 0x2a3640, 0, 0.1, 0.18)


# ---------------------------------------------------------------- guns
static func _ak(b: _B) -> void:
	b.bx(0.13, 0.95, 0.17, 0x2e3640, 0, -0.25, -0.02)
	b.bx(0.11, 0.7, 0.06, 0x2a3139, 0, -0.3, -0.11)
	b.bx(0.15, 0.55, 0.12, 0x8a5a2b, 0, -0.95, 0.02)
	b.bx(0.12, 0.5, 0.05, 0x6e4522, 0, -0.95, -0.07)
	b.cy(0.04, 0.04, 0.5, 0x1f262d, 0, -1.45, -0.02, 6)
	b.cy(0.058, 0.058, 0.12, 0x1f262d, 0, -1.72, -0.02, 6)
	b.cy(0.032, 0.032, 0.75, 0x3a434d, 0, -1.0, -0.12, 5)
	b.bx(0.04, 0.05, 0.13, 0x1f262d, 0, -1.6, -0.1)
	var mg := _mag(b, "Mag")
	b.bx(0.11, 0.16, 0.44, 0x32363d, 0, -0.45, 0.32, 0.3, 0, 0, mg)
	b.bx(0.11, 0.16, 0.22, 0x32363d, 0, -0.58, 0.58, 0.6, 0, 0, mg)
	b.bx(0.1, 0.14, 0.3, 0x2a2a2a, 0, 0.12, 0.22, -0.35)
	b.bx(0.12, 0.5, 0.17, 0x8a5a2b, 0, 0.62, 0.04)
	b.bx(0.13, 0.06, 0.2, 0x2a2a2a, 0, 0.9, 0.04)
	b.bx(0.09, 0.22, 0.09, 0xffd24a, 0.1, -0.35, -0.02).name = "Bolt"


static func _smg(b: _B) -> void:
	b.bx(0.15, 0.78, 0.2, 0x2b3138, 0, -0.3, 0)
	b.bx(0.1, 0.72, 0.05, 0x1d2126, 0, -0.3, -0.12)
	b.bx(0.17, 0.46, 0.2, 0x3a4048, 0, -0.82, 0.0)
	for y in [-0.68, -0.82, -0.96]:
		b.bx(0.19, 0.04, 0.11, 0x14171b, 0, y, 0)
	b.cy(0.04, 0.04, 0.3, 0x1c2228, 0, -1.2, 0, 6)
	b.cy(0.06, 0.06, 0.14, 0x14171b, 0, -1.36, 0, 6)
	b.bx(0.04, 0.06, 0.1, 0x14171b, 0, -1.25, -0.1)
	b.bx(0.09, 0.14, 0.1, 0x1a1d21, 0, -0.3, -0.2)
	b.bx(0.025, 0.025, 0.02, 0xff3b3b, 0, -0.36, -0.26)
	var mg := _mag(b, "Mag")
	b.bx(0.1, 0.12, 0.4, 0x1f2328, 0, -0.38, 0.3, 0.08, 0, 0, mg)
	b.bx(0.1, 0.12, 0.26, 0x1f2328, 0, -0.5, 0.58, 0.3, 0, 0, mg)
	b.bx(0.1, 0.14, 0.3, 0x1c1c1c, 0, 0.12, 0.22, -0.2)
	b.bx(0.08, 0.1, 0.3, 0x1c1c1c, 0, -0.82, 0.26)
	b.bx(0.03, 0.2, 0.04, 0x14171b, 0, -0.1, 0.12)
	b.bx(0.04, 0.5, 0.04, 0x9aa3ab, -0.05, 0.58, 0.0)
	b.bx(0.04, 0.5, 0.04, 0x9aa3ab, 0.05, 0.58, 0.0)
	b.bx(0.1, 0.05, 0.2, 0x2a3036, 0, 0.84, 0.03)
	b.bx(0.09, 0.2, 0.08, 0xffd24a, 0.11, -0.3, -0.02).name = "Bolt"


static func _uzi(b: _B) -> void:
	b.bx(0.15, 0.7, 0.2, 0x2a2f36, 0, -0.28, 0)
	b.bx(0.1, 0.62, 0.05, 0x1c2025, 0, -0.28, -0.12)
	b.bx(0.17, 0.12, 0.2, 0x3a4048, 0, -0.62, 0)
	b.cy(0.04, 0.04, 0.3, 0x14171b, 0, -0.84, 0, 6)
	b.cy(0.06, 0.06, 0.1, 0x14171b, 0, -1.02, 0, 6)
	b.bx(0.04, 0.05, 0.1, 0x14171b, 0, -0.74, -0.12)
	b.bx(0.11, 0.3, 0.16, 0x1a1d21, 0, 0.1, 0.16, -0.05)
	b.bx(0.03, 0.2, 0.04, 0x14171b, 0, -0.08, 0.15)
	b.bx(0.04, 0.22, 0.04, 0x9aa3ab, 0, 0.5, 0.02)
	var mg := _mag(b, "Mag")
	b.bx(0.09, 0.12, 0.5, 0x23272d, 0, 0.1, 0.38, 0, 0, 0, mg)
	b.bx(0.11, 0.14, 0.05, 0x14171b, 0, 0.1, 0.65, 0, 0, 0, mg)


static func _minigun(b: _B) -> void:
	b.cy(0.25, 0.25, 0.6, 0x6c7680, 0, -0.2, 0, 8)
	var spin := b.grp(0, 0, 0, "Spinner")
	for i in 6:
		var a := float(i) / 6.0 * TAU
		b.cy(0.04, 0.04, 1.25, 0x59636d, cos(a) * 0.14, -1.15, sin(a) * 0.14, 5, spin)
	for y in [-0.62, -1.0, -1.72]:
		b.cy(0.23, 0.23, 0.07, 0x8a949c, 0, y, 0, 8, spin)
		b.bx(0.07, 0.1, 0.07, 0x2a3036, 0.23, y, 0, 0, 0, 0, spin)
	var mg := _mag(b, "Mag")
	b.bx(0.3, 0.45, 0.28, 0x4b535a, 0, 0.1, 0.3, 0, 0, 0, mg)
	b.bx(0.1, 0.14, 0.3, 0x2a3640, 0, -0.1, 0.34)
	b.bx(0.08, 0.42, 0.08, 0x2a3640, 0, -0.25, -0.3)
	b.cy(0.15, 0.15, 0.2, 0x3a4249, 0, 0.15, 0, 8)
	var belt := b.grp(0, 0, 0, "Belt")                       # long belt of bullets from the ammo box into the gun (layoutBelt, full)
	var n := 44
	for i in n:
		var t := float(i) / (n - 1)
		var a := 1.0 - t
		var m := b.bx(0.1, 0.06, 0.04, 0xc9d1d8 if i % 4 == 3 else 0x7d8790,
			a * a * 0.25 + 2 * a * t * 0.6 + t * t * 0.17,
			a * a * -0.25 + 2 * a * t * -0.1 + t * t * 0.05,
			a * a * 0.17 + 2 * a * t * 0.85 + t * t * 0.42, 0, 0, 0, belt)
		m.rotation.y = atan2(2 * a * 0.35 + 2 * t * -0.43, 2 * a * 0.68 + 2 * t * -0.43)


static func _revolver(b: _B) -> void:
	b.bx(0.13, 0.42, 0.2, 0x8a949c, 0, -0.22, -0.2)
	b.cy(0.14, 0.14, 0.32, 0xc7ccd6, 0, -0.4, -0.2, 6).name = "Drum"
	var rs := b.cy(0.035, 0.035, 0.14, 0xe8c14a, 0, 0, 0, 6)
	rs.visible = false
	rs.name = "Shell"
	b.cy(0.05, 0.05, 0.8, 0x8a949c, 0, -0.9, -0.24, 6)
	b.bx(0.07, 0.5, 0.08, 0x8a949c, 0, -0.82, -0.16)
	b.bx(0.04, 0.05, 0.08, 0x2a3640, 0, -1.28, -0.3)
	b.bx(0.12, 0.14, 0.36, 0x6a4a2a, 0, 0.0, 0.0, -0.3)
	b.bx(0.05, 0.1, 0.07, 0x2a3640, 0, -0.04, -0.34, 0.4)
	b.bx(0.03, 0.03, 0.2, 0x2a3640, 0, -0.34, -0.06)
	b.bx(0.03, 0.12, 0.03, 0x2a3640, 0, -0.26, -0.08)
	_tip(b, 0, -1.32, -0.24)


static func _mammoth(b: _B) -> void:
	var slide := b.grp(0, 0, 0, "Slide")
	b.bx(0.17, 1.05, 0.24, 0x2b2f35, 0, -0.62, -0.2, 0, 0, 0, slide)
	b.bx(0.1, 0.92, 0.05, 0x14171a, 0, -0.62, -0.34, 0, 0, 0, slide)
	for i in 5:
		b.bx(0.19, 0.03, 0.2, 0x14171a, 0, -0.18 - i * 0.05, -0.2, 0, 0, 0, slide)
	b.bx(0.05, 0.07, 0.08, 0xffffff, 0, -1.08, -0.39, 0, 0, 0, slide)
	b.bx(0.12, 0.06, 0.08, 0x14171a, 0, -0.1, -0.37, 0, 0, 0, slide)
	b.bx(0.03, 0.26, 0.2, 0x0b0c0e, 0.09, -0.42, -0.2, 0, 0, 0, slide)
	b.cy(0.095, 0.095, 1.25, 0x1b1e22, 0, -1.05, -0.12, 8)
	b.cy(0.115, 0.115, 0.08, 0x0e1013, 0, -1.68, -0.12, 8)
	b.bx(0.15, 0.95, 0.17, 0x8c939c, 0, -0.55, -0.02)
	b.bx(0.14, 0.2, 0.12, 0x8c939c, 0, -0.25, 0.1)
	b.bx(0.14, 0.17, 0.5, 0x23262b, 0, 0.04, 0.12, -0.28)
	b.bx(0.16, 0.12, 0.36, 0x6a4a2a, 0, 0.04, 0.14, -0.28)
	var mg := _mag(b, "Mag")
	b.bx(0.12, 0.06, 0.2, 0x14171a, 0, 0.22, 0.33, -0.28, 0, 0, mg)
	b.bx(0.1, 0.3, 0.14, 0x23262b, 0, 0.1, 0.22, -0.28, 0, 0, mg)
	b.bx(0.04, 0.03, 0.34, 0x14171a, 0, -0.5, 0.1)
	b.bx(0.03, 0.14, 0.03, 0x14171a, 0, -0.38, 0.05)
	b.bx(0.05, 0.1, 0.06, 0x14171a, 0, -0.04, -0.12, 0.5)
	_tip(b, 0, -1.74, -0.12)


static func _shotgun(b: _B) -> void:
	b.bx(0.16, 0.55, 0.2, 0x3b4651, 0, -0.1, 0)
	b.cy(0.07, 0.07, 1.1, 0x2f3840, 0, -1.0, -0.03, 7)
	b.cy(0.055, 0.055, 0.9, 0x2f3840, 0, -0.95, 0.08, 6)
	b.cy(0.1, 0.1, 0.4, 0x7a4f2a, 0, -0.85, 0.08, 7).name = "Bolt"
	b.bx(0.04, 0.05, 0.1, 0xffd24a, 0, -1.52, -0.1)
	b.bx(0.13, 0.55, 0.2, 0x7a4f2a, 0, 0.58, 0.05, -0.12)
	b.bx(0.1, 0.12, 0.26, 0x2a3640, 0, 0.12, 0.17, -0.3)
	var rs := b.cy(0.06, 0.06, 0.22, 0xd9382f, 0, 0, 0, 7)
	rs.visible = false
	rs.name = "Shell"
	b.cy(0.065, 0.065, 0.05, 0xe8c14a, 0, 0.12, 0, 7, rs)


static func _sniper(b: _B) -> void:
	b.bx(0.13, 0.55, 0.15, 0x23272c, 0, -0.2, 0)
	b.bx(0.12, 0.3, 0.15, 0x23272c, 0, 0.2, 0)
	b.bx(0.14, 0.8, 0.17, 0x55663f, 0, -0.8, 0.03)
	b.bx(0.11, 0.7, 0.04, 0x3f4d2e, 0, -0.8, 0.13)
	b.cy(0.04, 0.04, 0.7, 0x15181b, 0, -1.55, 0, 7)
	b.cy(0.06, 0.06, 0.18, 0x101215, 0, -1.97, 0, 7)
	for y in [-1.93, -2.0]:
		b.cy(0.075, 0.075, 0.03, 0x15181b, 0, y, 0, 7)
	b.bx(0.14, 0.75, 0.2, 0x55663f, 0, 0.7, 0.05, -0.06)
	b.bx(0.12, 0.4, 0.08, 0x3f4d2e, 0, 0.62, -0.1)
	b.bx(0.15, 0.06, 0.26, 0x15181b, 0, 1.1, 0.07, -0.06)
	b.bx(0.1, 0.22, 0.16, 0x3f4d2e, 0, 0.02, 0.18, -0.3)
	b.bx(0.1, 0.3, 0.2, 0x1b1e22, 0, -0.3, 0.17)
	b.cy(0.07, 0.07, 0.65, 0x14171a, 0, -0.35, -0.2, 8)
	b.cy(0.075, 0.115, 0.2, 0x14171a, 0, -0.74, -0.2, 8)
	b.cy(0.1, 0.075, 0.16, 0x14171a, 0, 0.06, -0.2, 8)
	b.cy(0.1, 0.1, 0.025, 0x8fe8ff, 0, -0.85, -0.2, 8)
	b.cy(0.07, 0.07, 0.02, 0x2a6a8a, 0, 0.15, -0.2, 8)
	b.cy(0.03, 0.03, 0.09, 0x2a2e33, 0, -0.35, -0.29, 6)
	b.bx(0.09, 0.06, 0.06, 0x2a2e33, 0.09, -0.35, -0.2)
	b.bx(0.12, 0.07, 0.12, 0x23272c, 0, -0.17, -0.12)
	b.bx(0.12, 0.07, 0.12, 0x23272c, 0, -0.55, -0.12)
	b.bx(0.1, 0.06, 0.08, 0x23272c, 0, -1.0, 0.12)
	b.bx(0.025, 0.55, 0.025, 0x2a2e33, -0.06, -1.2, 0.15)
	b.bx(0.025, 0.55, 0.025, 0x2a2e33, 0.06, -1.2, 0.15)
	var bolt := b.bx(0.3, 0.06, 0.06, 0xe6edf2, 0.17, -0.05, 0)
	bolt.name = "Bolt"
	b.bx(0.11, 0.11, 0.11, 0xffffff, 0.18, 0, 0, 0, 0, 0, bolt)
	var rs := b.cy(0.04, 0.04, 0.2, 0xd8b04a, 0, 0, 0, 6)
	rs.visible = false
	rs.name = "Shell"


static func _flame(b: _B) -> void:
	var k1 := 0x121417
	var k2 := 0x1b1e22
	var k3 := 0x262a30
	var k4 := 0x363b43
	b.cy(0.08, 0.08, 1.7, k2, 0, -0.65, -0.25, 10)
	for y in [0.1, -0.15, -0.45, -0.75, -1.05, -1.3]:
		b.cy(0.105, 0.105, 0.05, k1, 0, y, -0.25, 10)
	b.cy(0.1, 0.1, 0.5, k3, 0, -0.95, -0.25, 10)
	for k in 4:
		b.bx(0.22, 0.05, 0.03, k1, 0, -0.78 - k * 0.1, -0.25)
	b.bx(0.2, 0.34, 0.2, k1, 0, 0.02, -0.25)
	b.bx(0.12, 0.12, 0.12, k4, 0, 0.26, -0.25)
	b.cy(0.1, 0.17, 0.3, k1, 0, -1.65, -0.25, 10)
	b.cy(0.175, 0.175, 0.05, 0x3a3a3a, 0, -1.82, -0.25, 10).name = "Glow"
	b.bx(0.03, 0.34, 0.03, k4, -0.13, -1.62, -0.25)
	b.ico(0.06, 0, 0xffb347, -0.13, -1.82, -0.25).name = "Pilot"
	_tip(b, 0, -1.9, -0.25)
	var tanks := b.grp(0, 0, 0, "Tanks")
	b.cy(0.17, 0.17, 0.95, k2, 0.22, -0.3, -0.45, 10, tanks)
	b.cy(0.1, 0.17, 0.1, k3, 0.22, 0.22, -0.45, 10, tanks)
	b.cy(0.17, 0.1, 0.1, k3, 0.22, -0.82, -0.45, 10, tanks)
	for y in [0.0, -0.6]:
		b.bx(0.38, 0.06, 0.38, k1, 0.22, y, -0.45, 0, 0, 0, tanks)
	b.bx(0.06, 0.06, 0.24, k1, 0.11, -0.05, -0.34, 0, 0, 0, tanks)
	b.bx(0.06, 0.06, 0.24, k1, 0.11, -0.55, -0.34, 0, 0, 0, tanks)
	b.cy(0.05, 0.05, 0.1, k4, 0.22, 0.3, -0.45, 6, tanks)
	b.bx(0.035, 0.6, 0.09, 0x050607, 0.395, -0.3, -0.45, 0, 0, 0, tanks)
	b.bx(0.04, 0.6, 0.06, 0xff8c2e, 0.4, -0.3, -0.45, 0, 0, 0, tanks).name = "Fuel"
	b.cy(0.06, 0.06, 0.03, 0xdddddd, 0.22, 0.34, -0.45, 12, tanks)
	var needle := b.grp(0.22, 0.36, -0.45, "Needle", tanks)
	b.bx(0.012, 0.012, 0.05, 0xd22222, 0, 0, -0.025, 0, 0, 0, needle)
	b.cy(0.03, 0.03, 0.5, k1, 0.1, -0.88, -0.38, 5)
	b.bx(0.1, 0.14, 0.32, k3, 0, 0.0, 0.0, -0.3)
	b.bx(0.04, 0.2, 0.04, k1, 0, -0.18, -0.08)
	b.bx(0.03, 0.1, 0.03, k4, 0, -0.1, -0.02)
	b.bx(0.12, 0.1, 0.16, k1, 0, -0.1, -0.2)
	b.bx(0.07, 0.07, 0.22, k3, 0.1, -0.88, -0.17, 0, PI / 4, 0)
	b.bx(0.075, 0.075, 0.36, k1, 0.285, -0.88, 0.0, 0, PI / 4, 0)
	for k in 3:
		b.bx(0.09, 0.09, 0.03, k4, 0.2 + k * 0.08, -0.88, -0.1 + k * 0.08, 0, PI / 4, 0)
	b.bx(0.09, 0.09, 0.05, k4, 0.42, -0.88, 0.13, 0, PI / 4, 0)
	b.bx(0.14, 0.12, 0.14, k1, 0.04, -0.88, -0.25)
	b.root.scale.x = -1.0                                    # modelled on the +X side; mirrored so the tank and handle sit on the LEFT


static func _net(b: _B) -> void:
	var k1 := 0x2a3036
	var ol := 0x56684a
	var od := 0x3f4f36
	var rp := 0xf2ead2
	b.cy(0.17, 0.17, 1.05, ol, 0, -0.55, -0.1, 10)
	b.cy(0.17, 0.25, 0.28, od, 0, -1.2, -0.1, 10)
	b.cy(0.25, 0.25, 0.04, k1, 0, -1.34, -0.1, 10)
	# the folded net waiting in the muzzle: a wireframe icosahedron (JS: MeshBasicMaterial wireframe)
	var src: Array = LowPoly.ico(0.2, 1).surface_get_arrays(0)
	var v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var lines := PackedVector3Array()
	for i in range(0, v.size(), 3):
		lines.append_array([v[i], v[i + 1], v[i + 1], v[i + 2], v[i + 2], v[i]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = lines
	var wm := ArrayMesh.new()
	wm.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var ball := b.mi(null, wm, rp, Vector3(0, -1.28, -0.1))
	ball.name = "NetBall"
	var bm: Material = ball.material_override
	if bm is BaseMaterial3D:
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for y in [-0.3, -0.5, -0.7]:
		b.mi(null, LowPoly.torus(0.18, 0.03, 4, 10), rp, Vector3(0, y, -0.1), Vector3(PI / 2, 0, 0))
	b.bx(0.3, 0.3, 0.3, k1, 0, 0.02, -0.1)
	b.cy(0.21, 0.21, 0.08, od, 0, 0.22, -0.1, 10)
	b.cy(0.07, 0.07, 0.45, 0xc4ccd4, 0, -0.1, -0.38, 8)
	b.cy(0.04, 0.04, 0.05, 0xff6b6b, 0, 0.14, -0.38, 6)
	b.bx(0.1, 0.14, 0.3, k1, 0, 0.14, 0.17, -0.3)
	b.bx(0.08, 0.14, 0.2, k1, 0, -0.62, 0.17)
	b.bx(0.04, 0.06, 0.1, 0xffd24a, 0, -1.05, -0.3)
	_tip(b, 0, -1.4, -0.1)


static func _rocket(b: _B) -> void:
	b.cy(0.2, 0.2, 1.7, 0x5f8f5a, 0, -0.5, -0.05, 9)
	b.cy(0.27, 0.2, 0.22, 0x3b4c5a, 0, 0.42, -0.05, 9)
	b.cy(0.24, 0.24, 0.12, 0x3b4c5a, 0, -1.35, -0.05, 9)
	b.mi(null, LowPoly.cyl(0.0, 0.17, 0.3, 9), 0xe3566b, Vector3(0, -1.55, -0.05), Vector3(PI, 0, 0))
	b.bx(0.1, 0.14, 0.3, 0x2a3640, 0, 0.0, 0.22, -0.2)
	b.bx(0.08, 0.1, 0.22, 0x2a3640, 0, -0.7, 0.2)
	b.bx(0.05, 0.2, 0.12, 0x2a3640, 0, -0.4, -0.3)


static func _meteor(b: _B) -> void:
	b.cy(0.3, 0.3, 1.5, 0x3a2a34, 0, -0.5, -0.05, 10)
	b.cy(0.36, 0.3, 0.3, 0x24181e, 0, 0.45, -0.05, 10)
	for y in [-0.15, -0.65, -1.05]:
		b.cy(0.33, 0.33, 0.07, 0xff6a2a, 0, y, -0.05, 10)
	b.cy(0.22, 0.22, 0.5, 0xffb347, 0, -0.45, -0.05, 6)
	b.mi(null, LowPoly.cyl(0.0, 0.3, 0.55, 10), 0xff3b1a, Vector3(0, -1.6, -0.05), Vector3(PI, 0, 0))
	for sx in [-1, 1]:
		b.bx(0.05, 0.3, 0.3, 0x24181e, sx * 0.38, 0.35, -0.05)
	b.bx(0.1, 0.14, 0.3, 0x2a3640, 0, 0.0, 0.3, -0.2)
	b.bx(0.08, 0.1, 0.22, 0x2a3640, 0, -0.7, 0.3)
	b.bx(0.05, 0.2, 0.12, 0x2a3640, 0, -0.4, -0.4)


static func _glauncher(b: _B) -> void:
	b.bx(0.16, 0.5, 0.22, 0x4a5560, 0, -0.15, 0)
	b.cy(0.16, 0.16, 0.75, 0x3a4650, 0, -0.75, -0.02, 8)
	b.cy(0.185, 0.185, 0.06, 0xe3566b, 0, -1.1, -0.02, 8)
	b.cy(0.21, 0.21, 0.28, 0x59636d, 0, -0.38, 0, 8)
	b.bx(0.14, 0.3, 0.14, 0x6a4a2a, 0, -0.78, 0.14)
	b.bx(0.12, 0.5, 0.16, 0x6a4a2a, 0, 0.5, 0.04)
	b.bx(0.1, 0.14, 0.28, 0x2a3640, 0, 0.1, 0.22, -0.3)
	b.bx(0.04, 0.16, 0.05, 0xffd24a, 0, -0.5, -0.2)


static func _cluster(b: _B) -> void:
	b.bx(0.16, 0.5, 0.22, 0x4a5560, 0, -0.15, 0)
	for dx in [-0.17, 0.0, 0.17]:
		var z: float = 0.02 if dx != 0.0 else -0.08
		b.cy(0.1, 0.1, 0.62, 0x3a4650, dx, -0.7, z, 8)
		b.cy(0.12, 0.12, 0.05, 0xe8a33a, dx, -1.03, z, 8)
	b.cy(0.24, 0.24, 0.26, 0xe8a33a, 0, -0.38, 0, 8)
	b.bx(0.14, 0.3, 0.14, 0x6a4a2a, 0, -0.78, 0.2)
	b.bx(0.12, 0.5, 0.16, 0x6a4a2a, 0, 0.5, 0.04)
	b.bx(0.1, 0.14, 0.28, 0x2a3640, 0, 0.1, 0.22, -0.3)


static func _snake(b: _B) -> void:
	b.bx(0.2, 0.6, 0.24, 0x3f9b4a, 0, -0.2, 0)
	for y in [-0.38, -0.2, -0.02]:
		b.cy(0.17, 0.17, 0.08, 0xffd93b if y == -0.2 else 0x2e7a3a, 0, y, 0, 8)
	b.mi(null, LowPoly.ico(1.0, 0), 0x4cc25a, Vector3(0, -0.78, 0), Vector3.ZERO, Vector3(0.24, 0.4, 0.2))
	for sx in [-0.13, 0.13]:
		b.bx(0.07, 0.09, 0.07, 0xffd93b, sx, -0.72, -0.08)
	b.bx(0.04, 0.3, 0.02, 0xe3566b, 0, -1.08, 0.0)
	b.bx(0.03, 0.1, 0.02, 0xe3566b, -0.04, -1.25, 0, 0, 0, 0.5)
	b.bx(0.03, 0.1, 0.02, 0xe3566b, 0.04, -1.25, 0, 0, 0, -0.5)
	b.bx(0.1, 0.14, 0.28, 0x2a3640, 0, 0.12, 0.2, -0.3)


static func _snow(b: _B) -> void:
	b.cy(0.17, 0.21, 0.9, 0xdff3fb, 0, -0.7, 0, 9)
	b.cy(0.26, 0.26, 0.12, 0x4a90d9, 0, -1.2, 0, 9)
	b.bx(0.22, 0.5, 0.26, 0x4a90d9, 0, -0.1, 0)
	b.ico(0.2, 0, 0xffffff, 0, -0.35, -0.32)
	b.bx(0.1, 0.14, 0.3, 0x2a3640, 0, 0.12, 0.2, -0.3)


# ---------------------------------------------------------------- thrown / bow
static func _bow(b: _B) -> void:
	b.bx(0.08, 0.12, 0.42, 0x6a4a2a, 0, 0, 0)
	for sg in [-1.0, 1.0]:
		b.bx(0.05, 0.1, 0.5, 0x8a5a2b, 0, 0.1, sg * 0.42, -sg * 0.28)
		b.bx(0.04, 0.1, 0.4, 0x8a5a2b, 0, 0.34, sg * 0.78, -sg * 0.75)
		b.cy(0.035, 0.035, 0.05, 0xe3566b, 0, 0.52, sg * 0.98, 5)
		b.mi(null, LowPoly.cyl(0.0, 0.045, 0.2, 4), 0xffd24a, Vector3(0, 0.62, sg * 1.04), Vector3(sg * 0.5, 0, 0))
		b.bx(0.07, 0.07, 0.16, 0xffd24a, 0, 0.0, sg * 0.14)
	# string and the two nocked arrows, at rest (updateBowMesh with draw = 0): nock point pulled back to y = 0.4
	var ny := 0.4
	var tip_y := 0.5
	var tip_z := 0.98
	for sg in [-1.0, 1.0]:
		var dy := ny - tip_y
		var dz: float = -sg * tip_z
		var s := b.mi(null, LowPoly.box(0.014, 1.0, 0.014), 0xf4f0e0, Vector3(0, (ny + tip_y) / 2.0, sg * tip_z / 2.0),
			Vector3(atan2(dz, dy), 0, 0), Vector3(1, sqrt(dy * dy + dz * dz), 1))
		s.name = "StringU" if sg < 0.0 else "StringL"
	var length := 1.05
	for z in [-0.07, 0.07]:
		var arrow := b.grp(0, 0, 0, "Arrow")
		b.mi(arrow, LowPoly.cyl(0.018, 0.018, 1.0, 5), 0xd9a066, Vector3(0, ny - length / 2.0 + 0.1, z), Vector3.ZERO, Vector3(1, length, 1))
		b.mi(arrow, LowPoly.cone(0.06, 0.16, 4), 0xc7ccd6, Vector3(0, ny - length + 0.1 - 0.05, z), Vector3(PI, 0, 0))
		b.mi(arrow, LowPoly.box(0.1, 0.12, 0.012), 0xe3566b, Vector3(0, ny - 0.02, z))


static func _knife(b: _B) -> void:
	b.cy(0.035, 0.04, 0.24, 0x6a4a2a, 0, 0, 0, 6)
	b.bx(0.15, 0.03, 0.05, 0xc7ccd6, 0, -0.14, 0)
	b.bx(0.05, 0.3, 0.014, 0xdfe6ec, 0, -0.3, 0)
	b.mi(null, LowPoly.cyl(0.0, 0.03, 0.14, 4), 0xdfe6ec, Vector3(0, -0.52, 0), Vector3(PI, 0, 0), Vector3(1, 1, 0.25))


static func _blade_mesh(wm: float) -> ArrayMesh:             # typhoonBladeGeo: one flat curved blade
	var r0 := 0.19
	var r1 := 0.5
	var n := 14
	var pos := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		var th := t * TAU / 3.0
		var r := r0 + (r1 - r0) * pow(t, 0.85)
		var w := (0.03 + 0.13 * sin(PI * minf(1.0, t * 1.08))) * (1.0 - pow(t, 2.5)) * wm
		var cx := cos(th)
		var cz := sin(th)
		pos.append(Vector3(cx * (r - w / 2.0), 0, cz * (r - w / 2.0)))
		pos.append(Vector3(cx * (r + w / 2.0), 0, cz * (r + w / 2.0)))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in n:
		var a := i * 2
		for k in [a, a + 1, a + 2, a + 1, a + 3, a + 2]:
			verts.append(pos[k])
			norms.append(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _double_sided(mi: MeshInstance3D) -> void:
	var m: Material = mi.material_override
	if m is BaseMaterial3D:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED


static func _typhoon(b: _B) -> void:
	var star := b.grp(0, -0.14, 0, "Star")
	for i in 3:
		var arm := b.grp(0, 0, 0, "Arm", star)
		arm.rotation.y = float(i) / 3.0 * TAU
		_double_sided(b.mi(arm, _blade_mesh(1.0), 0x7ee8ff, Vector3.ZERO))
		_double_sided(b.mi(arm, _blade_mesh(0.42), 0xe8fbff, Vector3(0, 0.006, 0)))
	b.cy(0.19, 0.19, 0.05, 0x2d7fb0, 0, 0, 0, 14, star)
	b.mi(star, LowPoly.torus(0.19, 0.03, 4, 14), 0xe8fbff, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	b.cy(0.07, 0.07, 0.08, 0x23405a, 0, 0, 0, 8, star)
	star.scale = Vector3.ONE * 0.62


static func _shuriken(b: _B) -> void:
	var star := b.grp(0, -0.12, 0, "Star")
	for r in [PI / 4, -PI / 4]:
		b.mi(star, LowPoly.box(0.62, 0.035, 0.13), 0xdfe6ec, Vector3.ZERO, Vector3(0, r, 0))
		for sg in [-1.0, 1.0]:
			b.mi(star, LowPoly.cone(0.065, 0.16, 4), 0xdfe6ec, Vector3(cos(r) * sg * 0.38, 0, -sin(r) * sg * 0.38), Vector3(0, r, -sg * PI / 2))
	b.cy(0.1, 0.1, 0.06, 0xe3566b, 0, 0, 0, 8, star)
	star.rotation.x = PI / 2
	b.cy(0.03, 0.03, 0.3, 0x59636d, 0, 0.1, 0, 5)


static func _boomerang(b: _B) -> void:
	var bg := b.grp(0, -0.5, 0, "Boomerang")
	bg.rotation.x = PI / 2
	var sc := 0.8
	var rr := 0.62
	var n := 10
	var a := 0.95
	for i in n:
		var u := (float(i) + 0.5) / n * 2.0 - 1.0
		var th := u * a
		var edge := absf(u)
		var ln := (2.0 * a * rr / n) * 1.12
		var wd := 0.2 - edge * 0.09
		var col := 0xe3566b if edge > 0.82 else (0xfff3d6 if edge > 0.7 else (0xd9964b if i % 2 == 1 else 0xe8ab5c))
		b.mi(bg, LowPoly.box(ln, 0.055, wd), col, Vector3(sin(th) * rr * sc, 0, (cos(th) * rr - rr) * sc), Vector3(0, -th, 0), Vector3(sc, 1, sc))
	b.cy(0.09 * sc, 0.09 * sc, 0.075, 0xffd24a, 0, 0, 0, 8, bg)
	b.cy(0.04, 0.04, 0.2, 0x6a4a2a, 0, 0.0, 0, 5)
