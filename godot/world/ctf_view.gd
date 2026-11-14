class_name CtfView
extends Node3D
## Capture the Flag visuals (logic/ctf.gd): a round stand, a pole with a cloth, and a thin light beam so the flag can be found
## across the arena. On the stand or where it was dropped the flag is white; carried, it is a small flag on the carrier's back
## in their team's colour (ModeRules.TEAM_COL). Primitive meshes only, no assets. World calls update() once per frame.

var rules: CtfRules
var _flag: Node3D                 ## pole + cloth, moved to wherever the flag is
var _cloth: MeshInstance3D
var _beam: MeshInstance3D
var _base: Node3D                 ## the stand, always at its place
var _cloth_mat: StandardMaterial3D
var _t := 0.0

static func _mat(c: Color, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emit:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func bind(r: CtfRules) -> void:
	rules = r
	_base = Node3D.new(); _base.name = "FlagStand"; add_child(_base)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.75; cm.bottom_radius = 0.85; cm.height = 0.18; cm.radial_segments = 20
	disc.mesh = cm; disc.material_override = _mat(Color(0.95, 0.8, 0.3)); disc.position.y = 0.09
	_base.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 1.15; tm.outer_radius = 1.4; tm.rings = 24; tm.ring_segments = 6
	ring.mesh = tm; ring.material_override = _mat(Color(1, 0.9, 0.4, 1), true); ring.position.y = 0.05
	_base.add_child(ring)
	_base.position = r.stand
	_flag = Node3D.new(); _flag.name = "Flag"; add_child(_flag)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new(); pm.top_radius = 0.04; pm.bottom_radius = 0.05; pm.height = 2.6; pm.radial_segments = 8
	pole.mesh = pm; pole.material_override = _mat(Color(0.85, 0.85, 0.9)); pole.position.y = 1.3
	_flag.add_child(pole)
	_cloth = MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.9, 0.55, 0.05)
	_cloth.mesh = bm
	_cloth_mat = _mat(Color.WHITE)
	_cloth.material_override = _cloth_mat
	_cloth.position = Vector3(0.47, 2.3, 0.0)
	_flag.add_child(_cloth)
	_beam = MeshInstance3D.new()
	var bc := CylinderMesh.new(); bc.top_radius = 0.07; bc.bottom_radius = 0.07; bc.height = 14.0; bc.radial_segments = 6
	_beam.mesh = bc
	var bmat := _mat(Color(1, 0.95, 0.5, 0.35), true)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam.material_override = bmat; _beam.position.y = 7.0
	_flag.add_child(_beam)
	update(0.0)

## The flag's place now: on the carrier's back (small, team colour) or at rules.pos (full size, white).
func update(dt: float) -> void:
	if rules == null: return
	_t += dt
	var c := rules.carrier
	if c != null:
		var p := c.phys
		var back := Vector3(-sin(c.yaw), 0.0, -cos(c.yaw)) * 0.38
		_flag.position = Vector3(p.px, p.py + 0.55, p.pz) + back
		_flag.scale = Vector3.ONE * 0.5
		_flag.rotation.y = c.yaw
		_beam.visible = false
		var col: int = ModeRules.TEAM_COL[clampi(rules.holder, 0, 1)]
		_cloth_mat.albedo_color = Color.hex(col << 8 | 0xff)
	else:
		_flag.position = rules.pos
		_flag.scale = Vector3.ONE
		_flag.rotation.y = 0.0
		_beam.visible = true
		_cloth_mat.albedo_color = Color.WHITE
	_cloth.rotation.y = sin(_t * 4.0) * 0.18          # the cloth flaps a little
