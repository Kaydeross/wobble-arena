class_name PackSpinner
extends Node3D
## The visible half of a pack's spinning Hills Hoist (PackZones "hoist" zone): `arms` bars at the top of the hit band with washing hung
## along them, turned every frame to the angle PackZones.hoist_angle gives for the sim clock, so what you see is what hits you
## (the hit band is y0..y1 above the floor; the lines between the arms are thin and sit above it). Built from one merged mesh per
## colour: about ten draw calls, no per-box nodes. It casts a shadow, so the turn also reads on the lawn.
## Also used for the temporary sweep a `hoist_sweep` stage event adds. Presentation only: it never touches the simulation.

const CLOTH := [0xe34a3a, 0xf1f4f6, 0x3a76c8, 0xf2c230, 0x3a8f5a, 0xe86fa5]
const BAR := 0xcfd4d8
const LINE := 0xf4f6f7
const PEG := 0x9b6b3d
const HUB_Y := 3.82             ## where the stays meet the pole (AustraliaProps.hoist: the hub box on a 3.7 m pole)
const TRAIL := 0.3              ## rad at 1 rad/s: how far the washing trails behind its arm

var zone: Dictionary = {}


## A spinner node for `zone` ({x, z, r, arms, omega, phase, y0, y1}): per arm a bar along the top of the hit band, a stay up to the
## hub, and big washing hung in the band (towels, shirts, shorts, a sheet) that trails behind the arm the way it turns; between the
## arms three rings of clothes line with pegs and socks, and a pennant on the hub. All of it turns together.
static func build(z: Dictionary) -> PackSpinner:
	var s := PackSpinner.new()
	s.name = "HillsHoist"
	s.zone = z
	s.position = Vector3(float(z["x"]), 0.0, float(z["z"]))
	var r := float(z["r"])
	var arms := maxi(1, int(z.get("arms", 4)))
	var y0 := float(z.get("y0", 0.8))
	var y1 := float(z.get("y1", 1.7))
	var band := y1 - y0
	var omega := float(z.get("omega", 1.0))
	var lean := clampf(omega * TRAIL, -0.45, 0.45)              # about the arm: the hem swings back against the turn
	var groups := {}
	var stay_len := sqrt(r * r + (HUB_Y - y1) * (HUB_Y - y1))
	var stay_tilt := atan2(HUB_Y - y1, r)
	for k in arms:
		var basis := Basis(Vector3.UP, -TAU * float(k) / float(arms))
		_add(groups, BAR, Transform3D(basis, basis * Vector3(r / 2.0, y1, 0.0)), Vector3(r, 0.16, 0.16))
		_add(groups, BAR, Transform3D(basis * Basis(Vector3(0, 0, 1), -stay_tilt), basis * Vector3(r / 2.0, (HUB_Y + y1) / 2.0, 0.0)), Vector3(stay_len, 0.07, 0.07))
		_add(groups, CLOTH[(k * 2) % CLOTH.size()], Transform3D(basis, basis * Vector3(r, y1, 0.0)), Vector3(0.3, 0.3, 0.3))     # the arm's end cap: one colour per arm
		# the washing on this arm, hung from the bar (the hinge) and leaning back
		var hang := basis * Basis(Vector3(1, 0, 0), lean)
		var at := 1.0
		var i := 0
		while at < r - 0.7:
			var kind := (k * 2 + i) % 4
			var col: int = CLOTH[(k * 3 + i * 2) % CLOTH.size()]
			var col2: int = CLOTH[(k * 3 + i * 2 + 1) % CLOTH.size()]
			var w: float = [1.05, 1.1, 0.8, 1.45][kind]
			if at + w > r - 0.2: break
			match kind:
				0:                                                 # a beach towel with two stripes
					_hung(groups, col, hang, basis, at + w / 2.0, y1, 0.0, band - 0.08, w, 0.07)
					_hung(groups, col2, hang, basis, at + w / 2.0, y1, 0.16, 0.12, w + 0.01, 0.09)
					_hung(groups, col2, hang, basis, at + w / 2.0, y1, band - 0.34, 0.12, w + 0.01, 0.09)
				1:                                                 # a T-shirt: sleeves and a body
					_hung(groups, col, hang, basis, at + w / 2.0, y1, 0.0, 0.26, w, 0.07)
					_hung(groups, col, hang, basis, at + w / 2.0, y1, 0.26, band - 0.42, 0.66, 0.07)
				2:                                                 # shorts: a waistband and two legs
					_hung(groups, col, hang, basis, at + w / 2.0, y1, 0.0, 0.3, w, 0.07)
					_hung(groups, col, hang, basis, at + 0.18, y1, 0.3, 0.36, 0.36, 0.07)
					_hung(groups, col, hang, basis, at + w - 0.18, y1, 0.3, 0.36, 0.36, 0.07)
				_:                                                 # a sheet, the full height of the band
					_hung(groups, col, hang, basis, at + w / 2.0, y1, 0.0, band, w, 0.06)
					_hung(groups, col2, hang, basis, at + w / 2.0, y1, band - 0.14, 0.14, w + 0.01, 0.08)
			for e: float in [0.14, w - 0.14]:                      # pegs
				_add(groups, PEG, Transform3D(basis, basis * Vector3(at + e, y1 + 0.08, 0.0)), Vector3(0.07, 0.16, 0.2))
			at += w + 0.22
			i += 1
		# the lines from this arm to the next: chords at three radii, the middle one with socks on it
		if arms >= 3:
			var half := PI / float(arms)
			var mid := Basis(Vector3.UP, -(TAU * float(k) / float(arms) + half))
			for j in 3:
				var rho := r * (0.45 + 0.27 * float(j))
				var apo := rho * cos(half)
				_add(groups, LINE, Transform3D(mid, mid * Vector3(apo, y1 + 0.04, 0.0)), Vector3(0.05, 0.05, 2.0 * rho * sin(half)))
				if j == 1:
					for e: float in [-0.7, 0.0, 0.7]:
						_add(groups, CLOTH[(k + int(e * 3.0) + 7) % CLOTH.size()], Transform3D(mid, mid * Vector3(apo, y1 - 0.14, e)), Vector3(0.06, 0.36, 0.18))
	# the pennant on the hub: one of a kind, so a turn is easy to read
	_add(groups, CLOTH[0], Transform3D(Basis.IDENTITY, Vector3(0.45, HUB_Y + 0.5, 0.0)), Vector3(0.8, 0.4, 0.05))
	_add(groups, BAR, Transform3D(Basis.IDENTITY, Vector3(0.0, HUB_Y + 0.35, 0.0)), Vector3(0.08, 0.8, 0.08))
	for c: int in groups:
		var mi := MeshInstance3D.new()
		mi.name = "Hoist_%06x" % c
		mi.mesh = (groups[c] as SurfaceTool).commit()
		mi.material_override = MapBuilder.material(c)
		s.add_child(mi)
	s.rotation.y = -PackZones.hoist_angle(z, PackZones.clock)
	return s


## One piece of washing: `w` wide along the arm at `along`, hanging from `top - drop` down `h`, hinged on the bar (so `hang` leans it).
static func _hung(groups: Dictionary, col: int, hang: Basis, arm: Basis, along: float, top: float, drop: float, h: float, w: float, th: float) -> void:
	_add(groups, col, Transform3D(hang, arm * Vector3(along, top, 0.0) + hang * Vector3(0.0, -(drop + h / 2.0), 0.0)), Vector3(w, h, th))


static func _add(groups: Dictionary, col: int, t: Transform3D, size: Vector3) -> void:
	if not groups.has(col):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[col] = st
	var bm := BoxMesh.new()
	bm.size = size
	(groups[col] as SurfaceTool).append_from(bm, 0, t)


func _process(_delta: float) -> void:
	if zone.is_empty(): return
	rotation.y = -PackZones.hoist_angle(zone, PackZones.clock)
