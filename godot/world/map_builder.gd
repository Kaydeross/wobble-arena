class_name MapBuilder
extends RefCounted
## Builds a map's visuals from res://data/maps.json (copy of shared/maps.json) and its collision solids.
## Ported from addBox / addLadder / addFloorPad / addBouncePad / loadMap env (public/index.html ~1574-1612, ~7643-7651).
## Decor that maps.json does not have (trees, far scenery, clouds) is skipped; the art pass replaces material().
##
##   var m := MapBuilder.build("arena")   # MapBuilder.MapNode (a Node3D)
##   m.solids                              # FighterPhysics solids
##   world_env.environment = MapBuilder.make_environment(m.map)

## The built map: visuals as children plus the gameplay data the sim needs.
class MapNode extends Node3D:
	var map_id := ""
	var map: Dictionary = {}
	var solids: Array = []        ## FighterPhysics.solids_from_map(map)
	var pads: Array = []          ## bounce pads {x, z, r, power}
	var ladders: Array = []       ## {x, z, nx, nz, y0, y1}
	var shadow_area := 32.0       ## half-size of the sun's shadow box (maps.json `shadow`)

	func spawn_point() -> Vector3:   ## the player's start, like loadMap (`m.player`, y = spawnY or 0.01)
		var p: Array = map.get("player", [0, 0])
		var y := float(p[2]) if p.size() > 2 else float(map.get("spawnY", 0.01))
		return Vector3(float(p[0]), y, float(p[1]))

const PAD_COLOR := 0x4fe0cf
const PAD_CORE_COLOR := 0xe9fffb
const LADDER_COLOR := 0xc79a5a
const HILL_COUNT := 16
const VOID_Y := -30.0

static var _materials: Dictionary = {}

## Build a map by id from the Content autoload.
static func build(map_id: String) -> MapNode:
	var content := _content()
	var map: Dictionary = content.get_map(map_id) if content else _load_maps_file().get(map_id, {})
	if map.is_empty():
		push_error("MapBuilder: unknown map " + map_id)
	return build_from(map_id, map)

## Build from a map Dictionary (one entry of maps.json).
static func build_from(map_id: String, map: Dictionary) -> MapNode:
	var root := MapNode.new()
	root.name = "Map_" + map_id
	root.map_id = map_id
	root.map = map
	var geo: Dictionary = map.get("geometry", {"boxes": [], "ladders": [], "bouncePads": [], "floorPads": []})
	root.solids = FighterPhysics.solids_from_map({"geometry": geo})
	root.shadow_area = float(map.get("shadow", 32))
	_add_boxes(root, geo.get("boxes", []))
	for fp in geo.get("floorPads", []):
		_add_floor_pad(root, float(fp["size"]), int(fp["color"]))
	for bp in geo.get("bouncePads", []):
		_add_bounce_pad(root, float(bp["x"]), float(bp["z"]))
		root.pads.append(bp)
	for l in geo.get("ladders", []):
		_add_ladder(root, float(l["x"]), float(l["z"]), float(l["nx"]), float(l["nz"]), float(l["y0"]), float(l["y1"]))
		root.ladders.append(l)
	_add_backdrop(root, map)
	return root

## THE material factory (like the web game's `lm`). Swap this for the art pass; everything in a map goes through it.
static func material(color: int) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = hex(color)
	m.roughness = 0.95
	m.metallic = 0.0
	m.metallic_specular = 0.3
	_materials[color] = m
	return m

static func hex(c: int) -> Color:
	return Color.hex((c << 8) | 0xff)

## Mix two 0xRRGGBB colours like the web game's mixHex.
static func mix_hex(a: int, b: int, t: float) -> int:
	var r := roundi(((a >> 16) & 255) + (((b >> 16) & 255) - ((a >> 16) & 255)) * t)
	var g := roundi(((a >> 8) & 255) + (((b >> 8) & 255) - ((a >> 8) & 255)) * t)
	var bl := roundi((a & 255) + ((b & 255) - (a & 255)) * t)
	return (r << 16) | (g << 8) | bl

## Sky, ambient, fog for a map (loadMap ~7647: background = fog colour = sky, fog [50, 160] unless the map sets `fog`, hemi intensity).
static func make_environment(map: Dictionary) -> Environment:
	var sky_c := int(map.get("sky", 0xbfe3f2))
	var top := int(map["skyTop"]) if map.has("skyTop") else mix_hex(sky_c, 0x4a8fe0, 0.62)
	var env_d: Dictionary = map.get("env", {})
	if env_d.has("top"):
		top = int(env_d["top"])
	var env := Environment.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = hex(top)
	sm.sky_horizon_color = hex(sky_c)
	sm.ground_horizon_color = hex(sky_c)
	sm.ground_bottom_color = hex(int(map.get("voidColor", sky_c)))
	sm.sky_curve = 0.12
	sm.ground_curve = 0.05
	sm.sun_angle_max = 8.0
	sm.sun_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# HemisphereLight(0xffffff, 0x9bb7c4, hemi) stand-in: a flat ambient between the two colours
	var hemi := float(map.get("hemi", 0.95))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = hex(0xffffff).lerp(hex(0x9bb7c4), 0.5)
	# three.js r160 (physically based lights) divides by PI where Godot does not: energy = intensity / PI keeps the same look
	env.ambient_light_energy = hemi / PI
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var fog: Array = map.get("fog", [50, 160])
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = hex(sky_c)
	env.fog_density = 1.0
	env.fog_depth_begin = float(fog[0])
	env.fog_depth_end = float(fog[1])
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	return env

## Sun for a map: position (sh*0.7, sh*1.2, sh*0.38) toward the centre, intensity sunI (default 1.35).
static func setup_sun(sun: DirectionalLight3D, map: Dictionary) -> void:
	var sh := float(map.get("shadow", 32))
	var p := Vector3(sh * 0.7, sh * 1.2, sh * 0.38)
	sun.transform = Transform3D(Basis.looking_at(-p.normalized(), Vector3.UP), p)
	sun.light_energy = float(map.get("sunI", 1.35)) / PI
	var env_d: Dictionary = map.get("env", {})
	var sc := int(map.get("sunColor", env_d.get("sunColor", 0xffffff)))
	sun.light_color = hex(0xffffff).lerp(hex(sc), 0.35)

# ---------------------------------------------------------------- builders

## Static boxes merged into one mesh per colour (fewer draw calls); each box is still its own solid.
## Roofs (big boxes high up, like the Practice Range ceiling) do not cast shadows, as in the web game (`roof.castShadow = false`).
static func _add_boxes(root: Node3D, boxes: Array) -> void:
	var groups := {}
	for b in boxes:
		var c := int(b["color"])
		var key := Vector2i(c, 0 if _is_roof(b) else 1)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(b)
	for key in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b in groups[key]:
			var bm := BoxMesh.new()
			bm.size = Vector3(float(b["w"]), float(b["h"]), float(b["d"]))
			st.append_from(bm, 0, Transform3D(Basis(), Vector3(float(b["x"]), float(b["y"]) + float(b["h"]) / 2.0, float(b["z"]))))
		var mi := MeshInstance3D.new()
		mi.name = ("Boxes_%06x" if key.y == 1 else "Roof_%06x") % key.x
		mi.mesh = st.commit()
		mi.material_override = material(key.x)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key.y == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

## Dynamic arenas: rebuild the merged box meshes without the boxes in `exclude` (index -> true); the world draws
## those itself (floor tiles, drifting blocks). Collision is not touched here.
static func rebuild_boxes(root: Node3D, boxes: Array, exclude: Dictionary) -> void:
	for c in root.get_children():
		var n := str(c.name)
		if n.begins_with("Boxes_") or n.begins_with("Roof_"):
			root.remove_child(c); c.queue_free()
	var keep: Array = []
	for i in boxes.size():
		if not exclude.has(i): keep.append(boxes[i])
	_add_boxes(root, keep)

static func _is_roof(b: Dictionary) -> bool:
	return float(b["y"]) >= 6.0 and float(b["w"]) * float(b["d"]) >= 1500.0

static func _add_floor_pad(root: Node3D, size: float, color: int) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.name = "FloorPad"
	mi.mesh = pm
	mi.material_override = material(color)
	mi.position.y = 0.01
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

static func _add_bounce_pad(root: Node3D, x: float, z: float) -> void:
	var pad := Node3D.new()
	pad.name = "BouncePad"
	pad.position = Vector3(x, 0.0, z)
	var ring := CylinderMesh.new()
	ring.top_radius = 1.15; ring.bottom_radius = 1.25; ring.height = 0.14; ring.radial_segments = 10; ring.rings = 1
	var m := MeshInstance3D.new()
	m.mesh = _flat(ring); m.material_override = material(PAD_COLOR); m.position.y = 0.07
	pad.add_child(m)
	var core := CylinderMesh.new()
	core.top_radius = 0.65; core.bottom_radius = 0.65; core.height = 0.2; core.radial_segments = 10; core.rings = 1
	var c := MeshInstance3D.new()
	c.name = "Core"
	c.mesh = _flat(core); c.material_override = material(PAD_CORE_COLOR); c.position.y = 0.08
	pad.add_child(c)
	root.add_child(pad)

## (x, z) = spot on the wall face, (nx, nz) = outward direction from the wall. Rails + rungs, one merged mesh.
static func _add_ladder(root: Node3D, x: float, z: float, nx: float, nz: float, y0: float, y1: float) -> void:
	var tx := -nz
	var tz := nx
	var along_x := nx != 0.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sg in [-1.0, 1.0]:
		var rail := BoxMesh.new()
		rail.size = Vector3(0.08, y1 - y0 + 0.5, 0.08)
		st.append_from(rail, 0, Transform3D(Basis(), Vector3(x + nx * 0.1 + tx * sg * 0.33, y0 + (y1 - y0) / 2.0 + 0.05, z + nz * 0.1 + tz * sg * 0.33)))
	var y := y0 + 0.35
	while y < y1 + 0.2:
		var rung := BoxMesh.new()
		rung.size = Vector3(0.07 if along_x else 0.7, 0.07, 0.7 if along_x else 0.07)
		st.append_from(rung, 0, Transform3D(Basis(), Vector3(x + nx * 0.1, y, z + nz * 0.1)))
		y += 0.38
	var mi := MeshInstance3D.new()
	mi.name = "Ladder"
	mi.mesh = st.commit()
	mi.material_override = material(LADDER_COLOR)
	root.add_child(mi)

## Far low-poly hills on a ring and the pale void plane below (index.html ~1856-1866), coloured from `hills` / `voidColor`.
## Seeded so every client sees the same hills.
static func _add_backdrop(root: Node3D, map: Dictionary) -> void:
	var cols: Array = map.get("hills", [0x8fc9b0, 0x7bb89f, 0xa3d6bd, 0x6fa994])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var by_color := {}
	for i in HILL_COUNT:
		var a := float(i) / HILL_COUNT * TAU + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(85.0, 120.0)
		var h := rng.randf_range(14.0, 34.0)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0; cone.bottom_radius = rng.randf_range(14.0, 26.0); cone.height = h; cone.radial_segments = 6; cone.rings = 1
		var c := int(cols[i % cols.size()])
		if not by_color.has(c):
			by_color[c] = SurfaceTool.new()
			by_color[c].begin(Mesh.PRIMITIVE_TRIANGLES)
		_append_flat(by_color[c], cone, Transform3D(Basis(), Vector3(cos(a) * r, VOID_Y + h / 2.0 + 6.0, sin(a) * r)))
	for c in by_color:
		var mi := MeshInstance3D.new()
		mi.name = "Hills_%06x" % c
		mi.mesh = by_color[c].commit()
		mi.material_override = material(c)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var vp := PlaneMesh.new()
	vp.size = Vector2(600, 600)
	var v := MeshInstance3D.new()
	v.name = "Void"
	v.mesh = vp
	v.material_override = material(int(map.get("voidColor", 0xa9d6e5)))
	v.position.y = VOID_Y
	v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(v)

## Faceted (flat-shaded) copy of a primitive mesh, like three.js flatShading: every triangle gets its own face normal.
static func _flat(mesh: PrimitiveMesh, xf := Transform3D()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_flat(st, mesh, xf)
	return st.commit()

static func _append_flat(st: SurfaceTool, mesh: PrimitiveMesh, xf: Transform3D) -> void:
	var arr := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var n := idx.size() if idx.size() > 0 else verts.size()
	for t in range(0, n, 3):
		var i0 := idx[t] if idx.size() > 0 else t
		var i1 := idx[t + 1] if idx.size() > 0 else t + 1
		var i2 := idx[t + 2] if idx.size() > 0 else t + 2
		var a := xf * verts[i0]
		var b := xf * verts[i1]
		var c := xf * verts[i2]
		var nrm := (c - a).cross(b - a)
		if nrm.length_squared() < 1e-12:
			continue   # degenerate (cone tip)
		nrm = nrm.normalized()
		if nrm.dot(xf.basis * (norms[i0] + norms[i1] + norms[i2])) < 0.0:
			nrm = -nrm   # keep the primitive's outward side
		for v in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(v)

static func _content() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root.has_node("Content"):
		return tree.root.get_node("Content")
	return null

static func _load_maps_file() -> Dictionary:
	return load("res://autoload/content.gd").load_json("maps")
