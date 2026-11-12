class_name MapBuilder
extends RefCounted
## Builds a map's visuals from res://data/maps.json (copy of shared/maps.json) and its collision solids.
## Ported from addBox / addLadder / addFloorPad / addBouncePad / loadMap env (public/index.html ~1574-1612, ~7643-7651).
## Everything else the web level shows (trees, rocks, rings, lamps, the far scenery ring, clouds, hills, the void) comes
## from res://data/extra/decor/<map>.bin and the sky / fog / light colours from res://data/extra/map_look.json, both
## exported from the running web game by tools/export-map-decor.js (one merged mesh per material kind: a few draw calls).
## The custom level ('custom', Sandbox) is generated here from its settings like MAPS.custom.build (custom_map()).
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
	var floor_pads: Array = []    ## {size, color}
	var shadow_area := 32.0       ## half-size of the sun's shadow box (maps.json `shadow`)
	var decor_tris := 0           ## triangles of exported web decor (0 = none: native hills and void)
	var box_styles := {}          ## map_look.json `boxes`: restyled collision boxes by index (see _add_boxes)

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
	if map_id == "custom":
		return build_from("custom", custom_map({}))
	var content := _content()
	var map: Dictionary = content.get_map(map_id) if content else _load_maps_file().get(map_id, {})
	if map.is_empty():
		push_error("MapBuilder: unknown map " + map_id)
	if PillarsMap.IDS.has(map_id): map = PillarsMap.complete(map)   # its pillars and spots are not in the web export
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
	root.box_styles = look(map_id).get("boxes", {}) if map_id != "custom" else {}
	_add_boxes(root, geo.get("boxes", []), root.box_styles)
	for fp in geo.get("floorPads", []):
		_add_floor_pad(root, float(fp["size"]), int(fp["color"]))
		root.floor_pads.append(fp)
	for bp in geo.get("bouncePads", []):
		_add_bounce_pad(root, float(bp["x"]), float(bp["z"]))
		root.pads.append(bp)
	for l in geo.get("ladders", []):
		_add_ladder(root, float(l["x"]), float(l["z"]), float(l["nx"]), float(l["nz"]), float(l["y0"]), float(l["y1"]))
		root.ladders.append(l)
	if not _add_decor(root, _decor_id(map_id, map)):
		_add_backdrop(root, map)
	if gfx_q() >= 1:
		_add_cloud_layer(root, look(map_id) if map_id != "custom" else {})
	return root

## Graphics quality from the Tier autoload: 0 LOW (web), 1 MID (phones), 2 HIGH (PC); 2 without the autoload.
## See docs/GRAPHICS.md for what each level turns on.
static func gfx_q() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var t: Node = tree.root.get_node_or_null("Tier") if tree and tree.root else null
	return int(t.call("quality")) if t else 2

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

## Sky, ambient, fog for a map. With the web look (map_look.json, `id` given): the sky bands as a gradient sky with the
## sun disc (or moon and stars at night) and the horizon haze, fog colour / range, hemisphere colours after gradeLook.
## Without it: loadMap ~7647 (background = fog colour = sky, fog [50, 160] unless the map sets `fog`, hemi intensity).
static func make_environment(map: Dictionary, id := "") -> Environment:
	var lk := look(id)
	var sky_c := int(map.get("sky", 0xbfe3f2))
	var top := int(map["skyTop"]) if map.has("skyTop") else mix_hex(sky_c, 0x4a8fe0, 0.62)
	var env_d: Dictionary = map.get("env", {})
	if env_d.has("top"):
		top = int(env_d["top"])
	var env := Environment.new()
	if not lk.is_empty() and bool(lk.get("indoor", false)):
		env.background_mode = Environment.BG_COLOR
		env.background_color = hex(int(lk.get("background", sky_c)))
	else:
		var sky := Sky.new()
		sky.sky_material = sky_material(lk) if not lk.is_empty() else _procedural_sky(top, sky_c, int(map.get("voidColor", sky_c)))
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		sky.process_mode = Sky.PROCESS_MODE_QUALITY if lk.is_empty() else Sky.PROCESS_MODE_INCREMENTAL
		env.background_mode = Environment.BG_SKY
		env.sky = sky
	# HemisphereLight stand-in: a flat ambient between the hemisphere's sky and ground colours
	var hemi := float(map.get("hemi", 0.95))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = hex(0xffffff).lerp(hex(0x9bb7c4), 0.5)
	if lk.has("hemi"):
		var h: Array = lk["hemi"]
		env.ambient_light_color = hex(int(h[1])).lerp(hex(int(h[0])), 0.8)   # mostly the sky colour: floors face up
		hemi = float(h[2])
	# three.js r160 (physically based lights) divides by PI where Godot does not: energy = intensity / PI keeps the same look
	env.ambient_light_energy = hemi / PI
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var fog: Array = map.get("fog", [50, 160])
	var fog_c := sky_c
	if lk.get("fog") is Array:
		fog_c = int(lk["fog"][0]); fog = [lk["fog"][1], lk["fog"][2]]
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = hex(fog_c)
	env.fog_density = 1.0
	env.fog_depth_begin = float(fog[0])
	env.fog_depth_end = float(fog[1])
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	_grade(env, lk)
	return env

## Post and colour grade by tier (docs/GRAPHICS.md). LOW keeps the web game's look (linear tonemap, depth fog only).
## MID / HIGH: filmic tonemap with the exposure lifted back to the web brightness, a gentle per-map grade from
## map_look.json (contrast / saturation, a split tone: shadows toward the hemisphere ground colour, highlights toward
## the sun). Godot's height fog and aerial perspective were tried and dropped: both wash the pastel sky and the
## fog-free far scenery out; the far scenery fades toward the fog colour in its own shader instead (decor_material).
## HIGH adds glow (only HDR pixels bloom: the sun disc, lamps, lava) and SSAO (SSIL was tried: noisy on flat
## colour faces and not worth its cost).
static func _grade(env: Environment, lk: Dictionary) -> void:
	var q := gfx_q()
	if q == 0:
		return
	var night := bool(lk.get("night", false))
	var indoor := bool(lk.get("indoor", false))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.4          # a gentle shoulder: mid-tones stay at the web brightness, highlights roll off
	env.tonemap_exposure = 0.88 if not night else 0.94
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.1 if night else (1.08 if indoor else 1.18)
	var sun_c := hex(int(lk["sun"][0])) if lk.get("sun") is Array else Color(1.0, 0.95, 0.85)
	var gnd_c := hex(int(lk["hemi"][1])) if lk.get("hemi") is Array else Color(0.45, 0.42, 0.4)
	var g := Gradient.new()
	g.set_color(0, Color.BLACK.lerp(gnd_c.darkened(0.5), 0.1))
	g.set_color(1, Color.WHITE)
	g.add_point(0.5, Color(0.5, 0.5, 0.5).lerp(sun_c, 0.07))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 128
	gt.use_hdr = false
	env.adjustment_color_correction = gt
	if q >= 2:
		env.glow_enabled = true
		env.glow_intensity = 0.5
		env.glow_strength = 1.0
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		env.set_glow_level(0, 0.0)
		env.set_glow_level(1, 0.0)
		env.set_glow_level(2, 1.0)
		env.set_glow_level(3, 0.8)
		env.set_glow_level(4, 0.5)
		env.ssao_enabled = true
		env.ssao_radius = 1.3
		env.ssao_intensity = 1.6
		env.ssao_power = 1.5
		env.ssao_detail = 0.5
		env.ssao_horizon = 0.06

static func _procedural_sky(top: int, sky_c: int, void_c: int) -> ProceduralSkyMaterial:
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = hex(top)
	sm.sky_horizon_color = hex(sky_c)
	sm.ground_horizon_color = hex(sky_c)
	sm.ground_bottom_color = hex(void_c)
	sm.sky_curve = 0.12
	sm.ground_curve = 0.05
	sm.sun_angle_max = 8.0
	sm.sun_curve = 0.1
	return sm

## Sun for a map: position (sh*0.7, sh*1.2, sh*0.38) toward the centre, intensity sunI (default 1.35); with the web look
## the colour and intensity gradeLook gives it.
static func setup_sun(sun: DirectionalLight3D, map: Dictionary, id := "") -> void:
	var sh := float(map.get("shadow", 32))
	var p := Vector3(sh * 0.7, sh * 1.2, sh * 0.38)
	sun.transform = Transform3D(Basis.looking_at(-p.normalized(), Vector3.UP), p)
	sun.light_energy = float(map.get("sunI", 1.35)) / PI
	var env_d: Dictionary = map.get("env", {})
	var sc := int(map.get("sunColor", env_d.get("sunColor", 0xffffff)))
	sun.light_color = hex(0xffffff).lerp(hex(sc), 0.35)
	var lk := look(id)
	if lk.get("sun") is Array:
		sun.light_color = hex(int(lk["sun"][0]))
		sun.light_energy = float(lk["sun"][1]) / PI

# ---------------------------------------------------------------- the web look (sky, fog, lights)

const LOOK_PATH := "res://data/extra/map_look.json"
const DECOR_DIR := "res://data/extra/decor/"
static var _look: Dictionary = {}
static var _shaders: Dictionary = {}

## The exported web look of a map ({} = none): indoor, night, bands [[polar angle, colour]], background, fog
## [colour, near, far], hemi [sky, ground, intensity], sun [colour, intensity], sunDir, sunDisc [colour, size],
## haze [colour, opacity], moon [colour, size] or null.
static func look(id: String) -> Dictionary:
	if id == "":
		return {}
	if _look.is_empty() and FileAccess.file_exists(LOOK_PATH):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOK_PATH))
		if v is Dictionary:
			_look = v
	return _look.get(id, {})

static func _lin(c: int) -> Vector3:
	var k := hex(c).srgb_to_linear()
	return Vector3(k.r, k.g, k.b)

## The web sky dome as a sky shader: 12 colour bands by angle from the zenith (blended), the sun disc with two soft
## glows, three layers of horizon haze; at night a moon and a sprinkle of stars instead of the sun. No TIME: Godot only
## redraws the radiance when the material changes.
static func sky_material(lk: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = _shader("sky", SKY_SHADER)
	var bands: Array = lk.get("bands", [])
	var cols := PackedVector3Array()
	var angs := PackedFloat32Array()
	for b in bands:
		angs.append(float(b[0])); cols.append(_lin(int(b[1])))
	while angs.size() < 12:
		angs.append(3.2); cols.append(cols[-1] if cols.size() else Vector3.ONE)
	sm.set_shader_parameter("band_col", cols)
	sm.set_shader_parameter("band_ang", angs)
	sm.set_shader_parameter("below_col", _lin(int(lk.get("background", 0xbfe3f2))))
	var sd: Array = lk.get("sunDir", [0.486, 0.833, 0.264])
	sm.set_shader_parameter("sun_dir", Vector3(float(sd[0]), float(sd[1]), float(sd[2])).normalized())
	var disc: Array = lk.get("sunDisc", [0xfff6d2, 1])
	sm.set_shader_parameter("sun_col", _lin(int(disc[0])))
	sm.set_shader_parameter("sun_size", float(disc[1]))
	var night := bool(lk.get("night", false))
	sm.set_shader_parameter("night", 1.0 if night else 0.0)
	sm.set_shader_parameter("sun_boost", 1.6 if gfx_q() >= 2 else 1.0)   # HIGH: the disc is HDR so it blooms
	if lk.get("moon") is Array:
		sm.set_shader_parameter("moon_col", _lin(int(lk["moon"][0])))
		sm.set_shader_parameter("moon_size", float(lk["moon"][1]) * 1.15)
	if lk.get("haze") is Array:
		sm.set_shader_parameter("haze_col", _lin(int(lk["haze"][0])))
		sm.set_shader_parameter("haze_op", float(lk["haze"][1]))
	return sm

const SKY_SHADER := """
shader_type sky;
uniform vec3 band_col[12];
uniform float band_ang[12];
uniform vec3 below_col;
uniform vec3 sun_dir = vec3(0.49, 0.83, 0.26);
uniform vec3 sun_col = vec3(1.0);
uniform float sun_size = 1.0;
uniform float sun_boost = 1.0;
uniform float night = 0.0;
uniform vec3 moon_col = vec3(0.9);
uniform float moon_size = 1.15;
uniform vec3 haze_col = vec3(0.9);
uniform float haze_op = 0.0;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void sky() {
	vec3 d = normalize(EYEDIR);
	float a = acos(clamp(d.y, -1.0, 1.0));
	vec3 c = band_col[0];
	for (int i = 1; i < 12; i++) {
		float t = clamp((a - band_ang[i - 1]) / max(1e-4, band_ang[i] - band_ang[i - 1]), 0.0, 1.0);
		c = mix(c, band_col[i], t);
	}
	c = mix(c, below_col, smoothstep(2.0, 2.15, a));
	// horizon haze: three see-through cylinders (radius 300) round the camera, tops at about 20, 48 and 76 m
	float e = d.y / max(0.05, length(d.xz));
	for (int i = 0; i < 3; i++) {
		float top = (16.0 + float(i) * 28.0) / 300.0;
		float k = (1.0 - smoothstep(top - 0.01, top + 0.01, e)) * smoothstep(-0.03, -0.01, e);
		c = mix(c, haze_col, k * max(0.0, haze_op - float(i) * 0.06));
	}
	float cs = dot(d, normalize(sun_dir));
	float ang = acos(clamp(cs, -1.0, 1.0));
	if (night < 0.5) {
		float r = atan(19.0 * sun_size / 315.0);
		c = mix(c, sun_col, 0.1 * (1.0 - smoothstep(r * 4.0, r * 5.3, ang)));
		c = mix(c, sun_col, 0.28 * (1.0 - smoothstep(r * 2.2, r * 2.45, ang)));
		c = mix(c, sun_col * sun_boost, 1.0 - smoothstep(r * 0.97, r * 1.03, ang));
	} else {
		float r = atan(15.0 * moon_size / 300.0);
		c = mix(c, moon_col, 0.16 * (1.0 - smoothstep(r * 1.9, r * 2.05, ang)));
		c = mix(c, moon_col, 1.0 - smoothstep(r * 0.97, r * 1.03, ang));
		vec3 g = floor(d * 160.0);
		float h = hash(g);
		vec3 f = fract(d * 160.0) - 0.5;
		float star = step(0.985, h) * (1.0 - smoothstep(0.08, 0.2, length(f))) * step(0.05, d.y);
		c = mix(c, vec3(1.0, 0.97, 0.9), star * 0.85);
	}
	COLOR = c;
}
"""

static func _shader(key: String, code: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var sh := Shader.new()
	sh.code = code
	_shaders[key] = sh
	return sh

# ---------------------------------------------------------------- builders

## Static boxes merged into one mesh per colour (fewer draw calls); each box is still its own solid.
## Roofs (big boxes high up, like the Practice Range ceiling) do not cast shadows, as in the web game (`roof.castShadow = false`).
## `styles` (map_look.json `boxes`, by box index) restyles boxes the way the level's build() does after addBox: hidden
## (invisible walls), op (glass), basic (self-lit), color, emissive / ei, noShadow. `idx[i]` = the index of boxes[i].
static func _add_boxes(root: Node3D, boxes: Array, styles := {}, idx := []) -> void:
	var q := gfx_q()
	var grid := root is MapNode and (root as MapNode).map_id == "practice"
	var groups := {}
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		var st: Dictionary = styles.get(str(idx[i] if i < idx.size() else i), {})
		if st.get("hidden", false):
			continue
		var c := int(st.get("color", b["color"]))
		var key := [c, 0 if _is_roof(b) else 1, JSON.stringify(st)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(b)
	for key: Array in groups:
		var st: Dictionary = JSON.parse_string(key[2])
		var st_tool := SurfaceTool.new()
		st_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		if q == 0 or not (st.is_empty() or _only_keys(st, ["color", "noShadow"])):
			for b in groups[key]:
				var bm := BoxMesh.new()
				bm.size = Vector3(float(b["w"]), float(b["h"]), float(b["d"]))
				st_tool.append_from(bm, 0, Transform3D(Basis(), Vector3(float(b["x"]), float(b["y"]) + float(b["h"]) / 2.0, float(b["z"]))))
		var mi := MeshInstance3D.new()
		mi.name = ("Boxes_%06x" if key[1] == 1 else "Roof_%06x") % key[0]
		var plain := st.is_empty() or (st.keys() == ["noShadow"])
		var shaded := q >= 1 and (plain or _only_keys(st, ["color", "noShadow"]))
		if shaded:
			var faces := SurfaceTool.new()
			faces.begin(Mesh.PRIMITIVE_TRIANGLES)
			for b in groups[key]:
				_append_box(faces, Vector3(float(b["x"]), float(b["y"]) + float(b["h"]) / 2.0, float(b["z"])), Vector3(float(b["w"]), float(b["h"]), float(b["d"])))
			mi.mesh = faces.commit()
			mi.material_override = box_material(key[0], grid and not plain)
		else:
			mi.mesh = st_tool.commit()
			mi.material_override = material(key[0]) if plain else _styled(key[0], st)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key[1] == 1 and not st.get("noShadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

static func _only_keys(d: Dictionary, allowed: Array) -> bool:
	for k in d:
		if not allowed.has(k): return false
	return true

## The stylised box material (MID / HIGH): res://shaders/box.gdshader in one colour, cached. grid = the Practice
## Range's prototype grid.
static func box_material(color: int, grid := false) -> ShaderMaterial:
	var k := "box_%06x_%d" % [color, int(grid)]
	if _materials.has(k):
		return _materials[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/box.gdshader")
	m.set_shader_parameter("albedo", hex(color))
	if grid:
		m.set_shader_parameter("grid", 1.0)
		m.set_shader_parameter("grid_minor", 0.06)
		m.set_shader_parameter("grid_major", 0.11)
	_materials[k] = m
	return m

## One box as 6 faces for box.gdshader: normal, UV = metres along the face (v up on the sides), UV2 = face size.
static func _append_box(st: SurfaceTool, c: Vector3, sz: Vector3) -> void:
	var h := sz / 2.0
	# [normal, origin corner, U axis, V axis, U length, V length]
	var faces := [
		[Vector3.UP, c + Vector3(-h.x, h.y, -h.z), Vector3.RIGHT, Vector3.BACK, sz.x, sz.z],
		[Vector3.DOWN, c + Vector3(-h.x, -h.y, -h.z), Vector3.RIGHT, Vector3.BACK, sz.x, sz.z],
		[Vector3.RIGHT, c + Vector3(h.x, -h.y, -h.z), Vector3.BACK, Vector3.UP, sz.z, sz.y],
		[Vector3.LEFT, c + Vector3(-h.x, -h.y, -h.z), Vector3.BACK, Vector3.UP, sz.z, sz.y],
		[Vector3.BACK, c + Vector3(-h.x, -h.y, h.z), Vector3.RIGHT, Vector3.UP, sz.x, sz.y],
		[Vector3.FORWARD, c + Vector3(-h.x, -h.y, -h.z), Vector3.RIGHT, Vector3.UP, sz.x, sz.y],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var o: Vector3 = f[1]
		var u: Vector3 = f[2]
		var v: Vector3 = f[3]
		var lu: float = f[4]
		var lv: float = f[5]
		var pts := [Vector2(0, 0), Vector2(lu, 0), Vector2(lu, lv), Vector2(0, lv)]
		var flip := u.cross(v).dot(n) > 0.0     # Godot front faces wind clockwise seen from outside
		for tri in [[0, 1, 2], [0, 2, 3]]:
			var order: Array = [tri[0], tri[2], tri[1]] if flip else tri
			for i in order:
				var p: Vector2 = pts[i]
				st.set_normal(n)
				st.set_uv(p)
				st.set_uv2(Vector2(lu, lv))
				st.add_vertex(o + u * p.x + v * p.y)

static func _styled(color: int, st: Dictionary) -> StandardMaterial3D:
	var k := "style_%06x_%s" % [color, JSON.stringify(st)]
	if _materials.has(k):
		return _materials[k]
	var m: StandardMaterial3D = material(color).duplicate()
	if st.has("op"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = float(st["op"])
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if st.get("basic", false):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if st.has("emissive"):
		m.emission_enabled = true
		m.emission = hex(int(st["emissive"]))
		m.emission_energy_multiplier = float(st.get("ei", 1.0))
	_materials[k] = m
	return m

## Dynamic arenas: rebuild the merged box meshes without the boxes in `exclude` (index -> true); the world draws
## those itself (floor tiles, drifting blocks). Collision is not touched here.
static func rebuild_boxes(root: Node3D, boxes: Array, exclude: Dictionary) -> void:
	for c in root.get_children():
		var n := str(c.name)
		if n.begins_with("Boxes_") or n.begins_with("Roof_"):
			root.remove_child(c); c.queue_free()
	var keep: Array = []
	var idx: Array = []
	for i in boxes.size():
		if not exclude.has(i): keep.append(boxes[i]); idx.append(i)
	_add_boxes(root, keep, root.box_styles if root is MapNode else {}, idx)

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

# ---------------------------------------------------------------- web decor (tools/export-map-decor.js)

## Which decor file a map uses: its own, or none for a custom level in a theme other than grass (its hills differ).
static func _decor_id(map_id: String, map: Dictionary) -> String:
	if map_id == "custom":
		return "custom" if str(map.get("theme", "grass")) == "grass" else ""
	return map_id

## Adds the exported decor of `id` as at most four MeshInstance3Ds (shadow casters / the rest, each split into still
## and moving pieces), one surface per material kind. Moving pieces (balloons, ships, turbines, smoke, swaying leaves,
## lava / water) carry their motion per vertex (CUSTOM0-2, tools/export-map-decor.js ANIM) and move in the vertex
## shader, so they cost no script time. Returns false when there is no decor file (native hills and void instead).
static func _add_decor(root: MapNode, id: String) -> bool:
	var d := load_decor(id)
	if d.is_empty():
		return false
	var lk := look(id) if root.map_id != "custom" else look("custom")
	var haze := _lin(int(lk["fog"][0])) if lk.get("fog") is Array else Vector3(0.75, 0.85, 0.9)
	for cast in [true, false]:
		for moving in [false, true]:
			var mesh := ArrayMesh.new()
			for g: Dictionary in d:
				if bool(int(g["shadow"]) & 1) != cast or g.has("anim") != moving:
					continue
				var arr := []
				arr.resize(Mesh.ARRAY_MAX)
				arr[Mesh.ARRAY_VERTEX] = g["pos"]
				arr[Mesh.ARRAY_COLOR] = g["col"]
				if g.has("uv"):
					arr[Mesh.ARRAY_TEX_UV] = g["uv"]
				arr[Mesh.ARRAY_INDEX] = g["idx"]
				var flags := 0
				if moving:
					var a: Array = g["anim"]
					arr[Mesh.ARRAY_CUSTOM0] = a[0]
					arr[Mesh.ARRAY_CUSTOM1] = a[1]
					arr[Mesh.ARRAY_CUSTOM2] = a[2]
					flags = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
				var m := decor_material(int(g["kind"]), bool(g["fog"]), float(g["em"]), bool(int(g["shadow"]) & 2), moving)
				m.set_shader_parameter("haze_col", haze)
				mesh.surface_set_material(mesh.get_surface_count() - 1, m)
			if mesh.get_surface_count() == 0:
				continue
			var mi := MeshInstance3D.new()
			mi.name = ("Decor" if cast else "DecorFar") + ("Moving" if moving else "")
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if moving:   # pieces orbit the level: never cull them by their t = 0 box
				mi.custom_aabb = AABB(Vector3(-700, -120, -700), Vector3(1400, 400, 1400))
			root.add_child(mi)
	root.decor_tris = 0
	for g: Dictionary in d:
		root.decor_tris += (g["idx"] as PackedInt32Array).size() / 3
	return true

## Reads res://data/extra/decor/<id>.bin: [{kind, fog, shadow, op, em, pos, col, uv?, anim?, idx}] ([] if missing or
## bad). anim (groups with shadow bit 2, "WAD2" files) = [CUSTOM0, CUSTOM1, CUSTOM2] as PackedFloat32Arrays.
static func load_decor(id: String) -> Array:
	var path := DECOR_DIR + id + ".bin"
	if id == "" or not FileAccess.file_exists(path):
		return []
	var b := FileAccess.get_file_as_bytes(path)
	var magic := b.slice(0, 4).get_string_from_ascii() if b.size() >= 8 else ""
	if magic != "WAD1" and magic != "WAD2":
		push_error("MapBuilder: bad decor file " + path)
		return []
	var n := b.decode_u32(4)
	var o := 8
	var out: Array = []
	for gi in n:
		var g := {"kind": b[o], "fog": b[o + 1], "shadow": b[o + 2], "op": b[o + 3], "em": b.decode_float(o + 4)}
		var nv := b.decode_u32(o + 8)
		var ni := b.decode_u32(o + 12)
		var mn := Vector3(b.decode_float(o + 16), b.decode_float(o + 20), b.decode_float(o + 24))
		var sz := Vector3(b.decode_float(o + 28), b.decode_float(o + 32), b.decode_float(o + 36)) / 65535.0
		o += 40
		var st := 12 if g["kind"] == 3 else 10
		var pos := PackedVector3Array()
		pos.resize(nv)
		var col := PackedColorArray()
		col.resize(nv)
		var uv := PackedVector2Array()
		if st == 12:
			uv.resize(nv)
		for i in nv:
			var q := o + i * st
			pos[i] = mn + Vector3(b.decode_u16(q), b.decode_u16(q + 2), b.decode_u16(q + 4)) * sz
			col[i] = Color8(b[q + 6], b[q + 7], b[q + 8], b[q + 9])
			if st == 12:
				uv[i] = Vector2(b[q + 10], b[q + 11]) / 255.0
		o += nv * st
		o += (4 - (nv * st) % 4) % 4
		g["pos"] = pos
		g["col"] = col
		if st == 12:
			g["uv"] = uv
		if magic == "WAD2" and (int(g["shadow"]) & 4):
			var f := b.slice(o, o + nv * 48).to_float32_array()
			o += nv * 48
			var cs := [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
			for c in cs: c.resize(nv * 4)
			for i in nv:
				for k in 3:
					for e in 4:
						cs[k][i * 4 + e] = f[i * 12 + k * 4 + e]
			g["anim"] = cs
		g["idx"] = b.slice(o, o + ni * 4).to_int32_array()
		o += ni * 4
		out.append(g)
	return out

## Decor kinds: 0 lit (flat shaded, emission = colour * em: the far scenery glows a little so it never goes muddy),
## 1 unlit, 2 unlit see-through, 3 additive glow (soft radial blob, fake bloom round lamps), 4 lit see-through.
## fog = false for the far scenery, which the web draws without fog (it gets the web's foot-to-top shading, farPatch,
## and on MID / HIGH a little aerial haze toward the fog colour with distance); receive = false: no shadows land on
## it (the void plane, trees). anim: the vertex shader moves the piece (see _add_decor; flags in CUSTOM1.w: 1 far
## leaves, 2 level trees, 3 lava, 4 water). MID / HIGH light lit kinds with the soft cel ramp. One cached material per
## combination.
static func decor_material(kind: int, fog: bool, em: float, receive := true, anim := false) -> ShaderMaterial:
	var q := gfx_q()
	var key := "decor_%d_%d_%d_%d_%d_%.3f" % [kind, int(fog), int(receive), int(anim), q, em]
	if _materials.has(key):
		return _materials[key]
	var modes := ["specular_disabled"]
	match kind:
		0: modes.append_array(["cull_back", "diffuse_lambert"])
		1: modes.append_array(["cull_back", "unshaded"])
		2: modes.append_array(["cull_back", "unshaded", "blend_mix", "depth_draw_never"])
		3: modes.append_array(["cull_disabled", "unshaded", "blend_add", "depth_draw_never"])
		_: modes.append_array(["cull_back", "diffuse_lambert", "blend_mix", "depth_draw_never"])
	if not fog:
		modes.append("fog_disabled")
	if not receive and (kind == 0 or kind == 4):
		modes.append("shadows_disabled")
	var lit := kind == 0 or kind == 4
	var code := "shader_type spatial;\nrender_mode %s;\nuniform float emission = 0.0;\nuniform vec3 haze_col = vec3(0.8);\nuniform float wind = %.1f;\nvarying vec3 wpos;\n" % [", ".join(modes), 1.0 if q >= 1 else 0.0]
	if anim:
		code += DECOR_ANIM_VERTEX
	else:
		code += "void vertex() {\n\twpos = VERTEX;\n}\n"
	code += "void fragment() {\n\tvec3 c = pow(COLOR.rgb, vec3(2.2));\n"
	if lit and not fog:      # web farPatch: darker at the foot, lighter at the top
		code += "\tc *= mix(0.84, 1.07, smoothstep(-30.0, 65.0, wpos.y));\n"
		if q >= 1:
			code += "\tc = mix(c, haze_col, 0.1 * smoothstep(150.0, 380.0, length(wpos.xz)));\n"
	if anim:
		code += DECOR_LIQUID
	if lit:
		code += "\tvec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));\n\tNORMAL = dot(n, VERTEX) > 0.0 ? -n : n;\n\tROUGHNESS = 0.95;\n\tEMISSION = c * emission;\n"
	code += "\tALBEDO = c;\n"
	if kind == 2 or kind == 4:
		code += "\tALPHA = COLOR.a;\n"
	if kind == 3:
		code += "\tfloat r = length(UV - 0.5) * 2.0;\n\tfloat k = r < 0.35 ? mix(1.0, 0.45, r / 0.35) : mix(0.45, 0.0, clamp((r - 0.35) / 0.65, 0.0, 1.0));\n\tALBEDO = c * k * COLOR.a;\n"
	code += "}\n"
	if lit and fog and q >= 1:
		code += SOFT_CEL_LIGHT
	var m := ShaderMaterial.new()
	m.shader = _shader("decor_%d_%d_%d_%d_%d" % [kind, int(fog), int(receive), int(anim), q], code)
	m.set_shader_parameter("emission", em)
	m.render_priority = -1 if kind == 3 else 0
	_materials[key] = m
	return m

## Moving decor (tools/export-map-decor.js ANIM): CUSTOM0 = pivot, CUSTOM1 = angular velocity (rad/s, axis through
## the pivot) + flag, CUSTOM2 = bob vector * sin(bob rate * TIME). Leaves sway like the web's farPatch (far, flag 1)
## or a little round the canopy (level trees, flag 2). Decor vertices are in world space (identity transform).
const DECOR_ANIM_VERTEX := """varying flat float vflag;
void vertex() {
	vec3 v = VERTEX;
	vec3 w = CUSTOM1.xyz;
	float sp = length(w);
	if (sp > 1e-5) {
		vec3 a = w / sp;
		float th = sp * TIME;
		vec3 p = v - CUSTOM0.xyz;
		v = CUSTOM0.xyz + p * cos(th) + cross(a, p) * sin(th) + a * dot(a, p) * (1.0 - cos(th));
	}
	v += CUSTOM2.xyz * sin(CUSTOM2.w * TIME);
	float f = CUSTOM1.w;
	if (f > 0.5 && f < 1.5) {
		float ph = v.x * 0.045 + v.z * 0.045;
		float k = clamp((v.y + 30.0) / 45.0, 0.0, 1.0) * wind;
		v.x += sin(TIME * 1.1 + ph) * 0.6 * k;
		v.z += cos(TIME * 0.85 + ph * 1.3) * 0.4 * k;
	} else if (f > 1.5 && f < 2.5) {
		float ph = CUSTOM0.x * 0.31 + CUSTOM0.z * 0.27;
		float k = clamp((v.y - CUSTOM0.y + 1.5) / 4.0, 0.0, 1.0) * wind;
		v.x += sin(TIME * 1.3 + ph) * 0.1 * k;
		v.z += cos(TIME * 1.05 + ph) * 0.08 * k;
	}
	vflag = f;
	wpos = v;
	VERTEX = v;
}
"""

## Lava (flag 3): slow bright / dark churn, emissive. Water (flag 4): soft moving ripple highlights. Cheap sines only.
const DECOR_LIQUID := """	if (vflag > 2.5 && vflag < 3.5) {
		float n = sin(wpos.x * 0.21 + TIME * 0.6) * sin(wpos.z * 0.19 - TIME * 0.45) + 0.5 * sin((wpos.x - wpos.z) * 0.55 + TIME * 1.3);
		c *= 0.82 + 0.3 * (n * 0.5 + 0.5);
	} else if (vflag > 3.5) {
		float n = sin(wpos.x * 0.35 + TIME * 0.8) + sin(wpos.z * 0.29 - TIME * 0.6) + sin((wpos.x + wpos.z) * 0.6 + TIME * 1.1);
		c = mix(c, c * 1.18 + 0.035, smoothstep(1.6, 2.6, n) * wind);
	}
"""

## Soft cel light for lit shaders (MID / HIGH): a short ramp round the terminator plus a bit of plain lambert.
const SOFT_CEL_LIGHT := """void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ramp = smoothstep(-0.02, 0.32, ndl) * 0.8 + clamp(ndl, 0.0, 1.0) * 0.2;
	DIFFUSE_LIGHT += ramp * ATTENUATION * LIGHT_COLOR / PI;
}
"""

## A slowly drifting flat cloud layer high over the level (MID / HIGH; res://shaders/clouds.gdshader), tinted from
## the map's look: white with a touch of sun and of the horizon colour by day, a few dim grey-blue wisps at night.
static func _add_cloud_layer(root: Node3D, lk: Dictionary) -> void:
	if bool(lk.get("indoor", false)):
		return
	var night := bool(lk.get("night", false))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/clouds.gdshader")
	var sun_c := hex(int(lk["sun"][0])) if lk.get("sun") is Array else Color.WHITE
	var fog_c := hex(int(lk["fog"][0])) if lk.get("fog") is Array else Color(0.75, 0.85, 0.95)
	if night:
		m.set_shader_parameter("col", fog_c.lerp(Color(0.55, 0.6, 0.75), 0.5))
		m.set_shader_parameter("shade", fog_c.lerp(Color(0.2, 0.22, 0.35), 0.5))
		m.set_shader_parameter("opacity", 0.32)
		m.set_shader_parameter("cover", 0.62)
	else:
		m.set_shader_parameter("col", Color.WHITE.lerp(sun_c, 0.15).lerp(fog_c, 0.3))
		m.set_shader_parameter("shade", fog_c.lerp(Color.WHITE, 0.25).darkened(0.08))
		m.set_shader_parameter("opacity", 0.62)
		m.set_shader_parameter("cover", 0.64)
	var pm := PlaneMesh.new()
	pm.size = Vector2(720, 720)
	var mi := MeshInstance3D.new()
	mi.name = "CloudLayer"
	mi.mesh = pm
	mi.material_override = m
	mi.position.y = 78.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

# ---------------------------------------------------------------- the custom level (MAPS.custom, index.html ~1907)

const CUSTOM_THEMES := {
	"grass": {"sky": 0xbfe3f2, "floor": 0x7fd1ae, "a": [0xe9a64f, 0xd98a3d, 0xf2c16b], "b": 0x6f95a8, "hills": [0x8fc9b0, 0x7bb89f, 0xa3d6bd, 0x6fa994]},
	"desert": {"sky": 0xffe2b8, "floor": 0xe6c68a, "a": [0xc98f4f, 0xb9783d, 0xd9a35f], "b": 0x9a7a4a, "hills": [0xe0b070, 0xd09f60, 0xeec080, 0xc0904f]},
	"snow": {"sky": 0xdff3ff, "floor": 0xeaf6ff, "a": [0x9fd3ea, 0x7fb7d1, 0xc4e6f5], "b": 0x7fb7d1, "hills": [0xc9e6f2, 0xb5d8ea, 0xdcf0f8, 0xa7cbe0]},
	"candy": {"sky": 0xffd6ec, "floor": 0xffc2de, "a": [0x8f7bd1, 0xff7fb0, 0x7fd1ff], "b": 0xb2677a, "hills": [0xe8a0c0, 0xd88fb0, 0xf0b5d0, 0xc97fa5]},
	"night": {"sky": 0x1b2040, "floor": 0x3a4170, "a": [0x6a78c9, 0x8f7bd1, 0x4fe0cf], "b": 0x56608f, "hills": [0x2a3060, 0x232a55, 0x30386e, 0x1c2248]},
}
const CUSTOM_DEFAULTS := {"size": 44, "theme": "grass", "obs": 10, "plat": 4, "pads": 3, "walls": 4, "ice": false, "seed": 7}

## The Sandbox level from its settings (cfg.custom: size, theme, obs, plat, pads, walls, ice, seed; optional blocks
## [[x, yBase, z], ...]): the same seeded layout as the web game's MAPS.custom.build, as a maps.json-style entry.
static func custom_map(cfg: Dictionary) -> Dictionary:
	var c := CUSTOM_DEFAULTS.duplicate()
	c.merge(cfg, true)
	var theme := str(c["theme"]) if CUSTOM_THEMES.has(str(c["theme"])) else "grass"
	var th: Dictionary = CUSTOM_THEMES[theme]
	var S := float(c["size"])
	var half := S / 2.0
	var seed := int(c["seed"])
	var rs := [(seed * 2654435761) & Dynamics.U32]
	var rnd := func() -> float:
		rs[0] = (rs[0] + 0x6D2B79F5) & Dynamics.U32
		var t: int = rs[0]
		t = Dynamics.imul(t ^ (t >> 15), t | 1)
		t = (t ^ ((t + Dynamics.imul(t ^ (t >> 7), t | 61)) & Dynamics.U32)) & Dynamics.U32
		return float((t ^ (t >> 14)) & Dynamics.U32) / 4294967296.0
	var boxes: Array = []
	var pads: Array = []
	var floor_pads: Array = []
	var add_box := func(x: float, z: float, w: float, d: float, h: float, color: int, y: float) -> void:
		boxes.append({"x": x, "z": z, "w": w, "d": d, "h": h, "y": y, "color": color})
	add_box.call(0.0, 0.0, S, S, 2.0, int(th["floor"]), -2.0)
	floor_pads.append({"size": S - 4.0, "color": int(th["floor"])})
	var spawns := _ring_pts(6, S * 0.3, 0.4)
	var drops := _ring_pts(10, S * 0.4, 0.15)
	drops.append([0.0, 0.0])
	var keep: Array = spawns + drops + [[0.0, 0.0]]
	var free := func(x: float, z: float, r: float) -> bool:
		for k: Array in keep:
			if Vector2(float(k[0]) - x, float(k[1]) - z).length() <= r: return false
		return true
	var place := func(n: int, fn: Callable, fr: float, edge: float) -> void:
		var i := 0
		var t := 0
		while i < n and t < n * 40:
			var x: float = (rnd.call() * 2.0 - 1.0) * (half - edge)
			var z: float = (rnd.call() * 2.0 - 1.0) * (half - edge)
			if free.call(x, z, fr) and fn.call(x, z): i += 1
			t += 1
	var a: Array = th["a"]
	place.call(int(c["obs"]), func(x: float, z: float) -> bool:
		var w: float = 1.6 + rnd.call() * 3.0
		var h: float = 1.0 + floorf(rnd.call() * 3.0) * 0.9
		var d: float = 1.6 + rnd.call() * 3.0
		add_box.call(x, z, w, d, h, int(a[int(floorf(rnd.call() * 3.0))]), 0.0)
		return true, 4.2, 3.5)
	place.call(int(c["plat"]), func(x: float, z: float) -> bool:
		var w: float = 5.0 + rnd.call() * 3.0
		add_box.call(x, z, w, w, 0.4, int(a[1]), 2.6)
		add_box.call(x + w / 2.0 + 1.1, z, 2.0, 2.0, 1.2, int(a[2]), 0.0)
		add_box.call(x + w / 2.0 + 1.1, z + 2.2, 2.0, 2.0, 2.4, int(a[0]), 0.0)
		return true, 9.5, 9.0)
	place.call(int(c["walls"]), func(x: float, z: float) -> bool:
		var l: float = 6.0 + rnd.call() * 8.0
		if not free.call(x, z, l / 2.0 + 3.0): return false
		if rnd.call() < 0.5: add_box.call(x, z, l, 0.8, 1.4, int(th["b"]), 0.0)
		else: add_box.call(x, z, 0.8, l, 1.4, int(th["b"]), 0.0)
		return true, 4.2, 3.5)
	place.call(int(c["pads"]), func(x: float, z: float) -> bool:
		pads.append({"x": x, "z": z, "r": 1.2, "power": 17})
		return true, 4.2, 3.5)
	for r in c.get("blocks", []):
		add_box.call(float(r[0]), float(r[2]), 2.0, 2.0, 2.0, 0xffe08a, float(r[1]))
	var night := theme == "night"
	var m := {"name": "Build Your Own", "only": "sandbox", "cat": "sandbox", "tags": ["Custom", "Random"], "theme": theme,
		"blurb": "Pick the size, theme, seed and how much stuff goes in.",
		"sky": th["sky"], "voidColor": th["sky"], "hills": th["hills"], "orbit": S * 0.95, "orbitH": S * 0.55,
		"shadow": maxf(30.0, S * 0.75), "wander": S * 0.3, "hemi": 0.55 if night else 0.95, "sunI": 0.6 if night else 1.35,
		"spawns": spawns, "player": spawns[0], "bots": spawns.slice(1), "drops": drops,
		"geometry": {"boxes": boxes, "ladders": [], "bouncePads": pads, "floorPads": floor_pads}}
	if bool(c["ice"]):
		m["grip"] = 0.2
	return m

## ringPts: n points on a circle, rounded to 0.1 like the web game (Math.round, 6.2832).
static func _ring_pts(n: int, r: float, a0 := 0.0) -> Array:
	var out: Array = []
	for i in n:
		var a := a0 + i * 6.2832 / n
		out.append([floorf(cos(a) * r * 10.0 + 0.5) / 10.0, floorf(sin(a) * r * 10.0 + 0.5) / 10.0])
	return out

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
