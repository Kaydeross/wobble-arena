extends SceneTree
## Pictures of maps in the offline world (needs a real renderer, opens a window):
##   godot --path godot --resolution 852x393 --script res://tests/map_shots.gd -- --no-save --out DIR [--play] map ...
## Default: the web game's level preview (previewCam: from above and to the side at TT_A0, fog pushed out like
## shot3d) so it can be put next to tools/shoot-maps.js. --play: the in-match camera behind the player instead.
## Saves DIR/godot-maps-<id>.png (--play: godot-maps-<id>-play.png). Used by tools/shoot-godot-maps.sh.
## --thumbs: instead writes the wizard's arena card art, res://ui/map_thumbs/<id>.jpg (a band round the level in the preview,
## 360x92). No ids = every map.

const FRAME := 1.0 / 60.0
const TT_A0 := 0.6

var out_dir := "."
var play := false
var thumbs := false
var ids: Array = []
var k := 0
var world: Node
var frames_left := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i] == "--out" and i + 1 < a.size(): out_dir = a[i + 1]; i += 1
		elif a[i] == "--play": play = true
		elif a[i] == "--thumbs": thumbs = true
		elif not a[i].begins_with("--"): ids.append(a[i])
		i += 1
	process_frame.connect(_next, CONNECT_ONE_SHOT)

func _all_ids() -> Array:
	var out: Array = []
	for id: String in root.get_node("Content").map_ids():
		if id != "test" and id != "pillars": out.append(id)   # Pillars: its pillars come from the (unported) mode
	return out

func _next() -> void:
	if world: world.free(); world = null
	if ids.is_empty(): ids = _all_ids()
	if k >= ids.size():
		quit(0); return
	world = load("res://world/world.tscn").instantiate()
	world.map_id = ids[k]
	world.auto_run = false
	world.bot_count = 3
	world.rng_seed = 777
	world.dyn_choice = "off"
	root.add_child(world)
	world.touch.visible = false
	for n in ["UI", "HUD"]:
		var ui := world.get_node_or_null(n)
		if ui is CanvasItem: (ui as CanvasItem).visible = play
		elif ui is CanvasLayer: (ui as CanvasLayer).visible = play
	if not play: world.set_process(false)     # the preview camera is ours
	if thumbs:
		for v in world.views.values(): v.visible = false
	frames_left = 20
	process_frame.connect(_frame)

func _frame() -> void:
	if play:
		world.tick(FRAME)
	else:
		_preview()
	frames_left -= 1
	if frames_left > 0: return
	process_frame.disconnect(_frame)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("godot-maps-%s%s.png" % [ids[k], "-play" if play else ""])
	var img := root.get_texture().get_image()
	if thumbs:
		var w := int(img.get_width() * 0.66)
		var h := int(w / 3.9)
		img = img.get_region(Rect2i((img.get_width() - w) / 2, int(img.get_height() * 0.56) - h / 2, w, h))
		img.resize(360, 92, Image.INTERPOLATE_LANCZOS)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/map_thumbs"))
		path = ProjectSettings.globalize_path("res://ui/map_thumbs/%s.jpg" % ids[k])
	if thumbs: img.save_jpg(path, 0.85)
	else: img.save_png(path)
	print("SHOT ", path)
	k += 1
	_next.call_deferred()

## previewCam + mapBounds (index.html ~10775): the floor's bounds (solids with bottom <= -1), capped at 90 m.
func _preview() -> void:
	var x0 := 1e9; var x1 := -1e9; var z0 := 1e9; var z1 := -1e9
	for pass_n in 2:
		for s: Dictionary in world.map_node.solids:
			if pass_n == 0 and float(s.bottom) > -1.0: continue
			x0 = minf(x0, s.minX); x1 = maxf(x1, s.maxX); z0 = minf(z0, s.minZ); z1 = maxf(z1, s.maxZ)
		if x0 <= x1: break
	if x0 > x1: x0 = -25; z0 = -25; x1 = 25; z1 = 25
	x1 = minf(x1, x0 + 90); z1 = minf(z1, z0 + 90)
	var cx := (x0 + x1) / 2.0; var cz := (z0 + z1) / 2.0; var r := Vector2(x1 - x0, z1 - z0).length() / 2.0
	var d := r * 1.88 + 13.0
	var cam: Camera3D = world.cam
	cam.fov = 56.0
	cam.look_at_from_position(Vector3(cx + sin(TT_A0) * d, d * 0.46, cz + cos(TT_A0) * d), Vector3(cx, d * 0.07, cz), Vector3.UP)
	var env: Environment = world.env_node.environment
	env.fog_depth_begin = d * 1.6; env.fog_depth_end = d * 6.0
	# the roofs and ceilings come off so you can see inside (shot3d)
	for c in world.map_node.get_children():
		if str(c.name).begins_with("Roof_"): c.visible = false
	for v in world.views.values(): v.visible = not thumbs
