class_name Gfx
extends RefCounted
## Per-match graphics extras that are not part of a map (docs/GRAPHICS.md), all behind the tier switch:
##   Gfx.add_post(world)          MID / HIGH: a gentle screen vignette under the HUD
##   Gfx.dress_fighter(fighter)   LOW: a contact shadow blob under the fighter, and its parts stop casting real shadows
## Map look (sky, fog, grade, materials, moving scenery, clouds) lives in MapBuilder; shadow cascades in Tier.

const VIGNETTE := "res://shaders/vignette.gdshader"
const BLOB := "res://shaders/blob_shadow.gdshader"

static func add_post(host: Node) -> void:
	if MapBuilder.gfx_q() < 1 or host.has_node("Vignette"):
		return
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = 0                      # over the 3D view, under the HUD (UI layer 1)
	var rect := ColorRect.new()
	rect.name = "Rect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load(VIGNETTE)
	rect.material = m
	layer.add_child(rect)
	host.add_child(layer)

static func dress_fighter(f: Node3D) -> void:
	if MapBuilder.gfx_q() >= 1 or f.has_node("BlobShadow"):
		return
	for n in f.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blob := BlobShadow.new()
	blob.name = "BlobShadow"
	f.add_child(blob)


## A soft dark disc on the ground under a fighter: follows its physics position, drops to the highest solid top below
## it while airborne, fades and grows with height. One quad, one tiny shader.
class BlobShadow extends MeshInstance3D:
	var _mat: ShaderMaterial

	func _ready() -> void:
		var q := QuadMesh.new()
		q.size = Vector2(1.5, 1.5)
		q.orientation = PlaneMesh.FACE_Y
		mesh = q
		_mat = ShaderMaterial.new()
		_mat.shader = load(BLOB)
		material_override = _mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		top_level = true

	func _process(_dt: float) -> void:
		var f := get_parent()
		var st: Variant = f.get("state")
		if st == null:
			return
		var p: FighterPhysics = st.phys
		var world := f.get_parent().get_parent() if f.get_parent() else null
		var solids: Array = world.get("solids") if world and world.get("solids") is Array else []
		var g := p.py
		if not p.grounded:
			g = -INF
			for s: Dictionary in solids:
				if p.px >= s.minX and p.px <= s.maxX and p.pz >= s.minZ and p.pz <= s.maxZ and s.top <= p.py + 0.05 and s.top > g:
					g = s.top
		visible = not st.dead and g > -INF
		if not visible:
			return
		var h := clampf(p.py - g, 0.0, 6.0)
		global_position = Vector3(p.px, g + 0.03, p.pz)
		scale = Vector3.ONE * (1.0 + h * 0.08)
		_mat.set_shader_parameter("fade", 1.0 - h / 6.0)
