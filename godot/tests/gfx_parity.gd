extends SceneTree
## Render-tier brightness parity (docs/GRAPHICS.md "Tier parity"). Renders three reference maps on the current tier
## (`-- --tier=pc|mobile|web`, run with the matching --rendering-method; needs a real renderer, opens a window) with
## the same seed and ticks, from two fixed cameras (`wide`: the level from above and to the side, sky included, like
## map_shots.gd's preview but with the map's own fog; `play`: low over the floor like the in-match camera), and
## prints the mean luminance of each frame:
##   PARITY <tier> <map>-<view> <mean luma 0..255>
## tools/test-gfx.js runs it for MID (Mobile) and LOW (Compatibility) and fails when LOW is more than 12 % away from
## MID on any map. `--out DIR` also saves DIR/godot-gfx-parity-<map>-<tier>.png.

const FRAME := 1.0 / 60.0
const MAPS := ["farm", "candy", "moonbase"]
const TICKS := 45
const VIEWS := ["wide", "play"]

var out_dir := ""
var k := 0
var world: Node
var left := 0
var tier_name := ""
var view := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size(): out_dir = a[i + 1]
	tier_name = ["LOW", "MID", "HIGH"][int(root.get_node("Tier").quality())]
	process_frame.connect(_next, CONNECT_ONE_SHOT)

func _next() -> void:
	if world: world.free(); world = null
	if k >= MAPS.size():
		print("PARITY done")
		quit(0); return
	world = load("res://world/world.tscn").instantiate()
	world.map_id = MAPS[k]
	world.auto_run = false
	world.bot_count = 3
	world.rng_seed = 4242
	world.dyn_choice = "off"
	root.add_child(world)
	world.set_process(false)       # the camera is ours: no real-time smoothing that could differ between runs
	world.touch.visible = false
	for n in ["UI", "HUD"]:
		var ui := world.get_node_or_null(n)
		if ui is CanvasItem: (ui as CanvasItem).visible = false
		elif ui is CanvasLayer: (ui as CanvasLayer).visible = false
	left = TICKS
	process_frame.connect(_frame)

func _frame() -> void:
	world.tick(FRAME)
	_camera()
	left -= 1
	if left > 0: return
	process_frame.disconnect(_frame)
	for v in VIEWS.size():
		view = v
		_camera()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		print("PARITY %s %s-%s %.2f" % [tier_name, MAPS[k], VIEWS[v], mean_luma(img)])
		if out_dir != "":
			img.save_png(out_dir.path_join("godot-gfx-parity-%s-%s-%s.png" % [MAPS[k], VIEWS[v], tier_name.to_lower()]))
	view = 0
	k += 1
	_next.call_deferred()

## A fixed view of the level: from above and to the side of the floor's bounds (map_shots.gd _preview).
func _camera() -> void:
	var x0 := 1e9; var x1 := -1e9; var z0 := 1e9; var z1 := -1e9
	for s: Dictionary in world.map_node.solids:
		if float(s.bottom) > -1.0: continue
		x0 = minf(x0, s.minX); x1 = maxf(x1, s.maxX); z0 = minf(z0, s.minZ); z1 = maxf(z1, s.maxZ)
	if x0 > x1: x0 = -25; z0 = -25; x1 = 25; z1 = 25
	x1 = minf(x1, x0 + 90); z1 = minf(z1, z0 + 90)
	var c := Vector3((x0 + x1) / 2.0, 0.0, (z0 + z1) / 2.0)
	var d := Vector2(x1 - x0, z1 - z0).length() / 2.0 * 1.3 + 10.0
	var cam: Camera3D = world.cam
	cam.fov = 60.0
	if view == 0:
		cam.look_at_from_position(c + Vector3(sin(0.6) * d, d * 0.32, cos(0.6) * d), c + Vector3(0, d * 0.08, 0), Vector3.UP)
	else:     # in-match: ~4 m up at the edge of the middle of the level, looking across it a little down
		var r := minf(Vector2(x1 - x0, z1 - z0).length() * 0.22, 14.0)
		cam.look_at_from_position(c + Vector3(sin(2.2) * r, 4.2, cos(2.2) * r), c + Vector3(0, 1.0, 0), Vector3.UP)

## Mean Rec. 709 luma of the displayed (sRGB) pixels, 0..255, on a 4 px grid.
static func mean_luma(img: Image) -> float:
	img.convert(Image.FORMAT_RGB8)
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / maxf(n, 1) * 255.0
