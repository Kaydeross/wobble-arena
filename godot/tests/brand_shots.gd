extends SceneTree
## Renders the brand images (needs a real renderer, opens a window; tools/shoot-godot-brand.sh):
##   icon : res://icon.png, 1024x1024 opaque app icon: the real Wobbler (with a crown) on a warm yellow-to-orange
##          gradient with soft rays and a vignette (iOS rounds the corners itself).
##   logo : res://ui/brand/launch_logo.png, the two-line WOBBLERS / ARENA logo on transparent (boot splash + iOS
##          launch storyboard, on the #102b35 background colour).
## Also writes review copies to --out DIR: godot-ui-icon-1024.png, godot-ui-icon-60.png (home-screen size, corners
## rounded like iOS), godot-ui-launch.png (the launch screen at iPhone landscape).
##   godot --path godot --resolution 640x480 --script res://tests/brand_shots.gd -- --no-save --out DIR

const ICON := 1024
const LOGO := Vector2i(2048, 1024)
const BG := Color(0.0627, 0.1686, 0.2078)       ## launch background (#102b35)
const WARM_A := Color(1.0, 0.86, 0.4)           ## icon gradient: top-left yellow...
const WARM_B := Color(1.0, 0.52, 0.16)          ## ...to bottom-right orange

var out_dir := ""
var _vp: SubViewport
var _w: Wobbler
var _n := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--out" and k + 1 < a.size(): out_dir = a[k + 1]
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/brand"))
	await _logo()
	await _icon()
	quit(0)

# ---------------- logo ----------------

func _logo() -> void:
	var vp := SubViewport.new()
	vp.size = LOGO
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var logo: Control = load("res://ui/logo.gd").new()
	logo.lines = PackedStringArray(["WOBBLERS", "ARENA"])
	logo.font_size = 290
	vp.add_child(logo)
	logo.size = Vector2(LOGO)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_save(img, "res://ui/brand/launch_logo.png")
	# review copy: the launch screen on an iPhone in landscape (852x393 pt at 3x would be big: show at 1x)
	var shot := Image.create(852, 393, false, Image.FORMAT_RGBA8)
	shot.fill(BG)
	var small: Image = img.duplicate()
	var k := minf(852.0 / LOGO.x, 393.0 / LOGO.y)
	small.resize(int(LOGO.x * k), int(LOGO.y * k), Image.INTERPOLATE_LANCZOS)
	shot.blend_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i((852 - small.get_width()) / 2, (393 - small.get_height()) / 2))
	if out_dir != "": _save(shot, out_dir.path_join("godot-ui-launch.png"))
	vp.queue_free()

# ---------------- icon ----------------

func _icon() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(ICON, ICON)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.93, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.95, 0.88)
	_vp.add_child(key)
	key.look_at_from_position(Vector3(3, 5, 6), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.55
	rim.light_color = Color(1.0, 0.8, 0.55)
	_vp.add_child(rim)
	rim.look_at_from_position(Vector3(-4, 2, -3), Vector3.ZERO, Vector3.UP)
	_w = load("res://actors/wobbler.tscn").instantiate()
	_vp.add_child(_w)
	_w.setup("wobbler", "none", "crown", 0x39b5a8)
	_w.set_weapon(null)
	var st := {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.25, "grounded": true, "aim": Vector3(0.55, -0.7, 0.45)}
	for i in 200:
		_w.apply_state(st)
		_w.animate(1.0 / 60.0)
	var head := _w.head_mesh.global_position
	var cam := Camera3D.new()
	cam.fov = 28.0
	_vp.add_child(cam)
	cam.look_at_from_position(head + Vector3(0.8, 0.45, 3.0), head + Vector3(0.0, 0.06, 0), Vector3.UP)
	cam.current = true
	for i in 6:
		_w.apply_state(st)
		_w.animate(1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var fg := _vp.get_texture().get_image()
	fg.convert(Image.FORMAT_RGBA8)
	var icon := _compose(fg)
	_save(icon, "res://icon.png")
	if out_dir != "":
		_save(icon, out_dir.path_join("godot-ui-icon-1024.png"))
		_save(_home(icon, 60), out_dir.path_join("godot-ui-icon-60.png"))
	_vp.queue_free()

## Gradient + rays + vignette backdrop, a soft shadow from the character's silhouette, then the character.
func _compose(fg: Image) -> Image:
	var img := Image.create(ICON, ICON, false, Image.FORMAT_RGBA8)
	var c := Vector2(ICON * 0.5, ICON * 0.42)
	for y in ICON:
		for x in ICON:
			var u := Vector2(x, y) / ICON
			var col := WARM_A.lerp(WARM_B, clampf((u.x * 0.45 + u.y * 0.9) / 1.2, 0.0, 1.0))
			var d := Vector2(x, y) - c
			var ang := atan2(d.y, d.x)
			var ray := 0.5 + 0.5 * sin(ang * 12.0)
			col = col.lerp(Color(1, 0.97, 0.85), 0.11 * smoothstep(0.55, 0.9, ray) * clampf(1.2 - d.length() / ICON, 0.0, 1.0))
			var r := (u - Vector2(0.5, 0.5)).length() / 0.7071
			col = col.lerp(Color(0.72, 0.24, 0.05), 0.5 * smoothstep(0.45, 1.05, r))
			col.a = 1.0
			img.set_pixel(x, y, col)
	# soft shadow: the silhouette shrunk and blown back up is a cheap blur
	var sh: Image = fg.duplicate()
	sh.resize(48, 48, Image.INTERPOLATE_BILINEAR)
	sh.resize(ICON, ICON, Image.INTERPOLATE_CUBIC)
	var shadow := Image.create(ICON, ICON, false, Image.FORMAT_RGBA8)
	for y in ICON:
		for x in ICON:
			var a := sh.get_pixel(x, y).a
			shadow.set_pixel(x, y, Color(0.45, 0.16, 0.0, clampf(a * 0.55, 0.0, 1.0)))
	img.blend_rect(shadow, Rect2i(0, 0, ICON, ICON), Vector2i(18, 30))
	img.blend_rect(fg, Rect2i(0, 0, ICON, ICON), Vector2i.ZERO)
	img.convert(Image.FORMAT_RGB8)   # no alpha channel: App Store icons must be opaque
	return img

## The icon at home-screen size with iOS-like rounded corners (review only).
func _home(icon: Image, px: int) -> Image:
	var s: Image = icon.duplicate()
	s.resize(px, px, Image.INTERPOLATE_LANCZOS)
	s.convert(Image.FORMAT_RGBA8)
	var rad := px * 0.225
	for y in px:
		for x in px:
			var q := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(q.x, rad, px - rad)
			var cy := clampf(q.y, rad, px - rad)
			var a := clampf(rad - q.distance_to(Vector2(cx, cy)) + 0.5, 0.0, 1.0)
			var p := s.get_pixel(x, y)
			p.a = a
			s.set_pixel(x, y, p)
	return s

func _save(img: Image, path: String) -> void:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var err := img.save_png(p)
	print("SHOT ", p, " ", img.get_size(), " ok" if err == OK else " error %d" % err)
