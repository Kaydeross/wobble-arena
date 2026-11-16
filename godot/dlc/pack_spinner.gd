class_name PackSpinner
extends Node3D
## The visible half of a pack's spinning Hills Hoist (PackZones "hoist" zone): `arms` bars at the top of the hit band with washing hung
## along them, turned every frame to the angle PackZones.hoist_angle gives for the sim clock, so what you see is what hits you
## (the hit band is y0..y1 above the floor). Built from one merged mesh per colour: a handful of draw calls, no per-box nodes.
## Also used for the temporary sweep a `hoist_sweep` stage event adds. Presentation only: it never touches the simulation.

const CLOTH := [0xe34a3a, 0xf1f4f6, 0x3a76c8, 0xf2c230, 0x3a8f5a]
const BAR := 0xcfd4d8

var zone: Dictionary = {}


## A spinner node for `zone` ({x, z, r, arms, omega, phase, y0, y1}); `speed_up` only affects how far the washing hangs.
static func build(z: Dictionary) -> PackSpinner:
	var s := PackSpinner.new()
	s.name = "HillsHoist"
	s.zone = z
	s.position = Vector3(float(z["x"]), 0.0, float(z["z"]))
	var r := float(z["r"])
	var arms := maxi(1, int(z.get("arms", 4)))
	var y0 := float(z.get("y0", 0.8))
	var y1 := float(z.get("y1", 1.7))
	var groups := {}
	for k in arms:
		var basis := Basis(Vector3.UP, -TAU * float(k) / float(arms))
		_add(groups, BAR, Transform3D(basis, basis * Vector3(r / 2.0, y1, 0.0)), Vector3(r, 0.2, 0.2))
		var n := maxi(2, int(r / 1.2))
		for i in n:
			var along := 0.9 + (float(i) + 0.5) * (r - 1.2) / float(n)
			var col: int = CLOTH[(k * 3 + i) % CLOTH.size()]
			_add(groups, col, Transform3D(basis, basis * Vector3(along, (y0 + y1) / 2.0 - 0.05, 0.0)), Vector3(0.95, y1 - y0 - 0.15, 0.06))
	for c: int in groups:
		var mi := MeshInstance3D.new()
		mi.name = "Hoist_%06x" % c
		mi.mesh = (groups[c] as SurfaceTool).commit()
		mi.material_override = MapBuilder.material(c)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.add_child(mi)
	s.rotation.y = -PackZones.hoist_angle(z, PackZones.clock)
	return s


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
